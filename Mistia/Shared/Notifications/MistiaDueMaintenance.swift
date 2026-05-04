import Foundation
import SwiftData

/// Single entry point that runs all due-maintenance passes in sequence:
/// 1. Credit-card statement maintenance (existing)
/// 2. Recurring-bill auto-pay / notification maintenance (new)
/// 3. Local notification scheduler rescheduling
@MainActor
enum MistiaDueMaintenance {
    static func run(
        modelContext: ModelContext,
        sessionStore: SessionStore,
        referenceDate: Date = .now,
        calendar: Calendar = .current
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
        await MistiaLocalNotificationScheduler.rescheduleReminders(
            modelContext: modelContext,
            referenceDate: referenceDate
        )
    }
}
