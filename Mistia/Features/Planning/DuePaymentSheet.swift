import SwiftData
import SwiftUI

// MARK: - Target

struct DuePaymentSheetTarget: Identifiable {
    let id = UUID()
    let sourceKind: PlanningDueSourceKind
    let sourceID: UUID
    let dueMonthKey: String
    let dueDate: Date
    let requiresAmountInput: Bool
    let currencyCode: String
    let name: String
}

// MARK: - Sheet

struct DuePaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(SessionStore.self) private var sessionStore
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
    private var wallets: [LedgerWallet]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var occurrences: [DueOccurrenceRecord]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var bills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var installments: [InstallmentPlan]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var transactions: [LedgerTransaction]

    let target: DuePaymentSheetTarget
    /// Called after a successful payment so the caller can mark the notification as read.
    var onPaid: (() -> Void)? = nil

    @State private var amountText = ""
    @State private var alertMessage: String?

    // MARK: - Init

    init(target: DuePaymentSheetTarget, onPaid: (() -> Void)? = nil) {
        self.target = target
        self.onPaid = onPaid
    }

    // MARK: - Computed

    private var activeCurrencyCode: String { target.currencyCode }

    private var resolvedDueItem: PlanningRecurringDueSnapshot? {
        let selectedMonth = selectedMonthDate
        let occurrenceSnaps = occurrences.map(\.planningSnapshot)

        switch target.sourceKind {
        case .recurringBill:
            let snap = bills
                .filter { $0.id == target.sourceID }
                .map(\.planningSnapshot)
            return PlanningLogic.recurringBillDueItems(
                bills: snap,
                occurrences: occurrenceSnaps,
                selectedMonth: selectedMonth,
                calendar: calendar
            ).first

        case .installment:
            let snap = installments
                .filter { $0.id == target.sourceID }
                .map(\.planningSnapshot)
            return PlanningLogic.installmentDueItems(
                plans: snap,
                occurrences: occurrenceSnaps,
                selectedMonth: selectedMonth,
                calendar: calendar
            ).first

        case .creditCard:
            return nil  // credit card uses statement view, not this sheet
        }
    }

    private var selectedMonthDate: Date {
        PlanningLogic.date(from: target.dueMonthKey, calendar: calendar)
            ?? PlanningLogic.startOfMonth(for: target.dueDate, calendar: calendar)
    }

    private var defaultAmountText: String {
        guard let item = resolvedDueItem, let amount = item.amountMinor else { return "" }
        return String(amount)
    }

    private var effectiveAmountMinor: Int64? {
        if target.requiresAmountInput {
            return amountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        }
        return resolvedDueItem?.amountMinor
    }

    private var walletName: String? {
        switch target.sourceKind {
        case .recurringBill:
            return bills.first(where: { $0.id == target.sourceID })?.paymentWallet?.name
        case .installment:
            return installments.first(where: { $0.id == target.sourceID })?.paymentWallet?.name
        case .creditCard:
            return nil
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MistiaAccent.purple.color.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(MistiaAccent.purple.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(MistiaDateFormatting.shortDateString(for: target.dueDate))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if target.requiresAmountInput {
                    Section {
                        TextField(
                            mistiaLocalized(vi: "Nhập số tiền thanh toán", en: "Enter payment amount", ja: "支払い金額を入力"),
                            text: $amountText
                        )
                        .keyboardType(.numberPad)
                    } header: {
                        Text(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額"))
                    } footer: {
                        Text(mistiaLocalized(
                            vi: "Hóa đơn này chưa có số tiền mặc định.",
                            en: "This bill has no default amount.",
                            ja: "この請求にはデフォルトの金額がありません。"
                        ))
                    }
                } else if let amount = resolvedDueItem?.amountMinor {
                    Section(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額")) {
                        HStack {
                            Text(mistiaLocalized(vi: "Thanh toán", en: "Payment", ja: "支払い"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(amount.formattedCurrency(code: activeCurrencyCode))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(MistiaAccent.purple.color)
                        }
                    }
                }

                if let walletName {
                    Section(mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット")) {
                        Text(walletName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        pay()
                    } label: {
                        HStack {
                            Spacer()
                            Text(mistiaLocalized(vi: "Thanh toán ngay", en: "Pay now", ja: "今すぐ支払う"))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Spacer()
                        }
                    }
                    .foregroundStyle(MistiaAccent.purple.color)
                }
            }
            .navigationTitle(mistiaLocalized(vi: "Thanh toán hóa đơn", en: "Pay bill", ja: "請求の支払い"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            amountText = defaultAmountText
        }
        .alert(
            mistiaLocalized(vi: "Không thể thanh toán", en: "Payment failed", ja: "支払いに失敗しました"),
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(mistiaLocalized(vi: "Đóng", en: "Dismiss", ja: "閉じる"), role: .cancel) {}
        } message: {
            if let alertMessage { Text(alertMessage) }
        }
    }

    // MARK: - Pay

    private func pay() {
        guard let dueItem = resolvedDueItem else {
            alertMessage = mistiaLocalized(
                vi: "Không tìm thấy khoản đến hạn.",
                en: "Could not find the due item.",
                ja: "期限項目が見つかりませんでした。"
            )
            return
        }

        guard dueItem.status == .pending else {
            dismiss()
            return
        }

        do {
            let overrideAmount: Int64? = target.requiresAmountInput
                ? amountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
                : nil

            let draft = try PlanningLogic.makePaymentDraft(
                for: dueItem,
                overrideAmountMinor: overrideAmount
            )
            let saved = try PlanningPersistenceSupport.saveDuePayment(
                draft: draft,
                sourceKind: target.sourceKind,
                sourceID: target.sourceID,
                selectedMonth: selectedMonthDate,
                scheduledDate: dueItem.dueDate,
                wallets: wallets,
                occurrences: Array(occurrences),
                modelContext: modelContext,
                actorUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: saved.transaction.id,
                modifiedAt: saved.transaction.updatedAt,
                subjectUserIDOverride: saved.subjectUserID
            )
            sessionStore.recordUpsert(
                entity: .dueOccurrenceRecord,
                recordID: saved.occurrenceID,
                modifiedAt: saved.transaction.updatedAt
            )
            onPaid?()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - Helpers

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func currencyInputToMinorUnits(currencyCode: String) -> Int64 {
        let sanitized = replacingOccurrences(of: "[^0-9-]", with: "", options: .regularExpression)
        return Int64(sanitized) ?? 0
    }
}

private extension PlanningLogic {
    static func date(from monthKey: String, calendar: Calendar) -> Date? {
        // monthKey format: "YYYY-MM" (e.g. "2026-05")
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        return calendar.date(from: comps)
    }
}
