import Foundation
import SwiftData

@MainActor
struct MistiaDueMaintenanceSnapshot {
    let activeUserID: UUID
    let storedWallets: [LedgerWallet]
    let storedTransactions: [LedgerTransaction]
    let storedOccurrences: [DueOccurrenceRecord]
    let storedBudgets: [BudgetPlan]
    let storedCategories: [TransactionCategory]
    let storedBills: [RecurringBillPlan]
    let ownershipScopes: [OwnedRecordScope]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let occurrenceOwnerMap: [UUID: UUID]
    let billOwnerMap: [UUID: UUID]
    let budgetOwnerMap: [UUID: UUID]
    let activeWallets: [LedgerWallet]
    let activeTransactions: [LedgerTransaction]
    let activeOccurrences: [DueOccurrenceRecord]
    let activeBudgets: [BudgetPlan]
    let activeBills: [RecurringBillPlan]
    let activeTransactionRecords: [TransactionRecordSnapshot]
    let familyBudgetTransactions: [FamilyAggregateTransactionSnapshot]
    let familyBudgetSpendingAvailable: Bool
    let activeOccurrenceSnapshots: [PlanningDueOccurrenceSnapshot]
    let walletByID: [UUID: LedgerWallet]
    let balanceIndex: TransactionWalletBalanceIndex

