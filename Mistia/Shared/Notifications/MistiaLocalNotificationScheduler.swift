import Foundation
import SwiftData
import UserNotifications

@MainActor
enum MistiaLocalNotificationScheduler {
    private static var calendar: Calendar { MistiaCalendar.current }
    private static let reminderCategoryID = "mistia.reminders"

    static func rescheduleReminders(
        modelContext: ModelContext,
        recipientUserID: UUID?,
        referenceDate: Date = .now
    ) async {
        await clearScheduledRemindersOnly()
        removeObsoleteDueSoonInboxRecords(modelContext: modelContext)
        guard MistiaNotificationPreferences.reminderEnabled(.wallets) else { return }
        guard let recipientUserID else { return }

        await requestAuthorizationIfNeeded()

        let storedWallets = (try? modelContext.fetch(
            FetchDescriptor<LedgerWallet>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let scopes = (try? modelContext.fetch(FetchDescriptor<OwnedRecordScope>())) ?? []
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .wallet)
        let wallets = storedWallets.filter {
            (walletOwnerMap[$0.id] ?? recipientUserID) == recipientUserID
        }
        removeStaleWalletReminderInboxRecords(
            activeWalletIDs: Set(wallets.map(\.id)),
            walletOwnerMap: walletOwnerMap,
            recipientUserID: recipientUserID,
            modelContext: modelContext
        )

        let storedTransactions = (try? modelContext.fetch(
            FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }
            )
        )) ?? []
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: scopes, entity: .transaction)
        let transactions = storedTransactions.filter {
            let walletOwnerUserID = $0.sourceWallet.flatMap { walletOwnerMap[$0.id] }
                ?? $0.destinationWallet.flatMap { walletOwnerMap[$0.id] }
            let ownerUserID = transactionOwnerMap[$0.id] ?? walletOwnerUserID ?? recipientUserID
            return ownerUserID == recipientUserID
        }

        let transactionRecords = transactions.map { $0.planningRecordSnapshot }
        await scheduleLowWalletAlerts(
            wallets: wallets,
            transactionRecords: transactionRecords,
            referenceDate: referenceDate,
            recipientUserID: recipientUserID,
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

    private static func removeObsoleteDueSoonInboxRecords(modelContext: ModelContext) {
        let rows = (try? modelContext.fetch(FetchDescriptor<AppNotificationRecord>())) ?? []
        let obsoleteRows = rows.filter { row in
            row.kind == .dueSoon || row.key.hasPrefix("mistia.reminder.due.")
        }

        guard !obsoleteRows.isEmpty else { return }
        for row in obsoleteRows {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }

    private static func scheduleLowWalletAlerts(
        wallets: [LedgerWallet],
        transactionRecords: [TransactionRecordSnapshot],
        referenceDate: Date,
        recipientUserID: UUID,
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
                source: .localReminder,
                recipientUserID: recipientUserID,
                resourceType: .wallet,
                resourceID: wallet.id
            )
        }
    }

    private static func removeStaleWalletReminderInboxRecords(
        activeWalletIDs: Set<UUID>,
        walletOwnerMap: [UUID: UUID],
        recipientUserID: UUID,
        modelContext: ModelContext
    ) {
        let rows = (try? modelContext.fetch(FetchDescriptor<AppNotificationRecord>())) ?? []
        var didDelete = false

        for row in rows where row.kind == .lowWallet && (row.source == .system || row.source == .localReminder) {
            let walletID = row.resourceID ?? walletIDFromReminderKey(row.key)
            guard let walletID else { continue }
            let belongsToOtherUser = walletOwnerMap[walletID].map { $0 != recipientUserID } ?? false
            if belongsToOtherUser || !activeWalletIDs.contains(walletID) {
                modelContext.delete(row)
                didDelete = true
            }
        }

        if didDelete {
            try? modelContext.save()
        }
    }

    private static func walletIDFromReminderKey(_ key: String) -> UUID? {
        let prefix = "mistia.reminder.wallet."
        guard key.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(prefix.count)))
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
        source: MistiaAppNotificationSource,
        recipientUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType? = nil,
        resourceID: UUID? = nil,
        metadataJSON: String? = nil
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
            existing.recipientUserID = recipientUserID
            existing.resourceType = resourceType
            existing.resourceID = resourceID
            existing.metadataJSON = metadataJSON
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
                actionRoute: nil,
                recipientUserID: recipientUserID,
                resourceType: resourceType,
                resourceID: resourceID,
                metadataJSON: metadataJSON
            ))
        }

        try? modelContext.save()
    }
}
