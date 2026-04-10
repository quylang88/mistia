import Foundation

enum MistiaSyncEntity: String, CaseIterable, Codable, Hashable {
    case wallet = "ledger_wallets"
    case creditCardProfile = "credit_card_profiles"
    case category = "transaction_categories"
    case transaction = "ledger_transactions"
    case budgetPlan = "budget_plans"
    case savingsGoal = "savings_goals"
    case recurringBillPlan = "recurring_bill_plans"
    case installmentPlan = "installment_plans"
    case dueOccurrenceRecord = "due_occurrence_records"

    var tableName: String { rawValue }
}

enum MistiaSyncMutationKind: String, Codable, Hashable {
    case upsert
    case delete
}

struct MistiaSyncMutation: Codable, Hashable, Identifiable {
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
}

@MainActor
final class MistiaSyncOutbox {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder.mistiaSyncEncoder
    private let decoder = JSONDecoder.mistiaSyncDecoder

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
        var mutations = load()
        mutations.removeAll { $0.entity == mutation.entity && $0.recordID == mutation.recordID }
        mutations.append(mutation)
        save(mutations.sorted { $0.modifiedAt < $1.modifiedAt })
    }

    func enqueue(_ mutations: [MistiaSyncMutation]) {
        guard !mutations.isEmpty else { return }

        var stored = load()
        for mutation in mutations {
            stored.removeAll { $0.entity == mutation.entity && $0.recordID == mutation.recordID }
            stored.append(mutation)
        }

        save(stored.sorted { $0.modifiedAt < $1.modifiedAt })
    }

    func remove(_ mutation: MistiaSyncMutation) {
        save(load().filter { $0.id != mutation.id })
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func contains(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        load().contains { $0.entity == entity && $0.recordID == recordID }
    }

    private func load() -> [MistiaSyncMutation] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? decoder.decode([MistiaSyncMutation].self, from: data)) ?? []
    }

    private func save(_ mutations: [MistiaSyncMutation]) {
        if mutations.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }

        if let data = try? encoder.encode(mutations) {
            defaults.set(data, forKey: key)
        }
    }
}
