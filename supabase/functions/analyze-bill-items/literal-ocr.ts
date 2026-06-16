export type ReceiptOCRContext = {
  raw_text: string | null;
  item_lines: string[];
  uncertain_lines: string[];
};

export const receiptOCRResponseSchema = {
  type: "OBJECT",
  properties: {
    raw_text: { type: "STRING", nullable: true },
    item_lines: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          line_text: { type: "STRING" },
          confidence: { type: "NUMBER" },
          uncertain_fragments: {
            type: "ARRAY",
            items: { type: "STRING" },
          },
          alternatives: {
            type: "ARRAY",
            items: { type: "STRING" },
          },
        },
        required: [
          "line_text",
          "confidence",
          "uncertain_fragments",
          "alternatives",
        ],
        propertyOrdering: [
          "line_text",
          "confidence",
          "uncertain_fragments",
          "alternatives",
        ],
      },
    },
  },
  required: ["raw_text", "item_lines"],
  propertyOrdering: ["raw_text", "item_lines"],
};

export function buildReceiptOCRPrompt(): string {
  return [
    "OCR this receipt image literally before any analysis.",
    "Return only JSON with snake_case keys: raw_text and item_lines.",
    "This is transcription, not translation and not dictionary correction.",
    "Copy visible Japanese kana, Latin letters, numbers, punctuation, coupon markers, and suffix-minus amounts exactly as printed.",
    "Mentally zoom/crop each item row before writing it. If a character is not clear, keep the closest visible character, add that fragment to uncertain_fragments, and list alternatives; do not replace it with a more common word.",
    "For katakana brand/product names, never normalize or autocorrect similar kana. カウ is not カワ. ラッフィング is not ラッピング. フィ is not ピ.",
    "Keep one item or discount row per item_lines entry in top-to-bottom receipt order. Include item rows, quantity rows, coupon/CPN rows, and discount rows.",
    "Do not infer missing product names from context. Do not choose a Japanese dictionary word just because it is common.",
  ].join("\n");
}

export function sanitizeReceiptOCRResult(
  rawResult: unknown,
): ReceiptOCRContext {
  const raw = typeof rawResult === "object" && rawResult !== null
    ? rawResult as Record<string, unknown>
    : {};
  const rawText = trimmedString(valueFor(raw, "raw_text", "rawText"));
  const lines = Array.isArray(raw.item_lines) ? raw.item_lines : [];
  const itemLines: string[] = [];
  const uncertainLines: string[] = [];

  for (const rawLine of lines) {
    const line = sanitizeOCRLine(rawLine);
    if (!line) continue;
    itemLines.push(line.line_text);
    if (line.is_uncertain) {
      uncertainLines.push(line.line_text);
    }
  }

  return {
    raw_text: rawText,
    item_lines: itemLines.slice(0, 160),
    uncertain_lines: uncertainLines.slice(0, 80),
  };
}

export function ocrContextPromptLines(context: ReceiptOCRContext): string[] {
  const itemLines = context.item_lines.slice(0, 160);
  const uncertainLines = context.uncertain_lines.slice(0, 80);

  return [
    "OCR-first transcript below is the source of truth for item original_name/raw_line_text. Use the image only to verify or fill fields that are absent from the transcript.",
    "Copy item original_name from OCR item lines exactly after removing only visible amount/quantity/coupon markers. Do not autocorrect kana or replace uncommon brand text with a common dictionary word.",
    "If a kana fragment is uncertain, keep raw_line_text faithful, set confidence lower, add originalName to missing_fields, and do not guess between similar kana such as カウ/カワ, フィ/ピ, シ/ツ, ン/ソ.",
    `OCR raw_text: ${context.raw_text ?? ""}`,
    `OCR item_lines: ${JSON.stringify(itemLines)}`,
    `OCR uncertain_lines: ${JSON.stringify(uncertainLines)}`,
  ];
}

function sanitizeOCRLine(rawLine: unknown): {
  line_text: string;
  is_uncertain: boolean;
} | null {
  if (typeof rawLine === "string") {
    const lineText = trimmedString(rawLine);
    return lineText ? { line_text: lineText, is_uncertain: false } : null;
  }

  if (typeof rawLine !== "object" || rawLine === null) return null;
  const raw = rawLine as Record<string, unknown>;
  const lineText = trimmedString(
    valueFor(raw, "line_text", "lineText", "text"),
  );
  if (!lineText) return null;

  const confidence = optionalConfidence(valueFor(raw, "confidence", "score"));
  const uncertainFragments = stringArray(
    valueFor(raw, "uncertain_fragments", "uncertainFragments"),
  );
  const alternatives = stringArray(valueFor(raw, "alternatives"));

  return {
    line_text: lineText,
    is_uncertain: confidence > 0 && confidence < 0.82 ||
      uncertainFragments.length > 0 ||
      alternatives.length > 0 ||
      lineText.includes("?"),
  };
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
