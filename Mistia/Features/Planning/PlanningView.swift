import SwiftData
import SwiftUI

private enum PlanningMode: String, CaseIterable, Identifiable {
    case budget
    case due
    case goals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budget:
            L10n.planning.planning.budget2
        case .due:
            L10n.planning.planning.due2
        case .goals:
            L10n.planning.planning.goals2
        }
    }

    var icon: String {
        switch self {
        case .budget:
            "banknote.fill"
        case .due:
            "calendar.badge.clock"
        case .goals:
            "target"
        }
    }
}

private enum PlanningDueMode: String, CaseIterable, Identifiable {
    case bills
    case creditCards
    case installments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bills:
            L10n.planning.planning.bills2
        case .creditCards:
            L10n.planning.planning.creditCards
        case .installments:
            L10n.planning.planning.installmentsLoans2
        }
    }
}

private enum PlanningNavigationDestination: Identifiable, Equatable, Hashable {
    case profile
    case creditCardStatement(LedgerWallet)

    var id: String {
        switch self {
        case .profile: return "profile"
        case .creditCardStatement(let wallet): return "creditCardStatement-\(wallet.id)"
        }
    }

    static func == (lhs: PlanningNavigationDestination, rhs: PlanningNavigationDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct PlanningPermissionPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
}

private struct PlanningInfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct PlanningFamilyOwnerConflictAlert: Identifiable {
    let entity: MistiaSyncEntity
    let recordID: UUID

    var id: String {
        FamilyOwnerPushConflict.key(entity: entity, recordID: recordID)
    }
}

private struct PlanningWalletPermissionPrompt: Identifiable {
    let id = UUID()
    let walletID: UUID
    let walletName: String
    let ownerUserID: UUID
    let title: String
    let message: String
}

private enum PlanningAlertPresentation: Identifiable {
    case permission(PlanningPermissionPrompt)
    case wallet(PlanningWalletPermissionPrompt)
    case info(PlanningInfoAlert)
    case familyOwnerConflict(PlanningFamilyOwnerConflictAlert)

    var id: String {
        switch self {
        case .permission(let prompt):
            prompt.id.uuidString
        case .wallet(let prompt):
            prompt.id.uuidString
        case .info(let alert):
            alert.id.uuidString
        case .familyOwnerConflict(let alert):
            alert.id
        }
    }

    var title: String {
        switch self {
        case .permission(let prompt):
            prompt.title
        case .wallet(let prompt):
            prompt.title
        case .info(let alert):
            alert.title
        case .familyOwnerConflict:
            L10n.shared.sync.familyOwnerPushConflict.alertTitle
        }
    }

