import {
  buildReceiptOCRPrompt,
  ocrContextPromptLines,
  sanitizeReceiptOCRResult,
} from "./literal-ocr.ts";

Deno.test("buildReceiptOCRPrompt requires literal katakana OCR without common-word correction", () => {
  const prompt = buildReceiptOCRPrompt();
  for (
    const expected of [
      "OCR",
      "not dictionary correction",
      "Mentally zoom/crop each item row",
      "カウ is not カワ",
      "ラッフィング is not ラッピング",
      "フィ is not ピ",
      "do not replace it with a more common word",
    ]
  ) {
    if (!prompt.includes(expected)) {
      throw new Error(`OCR prompt is missing guidance: ${expected}`);
    }
  }
});

Deno.test("sanitizeReceiptOCRResult preserves uncertain katakana item lines", () => {
  const context = sanitizeReceiptOCRResult({
    raw_text: "ラッフィング カウオリジナル 1178",
    item_lines: [
      {
        line_text: "ラッフィング カウオリジナル 1178",
        confidence: 0.72,
        uncertain_fragments: ["カウ"],
        alternatives: ["カワ"],
      },
    ],
  });

  if (context.item_lines[0] !== "ラッフィング カウオリジナル 1178") {
    throw new Error(`Unexpected OCR line: ${context.item_lines[0]}`);
  }
  if (!context.uncertain_lines.includes("ラッフィング カウオリジナル 1178")) {
    throw new Error(
      `Expected uncertain OCR line: ${JSON.stringify(context.uncertain_lines)}`,
    );
  }
});

Deno.test("ocrContextPromptLines makes OCR transcript source of truth", () => {
  const lines = ocrContextPromptLines({
    raw_text: "ラッフィング カウオリジナル 1178",
    item_lines: ["ラッフィング カウオリジナル 1178"],
    uncertain_lines: ["ラッフィング カウオリジナル 1178"],
  }).join("\n");

  for (
    const expected of [
      "source of truth",
      "Copy item original_name from OCR item lines exactly",
      "do not guess between similar kana",
      "カウ/カワ",
      "ラッフィング カウオリジナル",
    ]
  ) {
    if (!lines.includes(expected)) {
      throw new Error(`OCR context prompt is missing: ${expected}`);
    }
  }
});
