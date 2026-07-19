import Foundation
import SwiftData

@MainActor
struct MistiaRecurringBillNotificationBatch {
    private static let billKinds: Set<MistiaAppNotificationKind> = [
        .billPaymentRequired,
        .billAutoPaymentSucceeded,
        .billAutoPaymentFailed,
        .billOverdue
    ]
    private static let resolvedKinds: Set<MistiaAppNotificationKind> = [
        .billPaymentRequired,
        .billAutoPaymentFailed,
        .billOverdue
    ]

    private let modelContext: ModelContext
    private var recordsByKey: [String: AppNotificationRecord]
    private var didMutate: Bool

    init(
        modelContext: ModelContext,
        billOwnerMap: [UUID: UUID],
        activeUserID: UUID,
        pausedBillIDs: Set<UUID>,
        now: Date = .now
    ) {
        self.modelContext = modelContext

        let billResourceTypeRawValue = MistiaFamilyNotificationResourceType.bill.rawValue
        let localReminderSourceRawValue = MistiaAppNotificationSource.localReminder.rawValue
        let systemSourceRawValue = MistiaAppNotificationSource.system.rawValue
        let rows = (try? modelContext.fetch(
            FetchDescriptor<AppNotificationRecord>(
                predicate: #Predicate<AppNotificationRecord> { row in
                    row.resourceTypeRawValue == billResourceTypeRawValue
                        && (
                            row.sourceRawValue == localReminderSourceRawValue
                                || row.sourceRawValue == systemSourceRawValue
                        )
                }
            )
        )) ?? []

        var preparedRecordsByKey: [String: AppNotificationRecord] = [:]
        preparedRecordsByKey.reserveCapacity(rows.count)
        var preparedDidMutate = false

        for row in rows {
            if Self.billKinds.contains(row.kind),
               let billID = row.resourceID,
               let ownerUserID = billOwnerMap[billID],
               ownerUserID != activeUserID {
                modelContext.delete(row)
                preparedDidMutate = true
                continue
            }

            if let billID = row.resourceID,
               pausedBillIDs.contains(billID),
               Self.resolvedKinds.contains(row.kind) {
                row.isRead = true
                row.readAt = row.readAt ?? now
                row.actionState = .resolved
                row.updatedAt = now
                preparedDidMutate = true
            }

            preparedRecordsByKey[row.key] = row
        }

        recordsByKey = preparedRecordsByKey
        didMutate = preparedDidMutate
    }

    mutating func upsert(
        key: String,
        title: String,
        body: String,
        kind: MistiaAppNotificationKind,
        recipientUserID: UUID,
        billID: UUID,
        metadataJSON: String?,
        forceUnread: Bool,
        now: Date = .now
    ) {
        if let existing = recordsByKey[key] {
            existing.title = title
            existing.body = body
            existing.kind = kind
            existing.source = .system
            existing.recipientUserID = recipientUserID
            existing.resourceType = .bill
            existing.resourceID = billID
            existing.metadataJSON = metadataJSON
            existing.updatedAt = now
            if forceUnread {
                existing.createdAt = now
                existing.isRead = false
                existing.readAt = nil
            }
        } else {
            let record = AppNotificationRecord(
                key: key,
                createdAt: now,
                updatedAt: now,
                title: title,
                body: body,
                kind: kind,
                source: .system,
                isRead: false,
                recipientUserID: recipientUserID,
                resourceType: .bill,
                resourceID: billID,
                metadataJSON: metadataJSON
            )
            modelContext.insert(record)
            recordsByKey[key] = record
        }
        didMutate = true
    }

    func saveIfNeeded() {
        guard didMutate else { return }
        try? modelContext.save()
    }
}
