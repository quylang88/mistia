import Foundation

protocol MistiaRemoteRow: Codable {
    static var entity: MistiaSyncEntity { get }

    var id: UUID { get }
    var userID: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
    var syncVersion: Int64 { get set }
    var lastModifiedByDeviceID: UUID? { get set }
}

struct RemoteLedgerWallet: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .wallet

    var userID: UUID
    var id: UUID
    var name: String
    var kindRawValue: String
    var iconSymbolName: String
    var iconColorHex: String
    var currencyCode: String
    var openingBalanceMinor: Int64
    var institutionDisplayName: String?
    var institutionPresetKey: String?
    var sortOrder: Int
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case kindRawValue = "kind_raw_value"
        case iconSymbolName = "icon_symbol_name"
        case iconColorHex = "icon_color_hex"
        case currencyCode = "currency_code"
        case openingBalanceMinor = "opening_balance_minor"
        case institutionDisplayName = "institution_display_name"
        case institutionPresetKey = "institution_preset_key"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteCreditCardProfile: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .creditCardProfile

    var userID: UUID
    var id: UUID
    var issuerName: String
    var networkRawValue: String
    var last4: String
    var creditLimitMinor: Int64
    var statementClosingDay: Int
    var paymentDueDay: Int
    var notes: String?
    var walletID: UUID?
    var paymentSourceWalletID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case issuerName = "issuer_name"
        case networkRawValue = "network_raw_value"
        case last4
        case creditLimitMinor = "credit_limit_minor"
        case statementClosingDay = "statement_closing_day"
        case paymentDueDay = "payment_due_day"
        case notes
        case walletID = "wallet_id"
        case paymentSourceWalletID = "payment_source_wallet_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteTransactionCategory: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .category

    var userID: UUID
    var id: UUID
    var name: String
    var kindRawValue: String
    var iconSymbolName: String
    var iconColorHex: String
    var isFavorite: Bool
    var parentCategoryID: UUID?
    var hierarchyRoleRawValue: String?
    var systemKey: String?
    var isSystem: Bool
    var sortOrder: Int
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case kindRawValue = "kind_raw_value"
        case iconSymbolName = "icon_symbol_name"
        case iconColorHex = "icon_color_hex"
        case isFavorite = "is_favorite"
        case parentCategoryID = "parent_category_id"
        case hierarchyRoleRawValue = "hierarchy_role_raw_value"
        case systemKey = "system_key"
        case isSystem = "is_system"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kindRawValue = try container.decode(String.self, forKey: .kindRawValue)
        iconSymbolName = try container.decode(String.self, forKey: .iconSymbolName)
        iconColorHex = try container.decode(String.self, forKey: .iconColorHex)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        parentCategoryID = try container.decodeIfPresent(UUID.self, forKey: .parentCategoryID)
        hierarchyRoleRawValue = try container.decodeIfPresent(String.self, forKey: .hierarchyRoleRawValue)
        systemKey = try container.decodeIfPresent(String.self, forKey: .systemKey)
        isSystem = try container.decode(Bool.self, forKey: .isSystem)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }
}

