import SwiftData
import SwiftUI

enum SettlementEditorTarget: Identifiable, Equatable {
    case newSharedExpense
    case editSharedExpense(UUID)
    case viewSharedExpense(UUID)

    var id: String {
        switch self {
        case .newSharedExpense:
            return "newSharedExpense"
        case .editSharedExpense(let id):
            return "editSharedExpense-\(id.uuidString)"
        case .viewSharedExpense(let id):
            return "viewSharedExpense-\(id.uuidString)"
        }
    }
}

struct PreparingSettlementEventSheetTarget: Identifiable, Hashable {
    let groupID: UUID

    var id: UUID { groupID }
}

struct PreparingSettlementCompactChip: View {
    let event: PreparingSettlementEventSnapshot
    var showsIcon: Bool = true
    let action: () -> Void

    private var participantText: String {
        if event.participantNames.isEmpty {
            return L10n.transactions.settlement.noParticipantsYet
        }
        return event.participantNames.prefix(3).joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if showsIcon {
                    MistiaFinanceIconView(
                        icon: "mistia.settlement.event",
                        fallbackColor: MistiaAccent.purple.color,
                        size: 36
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(participantText)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(L10n.transactions.settlement.billCountValue(String(event.billCount)))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Text(event.totalPaidMinor.formattedCurrency(code: event.currencyCode))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MistiaAccent.expense.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(width: showsIcon ? 230 : 206, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.6)
                    }
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16, tint: MistiaAccent.purple.color))
    }
}

