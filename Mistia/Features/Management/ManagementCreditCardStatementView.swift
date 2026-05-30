import SwiftData
import SwiftUI

struct ManagementCreditCardStatementView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(MistiaUIState.self) private var uiState

    let wallet: LedgerWallet
    let initialMonth: Date?

    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var allTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]

    @State private var selectedMonth: Date
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var viewID = UUID()
    @State private var isMonthPickerPresented = false

    init(wallet: LedgerWallet, initialMonth: Date? = nil) {
        self.wallet = wallet
        self.initialMonth = initialMonth
        _selectedMonth = State(initialValue: initialMonth ?? PlanningLogic.startOfMonth(for: .now))
    }

    private var transactionRecords: [TransactionRecordSnapshot] {
        allTransactions.map(\.planningRecordSnapshot)
    }

    private var occurrenceSnapshots: [PlanningDueOccurrenceSnapshot] {
        storedOccurrences.map(\.planningSnapshot)
    }

    private var accountSnapshot: PlanningCreditCardAccountSnapshot? {
        wallet.planningCreditCardSnapshot(records: transactionRecords)
    }

    private var selectedStatement: PlanningCreditCardStatementSnapshot? {
        guard let accountSnapshot else { return nil }
        return PlanningLogic.creditCardStatementItems(
            accounts: [accountSnapshot],
            records: transactionRecords,
            occurrences: occurrenceSnapshots,
            statementMonths: [selectedMonth],
            referenceDate: .now,
            calendar: calendar
        ).first
    }

    private var availableMonths: [Date] {
        let currentMonth = PlanningLogic.startOfMonth(for: .now, calendar: calendar)
        return (0...24).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
        }
    }

    private var dynamicAccentColor: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .muted,
            title: wallet.name,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 16,
            contentBottomPadding: 56,
            titleDisplayMode: .inline
        ) {
            monthMenu

            if let selectedStatement {
                statementHero(selectedStatement)
                statementTimeline(selectedStatement)
                transactionSection(
                    title: L10n.management.managementcreditcardstatement.chargesInCycle,
                    emptyText: L10n.management.managementcreditcardstatement.noChargesInThisCycle,
                    transactions: chargeTransactions(for: selectedStatement),
                    isLocked: effectiveState(for: selectedStatement) == .paid
                )
            } else {
                emptyStatementCard
            }
        }
        .alert(L10n.management.managementcreditcardstatement.notice, isPresented: $showingAlert) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            uiState.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: viewID)
        }
    }

    private var monthMenu: some View {
        Button {
            isMonthPickerPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .bold))
                Text(MistiaDateFormatting.statementMonthYearString(for: selectedMonth, calendar: calendar))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Color(UIColor.secondarySystemGroupedBackground).opacity(0.66),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isMonthPickerPresented) {
            MistiaMonthPickerSheet(
                selection: $selectedMonth,
                calendar: calendar,
                accentColor: MistiaAccent.purple.color
            )
            .presentationDetents([.height(280)])
        }
    }

    private func statementHero(_ statement: PlanningCreditCardStatementSnapshot) -> some View {
        let state = effectiveState(for: statement)

        return MistiaGlassCard(cornerRadius: 24, tint: dynamicAccentColor.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.management.managementcreditcardstatement.totalDue)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(statement.amountMinor.formattedCurrency(code: statement.currencyCode))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Button {
                    performPayment(for: statement)
                } label: {
                    HStack {
                        Image(systemName: paymentButtonIcon(state, amountMinor: statement.amountMinor))
                        Text(paymentButtonTitle(state, amountMinor: statement.amountMinor))
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(paymentButtonBackground(state), in: Capsule())
                    .foregroundStyle(paymentButtonForeground(state))
                }
                .buttonStyle(.plain)
                .disabled(!canPay(statement, state: state))
            }
            .padding(20)
        }
    }

    private func statementTimeline(_ statement: PlanningCreditCardStatementSnapshot) -> some View {
        HStack(spacing: 10) {
            timelineItem(
                title: L10n.management.managementcreditcardstatement.spend,
                value: MistiaDateFormatting.statementMonthYearString(for: statement.statementMonth, calendar: calendar),
                color: Color(hex: "#5B7BFF")
            )
            timelineItem(
                title: L10n.management.managementcreditcardstatement.close,
                value: MistiaDateFormatting.shortDateString(for: statement.closingDate),
                color: dynamicAccentColor
            )
            timelineItem(
                title: L10n.management.managementcreditcardstatement.due,
                value: MistiaDateFormatting.shortDateString(for: statement.dueDate),
                color: Color(hex: "#F59B3F")
            )
        }
    }

    private func timelineItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(UIColor.secondarySystemGroupedBackground).opacity(0.58),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func transactionSection(
        title: String,
        emptyText: String,
        transactions: [LedgerTransaction],
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            MistiaBlockCard(cornerRadius: 22, padding: 0) {
                if transactions.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(transactions.enumerated()), id: \.element.id) { index, tx in
                            TransactionRow(
                                tx: tx,
                                currencyCode: wallet.currencyCode,
                                isLocked: isLocked
                            )

                            if index < transactions.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyStatementCard: some View {
        MistiaBlockCard(cornerRadius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.management.managementcreditcardstatement.noStatementYet)
                    .font(.system(.headline, design: .rounded))
                Text(L10n.management.managementcreditcardstatement.thisCardHasNoSpendingDataFor)
                    .descriptionTextStyle()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chargeTransactions(for statement: PlanningCreditCardStatementSnapshot) -> [LedgerTransaction] {
        allTransactions.filter { tx in
            tx.sourceWallet?.id == wallet.id
                && tx.entryStatus == .posted
                && tx.primaryKind == .expense
                && calendar.isDate(tx.occurredAt, equalTo: statement.statementMonth, toGranularity: .month)
        }
        .sorted { $0.occurredAt > $1.occurredAt }
    }

    private func effectiveState(for statement: PlanningCreditCardStatementSnapshot) -> PlanningCreditCardStatementState {
        return statement.state
    }

    private func canPay(
        _ statement: PlanningCreditCardStatementSnapshot,
        state: PlanningCreditCardStatementState
    ) -> Bool {
        statement.amountMinor > 0 && (state == .payable || state == .overdue)
    }

    private func performPayment(for statement: PlanningCreditCardStatementSnapshot) {
        let state = effectiveState(for: statement)
        guard canPay(statement, state: state) else { return }

        guard let sourceWalletID = statement.paymentSourceWalletID,
              let sourceWallet = storedWallets.first(where: { $0.id == sourceWalletID }) else {
            alertMessage = L10n.management.managementcreditcardstatement.pleaseSetALinkedPaymentWalletFor
            showingAlert = true
            return
        }

        let sourceBalanceMinor = TransactionLogic.effectiveBalance(
            for: TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            ),
            records: allTransactions.map(\.snapshot)
        )

        guard sourceBalanceMinor >= statement.amountMinor else {
            alertMessage = L10n.management.managementcreditcardstatement.theLinkedWalletBalanceIsNotEnough
            showingAlert = true
            return
        }

        do {
            let draft = try PlanningLogic.makePaymentDraft(for: statement)
            let savedPayment = try PlanningPersistenceSupport.saveDuePayment(
                draft: draft,
                sourceKind: .creditCard,
                sourceID: statement.walletID,
                selectedMonth: statement.statementMonth,
                scheduledDate: statement.dueDate,
                wallets: Array(storedWallets),
                occurrences: Array(storedOccurrences),
                modelContext: modelContext,
                actorUserID: sessionStore.activeLocalProfileUserID,
                calendar: calendar
            )
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: savedPayment.transaction.id,
                modifiedAt: savedPayment.transaction.updatedAt,
                subjectUserIDOverride: savedPayment.subjectUserID
            )
            sessionStore.recordUpsert(
                entity: .dueOccurrenceRecord,
                recordID: savedPayment.occurrenceID,
                modifiedAt: savedPayment.transaction.updatedAt
            )
            alertMessage = L10n.management.managementcreditcardstatement.statementPaid
            showingAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func paymentButtonTitle(
        _ state: PlanningCreditCardStatementState,
        amountMinor: Int64
    ) -> String {
        if amountMinor <= 0, state != .unclosed {
            return L10n.management.managementcreditcardstatement.noPaymentNeeded
        }

        switch state {
        case .unclosed:
            return L10n.management.managementcreditcardstatement.notClosedYet
        case .payable:
            return L10n.management.managementcreditcardstatement.payEarly
        case .overdue:
            return L10n.management.managementcreditcardstatement.payNow
        case .paid:
            return L10n.management.managementcreditcardstatement.paid
        }
    }

    private func paymentButtonIcon(
        _ state: PlanningCreditCardStatementState,
        amountMinor: Int64
    ) -> String {
        if amountMinor <= 0, state != .unclosed {
            return "checkmark.circle.fill"
        }

        switch state {
        case .unclosed:
            return "lock.fill"
        case .payable:
            return "creditcard.fill"
        case .paid:
            return "checkmark.circle.fill"
        case .overdue:
            return "exclamationmark.circle.fill"
        }
    }

    private func paymentButtonBackground(_ state: PlanningCreditCardStatementState) -> Color {
        switch state {
        case .payable:
            return dynamicAccentColor
        case .overdue:
            return Color(hex: "#F45C7E")
        case .unclosed, .paid:
            return Color(UIColor.secondarySystemGroupedBackground).opacity(0.72)
        }
    }

    private func paymentButtonForeground(_ state: PlanningCreditCardStatementState) -> AnyShapeStyle {
        switch state {
        case .payable, .overdue:
            return AnyShapeStyle(Color.white)
        case .unclosed, .paid:
            return AnyShapeStyle(Color.secondary)
        }
    }

}

private struct TransactionRow: View {
    let tx: LedgerTransaction
    let currencyCode: String
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: tx.category?.iconSymbolName ?? tx.primaryKind.financeIconToken,
                fallbackColor: MistiaAccent.expense.color,
                size: 32
            )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rowTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(MistiaDateFormatting.shortDateString(for: tx.occurredAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(amountText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MistiaAccent.expense.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var rowTitle: String {
        tx.title.isEmpty ? (tx.category?.localizedDisplayName ?? "") : tx.title
    }

    private var amountText: String {
        "-" + tx.amountMinor.formattedCurrency(code: currencyCode)
    }
}