struct RemoteLedgerTransaction: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .transaction

    var userID: UUID
    var id: UUID
    var primaryKindRawValue: String
    var transferSubtypeRawValue: String?
    var debtIntentRawValue: String?
    var entryStatusRawValue: String
    var title: String
    var note: String?
    var amountMinor: Int64
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var counterpartyName: String?
    var normalizedCounterpartyKey: String?
    var sourceWalletID: UUID?
    var destinationWalletID: UUID?
    var categoryID: UUID?
    var deletedAt: Date?
    var isArchived: Bool
    var archivedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case primaryKindRawValue = "primary_kind_raw_value"
        case transferSubtypeRawValue = "transfer_subtype_raw_value"
        case debtIntentRawValue = "debt_intent_raw_value"
        case entryStatusRawValue = "entry_status_raw_value"
        case title
        case note
        case amountMinor = "amount_minor"
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case counterpartyName = "counterparty_name"
        case normalizedCounterpartyKey = "normalized_counterparty_key"
        case sourceWalletID = "source_wallet_id"
        case destinationWalletID = "destination_wallet_id"
        case categoryID = "category_id"
        case deletedAt = "deleted_at"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteBudgetPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .budgetPlan

    var userID: UUID
    var id: UUID
    var categoryID: UUID?
    var monthAnchor: Date
    var limitMinor: Int64
    var rolloverEnabled: Bool
    var currencyCode: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case categoryID = "category_id"
        case monthAnchor = "month_anchor"
        case limitMinor = "limit_minor"
        case rolloverEnabled = "rollover_enabled"
        case currencyCode = "currency_code"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteSavingsGoal: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .savingsGoal

    var userID: UUID
    var id: UUID
    var name: String
    var iconSymbolName: String
    var targetMinor: Int64
    var currentSavedMinor: Int64
    var targetDate: Date
    var linkedWalletID: UUID?
    var currencyCode: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case iconSymbolName = "icon_symbol_name"
        case targetMinor = "target_minor"
        case currentSavedMinor = "current_saved_minor"
        case targetDate = "target_date"
        case linkedWalletID = "linked_wallet_id"
        case currencyCode = "currency_code"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteRecurringBillPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .recurringBillPlan

    var userID: UUID
    var id: UUID
    var name: String
    var iconSymbolName: String
    var categoryID: UUID?
    var amountMinor: Int64?
    var dueDay: Int
    var frequencyMonths: Int
    var paymentWalletID: UUID?
    var currencyCode: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case iconSymbolName = "icon_symbol_name"
        case categoryID = "category_id"
        case amountMinor = "amount_minor"
        case dueDay = "due_day"
        case frequencyMonths = "frequency_months"
        case paymentWalletID = "payment_wallet_id"
        case currencyCode = "currency_code"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteInstallmentPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .installmentPlan

    var userID: UUID
    var id: UUID
    var name: String
    var iconSymbolName: String
    var amountPerCycleMinor: Int64
    var dueDay: Int
    var totalCycles: Int?
    var frequencyMonths: Int
    var paymentWalletID: UUID?
    var currencyCode: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case iconSymbolName = "icon_symbol_name"
        case amountPerCycleMinor = "amount_per_cycle_minor"
        case dueDay = "due_day"
        case totalCycles = "total_cycles"
        case frequencyMonths = "frequency_months"
        case paymentWalletID = "payment_wallet_id"
        case currencyCode = "currency_code"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteDueOccurrenceRecord: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .dueOccurrenceRecord

    var userID: UUID
    var id: UUID
    var sourceKindRawValue: String
    var sourceID: UUID
    var selectedMonthKey: String
    var scheduledDate: Date
    var amountMinorSnapshot: Int64?
    var statusRawValue: String
    var paidAt: Date?
    var linkedTransactionID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case sourceKindRawValue = "source_kind_raw_value"
        case sourceID = "source_id"
        case selectedMonthKey = "selected_month_key"
        case scheduledDate = "scheduled_date"
        case amountMinorSnapshot = "amount_minor_snapshot"
        case statusRawValue = "status_raw_value"
        case paidAt = "paid_at"
        case linkedTransactionID = "linked_transaction_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct RemoteRowVersion: Codable {
    let id: UUID
    let updatedAt: Date
    let deletedAt: Date?
    let syncVersion: Int64
    let lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

struct MistiaRemoteSnapshot: Codable {
    let wallets: [RemoteLedgerWallet]
    let creditCardProfiles: [RemoteCreditCardProfile]
    let categories: [RemoteTransactionCategory]
    let transactions: [RemoteLedgerTransaction]
    let budgetPlans: [RemoteBudgetPlan]
    let savingsGoals: [RemoteSavingsGoal]
    let recurringBillPlans: [RemoteRecurringBillPlan]
    let installmentPlans: [RemoteInstallmentPlan]
    let dueOccurrences: [RemoteDueOccurrenceRecord]

