import type { ReceiptOCRContext } from "./literal-ocr.ts";

type RawItem = Record<string, unknown>;
export type ReceiptSourceRow = {
  source_line_indexes: number[];
  raw_line_text: string;
  original_name: string;
  line_type: "purchase" | "discount";
  quantity: number | null;
  original_amount_minor: number | null;
  discount_amount_minor: number;
  final_amount_minor: number;
};

// Only read explicit yen columns. Bare digits can be department codes, sizes,
// unit prices, counts or tax rates, and must never be searched as money pairs.
function yenColumn(line: string): { amount: number; start: number } | null {
  const match = /([-−－]?\s*[¥￥]\s*\d[\d,]*)(?:\s*[A-Z※*]?)\s*$/.exec(
    line.normalize("NFKC"),
  );
  if (!match) return null;
  const amount = Number(match[1].replace(/[^0-9]/g, ""));
  if (!Number.isSafeInteger(amount)) return null;
  return {
    amount: /[-−－]/.test(match[1]) ? -amount : amount,
    start: match.index,
  };
}

function normalizedName(name: unknown): string {
  return typeof name === "string"
    ? name.normalize("NFKC").toLowerCase().replace(/[\s\p{Punctuation}]/gu, "")
    : "";
}

const summaryLine =
  /^(?:\d+点\s*)?(?:小計|合計|総合計|税込合計|消費税|内税|外税|税額|含む|[（(]|お釣|お預|現金|PayPay|クレジット|伝票|登録番号|TEL|電話|ポイント)/i;
const sectionLine = /^[*＊\s-]*(?:まとめ売り)?[*＊\s-]+$/;
const itemDiscount =
  /^(?:M\d+\s*)?(?:まとめ売り値下|値引|割引|クーポン|CPN|COUPON)(?:\s|$|額|き|\d|[-−－¥￥])/i;

export function receiptSourceRows(
  context: ReceiptOCRContext,
): ReceiptSourceRow[] | null {
  const rows: ReceiptSourceRow[] = [];
  let pending: { name: string; text: string; index: number } | null = null;
  let canAttachDiscount = false;
  for (const [index, text] of context.item_lines.entries()) {
    const line = text.normalize("NFKC").trim();
    if (
      !line || sectionLine.test(line) ||
      (summaryLine.test(line) && !/(?:クーポン|coupon)/i.test(line))
    ) {
      // A section boundary must not move a coupon onto an unrelated product.
      if (pending) return null;
      canAttachDiscount = false;
      continue;
    }
    const money = yenColumn(line);
    const quantityMatch = /^@\s*([\d,]+)\s+(\d+)\s+(?:[x×]\s*)?[¥￥]/.exec(
      line,
    );
    if (quantityMatch && pending && money && money.amount >= 0) {
      const unitPrice = Number(quantityMatch[1].replace(/,/g, ""));
      const quantity = Number(quantityMatch[2]);
      if (
        !Number.isSafeInteger(quantity) || quantity < 1 ||
        unitPrice * quantity !== money.amount
      ) return null;
      rows.push({
        source_line_indexes: [pending.index, index],
        raw_line_text: `${pending.text}\n${text}`,
        original_name: pending.name,
        line_type: "purchase",
        quantity: quantity > 1 ? quantity : null,
        original_amount_minor: money.amount,
        discount_amount_minor: 0,
        final_amount_minor: money.amount,
      });
      pending = null;
      canAttachDiscount = true;
      continue;
    }
    if (money && money.amount < 0) {
      if (pending) return null;
      const name = line.slice(0, money.start).trim();
      const previous = rows.at(-1);
      if (
        canAttachDiscount && previous?.line_type === "purchase" &&
        itemDiscount.test(name)
      ) {
        const discount = Math.abs(money.amount);
        if (discount > previous.final_amount_minor) return null;
        previous.source_line_indexes.push(index);
        previous.raw_line_text += `\n${text}`;
        previous.discount_amount_minor += discount;
        previous.final_amount_minor -= discount;
      } else {
        rows.push({
          source_line_indexes: [index],
          raw_line_text: text,
          original_name: name,
          line_type: "discount",
          quantity: null,
          original_amount_minor: null,
          discount_amount_minor: Math.abs(money.amount),
          final_amount_minor: money.amount,
        });
        canAttachDiscount = false;
      }
      continue;
    }
    // This layout prints a department code before every product. Requiring it
    // keeps unknown receipt layouts on the general model path.
    const product = /^\d{2,8}\s+(.+)$/.exec(line);
    if (!product || pending) return null;
    const name = (money ? line.slice(0, money.start) : line).replace(
      /^\d{2,8}\s+/,
      "",
    ).trim();
    if (!/[\p{Letter}]/u.test(name)) return null;
    if (!money) {
      pending = { name, text, index };
      canAttachDiscount = false;
      continue;
    }
    rows.push({
      source_line_indexes: [index],
      raw_line_text: text,
      original_name: name,
      line_type: "purchase",
      quantity: null,
      original_amount_minor: money.amount,
      discount_amount_minor: 0,
      final_amount_minor: money.amount,
    });
    canAttachDiscount = true;
  }
  return !pending && rows.length > 0 ? rows : null;
}

export function groundReceiptItems(
  rawItems: unknown[],
  context: ReceiptOCRContext,
  currencyCode: string,
): { items: RawItem[]; missingFields: string[] } {
  const items = rawItems.filter((item): item is RawItem =>
    typeof item === "object" && item !== null
  );
  const rows = currencyCode === "JPY" ? receiptSourceRows(context) : null;
  if (rows) {
    const used = new Set<number>();
    const grounded = rows.map((row) => {
      // Semantics may only follow the same literal product. A repeated name
      // additionally needs its source row, never the first global name match.
      const matches = items.flatMap((item, index) =>
        !used.has(index) &&
          normalizedName(item.original_name) ===
            normalizedName(row.original_name)
          ? [{ item, index }]
          : []
      );
      const linked = matches.filter(({ item }) =>
        Array.isArray(item.source_line_indexes) &&
        item.source_line_indexes.includes(row.source_line_indexes[0])
      );
      const match = linked.length === 1
        ? linked[0]
        : matches.length === 1
        ? matches[0]
        : null;
      if (match) used.add(match.index);
      const uncertain = row.source_line_indexes.some((index) =>
        context.uncertain_lines.includes(context.item_lines[index])
      );
      const missing = new Set<string>(uncertain ? ["sourceText"] : []);
      if (!match && row.line_type === "purchase") missing.add("categoryID");
      return {
        ...match?.item,
        ...row,
        line_id: `source-${row.source_line_indexes[0] + 1}`,
        translated_name: match?.item.translated_name ?? null,
        category_id: row.line_type === "purchase"
          ? match?.item.category_id ?? null
          : null,
        confidence: uncertain ? 0.4 : match?.item.confidence ?? 0.7,
        missing_fields: Array.from(missing),
      };
    });
    return { items: grounded, missingFields: [] };
  }

  // General layouts still retain one-to-one provenance. No fuzzy global lookup:
  // similar names and repeated purchases must not borrow another row's price.
  const used = new Set<number>();
  const missingFields = new Set<string>();
  const grounded = items.map((item, index) => {
    const indexes = Array.isArray(item.source_line_indexes)
      ? item.source_line_indexes
      : [];
    const valid = indexes.length > 0 && indexes.every((value) =>
      Number.isInteger(value) && value >= 0 &&
      value < context.item_lines.length && !used.has(value)
    ) &&
      new Set(indexes).size === indexes.length && indexes.every((value, i) =>
        i === 0 || value === indexes[i - 1] + 1
      );
    const missing = new Set(
      Array.isArray(item.missing_fields) ? item.missing_fields : [],
    );
    if (context.item_lines.length > 0 && !valid) {
      missing.add("sourceText");
      missingFields.add("sourceLines");
    }
    if (valid) {
      const sourceName = normalizedName(
        indexes.map((value) => context.item_lines[value]).join("\n"),
      );
      const modelName = normalizedName(item.original_name);
      if (!modelName || !sourceName.includes(modelName)) {
        missing.add("sourceText");
      }
      indexes.forEach((value) => used.add(value));
      if (
        indexes.some((value) =>
          context.uncertain_lines.includes(context.item_lines[value])
        )
      ) missing.add("sourceText");
    }
    return {
      ...item,
      line_id: `line-${index + 1}`,
      raw_line_text: valid
        ? indexes.map((value) => context.item_lines[value]).join("\n")
        : item.raw_line_text,
      missing_fields: Array.from(missing),
    };
  });
  return { items: grounded, missingFields: Array.from(missingFields) };
}

export function billArithmeticIssues(
  items: {
    line_type: string;
    original_amount_minor: number | null;
    discount_amount_minor: number;
    final_amount_minor: number;
  }[],
  totalMinor: number | null,
): string[] {
  const issues: string[] = [];
  const sum = items.reduce((total, item) => total + item.final_amount_minor, 0);
  if (totalMinor !== null && sum !== totalMinor) issues.push("totalMismatch");
  if (
    items.some((item) =>
      item.line_type === "purchase" && item.original_amount_minor !== null &&
      item.original_amount_minor - item.discount_amount_minor !==
        item.final_amount_minor
    )
  ) issues.push("itemArithmetic");
  return issues;
}
