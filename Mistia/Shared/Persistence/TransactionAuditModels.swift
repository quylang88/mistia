import Foundation
import SwiftData

@Model
nonisolated final class TransactionAuditRecord {
    @Attribute(.unique) var transactionID: UUID
    var createdByUserID: UUID
    var lastModifiedByUserID: UUID
    var updatedAt: Date

    init(
        transactionID: UUID,
        createdByUserID: UUID,
        lastModifiedByUserID: UUID,
        updatedAt: Date = .now
    ) {
        self.transactionID = transactionID
        self.createdByUserID = createdByUserID
        self.lastModifiedByUserID = lastModifiedByUserID
        self.updatedAt = updatedAt
    }
}

nonisolated enum TransactionAuditStore {
    static func auditMap(
        from records: [TransactionAuditRecord]
    ) -> [UUID: TransactionAuditRecord] {
        Dictionary(records.map { ($0.transactionID, $0) }, uniquingKeysWith: latestAuditRecord)
    }

    nonisolated private static func latestAuditRecord(
        _ lhs: TransactionAuditRecord,
        _ rhs: TransactionAuditRecord
    ) -> TransactionAuditRecord {
        lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    static func fetch(
        transactionID: UUID,
        context: ModelContext
    ) throws -> TransactionAuditRecord? {
        let descriptor = FetchDescriptor<TransactionAuditRecord>(
            predicate: #Predicate<TransactionAuditRecord> { record in
                record.transactionID == transactionID
            }
        )
        return try context.fetch(descriptor).first
    }

    static func upsert(
        transactionID: UUID,
        createdByUserID: UUID,
        lastModifiedByUserID: UUID,
        updatedAt: Date,
        context: ModelContext
    ) throws {
        let record = try fetch(transactionID: transactionID, context: context)
            ?? TransactionAuditRecord(
                transactionID: transactionID,
                createdByUserID: createdByUserID,
                lastModifiedByUserID: lastModifiedByUserID,
                updatedAt: updatedAt
            )

        if record.modelContext == nil {
            context.insert(record)
        }

        record.createdByUserID = createdByUserID
        record.lastModifiedByUserID = lastModifiedByUserID
        record.updatedAt = updatedAt
    }

    static func touch(
        transactionID: UUID,
        actorUserID: UUID,
        fallbackCreatedByUserID: UUID,
        updatedAt: Date,
        context: ModelContext
    ) throws {
        let existing = try fetch(transactionID: transactionID, context: context)
        try upsert(
            transactionID: transactionID,
            createdByUserID: existing?.createdByUserID ?? fallbackCreatedByUserID,
            lastModifiedByUserID: actorUserID,
            updatedAt: updatedAt,
            context: context
        )
    }

    static func resolveOwnerUserID(
        forWalletID walletID: UUID?,
        ownershipScopes: [OwnedRecordScope]
    ) -> UUID? {
        guard let walletID else { return nil }
        return ownershipScopes.first {
            $0.entity == .wallet && $0.recordID == walletID
        }?.ownerUserID
    }
}