    static let empty = MistiaRemoteSnapshot(
        wallets: [],
        creditCardProfiles: [],
        categories: [],
        transactions: [],
        budgetPlans: [],
        savingsGoals: [],
        recurringBillPlans: [],
        installmentPlans: [],
        dueOccurrences: []
    )

    var totalRowCount: Int {
        wallets.count
            + creditCardProfiles.count
            + categories.count
            + transactions.count
            + budgetPlans.count
            + savingsGoals.count
            + recurringBillPlans.count
            + installmentPlans.count
            + dueOccurrences.count
    }

    var activeRowCount: Int {
        activeWallets.count
            + activeCreditCardProfiles.count
            + activeCategories.count
            + activeTransactions.count
            + activeBudgetPlans.count
            + activeSavingsGoals.count
            + activeRecurringBillPlans.count
            + activeInstallmentPlans.count
            + activeDueOccurrences.count
    }

    var hasRemoteData: Bool {
        totalRowCount > 0
    }

    var activeWallets: [RemoteLedgerWallet] {
        wallets.filter { $0.deletedAt == nil }
    }

    var activeCreditCardProfiles: [RemoteCreditCardProfile] {
        creditCardProfiles.filter { $0.deletedAt == nil }
    }

    var activeCategories: [RemoteTransactionCategory] {
        categories.filter { $0.deletedAt == nil }
    }

    var activeTransactions: [RemoteLedgerTransaction] {
        transactions.filter { $0.deletedAt == nil }
    }

    var activeBudgetPlans: [RemoteBudgetPlan] {
        budgetPlans.filter { $0.deletedAt == nil }
    }

    var activeSavingsGoals: [RemoteSavingsGoal] {
        savingsGoals.filter { $0.deletedAt == nil }
    }

    var activeRecurringBillPlans: [RemoteRecurringBillPlan] {
        recurringBillPlans.filter { $0.deletedAt == nil }
    }

    var activeInstallmentPlans: [RemoteInstallmentPlan] {
        installmentPlans.filter { $0.deletedAt == nil }
    }

    var activeDueOccurrences: [RemoteDueOccurrenceRecord] {
        dueOccurrences.filter { $0.deletedAt == nil }
    }

    var fingerprint: String {
        let normalized = MistiaRemoteSnapshot(
            wallets: wallets.sorted { $0.id.uuidString < $1.id.uuidString },
            creditCardProfiles: creditCardProfiles.sorted { $0.id.uuidString < $1.id.uuidString },
            categories: categories.sorted { $0.id.uuidString < $1.id.uuidString },
            transactions: transactions.sorted { $0.id.uuidString < $1.id.uuidString },
            budgetPlans: budgetPlans.sorted { $0.id.uuidString < $1.id.uuidString },
            savingsGoals: savingsGoals.sorted { $0.id.uuidString < $1.id.uuidString },
            recurringBillPlans: recurringBillPlans.sorted { $0.id.uuidString < $1.id.uuidString },
            installmentPlans: installmentPlans.sorted { $0.id.uuidString < $1.id.uuidString },
            dueOccurrences: dueOccurrences.sorted { $0.id.uuidString < $1.id.uuidString }
        )

        let encoder = JSONEncoder.mistiaSyncEncoder
        guard let data = try? encoder.encode(normalized) else {
            return UUID().uuidString
        }
        return data.base64EncodedString()
    }
}

enum MistiaSyncUploadRecord {
    case wallet(RemoteLedgerWallet)
    case creditCardProfile(RemoteCreditCardProfile)
    case category(RemoteTransactionCategory)
    case transaction(RemoteLedgerTransaction)
    case budgetPlan(RemoteBudgetPlan)
    case savingsGoal(RemoteSavingsGoal)
    case recurringBillPlan(RemoteRecurringBillPlan)
    case installmentPlan(RemoteInstallmentPlan)
    case dueOccurrence(RemoteDueOccurrenceRecord)

