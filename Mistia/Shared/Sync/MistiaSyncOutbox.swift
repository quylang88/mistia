import Foundation

nonisolated enum MistiaSyncEntity: String, CaseIterable, Codable, Hashable, Sendable {
    case wallet = "ledger_wallets"
    case creditCardProfile = "credit_card_profiles"
    case category = "transaction_categories"
    case settlementGroup = "settlement_groups"
    case settlementParticipant = "settlement_participants"
    case transaction = "ledger_transactions"
    case budgetPlan = "budget_plans"
    case savingsGoal = "savings_goals"
    case recurringBillPlan = "recurring_bill_plans"
    case installmentPlan = "installment_plans"
    case dueOccurrenceRecord = "due_occurrence_records"
    case investmentChannel = "investment_channels"
    case investmentAsset = "investment_assets"
    case investmentTrade = "investment_trades"
    case investmentValuation = "investment_valuations"
    case investmentPosting = "investment_wallet_postings"

    var tableName: String { rawValue }

    var pushPriority: Int {
        switch self {
        case .category: 10
        case .wallet: 20
        case .creditCardProfile: 30
        case .settlementGroup: 35
        case .settlementParticipant: 36
        case .transaction: 40
        case .budgetPlan: 50
        case .savingsGoal: 60
        case .recurringBillPlan: 70
        case .installmentPlan: 80
        case .dueOccurrenceRecord: 90
        case .investmentChannel: 100
        case .investmentAsset: 110
        case .investmentTrade: 120
        case .investmentValuation: 130
        case .investmentPosting: 140
        }
    }
}

nonisolated enum MistiaSyncMutationKind: String, Codable, Hashable, Sendable {
    case upsert
    case delete
}

nonisolated struct MistiaSyncMutation: Codable, Hashable, Identifiable, Sendable {
    let entity: MistiaSyncEntity
    let recordID: UUID
    let subjectUserID: UUID
    let kind: MistiaSyncMutationKind
    let modifiedAt: Date
    let baseVersion: Int64
    let deviceID: UUID

    init(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        kind: MistiaSyncMutationKind,
        modifiedAt: Date,
        baseVersion: Int64 = 0,
        deviceID: UUID = MistiaSyncDeviceIdentity.current()
    ) {
        self.entity = entity
        self.recordID = recordID
        self.subjectUserID = subjectUserID
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.baseVersion = baseVersion
        self.deviceID = deviceID
    }

    var id: String {
        "\(entity.rawValue):\(recordID.uuidString)"
    }

    private enum CodingKeys: String, CodingKey {
        case entity
        case recordID = "recordId"
        case subjectUserID = "subjectUserId"
        case kind
        case modifiedAt
        case baseVersion
        case deviceID = "deviceId"
    }
}

nonisolated private struct MistiaSyncMutationStorageKey: Hashable {
    let entity: MistiaSyncEntity
    let recordID: UUID

    init(entity: MistiaSyncEntity, recordID: UUID) {
        self.entity = entity
        self.recordID = recordID
    }

    init(_ mutation: MistiaSyncMutation) {
        self.init(entity: mutation.entity, recordID: mutation.recordID)
    }
}