    var message: String {
        switch self {
        case .permission(let prompt):
            prompt.message
        case .wallet(let prompt):
            prompt.message
        case .info(let alert):
            alert.message
        case .familyOwnerConflict:
            L10n.shared.sync.familyOwnerPushConflict.alertMessage
        }
    }
}

private struct PlanningBudgetRenderSnapshot {
    let summary: PlanningBudgetSummarySnapshot
    let rows: [PlanningBudgetBranchRowSnapshot]
}

private struct PlanningGoalRenderSnapshot {
    let summary: PlanningGoalSummarySnapshot
    let rows: [PlanningGoalRowSnapshot]
}

private struct PlanningDueRenderSnapshot {
    let summary: PlanningDueSummarySnapshot
    let creditCards: [PlanningCreditCardAccountSnapshot]
    let bills: [PlanningRecurringDueSnapshot]
    let pausedBills: [PlanningBillSnapshot]
    let installments: [PlanningRecurringDueSnapshot]
}

private struct PlanningRenderSnapshotBaseCacheKey: Hashable {
    let activeScope: FamilyContext.Scope
    let selectedSubjectUserID: UUID?
    let currentUserID: UUID?
    let activeLocalProfileUserID: UUID?
    let signedInUserID: UUID?
    let familyID: UUID?
    let selectedMonthStart: TimeInterval
    let calendarIdentifier: String
    let calendarTimeZoneIdentifier: String
    let currencyCode: String
    let currencyRateMode: String
    let manualJPYToVNDRate: String
    let cachedRatesSignature: Int
    let familyAccessSignature: Int
    let ownershipSignature: MistiaCollectionChangeSignature
}

private struct PlanningBudgetRenderSnapshotCacheKey: Hashable {
    let base: PlanningRenderSnapshotBaseCacheKey
    let budgetSignature: MistiaCollectionChangeSignature
    let categorySignature: MistiaCollectionChangeSignature
    let transactionSignature: MistiaCollectionChangeSignature
}

private struct PlanningGoalRenderSnapshotCacheKey: Hashable {
    let base: PlanningRenderSnapshotBaseCacheKey
    let goalSignature: MistiaCollectionChangeSignature
}

private struct PlanningDueRenderSnapshotCacheKey: Hashable {
    let base: PlanningRenderSnapshotBaseCacheKey
    let transactionSignature: MistiaCollectionChangeSignature
    let occurrenceSignature: MistiaCollectionChangeSignature
    let walletSignature: MistiaCollectionChangeSignature
    let billSignature: MistiaCollectionChangeSignature
    let installmentSignature: MistiaCollectionChangeSignature
}

private struct PlanningBudgetRenderSnapshotCache {
    let key: PlanningBudgetRenderSnapshotCacheKey
    let snapshot: PlanningBudgetRenderSnapshot
}

private struct PlanningGoalRenderSnapshotCache {
    let key: PlanningGoalRenderSnapshotCacheKey
    let snapshot: PlanningGoalRenderSnapshot
}

private struct PlanningDueRenderSnapshotCache {
    let key: PlanningDueRenderSnapshotCacheKey
    let snapshot: PlanningDueRenderSnapshot
}

private enum PlanningActiveRenderSnapshotCacheKey: Hashable {
    case budget(PlanningBudgetRenderSnapshotCacheKey)
    case due(PlanningDueRenderSnapshotCacheKey)
    case goals(PlanningGoalRenderSnapshotCacheKey)
}

private enum PlanningActiveRenderSnapshot {
    case budget(PlanningBudgetRenderSnapshot)
    case due(PlanningDueRenderSnapshot)
    case goals(PlanningGoalRenderSnapshot)
}

struct PlanningView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState
    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgets: [BudgetPlan]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil })
    private var storedGoals: [SavingsGoal]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var storedBills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var storedInstallments: [InstallmentPlan]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var storedTransactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var currencyRateMode = MistiaCurrencyRateMode.automatic.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = ""
    @AppStorage(MistiaCurrencySettings.StorageKey.cachedRatesData) private var cachedCurrencyRatesData = Data()

    @State private var selectedMode: PlanningMode = .budget
    @State private var selectedDueMode: PlanningDueMode = .bills
    @State private var selectedMonth = PlanningLogic.startOfMonth(for: .now)
    @State private var isMonthPickerPresented = false
    @State private var budgetEditorTarget: PlanningBudgetEditorTarget?
    @State private var goalEditorTarget: PlanningGoalEditorTarget?
    @State private var billEditorTarget: PlanningBillEditorTarget?
    @State private var installmentEditorTarget: PlanningInstallmentEditorTarget?
    @State private var creditCardEditorTarget: PlanningCreditCardEditorTarget?
    @State private var duePaymentTarget: DuePaymentSheetTarget?
    @State private var destination: PlanningNavigationDestination?
    @State private var permissionPrompt: PlanningPermissionPrompt?
    @State private var walletPermissionPrompt: PlanningWalletPermissionPrompt?
    @State private var infoAlert: PlanningInfoAlert?
    @State private var familyOwnerConflictAlert: PlanningFamilyOwnerConflictAlert?
    @State private var memberViewingExitPrompt: FamilyMemberViewingExitPrompt?
    @State private var budgetRenderSnapshotCache: PlanningBudgetRenderSnapshotCache?
    @State private var goalRenderSnapshotCache: PlanningGoalRenderSnapshotCache?
    @State private var dueRenderSnapshotCache: PlanningDueRenderSnapshotCache?

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14)
    }

    private var transactionSnapshots: [TransactionRecordSnapshot] {
        visibleTransactions.map(\.planningRecordSnapshot)
    }

    private var appExchangeRates: [MistiaExchangeRate] {
        _ = currencyRateMode
        _ = manualJPYToVNDRate
        _ = cachedCurrencyRatesData
        return MistiaCurrencySettings.rates()
    }

    private var occurrenceSnapshots: [PlanningDueOccurrenceSnapshot] {
        visibleOccurrences.map(\.planningSnapshot)
    }

    private var activeAlert: PlanningAlertPresentation? {
        if let familyOwnerConflictAlert {
            return .familyOwnerConflict(familyOwnerConflictAlert)
        }
        if let walletPermissionPrompt {
            return .wallet(walletPermissionPrompt)
        }
        if let permissionPrompt {
            return .permission(permissionPrompt)
        }
        if let infoAlert {
            return .info(infoAlert)
        }
        return nil
    }

    private func makeScopeSnapshot() -> FamilyScopedData.ScopeSnapshot {
        FamilyScopedData.ScopeSnapshot(
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private func budgetRenderSnapshot() -> PlanningBudgetRenderSnapshot {
        let scopeSnapshot = makeScopeSnapshot()
        let visibleBudgets = FamilyScopedData.visible(
            storedBudgets,
            entity: .budgetPlan,
            scopeSnapshot: scopeSnapshot
        )
        let visibleTransactions = FamilyScopedData.visibleTransactionsForFinancial(
            storedTransactions,
            scopeSnapshot: scopeSnapshot
        )
        let familyTransactions = FamilyScopedData.familyBudgetTransactionSnapshots(
            from: storedTransactions,
            scopeSnapshot: scopeSnapshot,
            familyMemberUserIDs: currentFamilyMemberUserIDs,
            signedInUserID: sessionStore.activeLocalProfileUserID
        )
        let usesAggregateFamilyBudgetSpending = FamilyScopedData.usesAggregateFamilyBudgetSpending(
            isFamilyBudgetSpendingAvailable: isFamilyBudgetSpendingAvailable,
            familyContextStore: familyContextStore
        )
        let transactionSnapshots = visibleTransactions.map(\.planningRecordSnapshot)
        let activeBudgetPlans = PlanningLogic.resolvingFamilySpendingCategoryScopes(
            plans: visibleBudgets
                .filter { !$0.isArchived && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == selectedMonth }
                .map { $0.planningSnapshot(calendar: calendar) },
            categoryScopes: familyBudgetSpendingCategoryScopes
        )
        let rows = PlanningLogic.budgetBranchRows(
            plans: activeBudgetPlans,
            records: transactionSnapshots,
            selectedMonth: selectedMonth,
            referenceDate: .now,
            calendar: calendar,
            exchangeRates: appExchangeRates,
            familyTransactions: usesAggregateFamilyBudgetSpending ? familyTransactions : [],
            familySpendingAvailable: usesAggregateFamilyBudgetSpending
        )

        return PlanningBudgetRenderSnapshot(
            summary: PlanningLogic.budgetSummary(
                from: rows,
                reportingCurrencyCode: currencyCode,
                exchangeRates: appExchangeRates
            ),
            rows: rows
        )
    }

    private func goalRenderSnapshot() -> PlanningGoalRenderSnapshot {
        let scopeSnapshot = makeScopeSnapshot()
        let visibleGoals = FamilyScopedData.visible(
            storedGoals,
            entity: .savingsGoal,
            scopeSnapshot: scopeSnapshot
        )
        let rows = PlanningLogic.goalRows(
            goals: visibleGoals
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        return PlanningGoalRenderSnapshot(
            summary: PlanningLogic.goalSummary(
                from: rows,
                reportingCurrencyCode: currencyCode,
                exchangeRates: appExchangeRates
            ),
            rows: rows
        )
    }

    private func dueRenderSnapshot() -> PlanningDueRenderSnapshot {
        let scopeSnapshot = makeScopeSnapshot()
        let visibleTransactions = FamilyScopedData.visibleTransactionsForFinancial(
            storedTransactions,
            scopeSnapshot: scopeSnapshot
        )
        let visibleOccurrences = FamilyScopedData.visible(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
            scopeSnapshot: scopeSnapshot
        )
        let visibleWallets = FamilyScopedData.visible(
            storedWallets,
            entity: .wallet,
            scopeSnapshot: scopeSnapshot
        )
        let visibleBills = FamilyScopedData.visible(
            storedBills,
            entity: .recurringBillPlan,
            scopeSnapshot: scopeSnapshot
        )
        let visibleInstallments = FamilyScopedData.visible(
            storedInstallments,
            entity: .installmentPlan,
            scopeSnapshot: scopeSnapshot
        )
        let transactionSnapshots = visibleTransactions.map(\.planningRecordSnapshot)
        let occurrenceSnapshots = visibleOccurrences.map(\.planningSnapshot)
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: visibleWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionSnapshots
        )
        let creditCardAccounts = visibleWallets.compactMap {
            $0.planningCreditCardSnapshot(balanceIndex: balanceIndex)
        }
        let creditCardStatements = PlanningLogic.creditCardStatementsDue(
            in: selectedMonth,
            accounts: creditCardAccounts,
            records: transactionSnapshots,
            occurrences: occurrenceSnapshots,
            referenceDate: .now,
            calendar: calendar
        )
        let activeVisibleBills = visibleBills.filter { !$0.isArchived }
        let activeBillSnapshots = activeVisibleBills.map(\.planningSnapshot)
        let pausedBills = PlanningLogic.pausedRecurringBills(from: activeBillSnapshots)
        let recurringBillDueItems = PlanningLogic.recurringBillDueItems(
            bills: activeBillSnapshots,
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
        let installmentDueItems = PlanningLogic.installmentDueItems(
            plans: visibleInstallments
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            calendar: calendar
        )

        return PlanningDueRenderSnapshot(
            summary: PlanningLogic.dueSummary(
                creditStatements: creditCardStatements,
                recurring: recurringBillDueItems + installmentDueItems,
                selectedMonth: selectedMonth,
                reportingCurrencyCode: currencyCode,
                exchangeRates: appExchangeRates,
                referenceDate: .now,
                calendar: calendar
            ),
            creditCards: creditCardAccounts,
            bills: recurringBillDueItems,
            pausedBills: pausedBills,
            installments: installmentDueItems
        )
    }

    private func cachedActiveRenderSnapshot(
        for activeKey: PlanningActiveRenderSnapshotCacheKey
    ) -> PlanningActiveRenderSnapshot {
        switch activeKey {
        case .budget:
            .budget(cachedBudgetRenderSnapshot(for: activeKey))
        case .due:
            .due(cachedDueRenderSnapshot(for: activeKey))
        case .goals:
            .goals(cachedGoalRenderSnapshot(for: activeKey))
        }
    }

    private func cachedBudgetRenderSnapshot(
        for activeKey: PlanningActiveRenderSnapshotCacheKey
    ) -> PlanningBudgetRenderSnapshot {
        guard case .budget(let key) = activeKey else {
            return budgetRenderSnapshot()
        }

        if let budgetRenderSnapshotCache, budgetRenderSnapshotCache.key == key {
            return budgetRenderSnapshotCache.snapshot
        }

        return budgetRenderSnapshot()
    }

    private func cachedGoalRenderSnapshot(
        for activeKey: PlanningActiveRenderSnapshotCacheKey
    ) -> PlanningGoalRenderSnapshot {
        guard case .goals(let key) = activeKey else {
            return goalRenderSnapshot()
        }

        if let goalRenderSnapshotCache, goalRenderSnapshotCache.key == key {
            return goalRenderSnapshotCache.snapshot
        }

        return goalRenderSnapshot()
    }

    private func cachedDueRenderSnapshot(
        for activeKey: PlanningActiveRenderSnapshotCacheKey
    ) -> PlanningDueRenderSnapshot {
        guard case .due(let key) = activeKey else {
            return dueRenderSnapshot()
        }

        if let dueRenderSnapshotCache, dueRenderSnapshotCache.key == key {
            return dueRenderSnapshotCache.snapshot
        }

        return dueRenderSnapshot()
    }

    private func refreshActiveRenderSnapshotCache(
        for activeKey: PlanningActiveRenderSnapshotCacheKey,
        snapshot activeSnapshot: PlanningActiveRenderSnapshot
    ) {
        switch (activeKey, activeSnapshot) {
        case (.budget(let key), .budget(let snapshot)):
            budgetRenderSnapshotCache = PlanningBudgetRenderSnapshotCache(
                key: key,
                snapshot: snapshot
            )
        case (.due(let key), .due(let snapshot)):
            dueRenderSnapshotCache = PlanningDueRenderSnapshotCache(
                key: key,
                snapshot: snapshot
            )
        case (.goals(let key), .goals(let snapshot)):
            goalRenderSnapshotCache = PlanningGoalRenderSnapshotCache(
                key: key,
                snapshot: snapshot
            )
        default:
            break
        }
    }

    private var activeRenderSnapshotCacheKey: PlanningActiveRenderSnapshotCacheKey {
        switch selectedMode {
        case .budget:
            .budget(budgetRenderSnapshotCacheKey)
        case .due:
            .due(dueRenderSnapshotCacheKey)
        case .goals:
            .goals(goalRenderSnapshotCacheKey)
        }
    }

    private var renderSnapshotBaseCacheKey: PlanningRenderSnapshotBaseCacheKey {
        PlanningRenderSnapshotBaseCacheKey(
            activeScope: familyContextStore.activeContext.scope,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.signedInUserID,
            familyID: familyContextStore.family?.id,
            selectedMonthStart: selectedMonth.timeIntervalSince1970,
            calendarIdentifier: String(describing: calendar.identifier),
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            currencyCode: currencyCode,
            currencyRateMode: currencyRateMode,
            manualJPYToVNDRate: manualJPYToVNDRate,
            cachedRatesSignature: cachedCurrencyRatesData.hashValue,
            familyAccessSignature: familyAccessSignature,
            ownershipSignature: MistiaCollectionChangeSignature.make(
                ownershipScopes,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            )
        )
    }

    private var budgetRenderSnapshotCacheKey: PlanningBudgetRenderSnapshotCacheKey {
        PlanningBudgetRenderSnapshotCacheKey(
            base: renderSnapshotBaseCacheKey,
            budgetSignature: MistiaCollectionChangeSignature.make(
                storedBudgets,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            categorySignature: MistiaCollectionChangeSignature.make(
                storedCategories,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            transactionSignature: MistiaCollectionChangeSignature.make(
                storedTransactions,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            )
        )
    }

    private var goalRenderSnapshotCacheKey: PlanningGoalRenderSnapshotCacheKey {
        PlanningGoalRenderSnapshotCacheKey(
            base: renderSnapshotBaseCacheKey,
            goalSignature: MistiaCollectionChangeSignature.make(
                storedGoals,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            )
        )
    }

    private var dueRenderSnapshotCacheKey: PlanningDueRenderSnapshotCacheKey {
        PlanningDueRenderSnapshotCacheKey(
            base: renderSnapshotBaseCacheKey,
            transactionSignature: MistiaCollectionChangeSignature.make(
                storedTransactions,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            occurrenceSignature: MistiaCollectionChangeSignature.make(
                storedOccurrences,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                remoteVersion: \.remoteVersion
            ),
            walletSignature: MistiaCollectionChangeSignature.make(
                storedWallets,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            billSignature: MistiaCollectionChangeSignature.make(
                storedBills,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            installmentSignature: MistiaCollectionChangeSignature.make(
                storedInstallments,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
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

    private var isFamilyBudgetSpendingAvailable: Bool {
        familyContextStore.family != nil && familyContextStore.members.count >= 2
    }

    private var currentFamilyMemberUserIDs: Set<UUID> {
        guard isFamilyBudgetSpendingAvailable else { return [] }
        return Set(familyContextStore.members.map(\.userID))
    }

    private var activeBudgetPlans: [BudgetPlanSnapshot] {
        PlanningLogic.resolvingFamilySpendingCategoryScopes(
            plans: visibleBudgets
                .filter { !$0.isArchived && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == selectedMonth }
                .map { $0.planningSnapshot(calendar: calendar) },
            categoryScopes: familyBudgetSpendingCategoryScopes
        )
    }

    private var familyBudgetSpendingCategoryScopes: [PlanningFamilyBudgetSpendingCategoryScope] {
        storedCategories
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .map(\.planningFamilyBudgetSpendingScope)
    }

    private var budgetRows: [PlanningBudgetBranchRowSnapshot] {
        let scopeSnapshot = makeScopeSnapshot()
        let familyTransactions = FamilyScopedData.familyBudgetTransactionSnapshots(
            from: storedTransactions,
            scopeSnapshot: scopeSnapshot,
            familyMemberUserIDs: currentFamilyMemberUserIDs,
            signedInUserID: sessionStore.activeLocalProfileUserID
        )
        let usesAggregateFamilyBudgetSpending = FamilyScopedData.usesAggregateFamilyBudgetSpending(
            isFamilyBudgetSpendingAvailable: isFamilyBudgetSpendingAvailable,
            familyContextStore: familyContextStore
        )

        return PlanningLogic.budgetBranchRows(
            plans: activeBudgetPlans,
            records: transactionSnapshots,
            selectedMonth: selectedMonth,
            referenceDate: .now,
            calendar: calendar,
            exchangeRates: appExchangeRates,
            familyTransactions: usesAggregateFamilyBudgetSpending ? familyTransactions : [],
            familySpendingAvailable: usesAggregateFamilyBudgetSpending
        )
    }

    private var budgetSummary: PlanningBudgetSummarySnapshot {
        PlanningLogic.budgetSummary(
            from: budgetRows,
            reportingCurrencyCode: currencyCode,
            exchangeRates: appExchangeRates
        )
    }

    private var activeGoals: [SavingsGoalSnapshot] {
        visibleGoals
            .filter { !$0.isArchived }
            .map(\.planningSnapshot)
    }

    private var goalRows: [PlanningGoalRowSnapshot] {
        PlanningLogic.goalRows(
            goals: activeGoals,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
    }

    private var goalSummary: PlanningGoalSummarySnapshot {
        PlanningLogic.goalSummary(
            from: goalRows,
            reportingCurrencyCode: currencyCode,
            exchangeRates: appExchangeRates
        )
    }

    private var creditCardAccounts: [PlanningCreditCardAccountSnapshot] {
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: visibleWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionSnapshots
        )
        return visibleWallets.compactMap { $0.planningCreditCardSnapshot(balanceIndex: balanceIndex) }
    }

    private var creditCardDueItems: [PlanningCreditCardDueSnapshot] {
        PlanningLogic.creditCardDueItems(
            accounts: creditCardAccounts,
            records: transactionSnapshots,
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var creditCardStatementDueItems: [PlanningCreditCardStatementSnapshot] {
        PlanningLogic.creditCardStatementsDue(
            in: selectedMonth,
            accounts: creditCardAccounts,
            records: transactionSnapshots,
            occurrences: occurrenceSnapshots,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var recurringBillDueItems: [PlanningRecurringDueSnapshot] {
        PlanningLogic.recurringBillDueItems(
            bills: storedBills
                .filter { visibleBillIDs.contains($0.id) }
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
    }

    private var installmentDueItems: [PlanningRecurringDueSnapshot] {
        PlanningLogic.installmentDueItems(
            plans: storedInstallments
                .filter { visibleInstallmentIDs.contains($0.id) }
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
    }

    private var visibleBudgets: [BudgetPlan] {
        FamilyScopedData.visible(
            storedBudgets,
            entity: .budgetPlan,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleGoals: [SavingsGoal] {
        FamilyScopedData.visible(
            storedGoals,
            entity: .savingsGoal,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleBills: [RecurringBillPlan] {
        FamilyScopedData.visible(
            storedBills,
            entity: .recurringBillPlan,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleBillIDs: Set<UUID> {
        Set(visibleBills.map(\.id))
    }

    private var visibleInstallments: [InstallmentPlan] {
        FamilyScopedData.visible(
            storedInstallments,
            entity: .installmentPlan,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleInstallmentIDs: Set<UUID> {
        Set(visibleInstallments.map(\.id))
    }

    private var visibleOccurrences: [DueOccurrenceRecord] {
        FamilyScopedData.visible(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
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

    private var visibleTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForFinancial(
            storedTransactions,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var selectedSubjectUserID: UUID? {
        familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var budgetOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
    }

    private var goalOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
    }

    private var billOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
    }

    private var installmentOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
    }

    private var dueSummary: PlanningDueSummarySnapshot {
        PlanningLogic.dueSummary(
            creditStatements: creditCardStatementDueItems,
            recurring: recurringBillDueItems + installmentDueItems,
            selectedMonth: selectedMonth,
            reportingCurrencyCode: currencyCode,
            exchangeRates: appExchangeRates,
            referenceDate: .now,
            calendar: calendar
        )
    }

    var body: some View {
        let activeSnapshotKey = activeRenderSnapshotCacheKey
        let activeSnapshot = cachedActiveRenderSnapshot(for: activeSnapshotKey)
        let memberToolbar = familyContextStore.memberViewingToolbarPresentation

        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .standard,
                title: L10n.planning.planning.planning,
                embedsInNavigationStack: false,
                leadingInitials: memberToolbar?.initials ?? sessionStore.summary?.initials ?? "MI",
                leadingAvatarURL: memberToolbar != nil ? familyContextStore.viewedMember?.avatarURL : sessionStore.summary?.avatarURL,
                leadingAccessibilityLabel: memberToolbar?.accessibilityLabel,
                leadingAvatarAttentionPulse: memberToolbar != nil,
                trailingSystemImage: "calendar",
                onLeadingTap: {
                    if let memberToolbar {
                        memberViewingExitPrompt = FamilyMemberViewingExitPrompt(presentation: memberToolbar)
                    } else {
                        destination = .profile
                    }
                },
                onTrailingTap: { isMonthPickerPresented = true },
                contentSpacing: 18,
                titleDisplayMode: .large,
                headerBehavior: .scrollsThenPins,
                pinnedHeader: {
                    VStack(alignment: .leading, spacing: 8) {
                        PlanningModePicker(selection: $selectedMode)
                    }
                }
            ) {
                switch activeSnapshot {
                case .budget(let tabSnapshot):
                    BudgetTabContent(
                        summary: tabSnapshot.summary,
                        currencyCode: currencyCode,
                        rows: tabSnapshot.rows,
                        referenceDate: .now,
                        onAdd: {
                            openBudgetAddIfAllowed()
                        },
                        onEditPrimary: { row in
                            guard let budgetID = row.primaryBudgetID else { return }
                            let budget = storedBudgets.first(where: { $0.id == budgetID })
                            openBudgetEditorIfAllowed(
                                budget: budget,
                                preferredParentCategoryID: row.parentCategoryID
                            )
                        },
                        onEditChild: { row in
                            let budget = storedBudgets.first(where: { $0.id == row.id })
                            openBudgetEditorIfAllowed(
                                budget: budget,
                                preferredParentCategoryID: nil
                            )
                        }
                    )
                case .due(let tabSnapshot):
                    DueTabContent(
                        selectedMode: $selectedDueMode,
                        summary: tabSnapshot.summary,
                        currencyCode: currencyCode,
                        creditCards: tabSnapshot.creditCards,
                        bills: tabSnapshot.bills,
                        pausedBills: tabSnapshot.pausedBills,
                        installments: tabSnapshot.installments,
                        referenceDate: .now,
                        onAddCreditCard: {
                            openCreditCardAddIfAllowed()
                        },
                        onEditCreditCard: { item in
                            openCreditCardEditorIfAllowed(
                                wallet: storedWallets.first(where: { $0.id == item.walletID }),
                                dueItem: nil
                            )
                        },
                        onAddBill: {
                            openBillAddIfAllowed()
                        },
                        onEditBill: { item in
                            openBillEditorIfAllowed(
                                plan: storedBills.first(where: { $0.id == item.sourceID }),
                                dueItem: item
                            )
                        },
                        onEditPausedBill: { item in
                            openBillEditorIfAllowed(
                                plan: storedBills.first(where: { $0.id == item.id }),
                                dueItem: nil
                            )
                        },
                        onResumePausedBill: { item in
                            resumePausedBillIfAllowed(item)
                        },
                        onAddInstallment: {
                            openInstallmentAddIfAllowed()
                        },
                        onEditInstallment: { item in
                            openInstallmentEditorIfAllowed(
                                plan: storedInstallments.first(where: { $0.id == item.sourceID }),
                                dueItem: item
                            )
                        },
                        onPayBill: { item in
                            openDuePaymentIfAllowed(item)
                        }
                    )
                case .goals(let tabSnapshot):
                    GoalsTabContent(
                        summary: tabSnapshot.summary,
                        currencyCode: currencyCode,
                        rows: tabSnapshot.rows,
                        onAdd: {
                            openGoalAddIfAllowed()
                        },
                        onEdit: { row in
                            openGoalEditorIfAllowed(
                                goal: storedGoals.first(where: { $0.id == row.id })
                            )
                        }
                    )
                }
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .profile:
                    ManagementAccountView()
                case .creditCardStatement(let wallet):
                    ManagementCreditCardStatementView(wallet: wallet)
                }
            }
        }
        .familyMemberViewingExitAlert(
            prompt: $memberViewingExitPrompt,
            familyContextStore: familyContextStore
        )
        .sheet(item: $budgetEditorTarget) { target in
            PlanningBudgetEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $goalEditorTarget) { target in
            PlanningGoalEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $billEditorTarget) { target in
            PlanningBillEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $installmentEditorTarget) { target in
            PlanningInstallmentEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $creditCardEditorTarget) { target in
            PlanningCreditCardEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $duePaymentTarget) { target in
            DuePaymentSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $isMonthPickerPresented) {
            MistiaMonthPickerSheet(
                selection: $selectedMonth,
                calendar: calendar,
                accentColor: MistiaAccent.purple.color
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.hidden)
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        familyOwnerConflictAlert = nil
                        walletPermissionPrompt = nil
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
                    }
                }
            case .permission(let prompt):
                Button(prompt.actionTitle) {
                    prompt.action()
                }
                Button(L10n.common.cancel, role: .cancel) {}
            case .wallet(let prompt):
                if shouldShowWalletPermissionAction(for: prompt, scope: .use) {
                    Button(walletPermissionActionTitle(for: prompt, scope: .use)) {
                        requestWalletPermission(prompt, scope: .use)
                    }
                }
                if shouldShowWalletPermissionAction(for: prompt, scope: .edit) {
                    Button(walletPermissionActionTitle(for: prompt, scope: .edit)) {
                        requestWalletPermission(prompt, scope: .edit)
                    }
                }
                Button(L10n.common.cancel, role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MistiaOpenCreditCardStatementFromPlanning"))) { notification in
            if let walletID = notification.object as? UUID,
               let wallet = storedWallets.first(where: { $0.id == walletID }) {
                destination = .creditCardStatement(wallet)
            }
        }
        .task(id: activeSnapshotKey) {
            refreshActiveRenderSnapshotCache(
                for: activeSnapshotKey,
                snapshot: activeSnapshot
            )
        }
    }

    private func openBudgetAddIfAllowed() {
        guard selectedMonth >= PlanningLogic.startOfMonth(for: .now, calendar: calendar) else {
            infoAlert = PlanningInfoAlert(
                title: L10n.planning.planning.budgets,
                message: L10n.planning.planning.pastBudgetReadOnlyReference
            )
            return
        }

        let ownerUserID = selectedSubjectUserID
        guard canCreate(ownerUserID: ownerUserID, resourceType: .budget) else {
            presentCreatePermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .budget,
                resourceName: L10n.planning.planning.budgets
            ) {
                openBudgetAddIfAllowed()
            }
            return
        }
        budgetEditorTarget = PlanningBudgetEditorTarget(
            budget: nil,
            selectedMonth: selectedMonth,
            preferredParentCategoryID: nil
        )
    }

    private func openBudgetEditorIfAllowed(budget: BudgetPlan?, preferredParentCategoryID: UUID?) {
        if let budget,
           presentFamilyOwnerConflictIfNeeded(entity: .budgetPlan, recordID: budget.id) {
            return
        }

        let ownerUserID = budget.flatMap { budgetOwnerMap[$0.id] } ?? selectedSubjectUserID
        guard canEdit(ownerUserID: ownerUserID, resourceType: .budget) else {
            presentEditPermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .budget,
                resourceName: L10n.planning.planning.budgets
            ) {
                openBudgetEditorIfAllowed(budget: budget, preferredParentCategoryID: preferredParentCategoryID)
            }
            return
        }
        budgetEditorTarget = PlanningBudgetEditorTarget(
            budget: budget,
            selectedMonth: selectedMonth,
            preferredParentCategoryID: preferredParentCategoryID
        )
    }

    private func openGoalAddIfAllowed() {
        let ownerUserID = selectedSubjectUserID
        guard canCreate(ownerUserID: ownerUserID, resourceType: .goal) else {
            presentCreatePermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .goal,
                resourceName: L10n.planning.planning.goals
            ) {
                openGoalAddIfAllowed()
            }
            return
        }
        goalEditorTarget = PlanningGoalEditorTarget(goal: nil)
    }

    private func openGoalEditorIfAllowed(goal: SavingsGoal?) {
        if let goal,
           presentFamilyOwnerConflictIfNeeded(entity: .savingsGoal, recordID: goal.id) {
            return
        }

        let ownerUserID = goal.flatMap { goalOwnerMap[$0.id] } ?? selectedSubjectUserID
        guard canEdit(ownerUserID: ownerUserID, resourceType: .goal) else {
            presentEditPermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .goal,
                resourceName: L10n.planning.planning.goals
            ) {
                openGoalEditorIfAllowed(goal: goal)
            }
            return
        }
        goalEditorTarget = PlanningGoalEditorTarget(goal: goal)
    }

    private func openCreditCardAddIfAllowed() {
        let ownerUserID = selectedSubjectUserID
        guard canCreate(ownerUserID: ownerUserID, resourceType: .wallet) else {
            presentCreatePermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .wallet,
                resourceName: L10n.planning.planning.walletsCards
            ) {
                openCreditCardAddIfAllowed()
            }
            return
        }
        creditCardEditorTarget = PlanningCreditCardEditorTarget(
            wallet: nil,
            dueItem: nil,
            selectedMonth: selectedMonth
        )
    }

    private func openCreditCardEditorIfAllowed(wallet: LedgerWallet?, dueItem: PlanningCreditCardDueSnapshot?) {
        let walletID = wallet?.id ?? dueItem?.walletID
        if let walletID,
           presentFamilyOwnerConflictIfNeeded(entity: .wallet, recordID: walletID) {
            return
        }

        let ownerUserID = walletID.flatMap { walletOwnerMap[$0] } ?? selectedSubjectUserID
        guard canOpenCreditCardEditor(walletID: walletID, ownerUserID: ownerUserID) else {
            if let walletID, let ownerUserID {
                presentCreditCardWalletPermissionPrompt(
                    walletID: walletID,
                    walletName: wallet?.name ?? dueItem?.walletName ?? L10n.planning.planning.creditCard,
                    ownerUserID: ownerUserID
                )
            } else {
                presentEditPermissionPrompt(
                    ownerUserID: ownerUserID,
                    resourceType: .wallet,
                    resourceID: walletID,
                    resourceName: L10n.planning.planning.walletsCards
                ) {
                    openCreditCardEditorIfAllowed(wallet: wallet, dueItem: dueItem)
                }
            }
            return
        }
        creditCardEditorTarget = PlanningCreditCardEditorTarget(
            wallet: wallet,
            dueItem: dueItem,
            selectedMonth: selectedMonth
        )
    }

    private func openBillAddIfAllowed() {
        let ownerUserID = selectedSubjectUserID
        guard canCreate(ownerUserID: ownerUserID, resourceType: .bill) else {
            presentCreatePermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .bill,
                resourceName: L10n.planning.planning.bills
            ) {
                openBillAddIfAllowed()
            }
            return
        }
        billEditorTarget = PlanningBillEditorTarget(plan: nil, dueItem: nil, selectedMonth: selectedMonth)
    }

    private func openBillEditorIfAllowed(plan: RecurringBillPlan?, dueItem: PlanningRecurringDueSnapshot?) {
        if let plan,
           presentFamilyOwnerConflictIfNeeded(entity: .recurringBillPlan, recordID: plan.id) {
            return
        }

        let ownerUserID = plan.flatMap { billOwnerMap[$0.id] } ?? selectedSubjectUserID
        guard canEdit(ownerUserID: ownerUserID, resourceType: .bill) else {
            presentEditPermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .bill,
                resourceName: L10n.planning.planning.bills
            ) {
                openBillEditorIfAllowed(plan: plan, dueItem: dueItem)
            }
            return
        }
        billEditorTarget = PlanningBillEditorTarget(plan: plan, dueItem: dueItem, selectedMonth: selectedMonth)
    }

    private func resumePausedBillIfAllowed(_ item: PlanningBillSnapshot) {
        guard let plan = storedBills.first(where: { $0.id == item.id }) else { return }
        if presentFamilyOwnerConflictIfNeeded(entity: .recurringBillPlan, recordID: plan.id) {
            return
        }

        let ownerUserID = billOwnerMap[plan.id] ?? selectedSubjectUserID
        guard canEdit(ownerUserID: ownerUserID, resourceType: .bill) else {
            presentEditPermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .bill,
                resourceName: L10n.planning.planning.bills
            ) {
                resumePausedBillIfAllowed(item)
            }
            return
        }

        let now = Date()
        do {
            try PlanningBillPauseActions.resume(
                plan,
                modelContext: modelContext,
                sessionStore: sessionStore,
                referenceDate: now,
                calendar: calendar
            )
        } catch {
            infoAlert = PlanningInfoAlert(
                title: L10n.planning.planning.bills,
                message: L10n.planning.planning.couldnTResumeThisBillRightNow + " \(error.localizedDescription)"
            )
        }
    }

    private func openInstallmentAddIfAllowed() {
        let ownerUserID = selectedSubjectUserID
        guard canCreate(ownerUserID: ownerUserID, resourceType: .installment) else {
            presentCreatePermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .installment,
                resourceName: L10n.planning.planning.installmentsLoans
            ) {
                openInstallmentAddIfAllowed()
            }
            return
        }
        installmentEditorTarget = PlanningInstallmentEditorTarget(plan: nil, dueItem: nil, selectedMonth: selectedMonth)
    }

    private func openInstallmentEditorIfAllowed(plan: InstallmentPlan?, dueItem: PlanningRecurringDueSnapshot?) {
        if let plan,
           presentFamilyOwnerConflictIfNeeded(entity: .installmentPlan, recordID: plan.id) {
            return
        }

        let ownerUserID = plan.flatMap { installmentOwnerMap[$0.id] } ?? selectedSubjectUserID
        guard canEdit(ownerUserID: ownerUserID, resourceType: .installment) else {
            presentEditPermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: .installment,
                resourceName: L10n.planning.planning.installmentsLoans
            ) {
                openInstallmentEditorIfAllowed(plan: plan, dueItem: dueItem)
            }
            return
        }
        installmentEditorTarget = PlanningInstallmentEditorTarget(plan: plan, dueItem: dueItem, selectedMonth: selectedMonth)
    }

    private func openDuePaymentIfAllowed(_ item: PlanningRecurringDueSnapshot) {
        if presentFamilyOwnerConflictIfNeeded(entity: .dueOccurrenceRecord, recordID: item.id) {
            return
        }

        if let entity = syncEntity(for: duePermissionResource(for: item).type),
           presentFamilyOwnerConflictIfNeeded(entity: entity, recordID: item.sourceID) {
            return
        }

        let ownerUserID = dueOwnerUserID(for: item)
        let resource = duePermissionResource(for: item)
        guard canEdit(ownerUserID: ownerUserID, resourceType: resource.type, resourceID: resource.resourceID) else {
            presentEditPermissionPrompt(
                ownerUserID: ownerUserID,
                resourceType: resource.type,
                resourceID: resource.resourceID,
                resourceName: resource.name
            ) {
                openDuePaymentIfAllowed(item)
            }
            return
        }
        duePaymentTarget = DuePaymentSheetTarget(
            sourceKind: item.sourceKind,
            sourceID: item.sourceID,
            dueMonthKey: PlanningLogic.monthKey(for: item.paymentStartDate),
            dueDate: item.dueDate,
            requiresAmountInput: item.amountMinor == nil,
            currencyCode: item.currencyCode,
            name: item.name,
            ownerUserID: ownerUserID
        )
    }

    private func dueOwnerUserID(for item: PlanningRecurringDueSnapshot) -> UUID? {
        switch item.sourceKind {
        case .recurringBill:
            return billOwnerMap[item.sourceID] ?? selectedSubjectUserID
        case .installment:
            return installmentOwnerMap[item.sourceID] ?? selectedSubjectUserID
        case .creditCard:
            return walletOwnerMap[item.sourceID] ?? selectedSubjectUserID
        }
    }

    private func duePermissionResource(
        for item: PlanningRecurringDueSnapshot
    ) -> (type: MistiaFamilyNotificationResourceType, resourceID: UUID?, name: String) {
        switch item.sourceKind {
        case .creditCard:
            return (.wallet, item.sourceID, L10n.planning.planning.walletsCards)
        case .recurringBill:
            return (.bill, nil, L10n.planning.planning.bills)
        case .installment:
            return (.installment, nil, L10n.planning.planning.installmentsLoans)
        }
    }

    private func canEdit(ownerUserID: UUID?, resourceType: MistiaFamilyNotificationResourceType, resourceID: UUID? = nil) -> Bool {
        guard let ownerUserID else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: resourceType, resourceID: resourceID)
    }

    private func canCreate(ownerUserID: UUID?, resourceType: MistiaFamilyNotificationResourceType) -> Bool {
        guard let ownerUserID else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canCreate(ownerUserID: ownerUserID, resourceType: resourceType)
    }

    private func canOpenCreditCardEditor(walletID: UUID?, ownerUserID: UUID?) -> Bool {
        guard let ownerUserID else { return false }
        if ownerUserID == sessionStore.activeLocalProfileUserID {
            return true
        }
        guard let walletID else { return false }
        return familyContextStore.canUseWallet(walletID: walletID, ownerUserID: ownerUserID)
            && familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .wallet, resourceID: walletID)
    }

    private func presentFamilyOwnerConflictIfNeeded(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        guard sessionStore.hasFamilyOwnerPushConflict(entity: entity, recordID: recordID) else {
            return false
        }
        familyOwnerConflictAlert = PlanningFamilyOwnerConflictAlert(entity: entity, recordID: recordID)
        return true
    }

    private func syncEntity(for resourceType: MistiaFamilyNotificationResourceType) -> MistiaSyncEntity? {
        switch resourceType {
        case .wallet, .card:
            return .wallet
        case .category:
            return .category
        case .budget:
            return .budgetPlan
        case .goal:
            return .savingsGoal
        case .transaction, .debt, .familyTransfer:
            return .transaction
        case .bill:
            return .recurringBillPlan
        case .installment:
            return .installmentPlan
        case .due:
            return .dueOccurrenceRecord
        case .permission:
            return nil
        }
    }

    private func presentCreditCardWalletPermissionPrompt(
        walletID: UUID,
        walletName: String,
        ownerUserID: UUID
    ) {
        guard ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        walletPermissionPrompt = PlanningWalletPermissionPrompt(
            walletID: walletID,
            walletName: walletName,
            ownerUserID: ownerUserID,
            title: L10n.planning.planning.noWalletAccess,
            message: L10n.planning.planning.youDoNotHaveEnoughAccessFor(String(describing: walletName))
        )
    }

    private func walletPermissionActionTitle(
        for prompt: PlanningWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> String {
        if isWalletPermissionGranted(for: prompt, scope: scope) {
            switch scope {
            case .use:
                return L10n.planning.planning.useRequestApproved
            case .edit:
                return L10n.planning.planning.editRequestApproved
            case .create:
                return L10n.planning.planning.createRequestApproved
            case .view:
                return L10n.planning.planning.requestApproved
            }
        }

        if familyContextStore.hasPendingPermissionRequest(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        ) {
            switch scope {
            case .use:
                return L10n.planning.planning.useRequested
            case .edit:
                return L10n.planning.planning.editRequested
            case .create:
                return L10n.planning.planning.createRequested
            case .view:
                return L10n.planning.planning.accessRequested
            }
        }

        switch scope {
        case .use:
            return L10n.planning.planning.requestUse
        case .edit:
            return L10n.planning.planning.requestEdit
        case .create:
            return L10n.planning.planning.requestCreate
        case .view:
            return L10n.planning.planning.requestAccess
        }
    }

    private func isWalletPermissionGranted(
        for prompt: PlanningWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        familyContextStore.hasPermission(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        )
    }

    private func shouldShowWalletPermissionAction(
        for prompt: PlanningWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        !isWalletPermissionGranted(for: prompt, scope: scope)
    }

    private func requestWalletPermission(
        _ prompt: PlanningWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) {
        guard !isWalletPermissionGranted(for: prompt, scope: scope) else {
            performApprovedWalletPermissionAction(prompt, scope: scope)
            return
        }

        guard !familyContextStore.hasPendingPermissionRequest(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        ) else {
            refreshPendingWalletPermission(prompt, scope: scope)
            return
        }

        sendPermissionRequest(
            resourceType: .wallet,
            resourceID: prompt.walletID,
            ownerUserID: prompt.ownerUserID,
            scope: scope,
            resourceName: prompt.walletName
        )
    }

    private func refreshPendingWalletPermission(
        _ prompt: PlanningWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) {
        Task { @MainActor in
            let isApproved = await familyContextStore.refreshPermissionGrant(
                ownerUserID: prompt.ownerUserID,
                resourceType: .wallet,
                resourceID: prompt.walletID,
                scope: scope,
                sessionStore: sessionStore
            )

            if isApproved {
                performApprovedWalletPermissionAction(prompt, scope: scope)
            } else {
                walletPermissionPrompt = nil
                infoAlert = PlanningInfoAlert(
                    title: L10n.planning.planning.requestSent2,
                    message: familyContextStore.lastErrorMessage ?? L10n.planning.planning.theRequestIsWaitingForTheData
                )
            }
        }
    }

    private func performApprovedWalletPermissionAction(
        _ prompt: PlanningWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) {
        walletPermissionPrompt = nil

        switch scope {
        case .use:
            uiState.requestQuickCreateMenuPresentation()
        case .edit:
            guard let wallet = storedWallets.first(where: { $0.id == prompt.walletID }) else { return }
            creditCardEditorTarget = PlanningCreditCardEditorTarget(
                wallet: wallet,
                dueItem: nil,
                selectedMonth: selectedMonth
            )
        case .create, .view:
            break
        }
    }

    private func presentEditPermissionPrompt(
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID? = nil,
        resourceName: String,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID,
              ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: resourceID,
            scope: .edit
        )
        permissionPrompt = PlanningPermissionPrompt(
            title: L10n.planning.planning.noEditAccess,
            message: L10n.planning.planning.youDoNotHavePermissionToEdit(String(describing: resourceName)),
            actionTitle: isPending
                ? L10n.planning.planning.editRequestSent
                : L10n.planning.planning.requestEditAccess
        ) {
            resolvePermissionPromptAction(
                resourceType: resourceType,
                resourceID: resourceID,
                ownerUserID: ownerUserID,
                scope: .edit,
                resourceName: resourceName,
                wasPending: isPending,
                onGranted: onGranted
            )
        }
    }

    private func presentCreatePermissionPrompt(
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceName: String,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID,
              ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: nil,
            scope: .create
        )
        permissionPrompt = PlanningPermissionPrompt(
            title: L10n.planning.planning.noCreateAccess,
            message: L10n.planning.planning.youDoNotHavePermissionToCreate(String(describing: resourceName)),
            actionTitle: isPending
                ? L10n.planning.planning.createRequestSent
                : L10n.planning.planning.requestCreateAccess
        ) {
            resolvePermissionPromptAction(
                resourceType: resourceType,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .create,
                resourceName: resourceName,
                wasPending: isPending,
                onGranted: onGranted
            )
        }
    }

    private func resolvePermissionPromptAction(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        ownerUserID: UUID,
        scope: MistiaFamilyPermissionScope,
        resourceName: String,
        wasPending: Bool,
        onGranted: @escaping () -> Void
    ) {
        Task { @MainActor in
            if wasPending {
                let isApproved = await familyContextStore.refreshPermissionGrant(
                    ownerUserID: ownerUserID,
                    resourceType: resourceType,
                    resourceID: resourceID,
                    scope: scope,
                    sessionStore: sessionStore
                )

                if isApproved {
                    permissionPrompt = nil
                    onGranted()
                    return
                }

                permissionPrompt = nil
                infoAlert = PlanningInfoAlert(
                    title: L10n.planning.planning.requestSent2,
                    message: familyContextStore.lastErrorMessage ?? L10n.planning.planning.theRequestIsWaitingForTheData
                )
                return
            }

            let didSend = await familyContextStore.requestPermission(
                resourceType: resourceType,
                resourceID: resourceID,
                ownerUserID: ownerUserID,
                scope: scope,
                resourceName: resourceName,
                sessionStore: sessionStore
            )

            permissionPrompt = nil
            infoAlert = PlanningInfoAlert(
                title: didSend
                    ? L10n.planning.planning.requestSent
                    : L10n.planning.planning.couldnTSend,
                message: didSend
                    ? L10n.planning.planning.thePermissionRequestWasSentToThe
                    : (familyContextStore.lastErrorMessage ?? L10n.planning.planning.couldnTSendTheRequestRightNow)
            )
        }
    }

    private func sendPermissionRequest(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        ownerUserID: UUID,
        scope: MistiaFamilyPermissionScope,
        resourceName: String
    ) {
        Task { @MainActor in
            let didSend = await familyContextStore.requestPermission(
                resourceType: resourceType,
                resourceID: resourceID,
                ownerUserID: ownerUserID,
                scope: scope,
                resourceName: resourceName,
                sessionStore: sessionStore
            )

            walletPermissionPrompt = nil
            permissionPrompt = nil
            infoAlert = PlanningInfoAlert(
                title: didSend
                    ? L10n.planning.planning.requestSent
                    : L10n.planning.planning.couldnTSend,
                message: didSend
                    ? L10n.planning.planning.thePermissionRequestWasSentToThe
                    : (familyContextStore.lastErrorMessage ?? L10n.planning.planning.couldnTSendTheRequestRightNow)
            )
        }
    }
}

private struct BudgetTabContent: View {
    let summary: PlanningBudgetSummarySnapshot
    let currencyCode: String
    let rows: [PlanningBudgetBranchRowSnapshot]
    let referenceDate: Date
    let onAdd: () -> Void
    let onEditPrimary: (PlanningBudgetBranchRowSnapshot) -> Void
    let onEditChild: (PlanningBudgetRowSnapshot) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PlanningBudgetSummaryCard(summary: summary, currencyCode: currencyCode)

            if rows.isEmpty {
                PlanningEmptyStateCard(
                    title: L10n.planning.planning.noBudgetsYet,
                    message: L10n.planning.planning.createCategoryBudgetsToTrackWhatYou,
                    buttonTitle: L10n.planning.planning.addBudget,
                    accent: MistiaAccent.purple.color,
                    symbols: ["banknote.fill", "chart.bar.fill", "bolt.fill", "plus"]
                ) {
                    onAdd()
                }
            } else {
                PlanningListCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        PlanningBudgetBranchCard(
                            row: row,
                            referenceDate: referenceDate,
                            onEditPrimary: { onEditPrimary(row) },
                            onEditChild: onEditChild
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }

                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 0)

                    PlanningFooterAddButton(title: L10n.planning.planning.addBudget) {
                        onAdd()
                    }
                }
            }
        }
    }
}

private struct GoalsTabContent: View {
    let summary: PlanningGoalSummarySnapshot
    let currencyCode: String
    let rows: [PlanningGoalRowSnapshot]
    let onAdd: () -> Void
    let onEdit: (PlanningGoalRowSnapshot) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PlanningGoalSummaryCard(summary: summary, currencyCode: currencyCode)

            if rows.isEmpty {
                PlanningEmptyStateCard(
                    title: L10n.planning.planning.noGoalsYet,
                    message: L10n.planning.planning.addAnEmergencyFundTripOrBig,
                    buttonTitle: L10n.planning.planning.addGoal,
                    accent: MistiaAccent.purple.color,
                    symbols: ["target", "sparkles", "flag.fill", "plus"]
                ) {
                    onAdd()
                }
            } else {
                PlanningListCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onEdit(row)
                        } label: {
                            PlanningGoalRowView(row: row)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }

                    Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)

                    PlanningFooterAddButton(title: L10n.planning.planning.addGoal) {
                        onAdd()
                    }
                }
            }
        }
    }
}