    static func make(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        familyContextStore: FamilyContextStore? = nil
    ) -> MistiaDueMaintenanceSnapshot? {
        guard let activeUserID = sessionStore.activeLocalProfileUserID else { return nil }

        let storedWallets = (try? modelContext.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let storedTransactions = (try? modelContext.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let storedOccurrences = (try? modelContext.fetch(
            FetchDescriptor<DueOccurrenceRecord>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )) ?? []
        let storedBudgets = (try? modelContext.fetch(
            FetchDescriptor<BudgetPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let storedCategories = (try? modelContext.fetch(
            FetchDescriptor<TransactionCategory>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let storedBills = (try? modelContext.fetch(
            FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let storedSettlementGroups = (try? modelContext.fetch(
            FetchDescriptor<SettlementGroup>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )) ?? []
        let ownershipScopes = (try? modelContext.fetch(FetchDescriptor<OwnedRecordScope>())) ?? []

        let ownerMaps = MistiaRecordOwnershipStore.ownerMaps(
            from: ownershipScopes,
            entities: [.wallet, .transaction, .dueOccurrenceRecord, .recurringBillPlan, .budgetPlan, .settlementGroup]
        )
        let walletOwnerMap = ownerMaps[.wallet]
        let transactionOwnerMap = ownerMaps[.transaction]
        let occurrenceOwnerMap = ownerMaps[.dueOccurrenceRecord]
        let billOwnerMap = ownerMaps[.recurringBillPlan]
        let budgetOwnerMap = ownerMaps[.budgetPlan]
        let settlementGroupOwnerMap = ownerMaps[.settlementGroup]
        let scopeSnapshot = familyContextStore.map {
            FamilyScopedData.ScopeSnapshot(
                scopes: ownershipScopes,
                familyContextStore: $0,
                sessionStore: sessionStore,
                entities: [.wallet, .transaction, .settlementGroup]
            )
        }

        let activeWallets = storedWallets.filter {
            (walletOwnerMap[$0.id] ?? activeUserID) == activeUserID
        }
        let activeSettlementGroups: [SettlementGroup]
        if let scopeSnapshot {
            activeSettlementGroups = FamilyScopedData.visible(
                storedSettlementGroups,
                entity: .settlementGroup,
                scopeSnapshot: scopeSnapshot
            )
        } else {
            activeSettlementGroups = storedSettlementGroups.filter {
                (settlementGroupOwnerMap[$0.id] ?? $0.organizerUserID ?? activeUserID) == activeUserID
            }
        }
        let archivedEventIDs = SettlementLogic.archivedSharedExpenseEventIDs(
            from: activeSettlementGroups.map(\.recordSnapshot)
        )
        let scopedActiveTransactions = storedTransactions.filter { transaction in
            let walletOwnerUserID = transaction.sourceWallet.flatMap { walletOwnerMap[$0.id] }
                ?? transaction.destinationWallet.flatMap { walletOwnerMap[$0.id] }
            let ownerUserID = transactionOwnerMap[transaction.id] ?? walletOwnerUserID ?? activeUserID
            return ownerUserID == activeUserID
        }
        let activeTransactionIDs = Set(
            SettlementLogic.visibleRecordsAfterEventArchiveFiltering(
                scopedActiveTransactions.map(\.planningRecordSnapshot),
                archivedEventIDs: archivedEventIDs
            )
            .map(\.id)
        )
        let activeTransactions = scopedActiveTransactions.filter {
            activeTransactionIDs.contains($0.id)
        }
        let activeOccurrences = storedOccurrences.filter { occurrence in
            let sourceOwnerUserID: UUID?
            switch occurrence.sourceKind {
            case .recurringBill:
                sourceOwnerUserID = billOwnerMap[occurrence.sourceID]
            case .creditCard:
                sourceOwnerUserID = walletOwnerMap[occurrence.sourceID]
            case .installment:
                sourceOwnerUserID = nil
            }
            let ownerUserID = occurrenceOwnerMap[occurrence.id] ?? sourceOwnerUserID ?? activeUserID
            return ownerUserID == activeUserID
        }
        let activeBudgets = storedBudgets.filter {
            (budgetOwnerMap[$0.id] ?? activeUserID) == activeUserID
        }
        let activeBills = storedBills.filter {
            (billOwnerMap[$0.id] ?? activeUserID) == activeUserID
        }
        let activeTransactionRecords = activeTransactions.map(\.planningRecordSnapshot)
        let familyBudgetSpendingAvailable = familyContextStore?.family != nil
            && (familyContextStore?.members.count ?? 0) >= 2
        let familyBudgetTransactions: [FamilyAggregateTransactionSnapshot]
        if let familyContextStore, let scopeSnapshot, familyBudgetSpendingAvailable {
            let familyMemberUserIDs = Set(familyContextStore.members.map(\.userID))
            let familyArchivedEventIDs = FamilyScopedData.archivedSharedExpenseEventIDsForCurrentFamily(
                from: storedSettlementGroups,
                scopeSnapshot: scopeSnapshot,
                familyMemberUserIDs: familyMemberUserIDs,
                signedInUserID: activeUserID
            )
            familyBudgetTransactions = FamilyScopedData.familyBudgetTransactionSnapshots(
                from: storedTransactions,
                scopeSnapshot: scopeSnapshot,
                familyMemberUserIDs: familyMemberUserIDs,
                signedInUserID: activeUserID,
                archivedEventIDs: familyArchivedEventIDs
            )
        } else {
            familyBudgetTransactions = []
        }
        let activeOccurrenceSnapshots = activeOccurrences.map(\.planningSnapshot)
        let walletByID = Dictionary(activeWallets.map { ($0.id, $0) }, uniquingKeysWith: latestWallet)
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: activeWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: activeTransactionRecords
        )

        return MistiaDueMaintenanceSnapshot(
            activeUserID: activeUserID,
            storedWallets: storedWallets,
            storedTransactions: storedTransactions,
            storedOccurrences: storedOccurrences,
            storedBudgets: storedBudgets,
            storedCategories: storedCategories,
            storedBills: storedBills,
            ownershipScopes: ownershipScopes,
            walletOwnerMap: walletOwnerMap,
            transactionOwnerMap: transactionOwnerMap,
            occurrenceOwnerMap: occurrenceOwnerMap,
            billOwnerMap: billOwnerMap,
            budgetOwnerMap: budgetOwnerMap,
            activeWallets: activeWallets,
            activeTransactions: activeTransactions,
            activeOccurrences: activeOccurrences,
            activeBudgets: activeBudgets,
            activeBills: activeBills,
            activeTransactionRecords: activeTransactionRecords,
            familyBudgetTransactions: familyBudgetTransactions,
            familyBudgetSpendingAvailable: familyBudgetSpendingAvailable,
            activeOccurrenceSnapshots: activeOccurrenceSnapshots,
            walletByID: walletByID,
            balanceIndex: balanceIndex
        )
    }

    private static func latestWallet(_ lhs: LedgerWallet, _ rhs: LedgerWallet) -> LedgerWallet {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }
}

/// Single entry point that runs all due-maintenance passes in sequence:
/// 1. Credit-card statement maintenance (existing)
/// 2. Recurring-bill auto-pay / notification maintenance (new)
/// 3. Budget reminder maintenance
/// 4. Local notification scheduler rescheduling
@MainActor
enum MistiaDueMaintenance {
    static func run(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        familyContextStore: FamilyContextStore? = nil,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) async {
        guard let snapshot = MistiaDueMaintenanceSnapshot.make(
            modelContext: modelContext,
            sessionStore: sessionStore,
            familyContextStore: familyContextStore
        ) else { return }

        await MistiaCreditCardStatementMaintenance.run(
            snapshot: snapshot,
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: referenceDate,
            calendar: calendar
        )
        await MistiaRecurringBillMaintenance.run(
            snapshot: snapshot,
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: referenceDate,
            calendar: calendar
        )
        MistiaBudgetReminderMaintenance.run(
            snapshot: snapshot,
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: referenceDate,
            calendar: calendar
        )
        await MistiaLocalNotificationScheduler.rescheduleReminders(
            snapshot: snapshot,
            modelContext: modelContext,
            recipientUserID: sessionStore.activeLocalProfileUserID,
            referenceDate: referenceDate
        )
    }
}

@MainActor
private enum MistiaBudgetReminderMaintenance {
    static func run(
        snapshot: MistiaDueMaintenanceSnapshot,
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date,
        calendar: Calendar
    ) {
        guard MistiaNotificationPreferences.reminderEnabled(.budget) else { return }
        guard !snapshot.activeBudgets.isEmpty else { return }

        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let familyBudgetSpendingCategoryScopes = snapshot.storedCategories
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .map(\.planningFamilyBudgetSpendingScope)
        let alerts = OverviewLogic.budgetAlerts(
            budgets: PlanningLogic.resolvingFamilySpendingCategoryScopes(
                plans: snapshot.activeBudgets
                    .filter {
                        PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == selectedMonth
                    }
                    .map { $0.planningSnapshot(calendar: calendar) },
                categoryScopes: familyBudgetSpendingCategoryScopes
            ),
            transactionRecords: snapshot.activeTransactionRecords,
            referenceDate: referenceDate,
            calendar: calendar,
            familyTransactions: snapshot.familyBudgetTransactions,
            familySpendingAvailable: snapshot.familyBudgetSpendingAvailable,
            includesStable: true,
            maximumCount: nil
        )
        guard !alerts.isEmpty else { return }

        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)
        var existingBudgetWarningsByKey = existingBudgetWarningsByKey(
            modelContext: modelContext,
            monthKey: monthKey
        )
        var didMutateNotifications = false
        for alert in alerts {
            didMutateNotifications = upsertBudgetWarning(
                alert,
                monthKey: monthKey,
                recipientUserID: snapshot.activeUserID,
                modelContext: modelContext,
                existingBudgetWarningsByKey: &existingBudgetWarningsByKey
            ) || didMutateNotifications
        }

        if didMutateNotifications {
            try? modelContext.save()
            MistiaNotificationStore.updateAppBadgeCount(in: modelContext, userID: snapshot.activeUserID)
        }
    }

    @discardableResult
    private static func upsertBudgetWarning(
        _ alert: OverviewBudgetAlertSnapshot,
        monthKey: String,
        recipientUserID: UUID,
        modelContext: ModelContext,
        existingBudgetWarningsByKey: inout [String: AppNotificationRecord]
    ) -> Bool {
        let key = "mistia.budget.warning.\(alert.id.uuidString.lowercased()).\(monthKey)"
        let metadataJSON = budgetWarningMetadataJSON(health: alert.health)

        if let existing = existingBudgetWarningsByKey[key] {
            let previousHealth = budgetWarningHealth(from: existing.metadataJSON)
            switch PlanningLogic.budgetNotificationTransition(
                hasExistingNotification: true,
                previousHealth: previousHealth,
                currentHealth: alert.health
            ) {
            case .none:
                return false
            case .create:
                return false
            case .updateSilently:
                if alert.health != .stable {
                    let presentation = budgetWarningPresentation(for: alert)
                    existing.title = presentation.title
                    existing.body = presentation.body
                }
                existing.metadataJSON = metadataJSON
                existing.updatedAt = .now
                return true
            case .resurface:
                let presentation = budgetWarningPresentation(for: alert)
                existing.title = presentation.title
                existing.body = presentation.body
                existing.kind = .budgetWarning
                existing.source = .system
                existing.recipientUserID = recipientUserID
                existing.resourceType = .category
                existing.resourceID = alert.id
                existing.metadataJSON = metadataJSON
                existing.updatedAt = .now
                existing.createdAt = .now
                existing.isRead = false
                existing.readAt = nil
                return true
            }
        }

        guard PlanningLogic.budgetNotificationTransition(
            hasExistingNotification: false,
            previousHealth: nil,
            currentHealth: alert.health
        ) == .create else { return false }
        let presentation = budgetWarningPresentation(for: alert)
        let record = AppNotificationRecord(
            key: key,
            createdAt: .now,
            updatedAt: .now,
            title: presentation.title,
            body: presentation.body,
            kind: .budgetWarning,
            source: .system,
            isRead: false,
            recipientUserID: recipientUserID,
            resourceType: .category,
            resourceID: alert.id,
            metadataJSON: metadataJSON
        )
        modelContext.insert(record)
        existingBudgetWarningsByKey[key] = record
        return true
    }

    private static func existingBudgetWarningsByKey(
        modelContext: ModelContext,
        monthKey: String
    ) -> [String: AppNotificationRecord] {
        let budgetWarningKindRawValue = MistiaAppNotificationKind.budgetWarning.rawValue
        let rows = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.kindRawValue == budgetWarningKindRawValue
                }
            )
        )) ?? []
        let keyPrefix = "mistia.budget.warning."
        let keySuffix = ".\(monthKey)"
        return Dictionary(
            rows.lazy
                .filter { $0.key.hasPrefix(keyPrefix) && $0.key.hasSuffix(keySuffix) }
                .map { ($0.key, $0) },
            uniquingKeysWith: latestNotification
        )
    }

    private static func budgetWarningPresentation(
        for alert: OverviewBudgetAlertSnapshot
    ) -> (title: String, body: String) {
        switch alert.health {
        case .stable, .caution:
            return (
                L10n.shared.notifications.mistiaduemaintenance.budgetSpendingTooFast,
                L10n.shared.notifications.mistiaduemaintenance.budgetSpendingTooFastBody(
                    alert.name,
                    alert.projectedSpentMinor.formattedCurrency(code: alert.currencyCode),
                    alert.remainingDailyAllowanceMinor.formattedCurrency(code: alert.currencyCode)
                )
            )
        case .exceeded:
            return (
                L10n.shared.notifications.mistiaduemaintenance.budgetOverLimit,
                L10n.shared.notifications.mistiaduemaintenance.valueUsedValueValueValue(
                    alert.name,
                    alert.spentMinor.formattedCurrency(code: alert.currencyCode),
                    alert.limitMinor.formattedCurrency(code: alert.currencyCode),
                    alert.progressPercentText
                )
            )
        }
    }

    private static func budgetWarningMetadataJSON(health: PlanningBudgetHealth) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["budget_pace_health": health.rawValue],
            options: [.sortedKeys]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func budgetWarningHealth(from metadataJSON: String?) -> PlanningBudgetHealth? {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let rawValue = metadata["budget_pace_health"]
        else {
            return nil
        }
        return PlanningBudgetHealth(rawValue: rawValue)
    }

    private static func latestNotification(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> AppNotificationRecord {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }
}
