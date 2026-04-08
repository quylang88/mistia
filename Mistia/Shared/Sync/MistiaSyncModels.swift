import Foundation

protocol MistiaRemoteRow: Codable {
    static var entity: MistiaSyncEntity { get }

    var id: UUID { get }
    var userID: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

struct RemoteLedgerWallet: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .wallet

    let userID: UUID
    let id: UUID
    let name: String
    let kindRawValue: String
    let iconSymbolName: String
    let iconColorHex: String
    let currencyCode: String
    let openingBalanceMinor: Int64
    let institutionDisplayName: String?
    let institutionPresetKey: String?
    let sortOrder: Int
    let isArchived: Bool
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

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
    }
}

struct RemoteCreditCardProfile: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .creditCardProfile

    let userID: UUID
    let id: UUID
    let issuerName: String
    let networkRawValue: String
    let last4: String
    let creditLimitMinor: Int64
    let statementClosingDay: Int
    let paymentDueDay: Int
    let notes: String?
    let walletID: UUID?
    let paymentSourceWalletID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

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
    }
}

struct RemoteTransactionCategory: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .category

    let userID: UUID
    let id: UUID
    let name: String
    let kindRawValue: String
    let iconSymbolName: String
    let iconColorHex: String
    let systemKey: String?
    let isSystem: Bool
    let sortOrder: Int
    let isArchived: Bool
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case kindRawValue = "kind_raw_value"
        case iconSymbolName = "icon_symbol_name"
        case iconColorHex = "icon_color_hex"
        case systemKey = "system_key"
        case isSystem = "is_system"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteLedgerTransaction: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .transaction

    let userID: UUID
    let id: UUID
    let primaryKindRawValue: String
    let transferSubtypeRawValue: String?
    let debtIntentRawValue: String?
    let entryStatusRawValue: String
    let title: String
    let note: String?
    let amountMinor: Int64
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let counterpartyName: String?
    let normalizedCounterpartyKey: String?
    let sourceWalletID: UUID?
    let destinationWalletID: UUID?
    let categoryID: UUID?
    let deletedAt: Date?
    let isArchived: Bool
    let archivedAt: Date?

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
    }
}

struct RemoteBudgetPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .budgetPlan

    let userID: UUID
    let id: UUID
    let categoryID: UUID?
    let monthAnchor: Date
    let limitMinor: Int64
    let rolloverEnabled: Bool
    let currencyCode: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

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
    }
}

struct RemoteSavingsGoal: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .savingsGoal

    let userID: UUID
    let id: UUID
    let name: String
    let iconSymbolName: String
    let targetMinor: Int64
    let currentSavedMinor: Int64
    let targetDate: Date
    let linkedWalletID: UUID?
    let currencyCode: String
    let sortOrder: Int
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

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
    }
}

struct RemoteRecurringBillPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .recurringBillPlan

    let userID: UUID
    let id: UUID
    let name: String
    let iconSymbolName: String
    let amountMinor: Int64?
    let dueDay: Int
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case iconSymbolName = "icon_symbol_name"
        case amountMinor = "amount_minor"
        case dueDay = "due_day"
        case frequencyMonths = "frequency_months"
        case paymentWalletID = "payment_wallet_id"
        case currencyCode = "currency_code"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteInstallmentPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .installmentPlan

    let userID: UUID
    let id: UUID
    let name: String
    let iconSymbolName: String
    let amountPerCycleMinor: Int64
    let dueDay: Int
    let totalCycles: Int?
    let frequencyMonths: Int
    let paymentWalletID: UUID?
    let currencyCode: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

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
    }
}

struct RemoteDueOccurrenceRecord: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .dueOccurrenceRecord

    let userID: UUID
    let id: UUID
    let sourceKindRawValue: String
    let sourceID: UUID
    let selectedMonthKey: String
    let scheduledDate: Date
    let amountMinorSnapshot: Int64?
    let statusRawValue: String
    let paidAt: Date?
    let linkedTransactionID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

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
    }
}

struct RemoteRowVersion: Codable {
    let id: UUID
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
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
}