private struct DueTabContent: View {
    @Binding var selectedMode: PlanningDueMode

    let summary: PlanningDueSummarySnapshot
    let currencyCode: String
    let creditCards: [PlanningCreditCardAccountSnapshot]
    let bills: [PlanningRecurringDueSnapshot]
    let pausedBills: [PlanningBillSnapshot]
    let installments: [PlanningRecurringDueSnapshot]
    let referenceDate: Date
    let onAddCreditCard: () -> Void
    let onEditCreditCard: (PlanningCreditCardAccountSnapshot) -> Void
    let onAddBill: () -> Void
    let onEditBill: (PlanningRecurringDueSnapshot) -> Void
    let onEditPausedBill: (PlanningBillSnapshot) -> Void
    let onResumePausedBill: (PlanningBillSnapshot) -> Void
    let onAddInstallment: () -> Void
    let onEditInstallment: (PlanningRecurringDueSnapshot) -> Void
    let onPayBill: (PlanningRecurringDueSnapshot) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PlanningDueSummaryCard(
                summary: summary,
                currencyCode: currencyCode,
                totalTitle: L10n.planning.planning.totalDue
            )
            PlanningDueModePicker(selection: $selectedMode)

            switch selectedMode {
            case .bills:
                VStack(spacing: 12) {
                    DueRowsSection(
                        emptyTitle: L10n.planning.planning.noBillsYet,
                        emptyMessage: L10n.planning.planning.addInternetUtilitiesOrRecurringBillsTo,
                        emptySymbols: ["wifi", "bolt.fill", "phone.fill", "plus"],
                        accent: MistiaAccent.purple.color,
                        items: bills,
                        addTitle: L10n.planning.planning.addBill,
                        referenceDate: referenceDate,
                        onAdd: onAddBill,
                        onEdit: onEditBill,
                        onPay: onPayBill
                    )

                    if !pausedBills.isEmpty {
                        PausedBillsSection(
                            items: pausedBills,
                            onEdit: onEditPausedBill,
                            onResume: onResumePausedBill
                        )
                    }
                }
            case .creditCards:
                CreditCardsSection(
                    items: creditCards,
                    referenceDate: referenceDate,
                    onAdd: onAddCreditCard,
                    onEdit: onEditCreditCard
                )
            case .installments:
                DueRowsSection(
                    emptyTitle: L10n.planning.planning.noInstallmentsOrLoansYet,
                    emptyMessage: L10n.planning.planning.addInstallmentOrLoanPaymentsAndCreate,
                    emptySymbols: ["creditcard.and.123", "building.columns.fill", "banknote.fill", "plus"],
                    accent: MistiaAccent.purple.color,
                    items: installments,
                    addTitle: L10n.planning.planning.addInstallmentLoan,
                    referenceDate: referenceDate,
                    onAdd: onAddInstallment,
                    onEdit: onEditInstallment
                )
            }
        }
    }
}

