import { createClient } from "npm:@supabase/supabase-js@2";
import {
  geminiModelNames,
  GeminiModelRequestError,
  requestGeminiModelJSON,
} from "./gemini-model-request.ts";
import {
  billItemPromptLines,
  normalizeBillAnalysisItems,
  sanitizeBillItem,
  type SanitizedItem,
} from "./bill-item-normalization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Candidate = {
  id: string;
  name?: string;
  parent_name?: string | null;
  kind_raw_value?: string;
  currency_code?: string;
  institution_display_name?: string | null;
};

type BillItemsRequest = {
  image_base64?: string;
  mime_type?: string;
  locale_identifier?: string;
  time_zone_identifier?: string;
  currency_code?: string;
  target_language_code?: string;
  categories?: Candidate[];
  wallets?: Candidate[];
};

type ReceiptQuota = {
  allowed?: boolean;
  used_count?: number;
  limit_count?: number;
  remaining_count?: number;
  usage_date?: string;
  reset_time_zone?: string;
  retry_after?: string;
};

const itemizedBillResponseSchema = {
  type: "OBJECT",
  properties: {
    merchant_name: { type: "STRING", nullable: true },
    total_minor: { type: "INTEGER", nullable: true },
    currency_code: { type: "STRING", nullable: true },
    occurred_at: { type: "STRING", nullable: true },
    wallet_id: { type: "STRING", nullable: true },
    multiple_bills_detected: { type: "BOOLEAN" },
    confidence: { type: "NUMBER" },
    missing_fields: {
      type: "ARRAY",
      items: { type: "STRING" },
    },
    raw_text: { type: "STRING", nullable: true },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          line_id: { type: "STRING" },
          original_name: { type: "STRING" },
          translated_name: { type: "STRING", nullable: true },
          line_type: { type: "STRING" },
          quantity: { type: "INTEGER", nullable: true },
          original_amount_minor: { type: "INTEGER", nullable: true },
          discount_amount_minor: { type: "INTEGER" },
          final_amount_minor: { type: "INTEGER" },
          category_id: { type: "STRING", nullable: true },
          confidence: { type: "NUMBER" },
          missing_fields: {
            type: "ARRAY",
            items: { type: "STRING" },
          },
        },
        required: [
          "line_id",
          "original_name",
          "translated_name",
          "line_type",
          "quantity",
          "original_amount_minor",
          "discount_amount_minor",
          "final_amount_minor",
          "category_id",
          "confidence",
          "missing_fields",
        ],
        propertyOrdering: [
          "line_id",
          "original_name",
          "translated_name",
          "line_type",
          "quantity",
          "original_amount_minor",
          "discount_amount_minor",
          "final_amount_minor",
          "category_id",
          "confidence",
          "missing_fields",
        ],
      },
    },
  },
  required: [
    "merchant_name",
    "total_minor",
    "currency_code",
    "occurred_at",
    "wallet_id",
    "multiple_bills_detected",
    "confidence",
    "missing_fields",
    "raw_text",
    "items",
  ],
  propertyOrdering: [
    "merchant_name",
    "total_minor",
    "currency_code",
    "occurred_at",
    "wallet_id",
    "multiple_bills_detected",
    "confidence",
    "missing_fields",
    "raw_text",
    "items",
  ],
};

function jsonResponse(
  payload: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function parseLimit(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed) : fallback;
}

function normalizeNumber(value: unknown, fallback: number): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : fallback;
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeQuota(value: unknown): ReceiptQuota {
  const raw = typeof value === "object" && value !== null
    ? value as Record<string, unknown>
    : {};
  const limit = Math.max(0, Math.floor(normalizeNumber(raw.limit_count, 0)));
  const used = Math.max(0, Math.floor(normalizeNumber(raw.used_count, 0)));
  const remaining = Math.max(
    0,
    Math.floor(normalizeNumber(raw.remaining_count, Math.max(limit - used, 0))),
  );

  return {
    allowed: raw.allowed === true,
    used_count: used,
    limit_count: limit,
    remaining_count: remaining,
    usage_date: typeof raw.usage_date === "string" ? raw.usage_date : undefined,
    reset_time_zone: typeof raw.reset_time_zone === "string"
      ? raw.reset_time_zone
      : undefined,
    retry_after: typeof raw.retry_after === "string"
      ? raw.retry_after
      : undefined,
  };
}

