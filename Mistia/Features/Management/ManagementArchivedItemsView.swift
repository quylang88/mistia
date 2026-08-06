import SwiftData
import SwiftUI

enum MistiaRestoreError: Error {
    case duplicatePayment
    case categoryDependency
}

private enum ArchivedItemSelection: Hashable {
    case transaction(UUID)
    case wallet(UUID)
    case category(UUID)
    case settlementGroup(UUID)
}

private struct ArchivedSyncMutation {
    let entity: MistiaSyncEntity
    let id: UUID
    let updatedAt: Date
    let subjectUserIDOverride: UUID?
    let action: ArchivedMutationAction
    let baseVersion: Int64
}

private struct CategoryDeleteBlockers {
    let transactionCount: Int
    let billCount: Int
    let currentBudgetCount: Int
    let childCategoryCount: Int

    var isEmpty: Bool {
        transactionCount == 0
            && billCount == 0
            && currentBudgetCount == 0
            && childCategoryCount == 0
    }
}

private struct ArchivedTransactionDescriptor {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let badgeTitle: String
    let badgeTint: Color
    let amountText: String
    let amountTint: Color
}

private struct ManagementArchivedItemsSnapshot {
    let activeTransactions: [LedgerTransaction]
    let archivedTransactions: [LedgerTransaction]
    let archivedWallets: [LedgerWallet]
    let archivedCategories: [TransactionCategory]
    let archivedSettlementGroups: [SettlementGroup]
    let eventSubtitleByGroupID: [UUID: String]
    let settlementParticipantsByGroupID: [UUID: [SettlementParticipant]]
    let transactionsBySettlementGroupID: [UUID: [LedgerTransaction]]
    let categoryDeleteBlockersByID: [UUID: CategoryDeleteBlockers]
    let ownerMaps: MistiaRecordOwnerMaps
    let availableSelections: Set<ArchivedItemSelection>

    private let archivedTransactionsByID: [UUID: LedgerTransaction]
    private let archivedWalletsByID: [UUID: LedgerWallet]
    private let archivedCategoriesByID: [UUID: TransactionCategory]
    private let archivedSettlementGroupsByID: [UUID: SettlementGroup]

    init(
        activeTransactions: [LedgerTransaction],
        archivedTransactions: [LedgerTransaction],
        archivedWallets: [LedgerWallet],
        archivedCategories: [TransactionCategory],
        archivedSettlementGroups: [SettlementGroup],
        eventSubtitleByGroupID: [UUID: String],
        settlementParticipantsByGroupID: [UUID: [SettlementParticipant]],
        transactionsBySettlementGroupID: [UUID: [LedgerTransaction]],
        categoryDeleteBlockersByID: [UUID: CategoryDeleteBlockers],
        ownerMaps: MistiaRecordOwnerMaps,
        buildsLookupIndexes: Bool = true
    ) {
        self.activeTransactions = activeTransactions
        self.archivedTransactions = archivedTransactions
        self.archivedWallets = archivedWallets
        self.archivedCategories = archivedCategories
        self.archivedSettlementGroups = archivedSettlementGroups
        self.eventSubtitleByGroupID = eventSubtitleByGroupID
        self.settlementParticipantsByGroupID = settlementParticipantsByGroupID
        self.transactionsBySettlementGroupID = transactionsBySettlementGroupID
        self.categoryDeleteBlockersByID = categoryDeleteBlockersByID
        self.ownerMaps = ownerMaps
        self.archivedTransactionsByID = buildsLookupIndexes
            ? Dictionary(uniqueKeysWithValues: archivedTransactions.map { ($0.id, $0) })
            : [:]
        self.archivedWalletsByID = buildsLookupIndexes
            ? Dictionary(uniqueKeysWithValues: archivedWallets.map { ($0.id, $0) })
            : [:]
        self.archivedCategoriesByID = buildsLookupIndexes
            ? Dictionary(uniqueKeysWithValues: archivedCategories.map { ($0.id, $0) })
            : [:]
        self.archivedSettlementGroupsByID = buildsLookupIndexes
            ? Dictionary(uniqueKeysWithValues: archivedSettlementGroups.map { ($0.id, $0) })
            : [:]

        var selections = Set<ArchivedItemSelection>()
        selections.reserveCapacity(
            archivedTransactions.count
                + archivedWallets.count
                + archivedCategories.count
                + archivedSettlementGroups.count
        )
        for transaction in archivedTransactions {
            selections.insert(.transaction(transaction.id))
        }
        for wallet in archivedWallets {
            selections.insert(.wallet(wallet.id))
        }
        for category in archivedCategories {
            selections.insert(.category(category.id))
        }
        for group in archivedSettlementGroups {
            selections.insert(.settlementGroup(group.id))
        }
        self.availableSelections = selections
    }

    var hasArchivedItems: Bool {
        !availableSelections.isEmpty
    }

    func archivedTransaction(id: UUID) -> LedgerTransaction? {
        archivedTransactionsByID[id]
    }

    func archivedWallet(id: UUID) -> LedgerWallet? {
        archivedWalletsByID[id]
    }

    func archivedCategory(id: UUID) -> TransactionCategory? {
        archivedCategoriesByID[id]
    }

    func archivedSettlementGroup(id: UUID) -> SettlementGroup? {
        archivedSettlementGroupsByID[id]
    }
}

private struct CategoryDeleteBlockerCounts {
    var transactionCount = 0
    var billCount = 0
    var currentBudgetCount = 0
    var childCategoryCount = 0

