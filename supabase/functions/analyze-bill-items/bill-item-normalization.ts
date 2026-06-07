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
    "Keep receipt line order. For quantity markers such as 1@, 2@, 3@, 4@, @2, @3, @4, x2, x3, x4, ×2, ×3, or Japanese quantity/count markers, set quantity to that literal integer. 1@ means one item, so use null, never 10. 2@ means quantity 2, never 20. 3@ means quantity 3, never 30; 4@ means quantity 4, never 40.",
    "For Costco-style receipts, a line like 3@ or 4@ directly below the product name means the product row quantity is x3 or x4; do not treat the quantity marker as a separate item and never expand it to 30 or 40.",
    "line_type must be purchase for purchased items and discount for standalone bill-level discount/promotion/coupon/voucher lines.",
    "List all purchased line items from this one receipt. Exclude change, cash received, payment method lines, tax-only summary lines, subtotal-only lines, loyalty points, and receipt metadata.",
    "A discount or promotion line directly below a purchased item, especially one starting with ※, -, −, or － or ending with a minus marker like 240-, 900-, 240-E, 800-T, or 800T-, is an item-level discount for the purchase immediately above it.",
    "On Costco and similar receipts, CPN, COUPON, coupon, voucher, member discount, markdown, promotion, promo, OFF, SALE, 値引, 割引, クーポン, ｸｰﾎﾟﾝ, 特売, 割戻, and similar abbreviations can mark coupon or promotion discount lines.",
    "If the coupon/discount line below repeats the same brand, product text, item code, or a strong substring from the row above, attach it to that product row even when the discount amount uses suffix codes such as -T or -E.",
    "For item-level discount lines directly below a purchased item, do not return a separate discount item. Fold the discount into the purchase row: original_amount_minor is the pre-discount row total, discount_amount_minor is positive, and final_amount_minor is original_amount_minor minus discount_amount_minor.",
    "If raw_line_text contains a purchase amount and an attached coupon/CPN amount, never collapse the pair into one negative bill-level discount. For example, product 3000 followed by CPN 500 must become one purchase row with original_amount_minor 3000, discount_amount_minor 500, and final_amount_minor 2500, not a -2500 discount row.",
    "Return a separate line_type discount item only for standalone bill-level discounts that are not clearly attached to the purchase immediately above them.",
    "Discount lines often start with -, −, or －, end with a minus/suffix code like 240-, 240-E, 800-T, or contain Japanese terms such as 値引, 割引, クーポン, ｸｰﾎﾟﾝ, 特売, 割戻, or Vietnamese/English terms such as Giảm giá, Khuyến mãi, Voucher, Coupon, Discount.",
    "Preserve original_name exactly as printed. Keep Japanese, Vietnamese, Latin, punctuation, and abbreviations as seen. Do not translate or romanize original_name.",
    "Do not autocorrect Japanese product text or small kana. For example, if the receipt says ラッフィング, keep ラッフィング and do not change it to ラッピング.",
    "Treat original_name as OCR transcription, not dictionary correction. Katakana brand and product names can be novel, punny, shortened, or non-dictionary words; keep the printed kana even when a more common word looks similar.",
    "Choose translated_name and category_id from the exact printed original_name/raw_line_text, not from an autocorrected or normalized product name. Similar-looking Japanese kana can be different products.",
    "Always translate translated_name fully into the target language when original_name is in a different language from the user's app language. If original_name is already in the target language, translated_name may be null.",
    "translated_name must describe the recognizable product type, size, variant, and purpose in the target language while preserving useful brand names. Do not return only a romanized brand when the product type is common.",
    "For food, alcohol, cosmetics, medicine, baby products, toiletries, household goods, supplements, and paper goods, infer the real product type from common Japanese/Vietnamese/English retail terms and translate that type accurately. Keep brands/product names when useful.",
    "Example for Vietnamese target language: のどごし生 should translate to Bia Nodogoshi Nama, not just Nodogoshi Nama.",
    "Example for Vietnamese target language: DOVE body care/lotion products should translate as a Dove body lotion/body care product, Pampers pants size L products as diapers/pants size L, KLEENEX tissue products as facial tissue/paper towel, and KORI KRILL OIL as krill oil supplement.",
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
  ocrItemLines: string[] = [],
): SanitizedItem | null {
  if (typeof rawItem !== "object" || rawItem === null) return null;
  const raw = rawItem as Record<string, unknown>;
  let originalName = trimmedString(
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
  const rawLineText = rawVisibleLineText(raw);
  originalName = preservePrintedOriginalName(originalName, rawLineText);
  const rawItemText = rawStringText(raw);
  const isDiscount = rawLineType === "discount" ||
    (rawFinalAmount ?? 0) < 0 ||
    /^[-−－]/.test(originalName) ||
    discountMarkerRegex.test(originalName) ||
    discountMarkerRegex.test(rawItemText);
  const literalOCRLineText = bestLiteralOCRLineText(
    rawLineText ?? rawItemText,
    originalName,
    ocrItemLines,
  );
  const effectiveRawLineText = literalOCRLineText ?? rawLineText;
  originalName = preservePrintedOriginalName(
    originalName,
    effectiveRawLineText,
  );

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
  const attachedDiscountCorrection = itemLevelDiscountCorrectionFromVisibleText(
    effectiveRawLineText,
    originalName,
    rawFinalAmount,
  );
  const effectiveIsDiscount = isDiscount && !attachedDiscountCorrection;
  if (attachedDiscountCorrection) {
    originalName = attachedDiscountCorrection.originalName;
  }
  const discountAmount = attachedDiscountCorrection?.discountAmount ??
    rawDiscountAmount ??
    (isDiscount ? Math.abs(rawFinalAmount ?? 0) : 0);
  const finalAmount = attachedDiscountCorrection?.finalAmount ??
    (effectiveIsDiscount
      ? -Math.abs(rawFinalAmount ?? discountAmount)
      : Math.max(0, rawFinalAmount ?? 0));

  const visibleQuantity = quantityFromVisibleMarker(
    effectiveRawLineText ?? rawItemText,
  );
  const rawQuantity = optionalQuantity(
    valueFor(
      raw,
      "quantity",
      "qty",
      "count",
      "quantity_text",
      "quantityText",
    ),
  );
  const item: InternalSanitizedItem = {
    line_id:
      trimmedString(valueFor(raw, "line_id", "lineID", "lineId", "id")) ??
        `line-${index + 1}`,
    original_name: originalName,
    translated_name: trimmedString(
      valueFor(raw, "translated_name", "translatedName", "translation"),
    ),
    line_type: effectiveIsDiscount ? "discount" : "purchase",
    quantity: effectiveIsDiscount
      ? null
      : normalizedQuantity(rawQuantity, visibleQuantity),
    original_amount_minor: effectiveIsDiscount ? null : (
      attachedDiscountCorrection?.originalAmount ??
        originalAmount ??
        (finalAmount > 0 ? finalAmount + discountAmount : null)
    ),
    discount_amount_minor: Math.max(0, discountAmount),
    final_amount_minor: finalAmount,
    category_id: effectiveIsDiscount ? null : optionalID(
      valueFor(raw, "category_id", "categoryID", "categoryId"),
      categoryIDs,
    ),
    confidence: optionalConfidence(valueFor(raw, "confidence", "score")),
    missing_fields: stringArray(
      valueFor(raw, "missing_fields", "missingFields"),
    ),
  };
  item[rawTextSymbol] = `${effectiveRawLineText ?? ""} ${rawItemText}`.trim();
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
const attachedCouponMarkerRegex =
  /\b(?:cpn|coupon|voucher|promo|promotion|markdown|off|sale)\b|クーポン|ｸｰﾎﾟﾝ|値引|割引|特売|割戻/i;

function rawStringText(raw: Record<string, unknown>): string {
  return [
    rawVisibleLineText(raw),
    valueFor(raw, "original_name", "originalName", "name", "item_name"),
    valueFor(raw, "quantity_text", "quantityText"),
    valueFor(raw, "original_amount_minor", "originalAmountMinor"),
    valueFor(raw, "discount_amount_minor", "discountAmountMinor"),
    valueFor(raw, "final_amount_minor", "finalAmountMinor", "amount"),
  ]
    .filter((value): value is string => typeof value === "string")
    .join(" ");
}

function rawVisibleLineText(raw: Record<string, unknown>): string | null {
  return trimmedString(
    valueFor(raw, "raw_line_text", "rawLineText", "line_text", "lineText"),
  );
}

function preservePrintedOriginalName(
  originalName: string,
  rawLineText: string | null,
): string {
  if (!rawLineText || !containsJapaneseKana(originalName)) return originalName;

  const printedName = printedItemNameCandidate(rawLineText);
  if (
    !printedName ||
    printedName === originalName ||
    !containsJapaneseKana(printedName)
  ) {
    return originalName;
  }

  if (printedName.includes(originalName)) return originalName;
  if (originalName.includes(printedName)) return printedName;

  const distanceRatio = levenshteinDistance(printedName, originalName) /
    Math.max(printedName.length, originalName.length);
  return distanceRatio <= 0.25 ? printedName : originalName;
}

function printedItemNameCandidate(rawLineText: string): string | null {
  const candidate = rawLineText
    .replace(/[¥￥]\s*\d[\d,]*/g, " ")
    .replace(
      /(?:^|\s)\d[\d,]*\s*(?:[-−－]\s*[A-Z]?|[A-Z]\s*[-−－])(?=\s|$)/gi,
      " ",
    )
    .replace(/(?:^|\s)\d[\d,]*(?=\s*$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return candidate.length > 0 ? candidate : null;
}

function bestLiteralOCRLineText(
  modelText: string | null,
  originalName: string,
  ocrItemLines: string[],
): string | null {
  const modelName = printedItemNameCandidate(modelText ?? "") ??
    originalName.trim();
  if (!modelName) return null;

  let bestLine: string | null = null;
  let bestScore = 0;
  for (const line of ocrItemLines) {
    const lineName = printedItemNameCandidate(line);
    if (!lineName) continue;
    const score = literalOCRMatchScore(modelName, lineName, modelText ?? "");
    if (score > bestScore) {
      bestLine = line;
      bestScore = score;
    }
  }

  return bestScore >= 0.65 ? bestLine : null;
}

function literalOCRMatchScore(
  modelName: string,
  ocrName: string,
  modelText: string,
): number {
  const left = modelName.normalize("NFKC").toLowerCase();
  const right = ocrName.normalize("NFKC").toLowerCase();
  if (!left || !right) return 0;
  if (left === right || left.includes(right) || right.includes(left)) return 1;
  if (hasStrongSharedToken(`${left} ${modelText}`, right)) return 0.9;

  if (containsJapaneseKana(left) && containsJapaneseKana(right)) {
    const distanceRatio = levenshteinDistance(left, right) /
      Math.max(left.length, right.length);
    if (distanceRatio <= 0.25) return 0.9 - distanceRatio;
  }

  return 0;
}

function itemLevelDiscountCorrectionFromVisibleText(
  rawLineText: string | null,
  originalName: string,
  rawFinalAmount: number | null,
): {
  originalName: string;
  originalAmount: number;
  discountAmount: number;
  finalAmount: number;
} | null {
  if (!rawLineText || rawFinalAmount === null || rawFinalAmount >= 0) {
    return null;
  }

  const normalized = rawLineText.normalize("NFKC");
  if (!attachedCouponMarkerRegex.test(normalized)) return null;

  const visibleAmounts = visibleMinorAmounts(normalized);
  const targetFinalAmount = Math.abs(rawFinalAmount);
  for (const originalAmount of visibleAmounts) {
    for (const discountAmount of visibleAmounts) {
      if (originalAmount <= discountAmount) continue;
      if (originalAmount - discountAmount !== targetFinalAmount) continue;

      const recoveredName = attachedCouponPurchaseName(
        normalized,
        originalName,
      );
      if (!recoveredName) return null;
      return {
        originalName: recoveredName,
        originalAmount,
        discountAmount,
        finalAmount: targetFinalAmount,
      };
    }
  }

  return null;
}

function visibleMinorAmounts(rawLineText: string): number[] {
  const seen = new Set<number>();
  for (const match of rawLineText.matchAll(/\d[\d,]*/g)) {
    const parsed = Number(match[0].replace(/,/g, ""));
    if (Number.isFinite(parsed) && parsed > 0) {
      seen.add(Math.round(parsed));
    }
  }
  return Array.from(seen).sort((left, right) => right - left);
}

function attachedCouponPurchaseName(
  rawLineText: string,
  fallbackName: string,
): string | null {
  const productLine = rawLineText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) =>
      line.length > 0 &&
      !attachedCouponMarkerRegex.test(line) &&
      !/^[-−－※]/.test(line)
    );
  const candidate = printedItemNameCandidate(
    productLine ?? rawLineText.split(attachedCouponMarkerRegex)[0] ?? "",
  );
  const fallback = fallbackName.trim();
  return candidate ?? (fallback.length > 0 ? fallback : null);
}

function containsJapaneseKana(text: string): boolean {
  return /[\u3040-\u30ff]/u.test(text);
}

function levenshteinDistance(left: string, right: string): number {
  const previous = Array.from(
    { length: right.length + 1 },
    (_, index) => index,
  );
  const current = Array.from({ length: right.length + 1 }, () => 0);

  for (let leftIndex = 1; leftIndex <= left.length; leftIndex++) {
    current[0] = leftIndex;
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex++) {
      const cost = left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1;
      current[rightIndex] = Math.min(
        current[rightIndex - 1] + 1,
        previous[rightIndex] + 1,
        previous[rightIndex - 1] + cost,
      );
    }
    previous.splice(0, previous.length, ...current);
  }

  return previous[right.length];
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

function normalizedQuantity(
  rawQuantity: number | null,
  visibleQuantity: number | null,
): number | null {
  if (visibleQuantity !== null) {
    if (visibleQuantity <= 1) return null;
    if (
      rawQuantity === null ||
      rawQuantity === visibleQuantity ||
      rawQuantity === visibleQuantity * 10 &&
        visibleQuantity >= 2 &&
        visibleQuantity <= 4
    ) {
      return visibleQuantity;
    }
  }

  return rawQuantity !== null && rawQuantity > 1 ? rawQuantity : null;
}

function quantityFromVisibleMarker(value: string | null): number | null {
  if (!value) return null;
  const normalized = value.normalize("NFKC");
  const patterns = [
    /(?:^|[^\d])(\d{1,2})\s*@(?:[^\d]|$)/,
    /(?:^|[^\d])@\s*(\d{1,2})(?:[^\d]|$)/,
    /(?:^|[^\d])[x×]\s*(\d{1,2})(?:[^\d]|$)/i,
    /(?:^|[^\d])(\d{1,2})\s*(?:個|点|pcs?|本|袋)(?:[^\d]|$)/i,
  ];

  for (const pattern of patterns) {
    const match = normalized.match(pattern);
    if (!match) continue;
    const parsed = Number(match[1]);
    if (Number.isFinite(parsed)) return Math.round(parsed);
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