function normalizeBase64(value: string): string {
  return value.replace(/^data:[^;]+;base64,/i, "").replace(/\s/g, "");
}

function approximateBase64Bytes(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return Math.floor((value.length * 3) / 4) - padding;
}

function candidateIDSet(candidates: Candidate[]): Set<string> {
  return new Set(candidates.map((candidate) => candidate.id).filter(Boolean));
}

function trimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function valueFor(raw: Record<string, unknown>, ...keys: string[]): unknown {
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(raw, key)) {
      return raw[key];
    }
  }
  return undefined;
}

function optionalID(value: unknown, allowedIDs: Set<string>): string | null {
  const id = trimmedString(value);
  if (!id || !allowedIDs.has(id)) return null;
  return id;
}

function isCashReceiptText(text: string | null): boolean {
  if (!text) return false;
  return /(現金|現計|げんきん|ゲンキン|genkin|cash|tiền mặt|tien mat)/i.test(
    text,
  );
}

function isCashWalletCandidate(wallet: Candidate): boolean {
  const text = [
    wallet.kind_raw_value,
    wallet.name,
    wallet.institution_display_name,
  ].filter((value): value is string => typeof value === "string")
    .join(" ");

  return /(cash|tiền mặt|tien mat|現金|genkin)/i.test(text);
}

function inferredCashWalletIDFromReceiptText(
  rawText: string | null,
  wallets: Candidate[],
  currencyCode?: string,
): string | null {
  if (!isCashReceiptText(rawText)) return null;

  const preferredCurrency = trimmedString(currencyCode)?.toUpperCase();
  const cashWallets = wallets.filter(isCashWalletCandidate);
  const matchingCurrencyWallets = preferredCurrency
    ? cashWallets.filter((wallet) =>
      trimmedString(wallet.currency_code)?.toUpperCase() === preferredCurrency
    )
    : cashWallets;

  if (matchingCurrencyWallets.length === 1) {
    return matchingCurrencyWallets[0].id;
  }
  if (cashWallets.length === 1) {
    return cashWallets[0].id;
  }
  return null;
}

function optionalPositiveMinor(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.round(value);
    return rounded > 0 ? rounded : null;
  }

  if (typeof value === "string") {
    const sanitized = value.replace(/[^0-9-]/g, "");
    const parsed = Number(sanitized);
    return Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed) : null;
  }

  return null;
}

function optionalConfidence(value: unknown): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : 0;
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.min(1, parsed));
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((field) => typeof field === "string")
    .map((field) => field.trim())
    .filter(Boolean);
}

function missingFieldsFor(result: Record<string, unknown>): string[] {
  const modelMissing = stringArray(
    valueFor(result, "missing_fields", "missingFields"),
  );
  const missing = new Set(modelMissing);

  if (!result.merchant_name) missing.add("merchantName");
  if (!result.total_minor) missing.add("totalMinor");
  if (!result.wallet_id) missing.add("walletID");

  return Array.from(missing).sort();
}

function extractModelText(payload: Record<string, unknown>): string {
  const candidates = Array.isArray(payload.candidates)
    ? payload.candidates
    : [];
  const parts = candidates.flatMap((candidate) => {
    const content = typeof candidate === "object" && candidate !== null
      ? (candidate as Record<string, unknown>).content
      : null;
    const rawParts = typeof content === "object" && content !== null
      ? (content as Record<string, unknown>).parts
      : null;
    return Array.isArray(rawParts) ? rawParts : [];
  });

  return parts
    .map((part) =>
      typeof part === "object" && part !== null
        ? (part as Record<string, unknown>).text
        : null
    )
    .filter((text): text is string => typeof text === "string")
    .join("\n")
    .trim();
}

function parseModelJSON(text: string): Record<string, unknown> {
  const trimmed = text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
  try {
    return JSON.parse(trimmed) as Record<string, unknown>;
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1)) as Record<
        string,
        unknown
      >;
    }
    throw new Error("Model response did not contain a JSON object.");
  }
}

