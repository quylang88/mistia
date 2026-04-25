import Foundation
import SwiftData
import UserNotifications

@MainActor
enum MistiaLocalNotificationScheduler {
    private static let calendar = Calendar.current
    private static let reminderCategoryID = "mistia.reminders"

    static func rescheduleReminders(
        modelContext: ModelContext,
        referenceDate: Date = .now
    ) async {
        await requestAuthorizationIfNeeded()
        await clearScheduledRemindersOnly()

        let startOfMonth = PlanningLogic.startOfMonth(for: referenceDate, calendar: calendar)

        let bills = (try? modelContext.fetch(
            FetchDescriptor<RecurringBillPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []

        let installments = (try? modelContext.fetch(
            FetchDescriptor<InstallmentPlan>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []

        let occurrences = (try? modelContext.fetch(
            FetchDescriptor<DueOccurrenceRecord>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )) ?? []

        let wallets = (try? modelContext.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []

        let transactions = (try? modelContext.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []

        let transactionRecords = transactions.map(\.planningRecordSnapshot)
        let planningCreditCardAccounts = wallets.compactMap { $0.planningCreditCardSnapshot(records: transactionRecords) }
        let occurrenceSnapshots = occurrences.map(\.planningSnapshot)

        let cardDueItems = PlanningLogic.creditCardDueItems(
            accounts: planningCreditCardAccounts,
            occurrences: occurrenceSnapshots,
            selectedMonth: startOfMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let recurringDueItems = PlanningLogic.recurringBillDueItems(
            bills: bills.map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: startOfMonth,
            calendar: calendar
        )

        let installmentDueItems = PlanningLogic.installmentDueItems(
            plans: installments.map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: startOfMonth,
            calendar: calendar
        )

        let dueAlerts = OverviewLogic.dueAlerts(
            creditCardDues: cardDueItems,
            recurringDues: recurringDueItems + installmentDueItems,
            referenceDate: referenceDate,
            calendar: calendar
        )

        for alert in dueAlerts {
            await scheduleDueAlert(alert, referenceDate: referenceDate, modelContext: modelContext)
        }

        await scheduleLowWalletAlerts(
            wallets: wallets,
            transactionRecords: transactionRecords,
            referenceDate: referenceDate,
            modelContext: modelContext
        )
    }

    static func clearAllScheduledReminders() async {
        await clearScheduledRemindersOnly()
    }

    // MARK: - Internals

    private static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private static func clearScheduledRemindersOnly() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("mistia.reminder.") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func scheduleDueAlert(
        _ alert: OverviewDueAlertSnapshot,
        referenceDate: Date,
        modelContext: ModelContext
    ) async {
        // One-day-before reminder at 09:00 local time.
        let startOfDueDay = calendar.startOfDay(for: alert.dueDate)
        let triggerDay = calendar.date(byAdding: .day, value: -1, to: startOfDueDay) ?? startOfDueDay
        var triggerComponents = calendar.dateComponents([.year, .month, .day], from: triggerDay)
        triggerComponents.hour = 9
        triggerComponents.minute = 0

        let triggerDate = calendar.date(from: triggerComponents) ?? triggerDay
        guard triggerDate > referenceDate else { return }

        let content = UNMutableNotificationContent()
        content.title = mistiaLocalized(
            vi: "Sắp đến hạn",
            en: "Due soon",
            ja: "期限が近い"
        )
        content.body = "\(alert.name) — \(MistiaDateFormatting.shortDateString(for: alert.dueDate))"
        content.sound = .default
        content.categoryIdentifier = reminderCategoryID

        let identifier = "mistia.reminder.due.\(alert.id)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)

        upsertInboxRecord(
            modelContext: modelContext,
            key: identifier,
            createdAt: triggerDate,
            title: content.title,
            body: content.body,
            kind: .dueSoon,
            source: .localReminder
        )
    }

    private static func scheduleLowWalletAlerts(
        wallets: [LedgerWallet],
        transactionRecords: [TransactionRecordSnapshot],
        referenceDate: Date,
        modelContext: ModelContext
    ) async {
        // Phase 1 heuristic: only notify when a cash wallet balance is <= 0.
        let cashWallets = wallets.filter { $0.kind == .cash }
        guard !cashWallets.isEmpty else { return }

        let nextMorning = nextLocalMorning(after: referenceDate, hour: 9, minute: 0)

        for wallet in cashWallets {
            let balance = TransactionLogic.effectiveBalance(
                for: TransactionWalletSnapshot(
                    id: wallet.id,
                    kind: wallet.kind,
                    openingBalanceMinor: wallet.openingBalanceMinor
                ),
                records: transactionRecords
            )

            guard balance <= 0 else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: nextMorning)
            components.hour = 9
            components.minute = 0

            let content = UNMutableNotificationContent()
            content.title = mistiaLocalized(
                vi: "Ví sắp hết tiền",
                en: "Low wallet balance",
                ja: "残高が少ない"
            )
            content.body = "\(wallet.name) — \(balance.formattedCurrency(code: wallet.currencyCode))"
            content.sound = .default
            content.categoryIdentifier = reminderCategoryID

            let identifier = "mistia.reminder.wallet.\(wallet.id.uuidString.lowercased())"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await UNUserNotificationCenter.current().add(request)

            upsertInboxRecord(
                modelContext: modelContext,
                key: identifier,
                createdAt: nextMorning,
                title: content.title,
                body: content.body,
                kind: .lowWallet,
                source: .localReminder
            )
        }
    }

    private static func nextLocalMorning(
        after date: Date,
        hour: Int,
        minute: Int
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        var components = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        components.hour = hour
        components.minute = minute
        let todayMorning = calendar.date(from: components) ?? startOfDay
        if todayMorning > date {
            return todayMorning
        }
        return calendar.date(byAdding: .day, value: 1, to: todayMorning) ?? todayMorning
    }

    private static func upsertInboxRecord(
        modelContext: ModelContext,
        key: String,
        createdAt: Date,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        source: MistiaAppNotificationSource
    ) {
        let existing = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate { $0.key == key }
            )
        ))?.first

        if let existing {
            existing.updatedAt = .now
            existing.createdAt = createdAt
            existing.title = title
            existing.body = body
            existing.kind = kind
            existing.source = source
        } else {
            modelContext.insert(AppNotificationRecord(
                key: key,
                createdAt: createdAt,
                updatedAt: .now,
                title: title,
                body: body,
                kind: kind,
                source: source,
                isRead: false,
                actionRoute: nil
            ))
        }

        try? modelContext.save()
    }
}