private struct CreditCardsSection: View {
    let items: [PlanningCreditCardAccountSnapshot]
    let referenceDate: Date
    let onAdd: () -> Void
    let onEdit: (PlanningCreditCardAccountSnapshot) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10)]

    var body: some View {
        if items.isEmpty {
            PlanningEmptyStateCard(
                title: L10n.planning.planning.noCreditCardsYet,
                message: L10n.planning.planning.linkOrAddCardsHereToShow,
                buttonTitle: L10n.planning.planning.addCreditCard,
                accent: MistiaAccent.purple.color,
                symbols: ["creditcard.fill", "wave.3.right.circle.fill", "building.columns.fill", "plus"]
            ) {
                onAdd()
            }
        } else {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        PlanningCreditCardCard(
                            item: item,
                            onOpenStatement: {
                                NotificationCenter.default.post(name: NSNotification.Name("MistiaOpenCreditCardStatementFromPlanning"), object: item.walletID)
                            }
                        )
                        .onTapGesture {
                            onEdit(item)
                        }
                    }
                }

                PlanningFooterAddButton(title: L10n.planning.planning.addCreditCard) {
                    onAdd()
                }
            }
        }
    }
}

private struct DueRowsSection: View {
    let emptyTitle: String
    let emptyMessage: String
    let emptySymbols: [String]
    let accent: Color
    let items: [PlanningRecurringDueSnapshot]
    let addTitle: String
    let referenceDate: Date
    let onAdd: () -> Void
    let onEdit: (PlanningRecurringDueSnapshot) -> Void
    var onPay: ((PlanningRecurringDueSnapshot) -> Void)? = nil

