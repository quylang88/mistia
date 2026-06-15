import SwiftData
import SwiftUI

private enum TransactionSegment: String, CaseIterable, Hashable {
    case expense
    case income
    case transfer
    case event
    case adjustment

    var title: String {
        switch self {
        case .expense:
            L10n.transactions.transactions.expense2
        case .income:
            L10n.transactions.transactions.income2
        case .transfer:
            L10n.transactions.transactions.transfer
        case .event:
            "Sự kiện"
        case .adjustment:
            L10n.transactions.transactions.adjustment
        }
    }

    var tint: Color {
        MistiaAccent.purple.color
    }

    var kind: TransactionPrimaryKind? {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        case .event, .adjustment:
            return nil
        }
    }
}

private enum TransactionsNavigationDestination: String, Identifiable {
    case aiBill

    var id: String { rawValue }
}

private struct TransactionsPermissionPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
}

private struct TransactionsInfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TransactionsFamilyOwnerConflictAlert: Identifiable {
    let entity: MistiaSyncEntity
    let recordID: UUID

    var id: String {
        FamilyOwnerPushConflict.key(entity: entity, recordID: recordID)
    }
}

private enum TransactionsAlertPresentation: Identifiable {
    case info(TransactionsInfoAlert)
    case permission(TransactionsPermissionPrompt)
    case familyOwnerConflict(TransactionsFamilyOwnerConflictAlert)

    var id: String {
        switch self {
        case .info(let alert):
            return alert.id.uuidString
        case .permission(let prompt):
            return prompt.id.uuidString
        case .familyOwnerConflict(let alert):
            return alert.id
        }
    }

    var title: String {
        switch self {
        case .info(let alert):
            alert.title
        case .permission(let prompt):
            prompt.title
        case .familyOwnerConflict:
            L10n.shared.sync.familyOwnerPushConflict.alertTitle
        }
    }

    var message: String {
        switch self {
        case .info(let alert):
            alert.message
        case .permission(let prompt):
            prompt.message
        case .familyOwnerConflict:
            L10n.shared.sync.familyOwnerPushConflict.alertMessage
        }
    }
}

private enum TransactionsListPaging {
    static let initialLimit = 60
    static let increment = 40
}

private func debtIntentTint(_ intent: TransactionDebtIntent?) -> Color {
    switch intent {
    case .lend:
        MistiaAccent.debtLend.color
    case .collect:
        MistiaAccent.debtCollect.color
    case .borrow:
        MistiaAccent.debtBorrow.color
    case .repay:
        MistiaAccent.debtRepay.color
    case nil:
        MistiaAccent.slate.color
    }
}

struct TransactionsListSnapshot {
    let activeTransactionCount: Int
    let visibleRecordCount: Int
    let displayedRecordCount: Int
    let hasAdjustments: Bool
    let debtCounterpartyFilterOptions: [DebtCounterpartyFilterOption]
    let preparingSettlementEvents: [PreparingSettlementEventSnapshot]
    let allSettlementEvents: [PreparingSettlementEventSnapshot]
    let openDebtPositions: [CounterpartyDebtSnapshot]
    let openReceivableDebtTotals: [PlanningCurrencyAmountTotalSnapshot]
    let sections: [TransactionSectionSnapshot]
    let transactionsByID: [UUID: LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]

    var hasMoreRows: Bool {
        displayedRecordCount < visibleRecordCount
    }
}

private struct TransactionsListSnapshotCache {
    let key: TransactionsListSnapshotCacheKey
    let snapshot: TransactionsListSnapshot
}

private struct TransactionsListSnapshotCacheKey: Hashable {
    let selectedSegmentRawValue: String?
    let isAdjustmentOnly: Bool
    let timeScopeRawValue: String
    let walletID: UUID?
    let categoryID: UUID?
    let transferSubtypeRawValue: String?
    let counterpartyDebtKey: String?
    let statusScopeRawValue: String
    let minAmountMinor: Int64?
    let maxAmountMinor: Int64?
    let searchText: String
    let visibleTransactionLimit: Int
    let calendarIdentifier: String
    let calendarTimeZoneIdentifier: String
    let localeIdentifier: String
    let activeScope: FamilyContext.Scope
    let selectedSubjectUserID: UUID?
    let currentUserID: UUID?
    let activeLocalProfileUserID: UUID?
    let signedInUserID: UUID?
    let familyID: UUID?
    let familyAccessSignature: Int
    let transactionSignature: MistiaCollectionChangeSignature
    let settlementGroupSignature: MistiaCollectionChangeSignature?
    let settlementParticipantSignature: MistiaCollectionChangeSignature?
    let ownershipSignature: MistiaCollectionChangeSignature
    let auditSignature: MistiaCollectionChangeSignature
}

struct DebtCounterpartyFilterOption: Equatable, Identifiable {
    let id: String
    let displayName: String
}

