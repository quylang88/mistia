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

Deno.test("billItemPromptLines explains Costco-style quantity and adjacent promotion signs", () => {
  const text = billItemPromptLines().join("\n");

  for (
    const expected of [
      "raw_line_text",
      "quantity",
      "3@",
      "4@",
      "x3",
      "item-level discount",
      "directly below",
      "CPN",
      "coupon",
      "800-",
      "800-T",
      "Do not autocorrect",
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
