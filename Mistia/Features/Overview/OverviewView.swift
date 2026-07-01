import Charts
import SwiftData
import SwiftUI

private enum OverviewNavigationDestination: String, Identifiable {
    case profile

    var id: String { rawValue }
}

private struct OverviewExpenseDaySelection: Identifiable, Equatable {
    let date: Date

    var id: Date { date }
}

private enum OverviewHeroChartMode: String, CaseIterable, Identifiable {
    case day
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            L10n.overview.overview.day
        case .category:
            L10n.overview.overview.category
        }
    }
}

private struct OverviewPermissionPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
}

private struct OverviewInfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum OverviewAlertPresentation: Identifiable {
    case info(OverviewInfoAlert)
    case permission(OverviewPermissionPrompt)

    var id: UUID {
        switch self {
        case .info(let alert):
            alert.id
        case .permission(let prompt):
            prompt.id
        }
    }

    var title: String {
        switch self {
        case .info(let alert):
            alert.title
        case .permission(let prompt):
            prompt.title
        }
    }

    var message: String {
        switch self {
        case .info(let alert):
            alert.message
        case .permission(let prompt):
            prompt.message
        }
    }
}

struct OverviewActionContext {
    let archivedSettlementGroupIDs: Set<UUID>
    let transactionOwnerMap: [UUID: UUID]

    func isSettlementGroupArchived(_ groupID: UUID) -> Bool {
        archivedSettlementGroupIDs.contains(groupID)
    }

    func ownerUserID(
        forTransactionID transactionID: UUID,
        selectedSubjectUserID: UUID?,
        activeLocalProfileUserID: UUID?
    ) -> UUID? {
        transactionOwnerMap[transactionID]
            ?? selectedSubjectUserID
            ?? activeLocalProfileUserID
    }
}

private struct OverviewRenderSnapshot {
    let dashboard: OverviewDashboardSnapshot
    let transactionsByID: [UUID: LedgerTransaction]
    let postedExpenseTransactionsByDay: [Date: [LedgerTransaction]]
    let preparingSettlementEvents: [PreparingSettlementEventSnapshot]
    let actionContext: OverviewActionContext
}

private struct OverviewRenderSnapshotCache {
    let key: OverviewRenderSnapshotCacheKey
    let snapshot: OverviewRenderSnapshot
}

struct OverviewRenderSnapshotCacheKey: Hashable {
    let activeScope: FamilyContext.Scope
    let selectedSubjectUserID: UUID?
    let currentUserID: UUID?
    let activeLocalProfileUserID: UUID?
    let signedInUserID: UUID?
    let familyID: UUID?
    let currentMonthStart: TimeInterval
    let calendarIdentifier: String
    let calendarTimeZoneIdentifier: String
    let localeIdentifier: String
    let currencyCode: String
    let currencyRateMode: String
    let manualJPYToVNDRate: String
    let cachedRatesSignature: Int
    let familyAccessSignature: Int
    let walletSignature: MistiaCollectionChangeSignature
    let transactionSignature: MistiaCollectionChangeSignature
    let budgetSignature: MistiaCollectionChangeSignature
    let categorySignature: MistiaCollectionChangeSignature
    let billSignature: MistiaCollectionChangeSignature
    let installmentSignature: MistiaCollectionChangeSignature
    let occurrenceSignature: MistiaCollectionChangeSignature
    let settlementGroupSignature: MistiaCollectionChangeSignature
    let settlementParticipantSignature: MistiaCollectionChangeSignature
    let ownershipSignature: MistiaCollectionChangeSignature
}

