import Foundation
import SwiftData

@Model
final class OwnedRecordScope {
    @Attribute(.unique) var id: String
    var entityRawValue: String
    var recordID: UUID
    var ownerUserID: UUID
    var updatedAt: Date

    init(
        entity: MistiaSyncEntity,
        recordID: UUID,
        ownerUserID: UUID,
        updatedAt: Date = .now
    ) {
        self.id = OwnedRecordScope.scopeID(entity: entity, recordID: recordID)
        self.entityRawValue = entity.rawValue
        self.recordID = recordID
        self.ownerUserID = ownerUserID
        self.updatedAt = updatedAt
    }

    var entity: MistiaSyncEntity {
        MistiaSyncEntity(rawValue: entityRawValue) ?? .transaction
    }

    static func scopeID(entity: MistiaSyncEntity, recordID: UUID) -> String {
        "\(entity.rawValue):\(recordID.uuidString.lowercased())"
    }
}

protocol MistiaOwnedRecord {
    var id: UUID { get }
}

extension LedgerWallet: MistiaOwnedRecord {}
extension CreditCardProfile: MistiaOwnedRecord {}
extension TransactionCategory: MistiaOwnedRecord {}
extension LedgerTransaction: MistiaOwnedRecord {}
extension BudgetPlan: MistiaOwnedRecord {}
extension SavingsGoal: MistiaOwnedRecord {}
extension RecurringBillPlan: MistiaOwnedRecord {}
extension InstallmentPlan: MistiaOwnedRecord {}
extension DueOccurrenceRecord: MistiaOwnedRecord {}

enum MistiaRecordOwnershipStore {
    static func ownerMap(
        from scopes: [OwnedRecordScope],
        entity: MistiaSyncEntity
    ) -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: scopes
                .filter { $0.entity == entity }
                .map { ($0.recordID, $0.ownerUserID) }
        )
    }

    static func ownerUserID(
        entity: MistiaSyncEntity,
        recordID: UUID,
        in container: ModelContainer
    ) throws -> UUID? {
        let context = ModelContext(container)
        return try scope(
            entity: entity,
            recordID: recordID,
            in: context
        )?.ownerUserID
    }

    static func upsert(
        entity: MistiaSyncEntity,
        recordID: UUID,
        ownerUserID: UUID,
        updatedAt: Date = .now,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        try upsert(
            entity: entity,
            recordID: recordID,
            ownerUserID: ownerUserID,
            updatedAt: updatedAt,
            context: context
        )
        try context.save()
    }

    static func upsert(
        entity: MistiaSyncEntity,
        recordID: UUID,
        ownerUserID: UUID,
        updatedAt: Date = .now,
        context: ModelContext
    ) throws {
        let existing = try scope(entity: entity, recordID: recordID, in: context)
        let scope = existing ?? OwnedRecordScope(
            entity: entity,
            recordID: recordID,
            ownerUserID: ownerUserID,
            updatedAt: updatedAt
        )

        if existing == nil {
            context.insert(scope)
        }

        scope.entityRawValue = entity.rawValue
        scope.recordID = recordID
        scope.ownerUserID = ownerUserID
        scope.updatedAt = updatedAt
    }

    static func remove(
        entity: MistiaSyncEntity,
        recordID: UUID,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        if let existing = try scope(entity: entity, recordID: recordID, in: context) {
            context.delete(existing)
            try context.save()
        }
    }

    static func ensureMissingOwnershipClaims(
        for ownerUserID: UUID,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let existingScopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let existingKeys = Set(existingScopes.map(\.id))

        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<LedgerWallet>()),
            entity: .wallet,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<CreditCardProfile>()),
            entity: .creditCardProfile,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<TransactionCategory>()),
            entity: .category,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<LedgerTransaction>()),
            entity: .transaction,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<BudgetPlan>()),
            entity: .budgetPlan,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<SavingsGoal>()),
            entity: .savingsGoal,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<RecurringBillPlan>()),
            entity: .recurringBillPlan,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<InstallmentPlan>()),
            entity: .installmentPlan,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )
        try insertMissingScopes(
            records: context.fetch(FetchDescriptor<DueOccurrenceRecord>()),
            entity: .dueOccurrenceRecord,
            ownerUserID: ownerUserID,
            existingKeys: existingKeys,
            context: context
        )

        try context.save()
    }

    static func visibleRecords<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        ownerMap: [UUID: UUID],
        subjectUserID: UUID?,
        signedInUserID: UUID?
    ) -> [Record] {
        guard let subjectUserID else {
            return records
        }

        return records.filter { record in
            guard let ownerUserID = ownerMap[record.id] else {
                return signedInUserID == nil || subjectUserID == signedInUserID
            }

            return ownerUserID == subjectUserID
        }
    }

    private static func scope(
        entity: MistiaSyncEntity,
        recordID: UUID,
        in context: ModelContext
    ) throws -> OwnedRecordScope? {
        let scopeID = OwnedRecordScope.scopeID(entity: entity, recordID: recordID)
        let descriptor = FetchDescriptor<OwnedRecordScope>(
            predicate: #Predicate<OwnedRecordScope> { scope in
                scope.id == scopeID
            }
        )
        return try context.fetch(descriptor).first
    }

    private static func insertMissingScopes<Record: MistiaOwnedRecord>(
        records: [Record],
        entity: MistiaSyncEntity,
        ownerUserID: UUID,
        existingKeys: Set<String>,
        context: ModelContext
    ) throws {
        for record in records {
            let scopeID = OwnedRecordScope.scopeID(entity: entity, recordID: record.id)
            guard !existingKeys.contains(scopeID) else { continue }
            context.insert(
                OwnedRecordScope(
                    entity: entity,
                    recordID: record.id,
                    ownerUserID: ownerUserID
                )
            )
        }
    }
}