    var body: some View {
        if items.isEmpty {
            PlanningEmptyStateCard(
                title: emptyTitle,
                message: emptyMessage,
                buttonTitle: addTitle,
                accent: accent,
                symbols: emptySymbols
            ) {
                onAdd()
            }
        } else {
            PlanningListCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PlanningDueRow(
                        item: item,
                        referenceDate: referenceDate,
                        onTap: { onEdit(item) },
                        onPay: {
                            onPay?(item)
                        }
                    )
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)

                    if index < items.count - 1 {
                        Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                    }
                }

                Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)

                PlanningFooterAddButton(title: addTitle) {
                    onAdd()
                }
            }
        }
    }
}

private struct PausedBillsSection: View {
    let items: [PlanningBillSnapshot]
    let onEdit: (PlanningBillSnapshot) -> Void
    let onResume: (PlanningBillSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.planning.planning.pausedBills)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            PlanningListCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PlanningPausedBillRow(
                        item: item,
                        onTap: { onEdit(item) },
                        onResume: { onResume(item) }
                    )
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                            .padding(.trailing, 0)
                    }
                }
            }
        }
    }
}

private struct PlanningPausedBillRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: PlanningBillSnapshot
    let onTap: () -> Void
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlanningIconTile(icon: item.iconSymbolName, color: MistiaAccent.purple.color.opacity(0.76))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(amountText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            PlanningDueActionButton(title: L10n.planning.planning.resumeBill, accent: resumeActionAccent) {
                onResume()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var amountText: String {
        if let amountMinor = item.amountMinor {
            return amountMinor.formattedCurrency(code: item.currencyCode)
        }
        return L10n.planning.planning.noAmountYet
    }

    private var resumeActionAccent: Color {
        colorScheme == .dark ? MistiaAccent.cyan.color : MistiaAccent.teal.color
    }
}

private struct PlanningModePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Binding var selection: PlanningMode

    private var accent: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlanningMode.allCases) { mode in
                Button {
                    withAnimation(.snappy) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12.5, weight: .bold))
                        Text(mode.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selection == mode ? activeForeground : idleForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selection == mode {
                            Capsule()
                                .fill(Color.clear)
                                .background {
                                    if #available(iOS 26, *) {
                                        Capsule()
                                            .fill(.clear)
                                            .glassEffect(
                                                Glass.regular
                                                    .tint(activeTint)
                                                    .interactive(true),
                                                in: .capsule
                                            )
                                    } else {
                                        Capsule()
                                            .fill(.regularMaterial)
                                    }
                                }
                        } else {
                            Capsule()
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                        }
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.20), lineWidth: 0.8)
                    }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 24, tint: accent))
            }
        }
        .id(locale.identifier)
        .padding(.horizontal, 18)
        .padding(.vertical, 2)
        .padding(.bottom, 10)
        .background(MistiaBackgroundView(tone: .standard).opacity(0.001))
    }

    private var activeForeground: Color {
        .white
    }

    private var idleForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.94, blue: 0.97)
            : Color.black.opacity(0.76)
    }

    private var activeTint: Color {
        colorScheme == .dark
            ? Color(red: 0.34, green: 0.18, blue: 0.60)
            : accent.opacity(0.98)
    }

    private var idleTint: Color {
        colorScheme == .dark
            ? Color(red: 0.24, green: 0.24, blue: 0.27)
            : Color.black.opacity(0.06)
    }
}

