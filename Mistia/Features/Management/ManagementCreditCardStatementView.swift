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
                statementSummary(selectedStatement)
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
        MistiaMonthNavigationControl(
            selection: $selectedMonth,
            calendar: calendar,
            accentColor: MistiaAccent.purple.color
        )
    }

    private func statementSummary(_ statement: PlanningCreditCardStatementSnapshot) -> some View {
        let state = effectiveState(for: statement)

        return MistiaBlockCard(cornerRadius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.management.managementcreditcardstatement.totalDue)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(statement.amountMinor.formattedCurrency(code: statement.currencyCode))
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }

                    Spacer(minLength: 8)

                    statementStatusPill(state)
                        .padding(.top, 2)
                }

                VStack(spacing: 0) {
                    statementDetailRow(
                        icon: "calendar",
                        title: L10n.management.managementcreditcardstatement.statementPeriod,
                        value: MistiaDateFormatting.statementMonthYearString(
                            for: statement.statementMonth,
                            calendar: calendar
                        )
                    )
                    Divider().padding(.leading, 34)
                    statementDetailRow(
                        icon: "lock.open",
                        title: L10n.management.managementcreditcardstatement.closingDate,
                        value: MistiaDateFormatting.shortDateString(for: statement.closingDate)
                    )
                    Divider().padding(.leading, 34)
                    statementDetailRow(
                        icon: "calendar.badge.clock",
                        title: L10n.management.managementcreditcardstatement.dueDate,
                        value: MistiaDateFormatting.shortDateString(for: statement.dueDate)
                    )
                    Divider().padding(.leading, 34)
                    statementDetailRow(
                        icon: "wallet.pass",
                        title: L10n.management.managementcreditcardstatement.linkedWallet,
                        value: linkedWalletText(for: statement)
                    )
                }
                .padding(.vertical, 2)

                Button {
                    performPayment(for: statement)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: paymentButtonIcon(state, amountMinor: statement.amountMinor))
                        Text(paymentButtonTitle(state, amountMinor: statement.amountMinor))
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        paymentButtonBackground(state),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .foregroundStyle(paymentButtonForeground(state))
                }
                .buttonStyle(.plain)
                .disabled(!canPay(statement, state: state))
                .opacity(canPay(statement, state: state) ? 1 : 0.74)
            }
        }
    }

    private func statementStatusPill(_ state: PlanningCreditCardStatementState) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statementStatusIcon(state))
                .font(.system(size: 11, weight: .bold))
            Text(statementStatusTitle(state))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(statementStatusColor(state))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            statementStatusColor(state).opacity(colorScheme == .dark ? 0.18 : 0.12),
            in: Capsule()
        )
    }

    private func statementDetailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)

            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
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
                && (
                    tx.primaryKind == .expense
                    || (
                        tx.primaryKind == .transfer
                        && tx.transferSubtype == .debt
                        && tx.debtIntent == .lend
                    )
                )
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

    private func linkedWalletText(for statement: PlanningCreditCardStatementSnapshot) -> String {
        if let name = statement.paymentSourceWalletName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return L10n.management.managementcreditcardstatement.noLinkedWallet
    }

    private func statementStatusTitle(_ state: PlanningCreditCardStatementState) -> String {
        switch state {
        case .unclosed:
            return L10n.management.managementcreditcardstatement.notClosedYet
        case .payable:
            return L10n.management.managementcreditcardstatement.payable
        case .overdue:
            return L10n.management.managementcreditcardstatement.overdue
        case .paid:
            return L10n.management.managementcreditcardstatement.paid
        }
    }

    private func statementStatusIcon(_ state: PlanningCreditCardStatementState) -> String {
        switch state {
        case .unclosed:
            return "lock.fill"
        case .payable:
            return "creditcard.fill"
        case .overdue:
            return "exclamationmark.triangle.fill"
        case .paid:
            return "checkmark.circle.fill"
        }
    }

    private func statementStatusColor(_ state: PlanningCreditCardStatementState) -> Color {
        switch state {
        case .unclosed:
            return .secondary
        case .payable:
            return dynamicAccentColor
        case .overdue:
            return Color(hex: "#D94841")
        case .paid:
            return Color(hex: "#2E9E5B")
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
            return L10n.management.managementcreditcardstatement.payNow
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