    var entity: MistiaSyncEntity {
        switch self {
        case .wallet:
            .wallet
        case .creditCardProfile:
            .creditCardProfile
        case .category:
            .category
        case .transaction:
            .transaction
        case .budgetPlan:
            .budgetPlan
        case .savingsGoal:
            .savingsGoal
        case .recurringBillPlan:
            .recurringBillPlan
        case .installmentPlan:
            .installmentPlan
        case .dueOccurrence:
            .dueOccurrenceRecord
        }
    }

    var id: UUID {
        switch self {
        case .wallet(let row):
            row.id
        case .creditCardProfile(let row):
            row.id
        case .category(let row):
            row.id
        case .transaction(let row):
            row.id
        case .budgetPlan(let row):
            row.id
        case .savingsGoal(let row):
            row.id
        case .recurringBillPlan(let row):
            row.id
        case .installmentPlan(let row):
            row.id
        case .dueOccurrence(let row):
            row.id
        }
    }

    var updatedAt: Date {
        switch self {
        case .wallet(let row):
            row.updatedAt
        case .creditCardProfile(let row):
            row.updatedAt
        case .category(let row):
            row.updatedAt
        case .transaction(let row):
            row.updatedAt
        case .budgetPlan(let row):
            row.updatedAt
        case .savingsGoal(let row):
            row.updatedAt
        case .recurringBillPlan(let row):
            row.updatedAt
        case .installmentPlan(let row):
            row.updatedAt
        case .dueOccurrence(let row):
            row.updatedAt
        }
    }

    var userID: UUID {
        switch self {
        case .wallet(let row):
            row.userID
        case .creditCardProfile(let row):
            row.userID
        case .category(let row):
            row.userID
        case .transaction(let row):
            row.userID
        case .budgetPlan(let row):
            row.userID
        case .savingsGoal(let row):
            row.userID
        case .recurringBillPlan(let row):
            row.userID
        case .installmentPlan(let row):
            row.userID
        case .dueOccurrence(let row):
            row.userID
        }
    }

    var deletedAt: Date? {
        switch self {
        case .wallet(let row):
            row.deletedAt
        case .creditCardProfile(let row):
            row.deletedAt
        case .category(let row):
            row.deletedAt
        case .transaction(let row):
            row.deletedAt
        case .budgetPlan(let row):
            row.deletedAt
        case .savingsGoal(let row):
            row.deletedAt
        case .recurringBillPlan(let row):
            row.deletedAt
        case .installmentPlan(let row):
            row.deletedAt
        case .dueOccurrence(let row):
            row.deletedAt
        }
    }

    var syncVersion: Int64 {
        switch self {
        case .wallet(let row):
            row.syncVersion
        case .creditCardProfile(let row):
            row.syncVersion
        case .category(let row):
            row.syncVersion
        case .transaction(let row):
            row.syncVersion
        case .budgetPlan(let row):
            row.syncVersion
        case .savingsGoal(let row):
            row.syncVersion
        case .recurringBillPlan(let row):
            row.syncVersion
        case .installmentPlan(let row):
            row.syncVersion
        case .dueOccurrence(let row):
            row.syncVersion
        }
    }

    var lastModifiedByDeviceID: UUID? {
        switch self {
        case .wallet(let row):
            row.lastModifiedByDeviceID
        case .creditCardProfile(let row):
            row.lastModifiedByDeviceID
        case .category(let row):
            row.lastModifiedByDeviceID
        case .transaction(let row):
            row.lastModifiedByDeviceID
        case .budgetPlan(let row):
            row.lastModifiedByDeviceID
        case .savingsGoal(let row):
            row.lastModifiedByDeviceID
        case .recurringBillPlan(let row):
            row.lastModifiedByDeviceID
        case .installmentPlan(let row):
            row.lastModifiedByDeviceID
        case .dueOccurrence(let row):
            row.lastModifiedByDeviceID
        }
    }

