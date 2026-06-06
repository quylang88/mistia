export type SanitizedItem = {
  line_id: string;
  original_name: string;
  translated_name: string | null;
  line_type: "purchase" | "discount";
  quantity: number | null;
  original_amount_minor: number | null;
  discount_amount_minor: number;
  final_amount_minor: number;
  category_id: string | null;
  confidence: number;
  missing_fields: string[];
};

const rawTextSymbol = Symbol("rawText");
type InternalSanitizedItem = SanitizedItem & { [rawTextSymbol]?: string };

export function billItemPromptLines(): string[] {
  return [
    "Each item must have snake_case keys: line_id, raw_line_text, original_name, translated_name, line_type, quantity, original_amount_minor, discount_amount_minor, final_amount_minor, category_id, confidence, missing_fields.",
    "raw_line_text must preserve the exact visible receipt text for the item row and any directly attached quantity/coupon/discount row. Include CPN, coupon markers, suffix-minus amounts like 800-, 800-T, 240-E, and Japanese kana exactly as printed.",
    "Keep receipt line order. For quantity markers such as 2@, 3@, 4@, @3, @4, x2, x3, x4, ×2, ×3, or Japanese quantity/count markers, set quantity to that integer. Use null when the receipt shows one item or quantity is unclear.",
    "For Costco-style receipts, a line like 3@ or 4@ directly below the product name means the product row quantity is x3 or x4; do not treat the quantity marker as a separate item.",
    "line_type must be purchase for purchased items and discount for standalone bill-level discount/promotion/coupon/voucher lines.",
    "List all purchased line items from this one receipt. Exclude change, cash received, payment method lines, tax-only summary lines, subtotal-only lines, loyalty points, and receipt metadata.",
    "A discount or promotion line directly below a purchased item, especially one starting with ※, -, −, or － or ending with a minus marker like 240-, 900-, 240-E, 800-T, or 800T-, is an item-level discount for the purchase immediately above it.",
    "On Costco and similar receipts, CPN, COUPON, coupon, voucher, member discount, markdown, promotion, promo, OFF, SALE, 値引, 割引, クーポン, ｸｰﾎﾟﾝ, 特売, 割戻, and similar abbreviations can mark coupon or promotion discount lines.",
    "If the coupon/discount line below repeats the same brand, product text, item code, or a strong substring from the row above, attach it to that product row even when the discount amount uses suffix codes such as -T or -E.",
    "For item-level discount lines directly below a purchased item, do not return a separate discount item. Fold the discount into the purchase row: original_amount_minor is the pre-discount row total, discount_amount_minor is positive, and final_amount_minor is original_amount_minor minus discount_amount_minor.",
    "Return a separate line_type discount item only for standalone bill-level discounts that are not clearly attached to the purchase immediately above them.",
    "Discount lines often start with -, −, or －, end with a minus/suffix code like 240-, 240-E, 800-T, or contain Japanese terms such as 値引, 割引, クーポン, ｸｰﾎﾟﾝ, 特売, 割戻, or Vietnamese/English terms such as Giảm giá, Khuyến mãi, Voucher, Coupon, Discount.",
    "Preserve original_name exactly as printed. Keep Japanese, Vietnamese, Latin, punctuation, and abbreviations as seen. Do not translate or romanize original_name.",
    "Do not autocorrect Japanese product text or small kana. For example, if the receipt says ラッフィング, keep ラッフィング and do not change it to ラッピング.",
    "Choose translated_name and category_id from the exact printed original_name/raw_line_text, not from an autocorrected or normalized product name. Similar-looking Japanese kana can be different products.",
    "Always try to translate original_name into the target language when the item language differs from the app language. Translate by product meaning, not only phonetics.",
    "For food, alcohol, cosmetics, medicine, toiletries, and household goods, infer the real product type from common Japanese/Vietnamese retail terms and translate that type accurately. Keep brands/product names when useful.",
    "Example for Vietnamese target language: のどごし生 should translate to Bia Nodogoshi Nama, not just Nodogoshi Nama.",
    "For cosmetics, translate specific product type accurately, such as lotion, cleanser, sunscreen, serum, mascara, shampoo, conditioner, deodorant, or makeup remover.",
    "Use null for translated_name only when the printed name is already in the target language, is a pure brand/product code, or translation would be effectively identical.",
    "For every purchase item, choose the closest category_id from the candidates using both category name and parent_name. Do not leave category_id null for common retail goods such as clothing, food, drinks, cosmetics, medicine, toiletries, supplements, household goods, or appliances when a reasonable candidate exists.",
    "Use null for category_id only when no candidate is reasonably close. Do not invent IDs.",
  ];
}

