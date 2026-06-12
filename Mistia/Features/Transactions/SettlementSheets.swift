import SwiftData
import SwiftUI

enum SettlementEditorTarget: Identifiable, Equatable {
    case resale
    case newSharedExpense
    case editSharedExpense(UUID)

    var id: String {
        switch self {
        case .resale:
            return "resale"
        case .newSharedExpense:
            return "newSharedExpense"
        case .editSharedExpense(let id):
            return "editSharedExpense-\(id.uuidString)"
        }
    }
}

struct PendingSettlementChipSnapshot: Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let title: String
    let kind: SettlementKind
    let direction: SettlementDirection
    let counterpartyName: String
    let currencyCode: String
    let expectedMinor: Int64
    let settledMinor: Int64
    let preferredWalletID: UUID?
    let occurredAt: Date
    let updatedAt: Date

    var remainingMinor: Int64 {
        max(expectedMinor - settledMinor, 0)
    }

    var isReceivable: Bool {
        direction == .receivable
    }
}

struct SettlementDetailSheetTarget: Identifiable {
    let item: PendingSettlementChipSnapshot

    var id: UUID { item.id }
}

struct PreparingSettlementEventSheetTarget: Identifiable, Hashable {
    let groupID: UUID

    var id: UUID { groupID }
}

struct PendingSettlementChip: View {
    let item: PendingSettlementChipSnapshot
    let action: () -> Void

    private var tint: Color {
        item.isReceivable ? MistiaAccent.income.color : MistiaAccent.expense.color
    }

    private var subtitle: String {
        switch item.direction {
        case .receivable:
            return L10n.transactions.settlement.theyWillPay
        case .payable:
            return L10n.transactions.settlement.youWillPay
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.counterpartyName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.remainingMinor.formattedCurrency(code: item.currencyCode))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(item.title)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(width: 158, alignment: .leading)
            .background {
                MistiaBlockCardBackground(tint: tint.opacity(0.14), cornerRadius: 22)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 22, tint: tint))
    }
}

struct PreparingSettlementCompactChip: View {
    let event: PreparingSettlementEventSnapshot
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
                MistiaFinanceIconView(
                    icon: "calendar.badge.clock",
                    fallbackColor: MistiaAccent.purple.color,
                    size: 36
                )

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
            .frame(width: 230, alignment: .leading)
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

    @State private var resaleTitle = ""
    @State private var buyerName = ""
    @State private var purchaseCostText = ""
    @State private var salePriceText = ""
    @State private var selectedPurchaseWalletID: UUID?
    @State private var selectedReceiveWalletID: UUID?
    @State private var selectedCategoryID: UUID?

    @State private var eventTitle = ""
    @State private var participantRows: [SharedExpenseParticipantDraft] = [
        SharedExpenseParticipantDraft(name: "", paidText: "")
    ]
    @State private var selectedSharedWalletID: UUID?
    @State private var selectedSharedCategoryID: UUID?
    @State private var eventNote = ""
    @State private var billRows: [SharedExpenseBillDraft] = []
    @State private var hasLoadedSharedExpenseDraft = false
    @State private var alertMessage: String?
    @State private var billEditorTarget: SharedExpenseBillEditorTarget?
    @State private var billSearchTarget: SharedExpenseBillSearchTarget?
    @State private var showingBillAddOptions = false
    @FocusState private var focusedParticipantRowID: UUID?
    @State private var hiddenParticipantSuggestionRowID: UUID?
    @State private var hiddenParticipantSuggestionQuery = ""

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