function sanitizeAnalysis(
  modelResult: Record<string, unknown>,
  requestPayload: BillItemsRequest,
  quota: ReceiptQuota,
): Record<string, unknown> {
  const categoryIDs = candidateIDSet(requestPayload.categories ?? []);
  const walletIDs = candidateIDSet(requestPayload.wallets ?? []);
  const multipleBillsDetected = valueFor(
    modelResult,
    "multiple_bills_detected",
    "multipleBillsDetected",
  ) === true;
  const totalMinor = optionalPositiveMinor(
    valueFor(modelResult, "total_minor", "totalMinor", "total", "amount"),
  );
  const rawText = trimmedString(
    valueFor(modelResult, "raw_text", "rawText", "ocr_text", "ocrText"),
  )?.slice(0, 12000) ?? null;
  const walletID = optionalID(
    valueFor(modelResult, "wallet_id", "walletID", "walletId"),
    walletIDs,
  ) ??
    inferredCashWalletIDFromReceiptText(
      rawText,
      requestPayload.wallets ?? [],
      requestPayload.currency_code,
    );

  let items = Array.isArray(modelResult.items)
    ? modelResult.items
      .map((item, index) => sanitizeBillItem(item, index, categoryIDs))
      .filter((item): item is SanitizedItem => item !== null)
    : [];

  if (multipleBillsDetected) {
    items = [];
  } else {
    items = normalizeBillAnalysisItems(items, totalMinor);
  }

  const result: Record<string, unknown> = {
    merchant_name: trimmedString(
      valueFor(modelResult, "merchant_name", "merchantName"),
    ),
    total_minor: totalMinor,
    currency_code:
      trimmedString(valueFor(modelResult, "currency_code", "currencyCode"))
        ?.toUpperCase() ??
        trimmedString(requestPayload.currency_code)?.toUpperCase() ?? null,
    occurred_at: trimmedString(
      valueFor(
        modelResult,
        "occurred_at",
        "occurredAt",
        "date",
        "receipt_date",
      ),
    ),
    wallet_id: walletID,
    multiple_bills_detected: multipleBillsDetected,
    confidence: optionalConfidence(
      valueFor(modelResult, "confidence", "score"),
    ),
    raw_text: rawText,
    items,
  };

  const missing = new Set(missingFieldsFor(result));
  if (multipleBillsDetected) missing.add("singleBillImage");
  if (!items.length && !multipleBillsDetected) missing.add("items");
  result.missing_fields = Array.from(missing).sort();
  result.quota = quota;
  return result;
}

function emptyAnalysis(
  requestPayload: BillItemsRequest,
  quota: ReceiptQuota,
  rawText: string | null = null,
): Record<string, unknown> {
  return {
    merchant_name: null,
    total_minor: null,
    currency_code: trimmedString(requestPayload.currency_code)?.toUpperCase() ??
      "JPY",
    occurred_at: null,
    wallet_id: null,
    multiple_bills_detected: false,
    confidence: 0,
    missing_fields: ["items", "merchantName", "totalMinor", "walletID"],
    raw_text: rawText,
    items: [],
    quota,
  };
}

