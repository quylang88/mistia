import {
  billItemPromptLines,
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

Deno.test("billItemPromptLines explains Costco-style quantity and adjacent promotion signs", () => {
  const text = billItemPromptLines().join("\n");

  for (
    const expected of [
      "quantity",
      "3@",
      "4@",
      "x3",
      "item-level discount",
      "directly below",
      "category_id",
      "closest category",
    ]
  ) {
    if (!text.includes(expected)) {
      throw new Error(`Prompt is missing guidance: ${expected}`);
    }
  }
});