    var snapshot: CategoryDeleteBlockers {
        CategoryDeleteBlockers(
            transactionCount: transactionCount,
            billCount: billCount,
            currentBudgetCount: currentBudgetCount,
            childCategoryCount: childCategoryCount
        )
    }
}

struct ManagementArchivedItemsView: View {
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    var isModalPresentation: Bool = false

    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var activeTransactions: [LedgerTransaction]

    @Query(filter: #Predicate<LedgerTransaction> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedTransactions: [LedgerTransaction]

    @Query(filter: #Predicate<LedgerWallet> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedWallets: [LedgerWallet]

    @Query(filter: #Predicate<TransactionCategory> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedCategories: [TransactionCategory]

    @Query(filter: #Predicate<SettlementGroup> { $0.isArchived == true && $0.deletedAt == nil }, sort: \SettlementGroup.occurredAt, order: .reverse)
    private var archivedSettlementGroups: [SettlementGroup]

    @Query
    private var allSettlementParticipants: [SettlementParticipant]

    @Query
    private var allCategories: [TransactionCategory]

    @Query
    private var allTransactions: [LedgerTransaction]

    @Query
    private var allBills: [RecurringBillPlan]

    @Query
    private var allBudgets: [BudgetPlan]

    @Query
    private var ownershipScopes: [OwnedRecordScope]

    @State private var isSelecting = false
    @State private var selectedItems: Set<ArchivedItemSelection> = []
    @State private var viewID = UUID()
    @State private var alertMessage: String?

    private var hasSelection: Bool {
        !selectedItems.isEmpty
    }

    private var navigationTitle: String {
        L10n.management.managementarchiveditems.archivedItems
    }

    private var selfUserID: UUID? {
        sessionStore.activeLocalProfileUserID ?? sessionStore.signedInUserID
    }

    var body: some View {
        let snapshot = makeArchivedSnapshot()

        MistiaPinnedTopBarScaffold(
            tone: isModalPresentation ? .modal : .standard,
            title: navigationTitle,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: isModalPresentation ? "xmark" : "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 16,
            contentBottomPadding: isSelecting ? 96 : (isModalPresentation ? 40 : 150)
        ) {
            EmptyView()
        } trailingAccessory: {
            trailingToolbarAccessory(hasArchivedItems: snapshot.hasArchivedItems)
        } content: {
            archivedContent(snapshot)
        }
        .onChange(of: isSelecting, initial: true) { _, newValue in
            uiState.requestTabBarHidden(newValue, id: viewID)
            NotificationCenter.default.post(
                name: NSNotification.Name("MistiaHideTabBar"),
                object: nil,
                userInfo: ["isHidden": newValue]
            )
        }
        .onDisappear {
            uiState.requestTabBarHidden(false, id: viewID)
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                ArchivedBottomActionBar(
                    selectedCount: selectedItems.count,
                    canRestore: hasSelection,
                    canDelete: hasSelection,
                    onRestore: restoreSelectedItems,
                    onDelete: deleteSelectedItems
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSelecting)
        .alert(
            L10n.management.managementarchiveditems.cannotRestore,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
        }
        .onChange(of: snapshot.availableSelections, initial: true) { _, newValue in
            selectedItems = selectedItems.intersection(newValue)

            if newValue.isEmpty {
                isSelecting = false
            }
        }
    }

    private func makeArchivedSnapshot(
        includesMutationIndexes: Bool = false
    ) -> ManagementArchivedItemsSnapshot {
        let ownerMaps = MistiaRecordOwnershipStore.ownerMaps(
            from: ownershipScopes,
            entities: [
                .transaction,
                .wallet,
                .category,
                .settlementGroup,
                .settlementParticipant
            ]
        )
        let activeTransactions = includesMutationIndexes
            ? MistiaRecordOwnershipStore.visibleRecords(
                self.activeTransactions,
                entity: .transaction,
                ownerMap: ownerMaps[.transaction],
                subjectUserID: selfUserID,
                signedInUserID: sessionStore.signedInUserID
            )
            : []
        let archivedTransactions = MistiaRecordOwnershipStore.visibleRecords(
            self.archivedTransactions,
            entity: .transaction,
            ownerMap: ownerMaps[.transaction],
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
        .filter { !TransactionLogic.isEventGeneratedSharedExpenseDebt($0.snapshot) }
        let archivedWallets = MistiaRecordOwnershipStore.visibleRecords(
            self.archivedWallets,
            entity: .wallet,
            ownerMap: ownerMaps[.wallet],
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
        let archivedCategories = MistiaRecordOwnershipStore.visibleRecords(
            self.archivedCategories,
            entity: .category,
            ownerMap: ownerMaps[.category],
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
        let archivedSettlementGroups = MistiaRecordOwnershipStore.visibleRecords(
            self.archivedSettlementGroups,
            entity: .settlementGroup,
            ownerMap: ownerMaps[.settlementGroup],
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
        .filter { $0.kind == .sharedExpense }
        let settlementParticipantsByGroupID = (includesMutationIndexes || !archivedSettlementGroups.isEmpty)
            ? makeSettlementParticipantsByGroupID()
            : [:]
        let transactionsBySettlementGroupID = includesMutationIndexes
            ? makeTransactionsBySettlementGroupID()
            : [:]
        let categoryDeleteBlockersByID = includesMutationIndexes
            ? makeCategoryDeleteBlockersByID()
            : [:]

        return ManagementArchivedItemsSnapshot(
            activeTransactions: activeTransactions,
            archivedTransactions: archivedTransactions,
            archivedWallets: archivedWallets,
            archivedCategories: archivedCategories,
            archivedSettlementGroups: archivedSettlementGroups,
            eventSubtitleByGroupID: makeArchivedEventSubtitles(
                for: archivedSettlementGroups,
                settlementParticipantsByGroupID: settlementParticipantsByGroupID
            ),
            settlementParticipantsByGroupID: settlementParticipantsByGroupID,
            transactionsBySettlementGroupID: transactionsBySettlementGroupID,
            categoryDeleteBlockersByID: categoryDeleteBlockersByID,
            ownerMaps: ownerMaps,
            buildsLookupIndexes: includesMutationIndexes
        )
    }

    private func makeSettlementParticipantsByGroupID() -> [UUID: [SettlementParticipant]] {
        var participantsByGroupID: [UUID: [SettlementParticipant]] = [:]
        for participant in allSettlementParticipants where participant.deletedAt == nil {
            participantsByGroupID[participant.groupID, default: []].append(participant)
        }
        return participantsByGroupID
    }

    private func makeTransactionsBySettlementGroupID() -> [UUID: [LedgerTransaction]] {
        var transactionsByGroupID: [UUID: [LedgerTransaction]] = [:]
        for transaction in allTransactions where transaction.deletedAt == nil {
            guard let groupID = transaction.settlementGroupID else { continue }
            transactionsByGroupID[groupID, default: []].append(transaction)
        }
        return transactionsByGroupID
    }

    private func makeArchivedEventSubtitles(
        for groups: [SettlementGroup],
        settlementParticipantsByGroupID: [UUID: [SettlementParticipant]]
    ) -> [UUID: String] {
        guard !groups.isEmpty else { return [:] }

        let groupIDs = Set(groups.map(\.id))
        var eventBillCountByGroupID: [UUID: Int] = [:]
        for transaction in allTransactions {
            guard let groupID = transaction.settlementGroupID,
                  groupIDs.contains(groupID),
                  SettlementLogic.isSharedExpenseEventBill(transaction) else {
                continue
            }
            eventBillCountByGroupID[groupID, default: 0] += 1
        }

        var subtitles: [UUID: String] = [:]
        subtitles.reserveCapacity(groups.count)
        for group in groups {
            let participantNames = (settlementParticipantsByGroupID[group.id] ?? [])
                .filter { !$0.isSelf }
                .sorted {
                    if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                .map(\.displayName)
                .prefix(3)
                .joined(separator: ", ")
            subtitles[group.id] = archivedEventSubtitle(
                participantNames: participantNames,
                billCount: eventBillCountByGroupID[group.id] ?? 0
            )
        }
        return subtitles
    }

    private func makeCategoryDeleteBlockersByID() -> [UUID: CategoryDeleteBlockers] {
        let currentMonth = PlanningLogic.startOfMonth(for: .now)
        var countsByCategoryID: [UUID: CategoryDeleteBlockerCounts] = [:]

        for transaction in allTransactions where transaction.deletedAt == nil {
            guard let categoryID = transaction.category?.id else { continue }
            countsByCategoryID[categoryID, default: CategoryDeleteBlockerCounts()].transactionCount += 1
        }

        for bill in allBills where bill.deletedAt == nil {
            guard let categoryID = bill.category?.id else { continue }
            countsByCategoryID[categoryID, default: CategoryDeleteBlockerCounts()].billCount += 1
        }

        for budget in allBudgets where budget.deletedAt == nil && !budget.isArchived {
            guard PlanningLogic.startOfMonth(for: budget.monthAnchor) == currentMonth,
                  let categoryID = budget.category?.id else {
                continue
            }
            countsByCategoryID[categoryID, default: CategoryDeleteBlockerCounts()].currentBudgetCount += 1
        }

        for category in allCategories where category.deletedAt == nil {
            guard let parentCategoryID = category.parentCategory?.id else { continue }
            countsByCategoryID[parentCategoryID, default: CategoryDeleteBlockerCounts()].childCategoryCount += 1
        }

        return countsByCategoryID.mapValues(\.snapshot)
    }

    @ViewBuilder
    private func archivedContent(_ snapshot: ManagementArchivedItemsSnapshot) -> some View {
        if !snapshot.hasArchivedItems {
            VStack(spacing: 16) {
                Spacer()
                    .frame(height: 80)

                Image(systemName: "archivebox")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.tertiary)

                Text(L10n.management.managementarchiveditems.noArchivedItems)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(
                    L10n.management.managementarchiveditems.youDonTHaveAnyArchivedItems
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        } else {
            if !snapshot.archivedSettlementGroups.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.events,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(snapshot.archivedSettlementGroups) { group in
                        ArchivedDetailRow(
                            title: group.title,
                            subtitle: snapshot.eventSubtitleByGroupID[group.id] ?? archivedEventSubtitle(
                                participantNames: "",
                                billCount: 0
                            ),
                            icon: "mistia.settlement.event",
                            iconTint: MistiaAccent.teal.color,
                            archivedAt: group.archivedAt,
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.settlementGroup(group.id)),
                            onToggleSelection: { toggleSelection(.settlementGroup(group.id)) },
                            onRestore: { restoreSelections([.settlementGroup(group.id)]) },
                            onDelete: { deleteSelections([.settlementGroup(group.id)]) }
                        )
                    }
                }
            }

            if !snapshot.archivedTransactions.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.transactions,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(snapshot.archivedTransactions) { transaction in
                        ArchivedTransactionRow(
                            descriptor: descriptor(for: transaction),
                            archivedAt: transaction.archivedAt,
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.transaction(transaction.id)),
                            onToggleSelection: { toggleSelection(.transaction(transaction.id)) },
                            onRestore: { restoreSelections([.transaction(transaction.id)]) },
                            onDelete: { deleteSelections([.transaction(transaction.id)]) }
                        )
                    }
                }
            }

            if !snapshot.archivedWallets.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.wallets,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(snapshot.archivedWallets) { wallet in
                        ArchivedDetailRow(
                            title: wallet.name,
                            subtitle: "\(wallet.kind.title) • \(wallet.currencyCode)",
                            icon: wallet.iconSymbolName,
                            iconTint: Color(hex: wallet.iconColorHex),
                            archivedAt: wallet.archivedAt,
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.wallet(wallet.id)),
                            onToggleSelection: { toggleSelection(.wallet(wallet.id)) },
                            onRestore: { restoreSelections([.wallet(wallet.id)]) },
                            onDelete: { deleteSelections([.wallet(wallet.id)]) }
                        )
                    }
                }
            }

            if !snapshot.archivedCategories.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.categories,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(snapshot.archivedCategories) { category in
                        ArchivedDetailRow(
                            title: category.name,
                            subtitle: categorySubtitle(for: category),
                            icon: category.iconSymbolName,
                            iconTint: Color(hex: category.iconColorHex),
                            archivedAt: category.archivedAt,
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.category(category.id)),
                            onToggleSelection: { toggleSelection(.category(category.id)) },
                            onRestore: { restoreSelections([.category(category.id)]) },
                            onDelete: { deleteSelections([.category(category.id)]) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trailingToolbarAccessory(hasArchivedItems: Bool) -> some View {
        if isSelecting {
            MistiaHeaderCircleButton(action: exitSelectionMode) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
        } else if hasArchivedItems {
            MistiaHeaderCircleButton(action: enterSelectionMode) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private func categorySubtitle(for category: TransactionCategory) -> String {
        if let parentName = category.parentCategory?.localizedDisplayName {
            return "\(category.kind.title) • \(parentName)"
        }

        return category.kind.title
    }

    private func archivedEventSubtitle(participantNames: String, billCount: Int) -> String {
        let participantText = participantNames.isEmpty
            ? L10n.transactions.settlement.noParticipantsYet
            : participantNames
        return "\(participantText) • \(L10n.transactions.settlement.billCountValue(String(billCount)))"
    }

    private func descriptor(for transaction: LedgerTransaction) -> ArchivedTransactionDescriptor {
        let defaultWalletTitle = L10n.management.managementarchiveditems.noWalletSelected
        let defaultCategoryTitle = L10n.management.managementarchiveditems.noCategorySelected
        let currency = transaction.sourceWallet?.currencyCode ?? transaction.destinationWallet?.currencyCode ?? currencyCode
        let rawAmount = transaction.amountMinor.formattedCurrency(code: currency)
        let title = transactionTitle(for: transaction)

        switch transaction.primaryKind {
        case .expense:
            return ArchivedTransactionDescriptor(
                title: title,
                subtitle: "\(transaction.sourceWallet?.name ?? defaultWalletTitle) • \(transaction.category?.localizedDisplayName ?? defaultCategoryTitle)",
                icon: transaction.category?.iconSymbolName ?? transaction.primaryKind.financeIconToken,
                iconTint: transaction.category.map { Color(hex: $0.iconColorHex) } ?? MistiaAccent.expense.color,
                badgeTitle: transaction.primaryKind.title,
                badgeTint: MistiaAccent.expense.color,
                amountText: "-" + rawAmount,
                amountTint: MistiaAccent.expense.color
            )
        case .income:
            return ArchivedTransactionDescriptor(
                title: title,
                subtitle: "\(transaction.sourceWallet?.name ?? defaultWalletTitle) • \(transaction.category?.localizedDisplayName ?? defaultCategoryTitle)",
                icon: transaction.category?.iconSymbolName ?? transaction.primaryKind.financeIconToken,
                iconTint: transaction.category.map { Color(hex: $0.iconColorHex) } ?? MistiaAccent.income.color,
                badgeTitle: transaction.primaryKind.title,
                badgeTint: MistiaAccent.income.color,
                amountText: "+" + rawAmount,
                amountTint: MistiaAccent.income.color
            )
        case .transfer:
            switch transaction.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                let source = transaction.sourceWallet?.name ?? L10n.management.managementarchiveditems.source
                let destination = transaction.destinationWallet?.name ?? L10n.management.managementarchiveditems.destination
                let transferTint = colorScheme == .dark ? .white : MistiaAccent.transfer.color

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: "\(source) → \(destination)",
                    icon: TransactionTransferSubtype.internalTransfer.financeIconToken,
                    iconTint: transferTint,
                    badgeTitle: L10n.management.managementarchiveditems.transfer,
                    badgeTint: transferTint,
                    amountText: rawAmount,
                    amountTint: transferTint
                )
            case .familyTransfer:
                let cashflow = TransactionLogic.cashflowAmount(for: transaction.snapshot)
                let familyTint: Color
                let amountText: String

                if cashflow < 0 {
                    familyTint = MistiaAccent.expense.color
                    amountText = "-" + rawAmount
                } else if cashflow > 0 {
                    familyTint = MistiaAccent.income.color
                    amountText = "+" + rawAmount
                } else {
                    familyTint = colorScheme == .dark ? .white : MistiaAccent.transfer.color
                    amountText = rawAmount
                }

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: transaction.note?.nilIfBlank ?? transaction.sourceWallet?.name ?? defaultWalletTitle,
                    icon: TransactionTransferSubtype.familyTransfer.financeIconToken,
                    iconTint: familyTint,
                    badgeTitle: L10n.shared.corelogic.financeenums.family,
                    badgeTint: familyTint,
                    amountText: amountText,
                    amountTint: familyTint
                )
            case .debt:
                let cashflow = debtCashflow(for: transaction)
                let personName = transaction.counterpartyName ?? L10n.management.managementarchiveditems.unknownName
                let walletName = transaction.sourceWallet?.name ?? defaultWalletTitle
                let debtTint: Color
                let amountText: String

                if cashflow < 0 {
                    debtTint = MistiaAccent.expense.color
                    amountText = "-" + rawAmount
                } else if cashflow > 0 {
                    debtTint = MistiaAccent.income.color
                    amountText = "+" + rawAmount
                } else {
                    debtTint = Color(red: 0.29, green: 0.56, blue: 0.96)
                    amountText = rawAmount
                }

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: "\(personName) • \(transaction.debtIntent?.title ?? L10n.management.managementarchiveditems.debt) • \(walletName)",
                    icon: transaction.debtIntent?.financeIconToken ?? TransactionTransferSubtype.debt.financeIconToken,
                    iconTint: debtTint,
                    badgeTitle: L10n.management.managementarchiveditems.debt,
                    badgeTint: Color(red: 0.29, green: 0.56, blue: 0.96),
                    amountText: amountText,
                    amountTint: debtTint
                )
            }
        }
    }

    private func transactionTitle(for transaction: LedgerTransaction) -> String {
        let trimmedTitle = transaction.localizedTransactionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        switch transaction.primaryKind {
        case .expense:
            return transaction.category?.localizedDisplayName
                ?? L10n.management.managementarchiveditems.expense
        case .income:
            return transaction.category?.localizedDisplayName
                ?? L10n.management.managementarchiveditems.income
        case .transfer:
            switch transaction.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                return L10n.management.managementarchiveditems.internalTransfer
            case .familyTransfer:
                return L10n.shared.corelogic.financeenums.family
            case .debt:
                return transaction.debtIntent?.title
                    ?? L10n.management.managementarchiveditems.debtTransaction
            }
        }
    }

    private func debtCashflow(for transaction: LedgerTransaction) -> Int64 {
        switch transaction.debtIntent {
        case .lend, .repay:
            return -transaction.amountMinor
        case .collect, .borrow:
            return transaction.amountMinor
        case nil:
            return 0
        }
    }

    private func enterSelectionMode() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isSelecting = true
        }
    }

    private func exitSelectionMode() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isSelecting = false
            selectedItems.removeAll()
        }
    }

    private func toggleSelection(_ selection: ArchivedItemSelection) {
        guard isSelecting else { return }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
            if selectedItems.contains(selection) {
                selectedItems.remove(selection)
            } else {
                selectedItems.insert(selection)
            }
        }
    }

    private func restoreSelectedItems() {
        guard hasSelection else { return }
        restoreSelections(Array(selectedItems))
    }

    private func deleteSelectedItems() {
        guard hasSelection else { return }
        deleteSelections(Array(selectedItems))
    }

    private func restoreSelections(_ selections: [ArchivedItemSelection]) {
        guard !selections.isEmpty else { return }

        if applyArchivedMutation(to: selections, action: .restore) {
            exitSelectionMode()
        }
    }

    private func deleteSelections(_ selections: [ArchivedItemSelection]) {
        guard !selections.isEmpty else { return }

        if applyArchivedMutation(to: selections, action: .delete) {
            exitSelectionMode()
        }
    }

    @discardableResult
    private func applyArchivedMutation(
        to selections: [ArchivedItemSelection],
        action: ArchivedMutationAction
    ) -> Bool {
        let now = Date.now
        var mutations: [ArchivedSyncMutation] = []
        let snapshot = makeArchivedSnapshot(includesMutationIndexes: true)

        do {
            for selection in selections {
                switch selection {
                case .transaction(let id):
                    guard let transaction = snapshot.archivedTransaction(id: id) else { continue }
                    try prepareTransactionMutation(
                        transaction,
                        action: action,
                        at: now,
                        snapshot: snapshot,
                        mutations: &mutations
                    )
                case .wallet(let id):
                    guard let wallet = snapshot.archivedWallet(id: id) else { continue }
                    prepareWalletMutation(
                        wallet,
                        action: action,
                        at: now,
                        snapshot: snapshot,
                        mutations: &mutations
                    )
                case .category(let id):
                    guard let category = snapshot.archivedCategory(id: id) else { continue }
                    try prepareCategoryMutation(
                        category,
                        action: action,
                        at: now,
                        snapshot: snapshot,
                        mutations: &mutations
                    )
                case .settlementGroup(let id):
                    guard let group = snapshot.archivedSettlementGroup(id: id) else { continue }
                    try prepareSettlementGroupMutation(
                        group,
                        action: action,
                        at: now,
                        snapshot: snapshot,
                        mutations: &mutations
                    )
                }
            }

            try modelContext.save()

            let fallbackUserID = selfUserID ?? UUID()
            let syncMutations: [MistiaSyncMutation] = mutations.map { mutation in
                MistiaSyncMutation(
                    entity: mutation.entity,
                    recordID: mutation.id,
                    subjectUserID: mutation.subjectUserIDOverride ?? fallbackUserID,
                    kind: mutation.action == .restore ? .upsert : .delete,
                    modifiedAt: mutation.updatedAt,
                    baseVersion: mutation.baseVersion
                )
            }

            sessionStore.recordMutations(syncMutations)

            let ownerUserIDs = Set(syncMutations.map(\.subjectUserID))
            if ownerUserIDs.contains(where: { $0 != sessionStore.activeLocalProfileUserID }) {
                Task { @MainActor in
                    _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
                }
            }

            return true
        } catch {
            print("Failed to mutate archived selections: \(error)")
            return false
        }
    }

    private func prepareTransactionMutation(
        _ transaction: LedgerTransaction,
        action: ArchivedMutationAction,
        at date: Date,
        snapshot: ManagementArchivedItemsSnapshot,
        mutations: inout [ArchivedSyncMutation]
    ) throws {
        if action == .restore && isCreditCardPayment(transaction) {
            let calendar = MistiaCalendar.current
            let isDuplicate = snapshot.activeTransactions.contains { tx in
                tx.id != transaction.id &&
                tx.destinationWallet?.id == transaction.destinationWallet?.id &&
                calendar.isDate(tx.occurredAt, equalTo: transaction.occurredAt, toGranularity: .month) &&
                TransactionLogic.isCreditCardPayment(tx.snapshot)
            }

            if isDuplicate {
                let monthStr = MistiaDateFormatting.monthYearString(for: transaction.occurredAt, calendar: calendar)
                alertMessage = L10n.management.managementarchiveditems.monthValueAlreadyHasACardPayment(String(describing: monthStr))
                throw MistiaRestoreError.duplicatePayment
            }
        }

        if let actorUserID = sessionStore.activeLocalProfileUserID {
            try TransactionAuditStore.touch(
                transactionID: transaction.id,
                actorUserID: actorUserID,
                fallbackCreatedByUserID: actorUserID,
                updatedAt: date,
                context: modelContext
            )
        }

        switch action {
        case .restore:
            transaction.isArchived = false
            transaction.archivedAt = nil
            transaction.updatedAt = date
        case .delete:
            transaction.markDeleted(at: date)
        }

        mutations.append(
            ArchivedSyncMutation(
                entity: .transaction,
                id: transaction.id,
                updatedAt: transaction.updatedAt,
                subjectUserIDOverride: transactionOwnerUserID(for: transaction, ownerMaps: snapshot.ownerMaps),
                action: action,
                baseVersion: transaction.remoteVersion
            )
        )
    }

    private func prepareWalletMutation(
        _ wallet: LedgerWallet,
        action: ArchivedMutationAction,
        at date: Date,
        snapshot: ManagementArchivedItemsSnapshot,
        mutations: inout [ArchivedSyncMutation]
    ) {
        switch action {
        case .restore:
            wallet.isArchived = false
            wallet.archivedAt = nil
            wallet.updatedAt = date
        case .delete:
            wallet.markDeleted(at: date)
        }

        mutations.append(
            ArchivedSyncMutation(
                entity: .wallet,
                id: wallet.id,
                updatedAt: wallet.updatedAt,
                subjectUserIDOverride: walletOwnerUserID(for: wallet, ownerMaps: snapshot.ownerMaps),
                action: action,
                baseVersion: wallet.remoteVersion
            )
        )
    }

    private func prepareCategoryMutation(
        _ category: TransactionCategory,
        action: ArchivedMutationAction,
        at date: Date,
        snapshot: ManagementArchivedItemsSnapshot,
        mutations: inout [ArchivedSyncMutation]
    ) throws {
        if action == .delete {
            let blockers = categoryDeleteBlockers(for: category, snapshot: snapshot)
            guard blockers.isEmpty else {
                alertMessage = L10n.management.managementarchiveditems.categoryDeleteBlockedWithCounts(
                    String(describing: blockers.transactionCount),
                    String(describing: blockers.billCount),
                    String(describing: blockers.currentBudgetCount),
                    String(describing: blockers.childCategoryCount)
                )
                throw MistiaRestoreError.categoryDependency
            }
        }

        switch action {
        case .restore:
            category.isArchived = false
            category.archivedAt = nil
            category.updatedAt = date
        case .delete:
            category.markDeleted(at: date)
        }

        mutations.append(
            ArchivedSyncMutation(
                entity: .category,
                id: category.id,
                updatedAt: category.updatedAt,
                subjectUserIDOverride: categoryOwnerUserID(for: category, ownerMaps: snapshot.ownerMaps),
                action: action,
                baseVersion: category.remoteVersion
            )
        )
    }

    private func prepareSettlementGroupMutation(
        _ group: SettlementGroup,
        action: ArchivedMutationAction,
        at date: Date,
        snapshot: ManagementArchivedItemsSnapshot,
        mutations: inout [ArchivedSyncMutation]
    ) throws {
        let ownerUserID = settlementGroupOwnerUserID(for: group, ownerMaps: snapshot.ownerMaps)

        switch action {
        case .restore:
            group.isArchived = false
            group.archivedAt = nil
            group.updatedAt = date
            mutations.append(
                ArchivedSyncMutation(
                    entity: .settlementGroup,
                    id: group.id,
                    updatedAt: group.updatedAt,
                    subjectUserIDOverride: ownerUserID,
                    action: .restore,
                    baseVersion: group.remoteVersion
                )
            )
        case .delete:
            let participants = snapshot.settlementParticipantsByGroupID[group.id] ?? []
            let groupTransactions = snapshot.transactionsBySettlementGroupID[group.id] ?? []
            let actorUserID = sessionStore.activeLocalProfileUserID

            group.markDeleted(at: date)
            mutations.append(
                ArchivedSyncMutation(
                    entity: .settlementGroup,
                    id: group.id,
                    updatedAt: group.updatedAt,
                    subjectUserIDOverride: ownerUserID,
                    action: .delete,
                    baseVersion: group.remoteVersion
                )
            )

            for participant in participants {
                participant.markDeleted(at: date)
                mutations.append(
                    ArchivedSyncMutation(
                        entity: .settlementParticipant,
                        id: participant.id,
                        updatedAt: participant.updatedAt,
                        subjectUserIDOverride: settlementParticipantOwnerUserID(
                            for: participant,
                            fallback: ownerUserID,
                            ownerMaps: snapshot.ownerMaps
                        ),
                        action: .delete,
                        baseVersion: participant.remoteVersion
                    )
                )
            }

            for transaction in groupTransactions {
                if transaction.settlementRole == .sharedExpensePaid {
                    transaction.settlementGroupID = nil
                    transaction.settlementObligationID = nil
                    transaction.settlementRoleRawValue = nil
                    transaction.reportingExpenseMinor = nil
                    transaction.reportingIncomeMinor = nil
                    transaction.updatedAt = date
                    if let actorUserID {
                        try TransactionAuditStore.touch(
                            transactionID: transaction.id,
                            actorUserID: actorUserID,
                            fallbackCreatedByUserID: actorUserID,
                            updatedAt: date,
                            context: modelContext
                        )
                    }
                    mutations.append(
                        ArchivedSyncMutation(
                            entity: .transaction,
                            id: transaction.id,
                            updatedAt: transaction.updatedAt,
                            subjectUserIDOverride: transactionOwnerUserID(
                                for: transaction,
                                ownerMaps: snapshot.ownerMaps
                            ),
                            action: .restore,
                            baseVersion: transaction.remoteVersion
                        )
                    )
                } else if TransactionLogic.isEventGeneratedSharedExpenseDebt(transaction.snapshot) {
                    transaction.markDeleted(at: date)
                    transaction.isArchived = true
                    if let actorUserID {
                        try TransactionAuditStore.touch(
                            transactionID: transaction.id,
                            actorUserID: actorUserID,
                            fallbackCreatedByUserID: actorUserID,
                            updatedAt: date,
                            context: modelContext
                        )
                    }
                    mutations.append(
                        ArchivedSyncMutation(
                            entity: .transaction,
                            id: transaction.id,
                            updatedAt: transaction.updatedAt,
                            subjectUserIDOverride: transactionOwnerUserID(
                                for: transaction,
                                ownerMaps: snapshot.ownerMaps
                            ),
                            action: .delete,
                            baseVersion: transaction.remoteVersion
                        )
                    )
                }
            }
        }
    }

    private func categoryDeleteBlockers(
        for category: TransactionCategory,
        snapshot: ManagementArchivedItemsSnapshot
    ) -> CategoryDeleteBlockers {
        snapshot.categoryDeleteBlockersByID[category.id] ?? CategoryDeleteBlockers(
            transactionCount: 0,
            billCount: 0,
            currentBudgetCount: 0,
            childCategoryCount: 0
        )
    }

    private func isCreditCardPayment(_ transaction: LedgerTransaction) -> Bool {
        TransactionLogic.isCreditCardPayment(transaction.snapshot)
    }

    private func transactionOwnerUserID(
        for transaction: LedgerTransaction,
        ownerMaps: MistiaRecordOwnerMaps
    ) -> UUID? {
        ownerMaps[.transaction][transaction.id]
            ?? transaction.sourceWallet.flatMap { walletOwnerUserID(for: $0, ownerMaps: ownerMaps) }
            ?? transaction.destinationWallet.flatMap { walletOwnerUserID(for: $0, ownerMaps: ownerMaps) }
            ?? selfUserID
    }

    private func walletOwnerUserID(
        for wallet: LedgerWallet,
        ownerMaps: MistiaRecordOwnerMaps
    ) -> UUID? {
        ownerMaps[.wallet][wallet.id] ?? selfUserID
    }

    private func categoryOwnerUserID(
        for category: TransactionCategory,
        ownerMaps: MistiaRecordOwnerMaps
    ) -> UUID? {
        ownerMaps[.category][category.id] ?? selfUserID
    }

    private func settlementGroupOwnerUserID(
        for group: SettlementGroup,
        ownerMaps: MistiaRecordOwnerMaps
    ) -> UUID? {
        ownerMaps[.settlementGroup][group.id] ?? group.organizerUserID ?? selfUserID
    }

    private func settlementParticipantOwnerUserID(
        for participant: SettlementParticipant,
        fallback: UUID?,
        ownerMaps: MistiaRecordOwnerMaps
    ) -> UUID? {
        ownerMaps[.settlementParticipant][participant.id] ?? fallback ?? selfUserID
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum ArchivedMutationAction {
    case restore
    case delete
}

private struct ArchivedTransactionRow: View {
    let descriptor: ArchivedTransactionDescriptor
    let archivedAt: Date?
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ArchivedBaseRow(
            title: descriptor.title,
            subtitle: descriptor.subtitle,
            icon: descriptor.icon,
            iconTint: descriptor.iconTint,
            archivedAt: archivedAt,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onToggleSelection: onToggleSelection
        ) {
            EmptyView()
        } trailingContent: {
            HStack(spacing: 12) {
                Text(descriptor.amountText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(descriptor.amountTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelecting)
        }
    }
}

private struct ArchivedDetailRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let archivedAt: Date?
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ArchivedBaseRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconTint: iconTint,
            archivedAt: archivedAt,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onToggleSelection: onToggleSelection
        ) {
            EmptyView()
        } trailingContent: {
            EmptyView()
        }
    }
}