    private var selectedPurchaseWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == selectedPurchaseWalletID })
    }

    private var selectedReceiveWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == selectedReceiveWalletID })
    }

    private var selectedSharedWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == selectedSharedWalletID })
    }

    private var editingSharedExpenseGroupID: UUID? {
        if case .editSharedExpense(let groupID) = target {
            return groupID
        }
        return nil
    }

    private var editingSharedExpenseGroup: SettlementGroup? {
        guard let editingSharedExpenseGroupID else { return nil }
        return settlementGroups.first(where: { $0.id == editingSharedExpenseGroupID })
    }

    private var activeCurrencyCode: String {
        MistiaCurrencyLogic.normalizedCode(
            selectedPurchaseWallet?.currencyCode
                ?? selectedSharedWallet?.currencyCode
                ?? editingSharedExpenseGroup?.currencyCode
                ?? availableWallets.first?.currencyCode
                ?? "JPY"
        )
    }

    private var purchaseCostMinor: Int64 {
        purchaseCostText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
    }

    private var salePriceMinor: Int64 {
        salePriceText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
    }

    private var expectedProfitMinor: Int64 {
        max(salePriceMinor - purchaseCostMinor, 0)
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

    private var selectedCategory: TransactionCategory? {
        expenseCategories.first(where: { $0.id == selectedCategoryID })
    }

    private var selectedSharedCategory: TransactionCategory? {
        expenseCategories.first(where: { $0.id == selectedSharedCategoryID })
    }

    private var linkedSharedExpenseBills: [LedgerTransaction] {
        guard let groupID = editingSharedExpenseGroupID else { return [] }
        return transactions
            .filter {
                $0.settlementGroupID == groupID
                    && $0.settlementRole == .sharedExpensePaid
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
                      transaction.primaryKind == .expense,
                      transaction.settlementGroupID == nil,
                      TransactionLogic.isExpenseSpending(transaction.snapshot) else {
                    return false
                }
                return transaction.sourceWallet != nil && transaction.category != nil
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

    private var visibleParticipantRows: [SharedExpenseParticipantDraft] {
        participantRows.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
        case .resale:
            return resaleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || purchaseCostMinor <= 0
                || salePriceMinor <= 0
                || selectedPurchaseWallet == nil
                || selectedReceiveWallet == nil
                || selectedCategory == nil
        case .newSharedExpense, .editSharedExpense:
            return !SettlementLogic.canSavePreparingEvent(
                title: eventTitle,
                participantNames: participantRows.map(\.name)
            )
        }
    }

    var body: some View {
        switch target {
        case .resale:
            NavigationStack {
                Form {
                    resaleForm
                }
                .navigationTitle(navigationTitle)
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

                    ToolbarItem(placement: .topBarTrailing) {
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
        case .newSharedExpense, .editSharedExpense:
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
        }
    }

    private var navigationTitle: String {
        switch target {
        case .resale:
            return L10n.transactions.settlement.resaleTitle
        case .newSharedExpense:
            return L10n.transactions.settlement.eventTitle
        case .editSharedExpense:
            return L10n.transactions.settlement.editEventTitle
        }
    }

    private var resaleForm: some View {
        Group {
            Section {
                TextField(L10n.transactions.settlement.itemName, text: $resaleTitle)
                TextField(L10n.transactions.settlement.buyerName, text: $buyerName)
            }

            Section {
                MistiaCurrencyInputField(
                    L10n.transactions.settlement.purchaseCost,
                    text: $purchaseCostText,
                    font: .mistiaRounded(size: 17, weight: .semibold)
                )
                .frame(minHeight: 44)

                MistiaCurrencyInputField(
                    L10n.transactions.settlement.salePrice,
                    text: $salePriceText,
                    font: .mistiaRounded(size: 17, weight: .semibold)
                )
                .frame(minHeight: 44)
            } footer: {
                Text(
                    "\(L10n.transactions.settlement.expectedProfit): \(expectedProfitMinor.formattedCurrency(code: activeCurrencyCode))"
                )
            }

            Section {
                walletPicker(
                    title: L10n.transactions.settlement.purchaseWallet,
                    selection: $selectedPurchaseWalletID
                )
                walletPicker(
                    title: L10n.transactions.settlement.receiveWallet,
                    selection: $selectedReceiveWalletID
                )
                categoryPicker(selection: $selectedCategoryID)
            }
        }
    }

    private var sharedExpensePreparationBody: some View {
        NavigationStack {
            Form {
                Section(L10n.transactions.settlement.eventName) {
                    TextField(L10n.transactions.settlement.eventName, text: $eventTitle)
                        .textInputAutocapitalization(.sentences)
                }

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

                Section(L10n.transactions.settlement.eventBills) {
                    draftBillsContent
                }

                Section(L10n.transactions.settlement.note) {
                    TextField(L10n.transactions.settlement.notePlaceholder, text: $eventNote, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(navigationTitle)
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

                ToolbarItem(placement: .topBarTrailing) {
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
                }
            }
        }
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
                    .textInputAutocapitalization(.words)
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
        if linkedSharedExpenseBills.isEmpty && billRows.isEmpty {
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
            VStack(spacing: 0) {
                ForEach(Array(linkedSharedExpenseBills.enumerated()), id: \.element.id) { index, bill in
                HStack(alignment: .center, spacing: 10) {
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
                            exchangeRateIndex: MistiaExchangeRateIndex(rates: MistiaCurrencySettings.rates())
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        detachBill(bill)
                    } label: {
                        Image(systemName: "link.badge.minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if index < linkedSharedExpenseBills.count - 1 || !billRows.isEmpty {
                    Divider()
                        .padding(.leading, 52)
                }
            }

                ForEach(billRows.indices, id: \.self) { index in
                    SharedExpenseBillDraftRow(
                        row: $billRows[index],
                        existingTransactions: attachableExpenseTransactions,
                        transactionAuditMap: transactionAuditMap,
                        walletOwnerMap: walletOwnerMap,
                        transactionOwnerMap: transactionOwnerMap,
                        primaryCurrencyCode: primaryCurrencyCode,
                        exchangeRateIndex: MistiaExchangeRateIndex(rates: MistiaCurrencySettings.rates()),
                        familyContextStore: familyContextStore,
                        currencyCode: activeCurrencyCode,
                        onTap: { billEditorTarget = SharedExpenseBillEditorTarget(rowID: billRows[index].id) },
                        onRemove: { removeBillRow(billRows[index].id) }
                    )

                    if index < billRows.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }

                Divider()
                    .padding(.leading, 52)

                MistiaFooterAddButton(
                    title: L10n.transactions.settlement.addExpense,
                    accent: MistiaAccent.purple.color
                ) {
                    showingBillAddOptions = true
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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

        if editingSharedExpenseGroup != nil {
            persistLinkedBillUpdate(transaction)
            billRows.removeAll { $0.id == rowID }
        }
    }

    private func applyExistingTransaction(_ transaction: LedgerTransaction, toBillRow rowID: UUID) {
        guard let index = billRows.firstIndex(where: { $0.id == rowID }) else { return }
        billRows[index].mode = .existingExpense
        billRows[index].existingTransactionID = transaction.id
        billRows[index].stagedTransaction = nil

        if editingSharedExpenseGroup != nil {
            persistLinkedBillUpdate(transaction)
            billRows.removeAll { $0.id == rowID }
        }
    }

    private func sharedParticipantName(for id: UUID) -> String {
        sharedParticipantNameByID[id] ?? L10n.transactions.settlement.participantName
    }

    private func applyInitialDefaults() {
        if !hasLoadedSharedExpenseDraft {
            loadSharedExpenseDraftIfNeeded()
        }
        if selectedPurchaseWalletID == nil {
            selectedPurchaseWalletID = availableWallets.first?.id
        }
        if selectedReceiveWalletID == nil {
            selectedReceiveWalletID = selectedPurchaseWalletID ?? availableWallets.first?.id
        }
        if selectedSharedWalletID == nil {
            selectedSharedWalletID = availableWallets.first?.id
        }
        if selectedCategoryID == nil {
            selectedCategoryID = expenseCategories.first?.id
        }
        if selectedSharedCategoryID == nil {
            selectedSharedCategoryID = selectedCategoryID ?? expenseCategories.first?.id
        }
    }

    private func loadSharedExpenseDraftIfNeeded() {
        hasLoadedSharedExpenseDraft = true
        guard case .editSharedExpense = target,
              let group = editingSharedExpenseGroup else {
            return
        }

        eventTitle = group.title
        eventNote = group.note ?? ""
        let rows = settlementParticipants
            .filter { $0.groupID == group.id && !$0.isSelf && $0.deletedAt == nil }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .map { SharedExpenseParticipantDraft(id: $0.id, name: $0.displayName, paidText: "") }
        participantRows = rows.isEmpty ? [SharedExpenseParticipantDraft(name: "", paidText: "")] : rows + [SharedExpenseParticipantDraft(name: "", paidText: "")]
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
                && $0.settlementRole == .sharedExpensePaid
                && $0.deletedAt == nil
                && !$0.isArchived
        }
        let existingIDs = Set(existing.map(\.id))
        return existing + createdTransactions.filter { !existingIDs.contains($0.id) }
    }

    private func save() {
        switch target {
        case .resale:
            saveResale()
        case .newSharedExpense, .editSharedExpense:
            saveSharedExpense()
        }
    }

    private func saveResale() {
        let title = resaleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let buyer = buyerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            alertMessage = L10n.transactions.settlement.enterTitle
            return
        }
        guard !buyer.isEmpty else {
            alertMessage = L10n.transactions.settlement.enterCounterparty
            return
        }
        guard purchaseCostMinor > 0, salePriceMinor > 0 else {
            alertMessage = L10n.transactions.settlement.enterAmountsGreaterThanZero
            return
        }
        guard let selectedPurchaseWallet, let selectedReceiveWallet else {
            alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
            return
        }
        guard let selectedCategory else {
            alertMessage = L10n.transactions.transactioneditor.chooseCategory
            return
        }

        let now = Date()
        let currencyCode = MistiaCurrencyLogic.normalizedCode(selectedPurchaseWallet.currencyCode)
        let group = SettlementGroup(
            kind: .resale,
            title: title,
            currencyCode: currencyCode,
            occurredAt: now,
            totalMinor: purchaseCostMinor,
            expectedMinor: salePriceMinor,
            organizerUserID: activeOwnerUserID,
            createdAt: now,
            updatedAt: now
        )
        let obligation = SettlementObligation(
            groupID: group.id,
            counterpartyName: buyer,
            normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(buyer),
            direction: .receivable,
            expectedMinor: salePriceMinor,
            preferredWalletID: selectedReceiveWallet.id,
            createdAt: now,
            updatedAt: now
        )
        let purchaseTransaction = LedgerTransaction(
            primaryKind: .expense,
            entryStatus: .posted,
            title: title,
            amountMinor: purchaseCostMinor,
            settlementGroupID: group.id,
            settlementObligationID: obligation.id,
            settlementRole: .resalePurchase,
            reportingExpenseMinor: purchaseCostMinor,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: currencyCode,
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            sourceWallet: selectedPurchaseWallet,
            category: selectedCategory,
            counterpartyName: buyer,
            normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(buyer)
        )

        persistNewSettlement(
            group: group,
            obligations: [obligation],
            transactions: [purchaseTransaction],
            ownerUserID: walletPickerAccess.walletOwnerUserID(for: selectedPurchaseWallet) ?? activeOwnerUserID,
            modifiedAt: now
        )
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
            shouldDismissAfterSave = false
        case .resale:
            return
        }

        let participants = upsertPreparingParticipants(
            groupID: group.id,
            participantNames: participantNames,
            ownerUserID: ownerUserID,
            modifiedAt: now
        )

        var transactions: [LedgerTransaction] = []
        var attachedTransactions: [LedgerTransaction] = []

        for row in billRows {
            switch row.mode {
            case .newExpense:
                guard let transaction = makeSharedExpenseBillTransaction(from: row, groupID: group.id, defaultTitle: title, now: now) else {
                    continue
                }
                modelContext.insert(transaction)
                transactions.append(transaction)
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
                attachedTransactions.append(transaction)
            }
        }

        let linkedTotal = transactionsForTotal(groupID: group.id, createdTransactions: transactions)
            .reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
        group.totalMinor = linkedTotal
        group.expectedMinor = 0
        group.settledMinor = 0
        group.status = .preparing
        group.updatedAt = now

        persistPreparedSharedExpense(
            group: group,
            participants: participants,
            transactions: transactions + attachedTransactions,
            ownerUserID: ownerUserID,
            modifiedAt: now,
            dismissAfterSave: shouldDismissAfterSave
        )
    }

    private func persistNewSettlement(
        group: SettlementGroup,
        obligations: [SettlementObligation],
        transactions: [LedgerTransaction],
        ownerUserID: UUID?,
        modifiedAt: Date
    ) {
        modelContext.insert(group)
        obligations.forEach(modelContext.insert)
        transactions.forEach(modelContext.insert)

        do {
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementGroup,
                    recordID: group.id,
                    ownerUserID: ownerUserID,
                    updatedAt: modifiedAt,
                    context: modelContext
                )
                for obligation in obligations {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .settlementObligation,
                        recordID: obligation.id,
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
                if let ownerUserID {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: transaction.id,
                        ownerUserID: ownerUserID,
                        updatedAt: modifiedAt,
                        context: modelContext
                    )
                }
            }

            try modelContext.save()
            queueUpserts(
                group: group,
                participants: [],
                obligations: obligations,
                transactions: transactions,
                ownerUserID: ownerUserID,
                modifiedAt: modifiedAt
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
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
                obligations: [],
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
                    && $0.settlementRole == .sharedExpensePaid
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
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
                obligations: [],
                transactions: [bill],
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
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
                    && $0.settlementRole == .sharedExpensePaid
                    && $0.deletedAt == nil
                    && !$0.isArchived
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
                obligations: [],
                transactions: [bill],
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func queueUpserts(
        group: SettlementGroup,
        participants: [SettlementParticipant] = [],
        obligations: [SettlementObligation],
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
            contentsOf: obligations.map {
                MistiaSyncMutation(
                    entity: .settlementObligation,
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
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""

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
            openDebtPositions: [],
            openReceivableDebtTotals: [],
            sections: TransactionLogic.sections(
                from: records,
                assumesSortedByRecency: true
            ),
            transactionsByID: transactionsByID,
            transactionAuditMap: transactionAuditMap,
            walletOwnerMap: walletOwnerMap,
            transactionOwnerMap: transactionOwnerMap
        )
    }

    var body: some View {
        NavigationStack {
            TransactionsSearchScene(
                searchText: effectiveSearchText,
                snapshot: snapshot,
                transactionsByID: transactionsByID,
                transactionAuditMap: transactionAuditMap,
                walletOwnerMap: walletOwnerMap,
                transactionOwnerMap: transactionOwnerMap,
                primaryCurrencyCode: primaryCurrencyCode,
                exchangeRateIndex: exchangeRateIndex,
                showsExpenseMinusSign: false,
                onSelect: onSelect,
                onLoadMore: { _ in }
            )
            .navigationTitle(L10n.transactions.settlement.searchExpense)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.transactions.transactions.searchTransactionName
            )
            .searchFocused($isSearchFocused)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await Task.yield()
                isSearchFocused = true
            }
        }
        .presentationBackground(Color(UIColor.systemGroupedBackground))
    }

    private var effectiveSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "."
            : searchText
    }

    private func filteredTransactions(searchText: String) -> [LedgerTransaction] {
        guard !searchText.isEmpty else {
            return transactions
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
    @State private var alertMessage: String?
    @State private var eventEditorTarget: SettlementEditorTarget?
    @State private var debtSettlementTarget: DebtSettlementSheetTarget?

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
                    && $0.settlementRole == .sharedExpensePaid
                    && $0.entryStatus == .posted
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var selfPaidMinor: Int64 {
        linkedBills.reduce(Int64(0)) { $0 + max($1.amountMinor, 0) }
    }

    private var currencyCode: String {
        MistiaCurrencyLogic.normalizedCode(group?.currencyCode ?? linkedBills.first?.sourceCurrencyCode ?? "JPY")
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
                paidMinor: paidTextsByParticipantID[$0.id, default: "0"].currencyInputToMinorUnits(currencyCode: currencyCode)
            )
        }
        return inputs
    }

    private var splitResult: SettlementSharedExpenseResult {
        SettlementLogic.sharedExpenseSettlement(
            participants: participantInputs,
            organizerID: selfParticipant?.id ?? UUID()
        )
    }

    private var suggestionsForSelf: [SettlementSuggestion] {
        guard let selfID = selfParticipant?.id else { return [] }
        return splitResult.suggestions.filter {
            $0.payerID == selfID || $0.receiverID == selfID
        }
    }

    private var participantNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: participantInputs.map { ($0.id, $0.name) })
    }

    private var ownerUserID: UUID? {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .settlementGroup)
        return ownerMap[target.groupID] ?? group?.organizerUserID ?? familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
    }

    var body: some View {
        NavigationStack {
            Form {
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
                        eventEditorTarget = .editSharedExpense(target.groupID)
                    } label: {
                        Label(L10n.management.management.edit, systemImage: "pencil")
                    }
                }

                Section(L10n.transactions.settlement.participants) {
                    if nonSelfParticipants.isEmpty {
                        Text(L10n.transactions.settlement.noParticipantsYet)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nonSelfParticipants) { participant in
                            SharedExpenseParticipantPaidInputRow(
                                participant: participant,
                                currencyCode: currencyCode,
                                paidText: paidTextBinding(for: participant)
                            )
                        }
                    }
                }

                Section(L10n.transactions.settlement.sharedExpenseTitle) {
                    if suggestionsForSelf.isEmpty {
                        Text(L10n.transactions.settlement.noSettlementNeeded)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(suggestionsForSelf.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                openDebtSettlement(for: suggestion)
                            } label: {
                                SharedExpenseSuggestionActionRow(
                                    suggestion: suggestion,
                                    selfParticipantID: selfParticipant?.id,
                                    name: name(for: suggestion.payerID == selfParticipant?.id ? suggestion.receiverID : suggestion.payerID),
                                    currencyCode: currencyCode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(group?.title ?? L10n.transactions.settlement.sharedExpenseTitle)
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
                ToolbarItem(placement: .topBarTrailing) {
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
                    .disabled(nonSelfParticipants.isEmpty)
                    .opacity(nonSelfParticipants.isEmpty ? 0.45 : 1)
                }
            }
        }
        .onAppear(perform: initializePaidInputsIfNeeded)
        .presentationBackground(Color(UIColor.systemGroupedBackground))
        .sheet(item: $eventEditorTarget) { target in
            SettlementEditorSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
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
            get: { paidTextsByParticipantID[participant.id, default: "0"] },
            set: { paidTextsByParticipantID[participant.id] = $0 }
        )
    }

    private func initializePaidInputsIfNeeded() {
        for participant in nonSelfParticipants where paidTextsByParticipantID[participant.id] == nil {
            paidTextsByParticipantID[participant.id] = "0"
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
                        .textInputAutocapitalization(.words)
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

                if suggestionsForSelf.isEmpty {
                    Text(L10n.transactions.settlement.noSettlementNeeded)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(suggestionsForSelf.enumerated()), id: \.offset) { _, suggestion in
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

        let now = Date()
        let ownerUserID = ownerUserID
        let currentSelfID = selfParticipant.id
        var principalTransactions: [LedgerTransaction] = []

        for suggestion in suggestionsForSelf {
            let isReceivable = suggestion.receiverID == currentSelfID
            let counterpartyID = isReceivable ? suggestion.payerID : suggestion.receiverID
            let counterpartyName = name(for: counterpartyID)
            let normalizedKey = TransactionLogic.normalizeCounterpartyName(counterpartyName)
            let debtIntent: TransactionDebtIntent = isReceivable ? .lend : .borrow
            let role: SettlementTransactionRole = isReceivable ? .sharedExpenseReceivable : .sharedExpensePayable
            let existingTransaction = existingPrincipalDebt(
                groupID: group.id,
                debtIntent: debtIntent,
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
                reportingExpenseMinor: 0,
                reportingIncomeMinor: 0,
                sourceCurrencyCode: currencyCode,
                occurredAt: now,
                createdAt: now,
                updatedAt: now,
                sourceWallet: nil,
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
            transaction.reportingExpenseMinor = 0
            transaction.reportingIncomeMinor = 0
            transaction.sourceCurrencyCode = currencyCode
            transaction.sourceWallet = nil
            transaction.destinationWallet = nil
            transaction.counterpartyName = counterpartyName
            transaction.normalizedCounterpartyKey = normalizedKey
            transaction.updatedAt = now
            transaction.deletedAt = nil
            transaction.isArchived = false
            principalTransactions.append(transaction)
        }

        group.expectedMinor = suggestionsForSelf.reduce(Int64(0)) { $0 + $1.amountMinor }
        group.settledMinor = 0
        group.status = principalTransactions.isEmpty ? .settled : .open
        group.isArchived = principalTransactions.isEmpty
        group.archivedAt = principalTransactions.isEmpty ? now : nil
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
                for transaction in principalTransactions {
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
                for transaction in principalTransactions {
                    try TransactionAuditStore.upsert(
                        transactionID: transaction.id,
                        createdByUserID: actorUserID,
                        lastModifiedByUserID: actorUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
            }
            try modelContext.save()
            queueFinalization(group: group, transactions: principalTransactions, ownerUserID: ownerUserID, modifiedAt: now)
            if dismissAfterSave {
                dismiss()
            }
            return principalTransactions
        } catch {
            alertMessage = error.localizedDescription
            return []
        }
    }

    private func existingPrincipalDebt(
        groupID: UUID,
        debtIntent: TransactionDebtIntent,
        normalizedCounterpartyKey: String?
    ) -> LedgerTransaction? {
        transactions.first {
            $0.settlementGroupID == groupID
                && $0.transferSubtype == .debt
                && $0.debtIntent == debtIntent
                && ($0.normalizedCounterpartyKey ?? TransactionLogic.normalizeCounterpartyName($0.counterpartyName)) == normalizedCounterpartyKey
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

struct SettlementDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query private var wallets: [LedgerWallet]
    @Query private var groups: [SettlementGroup]
    @Query private var obligations: [SettlementObligation]
    @Query private var transactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: SettlementDetailSheetTarget

    @State private var amountText = ""
    @State private var selectedWalletID: UUID?
    @State private var alertMessage: String?

    private var group: SettlementGroup? {
        groups.first { $0.id == target.item.groupID && $0.deletedAt == nil }
    }

    private var obligation: SettlementObligation? {
        obligations.first { $0.id == target.item.id && $0.deletedAt == nil }
    }

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeOwnerUserID: UUID? {
        walletPickerAccess.walletOwnerUserID(for: target.item.preferredWalletID)
            ?? familyContextStore.selectedSubjectUserID
            ?? walletPickerAccess.currentSelfUserID
    }

    private var availableWallets: [LedgerWallet] {
        walletPickerAccess.availableWallets(
            from: wallets,
            preferredWalletIDs: Set([target.item.preferredWalletID, selectedWalletID].compactMap { $0 }),
            targetOwnerUserID: activeOwnerUserID,
            excludesCreditCards: true
        )
        .filter {
            MistiaCurrencyLogic.normalizedCode($0.currencyCode) == target.item.currencyCode
        }
    }

    private var selectedWallet: LedgerWallet? {
        availableWallets.first { $0.id == selectedWalletID }
    }

    private var parsedAmountMinor: Int64 {
        amountText.currencyInputToMinorUnits(currencyCode: target.item.currencyCode)
    }

    private var isSaveDisabled: Bool {
        selectedWallet == nil || parsedAmountMinor <= 0 || parsedAmountMinor > target.item.remainingMinor
    }

    private var tint: Color {
        target.item.isReceivable ? MistiaAccent.income.color : MistiaAccent.expense.color
    }

    private var historyRows: [LedgerTransaction] {
        transactions
            .filter {
                $0.deletedAt == nil
                    && $0.settlementObligationID == target.item.id
                    && $0.settlementRole != .resalePurchase
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: target.item.isReceivable ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(tint)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.item.counterpartyName)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(target.item.remainingMinor.formattedCurrency(code: target.item.currencyCode))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                            Text(target.item.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(statusFooter)
                }

                if target.item.remainingMinor > 0 {
                    Section {
                        MistiaCurrencyInputField(
                            L10n.planning.duepayment.enterAmount,
                            text: $amountText,
                            font: .mistiaRounded(size: 17, weight: .semibold)
                        )
                        .frame(minHeight: 44)

                        Picker(L10n.planning.duepayment.paymentWallet, selection: $selectedWalletID) {
                            Text(L10n.planning.duepayment.chooseWallet).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(walletPickerAccess.title(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if !historyRows.isEmpty {
                    Section {
                        ForEach(historyRows) { transaction in
                            SettlementHistoryRow(transaction: transaction)
                        }
                    } header: {
                        Text(L10n.transactions.settlement.history)
                    }
                }
            }
            .navigationTitle(L10n.transactions.settlement.recordPayment)
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

                ToolbarItem(placement: .topBarTrailing) {
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
        .onAppear {
            amountText = MistiaCurrencyInputFormatting.groupedInput(String(target.item.remainingMinor))
            if let preferredWalletID = target.item.preferredWalletID,
               availableWallets.contains(where: { $0.id == preferredWalletID }) {
                selectedWalletID = preferredWalletID
            } else {
                selectedWalletID = availableWallets.first?.id
            }
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
    }

    private var statusFooter: String {
        let settled = target.item.settledMinor.formattedCurrency(code: target.item.currencyCode)
        let expected = target.item.expectedMinor.formattedCurrency(code: target.item.currencyCode)
        return "\(L10n.transactions.settlement.settled): \(settled) / \(expected)"
    }

    private func save() {
        guard parsedAmountMinor > 0 else {
            alertMessage = L10n.transactions.transactioneditor.enterAnAmountGreaterThan
            return
        }
        guard parsedAmountMinor <= target.item.remainingMinor else {
            alertMessage = L10n.transactions.settlement.amountExceedsOpenSettlement
            return
        }
        guard let selectedWallet else {
            alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
            return
        }
        guard let group, let obligation else {
            alertMessage = L10n.transactions.settlement.settlementNotFound
            return
        }

        let now = Date()
        let previousSettledMinor = obligation.settledMinor
        obligation.settledMinor = min(obligation.expectedMinor, obligation.settledMinor + parsedAmountMinor)
        obligation.updatedAt = now
        group.updatedAt = now

        let groupObligations = obligations.filter { $0.groupID == group.id && $0.deletedAt == nil }
        group.settledMinor = groupObligations.reduce(Int64(0)) { total, item in
            total + min(item.expectedMinor, item.settledMinor)
        }
        group.status = settlementStatus(for: groupObligations)

        let transaction = settlementTransaction(
            group: group,
            obligation: obligation,
            selectedWallet: selectedWallet,
            paymentMinor: parsedAmountMinor,
            previousSettledMinor: previousSettledMinor,
            modifiedAt: now
        )
        modelContext.insert(transaction)

        do {
            let ownerUserID = walletPickerAccess.walletOwnerUserID(for: selectedWallet) ?? activeOwnerUserID
            let actorUserID = sessionStore.activeLocalProfileUserID ?? ownerUserID
            if let actorUserID {
                try TransactionAuditStore.upsert(
                    transactionID: transaction.id,
                    createdByUserID: actorUserID,
                    lastModifiedByUserID: actorUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction,
                    recordID: transaction.id,
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
                try MistiaRecordOwnershipStore.upsert(
                    entity: .settlementObligation,
                    recordID: obligation.id,
                    ownerUserID: ownerUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }
            try modelContext.save()
            queuePaymentUpserts(
                group: group,
                obligation: obligation,
                transaction: transaction,
                ownerUserID: ownerUserID,
                modifiedAt: now
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func settlementStatus(for obligations: [SettlementObligation]) -> SettlementStatus {
        let totalExpected = obligations.reduce(Int64(0)) { $0 + $1.expectedMinor }
        let totalSettled = obligations.reduce(Int64(0)) { $0 + min($1.expectedMinor, $1.settledMinor) }
        if totalExpected == 0 || totalSettled >= totalExpected {
            return .settled
        }
        if totalSettled > 0 {
            return .partiallySettled
        }
        return .open
    }

    private func settlementTransaction(
        group: SettlementGroup,
        obligation: SettlementObligation,
        selectedWallet: LedgerWallet,
        paymentMinor: Int64,
        previousSettledMinor: Int64,
        modifiedAt: Date
    ) -> LedgerTransaction {
        let currencyCode = MistiaCurrencyLogic.normalizedCode(selectedWallet.currencyCode)

        switch group.kind {
        case .resale:
            let allocation = SettlementLogic.resaleReceiptAllocation(
                costMinor: group.totalMinor,
                saleMinor: group.expectedMinor,
                priorReceiptMinor: previousSettledMinor,
                paymentMinor: paymentMinor
            )
            return LedgerTransaction(
                primaryKind: .income,
                entryStatus: .posted,
                title: L10n.transactions.settlement.resaleReceiptTitle,
                amountMinor: paymentMinor,
                settlementGroupID: group.id,
                settlementObligationID: obligation.id,
                settlementRole: .resaleReceipt,
                reportingExpenseMinor: -allocation.expenseOffsetMinor,
                reportingIncomeMinor: allocation.incomeMinor,
                sourceCurrencyCode: currencyCode,
                occurredAt: modifiedAt,
                createdAt: modifiedAt,
                updatedAt: modifiedAt,
                sourceWallet: selectedWallet,
                counterpartyName: obligation.counterpartyName,
                normalizedCounterpartyKey: obligation.normalizedCounterpartyKey
            )

        case .sharedExpense:
            let isReceivable = obligation.direction == .receivable
            return LedgerTransaction(
                primaryKind: isReceivable ? .income : .expense,
                entryStatus: .posted,
                title: isReceivable
                    ? L10n.transactions.settlement.sharedExpenseReceiptTitle
                    : L10n.transactions.settlement.sharedExpensePaymentTitle,
                amountMinor: paymentMinor,
                settlementGroupID: group.id,
                settlementObligationID: obligation.id,
                settlementRole: isReceivable ? .sharedExpenseReceipt : .sharedExpensePayment,
                reportingExpenseMinor: isReceivable ? -paymentMinor : paymentMinor,
                reportingIncomeMinor: 0,
                sourceCurrencyCode: currencyCode,
                occurredAt: modifiedAt,
                createdAt: modifiedAt,
                updatedAt: modifiedAt,
                sourceWallet: selectedWallet,
                counterpartyName: obligation.counterpartyName,
                normalizedCounterpartyKey: obligation.normalizedCounterpartyKey
            )
        }
    }

    private func queuePaymentUpserts(
        group: SettlementGroup,
        obligation: SettlementObligation,
        transaction: LedgerTransaction,
        ownerUserID: UUID?,
        modifiedAt: Date
    ) {
        guard let ownerUserID else { return }
        sessionStore.recordMutations([
            MistiaSyncMutation(
                entity: .settlementGroup,
                recordID: group.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: group.remoteVersion
            ),
            MistiaSyncMutation(
                entity: .settlementObligation,
                recordID: obligation.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: obligation.remoteVersion
            ),
            MistiaSyncMutation(
                entity: .transaction,
                recordID: transaction.id,
                subjectUserID: ownerUserID,
                kind: .upsert,
                modifiedAt: modifiedAt,
                baseVersion: transaction.remoteVersion
            )
        ])
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
    let buttonTitle: String
    let accent: Color
    let symbols: [String]
    let action: () -> Void

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
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
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
                        exchangeRateIndex: exchangeRateIndex
                    )
                } else {
                    placeholderContent
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

                Text(row.mode == .newExpense ? L10n.transactions.settlement.addNewExpense : L10n.transactions.settlement.chooseExistingExpense)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(Int64(0).formattedCurrency(code: currencyCode))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(MistiaAccent.expense.color)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            }
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
    let participant: SettlementParticipant
    let currencyCode: String
    @Binding var paidText: String

    var body: some View {
        HStack(spacing: 12) {
            Text(participant.displayName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 12)

            MistiaCurrencyInputField(
                L10n.transactions.settlement.paidAmount,
                text: $paidText,
                font: .mistiaRounded(size: 16, weight: .semibold)
            )
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 150, minHeight: 40)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SharedExpenseSuggestionActionRow: View {
    let suggestion: SettlementSuggestion
    let selfParticipantID: UUID?
    let name: String
    let currencyCode: String

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

            Spacer(minLength: 12)

            Text(signedAmountText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .contentShape(Rectangle())
    }
}

private struct SettlementHistoryRow: View {
    let transaction: LedgerTransaction

    private var currencyCode: String {
        MistiaCurrencyLogic.normalizedCode(transaction.sourceCurrencyCode)
    }

    private var signedAmount: String {
        switch transaction.primaryKind {
        case .income:
            return "+\(transaction.amountMinor.formattedCurrency(code: currencyCode))"
        case .expense:
            return "-\(transaction.amountMinor.formattedCurrency(code: currencyCode))"
        case .transfer:
            return transaction.amountMinor.formattedCurrency(code: currencyCode)
        }
    }

    private var tint: Color {
        transaction.primaryKind == .expense ? MistiaAccent.expense.color : MistiaAccent.income.color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.primaryKind == .expense ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(nonBlankTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(MistiaDateFormatting.dateTimeString(for: transaction.occurredAt))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(signedAmount)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
    }

    private var nonBlankTitle: String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.transactions.settlement.recordPayment : trimmed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
