import Foundation

nonisolated struct MistiaArchiveCleanupProtectionIndex: Sendable {
    private let protectedRecordIDs: Set<String>

    init(
        queuedRecordIDs: Set<String>,
        conflictedRecordIDs: Set<String>
    ) {
        protectedRecordIDs = Set(
            queuedRecordIDs
                .union(conflictedRecordIDs)
                .lazy
                .map { $0.lowercased() }
        )
    }

    func canHardPurge(
        entity: MistiaSyncEntity,
        recordID: UUID
    ) -> Bool {
        !protectedRecordIDs.contains(Self.recordKey(entity: entity, recordID: recordID))
    }

    static func recordKey(
        entity: MistiaSyncEntity,
        recordID: UUID
    ) -> String {
        "\(entity.rawValue):\(recordID.uuidString.lowercased())"
    }
}

nonisolated enum MistiaArchiveRetention {
    static let retentionDays = 30

    static func canAutomaticallyCleanup(
        recordOwnerUserID: UUID?,
        signedInUserID: UUID
    ) -> Bool {
        recordOwnerUserID == signedInUserID
    }

    static func deletionDate(
        archivedAt: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        calendar.date(
            byAdding: .day,
            value: retentionDays,
            to: archivedAt
        ) ?? archivedAt
    }

    static func daysRemaining(
        archivedAt: Date,
        now: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> Int {
        let deletionDay = calendar.startOfDay(for: deletionDate(archivedAt: archivedAt, calendar: calendar))
        let today = calendar.startOfDay(for: now)
        let rawDays = calendar.dateComponents([.day], from: today, to: deletionDay).day ?? 0
        return max(rawDays, 0)
    }

    static func remainingDaysText(
        archivedAt: Date,
        now: Date = .now,
        calendar: Calendar = MistiaCalendar.current,
        language: MistiaAppLanguage = .current
    ) -> String {
        let days = daysRemaining(archivedAt: archivedAt, now: now, calendar: calendar)
        return L10n.management.managementarchiveditems.valueDaysUntilPermanentDelete(
            String(describing: days),
            language: language
        )
    }

    static func isUrgent(daysRemaining: Int) -> Bool {
        daysRemaining < 7
    }
}