private struct ArchivedBaseRow<TitleAccessory: View, TrailingContent: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let archivedAt: Date?
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    @ViewBuilder let titleAccessory: TitleAccessory
    @ViewBuilder let trailingContent: TrailingContent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(icon: icon, fallbackColor: iconTint, size: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    titleAccessory
                }

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let archivedAt {
                    Text(retentionText(for: archivedAt))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(retentionColor(for: archivedAt))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailingContent

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? MistiaAccent.lightPurple.color
                            : Color.secondary.opacity(0.45)
                    )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelecting)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            colorScheme == .dark
                ? Color(UIColor.secondarySystemGroupedBackground)
                : .white.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if isSelecting {
                onToggleSelection()
            }
        }
    }

    private func retentionText(for archivedAt: Date) -> String {
        MistiaArchiveRetention.remainingDaysText(archivedAt: archivedAt)
    }

    private func retentionColor(for archivedAt: Date) -> Color {
        let days = MistiaArchiveRetention.daysRemaining(archivedAt: archivedAt)
        return MistiaArchiveRetention.isUrgent(daysRemaining: days) ? .red : .secondary
    }
}

private struct ArchivedBottomActionBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedCount: Int
    let canRestore: Bool
    let canDelete: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(colorScheme == .dark ? 0.3 : 0.5)

            actionRow
                .padding(.horizontal, 20)

            // Bù khoảng trống cho Home Indicator để icon không bị đè
            Spacer(minLength: 0)
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .background {
            (colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.42))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var actionRow: some View {
        HStack(alignment: .center, spacing: 16) {
            ArchivedBottomActionMenu(
                accessibilityTitle: L10n.management.managementarchiveditems.restore,
                systemImage: "arrow.uturn.backward",
                isEnabled: canRestore,
                tint: .primary
            ) {
                Section {
                    Button {
                        onRestore()
                    } label: {
                        Label(
                            L10n.management.managementarchiveditems.restore,
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                } header: {
                    Text(
                        L10n.management.managementarchiveditems.theSelectedItemsWillBeRestoredTo
                    )
                }
            }

            Spacer(minLength: 12)

            Text(selectionText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 12)

            ArchivedBottomActionMenu(
                accessibilityTitle: L10n.common.delete,
                systemImage: "trash",
                isEnabled: canDelete,
                tint: .red
            ) {
                Section {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(
                            L10n.management.managementarchiveditems.deletePermanently,
                            systemImage: "trash"
                        )
                    }
                } header: {
                    Text(
                        L10n.management.managementarchiveditems.theseItemsWillBeRemovedFromThe
                    )
                }
            }
        }
        .frame(height: 49)
    }

    private var barBackground: some View {
        ZStack {
            Rectangle()
                .fill(colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.42))
        }
    }

    private var selectionText: String {
        if selectedCount == 0 {
            return L10n.management.managementarchiveditems.selectItems
        }

        return L10n.management.managementarchiveditems.valueSelected(String(describing: selectedCount))
    }
}