struct OverviewView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var currencyRateMode = MistiaCurrencyRateMode.automatic.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = ""
    @AppStorage(MistiaCurrencySettings.StorageKey.cachedRatesData) private var cachedCurrencyRatesData = Data()

    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgets: [BudgetPlan]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var storedBills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var storedInstallments: [InstallmentPlan]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var storedTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<SettlementGroup> { $0.deletedAt == nil }, sort: \SettlementGroup.occurredAt, order: .reverse)
    private var storedSettlementGroups: [SettlementGroup]
    @Query(filter: #Predicate<SettlementParticipant> { $0.deletedAt == nil }, sort: \SettlementParticipant.sortOrder)
    private var storedSettlementParticipants: [SettlementParticipant]
    @Query private var ownershipScopes: [OwnedRecordScope]

    private struct StatementTarget: Identifiable, Hashable {
        let wallet: LedgerWallet
        let month: Date?
        var id: String { "\(wallet.id.uuidString)-\(month?.timeIntervalSince1970 ?? 0)" }
    }

    @State private var editorTarget: TransactionEditorTarget?
    @State private var selectedExpenseDay: OverviewExpenseDaySelection?
    @State private var destination: OverviewNavigationDestination?
    @State private var statementTarget: StatementTarget?
    @State private var duePaymentTarget: DuePaymentSheetTarget?
    @State private var settlementEditorTarget: SettlementEditorTarget?
    @State private var preparingSettlementTarget: PreparingSettlementEventSheetTarget?
    @State private var permissionPrompt: OverviewPermissionPrompt?
    @State private var infoAlert: OverviewInfoAlert?
    @State private var memberViewingExitPrompt: FamilyMemberViewingExitPrompt?
    @State private var renderSnapshotCache: OverviewRenderSnapshotCache?

    private var currentMonth: Date {
        PlanningLogic.startOfMonth(for: .now, calendar: calendar)
    }

    private var appExchangeRates: [MistiaExchangeRate] {
        MistiaCurrencySettings.rates()
    }

    private var renderSnapshot: OverviewRenderSnapshot {
        let scopeSnapshot = FamilyScopedData.ScopeSnapshot(
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore,
            entities: [
                .wallet,
                .transaction,
                .settlementGroup,
                .budgetPlan,
                .installmentPlan,
                .recurringBillPlan,
                .dueOccurrenceRecord,
                .settlementParticipant
            ]
        )
        let transactionOwnerMap = scopeSnapshot.ownerMap(for: .transaction)
        let visibleSettlementGroups = FamilyScopedData.visible(
            storedSettlementGroups,
            entity: .settlementGroup,
            scopeSnapshot: scopeSnapshot
        )
        let archivedEventIDs = SettlementLogic.archivedSharedExpenseEventIDs(
            from: visibleSettlementGroups.map(\.recordSnapshot)
        )
        let visibleTransactions = FamilyScopedData.visibleTransactionsForFinancial(
            storedTransactions,
            scopeSnapshot: scopeSnapshot,
            archivedEventIDs: archivedEventIDs
        )
        let familyArchivedEventIDs = FamilyScopedData.archivedSharedExpenseEventIDsForCurrentFamily(
            from: storedSettlementGroups,
            scopeSnapshot: scopeSnapshot,
            familyMemberUserIDs: currentFamilyMemberUserIDs,
            signedInUserID: sessionStore.activeLocalProfileUserID
        )
        let familyTransactions = FamilyScopedData.familyBudgetTransactionSnapshots(
            from: storedTransactions,
            scopeSnapshot: scopeSnapshot,
            familyMemberUserIDs: currentFamilyMemberUserIDs,
            signedInUserID: sessionStore.activeLocalProfileUserID,
            archivedEventIDs: familyArchivedEventIDs
        )
        let usesAggregateFamilyBudgetSpending = FamilyScopedData.usesAggregateFamilyBudgetSpending(
            isFamilyBudgetSpendingAvailable: isFamilyBudgetSpendingAvailable,
            familyContextStore: familyContextStore
        )
        let visibleWallets = FamilyScopedData.visible(
            storedWallets,
            entity: .wallet,
            scopeSnapshot: scopeSnapshot
        )
        let visibleBudgets = FamilyScopedData.visible(
            storedBudgets,
            entity: .budgetPlan,
            scopeSnapshot: scopeSnapshot
        )
        let visibleInstallments = FamilyScopedData.visible(
            storedInstallments,
            entity: .installmentPlan,
            scopeSnapshot: scopeSnapshot
        )
        let visibleBills = FamilyScopedData.visible(
            storedBills,
            entity: .recurringBillPlan,
            scopeSnapshot: scopeSnapshot
        )
        let visibleOccurrences = FamilyScopedData.visible(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
            scopeSnapshot: scopeSnapshot
        )
        let visibleSettlementParticipants = FamilyScopedData.visible(
            storedSettlementParticipants,
            entity: .settlementParticipant,
            scopeSnapshot: scopeSnapshot
        )

        let transactionRecords = visibleTransactions.map(\.planningRecordSnapshot)
        let overviewTransactions = visibleTransactions.map(\.overviewSnapshot)
        let transactionSnapshots = visibleTransactions.map(\.snapshot)
        let occurrenceSnapshots = visibleOccurrences.map(\.planningSnapshot)
        let walletSnapshots = visibleWallets.compactMap(\.overviewWalletSnapshot)
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: walletSnapshots.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionRecords
        )
        let creditCardAccounts = visibleWallets.compactMap {
            $0.planningCreditCardSnapshot(records: transactionRecords, occurrences: occurrenceSnapshots)
        }
        let month = currentMonth
        let activeBudgets = PlanningLogic.resolvingFamilySpendingCategoryScopes(
            plans: visibleBudgets
                .filter {
                    !$0.isArchived
                        && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == month
                }
                .map { $0.planningSnapshot(calendar: calendar) },
            categoryScopes: familyBudgetSpendingCategoryScopes
        )
        let billSnapshots = visibleBills
            .filter { !$0.isArchived }
            .map(\.planningSnapshot)
        let creditCardDueItems = PlanningLogic.creditCardDueItems(
            accounts: creditCardAccounts,
            records: transactionRecords,
            occurrences: occurrenceSnapshots,
            selectedMonth: month,
            referenceDate: .now,
            calendar: calendar
        )
        let recurringDueItems = recurringBillDueItems(
            around: month,
            billSnapshots: billSnapshots,
            occurrenceSnapshots: occurrenceSnapshots
        )
        let installmentDueItems = PlanningLogic.installmentDueItems(
            plans: visibleInstallments
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: month,
            calendar: calendar
        )
        let dashboard = OverviewLogic.dashboard(
            wallets: walletSnapshots,
            transactionRecords: transactionRecords,
            transactions: overviewTransactions,
            budgets: activeBudgets,
            creditCardDues: creditCardDueItems,
            recurringDues: recurringDueItems + installmentDueItems,
            currencyCode: currencyCode,
            balanceIndex: balanceIndex,
            exchangeRates: appExchangeRates,
            familyTransactions: usesAggregateFamilyBudgetSpending ? familyTransactions : [],
            familySpendingAvailable: usesAggregateFamilyBudgetSpending,
            referenceDate: .now,
            calendar: calendar
        )
        let transactionsByID = Dictionary(
            visibleTransactions.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        )
        let expenseTransactionsByDay = Dictionary(
            grouping: visibleTransactions.filter { transaction in
                transaction.entryStatus == .posted
                    && TransactionLogic.isExpenseSpending(transaction.planningRecordSnapshot)
            },
            by: { calendar.startOfDay(for: $0.occurredAt) }
        )
        .mapValues { transactions in
            transactions.sorted(by: sortTransactionsByRecency)
        }
        let preparingSettlementEvents = SettlementLogic.preparingEventSnapshots(
            groups: visibleSettlementGroups.map(\.recordSnapshot),
            participants: visibleSettlementParticipants.map(\.recordSnapshot),
            records: transactionSnapshots
        )

        return OverviewRenderSnapshot(
            dashboard: dashboard,
            transactionsByID: transactionsByID,
            postedExpenseTransactionsByDay: expenseTransactionsByDay,
            preparingSettlementEvents: preparingSettlementEvents,
            actionContext: OverviewActionContext(
                archivedSettlementGroupIDs: archivedEventIDs,
                transactionOwnerMap: transactionOwnerMap
            )
        )
    }

    private func cachedRenderSnapshot(for key: OverviewRenderSnapshotCacheKey) -> OverviewRenderSnapshot {
        if let renderSnapshotCache, renderSnapshotCache.key == key {
            return renderSnapshotCache.snapshot
        }

        return renderSnapshot
    }

    private func refreshRenderSnapshotCache(
        for key: OverviewRenderSnapshotCacheKey,
        snapshot: OverviewRenderSnapshot
    ) {
        renderSnapshotCache = OverviewRenderSnapshotCache(
            key: key,
            snapshot: snapshot
        )
    }

    private var renderSnapshotCacheKey: OverviewRenderSnapshotCacheKey {
        OverviewRenderSnapshotCacheKey(
            activeScope: familyContextStore.activeContext.scope,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.signedInUserID,
            familyID: familyContextStore.family?.id,
            currentMonthStart: currentMonth.timeIntervalSince1970,
            calendarIdentifier: String(describing: calendar.identifier),
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: locale.identifier,
            currencyCode: currencyCode,
            currencyRateMode: currencyRateMode,
            manualJPYToVNDRate: manualJPYToVNDRate,
            cachedRatesSignature: cachedCurrencyRatesData.hashValue,
            familyAccessSignature: familyAccessSignature,
            walletSignature: MistiaCollectionChangeSignature.make(
                storedWallets,
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
            ),
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
            ),
            occurrenceSignature: MistiaCollectionChangeSignature.make(
                storedOccurrences,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
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

    private var activeAlert: OverviewAlertPresentation? {
        if let permissionPrompt {
            return .permission(permissionPrompt)
        }
        if let infoAlert {
            return .info(infoAlert)
        }
        return nil
    }

    private func recurringBillDueItems(
        around month: Date,
        billSnapshots: [PlanningBillSnapshot],
        occurrenceSnapshots: [PlanningDueOccurrenceSnapshot]
    ) -> [PlanningRecurringDueSnapshot] {
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: month) ?? month
        return [previousMonth, month]
            .flatMap { selectedMonth in
                PlanningLogic.recurringBillDueItems(
                    bills: billSnapshots,
                    occurrences: occurrenceSnapshots,
                    selectedMonth: selectedMonth,
                    calendar: calendar
                )
            }
    }

    private var familyBudgetSpendingCategoryScopes: [PlanningFamilyBudgetSpendingCategoryScope] {
        storedCategories
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .map(\.planningFamilyBudgetSpendingScope)
    }

    var body: some View {
        let snapshotKey = renderSnapshotCacheKey
        let renderSnapshot = cachedRenderSnapshot(for: snapshotKey)
        let actionContext = renderSnapshot.actionContext
        let memberToolbar = familyContextStore.memberViewingToolbarPresentation
        let preparingEvents = renderSnapshot.preparingSettlementEvents

        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .standard,
                title: L10n.overview.overview.overview,
                embedsInNavigationStack: false,
                leadingInitials: memberToolbar?.initials ?? sessionStore.summary?.initials ?? "MI",
                leadingAvatarURL: memberToolbar != nil ? familyContextStore.viewedMember?.avatarURL : sessionStore.summary?.avatarURL,
                leadingAccessibilityLabel: memberToolbar?.accessibilityLabel,
                leadingAvatarAttentionPulse: memberToolbar != nil,
                trailingSystemImage: nil,
                onLeadingTap: {
                    if let memberToolbar {
                        memberViewingExitPrompt = FamilyMemberViewingExitPrompt(presentation: memberToolbar)
                    } else {
                        destination = .profile
                    }
                },
                contentSpacing: 18,
                titleDisplayMode: .large,
                pinnedHeader: { EmptyView() },
                trailingAccessory: {
                    MistiaNotificationBellLink()
                }
            ) {
                OverviewHeroCard(
                    snapshot: renderSnapshot.dashboard.hero,
                    isSheetPresented: selectedExpenseDay != nil,
                    onOpenExpenseDay: { date in
                        openExpenseDay(date, transactionsByDay: renderSnapshot.postedExpenseTransactionsByDay)
                    }
                )
                if !preparingEvents.isEmpty {
                    OverviewPreparingSettlementSection(
                        events: preparingEvents,
                        onSelect: { event in
                            preparingSettlementTarget = PreparingSettlementEventSheetTarget(groupID: event.id)
                        }
                    )
                }
                if !renderSnapshot.dashboard.budgetAlerts.isEmpty {
                    BudgetFocusSection(rows: renderSnapshot.dashboard.budgetAlerts)
                }
                if !renderSnapshot.dashboard.dueAlerts.isEmpty {
                    UpcomingBillsSection(rows: renderSnapshot.dashboard.dueAlerts) { row in
                        routeDueAlertTap(row)
                    }
                }
                RecentTransactionsSection(rows: renderSnapshot.dashboard.recentTransactions) { row in
                    guard let transaction = renderSnapshot.transactionsByID[row.id] else { return }
                    presentEditor(for: transaction, actionContext: actionContext)
                }
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .profile:
                    ManagementAccountView()
                }
            }
            .navigationDestination(item: $statementTarget) { target in
                ManagementCreditCardStatementView(wallet: target.wallet, initialMonth: target.month)
            }
        }
        .familyMemberViewingExitAlert(
            prompt: $memberViewingExitPrompt,
            familyContextStore: familyContextStore
        )
        .sheet(item: $selectedExpenseDay) { selection in
            OverviewDayTransactionsSheet(
                day: selection.date,
                transactions: renderSnapshot.postedExpenseTransactionsByDay[selection.date] ?? [],
                currencyCode: currencyCode,
                archivedSettlementGroupIDs: actionContext.archivedSettlementGroupIDs,
                onSelectTransaction: { transaction in
                    presentEditorFromDaySheet(transaction, actionContext: actionContext)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $editorTarget) { target in
            TransactionEditorSheet(target: target)
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
                var ownerUserID = familyContextStore.viewedMember?.userID ?? sessionStore.activeLocalProfileUserID
                if let group = storedSettlementGroups.first(where: { $0.id == groupID }) {
                    ownerUserID = group.organizerUserID ?? ownerUserID
                }
                if familyContextStore.canEditEvent(for: ownerUserID) {
                    settlementEditorTarget = .editSharedExpense(groupID)
                } else if let ownerUserID {
                    presentEventPermissionPrompt(ownerUserID: ownerUserID, scope: .edit)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $duePaymentTarget) { target in
            DuePaymentSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { isPresented in
                    if !isPresented {
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
            case .permission(let prompt):
                Button(prompt.actionTitle) {
                    prompt.action()
                }
                Button(L10n.common.cancel, role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .task {
            try? MistiaOverviewDebugFixtures.seedCategoryChartDataIfNeeded(
                modelContext: modelContext,
                sessionStore: sessionStore
            )
        }
        .task(id: snapshotKey) {
            refreshRenderSnapshotCache(for: snapshotKey, snapshot: renderSnapshot)
        }
    }

    private func openExpenseDay(
        _ date: Date,
        transactionsByDay: [Date: [LedgerTransaction]]
    ) {
        let day = calendar.startOfDay(for: date)

        guard let transactions = transactionsByDay[day], !transactions.isEmpty else {
            return
        }

        selectedExpenseDay = OverviewExpenseDaySelection(date: day)
    }

    private func presentEditor(
        for transaction: LedgerTransaction,
        actionContext: OverviewActionContext
    ) {
        guard canEditTransaction(transaction, actionContext: actionContext) else {
            presentTransactionEditPermissionPrompt(transaction, actionContext: actionContext)
            return
        }
        editorTarget = TransactionEditorTarget(transaction: transaction)
    }

    private func presentEditorFromDaySheet(
        _ transaction: LedgerTransaction,
        actionContext: OverviewActionContext
    ) {
        selectedExpenseDay = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if canEditTransaction(transaction, actionContext: actionContext) {
                editorTarget = TransactionEditorTarget(transaction: transaction)
            } else {
                presentTransactionEditPermissionPrompt(transaction, actionContext: actionContext)
            }
        }
    }

    private func transactionOwnerUserID(
        for transaction: LedgerTransaction,
        actionContext: OverviewActionContext
    ) -> UUID? {
        actionContext.ownerUserID(
            forTransactionID: transaction.id,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID
        )
    }

    private func canEditTransaction(
        _ transaction: LedgerTransaction,
        actionContext: OverviewActionContext
    ) -> Bool {
        guard let ownerUserID = transactionOwnerUserID(for: transaction, actionContext: actionContext) else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .transaction)
    }

    private func presentTransactionEditPermissionPrompt(
        _ transaction: LedgerTransaction,
        actionContext: OverviewActionContext
    ) {
        guard let ownerUserID = transactionOwnerUserID(for: transaction, actionContext: actionContext),
              ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .transaction,
            resourceID: nil,
            scope: .edit
        )
        permissionPrompt = OverviewPermissionPrompt(
            title: L10n.overview.overview.noTransactionEditAccess,
            message: L10n.overview.overview.youDoNotHavePermissionToEdit,
            actionTitle: isPending
                ? L10n.overview.overview.editRequestSent
                : L10n.overview.overview.requestEditAccess
        ) {
            if isPending {
                refreshTransactionEditPermission(
                    transaction,
                    ownerUserID: ownerUserID
                )
                return
            }

            sendPermissionRequest(
                resourceType: .transaction,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .edit,
                resourceName: L10n.overview.overview.transactions2
            )
        }
    }

    private func refreshTransactionEditPermission(
        _ transaction: LedgerTransaction,
        ownerUserID: UUID
    ) {
        Task { @MainActor in
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
        }
    }

    private func presentEventPermissionPrompt(ownerUserID: UUID, scope: MistiaFamilyPermissionScope) {
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .event,
            resourceID: nil,
            scope: scope
        )
        permissionPrompt = OverviewPermissionPrompt(
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
                infoAlert = OverviewInfoAlert(
                    title: didSend
                        ? L10n.overview.overview.requestSent
                        : L10n.overview.overview.couldnTSend,
                    message: didSend
                        ? L10n.overview.overview.thePermissionRequestWasSentToThe
                        : (familyContextStore.lastErrorMessage ?? L10n.overview.overview.couldnTSendTheRequestRightNow)
                )
            }
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
            permissionPrompt = nil
            try? await Task.sleep(nanoseconds: 150_000_000)
            infoAlert = OverviewInfoAlert(
                title: didSend
                    ? L10n.overview.overview.requestSent
                    : L10n.overview.overview.couldnTSend,
                message: didSend
                    ? L10n.overview.overview.thePermissionRequestWasSentToThe
                    : (familyContextStore.lastErrorMessage ?? L10n.overview.overview.couldnTSendTheRequestRightNow)
            )
        }
    }

    private func sortTransactionsByRecency(_ lhs: LedgerTransaction, _ rhs: LedgerTransaction) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }

        return lhs.createdAt > rhs.createdAt
    }

    private func routeDueAlertTap(_ alert: OverviewDueAlertSnapshot) {
        switch alert.sourceKind {
        case .creditCard:
            if let walletID = alert.sourceID,
               let wallet = storedWallets.first(where: { $0.id == walletID }) {
                let month = PlanningLogic.month(from: alert.dueMonthKey, calendar: calendar) ?? alert.dueDate
                statementTarget = StatementTarget(
                    wallet: wallet,
                    month: PlanningLogic.startOfMonth(for: month, calendar: calendar)
                )
            }
        case .recurringBill, .installment:
            guard let sourceID = alert.sourceID else { return }
            duePaymentTarget = DuePaymentSheetTarget(
                sourceKind: alert.sourceKind,
                sourceID: sourceID,
                dueMonthKey: alert.dueMonthKey,
                dueDate: alert.dueDate,
                requiresAmountInput: alert.requiresAmountInput,
                currencyCode: alert.currencyCode,
                name: alert.name,
                ownerUserID: dueOwnerUserID(for: alert)
            )
        }
    }

    private func dueOwnerUserID(for alert: OverviewDueAlertSnapshot) -> UUID? {
        guard let sourceID = alert.sourceID else {
            return familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
        }

        let entity: MistiaSyncEntity
        switch alert.sourceKind {
        case .recurringBill:
            entity = .recurringBillPlan
        case .installment:
            entity = .installmentPlan
        case .creditCard:
            entity = .wallet
        }

        return MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: entity)[sourceID]
            ?? familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
    }
}

