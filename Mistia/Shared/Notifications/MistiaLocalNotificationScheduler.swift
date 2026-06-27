import Foundation
import SwiftData
import UserNotifications

@MainActor
enum MistiaLocalNotificationScheduler {
    private static var calendar: Calendar { MistiaCalendar.current }
    private static let reminderCategoryID = "mistia.reminders"

    static func rescheduleReminders(
        snapshot: MistiaDueMaintenanceSnapshot,
        modelContext: ModelContext,
        recipientUserID: UUID?,
        referenceDate: Date = .now
    ) async {
        await clearScheduledRemindersOnly()
        removeObsoleteDueSoonInboxRecords(modelContext: modelContext)
        guard MistiaNotificationPreferences.reminderEnabled(.wallets) else { return }
        guard let recipientUserID else { return }

        await requestAuthorizationIfNeeded()
        let existingLowWalletRows = existingLowWalletInboxRecords(modelContext: modelContext)
        var existingLowWalletRecordsByKey = Dictionary(
            existingLowWalletRows.map { ($0.key, $0) },
            uniquingKeysWith: latestNotification
        )
        let didRemoveStaleRows = removeStaleWalletReminderInboxRecords(
            activeWalletIDs: Set(snapshot.activeWallets.map(\.id)),
            walletOwnerMap: snapshot.walletOwnerMap,
            recipientUserID: recipientUserID,
            modelContext: modelContext,
            existingRows: existingLowWalletRows,
            existingRecordsByKey: &existingLowWalletRecordsByKey
        )
        let didUpsertInboxRows = await scheduleLowWalletAlerts(
            wallets: snapshot.activeWallets,
            balanceIndex: snapshot.balanceIndex,
            referenceDate: referenceDate,
            recipientUserID: recipientUserID,
            modelContext: modelContext,
            existingRecordsByKey: &existingLowWalletRecordsByKey
        )
        if didRemoveStaleRows || didUpsertInboxRows {
            try? modelContext.save()
            MistiaNotificationStore.updateAppBadgeCount(in: modelContext, userID: recipientUserID)
        }
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
        let dueSoonKindRawValue = MistiaAppNotificationKind.dueSoon.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        let rows = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.kindRawValue == dueSoonKindRawValue
                        || row.sourceRawValue == localReminderSourceRawValue
                        || row.sourceRawValue == systemSourceRawValue
                }
            )
        )) ?? []
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
        balanceIndex: TransactionWalletBalanceIndex,
        referenceDate: Date,
        recipientUserID: UUID,
        modelContext: ModelContext,
        existingRecordsByKey: inout [String: AppNotificationRecord]
    ) async -> Bool {
        // Phase 1 heuristic: only notify when a cash wallet balance is <= 0.
        let cashWallets = wallets.filter { $0.kind == .cash }
        guard !cashWallets.isEmpty else { return false }

        let nextMorning = nextLocalMorning(after: referenceDate, hour: 9, minute: 0)
        let notificationCenter = UNUserNotificationCenter.current()
        var inboxPayloads: [LocalReminderInboxPayload] = []
        inboxPayloads.reserveCapacity(cashWallets.count)

        for wallet in cashWallets {
            let balance = balanceIndex.balance(
                for: TransactionWalletSnapshot(
                    id: wallet.id,
                    kind: wallet.kind,
                    openingBalanceMinor: wallet.openingBalanceMinor
                )
            )

            guard balance <= 0 else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: nextMorning)
            components.hour = 9
            components.minute = 0

            let content = UNMutableNotificationContent()
            content.title = L10n.shared.notifications.mistialocalnotificationscheduler.lowWalletBalance
            content.body = "\(wallet.name) — \(balance.formattedCurrency(code: wallet.currencyCode))"
            content.sound = .default
            content.categoryIdentifier = reminderCategoryID

            let identifier = "mistia.reminder.wallet.\(wallet.id.uuidString.lowercased())"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await notificationCenter.add(request)

            inboxPayloads.append(LocalReminderInboxPayload(
                key: identifier,
                createdAt: nextMorning,
                title: content.title,
                body: content.body,
                kind: .lowWallet,
                source: .localReminder,
                recipientUserID: recipientUserID,
                resourceType: .wallet,
                resourceID: wallet.id
            ))
        }

        return upsertInboxRecords(
            modelContext: modelContext,
            payloads: inboxPayloads,
            existingRecordsByKey: &existingRecordsByKey
        )
    }

    @discardableResult
    private static func upsertInboxRecords(
        modelContext: ModelContext,
        payloads: [LocalReminderInboxPayload],
        existingRecordsByKey: inout [String: AppNotificationRecord]
    ) -> Bool {
        guard !payloads.isEmpty else { return false }

        var didMutate = false
        for payload in payloads {
            didMutate = upsertInboxRecord(
                modelContext: modelContext,
                payload: payload,
                existingRecordsByKey: &existingRecordsByKey
            ) || didMutate
        }

        return didMutate
    }

    private static func existingLowWalletInboxRecords(
        modelContext: ModelContext
    ) -> [AppNotificationRecord] {
        let lowWalletKindRawValue = MistiaAppNotificationKind.lowWallet.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        return (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.kindRawValue == lowWalletKindRawValue
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )) ?? []
    }

    @discardableResult
    private static func upsertInboxRecord(
        modelContext: ModelContext,
        payload: LocalReminderInboxPayload,
        existingRecordsByKey: inout [String: AppNotificationRecord]
    ) -> Bool {
        if let existing = existingRecordsByKey[payload.key] {
            existing.updatedAt = .now
            existing.createdAt = payload.createdAt
            existing.title = payload.title
            existing.body = payload.body
            existing.kind = payload.kind
            existing.source = payload.source
            existing.recipientUserID = payload.recipientUserID
            existing.resourceType = payload.resourceType
            existing.resourceID = payload.resourceID
            existing.metadataJSON = payload.metadataJSON
            return true
        }

        let row = AppNotificationRecord(
            key: payload.key,
            createdAt: payload.createdAt,
            updatedAt: .now,
            title: payload.title,
            body: payload.body,
            kind: payload.kind,
            source: payload.source,
            isRead: false,
            actionRoute: nil,
            recipientUserID: payload.recipientUserID,
            resourceType: payload.resourceType,
            resourceID: payload.resourceID,
            metadataJSON: payload.metadataJSON
        )
        modelContext.insert(row)
        existingRecordsByKey[payload.key] = row
        return true
    }

    private static func removeStaleWalletReminderInboxRecords(
        activeWalletIDs: Set<UUID>,
        walletOwnerMap: [UUID: UUID],
        recipientUserID: UUID,
        modelContext: ModelContext,
        existingRows: [AppNotificationRecord],
        existingRecordsByKey: inout [String: AppNotificationRecord]
    ) -> Bool {
        var didDelete = false

        for row in existingRows {
            let walletID = row.resourceID ?? walletIDFromReminderKey(row.key)
            guard let walletID else { continue }
            let belongsToOtherUser = walletOwnerMap[walletID].map { $0 != recipientUserID } ?? false
            if belongsToOtherUser || !activeWalletIDs.contains(walletID) {
                modelContext.delete(row)
                if existingRecordsByKey[row.key]?.id == row.id {
                    existingRecordsByKey.removeValue(forKey: row.key)
                }
                didDelete = true
            }
        }

        return didDelete
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

    private static func latestNotification(
        _ lhs: AppNotificationRecord,
        _ rhs: AppNotificationRecord
    ) -> AppNotificationRecord {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }
}

private struct LocalReminderInboxPayload {
    let key: String
    let createdAt: Date
    let title: String
    let body: String
    let kind: MistiaAppNotificationKind
    let source: MistiaAppNotificationSource
    let recipientUserID: UUID
    let resourceType: MistiaFamilyNotificationResourceType?
    let resourceID: UUID?
    var metadataJSON: String? = nil
}
