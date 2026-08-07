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
    let ownerUserID: UUID?
}

private struct DuePaymentIconPresentation {
    let symbolName: String
    let color: Color
}

private struct DuePaymentDismissalSnapshot: Equatable {
    let amountText: String
    let selectedWalletID: UUID?
}

// MARK: - Sheet

struct DuePaymentSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query
    private var wallets: [LedgerWallet]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var occurrences: [DueOccurrenceRecord]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var bills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var installments: [InstallmentPlan]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: DuePaymentSheetTarget
    /// Called after a successful payment so the caller can mark the notification as read.
    var onPaid: (() -> Void)? = nil

    @State private var amountText = ""
    @State private var selectedWalletID: UUID?
    @State private var dismissBaselineSnapshot: DuePaymentDismissalSnapshot?
    @State private var alertMessage: String?
    @State private var showingUndoSkipAlert = false
    @State private var showingUndoPaymentAlert = false

    // MARK: - Init

    init(target: DuePaymentSheetTarget, onPaid: (() -> Void)? = nil) {
        self.target = target
        self.onPaid = onPaid
    }

    // MARK: - Computed

    private var activeCurrencyCode: String { target.currencyCode }

    private func resolvedDueItem(selectedMonth: Date) -> PlanningRecurringDueSnapshot? {
        switch target.sourceKind {
        case .recurringBill:
            guard let bill = bills.first(where: { $0.id == target.sourceID }) else { return nil }
            return PlanningLogic.recurringBillDueItem(
                bill: bill.planningSnapshot,
                occurrences: occurrences.lazy.map(\.planningSnapshot),
                selectedMonth: selectedMonth,
                calendar: calendar
            )

        case .installment:
            guard let plan = installments.first(where: { $0.id == target.sourceID }) else { return nil }
            return PlanningLogic.installmentDueItem(
                plan: plan.planningSnapshot,
                occurrences: occurrences.lazy.map(\.planningSnapshot),
                selectedMonth: selectedMonth,
                calendar: calendar
            )

        case .creditCard:
            return nil  // credit card uses statement view, not this sheet
        }
    }

    private var selectedMonthDate: Date {
        PlanningLogic.month(from: target.dueMonthKey, calendar: calendar)
            ?? PlanningLogic.startOfMonth(for: target.dueDate, calendar: calendar)
    }

    private func defaultAmountText(for dueItem: PlanningRecurringDueSnapshot?) -> String {
        guard let amount = dueItem?.amountMinor else { return "" }
        return String(amount)
    }

    private func defaultWalletID(for dueItem: PlanningRecurringDueSnapshot?) -> UUID? {
        switch target.sourceKind {
        case .recurringBill, .installment:
            return dueItem?.paymentWalletID
        case .creditCard:
            return nil
        }
    }

    private func availableWallets(for dueItem: PlanningRecurringDueSnapshot?) -> [LedgerWallet] {
        walletPickerAccess.availableWallets(
            from: wallets,
            preferredWalletIDs: Set([defaultWalletID(for: dueItem), selectedWalletID].compactMap { $0 }),
            targetOwnerUserID: target.ownerUserID ?? walletPickerAccess.currentSelfUserID,
            excludesCreditCards: target.sourceKind == .installment
        )
    }

    private var parsedAmountInput: Int64? {
        amountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
    }

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var resolvedIconPresentation: DuePaymentIconPresentation {
        let fallbackColor = colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color

        switch target.sourceKind {
        case .recurringBill:
            if let plan = bills.first(where: { $0.id == target.sourceID }) {
                let symbolName = plan.category?.iconSymbolName ?? plan.iconSymbolName
                let colorHex = plan.category?.iconColorHex ?? MistiaFinanceIconRegistry.defaultColorHex(for: symbolName)
                return DuePaymentIconPresentation(
                    symbolName: symbolName,
                    color: Color(hex: colorHex)
                )
            }
            return DuePaymentIconPresentation(
                symbolName: "mistia.plan.bill",
                color: fallbackColor
            )
        case .installment:
            if let plan = installments.first(where: { $0.id == target.sourceID }) {
                return DuePaymentIconPresentation(
                    symbolName: plan.iconSymbolName,
                    color: Color(hex: MistiaFinanceIconRegistry.defaultColorHex(for: plan.iconSymbolName))
                )
            }
            return DuePaymentIconPresentation(
                symbolName: "mistia.plan.installment",
                color: fallbackColor
            )
        case .creditCard:
            return DuePaymentIconPresentation(
                symbolName: "mistia.plan.card_bill",
                color: fallbackColor
            )
        }
    }

    private func payButtonDisabled(for dueItem: PlanningRecurringDueSnapshot?) -> Bool {
        guard dueItem != nil, selectedWalletID != nil else {
            return true
        }

        if target.requiresAmountInput {
            return (parsedAmountInput ?? 0) <= 0
        }

        return (dueItem?.amountMinor ?? 0) <= 0
    }

    private var walletFieldTitle: String {
        L10n.planning.duepayment.paymentWallet
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: .creating,
            hasUnsavedChanges: hasUnsavedChangesForDismissal
        )
    }

    private var hasUnsavedChangesForDismissal: Bool {
        guard let dismissBaselineSnapshot else { return false }
        return DuePaymentDismissalSnapshot(
            amountText: amountText.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedWalletID: selectedWalletID
        ) != dismissBaselineSnapshot
    }

    // MARK: - Body

    var body: some View {
        let selectedMonth = selectedMonthDate
        let dueItem = resolvedDueItem(selectedMonth: selectedMonth)
        let iconPresentation = resolvedIconPresentation

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        MistiaFinanceIconView(
                            icon: iconPresentation.symbolName,
                            fallbackColor: iconPresentation.color,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(paymentCycleMonthText(selectedMonth: selectedMonth))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(paymentWindowText(for: dueItem))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                paymentDetailsSection(dueItem: dueItem, iconColor: iconPresentation.color)
                paymentActionSection(dueItem: dueItem)
            }
            .navigationTitle(L10n.planning.duepayment.payBill)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MistiaGuardedDismissButton(configuration: dismissGuardConfiguration)
                }
            }
        }
        .onAppear {
            amountText = defaultAmountText(for: dueItem)
            selectedWalletID = defaultWalletID(for: dueItem)
            if dismissBaselineSnapshot == nil {
                dismissBaselineSnapshot = DuePaymentDismissalSnapshot(
                    amountText: amountText.trimmingCharacters(in: .whitespacesAndNewlines),
                    selectedWalletID: selectedWalletID
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
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
    private func paymentDetailsSection(
        dueItem: PlanningRecurringDueSnapshot?,
        iconColor: Color
    ) -> some View {
        Section {
            amountRow(dueItem: dueItem, iconColor: iconColor)
            walletMenuRow(dueItem: dueItem)
        } footer: {
            if target.requiresAmountInput {
                MistiaSectionFooter(L10n.planning.duepayment.thisBillHasNoDefaultAmount, isFormSection: true)
            }
        }
    }

    private func paymentActionSection(dueItem: PlanningRecurringDueSnapshot?) -> some View {
        Section {
            VStack(spacing: 12) {
                DuePaymentPrimaryActionButton(
                    title: L10n.planning.duepayment.payNow,
                    isDisabled: payButtonDisabled(for: dueItem)
                ) {
                    pay(dueItem: dueItem)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func amountRow(
        dueItem: PlanningRecurringDueSnapshot?,
        iconColor: Color
    ) -> some View {
        if target.requiresAmountInput {
            MistiaCurrencyInputField(
                L10n.planning.duepayment.enterAmount,
                text: $amountText,
                font: .mistiaRounded(size: 17, weight: .semibold)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
        } else if let amount = dueItem?.amountMinor {
            Text(amount.formattedCurrency(code: activeCurrencyCode))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(iconColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
    }

    private func walletMenuRow(dueItem: PlanningRecurringDueSnapshot?) -> some View {
        Picker(walletFieldTitle, selection: $selectedWalletID) {
            Text(L10n.planning.duepayment.chooseWallet).tag(Optional<UUID>.none)
            ForEach(availableWallets(for: dueItem)) { wallet in
                Text(walletPickerAccess.title(for: wallet)).tag(Optional(wallet.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func paymentWindowText(for item: PlanningRecurringDueSnapshot?) -> String {
        guard let item else {
            return MistiaDateFormatting.shortDateString(for: target.dueDate)
        }
        if item.hasExplicitDueDate {
            return "\(MistiaDateFormatting.shortDateString(for: item.paymentStartDate)) - \(MistiaDateFormatting.shortDateString(for: item.dueDate))"
        }
        return MistiaDateFormatting.shortDateString(for: item.paymentStartDate)
    }

    private func paymentCycleMonthText(selectedMonth: Date) -> String {
        L10n.planning.duepayment.paymentCycleMonth(
            MistiaDateFormatting.statementMonthYearString(
                for: selectedMonth,
                calendar: calendar
            )
        )
    }

    // MARK: - Pay

    private func pay(dueItem: PlanningRecurringDueSnapshot?) {
        guard let dueItem else {
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

    private func skip(dueItem: PlanningRecurringDueSnapshot?) {
        guard let dueItem else {
            alertMessage = L10n.planning.duepayment.couldNotFindTheDueItem
            return
        }

        guard dueItem.status == .pending else {
            dismiss()
            return
        }

        do {
            let occurrence = try PlanningPersistenceSupport.saveDueSkip(
                sourceKind: target.sourceKind,
                sourceID: target.sourceID,
                selectedMonth: selectedMonthDate,
                scheduledDate: dueItem.dueDate,
                occurrences: Array(occurrences),
                modelContext: modelContext,
                actorUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            sessionStore.recordUpsert(
                entity: .dueOccurrenceRecord,
                recordID: occurrence.id,
                modifiedAt: occurrence.updatedAt
            )
            let monthKey = PlanningLogic.monthKey(for: selectedMonthDate, calendar: calendar)
            MistiaRecurringBillMaintenance.resolveNotifications(
                for: target.sourceID,
                monthKey: monthKey,
                modelContext: modelContext
            )
            onPaid?()
            dismiss()
        } catch let error as LocalizedError {
            alertMessage = error.errorDescription ?? error.localizedDescription
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func undoSkip(dueItem: PlanningRecurringDueSnapshot?) {
        guard dueItem != nil else { return }

        do {
            if let deletedID = try PlanningPersistenceSupport.undoDueSkip(
                sourceKind: target.sourceKind,
                sourceID: target.sourceID,
                selectedMonth: selectedMonthDate,
                occurrences: Array(occurrences),
                modelContext: modelContext,
                calendar: calendar
            ) {
                sessionStore.recordDelete(entity: .dueOccurrenceRecord, recordID: deletedID, modifiedAt: .now)
            }
            onPaid?()
            dismiss()
        } catch let error as LocalizedError {
            alertMessage = error.errorDescription ?? error.localizedDescription
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func undoPayment(dueItem: PlanningRecurringDueSnapshot?) {
        guard dueItem != nil else { return }

        do {
            let undone = try PlanningPersistenceSupport.undoDuePayment(
                sourceKind: target.sourceKind,
                sourceID: target.sourceID,
                selectedMonth: selectedMonthDate,
                occurrences: Array(occurrences),
                modelContext: modelContext,
                calendar: calendar
            )
            if let deletedTxID = undone.deletedTransactionID {
                sessionStore.recordDelete(entity: .transaction, recordID: deletedTxID, modifiedAt: .now)
            }
            if let deletedOccID = undone.deletedOccurrenceID {
                sessionStore.recordDelete(entity: .dueOccurrenceRecord, recordID: deletedOccID, modifiedAt: .now)
            }
            onPaid?()
            dismiss()
        } catch let error as LocalizedError {
            alertMessage = error.errorDescription ?? error.localizedDescription
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct DuePaymentStatusCard: View {
    let title: String
    let subtitle: String?
    let iconSymbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(color)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color(UIColor.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
        MistiaProminentActionButton(
            title: title,
            iconSystemName: "creditcard.fill",
            accent: accent,
            isDisabled: isDisabled,
            action: action
        )
    }
}

struct DuePaymentSecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color(UIColor.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