private enum MistiaOverviewDebugFixtures {
    static var startsInCategoryMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MISTIA_OVERVIEW_DEBUG_CATEGORY_MODE"] == "1"
        #else
        false
        #endif
    }

    static var startsInFirstCategoryDrilldown: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MISTIA_OVERVIEW_DEBUG_DRILLDOWN_FIRST"] == "1"
        #else
        false
        #endif
    }

    static func seedCategoryChartDataIfNeeded(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["MISTIA_OVERVIEW_DEBUG_SAMPLE_DATA"] == "1" else {
            return
        }

        let wallet = try sampleWallet(in: modelContext)
        let grocery = try MistiaBootstrap.ensureSystemCategory(.grocery, modelContext: modelContext)
        let dineOut = try MistiaBootstrap.ensureSystemCategory(.dineOut, modelContext: modelContext)
        let rent = try MistiaBootstrap.ensureSystemCategory(.rent, modelContext: modelContext)
        let medicine = try MistiaBootstrap.ensureSystemCategory(.medicine, modelContext: modelContext)
        let calendar = MistiaCalendar.current
        let currentMonth = PlanningLogic.startOfMonth(for: .now, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        let existingTransactionIDs = Set(try modelContext.fetch(FetchDescriptor<LedgerTransaction>()).map(\.id))

        let samples: [(id: UUID, title: String, amountMinor: Int64, occurredAt: Date, category: TransactionCategory)] = [
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!,
                "Debug groceries",
                12_500,
                sampleDate(dayOffset: 3, from: currentMonth, calendar: calendar),
                grocery
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!,
                "Debug dinner",
                8_200,
                sampleDate(dayOffset: 8, from: currentMonth, calendar: calendar),
                dineOut
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E003")!,
                "Debug rent",
                72_000,
                sampleDate(dayOffset: 1, from: currentMonth, calendar: calendar),
                rent
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E004")!,
                "Debug medicine",
                4_600,
                sampleDate(dayOffset: 15, from: currentMonth, calendar: calendar),
                medicine
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E005")!,
                "Debug last month groceries",
                9_400,
                sampleDate(dayOffset: 5, from: previousMonth, calendar: calendar),
                grocery
            )
        ]

        var didInsert = false
        let ownerUserID = sessionStore.activeLocalProfileUserID
        if let ownerUserID {
            try MistiaRecordOwnershipStore.upsert(
                entity: .wallet,
                recordID: wallet.id,
                ownerUserID: ownerUserID,
                context: modelContext
            )
        }

        for sample in samples where !existingTransactionIDs.contains(sample.id) {
            modelContext.insert(
                LedgerTransaction(
                    id: sample.id,
                    primaryKind: .expense,
                    title: sample.title,
                    amountMinor: sample.amountMinor,
                    occurredAt: sample.occurredAt,
                    createdAt: sample.occurredAt,
                    updatedAt: sample.occurredAt,
                    sourceWallet: wallet,
                    category: sample.category
                )
            )
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction,
                    recordID: sample.id,
                    ownerUserID: ownerUserID,
                    context: modelContext
                )
            }
            didInsert = true
        }

        if didInsert || ownerUserID != nil {
            try modelContext.save()
        }
        #endif
    }

    #if DEBUG
    private static func sampleWallet(in modelContext: ModelContext) throws -> LedgerWallet {
        let walletID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
        if let existing = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
            .first(where: { $0.id == walletID }) {
            return existing
        }

        let wallet = LedgerWallet(
            id: walletID,
            name: "Mistia Demo",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            currencyCode: "JPY",
            openingBalanceMinor: 500_000,
            sortOrder: -1
        )
        modelContext.insert(wallet)
        return wallet
    }

    private static func sampleDate(
        dayOffset: Int,
        from monthStart: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: monthStart) ?? monthStart
    }
    #endif
}

