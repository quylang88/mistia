import {
  billItemPromptLines,
  normalizeBillAnalysisItems,
  normalizeBillItems,
  sanitizeBillItem,
} from "./bill-item-normalization.ts";

Deno.test("normalizeBillItems folds adjacent promotion discounts into the previous purchase", () => {
  const clothingCategoryID = "cat-clothing";
  const items = normalizeBillItems([
    sanitizeBillItem(
      {
        line_id: "line-1",
        original_name: "KORI KRILL OIL 152C",
        translated_name: "Dầu nhuyễn thể Kori",
        line_type: "purchase",
        quantity: 4,
        original_amount_minor: 11392,
        final_amount_minor: 11392,
        category_id: clothingCategoryID,
        confidence: 0.86,
        missing_fields: [],
      },
      0,
      new Set([clothingCategoryID]),
    ),
    sanitizeBillItem(
      {
        line_id: "line-2",
        original_name: "※ブラックウィーク",
        line_type: "discount",
        final_amount_minor: -240,
        discount_amount_minor: 240,
        confidence: 0.9,
        missing_fields: [],
      },
      1,
      new Set([clothingCategoryID]),
    ),
  ].filter((item) => item !== null));

  if (items.length !== 1) {
    throw new Error(
      `Expected promotion to be folded, got ${items.length} rows`,
    );
  }
  const item = items[0];
  if (item.quantity !== 4) {
    throw new Error(`Expected quantity 4, got ${item.quantity}`);
  }
  if (item.original_amount_minor !== 11392) {
    throw new Error(
      `Unexpected original amount: ${item.original_amount_minor}`,
    );
  }
  if (item.discount_amount_minor !== 240) {
    throw new Error(
      `Unexpected discount amount: ${item.discount_amount_minor}`,
    );
  }
  if (item.final_amount_minor !== 11152) {
    throw new Error(`Unexpected final amount: ${item.final_amount_minor}`);
  }
});

Deno.test("normalizeBillItems folds Costco CPN suffix-minus rows into the previous matching purchase", () => {
  const categoryID = "cat-baby";
  const items = normalizeBillItems([
    sanitizeBillItem(
      {
        line_id: "line-1",
        original_name: "PAMPERS P-L TPD",
        translated_name: "Tã Pampers P-L TPD",
        line_type: "purchase",
        final_amount_minor: 800,
        category_id: categoryID,
        confidence: 0.9,
        missing_fields: [],
      },
      0,
      new Set([categoryID]),
    ),
    sanitizeBillItem(
      {
        line_id: "line-2",
        original_name: "PAMPERS P-L TPD CPN",
        line_type: "discount",
        final_amount_minor: "800-T",
        confidence: 0.9,
        missing_fields: [],
      },
      1,
      new Set([categoryID]),
    ),
  ].filter((item) => item !== null));

  if (items.length !== 1) {
    throw new Error(`Expected CPN row to be folded, got ${items.length} rows`);
  }
  const item = items[0];
  if (item.original_amount_minor !== 800) {
    throw new Error(
      `Unexpected original amount: ${item.original_amount_minor}`,
    );
  }
  if (item.discount_amount_minor !== 800) {
    throw new Error(
      `Unexpected discount amount: ${item.discount_amount_minor}`,
    );
  }
  if (item.final_amount_minor !== 0) {
    throw new Error(`Unexpected final amount: ${item.final_amount_minor}`);
  }
  if (item.missing_fields.includes("finalAmountMinor")) {
    throw new Error(
      `Fully discounted item should keep final amount: ${
        JSON.stringify(item.missing_fields)
      }`,
    );
  }
});