private struct PlanningDueModePicker: View {
    @Binding var selection: PlanningDueMode

    var body: some View {
        MistiaNativeSegmentedControl(
            selection: $selection,
            options: PlanningDueMode.allCases,
            title: \.title
        )
    }
}

private struct PlanningBudgetSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PlanningBudgetSummarySnapshot
    let currencyCode: String

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.planning.planning.monthlyBudgetTotal)
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(summary.totalBudgetMinor.formattedCurrency(code: currencyCode))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        PlanningStatusBadge(title: summary.health.title, color: summaryColor)
                    }

                    Spacer(minLength: 12)

                    PlanningSemiGauge(
                        progress: summary.progress,
                        text: summary.progress.percentText,
                        tint: summaryColor
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    PlanningMetricColumn(
                        title: L10n.planning.planning.spent,
                        value: summary.spentMinor.formattedCurrency(code: currencyCode),
                        tint: MistiaAccent.coral.color
                    )

                    PlanningMetricColumn(
                        title: L10n.planning.planning.remaining,
                        value: summary.remainingMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#2DAA9E")
                    )

                    PlanningMetricColumn(
                        title: L10n.planning.planning.projectedEndOfMonth,
                        value: summary.projectedSpentMinor.formattedCurrency(code: currencyCode),
                        tint: summaryColor
                    )

                    PlanningMetricColumn(
                        title: L10n.planning.planning.availablePerDay,
                        value: summary.remainingDailyAllowanceMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#2DAA9E")
                    )
                }
            }
        }
    }

    private var summaryColor: Color {
        switch summary.health {
        case .stable:
            Color(hex: "#2DAA9E")
        case .caution:
            Color(hex: "#F59B3F")
        case .exceeded:
            Color(hex: "#F45C7E")
        }
    }

}