private struct OverviewHeroCard: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedWeekStart: Date
    @State private var selectedCategoryMonth: Date
    @State private var chartMode: OverviewHeroChartMode
    @State private var chartDismissToken: Int = 0
    @State private var categoryChartHeight: CGFloat

    let snapshot: OverviewHeroSnapshot
    let isSheetPresented: Bool
    let onOpenExpenseDay: (Date) -> Void

    init(
        snapshot: OverviewHeroSnapshot,
        isSheetPresented: Bool,
        onOpenExpenseDay: @escaping (Date) -> Void
    ) {
        self.snapshot = snapshot
        self.isSheetPresented = isSheetPresented
        self.onOpenExpenseDay = onOpenExpenseDay
        _selectedWeekStart = State(initialValue: snapshot.currentWeekStart)
        _selectedCategoryMonth = State(
            initialValue: snapshot.categoryMonthPages.last?.monthStart
                ?? PlanningLogic.startOfMonth(for: .now)
        )
        _chartMode = State(initialValue: MistiaOverviewDebugFixtures.startsInCategoryMode ? .category : .day)
        _categoryChartHeight = State(
            initialValue: snapshot.categoryMonthPages.last.map {
                MistiaCategorySpendingChartView.preferredRootHeight(for: $0)
            } ?? MistiaCategorySpendingChartView.estimatedHeight(visibleSliceCount: 3)
        )
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.024) : .white.opacity(0.16)
    }

    private var insetSurface: Color {
        colorScheme == .dark ? .white.opacity(0.035) : .black.opacity(0.03)
    }

    private var activeWeek: OverviewWeekSpendingSnapshot {
        snapshot.weekPages.first(where: { $0.weekStart == selectedWeekStart })
            ?? snapshot.weekPages.last
            ?? OverviewWeekSpendingSnapshot(
                weekStart: snapshot.currentWeekStart,
                weekEnd: snapshot.currentWeekStart,
                title: L10n.overview.overview.thisWeek,
                isCurrentWeek: true,
                points: []
            )
    }

    private var activeCategoryMonth: OverviewCategorySpendingMonthSnapshot {
        snapshot.categoryMonthPages.first(where: { $0.monthStart == selectedCategoryMonth })
            ?? snapshot.categoryMonthPages.last
            ?? OverviewCategorySpendingMonthSnapshot(
                monthStart: PlanningLogic.startOfMonth(for: .now, calendar: calendar),
                title: MistiaDateFormatting.monthYearString(for: .now, calendar: calendar),
                currencyCode: snapshot.currencyCode,
                slices: []
            )
    }

    private var activeMonthlyCashflow: OverviewMonthlyCashflowSnapshot {
        let monthStart = chartMode == .category
            ? activeCategoryMonth.monthStart
            : (snapshot.monthlyCashflowPages.last?.monthStart ?? PlanningLogic.startOfMonth(for: .now, calendar: calendar))

        return snapshot.monthlyCashflowPages.first(where: { $0.monthStart == monthStart })
            ?? OverviewMonthlyCashflowSnapshot(
                monthStart: monthStart,
                incomeMinor: 0,
                expenseMinor: 0
            )
    }

    private var isShowingCurrentCashflowMonth: Bool {
        guard let currentMonthStart = snapshot.monthlyCashflowPages.last?.monthStart else {
            return true
        }

        return activeMonthlyCashflow.monthStart == currentMonthStart
    }

    private var incomeMetricTitle: String {
        guard chartMode == .category, !isShowingCurrentCashflowMonth else {
            return L10n.overview.overview.incomeThisMonth
        }

        return L10n.overview.overview.incomeMonthValue(monthNumberText(for: activeMonthlyCashflow.monthStart))
    }

    private var expenseMetricTitle: String {
        guard chartMode == .category, !isShowingCurrentCashflowMonth else {
            return L10n.overview.overview.expenseThisMonth
        }

        return L10n.overview.overview.expenseMonthValue(monthNumberText(for: activeMonthlyCashflow.monthStart))
    }

    private func monthNumberText(for date: Date) -> String {
        String(calendar.component(.month, from: date))
    }

    private var chartTitle: String {
        switch chartMode {
        case .day:
            L10n.overview.overview.dailySpending
        case .category:
            L10n.overview.overview.spendingByCategory
        }
    }

    private var chartSubtitle: String {
        switch chartMode {
        case .day:
            activeWeek.title
        case .category:
            activeCategoryMonth.title
        }
    }

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: cardTint
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.overview.overview.availableAssets)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(snapshot.totalAssetBalanceMinor.formattedCurrency(code: snapshot.currencyCode))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissChartSelection() }

                HStack(spacing: 14) {
                    SummaryMetricColumn(
                        title: incomeMetricTitle,
                        value: activeMonthlyCashflow.incomeMinor.formattedCurrency(code: snapshot.currencyCode),
                        accent: Color(hex: "#2DAA9E")
                    )

                    Divider()
                        .frame(height: 26)

                    SummaryMetricColumn(
                        title: expenseMetricTitle,
                        value: activeMonthlyCashflow.expenseMinor.formattedCurrency(code: snapshot.currencyCode),
                        accent: Color(hex: "#F45C7E")
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissChartSelection() }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chartTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(chartSubtitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { dismissChartSelection() }

                    Picker(String(), selection: $chartMode) {
                        ForEach(OverviewHeroChartMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("overview.hero.chart.mode")

                    if chartMode == .day {
                        TabView(selection: $selectedWeekStart) {
                            ForEach(snapshot.weekPages) { week in
                                OverviewWeekSpendingChart(
                                    week: week,
                                    currencyCode: snapshot.currencyCode,
                                    insetSurface: insetSurface,
                                    isVisible: selectedWeekStart == week.weekStart && !isSheetPresented,
                                    dismissToken: chartDismissToken,
                                    onOpenExpenseDay: onOpenExpenseDay
                                )
                                .tag(week.weekStart)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 154)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        TabView(selection: $selectedCategoryMonth) {
                            ForEach(snapshot.categoryMonthPages) { month in
                                MistiaCategorySpendingChartView(
                                    snapshot: month,
                                    resetKey: "overview-\(month.id)",
                                    startsInFirstDrilldown: MistiaOverviewDebugFixtures.startsInFirstCategoryDrilldown,
                                    accessibilityPrefix: "overview.category",
                                    onPreferredHeightChange: { height in
                                        guard month.monthStart == selectedCategoryMonth else { return }

                                        withAnimation(.snappy(duration: 0.18)) {
                                            categoryChartHeight = height
                                        }
                                    }
                                )
                                .tag(month.monthStart)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: categoryChartHeight)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
        }
        .onChange(of: snapshot.weekPages.map(\.weekStart)) { _, weekStarts in
            if !weekStarts.contains(selectedWeekStart) {
                selectedWeekStart = snapshot.currentWeekStart
            }
        }
        .onChange(of: snapshot.categoryMonthPages.map(\.monthStart)) { _, monthStarts in
            if !monthStarts.contains(selectedCategoryMonth) {
                selectedCategoryMonth = snapshot.categoryMonthPages.last?.monthStart
                    ?? PlanningLogic.startOfMonth(for: .now, calendar: calendar)
            }
            categoryChartHeight = MistiaCategorySpendingChartView.preferredRootHeight(for: activeCategoryMonth)
        }
        .onChange(of: selectedCategoryMonth) { _, _ in
            withAnimation(.snappy(duration: 0.18)) {
                categoryChartHeight = MistiaCategorySpendingChartView.preferredRootHeight(for: activeCategoryMonth)
            }
        }
        .onChange(of: chartMode) { _, _ in
            dismissChartSelection()
        }
    }

    private func dismissChartSelection() {
        chartDismissToken += 1
    }
}

private struct OverviewWeekSpendingChart: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    let week: OverviewWeekSpendingSnapshot
    let currencyCode: String
    let insetSurface: Color
    let isVisible: Bool
    let dismissToken: Int
    let onOpenExpenseDay: (Date) -> Void

    private var chartMax: Double {
        let highest = Double(week.points.map(\.valueMinor).max() ?? 0)
        return max(highest * 1.2, 1)
    }

    private var selectedPoint: OverviewChartPoint? {
        guard let selectedDate else { return nil }

        return week.points.first { point in
            calendar.isDate(point.date, inSameDayAs: selectedDate)
                && point.valueMinor > 0
        }
    }

    var body: some View {
        Chart(week.points) { point in
                let isSelected = selectedPoint?.id == point.id

                BarMark(
                    x: .value("Ngày", point.date, unit: .day),
                    y: .value("Giá trị", Double(point.valueMinor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(chartColor(for: point.intensity).gradient)
                .opacity(selectedPoint == nil ? 0.92 : (isSelected ? 1 : 0.42))
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: week.points.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(weekdayLabel(for: date))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(Int64(number.rounded()).compactAxisLabel)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... chartMax)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]

                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { event in
                                            guard plotFrame.contains(event.location) else {
                                                clearSelection()
                                                return
                                            }

                                            selectPoint(at: event.location, in: plotFrame)
                                        }
                                )

                            if plotFrame.width > 0 {
                                HStack(spacing: 0) {
                                    ForEach(week.points) { point in
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .allowsHitTesting(point.valueMinor > 0)
                                            .onTapGesture {
                                                guard point.valueMinor > 0 else { return }
                                                
                                                if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: point.date) {
                                                    clearSelection()
                                                } else {
                                                    withAnimation(.snappy) {
                                                        selectedDate = point.date
                                                    }
                                                }
                                            }
                                            .onLongPressGesture(minimumDuration: 0.35) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                clearSelection(animated: false)
                                                onOpenExpenseDay(point.date)
                                            }
                                    }
                                }
                                .frame(width: plotFrame.width, height: plotFrame.height)
                                .position(x: plotFrame.midX, y: plotFrame.midY)
                            }

                            if let selectedPoint,
                               let xPosition = proxy.position(forX: selectedPoint.date) {
                                let anchorX = plotFrame.origin.x + xPosition
                                let barTopY = plotFrame.origin.y + (proxy.position(forY: Double(selectedPoint.valueMinor)) ?? 0)
                                let clampedX = min(
                                    max(anchorX, plotFrame.minX + 36),
                                    plotFrame.maxX - 36
                                )
                                let calloutY = max(plotFrame.minY + 16, barTopY - 20)

                                OverviewChartSelectionCallout(
                                    point: selectedPoint,
                                    currencyCode: currencyCode
                                )
                                .position(x: clampedX, y: calloutY)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            .frame(height: 122)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(insetSurface)
        }
        .onChange(of: selectedDate) { _, newValue in
            guard let newValue,
                  let nearestPoint = nearestPoint(to: newValue),
                  !calendar.isDate(nearestPoint.date, inSameDayAs: newValue)
            else {
                return
            }

            selectedDate = nearestPoint.date
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                clearSelection(animated: false)
            }
        }
        .onChange(of: dismissToken) { _, _ in
            clearSelection()
        }
    }

    private func chartColor(for intensity: Double) -> Color {
        let clamped = min(max(intensity, 0), 1)
        let start = (red: 0.18, green: 0.67, blue: 0.62)
        let end = (red: 0.96, green: 0.36, blue: 0.49)

        return Color(
            red: start.red + (end.red - start.red) * clamped,
            green: start.green + (end.green - start.green) * clamped,
            blue: start.blue + (end.blue - start.blue) * clamped
        )
    }

    private func weekdayLabel(for date: Date) -> String {
        week.points.first { calendar.isDate($0.date, inSameDayAs: date) }?.label
            ?? MistiaDateFormatting.weekdayLabel(for: date, calendar: calendar)
    }

    private func nearestPoint(to date: Date) -> OverviewChartPoint? {
        week.points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func selectPoint(at location: CGPoint, in plotFrame: CGRect) {
        guard plotFrame.width > 0, !week.points.isEmpty else {
            clearSelection()
            return
        }

        let columnWidth = plotFrame.width / CGFloat(week.points.count)
        let relativeX = min(max(location.x - plotFrame.minX, 0), plotFrame.width - 1)
        let rawIndex = Int(floor(relativeX / max(columnWidth, 1)))
        let index = min(max(rawIndex, 0), week.points.count - 1)
        let point = week.points[index]

        guard point.valueMinor > 0 else {
            clearSelection()
            return
        }

        if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: point.date) {
            clearSelection()
            return
        }

        withAnimation(.snappy) {
            selectedDate = point.date
        }
    }

    private func clearSelection(animated: Bool = true) {
        if animated {
            withAnimation(.snappy) {
                selectedDate = nil
            }
        } else {
            selectedDate = nil
        }
    }
}

private struct OverviewChartSelectionCallout: View {
    @Environment(\.colorScheme) private var colorScheme

    let point: OverviewChartPoint
    let currencyCode: String

    private var calloutLabel: some View {
        Text(point.valueMinor.formattedCurrency(code: currencyCode))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                calloutLabel
                    .glassEffect(.regular.tint(colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.85)), in: .capsule)
            } else {
                calloutLabel
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.06),
                                        lineWidth: 0.5
                                    )
                            }
                    }
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 16, y: 6)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct OverviewDayTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme

    let day: Date
    let transactions: [LedgerTransaction]
    let currencyCode: String
    let archivedSettlementGroupIDs: Set<UUID>
    let onSelectTransaction: (LedgerTransaction) -> Void

    private var totalMinor: Int64 {
        transactions.reduce(into: Int64.zero) { partialResult, transaction in
            partialResult += transaction.amountMinor
        }
    }

    private var groupedBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                groupedBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        MistiaBlockCard(cornerRadius: 24, padding: 18) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(
                                    L10n.overview.overview.dailyExpenses
                                )
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)

                                Text(MistiaDateFormatting.fullDateString(for: day, calendar: calendar))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 12) {
                                    OverviewDaySummaryMetric(
                                        title: L10n.overview.overview.totalSpent,
                                        value: totalMinor.formattedCurrency(code: currencyCode),
                                        tint: MistiaAccent.expense.color
                                    )

                                    Divider()
                                        .frame(height: 28)

                                    OverviewDaySummaryMetric(
                                        title: L10n.overview.overview.transactions,
                                        value: "\(transactions.count)",
                                        tint: colorScheme == .dark ? .white : .primary
                                    )
                                }
                            }
                        }

                        MistiaBlockCard(cornerRadius: 22, padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                                    Button {
                                        dismiss()
                                        onSelectTransaction(transaction)
                                    } label: {
                                        OverviewDayTransactionRow(
                                            transaction: transaction,
                                            currencyCode: currencyCode,
                                            archivedSettlementGroupIDs: archivedSettlementGroupIDs
                                        )
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                                    if index < transactions.count - 1 {
                                        Divider()
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(L10n.overview.overview.dayDetails)
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
            .toolbarBackground(groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(groupedBackground)
    }
}

private struct OverviewDaySummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewDayTransactionRow: View {
    let transaction: LedgerTransaction
    let currencyCode: String
    let archivedSettlementGroupIDs: Set<UUID>

    private var titleText: String {
        let trimmed = transaction.localizedTransactionTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            return trimmed
        }

        return transaction.category?.localizedDisplayName
            ?? L10n.overview.overview.expense
    }

    private var subtitleText: String {
        let timeText = transaction.occurredAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(MistiaAppLanguage.current.locale)
        )
        let walletName = transaction.sourceWallet?.name
            ?? L10n.overview.overview.noWalletSelected

        if let categoryName = transaction.category?.localizedDisplayName,
           categoryName != titleText {
            return "\(timeText) • \(walletName) • \(categoryName)"
        }

        return "\(timeText) • \(walletName)"
    }

    private var iconName: String {
        transaction.category?.iconSymbolName ?? transaction.primaryKind.financeIconToken
    }

    private var amountColor: Color {
        MistiaAccent.expense.color
    }

    private var shouldShowSettlementEventBadge: Bool {
        guard let settlementGroupID = transaction.settlementGroupID else { return false }
        return !archivedSettlementGroupIDs.contains(settlementGroupID)
    }

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(icon: iconName, fallbackColor: amountColor, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if shouldShowSettlementEventBadge {
                    HStack(spacing: 6) {
                        MistiaMiniBadge(
                            title: L10n.transactions.settlement.eventTitle,
                            tint: MistiaAccent.teal.color
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: -8)
                }

                Text(subtitleText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(verbatim: "-" + transaction.amountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct SummaryMetricColumn: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetFocusSection: View {
    let rows: [OverviewBudgetAlertSnapshot]

    var body: some View {
        OverviewSection(title: L10n.overview.overview.budgetWatchlist) {
            if rows.isEmpty {
                OverviewEmptySectionContent(
                    message: L10n.overview.overview.noCategoriesHaveExceededOfTheir
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        BudgetRow(row: row)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                        if index < rows.count - 1 {
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

private struct BudgetRow: View {
    let row: OverviewBudgetAlertSnapshot

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: row.iconSymbolName, tint: row.tint.color)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(row.progressPercentText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(row.tint.color)
                }

                Text(verbatim: "\(row.spentMinor.formattedCurrency(code: row.currencyCode)) / \(row.limitMinor.formattedCurrency(code: row.currencyCode))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                ProgressView(value: min(max(row.progress, 0), 1))
                    .tint(row.tint.color)

                Text(
                    L10n.overview.overview.valueDaysLeft(String(describing: row.daysRemaining))
                )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(row.tint.color)
            }
        }
    }
}

private struct UpcomingBillsSection: View {
    let rows: [OverviewDueAlertSnapshot]
    let onSelect: (OverviewDueAlertSnapshot) -> Void

    var body: some View {
        OverviewSection(title: L10n.overview.overview.upcomingDueItems) {
            if rows.isEmpty {
                OverviewEmptySectionContent(
                    message: L10n.overview.overview.noBillsLoansOrCreditPaymentsAre
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onSelect(row)
                        } label: {
                            DueRow(row: row)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }
}

private struct DueRow: View {
    let row: OverviewDueAlertSnapshot

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: row.iconSymbolName, tint: row.tint.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(verbatim: "\(row.dueDate.overviewDayText) • \(detailText)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.tint == .red ? row.tint.color : .secondary)
            }

            Spacer()

            if let amountMinor = row.amountMinor {
                Text(amountMinor.formattedCurrency(code: row.currencyCode))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(row.tint == .red ? row.tint.color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(L10n.overview.overview.noAmountYet)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailText: String {
        if row.dayDelta == 0 {
            return L10n.overview.overview.dueToday
        }

        return L10n.overview.overview.valueDaysLeft(String(describing: row.dayDelta))
    }
}

private struct RecentTransactionsSection: View {
    let rows: [OverviewRecentTransactionSnapshot]
    let onSelect: (OverviewRecentTransactionSnapshot) -> Void

    var body: some View {
        OverviewSection(title: L10n.overview.overview.recentTransactions) {
            if rows.isEmpty {
                OverviewEmptySectionContent(
                    message: L10n.overview.overview.noTransactionsHaveBeenRecordedRecently
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onSelect(row)
                        } label: {
                            RecentTransactionRow(row: row)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewPreparingSettlementSection: View {
    let events: [PreparingSettlementEventSnapshot]
    let onSelect: (PreparingSettlementEventSnapshot) -> Void

    var body: some View {
        OverviewSection(title: L10n.transactions.settlement.ongoingEvents) {
            VStack(spacing: 0) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { index, event in
                    Button {
                        onSelect(event)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            OverviewIcon(icon: "mistia.settlement.event", tint: MistiaAccent.purple.color)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Text(participantText(for: event))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                
                                Text(L10n.transactions.settlement.billCountValue(String(event.billCount)))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                
                                if let note = trimmedNote(for: event) {
                                    Text(note)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer(minLength: 8)
                            
                            HStack(spacing: 8) {
                                Text(event.totalPaidMinor.formattedCurrency(code: event.currencyCode))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(MistiaAccent.expense.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)

                    if index < min(events.count, 3) - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
    }

    private func participantText(for event: PreparingSettlementEventSnapshot) -> String {
        if event.participantNames.isEmpty {
            return L10n.transactions.settlement.noParticipantsYet
        } else {
            return "\(event.participantNames.count) người: \(event.participantNames.joined(separator: ", "))"
        }
    }

    private func trimmedNote(for event: PreparingSettlementEventSnapshot) -> String? {
        guard let note = event.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        return note
    }
}

private struct RecentTransactionRow: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    let row: OverviewRecentTransactionSnapshot

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: iconName, tint: amountColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(row.timeLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(displayAmount)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var amountColor: Color {
        switch row.cashflowStyle {
        case .income:
            Color(red: 0.18, green: 0.67, blue: 0.62)  // Xanh lục
        case .expense:
            Color(red: 0.96, green: 0.36, blue: 0.49)  // Đỏ hồng
        case .neutral:
            colorScheme == .dark ? .white : Color(red: 0.60, green: 0.60, blue: 0.60)  // Trắng/xám
        }
    }

    private var iconName: String {
        row.categoryIconSymbolName
    }

    private var displayAmount: String {
        let raw = row.amountMinor.formattedCurrency(code: row.currencyCode)

        switch row.cashflowStyle {
        case .income:
            return "+" + raw
        case .expense:
            return "-" + raw
        case .neutral:
            return raw
        }
    }
}

private struct OverviewSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    private let content: Content

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43))

            MistiaBlockCard(
                cornerRadius: 22,
                tint: cardTint,
                padding: 0
            ) {
                content
            }
        }
    }
}

private struct OverviewEmptySectionContent: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
    }
}

private struct OverviewIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: tint, size: 30)
    }
}

private extension Date {
    var overviewDayText: String {
        MistiaDateFormatting.shortDateString(for: self)
    }
}