struct TransactionsView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var currencyRateMode = MistiaCurrencyRateMode.automatic.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = ""
    @AppStorage(MistiaCurrencySettings.StorageKey.cachedRatesData) private var cachedCurrencyRatesData = Data()

    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived }, sort: \LedgerTransaction.occurredAt, order: .reverse)
    private var storedTransactions: [LedgerTransaction]
    @Query private var storedWallets: [LedgerWallet]
    @Query private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<SettlementGroup> { $0.deletedAt == nil }, sort: \SettlementGroup.occurredAt, order: .reverse)
    private var storedSettlementGroups: [SettlementGroup]
    @Query(filter: #Predicate<SettlementParticipant> { $0.deletedAt == nil }, sort: \SettlementParticipant.sortOrder)
    private var storedSettlementParticipants: [SettlementParticipant]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @Query private var transactionAuditRecords: [TransactionAuditRecord]

    @State private var selectedSegment: TransactionSegment? = nil
    @State private var editorTarget: TransactionEditorTarget?
    @State private var filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearchPresented = false
    @State private var visibleSearchResultLimit = TransactionsListPaging.initialLimit
    @State private var shareItem: TransactionShareItem?
    @State private var exportErrorMessage: String?
    @State private var destination: TransactionsNavigationDestination?
    @State private var debtSettlementTarget: DebtSettlementSheetTarget?
    @State private var settlementEditorTarget: SettlementEditorTarget?
    @State private var preparingSettlementTarget: PreparingSettlementEventSheetTarget?
    @State private var permissionPrompt: TransactionsPermissionPrompt?
    @State private var infoAlert: TransactionsInfoAlert?
    @State private var familyOwnerConflictAlert: TransactionsFamilyOwnerConflictAlert?
    @State private var memberViewingExitPrompt: FamilyMemberViewingExitPrompt?
    @State private var visibleTransactionLimit = TransactionsListPaging.initialLimit
    @State private var listSnapshotCache: TransactionsListSnapshotCache?
    @State private var searchSnapshotCache: TransactionsListSnapshotCache?

    private var activeTransactions: [LedgerTransaction] {
        visibleTransactions
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.createdAt > $1.createdAt
            }
    }

    private var activeWallets: [LedgerWallet] {
        visibleWallets
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var appExchangeRates: [MistiaExchangeRate] {
        _ = currencyRateMode
        _ = manualJPYToVNDRate
        _ = cachedCurrencyRatesData
        return MistiaCurrencySettings.rates()
    }

    private var activeAlert: TransactionsAlertPresentation? {
        if let familyOwnerConflictAlert {
            return .familyOwnerConflict(familyOwnerConflictAlert)
        }
        if let permissionPrompt {
            return .permission(permissionPrompt)
        }
        if let infoAlert {
            return .info(infoAlert)
        }
        return nil
    }

    private var activeCategorySections: [TransactionCategoryGroupSection] {
        switch selectedSegment?.kind {
        case .expense:
            return MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .expense,
                includeArchived: false,
                includeEmptyParents: false
            )
        case .income:
            return MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .income,
                includeArchived: false,
                includeEmptyParents: false
            )
        case .transfer:
            return []
        case nil:
            return MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .expense,
                includeArchived: false,
                includeEmptyParents: false
            ) + MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .income,
                includeArchived: false,
                includeEmptyParents: false
            )
        }
    }

    private var visibleTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForHistory(
            storedTransactions,
            audits: transactionAuditRecords,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleWallets: [LedgerWallet] {
        FamilyScopedData.visible(
            storedWallets,
            entity: .wallet,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleCategories: [TransactionCategory] {
        FamilyScopedData.visible(
            storedCategories,
            entity: .category,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleSettlementGroups: [SettlementGroup] {
        FamilyScopedData.visible(
            storedSettlementGroups,
            entity: .settlementGroup,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleSettlementParticipants: [SettlementParticipant] {
        FamilyScopedData.visible(
            storedSettlementParticipants,
            entity: .settlementParticipant,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var transactionAuditMap: [UUID: TransactionAuditRecord] {
        TransactionAuditStore.auditMap(from: transactionAuditRecords)
    }

    private var transactionListSnapshot: TransactionsListSnapshot {
        let activeTransactions = self.activeTransactions
        let records = activeTransactions.map(\.snapshot)
        let settlementGroupSnapshots = visibleSettlementGroups.map(\.recordSnapshot)
        let settlementParticipantSnapshots = visibleSettlementParticipants.map(\.recordSnapshot)
        let page = TransactionLogic.visibleRecordsPage(
            from: records,
            selectedKind: selectedSegment?.kind,
            filters: effectiveFilters,
            limit: visibleTransactionLimit,
            assumesSortedByRecency: true,
            calendar: calendar
        )
        let displayedRecords = page.displayedRecords
        let displayedRecordIDs = Set(displayedRecords.map(\.id))
        let openDebtPositions = TransactionLogic.openDebtPositions(
            from: debtRecords(from: records)
        )

        return TransactionsListSnapshot(
            activeTransactionCount: activeTransactions.count,
            visibleRecordCount: page.totalCount,
            displayedRecordCount: displayedRecords.count,
            hasAdjustments: records.contains { TransactionLogic.isAdjustment($0) },
            debtCounterpartyFilterOptions: debtCounterpartyFilterOptions(from: records),
            preparingSettlementEvents: SettlementLogic.preparingEventSnapshots(
                groups: settlementGroupSnapshots,
                participants: settlementParticipantSnapshots,
                records: records
            ),
            allSettlementEvents: SettlementLogic.allEventSnapshots(
                groups: settlementGroupSnapshots,
                participants: settlementParticipantSnapshots,
                records: records
            )
            .sorted { $0.occurredAt > $1.occurredAt },
            openDebtPositions: openDebtPositions,
            openReceivableDebtTotals: TransactionLogic.openReceivableDebtTotalsByCurrency(
                from: openDebtPositions
            ),
            sections: TransactionLogic.sections(
                from: displayedRecords,
                assumesSortedByRecency: true,
                calendar: calendar
            ),
            transactionsByID: Dictionary(
                activeTransactions
                    .filter { displayedRecordIDs.contains($0.id) }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
            ),
            transactionAuditMap: transactionAuditMap,
            walletOwnerMap: walletOwnerMap,
            transactionOwnerMap: transactionOwnerMap
        )
    }

    private var transactionSearchSnapshot: TransactionsListSnapshot? {
        guard let filters = TransactionSearchLogic.filters(for: debouncedSearchText) else {
            return nil
        }

        let activeTransactions = self.activeTransactions
        let records = activeTransactions.map(\.snapshot)
        let page = TransactionLogic.visibleRecordsPage(
            from: records,
            selectedKind: nil,
            filters: filters,
            limit: visibleSearchResultLimit,
            assumesSortedByRecency: true,
            calendar: calendar
        )
        let displayedRecords = page.displayedRecords
        let displayedRecordIDs = Set(displayedRecords.map(\.id))

        return TransactionsListSnapshot(
            activeTransactionCount: activeTransactions.count,
            visibleRecordCount: page.totalCount,
            displayedRecordCount: displayedRecords.count,
            hasAdjustments: false,
            debtCounterpartyFilterOptions: [],
            preparingSettlementEvents: [],
            allSettlementEvents: [],
            openDebtPositions: [],
            openReceivableDebtTotals: [],
            sections: TransactionLogic.sections(
                from: displayedRecords,
                assumesSortedByRecency: true,
                calendar: calendar
            ),
            transactionsByID: Dictionary(
                activeTransactions
                    .filter { displayedRecordIDs.contains($0.id) }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
            ),
            transactionAuditMap: transactionAuditMap,
            walletOwnerMap: walletOwnerMap,
            transactionOwnerMap: transactionOwnerMap
        )
    }

    private func cachedTransactionListSnapshot(
        for key: TransactionsListSnapshotCacheKey
    ) -> TransactionsListSnapshot {
        if let listSnapshotCache, listSnapshotCache.key == key {
            return listSnapshotCache.snapshot
        }

        return transactionListSnapshot
    }

    private func refreshTransactionListSnapshotCache(
        for key: TransactionsListSnapshotCacheKey,
        snapshot: TransactionsListSnapshot
    ) {
        listSnapshotCache = TransactionsListSnapshotCache(
            key: key,
            snapshot: snapshot
        )
    }

    private func cachedTransactionSearchSnapshot(
        for key: TransactionsListSnapshotCacheKey?
    ) -> TransactionsListSnapshot? {
        guard let key else { return nil }
        if let searchSnapshotCache, searchSnapshotCache.key == key {
            return searchSnapshotCache.snapshot
        }

        return transactionSearchSnapshot
    }

    private func refreshTransactionSearchSnapshotCache(
        for key: TransactionsListSnapshotCacheKey,
        snapshot: TransactionsListSnapshot
    ) {
        searchSnapshotCache = TransactionsListSnapshotCache(
            key: key,
            snapshot: snapshot
        )
    }

    private var transactionListSnapshotCacheKey: TransactionsListSnapshotCacheKey {
        let effectiveFilters = effectiveFilters
        return TransactionsListSnapshotCacheKey(
            selectedSegmentRawValue: selectedSegment?.rawValue,
            isAdjustmentOnly: effectiveFilters.isAdjustmentOnly,
            timeScopeRawValue: effectiveFilters.timeScope.rawValue,
            walletID: effectiveFilters.walletID,
            categoryID: effectiveFilters.categoryID,
            transferSubtypeRawValue: effectiveFilters.transferSubtype?.rawValue,
            counterpartyDebtKey: effectiveFilters.counterpartyDebtKey,
            statusScopeRawValue: effectiveFilters.statusScope.rawValue,
            minAmountMinor: effectiveFilters.minAmountMinor,
            maxAmountMinor: effectiveFilters.maxAmountMinor,
            searchText: effectiveFilters.searchText,
            visibleTransactionLimit: visibleTransactionLimit,
            calendarIdentifier: String(describing: calendar.identifier),
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: locale.identifier,
            activeScope: familyContextStore.activeContext.scope,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.signedInUserID,
            familyID: familyContextStore.family?.id,
            familyAccessSignature: familyAccessSignature,
            transactionSignature: MistiaCollectionChangeSignature.make(
                storedTransactions,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            settlementGroupSignature: MistiaCollectionChangeSignature.make(
                storedSettlementGroups,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            settlementParticipantSignature: MistiaCollectionChangeSignature.make(
                storedSettlementParticipants,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                remoteVersion: \.remoteVersion
            ),
            ownershipSignature: MistiaCollectionChangeSignature.make(
                ownershipScopes,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            ),
            auditSignature: MistiaCollectionChangeSignature.make(
                transactionAuditRecords,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            )
        )
    }

    private var transactionSearchSnapshotCacheKey: TransactionsListSnapshotCacheKey? {
        guard let filters = TransactionSearchLogic.filters(for: debouncedSearchText) else {
            return nil
        }

        return TransactionsListSnapshotCacheKey(
            selectedSegmentRawValue: nil,
            isAdjustmentOnly: filters.isAdjustmentOnly,
            timeScopeRawValue: filters.timeScope.rawValue,
            walletID: filters.walletID,
            categoryID: filters.categoryID,
            transferSubtypeRawValue: filters.transferSubtype?.rawValue,
            counterpartyDebtKey: filters.counterpartyDebtKey,
            statusScopeRawValue: filters.statusScope.rawValue,
            minAmountMinor: filters.minAmountMinor,
            maxAmountMinor: filters.maxAmountMinor,
            searchText: filters.searchText,
            visibleTransactionLimit: visibleSearchResultLimit,
            calendarIdentifier: String(describing: calendar.identifier),
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: locale.identifier,
            activeScope: familyContextStore.activeContext.scope,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.signedInUserID,
            familyID: familyContextStore.family?.id,
            familyAccessSignature: familyAccessSignature,
            transactionSignature: MistiaCollectionChangeSignature.make(
                storedTransactions,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            settlementGroupSignature: nil,
            settlementParticipantSignature: nil,
            ownershipSignature: MistiaCollectionChangeSignature.make(
                ownershipScopes,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            ),
            auditSignature: MistiaCollectionChangeSignature.make(
                transactionAuditRecords,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            )
        )
    }

    private var familyAccessSignature: Int {
        var hasher = Hasher()
        hasher.combine(familyContextStore.currentMembership?.id)
        hasher.combine(familyContextStore.currentMembership?.updatedAt.timeIntervalSince1970)
        hasher.combine(familyContextStore.members.count)
        for member in familyContextStore.members {
            hasher.combine(member.membershipID)
            hasher.combine(member.userID)
            hasher.combine(member.role.rawValue)
            hasher.combine(member.hasSyncedCloudData)
        }
        hasher.combine(familyContextStore.permissionGrants.count)
        for grant in familyContextStore.permissionGrants {
            hasher.combine(grant.id)
            hasher.combine(grant.granteeUserID)
            hasher.combine(grant.ownerUserID)
            hasher.combine(grant.resourceTypeRawValue)
            hasher.combine(grant.resourceID)
            hasher.combine(grant.permissionScopeRawValue)
            hasher.combine(grant.updatedAt.timeIntervalSince1970)
            hasher.combine(grant.revokedAt?.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var transactionOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
    }

    private var transactionRecords: [TransactionRecordSnapshot] {
        activeTransactions.map(\.planningRecordSnapshot)
    }

    private var overviewTransactions: [OverviewTransactionSnapshot] {
        activeTransactions.map(\.overviewSnapshot)
    }

    private var walletSnapshots: [OverviewWalletSnapshot] {
        activeWallets.compactMap(\.overviewWalletSnapshot)
    }

    private var statementCreditCardAccounts: [OverviewCreditCardStatementAccountSnapshot] {
        let filteredWallets: [LedgerWallet]
        if let walletID = filterState.walletID {
            filteredWallets = activeWallets.filter { $0.id == walletID }
        } else {
            filteredWallets = activeWallets
        }
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: activeWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionRecords
        )
        return filteredWallets.compactMap { $0.overviewCreditCardStatementAccountSnapshot(balanceIndex: balanceIndex) }
    }

    private var statementPeriod: DateInterval {
        let now = Date.now
        switch filterState.timeScope {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .yesterday:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: start, end: today)
        case .thisMonth:
            let monthStart = PlanningLogic.startOfMonth(for: now, calendar: calendar)
            let monthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? now
            return DateInterval(start: monthStart, end: min(now, monthEnd))
        case .allTime:
            // Default: max 3 recent calendar months
            let currentMonthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? now
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -2, to: PlanningLogic.startOfMonth(for: now, calendar: calendar)) ?? now
            return DateInterval(start: threeMonthsAgo, end: min(now, currentMonthEnd))
        }
    }

    private var statementFilteredTransactions: [OverviewTransactionSnapshot] {
        overviewTransactions.filter { transaction in
            if let walletID = filterState.walletID {
                guard transaction.sourceWalletID == walletID || transaction.destinationWalletID == walletID else {
                    return false
                }
            }

            if let categoryID = filterState.categoryID {
                guard transaction.categoryID == categoryID else {
                    return false
                }
            }

            if let kind = selectedSegment?.kind {
                guard transaction.primaryKind == kind else {
                    return false
                }
            }

            return true
        }
    }

    private var monthlyStatement: TransactionSummaryStatementSnapshot {
        TransactionLogic.monthlyStatement(
            wallets: walletSnapshots,
            transactionRecords: transactionRecords,
            transactions: statementFilteredTransactions,
            statementPeriod: statementPeriod,
            currencyCode: currencyCode,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var creditCardStatement: TransactionCreditCardStatementSnapshot {
        TransactionLogic.creditCardStatement(
            accounts: statementCreditCardAccounts,
            transactions: statementFilteredTransactions,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var effectiveFilters: TransactionFilterState {
        var effective = filterState
        effective.searchText = ""
        effective.isAdjustmentOnly = selectedSegment == .adjustment
        effective.isEventOnly = selectedSegment == .event
        return effective
    }

    private func debtRecords(from records: [TransactionRecordSnapshot]) -> [TransactionRecordSnapshot] {
        records.filter { record in
            guard record.primaryKind == .transfer, record.transferSubtype == .debt else {
                return false
            }

            if let walletID = filterState.walletID {
                return record.sourceWalletID == walletID || record.destinationWalletID == walletID
            }

            return true
        }
    }

    private func debtCounterpartyFilterOptions(
        from records: [TransactionRecordSnapshot]
    ) -> [DebtCounterpartyFilterOption] {
        var optionsByKey: [String: DebtCounterpartyFilterOption] = [:]
        optionsByKey.reserveCapacity(8)

        for record in records {
            guard record.entryStatus == .posted,
                  record.primaryKind == .transfer,
                  record.transferSubtype == .debt,
                  let key = record.normalizedCounterpartyKey
                    ?? TransactionLogic.normalizeCounterpartyName(record.counterpartyName),
                  !key.isEmpty,
                  let displayName = record.counterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty
            else {
                continue
            }

            if optionsByKey[key] == nil {
                optionsByKey[key] = DebtCounterpartyFilterOption(id: key, displayName: displayName)
            }
        }

        return optionsByKey.values.sorted {
            if $0.displayName.localizedCaseInsensitiveCompare($1.displayName) != .orderedSame {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.id < $1.id
        }
    }

    private var activeFilterCount: Int {
        var count = 0

        if selectedSegment != nil { count += 1 }
        if filterState.timeScope != .allTime { count += 1 }
        if filterState.walletID != nil { count += 1 }
        if filterState.categoryID != nil { count += 1 }
        if filterState.transferSubtype != nil { count += 1 }
        if filterState.counterpartyDebtKey != nil { count += 1 }
        if filterState.minAmountMinor != nil || filterState.maxAmountMinor != nil { count += 1 }

        return count
    }

    private var activeFilterTint: Color {
        colorScheme == .dark
            ? Color(red: 0.53, green: 0.33, blue: 0.86)
            : MistiaAccent.purple.color
    }

    private var inactiveFilterTint: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }

    private var activeFilterBadgeTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.53, green: 0.33, blue: 0.86)
            : MistiaAccent.purple.color
    }

    private var isSearchSceneVisible: Bool {
        isSearchPresented || !searchText.isEmpty || !debouncedSearchText.isEmpty
    }

    var body: some View {
        let listSnapshotKey = transactionListSnapshotCacheKey
        let listSnapshot = cachedTransactionListSnapshot(for: listSnapshotKey)
        let searchSnapshotKey = transactionSearchSnapshotCacheKey
        let searchSnapshot = cachedTransactionSearchSnapshot(for: searchSnapshotKey)
        let memberToolbar = familyContextStore.memberViewingToolbarPresentation
        let exchangeRateIndex = MistiaExchangeRateIndex(rates: appExchangeRates)

        NavigationStack {
            ZStack {
                MistiaPinnedTopBarScaffold(
                    tone: .standard,
                    title: isSearchSceneVisible ? "" : L10n.transactions.transactions.transactions,
                    embedsInNavigationStack: false,
                    showsLeadingAvatar: memberToolbar != nil,
                    leadingInitials: memberToolbar?.initials ?? "MI",
                    leadingAvatarURL: memberToolbar != nil ? familyContextStore.viewedMember?.avatarURL : nil,
                    leadingAccessibilityLabel: memberToolbar?.accessibilityLabel,
                    leadingAvatarAttentionPulse: memberToolbar != nil,
                    leadingSystemImage: memberToolbar == nil ? "doc.viewfinder" : nil,
                    trailingSystemImage: nil,
                    onLeadingTap: {
                        if let memberToolbar {
                            memberViewingExitPrompt = FamilyMemberViewingExitPrompt(presentation: memberToolbar)
                        } else {
                            destination = .aiBill
                        }
                    },
                    contentSpacing: 18,
                    contentBottomPadding: 150,
                    titleDisplayMode: isSearchSceneVisible ? .inline : .large,
                    headerBehavior: .scrollsThenPins,
                    pinnedHeader: {
                        VStack(alignment: .leading, spacing: 8) {
                            unifiedFilterRow(listSnapshot)
                        }
                            .zIndex(99)
                    },
                    trailingAccessory: {
                        transactionsStatementMenuButton
                        .padding(.trailing, -12)
                    }
                ) {
                    if selectedSegment == .event {
                        let ongoingEvents = listSnapshot.preparingSettlementEvents
                        let completedEvents = SettlementLogic.completedEventSnapshots(
                            allEvents: listSnapshot.allSettlementEvents,
                            preparingEvents: ongoingEvents
                        )

                        if ongoingEvents.isEmpty && completedEvents.isEmpty {
                            MistiaEmptyStateContent(
                                title: "Chưa có sự kiện nào",
                                message: "Các sự kiện chia chi phí sẽ xuất hiện ở đây.",
                                buttonTitle: nil,
                                accent: MistiaAccent.purple.color,
                                symbols: ["calendar", "person.2.fill", "receipt.fill", "checkmark.seal.fill"]
                            )
                            .padding(.top, 40)
                        } else {
                            if !ongoingEvents.isEmpty {
                                eventSection(
                                    title: L10n.transactions.settlement.ongoingEvents,
                                    events: ongoingEvents
                                )
                            }
                            if !completedEvents.isEmpty {
                                eventSection(
                                    title: L10n.transactions.settlement.completedEvents,
                                    events: completedEvents
                                )
                            }
                        }
                    } else {
                        if !listSnapshot.preparingSettlementEvents.isEmpty {
                            preparingSettlementSection(listSnapshot.preparingSettlementEvents)
                        }
                        if !listSnapshot.openDebtPositions.isEmpty {
                            outstandingDebtSection(
                                listSnapshot.openDebtPositions,
                                receivableTotals: listSnapshot.openReceivableDebtTotals
                            )
                        }
                        transactionsContent(listSnapshot, exchangeRateIndex: exchangeRateIndex)
                    }
                }

                if isSearchSceneVisible {
                    TransactionsSearchScene(
                        searchText: searchText,
                        snapshot: searchSnapshot,
                        transactionsByID: searchSnapshot?.transactionsByID ?? [:],
                        transactionAuditMap: searchSnapshot?.transactionAuditMap ?? [:],
                        walletOwnerMap: searchSnapshot?.walletOwnerMap ?? [:],
                        transactionOwnerMap: searchSnapshot?.transactionOwnerMap ?? [:],
                        primaryCurrencyCode: primaryCurrencyCode,
                        exchangeRateIndex: exchangeRateIndex,
                        onSelect: openTransactionEditorIfAllowed,
                        onLoadMore: loadMoreSearchResultsIfNeeded
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                prompt: L10n.transactions.transactions.searchTransactionName
            )
            .searchToolbarBehavior(.minimize)
            .navigationDestination(item: $destination) { route in
                switch route {
                case .aiBill:
                    AIBillAnalysisView()
                }
            }
        }
        .familyMemberViewingExitAlert(
            prompt: $memberViewingExitPrompt,
            familyContextStore: familyContextStore
        )
        .sheet(item: $shareItem) { item in
            TransactionShareSheet(url: item.url)
        }
        .sheet(item: $editorTarget) { target in
            TransactionEditorSheet(target: target)
                .presentationDetents(target.quickCapture ? [.medium, .large] : [.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $debtSettlementTarget) { target in
            DebtSettlementSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $settlementEditorTarget) { target in
            SettlementEditorSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $preparingSettlementTarget) { target in
            SettlementSplitCalculatorSheet(target: target) { groupID in
                let ownerUserID = familyContextStore.viewedMember?.userID ?? sessionStore.activeLocalProfileUserID
                if familyContextStore.canEditEvent(for: ownerUserID) {
                    settlementEditorTarget = .editSharedExpense(groupID)
                } else if let ownerUserID {
                    presentEventPermissionPrompt(ownerUserID: ownerUserID, scope: .edit)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        familyOwnerConflictAlert = nil
                        permissionPrompt = nil
                        infoAlert = nil
                    }
                }
            ),
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .info:
                Button(L10n.common.ok) {}
            case .familyOwnerConflict(let conflict):
                Button(L10n.common.ok) {
                    Task { @MainActor in
                        await sessionStore.discardFamilyOwnerPushConflictAndRefresh(
                            entity: conflict.entity,
                            recordID: conflict.recordID,
                            familyContextStore: familyContextStore
                        )
                        familyOwnerConflictAlert = nil
                        listSnapshotCache = nil
                        searchSnapshotCache = nil
                    }
                }
            case .permission(let prompt):
                Button(prompt.actionTitle) {
                    prompt.action()
                }
                Button(L10n.common.cancel, role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .alert(
            L10n.transactions.transactions.couldnTExportStatement,
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.transactions.transactions.close, role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text((exportErrorMessage ?? ""))
        }
        .onChange(of: selectedSegment) { _, _ in
            resetTransactionPage()
        }
        .onChange(of: filterState) { _, _ in
            resetTransactionPage()
        }
        .onChange(of: searchText) { _, newValue in
            scheduleSearchDebounce(newValue)
        }
        .onChange(of: isSearchPresented) { _, isPresented in
            if !isPresented {
                closeTransactionSearch()
            }
        }
        .onChange(of: familyContextStore.selectedSubjectUserID) { _, _ in
            resetTransactionPage()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
        .task(id: listSnapshotKey) {
            refreshTransactionListSnapshotCache(for: listSnapshotKey, snapshot: listSnapshot)
        }
        .task(id: searchSnapshotKey) {
            guard let searchSnapshotKey, let searchSnapshot else {
                searchSnapshotCache = nil
                return
            }
            refreshTransactionSearchSnapshotCache(for: searchSnapshotKey, snapshot: searchSnapshot)
        }
    }

    private var transactionsStatementMenuButton: some View {
        MistiaHeaderCircleMenu(label: {
            ZStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 15, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.72))
            }
        }) {
            Button(action: { exportStatement(.monthlySummary) }) {
                Label(
                    L10n.transactions.transactions.summaryStatement,
                    systemImage: "doc.text.image"
                )
            }

            Button(action: { exportStatement(.creditCard) }) {
                Label(
                    L10n.transactions.transactions.creditCardStatement,
                    systemImage: "creditcard.and.123"
                )
            }

            Button(action: {
                let ownerUserID = familyContextStore.viewedMember?.userID ?? sessionStore.activeLocalProfileUserID
                if familyContextStore.canCreateEvent(for: ownerUserID) {
                    settlementEditorTarget = .newSharedExpense
                } else if let ownerUserID {
                    presentEventPermissionPrompt(ownerUserID: ownerUserID, scope: .create)
                }
            }) {
                Label(
                    L10n.transactions.settlement.addSharedExpense,
                    systemImage: "person.3.sequence"
                )
            }
        }
        .accessibilityLabel(L10n.transactions.transactions.statement)
    }

    private func exportStatement(_ kind: TransactionStatementKind) {
        do {
            let document: TransactionStatementDocument

            switch kind {
            case .monthlySummary:
                document = TransactionLogic.renderMonthlyStatement(monthlyStatement)
            case .creditCard:
                document = TransactionLogic.renderCreditCardStatement(creditCardStatement)
            }

            let url = try TransactionStatementExportSupport.write(document: document)
            shareItem = TransactionShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func unifiedFilterRow(_ snapshot: TransactionsListSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 10) {
                        filterChipsHStack(snapshot)
                    }
                } else {
                    filterChipsHStack(snapshot)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func filterMenu<Content: View>(
        isActive: Bool,
        @ViewBuilder label: () -> Content,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let menu = Menu {
            content()
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .buttonBorderShape(.capsule)
        .tint(isActive ? activeFilterTint : inactiveFilterTint)

        if isActive {
            menu.buttonStyle(.glassProminent)
                .zIndex(99)
        } else {
            menu.buttonStyle(.glass)
                .zIndex(0)
        }
    }

    private func filterChipsHStack(_ snapshot: TransactionsListSnapshot) -> some View {
        let debtCounterpartyFilterOptions = snapshot.debtCounterpartyFilterOptions
        let activeWallets = self.activeWallets
        let activeCategorySections = self.activeCategorySections
        let activeCategories = activeCategorySections.map(\.parent) + activeCategorySections.flatMap(\.children)

        return HStack(spacing: 8) {
            if activeFilterCount > 0 {
                filterMenu(isActive: true) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        
                        Text(verbatim: "\(activeFilterCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(activeFilterBadgeTextColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Circle().fill(.white))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                } content: {
                    Text(
                        L10n.transactions.transactions.valueActiveFilters(String(describing: activeFilterCount))
                    )
                    
                    Button(role: .destructive) {
                        withAnimation(.snappy) {
                            selectedSegment = nil
                            filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
                        }
                    } label: {
                        Text(L10n.transactions.transactions.clearAllFilters)
                    }
                }
            }

            filterMenu(isActive: selectedSegment != nil) {
                TransactionToolbarChip(
                    title: selectedSegment?.title ?? L10n.transactions.transactions.type,
                    isActive: selectedSegment != nil,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                Button(L10n.transactions.transactions.all) {
                    withAnimation(.snappy) {
                        selectedSegment = nil
                    }
                }
                ForEach(TransactionSegment.allCases, id: \.self) { segment in
                    if segment != .adjustment || snapshot.hasAdjustments {
                        Button(segment.title) {
                            withAnimation(.snappy) {
                                selectedSegment = segment
                            }
                        }
                    }
                }
            }

            filterMenu(isActive: filterState.timeScope != .allTime) {
                TransactionToolbarChip(
                    title: filterState.timeScope == .allTime ? L10n.transactions.transactions.time : filterState.timeScope.title,
                    isActive: filterState.timeScope != .allTime,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                ForEach(TransactionTimeScope.allCases, id: \.self) { scope in
                    Button(scope.title) {
                        withAnimation(.snappy) {
                            filterState.timeScope = scope
                        }
                    }
                }
            }

            filterMenu(isActive: filterState.walletID != nil) {
                let title = activeWallets.first { $0.id == filterState.walletID }?.name ?? L10n.transactions.transactions.wallet
                TransactionToolbarChip(
                    title: title,
                    isActive: filterState.walletID != nil,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                Button(L10n.transactions.transactions.all) {
                    withAnimation(.snappy) {
                        filterState.walletID = nil
                    }
                }
                ForEach(activeWallets, id: \.id) { wallet in
                    Button(wallet.name) {
                        withAnimation(.snappy) {
                            filterState.walletID = wallet.id
                        }
                    }
                }
            }

            if !debtCounterpartyFilterOptions.isEmpty {
                filterMenu(isActive: filterState.counterpartyDebtKey != nil) {
                    let title = debtCounterpartyFilterOptions
                        .first { $0.id == filterState.counterpartyDebtKey }?
                        .displayName ?? L10n.transactions.transactions.person
                    TransactionToolbarChip(
                        title: title,
                        isActive: filterState.counterpartyDebtKey != nil,
                        trailingIcon: "chevron.up.chevron.down"
                    )
                } content: {
                    Button(L10n.transactions.transactions.all) {
                        withAnimation(.snappy) {
                            filterState.counterpartyDebtKey = nil
                        }
                    }
                    ForEach(debtCounterpartyFilterOptions) { option in
                        Button(option.displayName) {
                            withAnimation(.snappy) {
                                selectedSegment = nil
                                filterState.categoryID = nil
                                filterState.counterpartyDebtKey = option.id
                            }
                        }
                    }
                }
            }

            if selectedSegment?.kind != .transfer && selectedSegment != .adjustment && selectedSegment != .event {
                filterMenu(isActive: filterState.categoryID != nil) {
                    let title = activeCategories.first { $0.id == filterState.categoryID }?.localizedDisplayName
                        ?? L10n.transactions.transactions.category
                    TransactionToolbarChip(
                        title: title,
                        isActive: filterState.categoryID != nil,
                        trailingIcon: "chevron.up.chevron.down"
                    )
                } content: {
                    Button(L10n.transactions.transactions.all) {
                        withAnimation(.snappy) {
                            filterState.categoryID = nil
                        }
                    }
                    ForEach(activeCategorySections) { section in
                        Menu {
                            Section() {
                                Button(L10n.transactions.transactions.all) {
                                    withAnimation(.snappy) {
                                        filterState.categoryID = section.parent.id
                                    }
                                }
                                ForEach(section.children) { category in
                                    Button(category.localizedDisplayName) {
                                        withAnimation(.snappy) {
                                            filterState.categoryID = category.id
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(section.parent.localizedDisplayName)
                        }
                    }
                }
            }
        }
    }

    private func outstandingDebtSection(
        _ positions: [CounterpartyDebtSnapshot],
        receivableTotals: [PlanningCurrencyAmountTotalSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L10n.transactions.transactions.openDebts)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer(minLength: 12)

                if let total = formattedReceivableDebtTotal(receivableTotals) {
                    Text(verbatim: total)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(debtIntentTint(.lend))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(positions) { position in
                        OutstandingDebtChip(position: position) {
                            debtSettlementTarget = DebtSettlementSheetTarget(position: position)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -18)
        }
    }

    private func preparingSettlementSection(
        _ events: [PreparingSettlementEventSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L10n.transactions.settlement.ongoingEvents)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(events) { event in
                        PreparingSettlementCompactChip(event: event, showsIcon: false) {
                            preparingSettlementTarget = PreparingSettlementEventSheetTarget(groupID: event.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -18)
        }
    }

    private func eventSection(
        title: String,
        events: [PreparingSettlementEventSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 2)

            MistiaBlockCard(
                cornerRadius: 22,
                tint: Color(UIColor.secondarySystemGroupedBackground),
                padding: 0
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            preparingSettlementTarget = PreparingSettlementEventSheetTarget(groupID: event.id)
                        } label: {
                            EventCashflowRow(event: event)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < events.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }
                }
            }
        }
    }

    private func formattedReceivableDebtTotal(
        _ totals: [PlanningCurrencyAmountTotalSnapshot]
    ) -> String? {
        guard !totals.isEmpty else { return nil }
        return totals
            .map { $0.amountMinor.formattedCurrency(code: $0.currencyCode) }
            .joined(separator: " / ")
    }

    @ViewBuilder
    private func transactionsContent(
        _ snapshot: TransactionsListSnapshot,
        exchangeRateIndex: MistiaExchangeRateIndex
    ) -> some View {
        if snapshot.activeTransactionCount == 0 {
            TransactionsPlaceholderCard(
                title: L10n.transactions.transactions.noTransactionsYet,
                message: L10n.transactions.transactions.whenYouAddAnExpenseIncomeTransfer
            )
        } else if snapshot.sections.isEmpty {
            TransactionsPlaceholderCard(
                title: L10n.transactions.transactions.noMatchingResults,
                message: L10n.transactions.transactions.tryAdjustingTheTimeRangeWalletFilters
            )
        } else {
            ForEach(snapshot.sections) { section in
                TransactionSectionCard(
                    section: section,
                    transactionsByID: snapshot.transactionsByID,
                    transactionAuditMap: snapshot.transactionAuditMap,
                    walletOwnerMap: snapshot.walletOwnerMap,
                    transactionOwnerMap: snapshot.transactionOwnerMap,
                    primaryCurrencyCode: primaryCurrencyCode,
                    exchangeRateIndex: exchangeRateIndex
                ) { transaction in
                    openTransactionEditorIfAllowed(transaction)
                }
            }

            if snapshot.hasMoreRows {
                TransactionListPagingSentinel()
                    .onAppear {
                        loadMoreTransactionsIfNeeded(totalVisibleCount: snapshot.visibleRecordCount)
                    }
            }
        }
    }

    private func resetTransactionPage() {
        guard visibleTransactionLimit != TransactionsListPaging.initialLimit else { return }
        visibleTransactionLimit = TransactionsListPaging.initialLimit
    }

    private func resetSearchResultsPage() {
        guard visibleSearchResultLimit != TransactionsListPaging.initialLimit else { return }
        visibleSearchResultLimit = TransactionsListPaging.initialLimit
    }

    private func loadMoreTransactionsIfNeeded(totalVisibleCount: Int) {
        guard visibleTransactionLimit < totalVisibleCount else { return }
        visibleTransactionLimit = min(
            visibleTransactionLimit + TransactionsListPaging.increment,
            totalVisibleCount
        )
    }

    private func loadMoreSearchResultsIfNeeded(totalVisibleCount: Int) {
        guard visibleSearchResultLimit < totalVisibleCount else { return }
        visibleSearchResultLimit = min(
            visibleSearchResultLimit + TransactionsListPaging.increment,
            totalVisibleCount
        )
    }

    private func scheduleSearchDebounce(_ value: String) {
        searchDebounceTask?.cancel()

        if value.isEmpty {
            debouncedSearchText = ""
            resetSearchResultsPage()
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            debouncedSearchText = value
            resetSearchResultsPage()
        }
    }

    private func closeTransactionSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        searchText = ""
        debouncedSearchText = ""
        resetSearchResultsPage()
    }

    private func openTransactionEditorIfAllowed(_ transaction: LedgerTransaction) {
        guard !sessionStore.hasFamilyOwnerPushConflict(entity: .transaction, recordID: transaction.id) else {
            familyOwnerConflictAlert = TransactionsFamilyOwnerConflictAlert(
                entity: .transaction,
                recordID: transaction.id
            )
            return
        }

        if transaction.primaryKind == .transfer,
           transaction.transferSubtype == .familyTransfer {
            editorTarget = TransactionEditorTarget(transaction: transaction)
            return
        }

        guard let ownerUserID = transactionOwnerUserID(for: transaction) else {
            editorTarget = TransactionEditorTarget(transaction: transaction)
            return
        }
        guard ownerUserID != sessionStore.activeLocalProfileUserID else {
            editorTarget = TransactionEditorTarget(transaction: transaction)
            return
        }
        guard familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .transaction) else {
            presentTransactionEditPermissionPrompt(transaction, ownerUserID: ownerUserID)
            return
        }
        editorTarget = TransactionEditorTarget(transaction: transaction)
    }

    private func transactionOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? ownerUserID(forWalletID: transaction.sourceWallet?.id)
            ?? ownerUserID(forWalletID: transaction.destinationWallet?.id)
            ?? familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
    }

    private func ownerUserID(forWalletID walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID]
    }

    private func presentEventPermissionPrompt(ownerUserID: UUID, scope: MistiaFamilyPermissionScope) {
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .event,
            resourceID: nil,
            scope: scope
        )
        permissionPrompt = TransactionsPermissionPrompt(
            title: scope == .create
                ? L10n.planning.planning.noCreateAccess
                : L10n.planning.planning.noEditAccess,
            message: scope == .create
                ? L10n.planning.planning.youDoNotHavePermissionToCreate(L10n.shared.persistence.notification.event)
                : L10n.planning.planning.youDoNotHavePermissionToEdit(L10n.shared.persistence.notification.event),
            actionTitle: isPending
                ? L10n.planning.planning.accessRequested
                : (scope == .create ? L10n.planning.planning.requestCreateAccess : L10n.planning.planning.requestEditAccess)
        ) {
            Task { @MainActor in
                if isPending {
                    let isApproved = await familyContextStore.refreshPermissionGrant(
                        ownerUserID: ownerUserID,
                        resourceType: .event,
                        resourceID: nil,
                        scope: scope,
                        sessionStore: sessionStore
                    )
                    if isApproved {
                        permissionPrompt = nil
                    }
                    return
                }

                let didSend = await familyContextStore.requestPermission(
                    resourceType: .event,
                    resourceID: nil,
                    ownerUserID: ownerUserID,
                    scope: scope,
                    resourceName: L10n.shared.persistence.notification.event,
                    sessionStore: sessionStore
                )
                permissionPrompt = nil
                try? await Task.sleep(nanoseconds: 150_000_000)
                infoAlert = TransactionsInfoAlert(
                    title: didSend
                        ? L10n.transactions.transactions.requestSent
                        : L10n.transactions.transactions.couldnTSend,
                    message: didSend
                        ? L10n.transactions.transactions.thePermissionRequestWasSentToThe
                        : (familyContextStore.lastErrorMessage ?? L10n.transactions.transactions.couldnTSendTheRequestRightNow)
                )
            }
        }
    }

    private func presentTransactionEditPermissionPrompt(_ transaction: LedgerTransaction, ownerUserID: UUID) {
        let resourceName = transaction.localizedTransactionTitle.nilIfBlank
            ?? L10n.transactions.transactions.transaction
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .transaction,
            resourceID: nil,
            scope: .edit
        )
        permissionPrompt = TransactionsPermissionPrompt(
            title: L10n.transactions.transactions.noTransactionEditAccess,
            message: L10n.transactions.transactions.youDoNotHavePermissionToEdit,
            actionTitle: isPending
                ? L10n.transactions.transactions.editRequestSent
                : L10n.transactions.transactions.requestEditAccess
        ) {
            Task { @MainActor in
                if isPending {
                    let isApproved = await familyContextStore.refreshPermissionGrant(
                        ownerUserID: ownerUserID,
                        resourceType: .transaction,
                        resourceID: nil,
                        scope: .edit,
                        sessionStore: sessionStore
                    )
                    if isApproved {
                        permissionPrompt = nil
                        editorTarget = TransactionEditorTarget(transaction: transaction)
                    }
                    return
                }

                let didSend = await familyContextStore.requestPermission(
                    resourceType: .transaction,
                    resourceID: nil,
                    ownerUserID: ownerUserID,
                    scope: .edit,
                    resourceName: resourceName,
                    sessionStore: sessionStore
                )
                permissionPrompt = nil
                try? await Task.sleep(nanoseconds: 150_000_000)
                infoAlert = TransactionsInfoAlert(
                    title: didSend
                        ? L10n.transactions.transactions.requestSent
                        : L10n.transactions.transactions.couldnTSend,
                    message: didSend
                        ? L10n.transactions.transactions.thePermissionRequestWasSentToThe
                        : (familyContextStore.lastErrorMessage ?? L10n.transactions.transactions.couldnTSendTheRequestRightNow)
                )
            }
        }
    }
}

struct TransactionsSearchScene: View {
    let searchText: String
    let snapshot: TransactionsListSnapshot?
    let transactionsByID: [UUID: LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let primaryCurrencyCode: String
    let exchangeRateIndex: MistiaExchangeRateIndex
    var showsExpenseMinusSign: Bool = true
    var displaysSnapshotWithoutSearchQuery: Bool = false
    var searchNoResultsMessage: String = L10n.transactions.transactions.searchNoResultsMessage
    let onSelect: (LedgerTransaction) -> Void
    let onLoadMore: (Int) -> Void

    private var backgroundColor: Color {
        Color(UIColor.systemGroupedBackground)
    }

    private var hasSearchQuery: Bool {
        TransactionSearchLogic.filters(for: searchText) != nil
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 18) {
                    searchContent
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 150)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if !hasSearchQuery && !displaysSnapshotWithoutSearchQuery {
            MistiaEmptyStateContent(
                title: L10n.transactions.transactions.searchEmptyTitle,
                message: L10n.transactions.transactions.searchEmptyMessage,
                buttonTitle: nil,
                symbols: ["magnifyingglass", "text.cursor", "list.bullet.rectangle"]
            )
            .padding(.top, 44)
        } else if let snapshot {
            if snapshot.sections.isEmpty {
                if hasSearchQuery {
                    MistiaEmptyStateContent(
                        title: L10n.transactions.transactions.noMatchingResults,
                        message: searchNoResultsMessage,
                        buttonTitle: nil,
                        symbols: ["magnifyingglass", "xmark.circle.fill", "list.bullet.rectangle"]
                    )
                    .padding(.top, 44)
                }
            } else {
                ForEach(snapshot.sections) { section in
                    TransactionSectionCard(
                        section: section,
                        transactionsByID: transactionsByID,
                        transactionAuditMap: transactionAuditMap,
                        walletOwnerMap: walletOwnerMap,
                        transactionOwnerMap: transactionOwnerMap,
                        primaryCurrencyCode: primaryCurrencyCode,
                        exchangeRateIndex: exchangeRateIndex,
                        showsExpenseMinusSign: showsExpenseMinusSign
                    ) { transaction in
                        onSelect(transaction)
                    }
                }

                if snapshot.hasMoreRows {
                    TransactionListPagingSentinel()
                        .onAppear {
                            onLoadMore(snapshot.visibleRecordCount)
                        }
                }
            }
        }
    }
}

private struct TransactionLiveSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: TransactionSummarySnapshot

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(
            cornerRadius: 24,
            tint: cardTint,
            padding: 18
        ) {
            HStack(alignment: .top, spacing: 14) {
                TransactionSummaryMetric(
                    title: L10n.transactions.transactions.expense,
                    value: summary.expenseMinor.formattedCurrency(code: "JPY"),
                    tint: MistiaAccent.expense.color
                )

                Spacer(minLength: 4)

                TransactionSummaryMetric(
                    title: L10n.transactions.transactions.income,
                    value: summary.incomeMinor.formattedCurrency(code: "JPY"),
                    tint: MistiaAccent.income.color
                )

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(verbatim: "\(summary.totalCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(
                        summary.draftCount == 0
                            ? L10n.transactions.transactions.transactions
                            : L10n.transactions.transactions.valueDrafts(String(describing: summary.draftCount))
                    )
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TransactionListPagingSentinel: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .accessibilityLabel(L10n.transactions.transactions.loadingMoreTransactions)
    }
}

private struct TransactionSummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

struct TransactionSectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(SessionStore.self) private var sessionStore
    let section: TransactionSectionSnapshot
    let transactionsByID: [UUID: LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let primaryCurrencyCode: String
    let exchangeRateIndex: MistiaExchangeRateIndex
    var showsExpenseMinusSign: Bool = true
    let onSelect: (LedgerTransaction) -> Void

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(section.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text(
                    L10n.transactions.transactions.valueItems(String(describing: section.rows.count))
                )
                    .lineLimit(1)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            MistiaBlockCard(
                cornerRadius: 22,
                tint: cardTint,
                padding: 0
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if let transaction = transactionsByID[row.id] {
                            Button {
                                onSelect(transaction)
                            } label: {
                                TransactionCashflowRow(
                                    record: row,
                                    transaction: transaction,
                                    auditRecord: transactionAuditMap[transaction.id],
                                    walletOwnerMap: walletOwnerMap,
                                    transactionOwnerMap: transactionOwnerMap,
                                    familyContextStore: familyContextStore,
                                    hasFamilyOwnerConflict: sessionStore.hasFamilyOwnerPushConflict(
                                        entity: .transaction,
                                        recordID: transaction.id
                                    ),
                                    primaryCurrencyCode: primaryCurrencyCode,
                                    exchangeRateIndex: exchangeRateIndex,
                                    showsExpenseMinusSign: showsExpenseMinusSign
                                )
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                        }

                        if index < section.rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }
                }
            }
        }
    }
}

struct TransactionCashflowRow: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    let record: TransactionRecordSnapshot
    let transaction: LedgerTransaction
    let auditRecord: TransactionAuditRecord?
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let familyContextStore: FamilyContextStore
    let hasFamilyOwnerConflict: Bool
    let primaryCurrencyCode: String
    let exchangeRateIndex: MistiaExchangeRateIndex
    var showsExpenseMinusSign: Bool = true
    var subtitleLineLimit: Int = 2
    var showsAuditSubtitle: Bool = true

    private var icon: String {
        switch record.primaryKind {
        case .expense, .income:
            transaction.category?.iconSymbolName ?? record.primaryKind.financeIconToken
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                TransactionTransferSubtype.internalTransfer.financeIconToken
            case .familyTransfer:
                TransactionTransferSubtype.familyTransfer.financeIconToken
            case .debt:
                TransactionTransferSubtype.debt.financeIconToken
            case nil:
                record.primaryKind.financeIconToken
            }
        }
    }

    private var iconColor: Color {
        if record.primaryKind == .transfer, record.transferSubtype == .debt {
            return debtIntentTint(record.debtIntent)
        }
        return MistiaAccent.purple.color
    }

    private var title: String {
        if let trimmed = record.title.nilIfBlank {
            return trimmed
        }

        switch record.primaryKind {
        case .expense:
            return transaction.category?.localizedDisplayName
                ?? L10n.transactions.transactions.expenseNeedsDetails
        case .income:
            return transaction.category?.localizedDisplayName
                ?? L10n.transactions.transactions.incomeNeedsDetails
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                return L10n.transactions.transactions.internalTransfer
            case .familyTransfer:
                return L10n.shared.corelogic.financeenums.family
            case .debt:
                return record.debtIntent?.title ?? L10n.transactions.transactions.debt
            case nil:
                return L10n.transactions.transactions.transferNeedsDetails
            }
        }
    }

    private var subtitle: String {
        if record.entryStatus == .draft {
            return L10n.transactions.transactions.draftTapToComplete
        }

        switch record.primaryKind {
        case .expense, .income:
            let wallet = transaction.sourceWallet?.name ?? L10n.transactions.transactions.noWalletSelected
            let category = transaction.category?.localizedDisplayName ?? L10n.transactions.transactions.noCategorySelected
            return "\(wallet) • \(category)"
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                let source = transaction.sourceWallet?.name ?? L10n.transactions.transactions.source
                let destination = transaction.destinationWallet?.name ?? L10n.transactions.transactions.destination
                return "\(source) → \(destination)"
            case .familyTransfer:
                if let note = record.note?.nilIfBlank {
                    return note
                }
                let source = transaction.sourceWallet?.name ?? L10n.transactions.transactions.source
                if let destination = transaction.destinationWallet?.name {
                    return "\(source) → \(destination)"
                }
                return source
            case .debt:
                let person = transaction.counterpartyName ?? L10n.transactions.transactions.unknownName
                let intent = record.debtIntent?.title ?? L10n.transactions.transactions.debt
                if TransactionLogic.isPaidForDebt(record) {
                    if let category = transaction.category?.localizedDisplayName {
                        return "\(person) • \(intent) • \(L10n.transactions.transactioneditor.borrowPaidFor) • \(category)"
                    }
                    return "\(person) • \(intent) • \(L10n.transactions.transactioneditor.borrowPaidFor)"
                }
                let wallet = transaction.sourceWallet?.name ?? L10n.transactions.transactions.noWalletSelected
                return "\(person) • \(intent) • \(wallet)"
            case nil:
                return L10n.transactions.transactions.transfer
            }
        }
    }

    private var auditSubtitle: String? {
        let canonicalOwnerUserID = transactionOwnerMap[transaction.id] ?? ownerUserID(for: transaction.sourceWallet?.id)
        let createdByUserID = auditRecord?.createdByUserID ?? canonicalOwnerUserID

        var parts: [String] = []

        if let createdByUserID,
           createdByUserID != canonicalOwnerUserID {
            let createdByName = familyContextStore.displayName(for: createdByUserID)
                ?? L10n.transactions.transactions.aFamilyMember
            return L10n.transactions.transactions.createdByValue(String(describing: createdByName))
        }

        if let sourceWallet = transaction.sourceWallet,
           let sourceOwnerUserID = ownerUserID(for: sourceWallet.id),
           sourceOwnerUserID != createdByUserID,
           let ownerName = familyContextStore.displayName(for: sourceOwnerUserID) {
            parts.append("\(sourceWallet.name) • \(ownerName)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var cashflowColor: Color {
        if TransactionLogic.isCreditCardPayment(record) {
            return .white
        }

        switch record.primaryKind {
        case .expense:
            return MistiaAccent.expense.color
        case .income:
            return MistiaAccent.income.color
        case .transfer:
            if TransactionLogic.isPaidForExpenseDebt(record) {
                return MistiaAccent.expense.color
            }
            if record.transferSubtype == .debt {
                return debtIntentTint(record.debtIntent)
            }
            if record.transferSubtype == .familyTransfer {
                let cashflow = TransactionLogic.cashflowAmount(for: record)
                if cashflow > 0 {
                    return MistiaAccent.income.color
                }
                if cashflow < 0 {
                    return MistiaAccent.expense.color
                }
            }
            return colorScheme == .dark ? .white : MistiaAccent.transfer.color
        }
    }

    private var displayAmount: String {
        let raw = displayAmountMinor.formattedCurrency(code: displayCurrencyCode)

        if TransactionLogic.isCreditCardPayment(record) {
            return raw
        }

        switch record.primaryKind {
        case .expense:
            return showsExpenseMinusSign ? "-" + raw : raw
        case .income:
            return "+" + raw
        case .transfer:
            if TransactionLogic.isPaidForExpenseDebt(record) {
                return "-" + raw
            }
            let cashflow = TransactionLogic.cashflowAmount(for: record)
            if cashflow > 0 {
                return "+" + raw
            }
            if cashflow < 0 {
                return "-" + raw
            }
            return raw
        }
    }

    private var displayAmountMinor: Int64 {
        if record.primaryKind == .transfer,
           record.transferSubtype == .internalTransfer,
           TransactionLogic.cashflowAmount(for: record) > 0 {
            return record.destinationAmountMinor ?? record.amountMinor
        }
        return record.amountMinor
    }

    private var displayCurrencyCode: String {
        if record.primaryKind == .transfer,
           record.transferSubtype == .internalTransfer,
           TransactionLogic.cashflowAmount(for: record) > 0 {
            return record.destinationCurrencyCode
                ?? transaction.destinationWallet?.currencyCode
                ?? transaction.sourceWallet?.currencyCode
                ?? "JPY"
        }

        return record.sourceCurrencyCode
            ?? transaction.sourceWallet?.currencyCode
            ?? transaction.destinationWallet?.currencyCode
            ?? "JPY"
    }

    private var approximatePrimaryAmountText: String? {
        MistiaCurrencyLogic.approximatePrimaryAmountText(
            amountMinor: displayAmountMinor,
            sourceCurrencyCode: displayCurrencyCode,
            primaryCurrencyCode: primaryCurrencyCode,
            rateIndex: exchangeRateIndex
        )
    }

    private var transferDestinationAmountText: String? {
        guard let destinationDisplay = TransactionLogic.crossCurrencyTransferDestinationDisplay(for: record) else {
            return nil
        }

        let amount = destinationDisplay.amountMinor.formattedCurrency(code: destinationDisplay.currencyCode)
        switch destinationDisplay.style {
        case .exactDestination:
            return "-> " + amount
        case .approximateDestination:
            return "~" + amount
        }
    }

    private var secondaryAmountText: String? {
        transferDestinationAmountText ?? approximatePrimaryAmountText
    }

    var body: some View {
        HStack(spacing: 12) {
            TransactionIconTile(icon: icon, tint: iconColor)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if record.primaryKind == .transfer, let subtype = record.transferSubtype,
                       subtype == .debt {
                        MistiaMiniBadge(
                            title: subtype.title,
                            tint: debtIntentTint(record.debtIntent)
                        )
                    }

                    if record.settlementGroupID != nil {
                        MistiaMiniBadge(
                            title: L10n.transactions.settlement.eventTitle,
                            tint: MistiaAccent.teal.color
                        )
                    }

                    if hasFamilyOwnerConflict {
                        MistiaMiniBadge(
                            title: L10n.shared.sync.familyOwnerPushConflict.badge,
                            tint: MistiaAccent.amber.color
                        )
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(subtitleLineLimit)
                    .truncationMode(.tail)

                if showsAuditSubtitle, let auditSubtitle {
                    Text(auditSubtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(displayAmount)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(cashflowColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let secondaryAmountText {
                    Text(secondaryAmountText)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 96, alignment: .trailing)
            .layoutPriority(2)
        }
    }

    private func ownerUserID(for walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID]
    }
}

private struct TransactionIconTile: View {
    let icon: String
    let tint: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: tint, size: 34)
    }
}




private struct TransactionToolbarChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isActive: Bool
    let trailingIcon: String?

    private var foregroundColor: Color {
        if isActive {
            return .white
        }

        if colorScheme == .dark {
            return Color.white.opacity(0.92)
        }

        return Color.black.opacity(0.74)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
            
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(foregroundColor)
        .animation(nil, value: title)
        .animation(nil, value: isActive)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}

private struct OutstandingDebtChip: View {
    let position: CounterpartyDebtSnapshot
    let action: () -> Void

    private var tint: Color {
        debtIntentTint(position.isReceivable ? .lend : .borrow)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MistiaFinanceIconView(
                    icon: (position.isReceivable ? TransactionDebtIntent.lend : TransactionDebtIntent.borrow).financeIconToken,
                    fallbackColor: tint,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(position.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(
                        position.isReceivable
                            ? L10n.transactions.transactions.theyOweYou
                            : L10n.transactions.transactions.youOwe
                    )
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(abs(position.netMinor).formattedCurrency(code: position.currencyCode))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(width: 220, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.6)
                    }
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16, tint: tint))
    }
}

struct DebtSettlementSheetTarget: Identifiable {
    let id: String
    let position: CounterpartyDebtSnapshot

    init(position: CounterpartyDebtSnapshot) {
        self.position = position
        self.id = position.id
    }

    var intent: TransactionDebtIntent {
        position.isReceivable ? .collect : .repay
    }

    var amountMinor: Int64 {
        abs(position.netMinor)
    }
}

private struct DebtSettlementDismissalSnapshot: Equatable {
    let amountText: String
    let selectedWalletID: UUID?
}

struct DebtSettlementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query
    private var wallets: [LedgerWallet]
    @Query private var settlementGroups: [SettlementGroup]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: DebtSettlementSheetTarget

    @State private var amountText = ""
    @State private var selectedWalletID: UUID?
    @State private var dismissBaselineSnapshot: DebtSettlementDismissalSnapshot?
    @State private var alertMessage: String?
    @State private var isDetailExpanded = false

    private var tint: Color {
        debtIntentTint(target.intent)
    }

    private var amountTint: Color {
        target.position.isReceivable ? debtIntentTint(.lend) : tint
    }

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeOwnerUserID: UUID? {
        walletPickerAccess.walletOwnerUserID(for: target.position.preferredWalletID)
            ?? familyContextStore.selectedSubjectUserID
            ?? walletPickerAccess.currentSelfUserID
    }

    private var availableWallets: [LedgerWallet] {
        walletPickerAccess.availableWallets(
            from: wallets,
            preferredWalletIDs: Set([target.position.preferredWalletID, selectedWalletID].compactMap { $0 }),
            targetOwnerUserID: activeOwnerUserID,
            excludesCreditCards: true
        )
        .filter { MistiaCurrencyLogic.normalizedCode($0.currencyCode) == target.position.currencyCode }
    }

    private var selectedWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == selectedWalletID })
    }

    private var parsedAmountMinor: Int64 {
        amountText.currencyInputToMinorUnits(currencyCode: target.position.currencyCode)
    }

    private var isSaveDisabled: Bool {
        selectedWallet == nil || parsedAmountMinor <= 0 || parsedAmountMinor > target.amountMinor
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: .creating,
            hasUnsavedChanges: hasUnsavedChangesForDismissal
        )
    }

    private var hasUnsavedChangesForDismissal: Bool {
        guard let dismissBaselineSnapshot else { return false }
        return DebtSettlementDismissalSnapshot(
            amountText: amountText.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedWalletID: selectedWalletID
        ) != dismissBaselineSnapshot
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        MistiaFinanceIconView(
                            icon: target.intent.financeIconToken,
                            fallbackColor: tint,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.position.displayName)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(target.amountMinor.formattedCurrency(code: target.position.currencyCode))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(amountTint)
                            Text(target.position.isReceivable ? L10n.transactions.transactions.theyOweYou : L10n.transactions.transactions.youOwe)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if target.amountMinor > 0 {
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
                } else {
                    Section {
                        HStack {
                            Spacer()
                            Text(L10n.transactions.settlement.debtFullySettled)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }

                if !target.position.relatedRecords.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isDetailExpanded) {
                            VStack(spacing: 0) {
                                ForEach(Array(target.position.relatedRecords.enumerated()), id: \.element.id) { index, record in
                                    DebtSettlementDetailRow(
                                        record: record,
                                        walletName: walletName(for: record.sourceWalletID)
                                    )

                                    if index < target.position.relatedRecords.count - 1 {
                                        Divider()
                                            .padding(.leading, 46)
                                    }
                                }
                            }
                        } label: {
                            Text(L10n.transactions.debtsettlement.detail)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
            .navigationTitle(target.intent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MistiaGuardedDismissButton(configuration: dismissGuardConfiguration)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if target.amountMinor > 0 {
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
        .onAppear {
            amountText = MistiaCurrencyInputFormatting.groupedInput(String(target.amountMinor))
            if let preferredWalletID = target.position.preferredWalletID,
               availableWallets.contains(where: { $0.id == preferredWalletID }) {
                selectedWalletID = preferredWalletID
            } else {
                selectedWalletID = availableWallets.first?.id
            }
            if dismissBaselineSnapshot == nil {
                dismissBaselineSnapshot = DebtSettlementDismissalSnapshot(
                    amountText: amountText.trimmingCharacters(in: .whitespacesAndNewlines),
                    selectedWalletID: selectedWalletID
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .alert(
            L10n.transactions.transactioneditor.canTSaveYet,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L10n.common.ok, role: .cancel) {}
        } message: {
            if let alertMessage { Text(alertMessage) }
        }
    }

    private func walletName(for walletID: UUID?) -> String? {
        guard let walletID,
              let wallet = wallets.first(where: { $0.id == walletID })
        else {
            return nil
        }

        return wallet.name
    }

    private func save() {
        guard parsedAmountMinor > 0 else {
            alertMessage = L10n.transactions.transactioneditor.enterAnAmountGreaterThan
            return
        }

        guard parsedAmountMinor <= target.amountMinor else {
            alertMessage = L10n.transactions.debtsettlement.amountExceedsOutstanding
            return
        }

        guard let selectedWallet else {
            alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
            return
        }

        let now = Date()
        let allocations = SettlementLogic.sharedExpenseDebtPaymentAllocations(
            from: target.position.relatedRecords,
            settlementIntent: target.intent,
            paymentMinor: parsedAmountMinor
        )
        let transactions = allocations.map { allocation in
            LedgerTransaction(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: target.intent,
                entryStatus: .posted,
                title: target.intent.title,
                amountMinor: allocation.amountMinor,
                settlementGroupID: allocation.settlementGroupID,
                settlementRole: allocation.settlementRole,
                reportingExpenseMinor: allocation.reportingExpenseMinor,
                reportingIncomeMinor: allocation.reportingIncomeMinor,
                sourceCurrencyCode: selectedWallet.currencyCode,
                occurredAt: now,
                createdAt: now,
                updatedAt: now,
                sourceWallet: selectedWallet,
                counterpartyName: target.position.displayName,
                normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(target.position.displayName)
            )
        }

        transactions.forEach(modelContext.insert)
        updateSharedExpenseGroupsAfterDebtPayment(allocations: allocations, transactions: transactions, modifiedAt: now)

        do {
            let ownerUserID = walletPickerAccess.walletOwnerUserID(for: selectedWallet)
            let actorUserID = sessionStore.activeLocalProfileUserID ?? ownerUserID
            if let actorUserID {
                for transaction in transactions {
                    try TransactionAuditStore.upsert(
                        transactionID: transaction.id,
                        createdByUserID: actorUserID,
                        lastModifiedByUserID: actorUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
            }
            if let ownerUserID {
                for transaction in transactions {
                    try MistiaRecordOwnershipStore.upsert(
                        entity: .transaction,
                        recordID: transaction.id,
                        ownerUserID: ownerUserID,
                        updatedAt: now,
                        context: modelContext
                    )
                }
                for groupID in Set(allocations.compactMap(\.settlementGroupID)) {
                    if let group = settlementGroups.first(where: { $0.id == groupID }) {
                        try MistiaRecordOwnershipStore.upsert(
                            entity: .settlementGroup,
                            recordID: group.id,
                            ownerUserID: ownerUserID,
                            updatedAt: now,
                            context: modelContext
                        )
                    }
                }
            }
            try modelContext.save()
            for transaction in transactions {
                sessionStore.recordUpsert(
                    entity: .transaction,
                    recordID: transaction.id,
                    modifiedAt: transaction.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            }
            for groupID in Set(allocations.compactMap(\.settlementGroupID)) {
                if let group = settlementGroups.first(where: { $0.id == groupID }) {
                    sessionStore.recordUpsert(
                        entity: .settlementGroup,
                        recordID: group.id,
                        modifiedAt: group.updatedAt,
                        subjectUserIDOverride: ownerUserID
                    )
                }
            }
            if let ownerUserID, ownerUserID != sessionStore.activeLocalProfileUserID {
                Task { @MainActor in
                    _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
                }
            }
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func updateSharedExpenseGroupsAfterDebtPayment(
        allocations: [SettlementDebtPaymentAllocation],
        transactions: [LedgerTransaction],
        modifiedAt: Date
    ) {
        let affectedGroupIDs = Set(allocations.compactMap(\.settlementGroupID))
        guard !affectedGroupIDs.isEmpty else { return }

        let newSnapshots = transactions.map(\.snapshot)
        for groupID in affectedGroupIDs {
            guard let group = settlementGroups.first(where: { $0.id == groupID }) else { continue }
            let groupRecords = target.position.relatedRecords.filter { $0.settlementGroupID == groupID } + newSnapshots.filter { $0.settlementGroupID == groupID }
            let principalIntent: TransactionDebtIntent = target.intent == .collect ? .lend : .borrow
            let paymentIntent: TransactionDebtIntent = target.intent
            let expected = groupRecords.reduce(Int64.zero) { total, record in
                record.debtIntent == principalIntent ? total + max(record.amountMinor, 0) : total
            }
            let settled = min(
                expected,
                groupRecords.reduce(Int64.zero) { total, record in
                    record.debtIntent == paymentIntent ? total + max(record.amountMinor, 0) : total
                }
            )
            group.expectedMinor = max(group.expectedMinor, expected)
            group.settledMinor = settled
            group.status = settled >= max(group.expectedMinor, expected) ? .settled : (settled > 0 ? .partiallySettled : .open)
            group.isArchived = group.status == .settled
            group.archivedAt = group.status == .settled ? (group.archivedAt ?? modifiedAt) : nil
            group.updatedAt = modifiedAt
        }
    }
}

private struct DebtSettlementDetailRow: View {
    let record: TransactionRecordSnapshot
    let walletName: String?

    private var icon: String {
        if TransactionLogic.isPaidForDebt(record) || record.transferSubtype == .debt {
            return record.debtIntent?.financeIconToken ?? TransactionTransferSubtype.debt.financeIconToken
        }

        return switch record.primaryKind {
        case .expense, .income:
            record.primaryKind.financeIconToken
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                TransactionTransferSubtype.internalTransfer.financeIconToken
            case .familyTransfer:
                TransactionTransferSubtype.familyTransfer.financeIconToken
            case .debt:
                TransactionTransferSubtype.debt.financeIconToken
            case nil:
                record.primaryKind.financeIconToken
            }
        }
    }

    private var tint: Color {
        debtIntentTint(record.debtIntent)
    }

    private var currencyCode: String {
        MistiaCurrencyLogic.normalizedCode(record.sourceCurrencyCode)
    }

    private var title: String {
        if let trimmed = record.title.nilIfBlank {
            return trimmed
        }

        switch record.primaryKind {
        case .expense:
            return L10n.transactions.transactions.expenseNeedsDetails
        case .income:
            return L10n.transactions.transactions.incomeNeedsDetails
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                return L10n.transactions.transactions.internalTransfer
            case .familyTransfer:
                return L10n.shared.corelogic.financeenums.family
            case .debt:
                return record.debtIntent?.title ?? L10n.transactions.transactions.debt
            case nil:
                return L10n.transactions.transactions.transferNeedsDetails
            }
        }
    }

    private var amountText: String {
        let raw = record.amountMinor.formattedCurrency(code: currencyCode)

        if TransactionLogic.isPaidForExpenseDebt(record) {
            return "-" + raw
        }

        let cashflow = TransactionLogic.cashflowAmount(for: record)
        if cashflow > 0 {
            return "+" + raw
        }
        if cashflow < 0 {
            return "-" + raw
        }
        return raw
    }

    private var cashflowColor: Color {
        if TransactionLogic.isPaidForExpenseDebt(record) {
            return MistiaAccent.expense.color
        }
        if record.transferSubtype == .debt {
            return debtIntentTint(record.debtIntent)
        }
        return tint
    }

    private var subtitle: String {
        let intent = record.debtIntent?.title ?? L10n.transactions.transactions.debt

        if TransactionLogic.isPaidForDebt(record) {
            return "\(intent) • \(L10n.transactions.transactioneditor.borrowPaidFor)"
        }

        if let walletName {
            return "\(intent) • \(walletName)"
        }

        return intent
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TransactionIconTile(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(MistiaDateFormatting.dateTimeString(for: record.occurredAt))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text(amountText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(cashflowColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.vertical, 10)
    }
}

private struct TransactionsPlaceholderCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let symbols = ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
    let accent = MistiaAccent.purple.color

    private var buttonForeground: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : accent
    }

    private var symbolBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.10
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 14) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                        ZStack {
                            Circle()
                                .fill(accent.opacity(symbolBackgroundOpacity + Double(index) * 0.025))

                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(buttonForeground)
                        }
                        .frame(width: 34, height: 34)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Int64 {
    var positiveOrNil: Int64? {
        self > 0 ? self : nil
    }
}

private struct EventCashflowRow: View {
    let event: PreparingSettlementEventSnapshot

    private var participantText: String {
        if event.participantNames.isEmpty {
            return L10n.transactions.settlement.noParticipantsYet
        }
        return event.participantNames.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            TransactionIconTile(
                icon: "mistia.settlement.event",
                tint: MistiaAccent.purple.color
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
        .contentShape(Rectangle())
    }
}
