import SwiftData
import SwiftUI

enum SettlementEditorTarget: String, Identifiable {
    case resale
    case sharedExpense

    var id: String { rawValue }
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

struct SettlementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query private var wallets: [LedgerWallet]
    @Query private var categories: [TransactionCategory]
    @Query private var ownershipScopes: [OwnedRecordScope]

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
        SharedExpenseParticipantDraft(name: "A", paidText: ""),
        SharedExpenseParticipantDraft(name: "B", paidText: ""),
        SharedExpenseParticipantDraft(name: "C", paidText: "")
    ]
    @State private var selectedSharedWalletID: UUID?
    @State private var selectedSharedCategoryID: UUID?
    @State private var alertMessage: String?

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

    private var activeCurrencyCode: String {
        MistiaCurrencyLogic.normalizedCode(
            selectedPurchaseWallet?.currencyCode
                ?? selectedSharedWallet?.currencyCode
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
        case .sharedExpense:
            let validParticipants = sharedParticipants.count >= 2
            let hasTotal = sharedParticipants.reduce(Int64(0)) { $0 + $1.paidMinor } > 0
            let needsWalletForPaidAmount = currentUserPaidMinor > 0
            return eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !validParticipants
                || !hasTotal
                || (needsWalletForPaidAmount && (selectedSharedWallet == nil || selectedSharedCategory == nil))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch target {
                case .resale:
                    resaleForm
                case .sharedExpense:
                    sharedExpenseForm
                }
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
    }

    private var navigationTitle: String {
        switch target {
        case .resale:
            return L10n.transactions.settlement.resaleTitle
        case .sharedExpense:
            return L10n.transactions.settlement.sharedExpenseTitle
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

    private var sharedExpenseForm: some View {
        Group {
            Section {
                TextField(L10n.transactions.settlement.eventName, text: $eventTitle)
            }

            Section {
                ForEach($participantRows) { $row in
                    HStack(spacing: 12) {
                        TextField(L10n.transactions.settlement.participantName, text: $row.name)
                            .textInputAutocapitalization(.words)

                        MistiaCurrencyInputField(
                            L10n.transactions.settlement.paidAmount,
                            text: $row.paidText,
                            font: .mistiaRounded(size: 15, weight: .semibold)
                        )
                        .frame(width: 132, height: 44)
                    }
                }
            } header: {
                Text(L10n.transactions.settlement.participants)
            } footer: {
                Text(
                    "\(L10n.transactions.settlement.totalPaid): \(sharedResult.totalPaidMinor.formattedCurrency(code: activeCurrencyCode))"
                )
            }

            if currentUserPaidMinor > 0 {
                Section {
                    walletPicker(
                        title: L10n.transactions.settlement.purchaseWallet,
                        selection: $selectedSharedWalletID
                    )
                    categoryPicker(selection: $selectedSharedCategoryID)
                }
            }

            Section {
                ForEach(sharedResult.participants) { participant in
                    SharedExpenseParticipantResultRow(
                        participant: participant,
                        currencyCode: activeCurrencyCode
                    )
                }
            } header: {
                Text(L10n.transactions.settlement.splitSummary)
            }

            Section {
                if currentUserSuggestionRows.isEmpty {
                    Text(L10n.transactions.settlement.noSettlementNeeded)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(currentUserSuggestionRows.enumerated()), id: \.offset) { _, suggestion in
                        HStack {
                            Text(verbatim: "\(sharedParticipantName(for: suggestion.payerID)) → \(sharedParticipantName(for: suggestion.receiverID))")
                            Spacer()
                            Text(suggestion.amountMinor.formattedCurrency(code: activeCurrencyCode))
                                .fontWeight(.semibold)
                        }
                    }
                }
            } header: {
                Text(L10n.transactions.settlement.settlementSuggestions)
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

    private func sharedParticipantName(for id: UUID) -> String {
        sharedParticipantNameByID[id] ?? L10n.transactions.settlement.participantName
    }

    private func applyInitialDefaults() {
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

    private func save() {
        switch target {
        case .resale:
            saveResale()
        case .sharedExpense:
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
            alertMessage = L10n.transactions.settlement.enterTitle
            return
        }
        guard sharedParticipants.count >= 2,
              sharedResult.totalPaidMinor > 0 else {
            alertMessage = L10n.transactions.settlement.enterAmountsGreaterThanZero
            return
        }

        let now = Date()
        let ownerUserID = selectedSharedWallet.flatMap { walletPickerAccess.walletOwnerUserID(for: $0) } ?? activeOwnerUserID
        let group = SettlementGroup(
            kind: .sharedExpense,
            title: title,
            currencyCode: activeCurrencyCode,
            occurredAt: now,
            totalMinor: sharedResult.totalPaidMinor,
            expectedMinor: currentUserSuggestionRows.reduce(Int64(0)) { $0 + $1.amountMinor },
            organizerUserID: ownerUserID,
            createdAt: now,
            updatedAt: now
        )

        let currentUserParticipantID = participantRows.first?.id
        let obligations = currentUserSuggestionRows.compactMap { suggestion -> SettlementObligation? in
            guard let currentUserParticipantID else { return nil }
            let isReceivable = suggestion.receiverID == currentUserParticipantID
            let counterpartyID = isReceivable ? suggestion.payerID : suggestion.receiverID
            let counterpartyName = sharedParticipantName(for: counterpartyID)
            return SettlementObligation(
                groupID: group.id,
                counterpartyName: counterpartyName,
                normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(counterpartyName),
                direction: isReceivable ? .receivable : .payable,
                expectedMinor: suggestion.amountMinor,
                preferredWalletID: selectedSharedWalletID,
                createdAt: now,
                updatedAt: now
            )
        }

        var transactions: [LedgerTransaction] = []
        if currentUserPaidMinor > 0 {
            guard let selectedSharedWallet else {
                alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
                return
            }
            guard let selectedSharedCategory else {
                alertMessage = L10n.transactions.transactioneditor.chooseCategory
                return
            }
            transactions.append(
                LedgerTransaction(
                    primaryKind: .expense,
                    entryStatus: .posted,
                    title: title,
                    amountMinor: currentUserPaidMinor,
                    settlementGroupID: group.id,
                    settlementRole: .sharedExpensePaid,
                    reportingExpenseMinor: currentUserPaidMinor,
                    reportingIncomeMinor: 0,
                    sourceCurrencyCode: MistiaCurrencyLogic.normalizedCode(selectedSharedWallet.currencyCode),
                    occurredAt: now,
                    createdAt: now,
                    updatedAt: now,
                    sourceWallet: selectedSharedWallet,
                    category: selectedSharedCategory
                )
            )
        }

        if obligations.isEmpty, transactions.isEmpty {
            group.status = .settled
        }

        persistNewSettlement(
            group: group,
            obligations: obligations,
            transactions: transactions,
            ownerUserID: ownerUserID,
            modifiedAt: now
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

    private func queueUpserts(
        group: SettlementGroup,
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
