import { createClient } from "npm:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

type Candidate = {
  id: string
  name?: string
  parent_name?: string | null
  kind_raw_value?: string
  currency_code?: string
  institution_display_name?: string | null
}

type ReceiptRequest = {
  image_base64?: string
  mime_type?: string
  locale_identifier?: string
  currency_code?: string
  categories?: Candidate[]
  wallets?: Candidate[]
}

type ReceiptQuota = {
  allowed?: boolean
  used_count?: number
  limit_count?: number
  remaining_count?: number
  usage_date?: string
  reset_time_zone?: string
  retry_after?: string
}

function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  })
}

function parseLimit(value: string | undefined, fallback: number): number {
  const parsed = Number(value)
  return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed) : fallback
}

function normalizeNumber(value: unknown, fallback: number): number {
  const parsed = typeof value === "number" ? value : typeof value === "string" ? Number(value) : fallback
  return Number.isFinite(parsed) ? parsed : fallback
}

function normalizeQuota(value: unknown): ReceiptQuota {
  const raw = typeof value === "object" && value !== null ? value as Record<string, unknown> : {}
  const limit = Math.max(0, Math.floor(normalizeNumber(raw.limit_count, 0)))
  const used = Math.max(0, Math.floor(normalizeNumber(raw.used_count, 0)))
  const remaining = Math.max(0, Math.floor(normalizeNumber(raw.remaining_count, Math.max(limit - used, 0))))

  return {
    allowed: raw.allowed === true,
    used_count: used,
    limit_count: limit,
    remaining_count: remaining,
    usage_date: typeof raw.usage_date === "string" ? raw.usage_date : undefined,
    reset_time_zone: typeof raw.reset_time_zone === "string" ? raw.reset_time_zone : undefined,
    retry_after: typeof raw.retry_after === "string" ? raw.retry_after : undefined,
  }
}

function normalizeBase64(value: string): string {
  return value.replace(/^data:[^;]+;base64,/i, "").replace(/\s/g, "")
}

function approximateBase64Bytes(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0
  return Math.floor((value.length * 3) / 4) - padding
}

function candidateIDSet(candidates: Candidate[]): Set<string> {
  return new Set(candidates.map((candidate) => candidate.id).filter(Boolean))
}

function trimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function optionalID(value: unknown, allowedIDs: Set<string>): string | null {
  const id = trimmedString(value)
  if (!id || !allowedIDs.has(id)) return null
  return id
}

function optionalTotalMinor(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.round(value)
    return rounded > 0 ? rounded : null
  }

  if (typeof value === "string") {
    const sanitized = value.replace(/[^0-9-]/g, "")
    const parsed = Number(sanitized)
    return Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed) : null
  }

  return null
}

function optionalConfidence(value: unknown): number {
  const parsed = typeof value === "number" ? value : typeof value === "string" ? Number(value) : 0
  if (!Number.isFinite(parsed)) return 0
  return Math.max(0, Math.min(1, parsed))
}

function missingFieldsFor(result: Record<string, unknown>): string[] {
  const modelMissing = Array.isArray(result.missing_fields)
    ? result.missing_fields
        .filter((field) => typeof field === "string")
        .map((field) => field.trim())
        .filter(Boolean)
    : []
  const missing = new Set(modelMissing)

  if (!result.merchant_name) missing.add("merchantName")
  if (!result.total_minor) missing.add("totalMinor")
  if (!result.category_id) missing.add("categoryID")
  if (!result.wallet_id) missing.add("walletID")

  return Array.from(missing).sort()
}

function extractModelText(payload: Record<string, unknown>): string {
  const candidates = Array.isArray(payload.candidates) ? payload.candidates : []
  const parts = candidates.flatMap((candidate) => {
    const content = typeof candidate === "object" && candidate !== null
      ? (candidate as Record<string, unknown>).content
      : null
    const rawParts = typeof content === "object" && content !== null
      ? (content as Record<string, unknown>).parts
      : null
    return Array.isArray(rawParts) ? rawParts : []
  })

  return parts
    .map((part) => typeof part === "object" && part !== null ? (part as Record<string, unknown>).text : null)
    .filter((text): text is string => typeof text === "string")
    .join("\n")
    .trim()
}

function parseModelJSON(text: string): Record<string, unknown> {
  const trimmed = text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim()
  return JSON.parse(trimmed) as Record<string, unknown>
}

function sanitizeAnalysis(
  modelResult: Record<string, unknown>,
  requestPayload: ReceiptRequest,
  quota: ReceiptQuota
): Record<string, unknown> {
  const categoryIDs = candidateIDSet(requestPayload.categories ?? [])
  const walletIDs = candidateIDSet(requestPayload.wallets ?? [])
  const result: Record<string, unknown> = {
    merchant_name: trimmedString(modelResult.merchant_name),
    total_minor: optionalTotalMinor(modelResult.total_minor),
    currency_code: trimmedString(modelResult.currency_code)?.toUpperCase() ?? trimmedString(requestPayload.currency_code)?.toUpperCase() ?? null,
    occurred_at: trimmedString(modelResult.occurred_at),
    category_id: optionalID(modelResult.category_id, categoryIDs),
    wallet_id: optionalID(modelResult.wallet_id, walletIDs),
    confidence: optionalConfidence(modelResult.confidence),
    raw_text: trimmedString(modelResult.raw_text)?.slice(0, 12000) ?? null,
  }

  result.missing_fields = missingFieldsFor(result)
  result.quota = quota
  return result
}

