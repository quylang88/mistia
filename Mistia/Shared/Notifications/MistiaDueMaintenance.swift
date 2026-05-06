import Foundation
import SwiftData

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
        await MistiaCreditCardStatementMaintenance.run(
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: referenceDate,
            calendar: calendar
        )
        await MistiaRecurringBillMaintenance.run(
            modelContext: modelContext,
            sessionStore: sessionStore,
            referenceDate: referenceDate,
            calendar: calendar
        )
        MistiaBudgetReminderMaintenance.run(
            modelContext: modelContext,
            referenceDate: referenceDate,
            calendar: calendar
        )
        await MistiaLocalNotificationScheduler.rescheduleReminders(
            modelContext: modelContext,
            referenceDate: referenceDate
        )
    }
}

@MainActor
private enum MistiaBudgetReminderMaintenance {
    static func run(
        modelContext: ModelContext,
        referenceDate: Date,
        calendar: Calendar
    ) {
        guard MistiaNotificationPreferences.reminderEnabled(.budget) else { return }

        let budgets = (try? modelContext.fetch(
            FetchDescriptor<BudgetPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        guard !budgets.isEmpty else { return }

        let transactions = (try? modelContext.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []

        let selectedMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)
        let alerts = OverviewLogic.budgetAlerts(
            budgets: budgets
                .filter {
                    PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == selectedMonth
                }
                .map { $0.planningSnapshot(calendar: calendar) },
            transactionRecords: transactions.map(\.planningRecordSnapshot),
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
                modelContext: modelContext
            )
        }
    }

    private static func upsertBudgetWarning(
        _ alert: OverviewBudgetAlertSnapshot,
        monthKey: String,
        modelContext: ModelContext
    ) {
        let key = "mistia.budget.warning.\(alert.id.uuidString.lowercased()).\(monthKey)"
        let title = alert.progress >= 1
            ? mistiaLocalized(vi: "Ngân sách đã vượt mức", en: "Budget over limit", ja: "予算を超過しました")
            : mistiaLocalized(vi: "Ngân sách sắp vượt mức", en: "Budget near limit", ja: "予算の上限が近づいています")
        let body = mistiaLocalized(
            vi: "\(alert.name) đã dùng \(alert.spentMinor.formattedCurrency(code: alert.currencyCode)) / \(alert.limitMinor.formattedCurrency(code: alert.currencyCode)) (\(alert.progressPercentText)).",
            en: "\(alert.name) used \(alert.spentMinor.formattedCurrency(code: alert.currencyCode)) / \(alert.limitMinor.formattedCurrency(code: alert.currencyCode)) (\(alert.progressPercentText)).",
            ja: "\(alert.name) は \(alert.spentMinor.formattedCurrency(code: alert.currencyCode)) / \(alert.limitMinor.formattedCurrency(code: alert.currencyCode))（\(alert.progressPercentText)）を使用しました。"
        )

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
                resourceType: .category,
                resourceID: alert.id
            ))
        }

        try? modelContext.save()
    }
}