Deno.test("normalizeBillItems folds coupon rows even when the model mislabels them as purchases", () => {
  const categoryID = "cat-baby";
  const items = normalizeBillItems([
    sanitizeBillItem(
      {
        line_id: "line-1",
        original_name: "PAMPERS P-L TPD",
        line_type: "purchase",
        final_amount_minor: 800,
        category_id: categoryID,
        confidence: 0.9,
        missing_fields: [],
      },
      0,
      new Set([categoryID]),
    ),
    sanitizeBillItem(
      {
        line_id: "line-2",
        original_name: "PAMPERS P-L TPD",
        raw_line_text: "PAMPERS P-L TPD CPN 800-T",
        line_type: "purchase",
        final_amount_minor: 800,
        category_id: categoryID,
        confidence: 0.8,
        missing_fields: [],
      },
      1,
      new Set([categoryID]),
    ),
  ].filter((item) => item !== null));

  if (items.length !== 1) {
    throw new Error(
      `Expected mislabeled CPN row to be folded, got ${items.length} rows`,
    );
  }
  if (
    items[0].discount_amount_minor !== 800 || items[0].final_amount_minor !== 0
  ) {
    throw new Error(`Unexpected folded item: ${JSON.stringify(items[0])}`);
  }
});

Deno.test("normalizeBillItems folds suffix-minus discount rows with repeated product text", () => {
  const categoryID = "cat-baby";
  const items = normalizeBillItems([
    sanitizeBillItem(
      {
        line_id: "line-1",
        raw_line_text: "PAMPERS P-L TPD 800",
        original_name: "PAMPERS P-L TPD",
        line_type: "purchase",
        final_amount_minor: 800,
        category_id: categoryID,
        confidence: 0.9,
        missing_fields: [],
      },
      0,
      new Set([categoryID]),
    ),
    sanitizeBillItem(
      {
        line_id: "line-2",
        raw_line_text: "PAMPERS P-L TPD 800-",
        original_name: "PAMPERS P-L TPD",
        line_type: "purchase",
        final_amount_minor: 800,
        category_id: categoryID,
        confidence: 0.8,
        missing_fields: [],
      },
      1,
      new Set([categoryID]),
    ),
  ].filter((item) => item !== null));

  if (items.length !== 1) {
    throw new Error(
      `Expected suffix-minus row to be folded, got ${items.length} rows`,
    );
  }
  if (
    items[0].discount_amount_minor !== 800 || items[0].final_amount_minor !== 0
  ) {
    throw new Error(`Unexpected folded item: ${JSON.stringify(items[0])}`);
  }
});

Deno.test("normalizeBillItems keeps standalone bill-level discounts separate", () => {
  const categoryID = "cat-household";
  const items = normalizeBillItems([
    sanitizeBillItem(
      {
        line_id: "line-1",
        raw_line_text: "DOVE SAKURA 1777",
        original_name: "DOVE SAKURA",
        line_type: "purchase",
        final_amount_minor: 1777,
        category_id: categoryID,
        confidence: 0.9,
        missing_fields: [],
      },
      0,
      new Set([categoryID]),
    ),
    sanitizeBillItem(
      {
        line_id: "line-2",
        raw_line_text: "TOTAL COUPON 500-",
        original_name: "TOTAL COUPON",
        line_type: "discount",
        final_amount_minor: -500,
        discount_amount_minor: 500,
        confidence: 0.8,
        missing_fields: [],
      },
      1,
      new Set([categoryID]),
    ),
  ].filter((item) => item !== null));

  if (items.length !== 2) {
    throw new Error(
      `Expected standalone bill-level discount to stay separate, got ${items.length} rows`,
    );
  }
  if (
    items[0].discount_amount_minor !== 0 || items[0].final_amount_minor !== 1777
  ) {
    throw new Error(
      `Purchase item was incorrectly mutated: ${JSON.stringify(items[0])}`,
    );
  }
  if (
    items[1].line_type !== "discount" || items[1].final_amount_minor !== -500
  ) {
    throw new Error(
      `Standalone discount was not preserved: ${JSON.stringify(items[1])}`,
    );
  }
});

Deno.test("sanitizeBillItem recovers purchase plus attached coupon from a collapsed discount row", () => {
  const categoryID = "cat-food";
  const item = sanitizeBillItem(
    {
      line_id: "line-1",
      raw_line_text: "SP A 3,000\nSP A CPN 500-",
      original_name: "SP A",
      line_type: "discount",
      final_amount_minor: -2500,
      discount_amount_minor: 2500,
      category_id: categoryID,
      confidence: 0.7,
      missing_fields: [],
    },
    0,
    new Set([categoryID]),
  );

  if (!item) {
    throw new Error("Expected item to sanitize");
  }
  if (item.line_type !== "purchase") {
    throw new Error(`Expected recovered purchase, got ${item.line_type}`);
  }
  if (item.original_amount_minor !== 3000) {
    throw new Error(
      `Expected original amount 3000, got ${item.original_amount_minor}`,
    );
  }
  if (item.discount_amount_minor !== 500) {
    throw new Error(
      `Expected discount amount 500, got ${item.discount_amount_minor}`,
    );
  }
  if (item.final_amount_minor !== 2500) {
    throw new Error(
      `Expected final amount 2500, got ${item.final_amount_minor}`,
    );
  }
});