function buildPrompt(payload: ReceiptRequest): string {
  const categories = (payload.categories ?? []).map((category) => ({
    id: category.id,
    name: category.name,
    parent_name: category.parent_name,
    kind_raw_value: category.kind_raw_value,
  }))
  const wallets = (payload.wallets ?? []).map((wallet) => ({
    id: wallet.id,
    name: wallet.name,
    kind_raw_value: wallet.kind_raw_value,
    currency_code: wallet.currency_code,
    institution_display_name: wallet.institution_display_name,
  }))

  return [
    "You analyze a receipt image for a personal finance app.",
    "Return only JSON with snake_case keys: merchant_name, total_minor, currency_code, occurred_at, category_id, wallet_id, confidence, missing_fields, raw_text.",
    "merchant_name must be the store or merchant name, not a generic item name.",
    "total_minor is the final payable total in minor units. For JPY, minor units are yen.",
    "occurred_at must be ISO 8601 or yyyy-MM-dd if a receipt date is visible. Use null if unclear.",
    "category_id and wallet_id must be selected only from the candidate IDs below. Return null if there is not a confident match.",
    "Do not invent IDs, wallets, categories, dates, or totals.",
    `Locale: ${payload.locale_identifier ?? "unknown"}. Preferred currency: ${payload.currency_code ?? "JPY"}.`,
    `Category candidates: ${JSON.stringify(categories)}`,
    `Wallet candidates: ${JSON.stringify(wallets)}`,
  ].join("\n")
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return jsonResponse({ message: "Method not allowed." }, 405)
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL")
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")
  const geminiAPIKey = Deno.env.get("GEMINI_API_KEY")
  const geminiModel = Deno.env.get("GEMINI_RECEIPT_MODEL") ?? "gemini-2.5-flash"
  const dailyLimit = 20
  const maxImageBytes = parseLimit(Deno.env.get("MISTIA_RECEIPT_AI_MAX_IMAGE_BYTES"), 4 * 1024 * 1024)
  const authHeader = request.headers.get("Authorization")

  if (!supabaseURL || !supabaseAnonKey || !geminiAPIKey) {
    return jsonResponse({ message: "Receipt analysis environment is incomplete." }, 500)
  }

  if (!authHeader) {
    return jsonResponse({ message: "Missing Authorization header." }, 401)
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
  })

  const {
    data: { user },
    error: getUserError,
  } = await userClient.auth.getUser()

  if (getUserError || !user) {
    return jsonResponse(
      { message: getUserError?.message ?? "Unable to validate the current user." },
      401
    )
  }

  let payload: ReceiptRequest
  try {
    payload = await request.json()
  } catch {
    return jsonResponse({ message: "Invalid JSON body." }, 400)
  }

  const imageBase64 = normalizeBase64(payload.image_base64 ?? "")
  const mimeType = payload.mime_type ?? "image/jpeg"
  const allowedMimeTypes = new Set(["image/jpeg", "image/png", "image/heic", "image/heif"])

  if (!imageBase64) {
    return jsonResponse({ message: "Missing receipt image." }, 400)
  }

  if (!allowedMimeTypes.has(mimeType)) {
    return jsonResponse({ message: "Unsupported image type." }, 415)
  }

  if (!Array.isArray(payload.categories) || payload.categories.length === 0) {
    return jsonResponse({ message: "Missing category candidates." }, 400)
  }

  const imageBytes = approximateBase64Bytes(imageBase64)
  if (imageBytes > maxImageBytes) {
    return jsonResponse({ message: "Receipt image is too large." }, 413)
  }

  const { data: quota, error: quotaError } = await userClient.rpc("consume_receipt_ai_scan_quota", {
    p_limit: dailyLimit,
  })

  if (quotaError) {
    return jsonResponse({ message: quotaError.message ?? "Unable to check receipt scan quota." }, 500)
  }

  const quotaPayload = normalizeQuota(quota)
  if (!quotaPayload.allowed) {
    return jsonResponse(
      {
        message: "Daily receipt scan limit reached. Try again after the daily reset.",
        quota: quotaPayload,
      },
      429
    )
  }

  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${geminiAPIKey}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
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
        },
      }),
    }
  )

  const geminiBody = await geminiResponse.json().catch(() => ({}))
  if (!geminiResponse.ok) {
    const message = typeof geminiBody.error === "object" && geminiBody.error !== null
      ? (geminiBody.error as Record<string, unknown>).message
      : null
    return jsonResponse(
      { message: typeof message === "string" ? message : "Gemini receipt analysis failed." },
      502
    )
  }

  try {
    const modelText = extractModelText(geminiBody as Record<string, unknown>)
    const modelResult = parseModelJSON(modelText)
    return jsonResponse(sanitizeAnalysis(modelResult, payload, quotaPayload))
  } catch (error) {
    return jsonResponse(
      {
        message: "Gemini returned an invalid receipt analysis response.",
        detail: error instanceof Error ? error.message : String(error),
      },
      502
    )
  }
})