private struct PlanningGoalSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PlanningGoalSummarySnapshot
    let currencyCode: String

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.planning.planning.activeGoals)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(
                    L10n.planning.planning.valueGoals(String(describing: summary.activeCount))
                )
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                HStack(spacing: 14) {
                    PlanningMetricColumn(
                        title: L10n.planning.planning.saved,
                        value: summary.totalSavedMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#2DAA9E")
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: L10n.planning.planning.closestToGoal,
                        value: summary.nearestGoalName ?? L10n.planning.planning.noneYet,
                        tint: Color(hex: "#5B7BFF")
                    )
                }
            }
        }
    }
}

private struct PlanningDueSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PlanningDueSummarySnapshot
    let currencyCode: String
    var totalTitle: String = L10n.planning.planning.totalDue
    var totalValue: String?

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.planning.planning.summary)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    PlanningMetricColumn(
                        title: L10n.planning.planning.upcoming2,
                        value: "\(summary.upcomingCount)",
                        tint: Color(hex: "#5B7BFF")
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: totalTitle,
                        value: totalValue ?? summary.totalDueMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#F59B3F")
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: L10n.planning.planning.overdue,
                        value: "\(summary.overdueCount)",
                        tint: Color(hex: "#F45C7E")
                    )
                }
            }
        }
    }
}