struct SettlementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query private var wallets: [LedgerWallet]
    @Query private var categories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil }, sort: \LedgerTransaction.occurredAt, order: .reverse)
    private var transactions: [LedgerTransaction]
    @Query
    private var transactionAuditRecords: [TransactionAuditRecord]
    @Query(filter: #Predicate<SettlementGroup> { $0.deletedAt == nil })
    private var settlementGroups: [SettlementGroup]
    @Query(filter: #Predicate<SettlementParticipant> { $0.deletedAt == nil }, sort: \SettlementParticipant.sortOrder)
    private var settlementParticipants: [SettlementParticipant]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"

    let target: SettlementEditorTarget
    let onEventCancelled: (() -> Void)?

    @State private var eventTitle = ""
    @State private var participantRows: [SharedExpenseParticipantDraft] = [
        SharedExpenseParticipantDraft(name: "", paidText: "")
    ]
    @State private var selectedSharedWalletID: UUID?
    @State private var selectedSharedCategoryID: UUID?
    @State private var eventNote = ""
    @State private var billRows: [SharedExpenseBillDraft] = []
    @State private var hasLoadedSharedExpenseDraft = false
    @State private var dismissBaselineSnapshot: MistiaSharedExpenseDismissalSnapshot?
    @State private var currentLinkedBillIDs: Set<UUID> = []
    @State private var initialLinkedBillIDs: Set<UUID> = []
    @State private var alertMessage: String?
    @State private var billEditorTarget: SharedExpenseBillEditorTarget?
    @State private var billSearchTarget: SharedExpenseBillSearchTarget?
    @State private var showingBillAddOptions = false
    @State private var showsResetConfirmation = false
    @FocusState private var focusedParticipantRowID: UUID?
    @State private var hiddenParticipantSuggestionRowID: UUID?
    @State private var hiddenParticipantSuggestionQuery = ""

    init(target: SettlementEditorTarget, onEventCancelled: (() -> Void)? = nil) {
        self.target = target
        self.onEventCancelled = onEventCancelled
    }

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeOwnerUserID: UUID? {
        familyContextStore.selectedSubjectUserID ?? walletPickerAccess.currentSelfUserID
    }

    private var availableWallets: [LedgerWallet] {
        walletPickerAccess.availableWallets(
            from: wallets,
            targetOwnerUserID: activeOwnerUserID,
            excludesCreditCards: true
        )
    }

    private var selectedSharedWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == selectedSharedWalletID })
    }

    private var editingSharedExpenseGroupID: UUID? {
        switch target {
        case .editSharedExpense(let groupID), .viewSharedExpense(let groupID):
            return groupID
        case .newSharedExpense:
            return nil
        }
    }

    private var editingSharedExpenseGroup: SettlementGroup? {
        guard let editingSharedExpenseGroupID else { return nil }
        return settlementGroups.first(where: { $0.id == editingSharedExpenseGroupID })
    }

    private var activeCurrencyCode: String {
        MistiaCurrencyLogic.normalizedCode(
            selectedSharedWallet?.currencyCode
                ?? editingSharedExpenseGroup?.currencyCode
                ?? availableWallets.first?.currencyCode
                ?? "JPY"
        )
    }

    private var expenseCategories: [TransactionCategory] {
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let targetOwnerUserID = activeOwnerUserID

        return categories
            .filter { category in
                guard category.deletedAt == nil,
                      !category.isArchived,
                      category.kind == .expense,
                      !category.isBalanceAdjustmentSystemCategory else {
                    return false
                }
                if let targetOwnerUserID {
                    let ownerUserID = categoryOwnerMap[category.id] ?? walletPickerAccess.currentSelfUserID
                    guard ownerUserID == targetOwnerUserID else {
                        return false
                    }
                }
                return category.parentCategory != nil || category.hierarchyRole == .child
            }
            .sorted { lhs, rhs in
                lhs.localizedDisplayName.localizedCaseInsensitiveCompare(rhs.localizedDisplayName) == .orderedAscending
            }
    }

    private var selectedSharedCategory: TransactionCategory? {
        expenseCategories.first(where: { $0.id == selectedSharedCategoryID })
    }

    private var linkedSharedExpenseBills: [LedgerTransaction] {
        transactions
            .filter {
                currentLinkedBillIDs.contains($0.id)
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var attachableExpenseTransactions: [LedgerTransaction] {
        visibleTransactionsForBillSearch
            .filter { transaction in
                guard transaction.deletedAt == nil,
                      !transaction.isArchived,
                      transaction.entryStatus == .posted,
                      transaction.settlementGroupID == nil,
                      TransactionLogic.isExpenseSpending(transaction.snapshot) else {
                    return false
                }
                if transaction.primaryKind == .expense {
                    return transaction.sourceWallet != nil && transaction.category != nil
                }
                return transaction.category != nil
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var visibleTransactionsForBillSearch: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForHistory(
            transactions,
            audits: transactionAuditRecords,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var transactionAuditMap: [UUID: TransactionAuditRecord] {
        TransactionAuditStore.auditMap(from: transactionAuditRecords)
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var transactionOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
    }

    private func settlementDebtTransactionsByParticipantKey(groupID: UUID) -> [String: [LedgerTransaction]] {
        var transactionsByKey: [String: [LedgerTransaction]] = [:]

        for transaction in transactions {
            guard transaction.settlementGroupID == groupID,
                  transaction.transferSubtype == .debt,
                  transaction.deletedAt == nil,
                  !transaction.isArchived,
                  let key = transaction.normalizedCounterpartyKey
                    ?? TransactionLogic.normalizeCounterpartyName(transaction.counterpartyName)
            else {
                continue
            }
            transactionsByKey[key, default: []].append(transaction)
        }

        return transactionsByKey
    }

    private var visibleParticipantRows: [SharedExpenseParticipantDraft] {
        participantRows.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var isReadOnlyEventDetail: Bool {
        if case .viewSharedExpense = target {
            return true
        }
        return false
    }

    private var selfParticipantDisplayName: String {
        let candidate = sessionStore.summary?.displayName
            ?? familyContextStore.displayName(for: activeOwnerUserID)
            ?? familyContextStore.displayName(for: sessionStore.activeLocalProfileUserID)
            ?? L10n.transactions.settlement.selfParticipantName
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.transactions.settlement.selfParticipantName : trimmed
    }

    private var participantNameSuggestions: [TransactionTitleSuggestion] {
        guard let rowID = focusedParticipantRowID,
              let focusedRow = participantRows.first(where: { $0.id == rowID }) else {
            return []
        }
        let query = focusedRow.name
        if rowID == hiddenParticipantSuggestionRowID,
           query.trimmingCharacters(in: .whitespacesAndNewlines) == hiddenParticipantSuggestionQuery {
            return []
        }
        let suggestionRecords = SettlementLogic.participantSuggestionRecords(
            from: transactions.map(\.snapshot),
            transactionOwnerMap: transactionOwnerMap,
            walletOwnerMap: walletOwnerMap,
            currentUserID: activeOwnerUserID
        )
        return TransactionLogic.counterpartySuggestions(
            from: suggestionRecords,
            query: query,
            limit: 5
        )
    }

    private var sharedParticipants: [SettlementParticipantInput] {
        participantRows.compactMap { row in
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return SettlementParticipantInput(
                id: row.id,
                name: name,
                paidMinor: row.paidText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
            )
        }
    }

    private var sharedResult: SettlementSharedExpenseResult {
        SettlementLogic.sharedExpenseSettlement(
            participants: sharedParticipants,
            organizerID: participantRows.first?.id ?? UUID()
        )
    }

    private var sharedParticipantNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: sharedResult.participants.map { ($0.id, $0.name) })
    }

    private var readOnlyParticipantProgressList: [ParticipantSettlementProgress] {
        guard let group = editingSharedExpenseGroup else { return [] }
        let eventParticipants = settlementParticipants
            .filter { $0.groupID == group.id && !$0.isSelf && $0.deletedAt == nil }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        let transactionsByParticipantKey = settlementDebtTransactionsByParticipantKey(groupID: group.id)

        return eventParticipants.map { participant in
            let name = participant.displayName
            let key = participant.normalizedKey ?? TransactionLogic.normalizeCounterpartyName(name) ?? ""
            let participantTransactions = transactionsByParticipantKey[key] ?? []
            let principal = participantTransactions.first {
                $0.settlementRole == .sharedExpenseReceivable || $0.settlementRole == .sharedExpensePayable
            }

            guard let principal else {
                return ParticipantSettlementProgress(
                    id: participant.id,
                    displayName: name,
                    normalizedKey: key,
                    hasDebt: false,
                    isReceivable: false,
                    originalAmount: 0,
                    paidAmount: 0,
                    remainingAmount: 0,
                    isSettled: true
                )
            }

            let isReceivable = principal.settlementRole == .sharedExpenseReceivable
            let paidAmount = participantTransactions.reduce(Int64.zero) { total, transaction in
                guard transaction.settlementRole == .sharedExpenseReceipt
                    || transaction.settlementRole == .sharedExpensePayment
                else {
                    return total
                }
                return total + max(transaction.amountMinor, 0)
            }
            let originalAmount = max(principal.amountMinor, 0)
            let remainingAmount = max(originalAmount - paidAmount, 0)
            return ParticipantSettlementProgress(
                id: participant.id,
                displayName: name,
                normalizedKey: key,
                hasDebt: true,
                isReceivable: isReceivable,
                originalAmount: originalAmount,
                paidAmount: paidAmount,
                remainingAmount: remainingAmount,
                isSettled: remainingAmount == 0
            )
        }
    }

    private var currentUserPaidMinor: Int64 {
        participantRows.first?.paidText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode) ?? 0
    }

    private var currentUserSuggestionRows: [SettlementSuggestion] {
        guard let currentUserParticipantID = participantRows.first?.id else { return [] }
        return sharedResult.suggestions.filter {
            $0.payerID == currentUserParticipantID || $0.receiverID == currentUserParticipantID
        }
    }

    private var isSaveDisabled: Bool {
        switch target {
        case .newSharedExpense, .editSharedExpense:
            return !SettlementLogic.canSavePreparingEvent(
                title: eventTitle,
                participantNames: participantRows.map(\.name)
            )
        case .viewSharedExpense:
            return true
        }
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: target == .newSharedExpense ? .creating : .editing,
            hasUnsavedChanges: isReadOnlyEventDetail ? false : hasUnsavedChangesForDismissal
        )
    }

    private var hasUnsavedChangesForDismissal: Bool {
        guard let dismissBaselineSnapshot else { return false }
        return MistiaSharedExpenseDismissalDecision.hasUnsavedChanges(
            baseline: dismissBaselineSnapshot,
            current: sharedExpenseDismissalSnapshot
        )
    }

    private var sharedExpenseDismissalSnapshot: MistiaSharedExpenseDismissalSnapshot {
        MistiaSharedExpenseDismissalSnapshot(
            eventTitle: eventTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            participantRows: participantRows.map {
                MistiaSharedExpenseParticipantDismissalSnapshot(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            },
            selectedSharedWalletID: selectedSharedWalletID,
            selectedSharedCategoryID: selectedSharedCategoryID,
            eventNote: eventNote.trimmingCharacters(in: .whitespacesAndNewlines),
            linkedBillIDs: linkedSharedExpenseBills
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString },
            billRows: billRows.map {
                MistiaSharedExpenseBillDismissalSnapshot(
                    id: $0.id,
                    modeRawValue: $0.mode.rawValue,
                    hasStagedTransaction: $0.stagedTransaction != nil,
                    existingTransactionID: $0.existingTransactionID
                )
            }
        )
    }

    var body: some View {
        switch target {
        case .newSharedExpense, .editSharedExpense, .viewSharedExpense:
            sharedExpensePreparationBody
                .onAppear(perform: applyInitialDefaults)
                .alert(
                    L10n.transactions.transactioneditor.canTSaveYet,
                    isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
                ) {
                    Button(L10n.common.ok, role: .cancel) {}
                } message: {
                    if let alertMessage {
                        Text(alertMessage)
                    }
                }
                .alert(
                    L10n.transactions.settlement.resetSplitTitle,
                    isPresented: $showsResetConfirmation
                ) {
                    Button(L10n.common.cancel, role: .cancel) {}
                    Button(L10n.transactions.settlement.resetSplitAction, role: .destructive) {
                        resetCompletedSharedExpenseToPreparing()
                    }
                } message: {
                    Text(L10n.transactions.settlement.resetSplitMessage)
                }
        }
    }

    private var navigationTitle: String {
        switch target {
        case .newSharedExpense:
            return L10n.transactions.settlement.eventTitle
        case .editSharedExpense:
            return L10n.transactions.settlement.editEventTitle
        case .viewSharedExpense:
            return L10n.transactions.settlement.eventDetailsTitle
        }
    }

    private var sharedExpensePreparationBody: some View {
        NavigationStack {
            Form {
                Section(L10n.transactions.settlement.eventName) {
                    TextField(L10n.transactions.settlement.eventName, text: $eventTitle)
                        .textInputAutocapitalization(.sentences)
                        .disabled(isReadOnlyEventDetail)
                }

                if isReadOnlyEventDetail {
                    Section(L10n.transactions.settlement.participants) {
                        readOnlySharedExpenseParticipantsContent
                    }
                } else {
                    Section {
                        sharedExpenseParticipantsContent
                    } header: {
                        sectionHeader(
                            title: L10n.transactions.settlement.participants,
                            accessibilityLabel: L10n.transactions.settlement.addParticipant
                        ) {
                            participantRows.append(SharedExpenseParticipantDraft(name: "", paidText: ""))
                        }
                    }
                }

                Section(L10n.transactions.settlement.eventBills) {
                    if isReadOnlyEventDetail {
                        readOnlyBillsContent
                    } else {
                        draftBillsContent
                    }
                }

                Section(L10n.transactions.settlement.note) {
                    TextField(L10n.transactions.settlement.notePlaceholder, text: $eventNote, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(isReadOnlyEventDetail)
                }

                if editingSharedExpenseGroup != nil {
                    MistiaDestructiveActionSection(
                        buttonTitle: L10n.transactions.settlement.archiveEvent,
                        descriptionText: L10n.transactions.settlement.archiveEventDescription,
                        popupMessage: L10n.transactions.settlement.archiveEventMessage,
                        confirmationButtonTitle: L10n.common.archive,
                        showsCancelButton: false
                    ) {
                        archiveSharedExpenseEvent()
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MistiaGuardedDismissButton(configuration: dismissGuardConfiguration)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isReadOnlyEventDetail {
                        Button {
                            showsResetConfirmation = true
                        } label: {
                            Image(systemName: "arrow.uturn.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(MistiaAccent.purple.color)
                    } else {
                        Button {
                            save()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(MistiaAccent.purple.color)
                        .disabled(isSaveDisabled)
                        .opacity(isSaveDisabled ? 0.45 : 1)
                    }
                }
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .presentationBackground(Color(UIColor.systemGroupedBackground))
        .sheet(item: $billEditorTarget, onDismiss: removeIncompleteBillRows) { target in
            TransactionEditorSheet(
                target: transactionEditorTarget(for: target),
                onComplete: { _ in
                    if let transactionID = target.transactionID,
                       let transaction = transactions.first(where: { $0.id == transactionID }) {
                        persistLinkedBillUpdate(transaction)
                    }
                },
                onStageTransaction: { transaction in
                    if let rowID = target.rowID {
                        applyStagedTransaction(transaction, toBillRow: rowID)
                    }
                },
                onPersistedTransaction: { transaction in
                    if let rowID = target.rowID {
                        applyPersistedTransaction(transaction, toBillRow: rowID)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $billSearchTarget, onDismiss: removeIncompleteBillRows) { target in
            SharedExpenseTransactionSearchSheet(
                transactions: attachableExpenseTransactions.filter { transaction in
                    !billRows.contains {
                        $0.id != target.rowID && $0.existingTransactionID == transaction.id
                    }
                },
                transactionsByID: Dictionary(
                    uniqueKeysWithValues: attachableExpenseTransactions.map { ($0.id, $0) }
                ),
                transactionAuditMap: transactionAuditMap,
                walletOwnerMap: walletOwnerMap,
                transactionOwnerMap: transactionOwnerMap,
                primaryCurrencyCode: primaryCurrencyCode,
                exchangeRateIndex: MistiaExchangeRateIndex(rates: MistiaCurrencySettings.rates())
            ) { transaction in
                applyExistingTransaction(transaction, toBillRow: target.rowID)
                billSearchTarget = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .confirmationDialog(
            L10n.transactions.settlement.addExpenseToEvent,
            isPresented: $showingBillAddOptions,
            titleVisibility: .visible
        ) {
            Button(L10n.transactions.settlement.addNewExpense) {
                beginAddingBill(mode: .newExpense)
            }
            Button(L10n.transactions.settlement.chooseExistingExpense) {
                beginAddingBill(mode: .existingExpense)
            }
            Button(L10n.common.cancel, role: .cancel) {}
        }
    }

    @ViewBuilder
    private var sharedExpenseParticipantsContent: some View {
        ForEach($participantRows) { $row in
            HStack(spacing: 10) {
                TextField(L10n.transactions.settlement.participantName, text: $row.name)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedParticipantRowID, equals: row.id)
                    .onChange(of: row.name) { _, newValue in
                        clearHiddenParticipantSuggestionIfNeeded(
                            rowID: row.id,
                            query: newValue
                        )
                    }
                    .onSubmit {
                        ensureTrailingParticipantRow()
                    }

                if participantRows.count > 1 {
                    Button {
                        removeParticipantRow(row.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !participantNameSuggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(participantNameSuggestions) { suggestion in
                        Button {
                            applyParticipantSuggestion(suggestion.title)
                        } label: {
                            Text(suggestion.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(MistiaAccent.purple.color.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private var readOnlySharedExpenseParticipantsContent: some View {
        let progressList = readOnlyParticipantProgressList
        if progressList.isEmpty {
            SettlementEventExpenseEmptyState(
                title: L10n.transactions.settlement.noParticipantsYet,
                message: L10n.transactions.settlement.addParticipantsInEventEditor,
                buttonTitle: nil,
                accent: MistiaAccent.purple.color,
                symbols: ["person.2.fill", "calendar.badge.clock", "checklist"]
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        } else {
            ForEach(progressList) { progress in
                SharedExpenseReadOnlyParticipantRow(
                    progress: progress,
                    currencyCode: activeCurrencyCode
                )
            }
        }
    }

    private func sectionHeader(
        title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var draftBillsContent: some View {
        let contentfulBillRows = billRows.filter { $0.hasContent }
        if linkedSharedExpenseBills.isEmpty && contentfulBillRows.isEmpty {
            SettlementEventExpenseEmptyState(
                title: L10n.transactions.settlement.noBillsYet,
                message: L10n.transactions.settlement.addExpensesToTrackEventCost,
                buttonTitle: L10n.transactions.settlement.addExpense,
                accent: MistiaAccent.purple.color,
                symbols: ["receipt.fill", "wallet.pass.fill", "person.2.fill", "plus"]
            ) {
                showingBillAddOptions = true
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        } else {
            ForEach(linkedSharedExpenseBills) { bill in
                Button {
                    billEditorTarget = SharedExpenseBillEditorTarget(transactionID: bill.id)
                } label: {
                    TransactionCashflowRow(
                        record: bill.snapshot,
                        transaction: bill,
                        auditRecord: transactionAuditMap[bill.id],
                        walletOwnerMap: walletOwnerMap,
                        transactionOwnerMap: transactionOwnerMap,
                        familyContextStore: familyContextStore,
                        hasFamilyOwnerConflict: false,
                        primaryCurrencyCode: primaryCurrencyCode,
                        exchangeRateIndex: MistiaExchangeRateIndex(rates: MistiaCurrencySettings.rates()),
                        subtitleLineLimit: 1,
                        showsAuditSubtitle: false
                    )
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        detachBillDraft(bill)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L10n.common.delete)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))

                SharedExpenseBillCategoryPickerRow(
                    selectedCategoryID: bill.category?.id,
                    selectedCategoryLabel: categoryLabel(for: bill.category?.id),
                    categories: expenseCategories,
                    categoryLabel: categoryLabel(for:)
                ) { categoryID in
                    updateLinkedBillCategory(bill, categoryID: categoryID)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 8, trailing: 14))
            }

            ForEach($billRows) { $row in
                if row.hasContent {
                    SharedExpenseBillDraftRow(
                        row: $row,
                        existingTransactions: attachableExpenseTransactions,
                        transactionAuditMap: transactionAuditMap,
                        walletOwnerMap: walletOwnerMap,
                        transactionOwnerMap: transactionOwnerMap,
                        primaryCurrencyCode: primaryCurrencyCode,
                        exchangeRateIndex: MistiaExchangeRateIndex(rates: MistiaCurrencySettings.rates()),
                        familyContextStore: familyContextStore,
                        currencyCode: activeCurrencyCode,
                        categories: expenseCategories,
                        categoryLabel: categoryLabel(for:),
                        onTap: { billEditorTarget = SharedExpenseBillEditorTarget(rowID: row.id) },
                        onCategoryChange: { categoryID in
                            updateDraftBillRowCategory(row.id, categoryID: categoryID)
                        },
                        onRemove: { removeBillRow(row.id) }
                    )
                }
            }

            MistiaFooterAddButton(
                title: L10n.transactions.settlement.addExpense,
                accent: MistiaAccent.purple.color
            ) {
                showingBillAddOptions = true
            }
            .padding(.vertical, 10)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
        }
    }

    @ViewBuilder
    private var readOnlyBillsContent: some View {
        if linkedSharedExpenseBills.isEmpty {
            SettlementEventExpenseEmptyState(
                title: L10n.transactions.settlement.noBillsYet,
                message: L10n.transactions.settlement.addExpensesToTrackEventCost,
                buttonTitle: nil,
                accent: MistiaAccent.purple.color,
                symbols: ["receipt.fill", "wallet.pass.fill", "person.2.fill", "checkmark.seal.fill"]
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        } else {
            ForEach(linkedSharedExpenseBills) { bill in
                TransactionCashflowRow(
                    record: bill.snapshot,
                    transaction: bill,
                    auditRecord: transactionAuditMap[bill.id],
                    walletOwnerMap: walletOwnerMap,
                    transactionOwnerMap: transactionOwnerMap,
                    familyContextStore: familyContextStore,
                    hasFamilyOwnerConflict: false,
                    primaryCurrencyCode: primaryCurrencyCode,
                    exchangeRateIndex: MistiaExchangeRateIndex(rates: MistiaCurrencySettings.rates()),
                    subtitleLineLimit: 1,
                    showsAuditSubtitle: false
                )
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
            }
        }
    }

    private func walletPicker(
        title: String,
        selection: Binding<UUID?>
    ) -> some View {
        Picker(title, selection: selection) {
            Text(L10n.planning.duepayment.chooseWallet).tag(Optional<UUID>.none)
            ForEach(availableWallets) { wallet in
                Text(walletPickerAccess.title(for: wallet)).tag(Optional(wallet.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func categoryPicker(selection: Binding<UUID?>) -> some View {
        Picker(L10n.transactions.settlement.category, selection: selection) {
            Text(L10n.transactions.transactioneditor.chooseCategory).tag(Optional<UUID>.none)
            ForEach(expenseCategories) { category in
                Text(categoryLabel(for: category)).tag(Optional(category.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func categoryLabel(for category: TransactionCategory) -> String {
        if let parent = category.parentCategory {
            return "\(parent.localizedDisplayName) / \(category.localizedDisplayName)"
        }
        return category.localizedDisplayName
    }

    private func categoryLabel(for categoryID: UUID?) -> String {
        guard let categoryID,
              let category = expenseCategories.first(where: { $0.id == categoryID }) else {
            return L10n.transactions.transactioneditor.chooseCategory
        }
        return categoryLabel(for: category)
    }

    private func existingTransactionLabel(for transaction: LedgerTransaction) -> String {
        "\(transaction.localizedTransactionTitle) • \(transaction.amountMinor.formattedCurrency(code: transaction.sourceCurrencyCode ?? activeCurrencyCode))"
    }

    private func transactionEditorTarget(for target: SharedExpenseBillEditorTarget) -> TransactionEditorTarget {
        if let transactionID = target.transactionID,
           let transaction = transactions.first(where: { $0.id == transactionID }) {
            return TransactionEditorTarget(transaction: transaction)
        }

        guard let rowID = target.rowID else {
            return TransactionEditorTarget(
                initialKind: .expense,
                prefill: TransactionEditorPrefill(
                    title: nil,
                    amountMinor: nil,
                    occurredAt: Date(),
                    sourceWalletID: selectedSharedWalletID,
                    categoryID: selectedSharedCategoryID
                ),
                subjectUserIDOverride: activeOwnerUserID
            )
        }

        if let existingTransactionID = billRows.first(where: { $0.id == rowID })?.existingTransactionID,
           let transaction = transactions.first(where: { $0.id == existingTransactionID }) {
            return TransactionEditorTarget(transaction: transaction)
        }

        let stagedTransaction = billRows.first(where: { $0.id == rowID })?.stagedTransaction
        if let stagedTransaction {
            return TransactionEditorTarget(
                transaction: stagedTransaction
            )
        }
        return TransactionEditorTarget(
            initialKind: .expense,
            prefill: TransactionEditorPrefill(
                title: nil,
                amountMinor: nil,
                occurredAt: Date(),
                sourceWalletID: selectedSharedWalletID,
                categoryID: selectedSharedCategoryID
            ),
            subjectUserIDOverride: activeOwnerUserID
        )
    }

    private func applyStagedTransaction(_ transaction: LedgerTransaction, toBillRow rowID: UUID) {
        guard let index = billRows.firstIndex(where: { $0.id == rowID }) else { return }
        billRows[index].mode = .newExpense
        billRows[index].stagedTransaction = transaction
        billRows[index].existingTransactionID = nil
        selectedSharedWalletID = transaction.sourceWallet?.id ?? selectedSharedWalletID
        selectedSharedCategoryID = transaction.category?.id ?? selectedSharedCategoryID
    }

    private func applyPersistedTransaction(_ transaction: LedgerTransaction, toBillRow rowID: UUID) {
        guard let index = billRows.firstIndex(where: { $0.id == rowID }) else { return }
        billRows[index].mode = .existingExpense
        billRows[index].existingTransactionID = transaction.id
        billRows[index].stagedTransaction = nil
        selectedSharedWalletID = transaction.sourceWallet?.id ?? selectedSharedWalletID
        selectedSharedCategoryID = transaction.category?.id ?? selectedSharedCategoryID
    }

    private func applyExistingTransaction(_ transaction: LedgerTransaction, toBillRow rowID: UUID) {
        guard let index = billRows.firstIndex(where: { $0.id == rowID }) else { return }
        billRows[index].mode = .existingExpense
        billRows[index].existingTransactionID = transaction.id
        billRows[index].stagedTransaction = nil
    }

    private func updateLinkedBillCategory(_ bill: LedgerTransaction, categoryID: UUID?) {
        let category = categoryID.flatMap { selectedID in
            expenseCategories.first { $0.id == selectedID }
        }
        guard bill.category?.id != category?.id else { return }
        bill.category = category
        persistLinkedBillUpdate(bill)
    }

    private func updateDraftBillRowCategory(_ rowID: UUID, categoryID: UUID?) {
        guard let index = billRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }
        let category = categoryID.flatMap { selectedID in
            expenseCategories.first { $0.id == selectedID }
        }

        switch billRows[index].mode {
        case .newExpense:
            billRows[index].stagedTransaction?.category = category
        case .existingExpense:
            guard let existingTransactionID = billRows[index].existingTransactionID,
                  let transaction = transactions.first(where: { $0.id == existingTransactionID }),
                  transaction.category?.id != category?.id else {
                return
            }
            transaction.category = category
        }
    }

    private func sharedParticipantName(for id: UUID) -> String {
        sharedParticipantNameByID[id] ?? L10n.transactions.settlement.participantName
    }

    private func applyInitialDefaults() {
        if !hasLoadedSharedExpenseDraft {
            loadSharedExpenseDraftIfNeeded()
        }
        if selectedSharedWalletID == nil {
            selectedSharedWalletID = availableWallets.first?.id
        }
        if selectedSharedCategoryID == nil {
            selectedSharedCategoryID = expenseCategories.first?.id
        }
        if dismissBaselineSnapshot == nil {
            dismissBaselineSnapshot = sharedExpenseDismissalSnapshot
        }
    }

    private func markLinkedBillDetachedInDismissBaseline(_ billID: UUID) {
        guard let baseline = dismissBaselineSnapshot else { return }
        dismissBaselineSnapshot = MistiaSharedExpenseDismissalSnapshot(
            eventTitle: baseline.eventTitle,
            participantRows: baseline.participantRows,
            selectedSharedWalletID: baseline.selectedSharedWalletID,
            selectedSharedCategoryID: baseline.selectedSharedCategoryID,
            eventNote: baseline.eventNote,
            linkedBillIDs: baseline.linkedBillIDs
                .filter { $0 != billID }
                .sorted { $0.uuidString < $1.uuidString },
            billRows: baseline.billRows
        )
    }

    private func loadSharedExpenseDraftIfNeeded() {
        hasLoadedSharedExpenseDraft = true
        guard editingSharedExpenseGroupID != nil,
              let group = editingSharedExpenseGroup else {
            return
        }

        // Initialize linked bill IDs first
        let dbLinked = transactions.filter {
            $0.settlementGroupID == group.id
                && SettlementLogic.isSharedExpenseEventBill($0)
        }
        let dbLinkedIDs = Set(dbLinked.map(\.id))
        initialLinkedBillIDs = dbLinkedIDs
        currentLinkedBillIDs = dbLinkedIDs

        eventTitle = group.title
        eventNote = group.note ?? ""
        let rows = settlementParticipants
            .filter { $0.groupID == group.id && !$0.isSelf && $0.deletedAt == nil }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .map { SharedExpenseParticipantDraft(id: $0.id, name: $0.displayName, paidText: "") }
        participantRows = rows.isEmpty ? [SharedExpenseParticipantDraft(name: "", paidText: "")] : rows
        selectedSharedWalletID = linkedSharedExpenseBills.first?.sourceWallet?.id ?? availableWallets.first?.id
        selectedSharedCategoryID = linkedSharedExpenseBills.first?.category?.id ?? expenseCategories.first?.id
        billRows = []
    }

    private func ensureTrailingParticipantRow() {
        guard participantRows.last?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        participantRows.append(SharedExpenseParticipantDraft(name: "", paidText: ""))
    }

    private func removeParticipantRow(_ id: UUID) {
        guard participantRows.count > 1 else { return }
        let removedFocusedRow = focusedParticipantRowID == id
        participantRows.removeAll { $0.id == id }
        if participantRows.isEmpty {
            participantRows = [SharedExpenseParticipantDraft(name: "", paidText: "")]
        }
        if removedFocusedRow {
            focusedParticipantRowID = nil
        }
        if hiddenParticipantSuggestionRowID == id {
            hiddenParticipantSuggestionRowID = nil
            hiddenParticipantSuggestionQuery = ""
        }
    }

    private func applyParticipantSuggestion(_ name: String) {
        let targetIndex: Int?
        if let focusedParticipantRowID,
           let index = participantRows.firstIndex(where: { $0.id == focusedParticipantRowID }) {
            targetIndex = index
        } else if let index = participantRows.lastIndex(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            targetIndex = index
        } else {
            targetIndex = participantRows.indices.last
        }
        guard let targetIndex else { return }
        participantRows[targetIndex].name = name
        hiddenParticipantSuggestionRowID = participantRows[targetIndex].id
        hiddenParticipantSuggestionQuery = name.trimmingCharacters(in: .whitespacesAndNewlines)
        focusedParticipantRowID = participantRows[targetIndex].id
    }

    private func clearHiddenParticipantSuggestionIfNeeded(rowID: UUID, query: String) {
        guard rowID == hiddenParticipantSuggestionRowID else { return }
        if query.trimmingCharacters(in: .whitespacesAndNewlines) != hiddenParticipantSuggestionQuery {
            hiddenParticipantSuggestionRowID = nil
            hiddenParticipantSuggestionQuery = ""
        }
    }

    private func beginAddingBill(mode: SharedExpenseBillDraftMode) {
        let row = SharedExpenseBillDraft(mode: mode)
        billRows.append(row)
        switch mode {
        case .newExpense:
            billEditorTarget = SharedExpenseBillEditorTarget(rowID: row.id)
        case .existingExpense:
            billSearchTarget = SharedExpenseBillSearchTarget(rowID: row.id)
        }
    }

    private func removeBillRow(_ id: UUID) {
        billRows.removeAll { $0.id == id }
    }

    private func removeIncompleteBillRows() {
        billRows.removeAll { !$0.hasContent }
    }

    private func normalizedParticipantNames() -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for row in participantRows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = TransactionLogic.normalizeCounterpartyName(name) ?? name.localizedLowercase
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(name)
        }
        return names
    }

    private func resolvedSharedExpenseOwnerUserID() -> UUID? {
        for row in billRows where row.mode == .newExpense {
            if let wallet = row.stagedTransaction?.sourceWallet,
               let owner = walletPickerAccess.walletOwnerUserID(for: wallet) {
                return owner
            }
        }
        if let selectedSharedWallet,
           let owner = walletPickerAccess.walletOwnerUserID(for: selectedSharedWallet) {
            return owner
        }
        return activeOwnerUserID
    }

    private func upsertPreparingParticipants(
        groupID: UUID,
        participantNames: [String],
        ownerUserID: UUID?,
        modifiedAt: Date
    ) -> [SettlementParticipant] {
        let existing = settlementParticipants.filter { $0.groupID == groupID }
        let selfParticipant = existing.first(where: { $0.isSelf }) ?? SettlementParticipant(
            groupID: groupID,
            displayName: selfParticipantDisplayName,
            normalizedKey: TransactionLogic.normalizeCounterpartyName(selfParticipantDisplayName),
            memberUserID: ownerUserID,
            isSelf: true,
            sortOrder: 0,
            createdAt: modifiedAt,
            updatedAt: modifiedAt
        )
        if existing.first(where: { $0.id == selfParticipant.id }) == nil {
            modelContext.insert(selfParticipant)
        }
        selfParticipant.displayName = selfParticipantDisplayName
        selfParticipant.normalizedKey = TransactionLogic.normalizeCounterpartyName(selfParticipantDisplayName)
        selfParticipant.memberUserID = ownerUserID
        selfParticipant.isSelf = true
        selfParticipant.sortOrder = 0
        selfParticipant.deletedAt = nil
        selfParticipant.updatedAt = modifiedAt

        var participants = [selfParticipant]
        let existingByKey = Dictionary(
            existing.filter { !$0.isSelf }.compactMap { participant -> (String, SettlementParticipant)? in
                let key = participant.normalizedKey ?? TransactionLogic.normalizeCounterpartyName(participant.displayName)
                guard let key else { return nil }
                return (key, participant)
            },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        )
        var activeKeys: Set<String> = []

        for (offset, name) in participantNames.enumerated() {
            let key = TransactionLogic.normalizeCounterpartyName(name) ?? name.localizedLowercase
            activeKeys.insert(key)
            let participant = existingByKey[key] ?? SettlementParticipant(
                groupID: groupID,
                displayName: name,
                normalizedKey: key,
                memberUserID: nil,
                isSelf: false,
                sortOrder: offset + 1,
                createdAt: modifiedAt,
                updatedAt: modifiedAt
            )
            if existing.first(where: { $0.id == participant.id }) == nil {
                modelContext.insert(participant)
            }
            participant.groupID = groupID
            participant.displayName = name
            participant.normalizedKey = key
            participant.isSelf = false
            participant.sortOrder = offset + 1
            participant.deletedAt = nil
            participant.updatedAt = modifiedAt
            participants.append(participant)
        }

        for participant in existing where !participant.isSelf {
            let key = participant.normalizedKey ?? TransactionLogic.normalizeCounterpartyName(participant.displayName)
            if key.map(activeKeys.contains) != true {
                participant.deletedAt = modifiedAt
                participant.updatedAt = modifiedAt
                participants.append(participant)
            }
        }

        if let ownerUserID {
            for participant in participants {
                try? MistiaRecordOwnershipStore.upsert(
                    entity: .settlementParticipant,
                    recordID: participant.id,
                    ownerUserID: ownerUserID,
                    updatedAt: modifiedAt,
                    context: modelContext
                )
            }
        }

        return participants
    }

    private func makeSharedExpenseBillTransaction(
        from row: SharedExpenseBillDraft,
        groupID: UUID,
        defaultTitle: String,
        now: Date
    ) -> LedgerTransaction? {
        guard let transaction = row.stagedTransaction,
              transaction.amountMinor > 0,
              transaction.sourceWallet != nil,
              transaction.category != nil else {
            return nil
        }

        transaction.primaryKind = .expense
        transaction.entryStatus = .posted
        if transaction.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transaction.title = defaultTitle
        }
        transaction.settlementGroupID = groupID
        transaction.settlementObligationID = nil
        transaction.settlementRole = .sharedExpensePaid
        transaction.reportingExpenseMinor = max(transaction.amountMinor, 0)
        transaction.reportingIncomeMinor = 0
        transaction.updatedAt = now
        return transaction
    }

    private func transactionsForTotal(groupID: UUID, createdTransactions: [LedgerTransaction]) -> [LedgerTransaction] {
        let existing = transactions.filter {
            $0.settlementGroupID == groupID
                && SettlementLogic.isSharedExpenseEventBill($0)
        }
        let existingIDs = Set(existing.map(\.id))
        return existing + createdTransactions.filter { !existingIDs.contains($0.id) }
    }

    private func save() {
        switch target {
        case .newSharedExpense, .editSharedExpense:
            saveSharedExpense()
        case .viewSharedExpense:
            break
        }
    }

    private func saveSharedExpense() {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            alertMessage = L10n.transactions.settlement.enterEventName
            return
        }
        let participantNames = normalizedParticipantNames()

        let now = Date()
        let ownerUserID = resolvedSharedExpenseOwnerUserID()
        let group: SettlementGroup
        let shouldDismissAfterSave: Bool

        switch target {
        case .newSharedExpense:
            group = SettlementGroup(
                kind: .sharedExpense,
                status: .preparing,
                title: title,
                currencyCode: activeCurrencyCode,
                occurredAt: now,
                totalMinor: 0,
                expectedMinor: 0,
                settledMinor: 0,
                organizerUserID: ownerUserID,
                note: eventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(group)
            shouldDismissAfterSave = true
        case .editSharedExpense:
            guard let existingGroup = editingSharedExpenseGroup else {
                alertMessage = L10n.transactions.settlement.settlementNotFound
                return
            }
            group = existingGroup
            group.title = title
            group.currencyCode = activeCurrencyCode
            group.note = eventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            group.updatedAt = now
            shouldDismissAfterSave = true
        case .viewSharedExpense:
            return
        }

        let participants = upsertPreparingParticipants(
            groupID: group.id,
            participantNames: participantNames,
            ownerUserID: ownerUserID,
            modifiedAt: now
        )

        // 1. Process detached bills (those in initial but not current)
        let detachedBillIDs = initialLinkedBillIDs.subtracting(currentLinkedBillIDs)
        var detachedBills: [LedgerTransaction] = []
        for billID in detachedBillIDs {
            if let bill = transactions.first(where: { $0.id == billID }) {
                let billOwnerUserID = bill.sourceWallet.flatMap { walletPickerAccess.walletOwnerUserID(for: $0) } ?? ownerUserID
                bill.settlementGroupID = nil
                bill.settlementObligationID = nil
                bill.settlementRoleRawValue = nil
                bill.reportingExpenseMinor = nil
                bill.reportingIncomeMinor = nil
                bill.updatedAt = now
                if let billOwnerUserID {
                    try? MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: bill.id,
                        ownerUserID: billOwnerUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
                detachedBills.append(bill)
            }
        }

        // 2. Process newly added/linked bills
        var newlyCreatedTransactions: [LedgerTransaction] = []
        var newlyAttachedTransactions: [LedgerTransaction] = []

        for row in billRows {
            switch row.mode {
            case .newExpense:
                guard let transaction = makeSharedExpenseBillTransaction(from: row, groupID: group.id, defaultTitle: title, now: now) else {
                    continue
                }
                modelContext.insert(transaction)
                newlyCreatedTransactions.append(transaction)
            case .existingExpense:
                guard let existingID = row.existingTransactionID,
                      let transaction = attachableExpenseTransactions.first(where: { $0.id == existingID }) else {
                    continue
                }
                transaction.settlementGroupID = group.id
                transaction.settlementRole = .sharedExpensePaid
                transaction.reportingExpenseMinor = max(transaction.amountMinor, 0)
                transaction.reportingIncomeMinor = 0
                transaction.updatedAt = now
                newlyAttachedTransactions.append(transaction)
            }
        }

        // 3. Recalculate group total using all active linked bills
        let allLinkedBills = linkedSharedExpenseBills + newlyCreatedTransactions + newlyAttachedTransactions
        let linkedTotal = allLinkedBills.reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
        group.totalMinor = linkedTotal
        group.expectedMinor = 0
        group.settledMinor = 0
        group.status = .preparing
        group.updatedAt = now

        // 4. Save and register sync mutations
        persistPreparedSharedExpense(
            group: group,
            participants: participants,
            transactions: newlyCreatedTransactions + newlyAttachedTransactions + detachedBills,
            ownerUserID: ownerUserID,
            modifiedAt: now,
            dismissAfterSave: shouldDismissAfterSave
        )
    }

    private func persistPreparedSharedExpense(
        group: SettlementGroup,
        participants: [SettlementParticipant],
        transactions: [LedgerTransaction],
        ownerUserID: UUID?,
        modifiedAt: Date,
        dismissAfterSave: Bool
    ) {
        do {
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: modifiedAt,
                    context: modelContext
                )
                for participant in participants {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .settlementParticipant,
                        recordID: participant.id,
                        ownerUserID: ownerUserID,
                        updatedAt: modifiedAt,
                        context: modelContext
                    )
                }
            }

            let actorUserID = sessionStore.activeLocalProfileUserID ?? ownerUserID
            for transaction in transactions {
                if let actorUserID {
                    try TransactionAuditStore.upsert(
                        transactionID: transaction.id,
                        createdByUserID: actorUserID,
                        lastModifiedByUserID: actorUserID,
                        updatedAt: modifiedAt,
                        context: modelContext
                    )
                }
                if let transactionOwnerUserID = transaction.sourceWallet.flatMap({ walletPickerAccess.walletOwnerUserID(for: $0) }) ?? ownerUserID {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: transaction.id,
                        ownerUserID: transactionOwnerUserID,
                        updatedAt: modifiedAt,
                        context: modelContext
                    )
                }
            }

            try modelContext.save()
            queueUpserts(
                group: group,
                participants: participants,
                transactions: transactions,
                ownerUserID: ownerUserID,
                modifiedAt: modifiedAt
            )
            if dismissAfterSave {
                dismiss()
            } else {
                billRows = []
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func detachBillDraft(_ bill: LedgerTransaction) {
        currentLinkedBillIDs.remove(bill.id)
    }

    private func detachBill(_ bill: LedgerTransaction) {
        guard let groupID = bill.settlementGroupID,
              let group = settlementGroups.first(where: { $0.id == groupID }) else {
            return
        }

        let now = Date()
        let ownerUserID = bill.sourceWallet.flatMap { walletPickerAccess.walletOwnerUserID(for: $0) } ?? activeOwnerUserID
        bill.settlementGroupID = nil
        bill.settlementObligationID = nil
        bill.settlementRoleRawValue = nil
        bill.reportingExpenseMinor = nil
        bill.reportingIncomeMinor = nil
        bill.updatedAt = now
        group.totalMinor = transactions
            .filter {
                $0.id != bill.id
                    && $0.settlementGroupID == groupID
                    && SettlementLogic.isSharedExpenseEventBill($0)
            }
            .reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
        group.updatedAt = now

        do {
            let actorUserID = sessionStore.activeLocalProfileUserID ?? ownerUserID
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction,
                    recordID: bill.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }
            if let actorUserID {
                try TransactionAuditStore.touch(
                    transactionID: bill.id,
                    actorUserID: actorUserID,
                    fallbackCreatedByUserID: actorUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }
            try modelContext.save()
            queueUpserts(
                group: group,
                participants: [],
                transactions: [bill],
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
            markLinkedBillDetachedInDismissBaseline(bill.id)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func persistLinkedBillUpdate(_ bill: LedgerTransaction) {
        guard let group = editingSharedExpenseGroup
            ?? bill.settlementGroupID.flatMap({ groupID in settlementGroups.first(where: { $0.id == groupID }) })
        else {
            return
        }

        let now = Date()
        let ownerUserID = bill.sourceWallet.flatMap { walletPickerAccess.walletOwnerUserID(for: $0) } ?? activeOwnerUserID
        bill.settlementGroupID = group.id
        bill.settlementObligationID = nil
        bill.settlementRole = .sharedExpensePaid
        bill.reportingExpenseMinor = max(bill.amountMinor, 0)
        bill.reportingIncomeMinor = 0
        bill.updatedAt = now

        group.totalMinor = transactions
            .filter {
                $0.id != bill.id
                    && $0.settlementGroupID == group.id
                    && SettlementLogic.isSharedExpenseEventBill($0)
            }
            .reduce(max(bill.amountMinor, 0)) { $0 + max($1.amountMinor, 0) }
        group.updatedAt = now

        do {
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction,
                    recordID: bill.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }
            try modelContext.save()
            queueUpserts(
                group: group,
                participants: [],
                transactions: [bill],
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func archiveSharedExpenseEvent() {
        guard let group = editingSharedExpenseGroup else {
            alertMessage = L10n.transactions.settlement.settlementNotFound
            return
        }

        let now = Date()
        let ownerUserID = eventOwnerUserID(for: group)
        group.isArchived = true
        group.archivedAt = now
        group.updatedAt = now

        do {
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }

            try modelContext.save()
            queueUpserts(group: group, transactions: [], ownerUserID: ownerUserID, modifiedAt: now)
            onEventCancelled?()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func resetCompletedSharedExpenseToPreparing() {
        guard let group = editingSharedExpenseGroup else {
            alertMessage = L10n.transactions.settlement.settlementNotFound
            return
        }

        let now = Date()
        let ownerUserID = eventOwnerUserID(for: group)
        let groupTransactions = transactions.filter { $0.settlementGroupID == group.id && $0.deletedAt == nil }
        var updatedBills: [LedgerTransaction] = []
        var deletedGeneratedTransactions: [LedgerTransaction] = []

        for transaction in groupTransactions {
            if transaction.settlementRole == .sharedExpensePaid {
                transaction.reportingExpenseMinor = max(transaction.amountMinor, 0)
                transaction.reportingIncomeMinor = 0
                transaction.updatedAt = now
                updatedBills.append(transaction)
            } else if TransactionLogic.isEventGeneratedSharedExpenseDebt(transaction.snapshot) {
                transaction.deletedAt = now
                transaction.isArchived = true
                transaction.updatedAt = now
                deletedGeneratedTransactions.append(transaction)
            }
        }

        group.expectedMinor = 0
        group.settledMinor = 0
        group.status = .preparing
        group.isArchived = false
        group.archivedAt = nil
        group.updatedAt = now

        do {
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }

            let actorUserID = sessionStore.activeLocalProfileUserID ?? ownerUserID
            for transaction in updatedBills + deletedGeneratedTransactions {
                if let transactionOwnerUserID = eventTransactionOwnerUserID(for: transaction, fallback: ownerUserID) {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: transaction.id,
                        ownerUserID: transactionOwnerUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
                if let actorUserID {
                    try TransactionAuditStore.touch(
                        transactionID: transaction.id,
                        actorUserID: actorUserID,
                        fallbackCreatedByUserID: actorUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
            }

            try modelContext.save()
            queueEventResetToPreparing(
                group: group,
                updatedBills: updatedBills,
                deletedGeneratedTransactions: deletedGeneratedTransactions,
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func eventOwnerUserID(for group: SettlementGroup) -> UUID? {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementGroup)
        return ownerMap[group.id] ?? group.organizerUserID ?? activeOwnerUserID
    }

    private func eventTransactionOwnerUserID(
        for transaction: LedgerTransaction,
        fallback: UUID?
    ) -> UUID? {
        transaction.sourceWallet.flatMap { walletPickerAccess.walletOwnerUserID(for: $0) } ?? fallback
    }

    private func queueEventCancellation(
        group: SettlementGroup,
        participants: [SettlementParticipant],
        detachedBills: [LedgerTransaction],
        deletedTransactions: [LedgerTransaction],
        ownerUserID: UUID?,
        modifiedAt: Date
    ) {
        guard let ownerUserID else { return }
        var mutations: [MistiaSyncMutation] = [
            MistiaSyncMutation(
                entity: .settlementGroup,
                recordID: group.id,
                subjectUserID: ownerUserID,
                kind: .delete,
                modifiedAt: modifiedAt,
                baseVersion: group.remoteVersion
            )
        ]
        mutations.append(
            contentsOf: participants.map {
                MistiaSyncMutation(
                    entity: .settlementParticipant,
                    recordID: $0.id,
                    subjectUserID: ownerUserID,
                    kind: .delete,
                    modifiedAt: modifiedAt,
                    baseVersion: $0.remoteVersion
                )
            }
        )
        mutations.append(
            contentsOf: detachedBills.compactMap { transaction in
                guard let transactionOwnerUserID = eventTransactionOwnerUserID(for: transaction, fallback: ownerUserID) else {
                    return nil
                }
                return MistiaSyncMutation(
                    entity: .transaction,
                    recordID: transaction.id,
                    subjectUserID: transactionOwnerUserID,
                    kind: .upsert,
                    modifiedAt: modifiedAt,
                    baseVersion: transaction.remoteVersion
                )
            }
        )
        mutations.append(
            contentsOf: deletedTransactions.compactMap { transaction in
                guard let transactionOwnerUserID = eventTransactionOwnerUserID(for: transaction, fallback: ownerUserID) else {
                    return nil
                }
                return MistiaSyncMutation(
                    entity: .transaction,
                    recordID: transaction.id,
                    subjectUserID: transactionOwnerUserID,
                    kind: .delete,
                    modifiedAt: modifiedAt,
                    baseVersion: transaction.remoteVersion
                )
            }
        )
        sessionStore.recordMutations(mutations)
        if mutations.contains(where: { $0.subjectUserID != sessionStore.activeLocalProfileUserID }) {
            Task { @MainActor in
                _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
            }
        }
    }

    private func queueEventResetToPreparing(
        group: SettlementGroup,
        updatedBills: [LedgerTransaction],
        deletedGeneratedTransactions: [LedgerTransaction],
        ownerUserID: UUID?,
        modifiedAt: Date
    ) {
        guard let ownerUserID else { return }

        var mutations: [MistiaSyncMutation] = [
            MistiaSyncMutation(
                entity: .settlementGroup,
                recordID: group.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: group.remoteVersion
            )
        ]
        mutations.append(
            contentsOf: updatedBills.compactMap { transaction in
                guard let transactionOwnerUserID = eventTransactionOwnerUserID(for: transaction, fallback: ownerUserID) else {
                    return nil
                }
                return MistiaSyncMutation(
                    entity: .transaction,
                    recordID: transaction.id,
                    subjectUserID: transactionOwnerUserID,
                    kind: .upsert,
                    modifiedAt: modifiedAt,
                    baseVersion: transaction.remoteVersion
                )
            }
        )
        mutations.append(
            contentsOf: deletedGeneratedTransactions.compactMap { transaction in
                guard let transactionOwnerUserID = eventTransactionOwnerUserID(for: transaction, fallback: ownerUserID) else {
                    return nil
                }
                return MistiaSyncMutation(
                    entity: .transaction,
                    recordID: transaction.id,
                    subjectUserID: transactionOwnerUserID,
                    kind: .delete,
                    modifiedAt: modifiedAt,
                    baseVersion: transaction.remoteVersion
                )
            }
        )

        sessionStore.recordMutations(mutations)
        if mutations.contains(where: { $0.subjectUserID != sessionStore.activeLocalProfileUserID }) {
            Task { @MainActor in
                _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
            }
        }
    }

    private func queueUpserts(
        group: SettlementGroup,
        participants: [SettlementParticipant] = [],
        transactions: [LedgerTransaction],
        ownerUserID: UUID?,
        modifiedAt: Date
    ) {
        guard let ownerUserID else { return }
        var mutations: [MistiaSyncMutation] = [
            MistiaSyncMutation(
                entity: .settlementGroup,
                recordID: group.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: group.remoteVersion
            )
        ]
        mutations.append(
            contentsOf: participants.map {
                MistiaSyncMutation(
                    entity: .settlementParticipant,
                    recordID: $0.id,
                    subjectUserID: ownerUserID,
                    kind: .upsert,
                    modifiedAt: modifiedAt,
                    baseVersion: $0.remoteVersion
                )
            }
        )
        mutations.append(
            contentsOf: transactions.map {
                MistiaSyncMutation(
                    entity: .transaction,
                    recordID: $0.id,
                    subjectUserID: ownerUserID,
                    kind: .upsert,
                    modifiedAt: modifiedAt,
                    baseVersion: $0.remoteVersion
                )
            }
        )
        sessionStore.recordMutations(mutations)
        if ownerUserID != sessionStore.activeLocalProfileUserID {
            Task { @MainActor in
                _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
            }
        }
    }
}

private struct SharedExpenseBillEditorTarget: Identifiable, Hashable {
    let rowID: UUID?
    let transactionID: UUID?

    var id: String {
        if let rowID {
            return "row-\(rowID.uuidString)"
        }
        if let transactionID {
            return "transaction-\(transactionID.uuidString)"
        }
        return "empty"
    }

    init(rowID: UUID) {
        self.rowID = rowID
        self.transactionID = nil
    }

    init(transactionID: UUID) {
        self.rowID = nil
        self.transactionID = transactionID
    }
}

private struct SharedExpenseBillSearchTarget: Identifiable, Hashable {
    let rowID: UUID

    var id: UUID { rowID }
}

private struct SharedExpenseTransactionSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isSearchPresented = false

    let transactions: [LedgerTransaction]
    let transactionsByID: [UUID: LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let primaryCurrencyCode: String
    let exchangeRateIndex: MistiaExchangeRateIndex
    let onSelect: (LedgerTransaction) -> Void

    private var snapshot: TransactionsListSnapshot? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = filteredTransactions(searchText: trimmed).map(\.snapshot)
        return TransactionsListSnapshot(
            activeTransactionCount: transactions.count,
            visibleRecordCount: records.count,
            displayedRecordCount: records.count,
            hasAdjustments: false,
            debtCounterpartyFilterOptions: [],
            preparingSettlementEvents: [],
            allSettlementEvents: [],
            openDebtPositions: [],
            openReceivableDebtTotals: [],
            sections: TransactionLogic.sections(
                from: records,
                assumesSortedByRecency: true
            ),
            transactionsByID: transactionsByID,
            transactionAuditMap: transactionAuditMap,
            walletOwnerMap: walletOwnerMap,
            transactionOwnerMap: transactionOwnerMap,
            archivedSettlementGroupIDs: []
        )
    }

    var body: some View {
        NavigationStack {
            TransactionsSearchScene(
                searchText: searchText,
                snapshot: snapshot,
                transactionsByID: transactionsByID,
                transactionAuditMap: transactionAuditMap,
                walletOwnerMap: walletOwnerMap,
                transactionOwnerMap: transactionOwnerMap,
                primaryCurrencyCode: primaryCurrencyCode,
                exchangeRateIndex: exchangeRateIndex,
                showsExpenseMinusSign: false,
                displaysSnapshotWithoutSearchQuery: true,
                searchNoResultsMessage: L10n.transactions.settlement.searchNoResultsMessage,
                onSelect: onSelect,
                onLoadMore: { _ in }
            )
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.transactions.settlement.searchExpenseNamePrompt
            )
            .onChange(of: isSearchPresented) { _, newValue in
                if !newValue {
                    dismiss()
                }
            }
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
            isSearchPresented = true
        }
        .presentationBackground(Color(UIColor.systemGroupedBackground))
    }

    private func filteredTransactions(searchText: String) -> [LedgerTransaction] {
        guard !searchText.isEmpty else {
            return Array(transactions.prefix(20))
        }

        let normalized = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return transactions.filter { transaction in
            [
                transaction.localizedTransactionTitle,
                transaction.note ?? "",
                transaction.category?.localizedDisplayName ?? "",
                transaction.sourceWallet?.name ?? "",
                transaction.counterpartyName ?? ""
            ]
            .contains {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .contains(normalized)
            }
        }
    }
}

struct ParticipantSettlementProgress: Identifiable {
    let id: UUID
    let displayName: String
    let normalizedKey: String
    let hasDebt: Bool
    let isReceivable: Bool
    let originalAmount: Int64
    let paidAmount: Int64
    let remainingAmount: Int64
    let isSettled: Bool
}

private struct ParticipantSettlementProgressRow: View {
    let progress: ParticipantSettlementProgress
    let currencyCode: String
    
    private var isReceivable: Bool {
        progress.isReceivable
    }
    
    private var amountColor: Color {
        if !progress.hasDebt || progress.isSettled {
            return MistiaAccent.income.color
        }
        return isReceivable ? MistiaAccent.debtLend.color : MistiaAccent.debtBorrow.color
    }
    
    private var icon: String {
        if !progress.hasDebt || progress.isSettled {
            return "checkmark.circle.fill"
        }
        return isReceivable ? TransactionDebtIntent.lend.financeIconToken : TransactionDebtIntent.borrow.financeIconToken
    }
    
    private var title: String {
        progress.displayName
    }
    
    private var subtitle: String {
        if !progress.hasDebt {
            return L10n.transactions.settlement.participantSettled
        }
        if progress.isSettled {
            return L10n.transactions.settlement.participantSettled
        }
        
        let paidFormatted = progress.paidAmount.formattedCurrency(code: currencyCode)
        let remainingFormatted = progress.remainingAmount.formattedCurrency(code: currencyCode)
        let paidText = isReceivable
            ? L10n.transactions.settlement.participantCollectedValue(String(describing: paidFormatted))
            : L10n.transactions.settlement.participantPaidValue(String(describing: paidFormatted))
        let remainingText = L10n.transactions.settlement.participantRemainingValue(String(describing: remainingFormatted))
        
        return "\(paidText) • \(remainingText)"
    }
    
    private var amountText: String {
        if !progress.hasDebt || progress.isSettled {
            return L10n.transactions.settlement.settled
        }
        let remainingFormatted = progress.remainingAmount.formattedCurrency(code: currencyCode)
        return isReceivable ? "+\(remainingFormatted)" : "-\(remainingFormatted)"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: icon,
                fallbackColor: amountColor,
                size: 36
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 12)
            
            Text(amountText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .contentShape(Rectangle())
    }
}

private struct SharedExpenseReadOnlyParticipantRow: View {
    let progress: ParticipantSettlementProgress
    let currencyCode: String

    private var amountColor: Color {
        if !progress.hasDebt || progress.isSettled {
            return MistiaAccent.income.color
        }
        return progress.isReceivable ? MistiaAccent.debtLend.color : MistiaAccent.debtBorrow.color
    }

    private var icon: String {
        if !progress.hasDebt || progress.isSettled {
            return "checkmark.circle.fill"
        }
        return progress.isReceivable ? TransactionDebtIntent.lend.financeIconToken : TransactionDebtIntent.borrow.financeIconToken
    }

    private var subtitle: String {
        guard progress.hasDebt else {
            return L10n.transactions.settlement.participantSettled
        }
        let paidText = progress.paidAmount.formattedCurrency(code: currencyCode)
        return progress.isReceivable
            ? L10n.transactions.settlement.participantCollectedValue(String(describing: paidText))
            : L10n.transactions.settlement.participantPaidValue(String(describing: paidText))
    }

    private var amountText: String {
        guard progress.hasDebt else {
            return L10n.transactions.settlement.settled
        }
        return progress.remainingAmount.formattedCurrency(code: currencyCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: icon,
                fallbackColor: amountColor,
                size: 34
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(progress.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(amountText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .contentShape(Rectangle())
    }
}

struct SettlementSplitCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query(filter: #Predicate<SettlementGroup> { $0.deletedAt == nil })
    private var groups: [SettlementGroup]
    @Query(filter: #Predicate<SettlementParticipant> { $0.deletedAt == nil }, sort: \SettlementParticipant.sortOrder)
    private var participants: [SettlementParticipant]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var transactions: [LedgerTransaction]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
    private var wallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: PreparingSettlementEventSheetTarget
    let onEdit: (UUID) -> Void

    @State private var additionalRows: [SharedExpenseParticipantDraft] = []
    @State private var paidTextsByParticipantID: [UUID: String] = [:]
    @State private var debtAmountTextsBySuggestionID: [SettlementSuggestionID: String] = [:]
    @State private var dismissBaselinePaidTextsByParticipantID: [UUID: String] = [:]
    @State private var dismissBaselineDebtAmountTextsBySuggestionID: [SettlementSuggestionID: String] = [:]
    @State private var editingDebtSuggestionID: SettlementSuggestionID?
    @State private var editingDebtAmountText = ""
    @State private var alertMessage: String?
    @State private var debtSettlementTarget: DebtSettlementSheetTarget?
    @State private var showsResetConfirmation = false

    private var group: SettlementGroup? {
        groups.first(where: { $0.id == target.groupID })
    }

    private var groupParticipants: [SettlementParticipant] {
        participants
            .filter { $0.groupID == target.groupID && $0.deletedAt == nil }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var selfParticipant: SettlementParticipant? {
        groupParticipants.first(where: \.isSelf)
    }

    private var nonSelfParticipants: [SettlementParticipant] {
        groupParticipants.filter { !$0.isSelf }
    }

    private var linkedBills: [LedgerTransaction] {
        transactions
            .filter {
                $0.settlementGroupID == target.groupID
                    && SettlementLogic.isSharedExpenseEventBill($0)
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var defaultSharedExpensePrincipalCategory: TransactionCategory? {
        guard let categoryID = SettlementLogic.sharedExpenseDefaultCategoryID(
            from: linkedBills.map(\.snapshot)
        ) else {
            return nil
        }
        return linkedBills.compactMap(\.category).first { $0.id == categoryID }
    }

    private var selfPaidMinor: Int64 {
        linkedBills.reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
    }

    private var currencyCode: String {
        MistiaCurrencyLogic.normalizedCode(group?.currencyCode ?? linkedBills.first?.sourceCurrencyCode ?? "JPY")
    }

    private var allInputsProvided: Bool {
        guard !nonSelfParticipants.isEmpty else { return false }
        return nonSelfParticipants.allSatisfy {
            if let text = paidTextsByParticipantID[$0.id] {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
    }

    private var participantInputs: [SettlementParticipantInput] {
        guard let selfParticipant else { return [] }
        var inputs = [
            SettlementParticipantInput(
                id: selfParticipant.id,
                name: selfParticipant.displayName,
                paidMinor: selfPaidMinor
            )
        ]
        inputs += nonSelfParticipants.map {
            SettlementParticipantInput(
                id: $0.id,
                name: $0.displayName,
                paidMinor: paidTextsByParticipantID[$0.id, default: ""].currencyInputToMinorUnits(currencyCode: currencyCode)
            )
        }
        return inputs
    }

    private var canFinalizeSplit: Bool {
        !nonSelfParticipants.isEmpty
            && allInputsProvided
            && editingDebtSuggestionID == nil
    }

    private var splitResult: SettlementSharedExpenseResult {
        SettlementLogic.sharedExpenseSettlement(
            participants: participantInputs,
            organizerID: selfParticipant?.id ?? UUID()
        )
    }

    private var automaticSuggestionsForSelf: [SettlementSuggestion] {
        guard allInputsProvided else { return [] }
        guard let selfID = selfParticipant?.id else { return [] }
        return splitResult.suggestions.filter {
            $0.payerID == selfID || $0.receiverID == selfID
        }
    }

    private var effectiveSuggestionsForSelf: [SettlementSuggestion] {
        SettlementLogic.applyingDebtAmountOverrides(
            to: automaticSuggestionsForSelf,
            overridesBySuggestionID: debtAmountOverridesBySuggestionID
        )
    }

    private var debtAmountOverridesBySuggestionID: [SettlementSuggestionID: Int64] {
        var overrides: [SettlementSuggestionID: Int64] = [:]
        for (suggestionID, text) in debtAmountTextsBySuggestionID {
            let amountMinor = text.currencyInputToMinorUnits(currencyCode: currencyCode)
            if amountMinor > 0 {
                overrides[suggestionID] = amountMinor
            }
        }
        return overrides
    }

    private var participantNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: participantInputs.map { ($0.id, $0.name) })
    }

    private var ownerUserID: UUID? {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementGroup)
        return ownerMap[target.groupID] ?? group?.organizerUserID ?? familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
    }

    private var isFinalized: Bool {
        if let status = group?.status {
            return status == .open || status == .partiallySettled || status == .settled
        }
        return false
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: .editing,
            hasUnsavedChanges: !isFinalized
                && (
                    paidTextsByParticipantID != dismissBaselinePaidTextsByParticipantID
                        || debtAmountTextsBySuggestionID != dismissBaselineDebtAmountTextsBySuggestionID
                        || editingDebtSuggestionID != nil
                )
        )
    }

    private func participantSettlementProgressList() -> [ParticipantSettlementProgress] {
        let transactionsByParticipantKey = settlementDebtTransactionsByParticipantKey()

        return nonSelfParticipants.map { participant in
            let name = participant.displayName
            let key = participant.normalizedKey ?? TransactionLogic.normalizeCounterpartyName(name) ?? ""
            let participantTxs = transactionsByParticipantKey[key] ?? []
            
            let principalTx = participantTxs.first {
                $0.settlementRole == .sharedExpenseReceivable || $0.settlementRole == .sharedExpensePayable
            }
            
            if let principalTx {
                let isReceivable = principalTx.settlementRole == .sharedExpenseReceivable
                let originalAmount = principalTx.amountMinor
                let paidAmount = participantTxs.reduce(Int64.zero) { total, transaction in
                    guard transaction.settlementRole == .sharedExpenseReceipt
                        || transaction.settlementRole == .sharedExpensePayment
                    else {
                        return total
                    }
                    return total + transaction.amountMinor
                }
                let remainingAmount = max(0, originalAmount - paidAmount)
                return ParticipantSettlementProgress(
                    id: participant.id,
                    displayName: name,
                    normalizedKey: key,
                    hasDebt: true,
                    isReceivable: isReceivable,
                    originalAmount: originalAmount,
                    paidAmount: paidAmount,
                    remainingAmount: remainingAmount,
                    isSettled: remainingAmount == 0
                )
            } else {
                return ParticipantSettlementProgress(
                    id: participant.id,
                    displayName: name,
                    normalizedKey: key,
                    hasDebt: false,
                    isReceivable: false,
                    originalAmount: 0,
                    paidAmount: 0,
                    remainingAmount: 0,
                    isSettled: true
                )
            }
        }
    }

    private func settlementDebtTransactionsByParticipantKey() -> [String: [LedgerTransaction]] {
        var transactionsByKey: [String: [LedgerTransaction]] = [:]
        transactionsByKey.reserveCapacity(nonSelfParticipants.count)

        for transaction in transactions {
            guard transaction.settlementGroupID == target.groupID,
                  transaction.transferSubtype == .debt,
                  transaction.deletedAt == nil,
                  !transaction.isArchived,
                  let key = transaction.normalizedCounterpartyKey
                    ?? TransactionLogic.normalizeCounterpartyName(transaction.counterpartyName)
            else {
                continue
            }

            transactionsByKey[key, default: []].append(transaction)
        }

        return transactionsByKey
    }

    private func openDebtSettlement(forParticipantKey normalizedKey: String, displayName: String) {
        guard let position = debtPosition(forParticipantKey: normalizedKey, displayName: displayName) else {
            return
        }
        debtSettlementTarget = DebtSettlementSheetTarget(position: position)
    }

    private func debtPosition(
        forParticipantKey normalizedKey: String,
        displayName: String
    ) -> CounterpartyDebtSnapshot? {
        let existingRecords = transactions
            .filter {
                $0.settlementGroupID == target.groupID
                    && $0.transferSubtype == .debt
                    && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == normalizedKey
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .map(\.snapshot)
        
        let netMinor = existingRecords.reduce(Int64.zero) { total, record in
            switch record.debtIntent {
            case .lend:
                return total + record.amountMinor
            case .collect:
                return total - record.amountMinor
            case .borrow:
                return total - record.amountMinor
            case .repay:
                return total + record.amountMinor
            case nil:
                return total
            }
        }
        guard netMinor != 0 else { return nil }

        return CounterpartyDebtSnapshot(
            id: "\(normalizedKey)|\(currencyCode)|\(target.groupID.uuidString)",
            displayName: displayName,
            normalizedCounterpartyKey: normalizedKey,
            netMinor: netMinor,
            currencyCode: currencyCode,
            preferredWalletID: linkedBills.first?.sourceWallet?.id ?? wallets.first?.id,
            relatedRecords: existingRecords.sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    private func resetSplitToPreparing() {
        guard let group else { return }
        let now = Date()
        let groupTxs = transactions.filter { $0.settlementGroupID == group.id && $0.deletedAt == nil }
        for tx in groupTxs {
            if tx.settlementRole == .sharedExpensePaid {
                tx.reportingExpenseMinor = max(tx.amountMinor, 0)
                tx.reportingIncomeMinor = 0
            } else {
                tx.deletedAt = now
                tx.isArchived = true
            }
            tx.updatedAt = now
        }
        group.expectedMinor = 0
        group.settledMinor = 0
        group.status = .preparing
        group.isArchived = false
        group.archivedAt = nil
        group.updatedAt = now
        do {
            try modelContext.save()
            paidTextsByParticipantID = [:]
            debtAmountTextsBySuggestionID = [:]
            dismissBaselinePaidTextsByParticipantID = [:]
            dismissBaselineDebtAmountTextsBySuggestionID = [:]
            editingDebtSuggestionID = nil
            editingDebtAmountText = ""
            initializePaidInputsIfNeeded()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                splitSummarySection

                if isFinalized {
                    paymentProgressSection
                } else {
                    participantInputSection
                    splitSuggestionSection
                }
            }
            .navigationTitle(group?.title ?? L10n.transactions.settlement.sharedExpenseTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MistiaGuardedDismissButton(configuration: dismissGuardConfiguration)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isFinalized {
                        Button {
                            finalizeSplit()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(MistiaAccent.purple.color)
                        .disabled(!canFinalizeSplit)
                        .opacity(canFinalizeSplit ? 1 : 0.45)
                    }
                }
            }
        }
        .onAppear(perform: initializePaidInputsIfNeeded)
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .presentationBackground(Color(UIColor.systemGroupedBackground))

        .sheet(item: $debtSettlementTarget) { target in
            DebtSettlementSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .alert(
            L10n.transactions.transactioneditor.canTSaveYet,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L10n.common.ok, role: .cancel) {}
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
        }
        .alert(
            L10n.transactions.settlement.resetSplitTitle,
            isPresented: $showsResetConfirmation
        ) {
            Button(L10n.common.cancel, role: .cancel) {}
            Button(L10n.transactions.settlement.resetSplitAction, role: .destructive) {
                resetSplitToPreparing()
            }
        } message: {
            Text(L10n.transactions.settlement.resetSplitMessage)
        }
    }

    private var splitSummarySection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.transactions.settlement.totalPaid)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selfPaidMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(MistiaAccent.expense.color)
            }

            Button {
                onEdit(target.groupID)
                dismiss()
            } label: {
                Label(L10n.management.management.edit, systemImage: "pencil")
            }
            .disabled(isFinalized)
            .opacity(isFinalized ? 0.45 : 1)

            if isFinalized {
                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    Label(L10n.transactions.settlement.recalculateSplit, systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private var paymentProgressSection: some View {
        Section(L10n.transactions.settlement.paymentProgress) {
            ForEach(participantSettlementProgressList()) { progress in
                if progress.hasDebt && !progress.isSettled {
                    Button {
                        openDebtSettlement(forParticipantKey: progress.normalizedKey, displayName: progress.displayName)
                    } label: {
                        ParticipantSettlementProgressRow(progress: progress, currencyCode: currencyCode)
                    }
                    .buttonStyle(.plain)
                } else {
                    ParticipantSettlementProgressRow(progress: progress, currencyCode: currencyCode)
                }
            }
        }
    }

    private var participantInputSection: some View {
        Section(L10n.transactions.settlement.participants) {
            if nonSelfParticipants.isEmpty {
                SettlementEventExpenseEmptyState(
                    title: L10n.transactions.settlement.noParticipantsYet,
                    message: L10n.transactions.settlement.addParticipantsInEventEditor,
                    buttonTitle: nil,
                    accent: MistiaAccent.purple.color,
                    symbols: ["person.2.fill", "calendar.badge.clock", "checklist"]
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            } else {
                ForEach(nonSelfParticipants) { participant in
                    SharedExpenseParticipantPaidInputRow(
                        participantName: participant.displayName,
                        paidText: paidTextBinding(for: participant)
                    )
                }
            }
        }
    }

    private var splitSuggestionSection: some View {
        Section(L10n.transactions.settlement.sharedExpenseTitle) {
            splitSuggestionContent
        }
    }

    @ViewBuilder
    private var splitSuggestionContent: some View {
        if !allInputsProvided {
            Text(L10n.transactions.settlement.enterAllParticipantAmounts)
                .foregroundStyle(.secondary)
                .italic()
                .font(.system(size: 14, design: .rounded))
        } else {
            if effectiveSuggestionsForSelf.isEmpty {
                Text(L10n.transactions.settlement.noSettlementNeeded)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(effectiveSuggestionsForSelf) { suggestion in
                    settlementSuggestionRow(for: suggestion)
                }
            }

            if !debtAmountTextsBySuggestionID.isEmpty {
                Button {
                    resetDebtAmountsToAutomatic()
                } label: {
                    Label(
                        L10n.transactions.settlement.recalculateSplit,
                        systemImage: "arrow.counterclockwise"
                    )
                }
            }
        }
    }

    private var summaryCard: some View {
        MistiaBlockCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.transactions.settlement.totalPaid)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(selfPaidMinor.formattedCurrency(code: currencyCode))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(MistiaAccent.expense.color)
                    }
                    Spacer()
                    Button {
                        onEdit(target.groupID)
                        dismiss()
                    } label: {
                        Label(L10n.management.management.edit, systemImage: "pencil")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                }

                Text(L10n.transactions.settlement.selfPaidLocked)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func paidTextBinding(for participant: SettlementParticipant) -> Binding<String> {
        Binding(
            get: { paidTextsByParticipantID[participant.id, default: ""] },
            set: { paidTextsByParticipantID[participant.id] = $0 }
        )
    }

    private func beginEditingDebt(_ suggestion: SettlementSuggestion) {
        editingDebtAmountText = MistiaCurrencyInputFormatting.groupedInput(
            String(suggestion.amountMinor)
        )
        editingDebtSuggestionID = suggestion.id
    }

    private func commitEditingDebt(for suggestion: SettlementSuggestion) {
        let amountMinor = editingDebtAmountText.currencyInputToMinorUnits(currencyCode: currencyCode)
        guard amountMinor > 0 else {
            alertMessage = L10n.transactions.settlement.enterAmountsGreaterThanZero
            return
        }

        let automaticAmountMinor = automaticSuggestionsForSelf
            .first(where: { $0.id == suggestion.id })?
            .amountMinor
        if amountMinor == automaticAmountMinor {
            debtAmountTextsBySuggestionID.removeValue(forKey: suggestion.id)
        } else {
            debtAmountTextsBySuggestionID[suggestion.id] =
                MistiaCurrencyInputFormatting.groupedInput(String(amountMinor))
        }
        editingDebtSuggestionID = nil
        editingDebtAmountText = ""
    }

    private func resetDebtAmountsToAutomatic() {
        debtAmountTextsBySuggestionID = [:]
        editingDebtSuggestionID = nil
        editingDebtAmountText = ""
    }

    private func settlementSuggestionRow(for suggestion: SettlementSuggestion) -> some View {
        SharedExpenseSuggestionActionRow(
            suggestion: suggestion,
            selfParticipantID: selfParticipant?.id,
            name: name(for: counterpartyID(for: suggestion)),
            currencyCode: currencyCode,
            isEditing: editingDebtSuggestionID == suggestion.id,
            isAnotherRowEditing: editingDebtSuggestionID != nil
                && editingDebtSuggestionID != suggestion.id,
            editingText: $editingDebtAmountText,
            onOpen: { openDebtSettlement(for: suggestion) },
            onEdit: { beginEditingDebt(suggestion) },
            onSave: { commitEditingDebt(for: suggestion) }
        )
    }

    private func counterpartyID(for suggestion: SettlementSuggestion) -> UUID {
        suggestion.payerID == selfParticipant?.id ? suggestion.receiverID : suggestion.payerID
    }

    private func initializePaidInputsIfNeeded() {
        for participant in nonSelfParticipants where paidTextsByParticipantID[participant.id] == nil {
            paidTextsByParticipantID[participant.id] = ""
        }
        if dismissBaselinePaidTextsByParticipantID.isEmpty {
            dismissBaselinePaidTextsByParticipantID = paidTextsByParticipantID
        }
        if dismissBaselineDebtAmountTextsBySuggestionID.isEmpty {
            dismissBaselineDebtAmountTextsBySuggestionID = debtAmountTextsBySuggestionID
        }
    }

    private func openDebtSettlement(for suggestion: SettlementSuggestion) {
        let principalTransactions = finalizeSplit(dismissAfterSave: false)
        guard let position = debtPosition(for: suggestion, principalTransactions: principalTransactions) else {
            return
        }
        debtSettlementTarget = DebtSettlementSheetTarget(position: position)
    }

    private func debtPosition(
        for suggestion: SettlementSuggestion,
        principalTransactions: [LedgerTransaction]
    ) -> CounterpartyDebtSnapshot? {
        guard let selfID = selfParticipant?.id else { return nil }
        let isReceivable = suggestion.receiverID == selfID
        let counterpartyID = isReceivable ? suggestion.payerID : suggestion.receiverID
        let counterpartyName = name(for: counterpartyID)
        guard let normalizedKey = TransactionLogic.normalizeCounterpartyName(counterpartyName) else {
            return nil
        }

        let existingRecords = transactions
            .filter {
                $0.settlementGroupID == target.groupID
                    && $0.transferSubtype == .debt
                    && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == normalizedKey
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .map(\.snapshot)
        let newRecords = principalTransactions
            .filter {
                $0.settlementGroupID == target.groupID
                    && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == normalizedKey
            }
            .map(\.snapshot)
        let records = existingRecords + newRecords
        let netMinor = records.reduce(Int64.zero) { total, record in
            switch record.debtIntent {
            case .lend:
                return total + record.amountMinor
            case .collect:
                return total - record.amountMinor
            case .borrow:
                return total - record.amountMinor
            case .repay:
                return total + record.amountMinor
            case nil:
                return total
            }
        }
        guard netMinor != 0 else { return nil }

        return CounterpartyDebtSnapshot(
            id: "\(normalizedKey)|\(currencyCode)|\(target.groupID.uuidString)",
            displayName: counterpartyName,
            normalizedCounterpartyKey: normalizedKey,
            netMinor: netMinor,
            currencyCode: currencyCode,
            preferredWalletID: linkedBills.first?.sourceWallet?.id ?? wallets.first?.id,
            relatedRecords: records.sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    private var peopleCard: some View {
        MistiaBlockCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.transactions.settlement.participants)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        additionalRows.append(SharedExpenseParticipantDraft(name: "", paidText: ""))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(splitResult.participants) { participant in
                    SharedExpenseParticipantResultRow(
                        participant: participant,
                        currencyCode: currencyCode
                    )
                }

                ForEach($additionalRows) { $row in
                    TextField(L10n.transactions.settlement.participantName, text: $row.name)
                        .textInputAutocapitalization(.sentences)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    private var suggestionsCard: some View {
        MistiaBlockCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.transactions.settlement.settlementSuggestions)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if effectiveSuggestionsForSelf.isEmpty {
                    Text(L10n.transactions.settlement.noSettlementNeeded)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(effectiveSuggestionsForSelf) { suggestion in
                        HStack {
                            Text(verbatim: "\(name(for: suggestion.payerID)) → \(name(for: suggestion.receiverID))")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(suggestion.amountMinor.formattedCurrency(code: currencyCode))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                    }
                }
            }
        }
    }

    private func name(for id: UUID) -> String {
        participantNameByID[id] ?? L10n.transactions.settlement.participantName
    }

    @discardableResult
    private func finalizeSplit(dismissAfterSave: Bool = true) -> [LedgerTransaction] {
        guard let group, let selfParticipant else {
            alertMessage = L10n.transactions.settlement.settlementNotFound
            return []
        }
        guard !nonSelfParticipants.isEmpty else {
            alertMessage = L10n.transactions.settlement.enterParticipant
            return []
        }
        guard allInputsProvided else {
            alertMessage = L10n.transactions.settlement.enterAllParticipantAmounts
            return []
        }
        let now = Date()
        let ownerUserID = ownerUserID
        let currentSelfID = selfParticipant.id
        let defaultPrincipalCategory = defaultSharedExpensePrincipalCategory
        var principalTransactions: [LedgerTransaction] = []
        var reconciledPrincipalIDs: Set<UUID> = []

        for suggestion in effectiveSuggestionsForSelf {
            let isReceivable = suggestion.receiverID == currentSelfID
            let counterpartyID = isReceivable ? suggestion.payerID : suggestion.receiverID
            let counterpartyName = name(for: counterpartyID)
            let normalizedKey = TransactionLogic.normalizeCounterpartyName(counterpartyName)
            let debtIntent: TransactionDebtIntent = isReceivable ? .lend : .borrow
            let role: SettlementTransactionRole = isReceivable ? .sharedExpenseReceivable : .sharedExpensePayable
            let reportingOverride = SettlementLogic.sharedExpensePrincipalReportingOverride(
                settlementRole: role,
                amountMinor: suggestion.amountMinor,
                categoryID: defaultPrincipalCategory?.id
            )
            let existingTransaction = existingPrincipalDebt(
                groupID: group.id,
                normalizedCounterpartyKey: normalizedKey
            )
            let transaction = existingTransaction ?? LedgerTransaction(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: debtIntent,
                entryStatus: .posted,
                title: debtIntent.title,
                amountMinor: suggestion.amountMinor,
                settlementGroupID: group.id,
                settlementRole: role,
                reportingExpenseMinor: reportingOverride.expenseMinor,
                reportingIncomeMinor: reportingOverride.incomeMinor,
                sourceCurrencyCode: currencyCode,
                occurredAt: now,
                createdAt: now,
                updatedAt: now,
                sourceWallet: nil,
                category: defaultPrincipalCategory,
                counterpartyName: counterpartyName,
                normalizedCounterpartyKey: normalizedKey
            )

            if existingTransaction == nil {
                modelContext.insert(transaction)
            }
            transaction.primaryKind = .transfer
            transaction.transferSubtype = .debt
            transaction.debtIntent = debtIntent
            transaction.title = debtIntent.title
            transaction.amountMinor = suggestion.amountMinor
            transaction.settlementGroupID = group.id
            transaction.settlementRole = role
            transaction.reportingExpenseMinor = reportingOverride.expenseMinor
            transaction.reportingIncomeMinor = reportingOverride.incomeMinor
            transaction.sourceCurrencyCode = currencyCode
            transaction.sourceWallet = nil
            transaction.destinationWallet = nil
            transaction.category = defaultPrincipalCategory
            transaction.counterpartyName = counterpartyName
            transaction.normalizedCounterpartyKey = normalizedKey
            transaction.updatedAt = now
            transaction.deletedAt = nil
            transaction.isArchived = false
            principalTransactions.append(transaction)
            reconciledPrincipalIDs.insert(transaction.id)
        }

        let stalePrincipalTransactions = existingPrincipalDebtTransactions(groupID: group.id)
            .filter { !reconciledPrincipalIDs.contains($0.id) }
        for transaction in stalePrincipalTransactions {
            transaction.updatedAt = now
            transaction.deletedAt = now
            transaction.isArchived = true
        }

        let billReportingUpdates = applyPaidAmountReportingToLinkedBills(modifiedAt: now)
        group.expectedMinor = effectiveSuggestionsForSelf.reduce(Int64(0)) { $0 + $1.amountMinor }
        group.settledMinor = 0
        group.status = principalTransactions.isEmpty ? .settled : .open
        group.isArchived = false
        group.archivedAt = nil
        group.updatedAt = now
        let transactionsToSync = principalTransactions + stalePrincipalTransactions + billReportingUpdates

        do {
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
                for transaction in transactionsToSync {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: transaction.id,
                        ownerUserID: ownerUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
            }
            let actorUserID = sessionStore.activeLocalProfileUserID ?? ownerUserID
            if let actorUserID {
                for transaction in transactionsToSync {
                    try TransactionAuditStore.touch(
                        transactionID: transaction.id,
                        actorUserID: actorUserID,
                        fallbackCreatedByUserID: actorUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
            }
            try modelContext.save()
            queueFinalization(
                group: group,
                transactions: transactionsToSync,
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
            if dismissAfterSave {
                dismiss()
            }
            return principalTransactions
        } catch {
            alertMessage = error.localizedDescription
            return []
        }
    }

    private func applyPaidAmountReportingToLinkedBills(modifiedAt: Date) -> [LedgerTransaction] {
        var updatedBills: [LedgerTransaction] = []
        for bill in linkedBills {
            bill.reportingExpenseMinor = max(bill.amountMinor, 0)
            bill.reportingIncomeMinor = 0
            bill.updatedAt = modifiedAt
            updatedBills.append(bill)
        }
        return updatedBills
    }

    private func existingPrincipalDebt(
        groupID: UUID,
        normalizedCounterpartyKey: String?
    ) -> LedgerTransaction? {
        transactions.first {
            $0.settlementGroupID == groupID
                && $0.transferSubtype == .debt
                && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == normalizedCounterpartyKey
                && ($0.settlementRole == .sharedExpenseReceivable || $0.settlementRole == .sharedExpensePayable)
                && $0.deletedAt == nil
                && !$0.isArchived
        }
    }

    private func existingPrincipalDebtTransactions(groupID: UUID) -> [LedgerTransaction] {
        transactions.filter {
            $0.settlementGroupID == groupID
                && $0.transferSubtype == .debt
                && ($0.settlementRole == .sharedExpenseReceivable || $0.settlementRole == .sharedExpensePayable)
                && $0.deletedAt == nil
                && !$0.isArchived
        }
    }

    private func upsertAdditionalParticipants(
        groupID: UUID,
        ownerUserID: UUID?,
        modifiedAt: Date
    ) -> [SettlementParticipant] {
        let existingKeys = Set(groupParticipants.compactMap { $0.normalizedKey ?? TransactionLogic.normalizeCounterpartyName($0.displayName) })
        var result: [SettlementParticipant] = []
        var sortOrder = (groupParticipants.map(\.sortOrder).max() ?? 0) + 1

        for row in additionalRows {
            guard let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else { continue }
            let key = TransactionLogic.normalizeCounterpartyName(name) ?? name.localizedLowercase
            guard !existingKeys.contains(key) else { continue }
            let participant = SettlementParticipant(
                groupID: groupID,
                displayName: name,
                normalizedKey: key,
                isSelf: false,
                sortOrder: sortOrder,
                createdAt: modifiedAt,
                updatedAt: modifiedAt
            )
            sortOrder += 1
            modelContext.insert(participant)
            result.append(participant)
        }
        return result
    }

    private func queueFinalization(
        group: SettlementGroup,
        transactions: [LedgerTransaction],
        ownerUserID: UUID?,
        modifiedAt: Date
    ) {
        guard let ownerUserID else { return }
        var mutations = [
            MistiaSyncMutation(
                entity: .settlementGroup,
                recordID: group.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: group.remoteVersion
            )
        ]
        mutations += transactions.map {
            MistiaSyncMutation(
                entity: .transaction,
                recordID: $0.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: $0.remoteVersion
            )
        }
        sessionStore.recordMutations(mutations)
        if ownerUserID != sessionStore.activeLocalProfileUserID {
            Task { @MainActor in
                _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
            }
        }
    }
}


private struct SharedExpenseParticipantDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var paidText: String

    init(id: UUID = UUID(), name: String, paidText: String) {
        self.id = id
        self.name = name
        self.paidText = paidText
    }
}

private enum SharedExpenseBillDraftMode: String, CaseIterable, Identifiable {
    case newExpense
    case existingExpense

    var id: String { rawValue }
}

private struct SharedExpenseBillDraft: Identifiable, Hashable {
    let id: UUID
    var mode: SharedExpenseBillDraftMode
    var stagedTransaction: LedgerTransaction?
    var existingTransactionID: UUID?

    init(
        id: UUID = UUID(),
        mode: SharedExpenseBillDraftMode = .newExpense,
        stagedTransaction: LedgerTransaction? = nil,
        existingTransactionID: UUID? = nil
    ) {
        self.id = id
        self.mode = mode
        self.stagedTransaction = stagedTransaction
        self.existingTransactionID = existingTransactionID
    }

    var hasContent: Bool {
        switch mode {
        case .newExpense:
            return stagedTransaction != nil
        case .existingExpense:
            return existingTransactionID != nil
        }
    }

    var stagedExpenseAmountMinor: Int64 {
        guard mode == .newExpense else { return 0 }
        return max(stagedTransaction?.amountMinor ?? 0, 0)
    }
}

private struct SettlementEventExpenseEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let buttonTitle: String?
    let accent: Color
    let symbols: [String]
    var action: (() -> Void)? = nil

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(
            cornerRadius: 24,
            tint: cardTint,
            padding: 0
        ) {
            MistiaEmptyStateContent(
                title: title,
                message: message,
                buttonTitle: buttonTitle,
                accent: accent,
                symbols: symbols,
                action: action
            )
        }
    }
}

private struct SharedExpenseBillDraftRow: View {
    @Binding var row: SharedExpenseBillDraft

    let existingTransactions: [LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let primaryCurrencyCode: String
    let exchangeRateIndex: MistiaExchangeRateIndex
    let familyContextStore: FamilyContextStore
    let currencyCode: String
    let categories: [TransactionCategory]
    let categoryLabel: (UUID?) -> String
    let onTap: () -> Void
    let onCategoryChange: (UUID?) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                if let transaction = selectedTransaction {
                    TransactionCashflowRow(
                        record: transaction.snapshot,
                        transaction: transaction,
                        auditRecord: transactionAuditMap[transaction.id],
                        walletOwnerMap: walletOwnerMap,
                        transactionOwnerMap: transactionOwnerMap,
                        familyContextStore: familyContextStore,
                        hasFamilyOwnerConflict: false,
                        primaryCurrencyCode: primaryCurrencyCode,
                        exchangeRateIndex: exchangeRateIndex,
                        subtitleLineLimit: 1,
                        showsAuditSubtitle: false
                    )
                } else {
                    placeholderContent
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let transaction = selectedTransaction {
                SharedExpenseBillCategoryPickerRow(
                    selectedCategoryID: transaction.category?.id,
                    selectedCategoryLabel: categoryLabel(transaction.category?.id),
                    categories: categories,
                    categoryLabel: categoryLabel,
                    onSelect: onCategoryChange
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(L10n.common.delete)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
    }

    private var selectedStagedTransaction: LedgerTransaction? {
        row.stagedTransaction
    }

    private var selectedExistingTransaction: LedgerTransaction? {
        existingTransactions.first(where: { $0.id == row.existingTransactionID })
    }

    private var selectedTransaction: LedgerTransaction? {
        switch row.mode {
        case .newExpense:
            selectedStagedTransaction
        case .existingExpense:
            selectedExistingTransaction
        }
    }

    private var placeholderContent: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(
                icon: row.mode == .newExpense ? "receipt.fill" : "link",
                fallbackColor: MistiaAccent.expense.color,
                size: 34
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(row.mode == .newExpense ? L10n.transactions.settlement.addNewExpense : L10n.transactions.settlement.searchExpense)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(row.mode == .newExpense ? L10n.transactions.settlement.addNewExpense : L10n.transactions.settlement.chooseExistingExpense)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text(Int64(0).formattedCurrency(code: currencyCode))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(MistiaAccent.expense.color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(minWidth: 96, alignment: .trailing)
                .layoutPriority(2)
        }
    }
}

private struct SharedExpenseBillCategoryPickerRow: View {
    let selectedCategoryID: UUID?
    let selectedCategoryLabel: String
    let categories: [TransactionCategory]
    let categoryLabel: (UUID?) -> String
    let onSelect: (UUID?) -> Void

    var body: some View {
        Picker(selection: categorySelection) {
            Text(L10n.transactions.transactioneditor.chooseCategory).tag(Optional<UUID>.none)
            ForEach(categories) { category in
                Text(categoryLabel(category.id)).tag(Optional(category.id))
            }
        } label: {
            HStack(spacing: 8) {
                Text(L10n.transactions.transactioneditor.category)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(selectedCategoryLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selectedCategoryID == nil ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .pickerStyle(.menu)
    }

    private var categorySelection: Binding<UUID?> {
        Binding(
            get: { selectedCategoryID },
            set: onSelect
        )
    }
}

private struct SharedExpenseParticipantResultRow: View {
    let participant: SettlementParticipantResult
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(participant.name)
                    .fontWeight(.semibold)
                Spacer()
                Text(netText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(netColor)
            }
            HStack(spacing: 12) {
                Text(verbatim: "\(L10n.transactions.settlement.paid): \(participant.paidMinor.formattedCurrency(code: currencyCode))")
                Text(verbatim: "\(L10n.transactions.settlement.share): \(participant.shareMinor.formattedCurrency(code: currencyCode))")
            }
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var netText: String {
        if participant.netMinor > 0 {
            return "+\(participant.netMinor.formattedCurrency(code: currencyCode))"
        }
        if participant.netMinor < 0 {
            return "-\(abs(participant.netMinor).formattedCurrency(code: currencyCode))"
        }
        return participant.netMinor.formattedCurrency(code: currencyCode)
    }

    private var netColor: Color {
        if participant.netMinor > 0 {
            return MistiaAccent.income.color
        }
        if participant.netMinor < 0 {
            return MistiaAccent.expense.color
        }
        return .secondary
    }
}

private struct SharedExpenseParticipantPaidInputRow: View {
    let participantName: String
    @Binding var paidText: String

    var body: some View {
        HStack(spacing: 12) {
            Text(participantName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            MistiaCurrencyInputField(
                L10n.transactions.settlement.paidAmount,
                text: $paidText,
                font: .mistiaRounded(size: 16, weight: .semibold)
            )
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 132, idealWidth: 156, maxWidth: 180, minHeight: 40)
        }
        .padding(.vertical, 4)
    }
}

private struct SharedExpenseSuggestionActionRow: View {
    let suggestion: SettlementSuggestion
    let selfParticipantID: UUID?
    let name: String
    let currencyCode: String
    let isEditing: Bool
    let isAnotherRowEditing: Bool
    @Binding var editingText: String
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void

    private var isReceivable: Bool {
        suggestion.receiverID == selfParticipantID
    }

    private var amountColor: Color {
        isReceivable ? MistiaAccent.debtLend.color : MistiaAccent.debtBorrow.color
    }

    private var signedAmountText: String {
        let amount = suggestion.amountMinor.formattedCurrency(code: currencyCode)
        return isReceivable ? "+\(amount)" : "-\(amount)"
    }

    private var subtitle: String {
        isReceivable ? L10n.transactions.transactions.theyOweYou : L10n.transactions.transactions.youOwe
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    MistiaFinanceIconView(
                        icon: isReceivable ? TransactionDebtIntent.lend.financeIconToken : TransactionDebtIntent.borrow.financeIconToken,
                        fallbackColor: amountColor,
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .disabled(isEditing || isAnotherRowEditing)
            .opacity((isEditing || isAnotherRowEditing) ? 0.55 : 1)

            if isEditing {
                HStack(spacing: 4) {
                    Text(isReceivable ? "+" : "-")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(amountColor)

                    MistiaCurrencyInputField(
                        L10n.transactions.settlement.amount,
                        text: $editingText,
                        font: .mistiaRounded(size: 16, weight: .bold),
                        showsCalculatorButton: false,
                        requestsFocus: true,
                        selectsAllOnFocus: true
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .frame(minHeight: 36)
                }
            } else {
                Text(signedAmountText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Button(action: isEditing ? onSave : onEdit) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(Color(UIColor.tertiarySystemFill))
                    }
            }
            .buttonStyle(.plain)
            .disabled(isAnotherRowEditing)
            .opacity(isAnotherRowEditing ? 0.4 : 1)
            .accessibilityLabel(
                isEditing
                    ? L10n.transactions.settlement.saveDebtAmount(name)
                    : L10n.transactions.settlement.editDebtAmount(name)
            )
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}


private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