Deno.test("sanitizeBillItem preserves printed katakana brand text from raw line", () => {
  const categoryID = "cat-household";
  const item = sanitizeBillItem(
    {
      line_id: "line-1",
      raw_line_text: "ラッフィング カウオリジナル 1178",
      original_name: "ラッピング カワオリジナル",
      line_type: "purchase",
      final_amount_minor: 1178,
      category_id: categoryID,
      confidence: 0.82,
      missing_fields: [],
    },
    0,
    new Set([categoryID]),
  );

  if (!item) {
    throw new Error("Expected item to sanitize");
  }
  if (item.original_name !== "ラッフィング カウオリジナル") {
    throw new Error(`Original name was autocorrected: ${item.original_name}`);
  }
});

Deno.test("sanitizeBillItem uses OCR transcript to correct autocorrected katakana", () => {
  const categoryID = "cat-household";
  const item = sanitizeBillItem(
    {
      line_id: "line-1",
      raw_line_text: "ラッピング カワオリジナル 1178",
      original_name: "ラッピング カワオリジナル",
      line_type: "purchase",
      final_amount_minor: 1178,
      category_id: categoryID,
      confidence: 0.82,
      missing_fields: [],
    },
    0,
    new Set([categoryID]),
    ["ラッフィング カウオリジナル 1178"],
  );

  if (!item) {
    throw new Error("Expected item to sanitize");
  }
  if (item.original_name !== "ラッフィング カウオリジナル") {
    throw new Error(`OCR text was not preserved: ${item.original_name}`);
  }
});

Deno.test("billItemPromptLines explains Costco-style quantity and adjacent promotion signs", () => {
  const text = billItemPromptLines().join("\n");

  for (
    const expected of [
      "raw_line_text",
      "quantity",
      "1@",
      "3@",
      "4@",
      "never 10",
      "never 20",
      "never 30",
      "never 40",
      "x3",
      "item-level discount",
      "directly below",
      "CPN",
      "coupon",
      "800-",
      "800-T",
      "Do not autocorrect",
      "OCR transcription",
      "non-dictionary",
      "Similar-looking Japanese kana",
      "category_id",
      "closest category",
    ]
  ) {
    if (!text.includes(expected)) {
      throw new Error(`Prompt is missing guidance: ${expected}`);
    }
  }
});

Deno.test("sanitizeBillItem corrects suspicious multiplied quantities from visible at-mark markers", () => {
  const categoryID = "cat-supplement";
  const cases = [
    { raw_line_text: "KORI KRILL OIL 2@ 5696", quantity: 20, expected: 2 },
    { raw_line_text: "KORI KRILL OIL 3@ 8544", quantity: 30, expected: 3 },
    { raw_line_text: "KORI KRILL OIL 4@ 11392", quantity: 40, expected: 4 },
    { raw_line_text: "KORI KRILL OIL @2 5696", quantity: 20, expected: 2 },
    { raw_line_text: "KORI KRILL OIL ×3 8544", quantity: 30, expected: 3 },
  ];

  for (const testCase of cases) {
    const item = sanitizeBillItem(
      {
        line_id: `line-${testCase.expected}`,
        raw_line_text: testCase.raw_line_text,
        original_name: "KORI KRILL OIL",
        line_type: "purchase",
        quantity: testCase.quantity,
        final_amount_minor: 1000,
        category_id: categoryID,
        confidence: 0.9,
        missing_fields: [],
      },
      0,
      new Set([categoryID]),
    );

    if (!item) {
      throw new Error("Expected item to sanitize");
    }
    if (item.quantity !== testCase.expected) {
      throw new Error(
        `Expected ${testCase.expected} for ${testCase.raw_line_text}, got ${item.quantity}`,
      );
    }
  }
});