function buildPrompt(payload: BillItemsRequest): string {
  const categories = (payload.categories ?? []).map((category) => ({
    id: category.id,
    name: category.name,
    parent_name: category.parent_name,
    kind_raw_value: category.kind_raw_value,
  }));
  const wallets = (payload.wallets ?? []).map((wallet) => ({
    id: wallet.id,
    name: wallet.name,
    kind_raw_value: wallet.kind_raw_value,
    currency_code: wallet.currency_code,
    institution_display_name: wallet.institution_display_name,
  }));

  return [
    "You analyze one receipt image for a personal finance app.",
    "The image must contain exactly one receipt/bill. If multiple receipts or bills are visible, set multiple_bills_detected to true, return items as an empty array, include singleBillImage in missing_fields, and do not try to merge them.",
    "Return only JSON with snake_case keys: merchant_name, total_minor, currency_code, occurred_at, wallet_id, multiple_bills_detected, confidence, missing_fields, raw_text, items.",
    ...billItemPromptLines(),
    "Never translate, romanize, or localize merchant_name. Preserve the exact script printed on the receipt.",
    "The receipt may be Japanese. Carefully read Japanese store names, dates, totals, item rows, discounts, and tax labels.",
    "The receipt may also be Vietnamese. Carefully read Vietnamese store names, dates, totals, item rows, discounts, and VAT labels.",
    "For Japanese receipts, merchant_name is often near the top and may contain 店, 株式会社, コンビニ, スーパー, レストラン, カフェ, or brand text.",
    "For Vietnamese receipts, merchant_name is often near the top and totals may be labeled Tổng cộng, Tổng thanh toán, Thành tiền, Tiền hàng, Thanh toán, or Khách phải trả.",
    "For Japanese totals, prefer the final customer-paid amount labeled 合計/goukei, 税込合計, お買上計, 総合計, お支払金額, 領収金額, クレジット売上, or PayPay/電子マネー支払. On Costco receipts, the final payable total is the large highlighted amount next to 合計/goukei, not tax lines, points, item count, or per-item subtotals.",
    "If 合計/goukei and 現金/genkin/cash tendered both appear, total_minor must be the 合計/goukei payable amount, not the cash tendered amount.",
    "Do not use お預り, お釣り, 釣銭, 現金, genkin, cash tendered, 内税, 消費税, 小計, 値引, points, item count, or change as total_minor.",
    "Do not use Tiền khách đưa, Tiền thừa, Thuế/VAT, Giảm giá, Tạm tính, điểm, item count, or change as total_minor.",
    "total_minor is the final payable total in minor units. For JPY, minor units are yen.",
    "For purchase rows, original_amount_minor is the original row amount before item-level discount when visible; discount_amount_minor is a positive discount amount applied to that row; final_amount_minor is the amount after row-level discount and tax allocation.",
    "For discount rows, original_amount_minor must be null, discount_amount_minor must be positive, final_amount_minor must be negative, and category_id must be null.",
    "If a discount is printed as a standalone bill-level line that is not clearly attached to a purchase row, keep it as a separate discount record and do not fold it into purchase rows.",
    "Never invent or estimate money values. Do not create per-item discounts or adjust item totals just to make item rows sum to total_minor. If a discount/tax/allocation is not explicitly printed or confidently readable, leave the item amount as read and add the uncertain field to missing_fields.",
    "Set wallet_id only when the receipt explicitly shows a payment method, card brand, card last digits, or wallet name that clearly matches one candidate. If the payment method says 現金, 現計, GENKIN, genkin, cash, CASH, or tiền mặt, choose the candidate whose kind_raw_value is cash or whose name means cash/tiền mặt/現金 for the receipt currency.",
    "If the receipt does not clearly identify the user's wallet, return null for wallet_id.",
    "occurred_at must be machine-readable, not localized display text. If date and time are visible, use yyyy-MM-dd'T'HH:mm:ss±HH:mm with the user's time zone offset. If seconds are not visible, use :00 seconds. If only a date is visible, use yyyy-MM-dd. Use null if unclear.",
    "Japanese dates/times like 2026年5月19日 21時34分, 26/05/19 21:34, 2026/5/19 9:34午後 must be normalized.",
    "Vietnamese dates/times like 19/05/2026 21:34, 19-05-26 9:34 CH, Ngày 19 tháng 5 năm 2026 must be normalized.",
    "category_id and wallet_id must be selected only from the candidate IDs below. Do not invent IDs.",
    "If the image is blurry or incomplete, return null for uncertain fields, confidence 0-0.4, and include missing field names. Do not fail or return prose.",
    "raw_text should include the visible total, payment, coupon, and item-discount lines exactly enough to audit money fields.",
    `User device locale: ${
      payload.locale_identifier ?? "unknown"
    }. User time zone: ${
      payload.time_zone_identifier ?? "Asia/Tokyo"
    }. Preferred currency: ${
      payload.currency_code ?? "JPY"
    }. Target language code: ${
      payload.target_language_code ?? "current app language"
    }.`,
    `Category candidates: ${JSON.stringify(categories)}`,
    `Wallet candidates: ${JSON.stringify(wallets)}`,
  ].join("\n");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ message: "Method not allowed." }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const geminiAPIKey = Deno.env.get("GEMINI_API_KEY");
  const geminiModel = Deno.env.get("GEMINI_RECEIPT_MODEL") ??
    "gemini-2.5-flash";
  const geminiModels = geminiModelNames(
    geminiModel,
    Deno.env.get("GEMINI_RECEIPT_FALLBACK_MODELS"),
  );
  const dailyLimit = 20;
  const maxImageBytes = parseLimit(
    Deno.env.get("MISTIA_RECEIPT_AI_MAX_IMAGE_BYTES"),
    4 * 1024 * 1024,
  );
  const authHeader = request.headers.get("Authorization");

  if (!supabaseURL || !supabaseAnonKey || !geminiAPIKey) {
    return jsonResponse({
      message: "Bill item analysis environment is incomplete.",
    }, 500);
  }

  if (!authHeader) {
    return jsonResponse({ message: "Missing Authorization header." }, 401);
  }

  const userClient = createClient(supabaseURL, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  });

  const {
    data: { user },
    error: getUserError,
  } = await userClient.auth.getUser();

  if (getUserError || !user) {
    return jsonResponse(
      {
        message: getUserError?.message ??
          "Unable to validate the current user.",
      },
      401,
    );
  }

  let payload: BillItemsRequest;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ message: "Invalid JSON body." }, 400);
  }

  const imageBase64 = normalizeBase64(payload.image_base64 ?? "");
  const mimeType = payload.mime_type ?? "image/jpeg";
  const allowedMimeTypes = new Set([
    "image/jpeg",
    "image/png",
    "image/heic",
    "image/heif",
  ]);

  if (!imageBase64) {
    return jsonResponse({ message: "Missing receipt image." }, 400);
  }

  if (!allowedMimeTypes.has(mimeType)) {
    return jsonResponse({ message: "Unsupported image type." }, 415);
  }

  if (!Array.isArray(payload.categories) || payload.categories.length === 0) {
    return jsonResponse({ message: "Missing category candidates." }, 400);
  }

  if (!Array.isArray(payload.wallets) || payload.wallets.length === 0) {
    return jsonResponse({ message: "Missing wallet candidates." }, 400);
  }

  const imageBytes = approximateBase64Bytes(imageBase64);
  if (imageBytes > maxImageBytes) {
    return jsonResponse({ message: "Receipt image is too large." }, 413);
  }

  const { data: quota, error: quotaError } = await userClient.rpc(
    "consume_receipt_ai_scan_quota",
    {
      p_limit: dailyLimit,
    },
  );

  if (quotaError) {
    return jsonResponse({
      message: quotaError.message ?? "Unable to check receipt scan quota.",
    }, 500);
  }

  const quotaPayload = normalizeQuota(quota);
  if (!quotaPayload.allowed) {
    return jsonResponse(
      {
        message:
          "Daily receipt scan limit reached. Try again after the daily reset.",
        quota: quotaPayload,
      },
      429,
    );
  }

  try {
    const geminiResult = await requestGeminiModelJSON({
      apiKey: geminiAPIKey,
      models: geminiModels,
      body: {
        contents: [
          {
            role: "user",
            parts: [
              { text: buildPrompt(payload) },
              {
                inlineData: {
                  mimeType,
                  data: imageBase64,
                },
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: itemizedBillResponseSchema,
        },
      },
    });
    const modelText = extractModelText(geminiResult.body);
    if (!modelText) {
      return jsonResponse(emptyAnalysis(payload, quotaPayload));
    }
    const modelResult = parseModelJSON(modelText);
    return jsonResponse(sanitizeAnalysis(modelResult, payload, quotaPayload));
  } catch (error) {
    if (error instanceof GeminiModelRequestError) {
      return jsonResponse({ message: error.message }, 502);
    }
    return jsonResponse(
      emptyAnalysis(
        payload,
        quotaPayload,
        error instanceof Error ? error.message : String(error),
      ),
    );
  }
});