export function sanitizeBillItem(
  rawItem: unknown,
  index: number,
  categoryIDs: Set<string>,
): SanitizedItem | null {
  if (typeof rawItem !== "object" || rawItem === null) return null;
  const raw = rawItem as Record<string, unknown>;
  const originalName = trimmedString(
    valueFor(
      raw,
      "original_name",
      "originalName",
      "name",
      "item_name",
      "itemName",
    ),
  ) ?? "";
  const rawLineType = trimmedString(
    valueFor(raw, "line_type", "lineType", "type"),
  )?.toLowerCase();
  const rawFinalAmount = optionalMinor(
    valueFor(
      raw,
      "final_amount_minor",
      "finalAmountMinor",
      "amount_minor",
      "amountMinor",
      "amount",
    ),
  );
  const rawItemText = rawStringText(raw);
  const isDiscount = rawLineType === "discount" ||
    (rawFinalAmount ?? 0) < 0 ||
    /^[-−－]/.test(originalName) ||
    discountMarkerRegex.test(originalName) ||
    discountMarkerRegex.test(rawItemText);

  if (rawFinalAmount === null && !originalName) return null;

  const originalAmount = optionalPositiveMinor(
    valueFor(
      raw,
      "original_amount_minor",
      "originalAmountMinor",
      "gross_amount_minor",
      "grossAmountMinor",
      "original_amount",
      "originalAmount",
    ),
  );
  const rawDiscountAmount = optionalPositiveMinor(
    valueFor(
      raw,
      "discount_amount_minor",
      "discountAmountMinor",
      "discount_minor",
      "discountMinor",
      "discount_amount",
      "discountAmount",
    ),
  );
  const discountAmount = rawDiscountAmount ??
    (isDiscount ? Math.abs(rawFinalAmount ?? 0) : 0);
  const finalAmount = isDiscount
    ? -Math.abs(rawFinalAmount ?? discountAmount)
    : Math.max(0, rawFinalAmount ?? 0);

  const item: InternalSanitizedItem = {
    line_id:
      trimmedString(valueFor(raw, "line_id", "lineID", "lineId", "id")) ??
        `line-${index + 1}`,
    original_name: originalName,
    translated_name: trimmedString(
      valueFor(raw, "translated_name", "translatedName", "translation"),
    ),
    line_type: isDiscount ? "discount" : "purchase",
    quantity: isDiscount ? null : optionalQuantity(
      valueFor(
        raw,
        "quantity",
        "qty",
        "count",
        "quantity_text",
        "quantityText",
      ),
    ),
    original_amount_minor: isDiscount ? null : (originalAmount ??
      (finalAmount > 0 ? finalAmount + discountAmount : null)),
    discount_amount_minor: Math.max(0, discountAmount),
    final_amount_minor: finalAmount,
    category_id: isDiscount ? null : optionalID(
      valueFor(raw, "category_id", "categoryID", "categoryId"),
      categoryIDs,
    ),
    confidence: optionalConfidence(valueFor(raw, "confidence", "score")),
    missing_fields: stringArray(
      valueFor(raw, "missing_fields", "missingFields"),
    ),
  };
  item[rawTextSymbol] = rawItemText;
  item.missing_fields = itemMissingFieldsFor(item);
  return item;
}

export function normalizeBillItems(items: SanitizedItem[]): SanitizedItem[] {
  const normalized: InternalSanitizedItem[] = [];

  for (const item of items) {
    const previous = normalized[normalized.length - 1];
    if (
      shouldFoldIntoPreviousPurchase(item as InternalSanitizedItem, previous)
    ) {
      const discountAmount = Math.max(
        item.discount_amount_minor,
        Math.abs(item.final_amount_minor),
      );
      previous.discount_amount_minor += discountAmount;
      previous.original_amount_minor = previous.original_amount_minor ??
        previous.final_amount_minor + discountAmount;
      previous.final_amount_minor = Math.max(
        0,
        previous.final_amount_minor - discountAmount,
      );
      previous.missing_fields = itemMissingFieldsFor(previous);
      continue;
    }
    normalized.push(item as InternalSanitizedItem);
  }

  return normalized.map(stripInternalFields);
}

export function normalizeBillAnalysisItems(
  items: SanitizedItem[],
  _totalMinor: number | null,
): SanitizedItem[] {
  return normalizeBillItems(items);
}

function shouldFoldIntoPreviousPurchase(
  item: InternalSanitizedItem,
  previous: InternalSanitizedItem | undefined,
): previous is InternalSanitizedItem {
  if (!previous || previous.line_type !== "purchase") return false;
  if (item.line_type !== "discount") return false;
  if (item.final_amount_minor >= 0 && item.discount_amount_minor <= 0) {
    return false;
  }
  return hasAttachedDiscountSignal(item, previous);
}