private struct PlanningBudgetBranchCard: View {
    let row: PlanningBudgetBranchRowSnapshot
    let referenceDate: Date
    let onEditPrimary: () -> Void
    let onEditChild: (PlanningBudgetRowSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            primarySection

            if !row.childRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    childHeader
                    childRows
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var primarySection: some View {
        if row.primaryBudgetID != nil {
            Button(action: onEditPrimary) {
                primaryContent
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
        } else {
            primaryContent
        }
    }

    private var primaryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: row.iconSymbolName, color: toneColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(verbatim: "\(row.spentMinor.formattedCurrency(code: row.currencyCode)) / \(row.limitMinor.formattedCurrency(code: row.currencyCode))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text(row.progress.percentText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(toneColor)
            }

            PlanningProgressBar(progress: row.progressClamped, tint: toneColor)

            Text(daysText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var childHeader: some View {
        HStack(spacing: 8) {
            Text(
                L10n.planning.planning.childBudgets
            )
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var childRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(row.childRows.enumerated()), id: \.element.id) { index, childRow in
                Button {
                    onEditChild(childRow)
                } label: {
                    PlanningBudgetRowView(row: childRow, referenceDate: referenceDate)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                if index < row.childRows.count - 1 {
                    Divider()
                        .padding(.leading, 48)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private var toneColor: Color {
        switch row.tone {
        case .calm:
            Color(hex: "#2DAA9E")
        case .warning:
            Color(hex: "#F59B3F")
        case .critical:
            Color(hex: "#F45C7E")
        }
    }

    private var daysText: String {
        if row.isPastMonth {
            return L10n.planning.planning.monthEnded
        }

        return L10n.planning.planning.valueDaysLeft(String(describing: row.daysRemaining))
    }
}

private struct PlanningBudgetRowView: View {
    let row: PlanningBudgetRowSnapshot
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: row.iconSymbolName, color: toneColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(verbatim: "\(row.spentMinor.formattedCurrency(code: row.currencyCode)) / \(row.limitMinor.formattedCurrency(code: row.currencyCode))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text(row.progress.percentText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(toneColor)
            }

            PlanningProgressBar(progress: row.progressClamped, tint: toneColor)

            Text(daysText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var toneColor: Color {
        switch row.tone {
        case .calm:
            Color(hex: "#2DAA9E")
        case .warning:
            Color(hex: "#F59B3F")
        case .critical:
            Color(hex: "#F45C7E")
        }
    }

    private var daysText: String {
        if row.isPastMonth {
            return L10n.planning.planning.monthEnded
        }

        return L10n.planning.planning.valueDaysLeft(String(describing: row.daysRemaining))
    }
}

private struct PlanningGoalRowView: View {
    let row: PlanningGoalRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: row.iconSymbolName, color: Color(hex: "#2DAA9E"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(verbatim: "\(row.currentSavedMinor.formattedCurrency(code: row.currencyCode)) / \(row.targetMinor.formattedCurrency(code: row.currencyCode))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            PlanningProgressBar(progress: row.progressClamped, tint: Color(hex: "#2DAA9E"))

            HStack {
                Text(row.targetDate.shortDisplayText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    L10n.planning.planning.needValueMonth(String(describing: row.monthlyRequiredMinor.formattedCurrency(code: row.currencyCode)))
                )
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#5B7BFF"))
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct PlanningDueRow: View {
    let item: PlanningRecurringDueSnapshot
    let referenceDate: Date
    let onTap: () -> Void
    let onPay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: item.iconSymbolName, color: tone.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(amountText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                if showsPayButton {
                    PlanningDueActionButton(title: L10n.planning.planning.pay) {
                        onPay()
                    }
                } else {
                    PlanningStatusBadge(title: statusText, color: tone.color)
                }
            }

            HStack {
                Text(dateWindowText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(dueDetailText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(tone.color)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var tone: PlanningDueRowTone {
        item.tone(referenceDate: referenceDate)
    }

    private var amountText: String {
        if let amount = item.amountMinor {
            return amount.formattedCurrency(code: item.currencyCode)
        }
        return L10n.planning.planning.noAmountYet
    }

    private var statusText: String {
        switch item.status {
        case .paid:
            L10n.planning.planning.paid
        case .pending:
            switch item.sourceKind {
            case .recurringBill:
                L10n.planning.planning.upcoming
            case .installment:
                L10n.planning.planning.installmentLoan2
            case .creditCard:
                L10n.planning.planning.due2
            }
        }
    }

    private var showsPayButton: Bool {
        item.sourceKind == .recurringBill && item.status != .paid
    }

    private var dueDetailText: String {
        if item.status == .paid {
            return L10n.planning.planning.completed
        }

        let comparisonDate = currentComparisonDate
        let dayDelta = MistiaCalendar.current.dateComponents(
            [.day],
            from: MistiaCalendar.current.startOfDay(for: referenceDate),
            to: MistiaCalendar.current.startOfDay(for: comparisonDate)
        ).day ?? 0

        if dayDelta < 0 {
            return L10n.planning.planning.overdueByValueDays(String(describing: -dayDelta))
        }
        if dayDelta == 0 {
            return L10n.planning.planning.dueToday
        }
        return L10n.planning.planning.valueDaysLeft(String(describing: dayDelta))
    }

    private var dateWindowText: String {
        if item.hasExplicitDueDate {
            return "\(item.paymentStartDate.shortDisplayText) - \(item.dueDate.shortDisplayText)"
        }
        return item.paymentStartDate.shortDisplayText
    }

    private var currentComparisonDate: Date {
        let today = MistiaCalendar.current.startOfDay(for: referenceDate)
        let paymentStart = MistiaCalendar.current.startOfDay(for: item.paymentStartDate)
        if today < paymentStart {
            return item.paymentStartDate
        }
        return item.dueDate
    }
}

private struct PlanningDueActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var accent: Color?
    let action: () -> Void

    private var resolvedAccent: Color {
        if let accent {
            return accent
        }
        return colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    label
                        .foregroundStyle(resolvedAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(resolvedAccent)
            } else {
                Button(action: action) {
                    label
                        .foregroundStyle(resolvedAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            MistiaCapsuleGlassBackground(
                                tint: resolvedAccent.opacity(colorScheme == .dark ? 0.18 : 0.12),
                                interactive: true
                            )
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(resolvedAccent.opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
    }
}

private struct PlanningCreditCardCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: PlanningCreditCardAccountSnapshot
    let onOpenStatement: () -> Void

    private var presentation: CreditCardNetworkPresentation {
        CreditCardNetworkPresentation(network: item.network)
    }

    var body: some View {
        ZStack(alignment: .top) {
            cardBackground

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.walletName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(issuerSubtitle.uppercased())
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 7) {
                        CreditCardNetworkLogoMark(network: item.network)
                            .frame(width: 66, height: 38)

                        Text(maskedLast4)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    amountBlock(
                        title: L10n.planning.planning.availableCredit,
                        value: item.availableCreditMinor.formattedCurrency(code: item.currencyCode),
                        isPrimary: true
                    )

                    amountBlock(
                        title: L10n.planning.planning.currentDebt,
                        value: item.currentDebtMinor.formattedCurrency(code: item.currencyCode),
                        isPrimary: false
                    )
                }

                HStack(spacing: 7) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))

                    Text(paymentSourceText)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(colorScheme == .dark ? 0.13 : 0.16), in: Capsule())

                HStack(alignment: .center, spacing: 8) {
                    statementMiniLabel(title: L10n.planning.planning.close, value: "\(item.statementClosingDay)")
                    statementMiniLabel(title: L10n.planning.planning.due, value: "\(item.dueDay)")

                    Spacer(minLength: 8)

                    Button(action: onOpenStatement) {
                        Label(L10n.planning.planning.statement, systemImage: "doc.text.fill")
                            .font(.system(size: 11.5, weight: .black, design: .rounded))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.18), in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                }
        }
    }

    private var maskedLast4: String {
        "•••• \(item.last4)"
    }

    private var issuerSubtitle: String {
        let trimmed = item.issuerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? item.network.title : trimmed
    }

    private var paymentSourceText: String {
        if let name = item.paymentSourceWalletName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return L10n.planning.planning.linkedWalletValue(name)
        }
        return L10n.planning.planning.noLinkedWallet
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: presentation.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.08 : 0.14))
                    .frame(width: 150, height: 150)
                    .blur(radius: 28)
                    .offset(x: -48, y: 50)
            }
    }

    private func amountBlock(title: String, value: String, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(isPrimary ? 0.70 : 0.62))
                .lineLimit(1)

            Text(value)
                .font(.system(size: isPrimary ? 24 : 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(isPrimary ? 0.62 : 0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isPrimary ? 0 : 10)
        .padding(.vertical, isPrimary ? 0 : 8)
        .background {
            if !isPrimary {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(colorScheme == .dark ? 0.11 : 0.15))
            }
        }
    }

    private func statementMiniLabel(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
            Text(value)
                .font(.system(size: 13.5, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(0.14), in: Capsule())
    }
}

private struct CreditCardNetworkPresentation {
    let gradientColors: [Color]
    let accent: Color

    init(network: CreditCardNetwork) {
        switch network {
        case .visa:
            gradientColors = [Color(hex: "#1A5BD7"), Color(hex: "#1744A7"), Color(hex: "#0C255F")]
            accent = Color(hex: "#F4C542")
        case .mastercard:
            gradientColors = [Color(hex: "#D43C2F"), Color(hex: "#F2932E"), Color(hex: "#682A79")]
            accent = Color(hex: "#FFB347")
        case .jcb:
            gradientColors = [Color(hex: "#1B78B5"), Color(hex: "#17985F"), Color(hex: "#D43C4A")]
            accent = Color(hex: "#FFFFFF")
        case .americanExpress:
            gradientColors = [Color(hex: "#2FB7C7"), Color(hex: "#1B77B6"), Color(hex: "#164B83")]
            accent = Color(hex: "#D9F6FF")
        case .unionPay:
            gradientColors = [Color(hex: "#C92237"), Color(hex: "#1968B3"), Color(hex: "#0C8A5A")]
            accent = Color(hex: "#FFFFFF")
        case .other:
            gradientColors = [Color(hex: "#556270"), Color(hex: "#4E7A87"), Color(hex: "#2A3A46")]
            accent = MistiaAccent.lightPurple.color
        }
    }
}

private struct CreditCardNetworkLogoMark: View {
    let network: CreditCardNetwork

    var body: some View {
        ZStack {
            switch network {
            case .visa:
                Text(verbatim: "VISA")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(Color(hex: "#243D92"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            case .mastercard:
                ZStack {
                    Circle()
                        .fill(Color(hex: "#EB001B"))
                        .frame(width: 30, height: 30)
                        .offset(x: -9)
                    Circle()
                        .fill(Color(hex: "#F79E1B"))
                        .frame(width: 30, height: 30)
                        .offset(x: 9)
                    Text(verbatim: "MC")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            case .jcb:
                HStack(spacing: 2) {
                    logoStripe("J", color: Color(hex: "#1B78B5"))
                    logoStripe("C", color: Color(hex: "#1E9C5F"))
                    logoStripe("B", color: Color(hex: "#D13C4A"))
                }
            case .americanExpress:
                VStack(spacing: -1) {
                    Text(verbatim: "AMEX")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Text(verbatim: "CARD")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: 54, height: 34)
                .background(Color(hex: "#2178B8"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                }
            case .unionPay:
                HStack(spacing: -4) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "#D61F35"))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "#1B68B3"))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "#0E8A56"))
                }
                .frame(width: 52, height: 31)
                .overlay {
                    Text(verbatim: "UP")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            case .other:
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 34)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func logoStripe(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct PlanningListCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(
            cornerRadius: 22,
            tint: cardTint,
            padding: 0
        ) {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct PlanningFooterAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        MistiaFooterAddButton(title: title, accent: MistiaAccent.purple.color, action: action)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }
}

private struct PlanningEmptyStateCard: View {
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

private struct PlanningProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                let clamped = min(max(progress, 0), 1)

                Capsule()
                    .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))

                Capsule()
                    .fill(tint.opacity(colorScheme == .dark ? 0.94 : 0.82))
                    .frame(width: max(proxy.size.width * clamped, progress > 0 ? 18 : 0))
            }
        }
        .frame(height: 10)
    }
}

private struct PlanningSemiGauge: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let text: String
    let tint: Color

    private let lineWidth: CGFloat = 13

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                PlanningSemiGaugeArc(progress: 1)
                    .stroke(
                        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                PlanningSemiGaugeArc(progress: min(max(progress, 0), 1))
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .shadow(color: progress >= 1 ? gaugeColor.opacity(0.24) : .clear, radius: 4, y: 2)

                VStack(spacing: 2) {
                    Text(text)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(gaugeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if progress > 1 {
                        Text(L10n.planning.planning.over)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(gaugeColor)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(width: 126, height: 72)

            if progress > 1 {
                Text(verbatim: "+\(Int(((progress - 1) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(gaugeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(gaugeColor.opacity(0.12), in: Capsule())
            }
        }
    }

    private var gaugeColor: Color {
        progress >= 1 ? Color(hex: "#F45C7E") : tint
    }
}

private struct PlanningSemiGaugeArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(progress, 0), 1)
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * clamped),
            clockwise: false
        )
        return path
    }
}

private struct PlanningMetricColumn: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanningStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct PlanningIconTile: View {
    let icon: String
    let color: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: color, size: 32)
    }
}

private extension Date {
    func monthDisplayText(calendar: Calendar) -> String {
        MistiaDateFormatting.monthYearString(for: self, calendar: calendar)
    }

    var shortDisplayText: String {
        MistiaDateFormatting.shortDateString(for: self)
    }
}

private extension Double {
    var percentText: String {
        "\(Int((self * 100).rounded()))%"
    }
}