nonisolated final class MistiaSyncOutbox {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder.mistiaSyncEncoder
    private let decoder = JSONDecoder.mistiaSyncDecoder
    private var cachedData: Data?
    private var cachedMutations: [MistiaSyncMutation]?

    init(
        defaults: UserDefaults = .standard,
        key: String = "mistia.sync.outbox"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var allMutations: [MistiaSyncMutation] {
        load()
    }

    func enqueue(_ mutation: MistiaSyncMutation) {
        let mutationKey = MistiaSyncMutationStorageKey(mutation)
        var mutations = load()
        mutations.removeAll { MistiaSyncMutationStorageKey($0) == mutationKey }
        mutations.append(mutation)
        save(mutations.sorted { $0.modifiedAt < $1.modifiedAt })
    }

    func enqueue(_ mutations: [MistiaSyncMutation]) {
        guard !mutations.isEmpty else { return }

        let incoming = deduplicatedIncomingMutations(mutations)
        var incomingKeys: Set<MistiaSyncMutationStorageKey> = []
        incomingKeys.reserveCapacity(incoming.count)
        for mutation in incoming {
            incomingKeys.insert(MistiaSyncMutationStorageKey(mutation))
        }

        var stored = load()
        stored.removeAll { incomingKeys.contains(MistiaSyncMutationStorageKey($0)) }
        stored.reserveCapacity(stored.count + incoming.count)
        stored.append(contentsOf: incoming)

        save(stored.sorted { $0.modifiedAt < $1.modifiedAt })
    }

    func remove(_ mutation: MistiaSyncMutation) {
        remove(entity: mutation.entity, recordID: mutation.recordID)
    }

    func remove(entity: MistiaSyncEntity, recordID: UUID) {
        let mutationKey = MistiaSyncMutationStorageKey(entity: entity, recordID: recordID)
        save(load().filter { MistiaSyncMutationStorageKey($0) != mutationKey })
    }

    func clear() {
        defaults.removeObject(forKey: key)
        cachedData = nil
        cachedMutations = []
    }

    func contains(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        let mutationKey = MistiaSyncMutationStorageKey(entity: entity, recordID: recordID)
        return load().contains { MistiaSyncMutationStorageKey($0) == mutationKey }
    }

    func rewriteRecordIDs(entity: MistiaSyncEntity, mappings: [UUID: UUID]) {
        guard !mappings.isEmpty else { return }

        let stored = load()
        var rewrittenByKey: [MistiaSyncMutationStorageKey: MistiaSyncMutation] = [:]
        rewrittenByKey.reserveCapacity(stored.count)
        for mutation in stored {
            guard mutation.entity == entity, let replacementID = mappings[mutation.recordID] else {
                rewrittenByKey[MistiaSyncMutationStorageKey(mutation)] = mutation
                continue
            }

            let rewritten = MistiaSyncMutation(
                entity: mutation.entity,
                recordID: replacementID,
                subjectUserID: mutation.subjectUserID,
                kind: mutation.kind,
                modifiedAt: mutation.modifiedAt,
                baseVersion: mutation.baseVersion,
                deviceID: mutation.deviceID
            )
            let rewrittenKey = MistiaSyncMutationStorageKey(rewritten)

            if let existing = rewrittenByKey[rewrittenKey] {
                rewrittenByKey[rewrittenKey] = preferredMutation(existing, rewritten)
            } else {
                rewrittenByKey[rewrittenKey] = rewritten
            }
        }

        save(rewrittenByKey.values.sorted { $0.modifiedAt < $1.modifiedAt })
    }

    private func deduplicatedIncomingMutations(
        _ mutations: [MistiaSyncMutation]
    ) -> [MistiaSyncMutation] {
        var seenKeys: Set<MistiaSyncMutationStorageKey> = []
        seenKeys.reserveCapacity(mutations.count)
        var deduplicated: [MistiaSyncMutation] = []
        deduplicated.reserveCapacity(mutations.count)

        for mutation in mutations.reversed() {
            guard seenKeys.insert(MistiaSyncMutationStorageKey(mutation)).inserted else {
                continue
            }
            deduplicated.append(mutation)
        }

        deduplicated.reverse()
        return deduplicated
    }

    private func load() -> [MistiaSyncMutation] {
        guard let data = defaults.data(forKey: key) else {
            cachedData = nil
            cachedMutations = []
            return []
        }

        if cachedData == data, let cachedMutations {
            return cachedMutations
        }

        let mutations = (try? decoder.decode([MistiaSyncMutation].self, from: data)) ?? []
        cachedData = data
        cachedMutations = mutations
        return mutations
    }

    private func save(_ mutations: [MistiaSyncMutation]) {
        if mutations.isEmpty {
            defaults.removeObject(forKey: key)
            cachedData = nil
            cachedMutations = []
            return
        }

        if let data = try? encoder.encode(mutations) {
            defaults.set(data, forKey: key)
            cachedData = data
            cachedMutations = mutations
        }
    }

    private func preferredMutation(
        _ lhs: MistiaSyncMutation,
        _ rhs: MistiaSyncMutation
    ) -> MistiaSyncMutation {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt ? lhs : rhs
        }

        if lhs.kind != rhs.kind {
            return rhs.kind == .delete ? rhs : lhs
        }

        return lhs.baseVersion >= rhs.baseVersion ? lhs : rhs
    }
}
