import {
  billArithmeticIssues,
  groundReceiptItems,
  receiptSourceRows,
} from "./receipt-line-grounding.ts";
import {
  normalizeBillAnalysisItems,
  sanitizeBillItem,
} from "./bill-item-normalization.ts";
import { sanitizeReceiptOCRResult } from "./literal-ocr.ts";

// Manually transcribed from IMG_4157. Names retain the receipt's abbreviations.
const lines = [
  "083 パンパ パンツMコ L ¥2,480",
  "087 フレアF&H替2100 ¥1,280",
  "083 99%テアラマワリ ¥348",
  "086 トイレクイックル ¥298",
  "081 タンゴカード ¥148",
  "081 ボールペン替芯 ¥48",
  "082 ガスビ フライパン20 ¥798",
  "081 付箋 ¥128",
  "********まとめ売り********",
  "073 ソフティモ",
  "@298 10 ¥2,980",
  "M01まとめ売り値下 -¥200",
  "************************",
  "083 L3_ライオン ホワイト&赤",
  "@228 10 ¥2,280",
];
const context = sanitizeReceiptOCRResult({
  raw_text: `${
    lines.join("\n")
  }\n28点 小計 ¥10,588\n合計 ¥10,588\n含む消費税等 ¥962\nPayPay ¥10,588`,
  item_lines: lines.map((line_text) => ({ line_text, confidence: 0.98 })),
});
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
function sanitized(rawItems: Record<string, unknown>[], ctx = context) {
  const grounded = groundReceiptItems(rawItems, ctx, "JPY");
  return normalizeBillAnalysisItems(
    grounded.items.map((item, index) =>
      sanitizeBillItem(item, index, new Set(["household", "stationery"]))
    ).filter((item) => item !== null),
    10588,
  );
}

Deno.test("CAINZ 4157 rebuilds 10 purchases, 28 units and ¥10588 despite corrupted model rows", () => {
  const corrupted = lines.slice(0, 8).map((_, index) => ({
    line_id: "duplicate",
    original_name: index >= 4 ? "ボールペン替芯" : "99%テアラマワリ",
    quantity: index === 2 ? 10 : null,
    final_amount_minor: index >= 4 ? 128 : 2280,
    category_id: "household",
    translated_name: "Wrong translation",
    confidence: 0.99,
  }));
  corrupted.push({
    line_id: "duplicate",
    original_name: "ソフティモ",
    quantity: 10,
    final_amount_minor: -2780,
    category_id: "household",
    translated_name: "Softymo",
    confidence: 0.9,
  });
  const items = sanitized(corrupted);
  equal(items.length, 10);
  equal(items.map((item) => item.final_amount_minor), [
    2480,
    1280,
    348,
    298,
    148,
    48,
    798,
    128,
    2780,
    2280,
  ]);
  equal(items.reduce((sum, item) => sum + (item.quantity ?? 1), 0), 28);
  equal(items.every((item) => item.line_type === "purchase"), true);
  equal(new Set(items.map((item) => item.line_id)).size, 10);
  equal([
    items[8].original_amount_minor,
    items[8].discount_amount_minor,
    items[8].quantity,
  ], [2980, 200, 10]);
  equal([items[9].original_amount_minor, items[9].quantity], [2280, 10]);
  equal(items[7].original_name, "付箋");
  equal(items[7].translated_name, null);
  equal(billArithmeticIssues(items, 10588), []);
});

Deno.test("source rows keep repeated purchases separate and bind semantics by index", () => {
  const ctx = sanitizeReceiptOCRResult({
    item_lines: ["081 ボールペン替芯 ¥48", "081 ボールペン替芯 ¥128"],
  });
  const items = sanitized([
    {
      original_name: "ボールペン替芯",
      source_line_indexes: [1],
      category_id: "household",
    },
    {
      original_name: "ボールペン替芯",
      source_line_indexes: [0],
      category_id: "stationery",
    },
  ], ctx);
  equal(items.map((item) => [item.final_amount_minor, item.category_id]), [[
    48,
    "stationery",
  ], [128, "household"]]);
});

Deno.test("unsupported layouts and inconsistent unit-price arithmetic use general path", () => {
  equal(
    receiptSourceRows({
      ...context,
      item_lines: ["073 ソフティモ", "@298 10 ¥2,280"],
    }),
    null,
  );
  equal(
    receiptSourceRows({
      ...context,
      item_lines: ["073 ソフティモ", "unknown continuation"],
    }),
    null,
  );
});

Deno.test("general source links reject duplicate, out-of-range and noncontiguous references", () => {
  const ctx = {
    ...context,
    item_lines: ["Milk $2.00", "Bread $3.00", "Tea $4.00"],
  };
  const result = groundReceiptItems(
    [
      { source_line_indexes: [0], original_name: "Milk" },
      { source_line_indexes: [0], original_name: "Bread" },
      { source_line_indexes: [10], original_name: "Tea" },
      { source_line_indexes: [1, 1], original_name: "Tea" },
    ],
    ctx,
    "USD",
  );
  equal(result.missingFields, ["sourceLines"]);
  equal(
    result.items.slice(1).every((item) =>
      (item.missing_fields as string[]).includes("sourceText")
    ),
    true,
  );
});

Deno.test("uncertain OCR remains reviewable even when totals match", () => {
  const ctx = { ...context, uncertain_lines: [context.item_lines[5]] };
  equal(sanitized([], ctx)[5].missing_fields.includes("sourceText"), true);
});

Deno.test("a whole-bill coupon stays separate and a discount cannot exceed its purchase", () => {
  const ctx = {
    ...context,
    item_lines: ["081 商品 ¥300", "合計クーポン -¥50"],
  };
  // A whole-bill coupon is not a purchase summary or an attached coupon.
  equal(receiptSourceRows(ctx)?.length, 2);
  equal(
    receiptSourceRows({
      ...context,
      item_lines: ["081 商品 ¥300", "M01まとめ売り値下 -¥500"],
    }),
    null,
  );
});

Deno.test("money validation reports differences without inventing discounts or changing totals", () => {
  const items = sanitized([]);
  equal(billArithmeticIssues(items, 11000), ["totalMismatch"]);
  items[0].original_amount_minor = 2400;
  equal(billArithmeticIssues(items, 10588), ["itemArithmetic"]);
});

Deno.test("CAINZ quantity prices cannot turn into quantities 298 or 228", () => {
  for (const [unit, total] of [[298, 2980], [228, 2280]]) {
    const item = sanitizeBillItem(
      {
        original_name: "商品",
        raw_line_text: `083 商品\n@${unit} 10 ¥${total}`,
        quantity: unit,
        final_amount_minor: total,
      },
      0,
      new Set(),
    );
    equal(item?.quantity, 10);
  }
});

Deno.test("positive purchases with attached bulk discount never become negative discounts", () => {
  const item = sanitizeBillItem(
    {
      original_name: "ソフティモ",
      raw_line_text: "073 ソフティモ\n@298 10 ¥2,980\nM01まとめ売り値下 -¥200",
      quantity: 10,
      final_amount_minor: 2780,
      discount_amount_minor: 200,
    },
    0,
    new Set(),
  );
  equal([
    item?.line_type,
    item?.final_amount_minor,
    item?.discount_amount_minor,
  ], ["purchase", 2780, 200]);
});
