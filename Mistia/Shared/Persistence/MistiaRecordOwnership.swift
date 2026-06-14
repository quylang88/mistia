import Foundation
import SwiftData

@Model
nonisolated final class OwnedRecordScope {
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

nonisolated protocol MistiaOwnedRecord {
    var id: UUID { get }
}

nonisolated extension LedgerWallet: MistiaOwnedRecord {}
nonisolated extension CreditCardProfile: MistiaOwnedRecord {}
nonisolated extension TransactionCategory: MistiaOwnedRecord {}
nonisolated extension SettlementGroup: MistiaOwnedRecord {}
nonisolated extension SettlementParticipant: MistiaOwnedRecord {}
nonisolated extension LedgerTransaction: MistiaOwnedRecord {}
nonisolated extension BudgetPlan: MistiaOwnedRecord {}
nonisolated extension SavingsGoal: MistiaOwnedRecord {}
nonisolated extension RecurringBillPlan: MistiaOwnedRecord {}
nonisolated extension InstallmentPlan: MistiaOwnedRecord {}
nonisolated extension DueOccurrenceRecord: MistiaOwnedRecord {}

nonisolated struct MistiaRecordOwnerMaps {
    private let ownersByEntity: [MistiaSyncEntity: [UUID: UUID]]

    init(_ ownersByEntity: [MistiaSyncEntity: [UUID: UUID]]) {
        self.ownersByEntity = ownersByEntity
    }

    subscript(entity: MistiaSyncEntity) -> [UUID: UUID] {
        ownersByEntity[entity] ?? [:]
    }
}

nonisolated enum MistiaRecordOwnershipStore {
    static func ownerMap(
        from scopes: [OwnedRecordScope],
        entity: MistiaSyncEntity
    ) -> [UUID: UUID] {
        ownerMaps(from: scopes, entities: [entity])[entity]
    }

    static func ownerMaps(
        from scopes: [OwnedRecordScope],
        entities requestedEntities: Set<MistiaSyncEntity>? = nil
    ) -> MistiaRecordOwnerMaps {
        var ownersByEntity: [MistiaSyncEntity: [UUID: (ownerUserID: UUID, updatedAt: Date)]] = [:]
        ownersByEntity.reserveCapacity(requestedEntities?.count ?? 0)

        for scope in scopes {
            let entity = scope.entity
            if let requestedEntities, !requestedEntities.contains(entity) {
                continue
            }

            if let existing = ownersByEntity[entity]?[scope.recordID],
               existing.updatedAt > scope.updatedAt {
                continue
            }
            ownersByEntity[entity, default: [:]][scope.recordID] = (scope.ownerUserID, scope.updatedAt)
        }

        var maps: [MistiaSyncEntity: [UUID: UUID]] = [:]
        maps.reserveCapacity(ownersByEntity.count)
        for (entity, ownersByRecordID) in ownersByEntity {
            var ownerMap: [UUID: UUID] = [:]
            ownerMap.reserveCapacity(ownersByRecordID.count)
            for (recordID, owner) in ownersByRecordID {
                ownerMap[recordID] = owner.ownerUserID
            }
            maps[entity] = ownerMap
        }

        return MistiaRecordOwnerMaps(maps)
    }

    @discardableResult
    static func reconcileDuplicateScopes(
        in context: ModelContext
    ) throws -> Bool {
        let scopes = try context.fetch(FetchDescriptor<OwnedRecordScope>())
        let groupedScopes = Dictionary(grouping: scopes) { scope in
            OwnedRecordScope.scopeID(entity: scope.entity, recordID: scope.recordID)
        }
        var didMutate = false

        for (scopeID, group) in groupedScopes where group.count > 1 {
            let preferred = group.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.id < rhs.id
            } ?? group[0]

            if preferred.id != scopeID {
                preferred.id = scopeID
                didMutate = true
            }

            for duplicate in group where duplicate !== preferred {
                context.delete(duplicate)
                didMutate = true
            }
        }

        if didMutate {
            try context.save()
        }

        return didMutate
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
        try remove(entity: entity, recordID: recordID, context: context)
        try context.save()
    }

    static func remove(
        entity: MistiaSyncEntity,
        recordID: UUID,
        context: ModelContext
    ) throws {
        if let existing = try scope(entity: entity, recordID: recordID, in: context) {
            context.delete(existing)
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