private struct ArchivedBottomActionMenu<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let accessibilityTitle: String
    let systemImage: String
    let isEnabled: Bool
    let tint: Color
    @ViewBuilder let content: Content

    private let visualSize: CGFloat = 36
    private let touchTargetSize: CGFloat = 42

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Menu {
                    content
                } label: {
                    label
                }
                .menuIndicator(.hidden)
                .menuOrder(.fixed)
                .menuStyle(.button)
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.circle)
            } else {
                Menu {
                    content
                } label: {
                    label
                        .background {
                            ArchivedBottomActionButtonBackground(isEnabled: isEnabled)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(borderColor, lineWidth: 0.8)
                        }
                }
                .menuIndicator(.hidden)
                .menuOrder(.fixed)
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .disabled(!isEnabled)
        .frame(width: touchTargetSize, height: touchTargetSize)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isEnabled)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(.isButton)
        .opacity(isEnabled ? 1 : 0.46)
        .scaleEffect(isEnabled ? 1 : 0.98)
    }

    private var label: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconColor)
            .frame(width: visualSize, height: visualSize)
    }

    private var iconColor: Color {
        isEnabled ? tint : .primary.opacity(0.25)
    }

    private var borderColor: Color {
        .white.opacity(colorScheme == .dark ? 0.14 : 0.20)
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        var style = Glass.regular.tint(
            .white.opacity(colorScheme == .dark ? (isEnabled ? 0.08 : 0.04) : (isEnabled ? 0.14 : 0.08))
        )
        if isEnabled {
            style = style.interactive(true)
        }
        return style
    }
}

private struct ArchivedBottomActionButtonBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let isEnabled: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(nativeGlassStyle, in: .circle)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(fallbackTint)
                    }
            }
        }
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.16), lineWidth: 0.5)
        }
    }

    private var fallbackTint: Color {
        .white.opacity(isEnabled ? (colorScheme == .dark ? 0.08 : 0.14) : (colorScheme == .dark ? 0.04 : 0.08))
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        var style = Glass.regular.tint(
            .white.opacity(isEnabled ? (colorScheme == .dark ? 0.10 : 0.16) : (colorScheme == .dark ? 0.05 : 0.10))
        )
        if isEnabled {
            style = style.interactive(true)
        }
        return style
    }
}
