import Foundation
import SwiftData

@MainActor
struct MistiaDueMaintenanceSnapshot {
    let activeUserID: UUID
    let storedWallets: [LedgerWallet]
    let storedTransactions: [LedgerTransaction]
    let storedOccurrences: [DueOccurrenceRecord]
    let storedBudgets: [BudgetPlan]
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
    let activeOccurrenceSnapshots: [PlanningDueOccurrenceSnapshot]
    let walletByID: [UUID: LedgerWallet]
    let balanceIndex: TransactionWalletBalanceIndex

    static func make(
        modelContext: ModelContext,
        sessionStore: SessionStore
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
        let storedBills = (try? modelContext.fetch(
            FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let ownershipScopes = (try? modelContext.fetch(FetchDescriptor<OwnedRecordScope>())) ?? []

        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)
        let billOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)

        let activeWallets = storedWallets.filter {
            (walletOwnerMap[$0.id] ?? activeUserID) == activeUserID
        }
        let activeTransactions = storedTransactions.filter { transaction in
            let walletOwnerUserID = transaction.sourceWallet.flatMap { walletOwnerMap[$0.id] }
                ?? transaction.destinationWallet.flatMap { walletOwnerMap[$0.id] }
            let ownerUserID = transactionOwnerMap[transaction.id] ?? walletOwnerUserID ?? activeUserID
            return ownerUserID == activeUserID
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
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) async {
        guard let snapshot = MistiaDueMaintenanceSnapshot.make(
            modelContext: modelContext,
            sessionStore: sessionStore
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
        let alerts = OverviewLogic.budgetAlerts(
            budgets: snapshot.activeBudgets
                .filter {
                    PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == selectedMonth
                }
                .map { $0.planningSnapshot(calendar: calendar) },
            transactionRecords: snapshot.activeTransactionRecords,
            referenceDate: referenceDate,
            calendar: calendar,
            minimumProgress: 0.8,
            includesMinimumProgress: true,
            maximumCount: nil
        )

        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)
        for alert in alerts {
            upsertBudgetWarning(
                alert,
                monthKey: monthKey,
                recipientUserID: snapshot.activeUserID,
                modelContext: modelContext
            )
        }
    }

    private static func upsertBudgetWarning(
        _ alert: OverviewBudgetAlertSnapshot,
        monthKey: String,
        recipientUserID: UUID,
        modelContext: ModelContext
    ) {
        let key = "mistia.budget.warning.\(alert.id.uuidString.lowercased()).\(monthKey)"
        let title = alert.progress >= 1
            ? L10n.shared.notifications.mistiaduemaintenance.budgetOverLimit
            : L10n.shared.notifications.mistiaduemaintenance.budgetNearLimit
        let body = L10n.shared.notifications.mistiaduemaintenance.valueUsedValueValueValue(String(describing: alert.name), String(describing: alert.spentMinor.formattedCurrency(code: alert.currencyCode)), String(describing: alert.limitMinor.formattedCurrency(code: alert.currencyCode)), String(describing: alert.progressPercentText))

        let existing = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate { $0.key == key }
            )
        ))?.first

        if let existing {
            existing.title = title
            existing.body = body
            existing.kind = .budgetWarning
            existing.source = .system
            existing.recipientUserID = recipientUserID
            existing.resourceType = .category
            existing.resourceID = alert.id
            existing.updatedAt = .now
        } else {
            modelContext.insert(AppNotificationRecord(
                key: key,
                createdAt: .now,
                updatedAt: .now,
                title: title,
                body: body,
                kind: .budgetWarning,
                source: .system,
                isRead: false,
                recipientUserID: recipientUserID,
                resourceType: .category,
                resourceID: alert.id
            ))
        }

        try? modelContext.save()
    }
}
