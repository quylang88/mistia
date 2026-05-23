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
    @Environment(\.colorScheme) private var colorScheme
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

    let target: DuePaymentSheetTarget
    /// Called after a successful payment so the caller can mark the notification as read.
    var onPaid: (() -> Void)? = nil

    @State private var amountText = ""
    @State private var selectedWalletID: UUID?
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
        PlanningLogic.month(from: target.dueMonthKey, calendar: calendar)
            ?? PlanningLogic.startOfMonth(for: target.dueDate, calendar: calendar)
    }

    private var defaultAmountText: String {
        guard let item = resolvedDueItem, let amount = item.amountMinor else { return "" }
        return String(amount)
    }

    private var defaultWalletID: UUID? {
        switch target.sourceKind {
        case .recurringBill, .installment:
            return resolvedDueItem?.paymentWalletID
        case .creditCard:
            return nil
        }
    }

    private var availableWallets: [LedgerWallet] {
        wallets
            .filter { !$0.isArchived }
            .filter { wallet in
                switch target.sourceKind {
                case .recurringBill:
                    return true
                case .installment:
                    return wallet.kind != .creditCard
                case .creditCard:
                    return true
                }
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var parsedAmountInput: Int64? {
        amountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
    }

    private var selectedWalletName: String {
        guard let selectedWalletID,
              let wallet = wallets.first(where: { $0.id == selectedWalletID }) else {
            return L10n.planning.duepayment.chooseWallet
        }
        return wallet.name
    }

    private var resolvedIconSymbolName: String {
        switch target.sourceKind {
        case .recurringBill:
            if let plan = bills.first(where: { $0.id == target.sourceID }) {
                return plan.category?.iconSymbolName ?? plan.iconSymbolName
            }
            return "mistia.plan.bill"
        case .installment:
            return installments.first(where: { $0.id == target.sourceID })?.iconSymbolName ?? "mistia.plan.installment"
        case .creditCard:
            return "mistia.plan.card_bill"
        }
    }

    private var resolvedIconColor: Color {
        switch target.sourceKind {
        case .recurringBill:
            if let plan = bills.first(where: { $0.id == target.sourceID }) {
                let hex = plan.category?.iconColorHex ?? MistiaFinanceIconRegistry.defaultColorHex(for: resolvedIconSymbolName)
                return Color(hex: hex)
            }
        case .installment:
            if let plan = installments.first(where: { $0.id == target.sourceID }) {
                return Color(hex: MistiaFinanceIconRegistry.defaultColorHex(for: plan.iconSymbolName))
            }
        case .creditCard:
            break
        }

        return colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    private var payButtonDisabled: Bool {
        guard resolvedDueItem != nil, selectedWalletID != nil else {
            return true
        }

        if target.requiresAmountInput {
            return (parsedAmountInput ?? 0) <= 0
        }

        return (resolvedDueItem?.amountMinor ?? 0) <= 0
    }

    private var walletFieldTitle: String {
        L10n.planning.duepayment.paymentWallet
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        MistiaFinanceIconView(
                            icon: resolvedIconSymbolName,
                            fallbackColor: resolvedIconColor,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(paymentWindowText)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                paymentDetailsSection
                paymentActionSection
            }
            .navigationTitle(L10n.planning.duepayment.payBill)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            amountText = defaultAmountText
            selectedWalletID = defaultWalletID
        }
        .alert(
            L10n.planning.duepayment.paymentFailed,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L10n.planning.duepayment.dismiss, role: .cancel) {}
        } message: {
            if let alertMessage { Text(alertMessage) }
        }
    }

    @ViewBuilder
    private var paymentDetailsSection: some View {
        Section {
            amountRow
            walletMenuRow
        } footer: {
            if target.requiresAmountInput {
                Text(L10n.planning.duepayment.thisBillHasNoDefaultAmount)
            }
        }
    }

    private var paymentActionSection: some View {
        Section {
            DuePaymentPrimaryActionButton(
                title: L10n.planning.duepayment.payNow,
                isDisabled: payButtonDisabled
            ) {
                pay()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var amountRow: some View {
        if target.requiresAmountInput {
            TextField(
                "",
                text: $amountText,
                prompt: Text(L10n.planning.duepayment.enterAmount)
                    .foregroundStyle(.tertiary)
            )
            .keyboardType(.numberPad)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
        } else if let amount = resolvedDueItem?.amountMinor {
            Text(amount.formattedCurrency(code: activeCurrencyCode))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(resolvedIconColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
    }

    private var walletMenuRow: some View {
        Picker(walletFieldTitle, selection: $selectedWalletID) {
            Text(L10n.planning.duepayment.chooseWallet).tag(Optional<UUID>.none)
            ForEach(availableWallets) { wallet in
                Text(wallet.name).tag(Optional(wallet.id))
            }
        }
        .pickerStyle(.menu)
    }

    private var paymentWindowText: String {
        guard let item = resolvedDueItem else {
            return MistiaDateFormatting.shortDateString(for: target.dueDate)
        }
        if item.hasExplicitDueDate {
            return "\(MistiaDateFormatting.shortDateString(for: item.paymentStartDate)) - \(MistiaDateFormatting.shortDateString(for: item.dueDate))"
        }
        return MistiaDateFormatting.shortDateString(for: item.paymentStartDate)
    }

    // MARK: - Pay

    private func pay() {
        guard let dueItem = resolvedDueItem else {
            alertMessage = L10n.planning.duepayment.couldNotFindTheDueItem
            return
        }

        guard dueItem.status == .pending else {
            dismiss()
            return
        }

        do {
            let overrideAmount: Int64? = target.requiresAmountInput
                ? parsedAmountInput
                : nil

            let draft = try PlanningLogic.makePaymentDraft(
                for: dueItem,
                overrideAmountMinor: overrideAmount,
                sourceWalletIDOverride: selectedWalletID
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
        } catch let error as LocalizedError {
            alertMessage = error.errorDescription ?? error.localizedDescription
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct DuePaymentPrimaryActionButton: View {
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    private var accent: Color {
        MistiaAccent.purple.color
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    isDisabled ? Color(UIColor.systemGray4) : accent,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .scaleEffect(isDisabled ? 0.98 : 1.0)
        .animation(.snappy, value: isDisabled)
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