    var payloadFingerprint: String {
        switch self {
        case .wallet(let row):
            return [
                entity.rawValue,
                row.name,
                row.kindRawValue,
                row.iconSymbolName,
                row.iconColorHex,
                row.currencyCode,
                "\(row.openingBalanceMinor)",
                row.institutionDisplayName ?? "",
                row.institutionPresetKey ?? "",
                "\(row.sortOrder)",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .creditCardProfile(let row):
            return [
                entity.rawValue,
                row.issuerName,
                row.networkRawValue,
                row.last4,
                "\(row.creditLimitMinor)",
                "\(row.statementClosingDay)",
                "\(row.paymentDueDay)",
                row.notes ?? "",
                row.walletID?.uuidString.lowercased() ?? "",
                row.paymentSourceWalletID?.uuidString.lowercased() ?? "",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .category(let row):
            return [
                entity.rawValue,
                row.name,
                row.kindRawValue,
                row.iconSymbolName,
                row.iconColorHex,
                row.parentCategoryID?.uuidString.lowercased() ?? "",
                row.hierarchyRoleRawValue ?? "",
                row.systemKey ?? "",
                row.isSystem ? "1" : "0",
                "\(row.sortOrder)",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .transaction(let row):
            return [
                entity.rawValue,
                row.primaryKindRawValue,
                row.transferSubtypeRawValue ?? "",
                row.debtIntentRawValue ?? "",
                row.entryStatusRawValue,
                row.title,
                row.note ?? "",
                "\(row.amountMinor)",
                Self.dateString(row.occurredAt),
                row.counterpartyName ?? "",
                row.normalizedCounterpartyKey ?? "",
                row.sourceWalletID?.uuidString.lowercased() ?? "",
                row.destinationWalletID?.uuidString.lowercased() ?? "",
                row.categoryID?.uuidString.lowercased() ?? "",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .budgetPlan(let row):
            return [
                entity.rawValue,
                row.categoryID?.uuidString.lowercased() ?? "",
                Self.dateString(row.monthAnchor),
                "\(row.limitMinor)",
                row.rolloverEnabled ? "1" : "0",
                row.currencyCode,
                row.isArchived ? "1" : "0",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .savingsGoal(let row):
            return [
                entity.rawValue,
                row.name,
                row.iconSymbolName,
                "\(row.targetMinor)",
                "\(row.currentSavedMinor)",
                Self.dateString(row.targetDate),
                row.linkedWalletID?.uuidString.lowercased() ?? "",
                row.currencyCode,
                "\(row.sortOrder)",
                row.isArchived ? "1" : "0",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .recurringBillPlan(let row):
            return [
                entity.rawValue,
                row.name,
                row.iconSymbolName,
                row.categoryID?.uuidString.lowercased() ?? "",
                row.amountMinor.map(String.init) ?? "",
                "\(row.dueDay)",
                "\(row.frequencyMonths)",
                row.paymentWalletID?.uuidString.lowercased() ?? "",
                row.currencyCode,
                row.isArchived ? "1" : "0",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .installmentPlan(let row):
            return [
                entity.rawValue,
                row.name,
                row.iconSymbolName,
                "\(row.amountPerCycleMinor)",
                "\(row.dueDay)",
                row.totalCycles.map(String.init) ?? "",
                "\(row.frequencyMonths)",
                row.paymentWalletID?.uuidString.lowercased() ?? "",
                row.currencyCode,
                row.isArchived ? "1" : "0",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .dueOccurrence(let row):
            return [
                entity.rawValue,
                row.sourceKindRawValue,
                row.sourceID.uuidString.lowercased(),
                row.selectedMonthKey,
                Self.dateString(row.scheduledDate),
                row.amountMinorSnapshot.map(String.init) ?? "",
                row.statusRawValue,
                Self.dateString(row.paidAt),
                row.linkedTransactionID?.uuidString.lowercased() ?? "",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        }
    }

    var previewTitle: String {
        switch self {
        case .wallet(let row):
            return row.name
        case .creditCardProfile(let row):
            return row.issuerName.isEmpty ? row.last4 : row.issuerName
        case .category(let row):
            return row.name
        case .transaction(let row):
            if row.title.isEmpty {
                return mistiaLocalized(
                    vi: "Giao dịch không tên",
                    en: "Unnamed transaction",
                    ja: "無名取引"
                )
            }
            return row.title
        case .budgetPlan:
            return mistiaLocalized(vi: "Ngân sách", en: "Budget plan", ja: "予算")
        case .savingsGoal(let row):
            return row.name
        case .recurringBillPlan(let row):
            return row.name
        case .installmentPlan(let row):
            return row.name
        case .dueOccurrence:
            return mistiaLocalized(vi: "Kỳ đến hạn", en: "Due occurrence", ja: "支払予定")
        }
    }

    func preparedForCreate(deviceID: UUID) -> MistiaSyncUploadRecord {
        preparedForMutation(nextVersion: 1, deviceID: deviceID)
    }

    func preparedForMutation(nextVersion: Int64, deviceID: UUID) -> MistiaSyncUploadRecord {
        switch self {
        case .wallet(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .wallet(row)
        case .creditCardProfile(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .creditCardProfile(row)
        case .category(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .category(row)
        case .transaction(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .transaction(row)
        case .budgetPlan(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .budgetPlan(row)
        case .savingsGoal(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .savingsGoal(row)
        case .recurringBillPlan(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .recurringBillPlan(row)
        case .installmentPlan(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .installmentPlan(row)
        case .dueOccurrence(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .dueOccurrence(row)
        }
    }

    func asJSONString() throws -> String {
        let encoder = JSONEncoder.mistiaSyncEncoder
        let data: Data
        switch self {
        case .wallet(let row):
            data = try encoder.encode(row)
        case .creditCardProfile(let row):
            data = try encoder.encode(row)
        case .category(let row):
            data = try encoder.encode(row)
        case .transaction(let row):
            data = try encoder.encode(row)
        case .budgetPlan(let row):
            data = try encoder.encode(row)
        case .savingsGoal(let row):
            data = try encoder.encode(row)
        case .recurringBillPlan(let row):
            data = try encoder.encode(row)
        case .installmentPlan(let row):
            data = try encoder.encode(row)
        case .dueOccurrence(let row):
            data = try encoder.encode(row)
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw SupabaseServiceError.invalidResponse
        }
        return json
    }

    static func decode(entity: MistiaSyncEntity, jsonString: String) throws -> MistiaSyncUploadRecord {
        let decoder = JSONDecoder.mistiaSyncDecoder
        guard let data = jsonString.data(using: .utf8) else {
            throw SupabaseServiceError.invalidResponse
        }

        switch entity {
        case .wallet:
            return .wallet(try decoder.decode(RemoteLedgerWallet.self, from: data))
        case .creditCardProfile:
            return .creditCardProfile(try decoder.decode(RemoteCreditCardProfile.self, from: data))
        case .category:
            return .category(try decoder.decode(RemoteTransactionCategory.self, from: data))
        case .transaction:
            return .transaction(try decoder.decode(RemoteLedgerTransaction.self, from: data))
        case .budgetPlan:
            return .budgetPlan(try decoder.decode(RemoteBudgetPlan.self, from: data))
        case .savingsGoal:
            return .savingsGoal(try decoder.decode(RemoteSavingsGoal.self, from: data))
        case .recurringBillPlan:
            return .recurringBillPlan(try decoder.decode(RemoteRecurringBillPlan.self, from: data))
        case .installmentPlan:
            return .installmentPlan(try decoder.decode(RemoteInstallmentPlan.self, from: data))
        case .dueOccurrenceRecord:
            return .dueOccurrence(try decoder.decode(RemoteDueOccurrenceRecord.self, from: data))
        }
    }

    private static func dateString(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter.mistiaSyncWithFractionalSeconds.string(from: date)
    }
}

extension MistiaSyncEntity {
    var displayTitle: String {
        switch self {
        case .wallet:
            return mistiaLocalized(vi: "Ví", en: "Wallet", ja: "ウォレット")
        case .creditCardProfile:
            return mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード")
        case .category:
            return mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ")
        case .transaction:
            return mistiaLocalized(vi: "Giao dịch", en: "Transaction", ja: "取引")
        case .budgetPlan:
            return mistiaLocalized(vi: "Ngân sách", en: "Budget", ja: "予算")
        case .savingsGoal:
            return mistiaLocalized(vi: "Mục tiêu", en: "Goal", ja: "目標")
        case .recurringBillPlan:
            return mistiaLocalized(vi: "Hóa đơn", en: "Bill", ja: "請求書")
        case .installmentPlan:
            return mistiaLocalized(vi: "Trả góp", en: "Installment", ja: "分割払い")
        case .dueOccurrenceRecord:
            return mistiaLocalized(vi: "Kỳ đến hạn", en: "Due occurrence", ja: "支払予定")
        }
    }
}

extension MistiaSyncConflictKind {
    var localizedTitle: String {
        switch self {
        case .createCreate:
            return mistiaLocalized(
                vi: "Trùng tạo dữ liệu",
                en: "Duplicate create",
                ja: "重複作成"
            )
        case .editEdit:
            return mistiaLocalized(
                vi: "Hai thiết bị cùng sửa",
                en: "Edited on two devices",
                ja: "2 台で同時編集"
            )
        case .editDelete:
            return mistiaLocalized(
                vi: "Máy này sửa, cloud đã xóa",
                en: "Edited here, deleted in cloud",
                ja: "この端末で編集、クラウドでは削除"
            )
        case .deleteEdit:
            return mistiaLocalized(
                vi: "Máy này xóa, cloud đã sửa",
                en: "Deleted here, edited in cloud",
                ja: "この端末で削除、クラウドでは編集"
            )
        }
    }

    var localActionTitle: String {
        switch self {
        case .editDelete:
            return mistiaLocalized(
                vi: "Khôi phục bản trên máy",
                en: "Restore record",
                ja: "この端末の内容を復元"
            )
        default:
            return mistiaLocalized(
                vi: "Dùng bản trên máy này",
                en: "Use this device's version",
                ja: "この端末の内容を使う"
            )
        }
    }

    var remoteActionTitle: String {
        switch self {
        case .deleteEdit:
            return mistiaLocalized(
                vi: "Giữ đã xóa",
                en: "Keep deleted",
                ja: "削除を維持"
            )
        default:
            return mistiaLocalized(
                vi: "Dùng bản trên cloud",
                en: "Use cloud version",
                ja: "クラウドの内容を使う"
            )
        }
    }
}

extension JSONDecoder {
    static var mistiaSyncDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.mistiaSyncWithFractionalSeconds.date(from: value)
                ?? ISO8601DateFormatter.mistiaSyncWithoutFractionalSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }

    static var mistiaRemoteAPIDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.mistiaSyncWithFractionalSeconds.date(from: value)
                ?? ISO8601DateFormatter.mistiaSyncWithoutFractionalSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var mistiaSyncEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.mistiaSyncWithFractionalSeconds.string(from: date))
        }
        return encoder
    }

    static var mistiaRemoteAPIEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.mistiaSyncWithFractionalSeconds.string(from: date))
        }
        return encoder
    }
}

extension ISO8601DateFormatter {
    static let mistiaSyncWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let mistiaSyncWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let mistiaRemoteAPI: ISO8601DateFormatter = mistiaSyncWithFractionalSeconds
}