Deno.test("sanitizeBillItem uses OCR transcript to correct suspicious 1@ and 2@ quantities", () => {
  const categoryID = "cat-supplement";
  const singleItem = sanitizeBillItem(
    {
      line_id: "line-1",
      original_name: "KORI KRILL OIL",
      line_type: "purchase",
      quantity: 10,
      final_amount_minor: 5696,
      category_id: categoryID,
      confidence: 0.8,
      missing_fields: [],
    },
    0,
    new Set([categoryID]),
    ["KORI KRILL OIL 1@ 5696"],
  );
  const doubleItem = sanitizeBillItem(
    {
      line_id: "line-2",
      original_name: "KORI KRILL OIL",
      line_type: "purchase",
      quantity: 20,
      final_amount_minor: 11392,
      category_id: categoryID,
      confidence: 0.8,
      missing_fields: [],
    },
    0,
    new Set([categoryID]),
    ["KORI KRILL OIL 2@ 11392"],
  );

  if (!singleItem || !doubleItem) {
    throw new Error("Expected items to sanitize");
  }
  if (singleItem.quantity !== null) {
    throw new Error(
      `Expected 1@ to stay single/null, got ${singleItem.quantity}`,
    );
  }
  if (doubleItem.quantity !== 2) {
    throw new Error(`Expected 2@ to become x2, got ${doubleItem.quantity}`);
  }
});

Deno.test("sanitizeBillItem does not clamp real two digit visible quantities", () => {
  const categoryID = "cat-supplement";
  const item = sanitizeBillItem(
    {
      line_id: "line-12",
      raw_line_text: "KORI KRILL OIL 12@ 34176",
      original_name: "KORI KRILL OIL",
      line_type: "purchase",
      quantity: 12,
      final_amount_minor: 34176,
      category_id: categoryID,
      confidence: 0.9,
      missing_fields: [],
    },
    0,
    new Set([categoryID]),
  );

  if (!item) {
    throw new Error("Expected item to sanitize");
  }
  if (item.quantity !== 12) {
    throw new Error(`Expected quantity 12, got ${item.quantity}`);
  }
});

Deno.test("billItemPromptLines requires full target-language product translations", () => {
  const text = billItemPromptLines().join("\n");

  for (
    const expected of [
      "translated_name must describe the recognizable product type",
      "target language",
      "DOVE",
      "body lotion",
      "Pampers",
      "size L",
      "KLEENEX",
      "facial tissue",
      "KORI KRILL OIL",
      "krill oil supplement",
    ]
  ) {
    if (!text.includes(expected)) {
      throw new Error(`Prompt is missing translation guidance: ${expected}`);
    }
  }
});

Deno.test("normalizeBillAnalysisItems does not invent discounts to force receipt total", () => {
  const categoryID = "cat-supplement";
  const items = normalizeBillAnalysisItems(
    [
      sanitizeBillItem(
        {
          line_id: "line-1",
          original_name: "KORI KRILL OIL152C",
          line_type: "purchase",
          quantity: 3,
          original_amount_minor: 8544,
          discount_amount_minor: 0,
          final_amount_minor: 8544,
          category_id: categoryID,
          confidence: 0.9,
          missing_fields: [],
        },
        0,
        new Set([categoryID]),
      ),
      sanitizeBillItem(
        {
          line_id: "line-2",
          original_name: "KORI KRILL OIL152C",
          line_type: "purchase",
          quantity: 4,
          original_amount_minor: 11392,
          discount_amount_minor: 0,
          final_amount_minor: 11392,
          category_id: categoryID,
          confidence: 0.9,
          missing_fields: [],
        },
        1,
        new Set([categoryID]),
      ),
    ].filter((item) => item !== null),
    31523,
  );

  if (
    items[0].discount_amount_minor !== 0 || items[0].final_amount_minor !== 8544
  ) {
    throw new Error(`First item was mutated: ${JSON.stringify(items[0])}`);
  }
  if (
    items[1].discount_amount_minor !== 0 ||
    items[1].final_amount_minor !== 11392
  ) {
    throw new Error(`Second item was mutated: ${JSON.stringify(items[1])}`);
  }
});