function itemMissingFieldsFor(item: SanitizedItem): string[] {
  const missing = new Set(item.missing_fields);
  if (!item.original_name) missing.add("originalName");
  const hasExplicitFullDiscount = item.line_type === "purchase" &&
    (item.original_amount_minor ?? 0) > 0 &&
    item.discount_amount_minor >= (item.original_amount_minor ?? 0);
  if (
    item.line_type === "purchase" && item.final_amount_minor <= 0 &&
    !hasExplicitFullDiscount
  ) {
    missing.add("finalAmountMinor");
  }
  if (item.line_type === "purchase" && !item.category_id) {
    missing.add("categoryID");
  }
  return Array.from(missing).sort();
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

const discountMarkerRegex =
  /(値引|割引|クーポン|ｸｰﾎﾟﾝ|割戻|特売|特価|値下|cpn|coupon|voucher|discount|promo|promotion|markdown|off|sale|giảm giá|khuyến mãi|khuyen mai|(?:^|\s)\d[\d,]*\s*(?:[-−－]\s*[A-ZＡ-Ｚ]?|[A-ZＡ-Ｚ]\s*[-−－])(?:\s|$))/i;

function rawStringText(raw: Record<string, unknown>): string {
  return [
    valueFor(raw, "raw_line_text", "rawLineText", "line_text", "lineText"),
    valueFor(raw, "original_name", "originalName", "name", "item_name"),
    valueFor(raw, "quantity_text", "quantityText"),
    valueFor(raw, "original_amount_minor", "originalAmountMinor"),
    valueFor(raw, "discount_amount_minor", "discountAmountMinor"),
    valueFor(raw, "final_amount_minor", "finalAmountMinor", "amount"),
  ]
    .filter((value): value is string => typeof value === "string")
    .join(" ");
}

function stripInternalFields(item: InternalSanitizedItem): SanitizedItem {
  const { [rawTextSymbol]: _rawText, ...publicItem } = item;
  return publicItem;
}

function hasAttachedDiscountSignal(
  item: InternalSanitizedItem,
  previous: InternalSanitizedItem,
): boolean {
  const discountText = `${item.original_name} ${item[rawTextSymbol] ?? ""}`;
  const previousText = `${previous.original_name} ${
    previous[rawTextSymbol] ?? ""
  }`;

  if (hasStrongSharedToken(discountText, previousText)) return true;

  const discountName = item.original_name.trim();
  const isAnonymousDiscountLine = /^[-−－※]/.test(discountName) ||
    /^(cpn|coupon|voucher|discount|promo|promotion|off|sale|値引|割引|クーポン|ｸｰﾎﾟﾝ|特売|割戻)$/i
      .test(discountName);
  const hasDiscountAmountSignal = item.final_amount_minor < 0 ||
    item.discount_amount_minor > 0 ||
    /(?:^|\s)\d[\d,]*\s*(?:[-−－]\s*[A-ZＡ-Ｚ]?|[A-ZＡ-Ｚ]\s*[-−－])(?:\s|$)/
      .test(discountText);

  return isAnonymousDiscountLine && hasDiscountAmountSignal;
}

function hasStrongSharedToken(left: string, right: string): boolean {
  const rightTokens = new Set(significantTokens(right));
  return significantTokens(left).some((token) => rightTokens.has(token));
}

function significantTokens(text: string): string[] {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .split(/[^\p{Letter}\p{Number}]+/u)
    .map((token) => token.trim())
    .filter((token) =>
      token.length >= 4 &&
      !discountOnlyTokens.has(token) &&
      !/^\d+$/.test(token)
    );
}

const discountOnlyTokens = new Set([
  "cpn",
  "coupon",
  "voucher",
  "discount",
  "promo",
  "promotion",
  "markdown",
  "sale",
  "off",
  "値引",
  "割引",
  "クーポン",
  "特売",
  "割戻",
]);

function optionalID(value: unknown, allowedIDs: Set<string>): string | null {
  const id = trimmedString(value);
  if (!id || !allowedIDs.has(id)) return null;
  return id;
}

function optionalPositiveMinor(value: unknown): number | null {
  const minor = optionalMinor(value);
  return minor !== null && minor > 0 ? minor : null;
}

function optionalMinor(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }

  if (typeof value === "string") {
    const trimmed = value.trim();
    const hasNegativePrefix = /^[-−－]/.test(trimmed);
    const hasNegativeSuffix = /[-−－]\s*[A-ZＡ-Ｚ]?\s*$/i.test(trimmed) ||
      /[A-ZＡ-Ｚ]\s*[-−－]\s*$/i.test(trimmed);
    const digits = trimmed.replace(/[^0-9]/g, "");
    if (!digits) return null;
    const parsed = Number(digits);
    if (!Number.isFinite(parsed)) return null;
    const amount = Math.round(parsed);
    return hasNegativePrefix || hasNegativeSuffix ? -amount : amount;
  }

  return null;
}

function optionalQuantity(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.round(value);
    return rounded > 1 ? rounded : null;
  }

  if (typeof value === "string") {
    const match = value.match(
      /(?:x|×|@)?\s*(\d{1,2})\s*(?:@|個|点|pcs?|本|袋|x|×)?/i,
    );
    if (!match) return null;
    const parsed = Number(match[1]);
    return Number.isFinite(parsed) && parsed > 1 ? Math.round(parsed) : null;
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
