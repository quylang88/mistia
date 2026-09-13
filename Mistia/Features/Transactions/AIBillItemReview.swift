import SwiftUI

struct AIBillItemEditorTarget: Identifiable {
    let billID: UUID
    let item: BillItemAnalysisItem
    let currencyCode: String
    var isNew = false
    var id: String { "\(billID)-\(item.lineID)" }
}

/// Receipt facts keep the same hierarchy in the list and the review sheet.
struct AIBillItemSummary: View {
    let item: BillItemAnalysisItem
    let currencyCode: String
    let amountMinor: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: item.originalName)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let translatedName = item.translatedName {
                Text(verbatim: translatedName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if item.showsDiscountBreakdown, let original = item.originalAmountMinor, amountMinor == item.finalAmountMinor {
                    Text(verbatim: original.formattedCurrency(code: currencyCode))
                        .font(.subheadline).strikethrough().foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(verbatim: amountMinor.formattedCurrency(code: currencyCode))
                    .font(.headline)
                    .foregroundStyle(item.lineType == .discount ? Color.secondary : Color.primary)
                    .fixedSize()
            }
            .monospacedDigit()
            if item.lineType == .purchase, item.discountAmountMinor > 0, amountMinor == item.finalAmountMinor {
                Text(L10n.transactions.aibill.itemDiscount(item.discountAmountMinor.formattedCurrency(code: currencyCode)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AIBillItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var item: BillItemAnalysisItem
    @State private var originalAmount: String
    @State private var discountAmount: String
    @State private var quantity: String
    let currencyCode: String
    let onSave: (BillItemAnalysisItem) -> Void
    var onDelete: (() -> Void)?

    init(item: BillItemAnalysisItem, currencyCode: String, onDelete: (() -> Void)? = nil, onSave: @escaping (BillItemAnalysisItem) -> Void) {
        _item = State(initialValue: item)
        _originalAmount = State(initialValue: String(item.originalAmountMinor ?? max(0, item.finalAmountMinor)))
        _discountAmount = State(initialValue: String(item.discountAmountMinor))
        _quantity = State(initialValue: String(item.quantity ?? 1))
        self.currencyCode = currencyCode
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var editedItem: BillItemAnalysisItem? {
        guard let original = Int64(MistiaCurrencyInputFormatting.sanitizedDigitsAndSign(from: originalAmount)),
              let discount = Int64(MistiaCurrencyInputFormatting.sanitizedDigitsAndSign(from: discountAmount)),
              let count = Int(quantity) else { return nil }
        return item.reviewed(originalAmount: original, discountAmount: discount, quantity: count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.transactions.aibill.itemDetails) {
                    TextField(L10n.transactions.aibill.originalName, text: $item.originalName, axis: .vertical)
                    TextField(L10n.transactions.aibill.translatedName, text: Binding(
                        get: { item.translatedName ?? "" },
                        set: { item.translatedName = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    Picker(L10n.transactions.aibill.lineType, selection: $item.lineType) {
                        Text(L10n.transactions.aibill.purchaseLine).tag(BillItemLineType.purchase)
                        Text(L10n.transactions.aibill.discountLine).tag(BillItemLineType.discount)
                    }
                }
                Section {
                    if item.lineType == .purchase {
                        LabeledContent(L10n.transactions.aibill.quantity) {
                            TextField(L10n.transactions.aibill.quantity, text: $quantity)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent(L10n.transactions.aibill.originalRowAmount) {
                            MistiaCurrencyInputField(L10n.transactions.aibill.originalRowAmount, text: $originalAmount)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent(L10n.transactions.aibill.discountAmount) {
                        MistiaCurrencyInputField(L10n.transactions.aibill.discountAmount, text: $discountAmount)
                            .multilineTextAlignment(.trailing)
                    }
                    if let editedItem {
                        LabeledContent(L10n.transactions.aibill.finalRowAmount,
                                       value: editedItem.finalAmountMinor.formattedCurrency(code: currencyCode))
                            .monospacedDigit().fontWeight(.semibold)
                    }
                } header: {
                    Text(verbatim: currencyCode)
                } footer: {
                    Text(L10n.transactions.aibill.rowAmountHelp)
                }
                if let onDelete {
                    Section {
                        Button(L10n.transactions.aibill.removeItem, role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
                if let rawLineText = item.rawLineText {
                    Section(L10n.transactions.aibill.printedText) {
                        Text(verbatim: rawLineText).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(L10n.transactions.aibill.editItem)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) {
                        guard let editedItem else { return }
                        onSave(editedItem)
                        dismiss()
                    }
                    .disabled(editedItem == nil)
                }
            }
            .tint(colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color)
        }
    }
}

struct AIBillTotalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var totalText: String
    let currencyCode: String
    let onSave: (Int64) -> Void

    init(totalMinor: Int64?, currencyCode: String, onSave: @escaping (Int64) -> Void) {
        _totalText = State(initialValue: totalMinor.map(String.init) ?? "")
        self.currencyCode = currencyCode
        self.onSave = onSave
    }

    private var totalMinor: Int64? {
        guard let value = Int64(MistiaCurrencyInputFormatting.sanitizedDigitsAndSign(from: totalText)), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MistiaCurrencyInputField(L10n.transactions.aibill.receiptTotal, text: $totalText)
                    if let totalMinor { Text(verbatim: totalMinor.formattedCurrency(code: currencyCode)) }
                } header: {
                    Text(L10n.transactions.aibill.receiptTotal)
                } footer: {
                    Text(L10n.transactions.aibill.receiptTotalHelp)
                }
            }
            .navigationTitle(L10n.transactions.aibill.editTotal)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.common.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) {
                        guard let totalMinor else { return }
                        onSave(totalMinor)
                        dismiss()
                    }.disabled(totalMinor == nil)
                }
            }
        }
    }
}
