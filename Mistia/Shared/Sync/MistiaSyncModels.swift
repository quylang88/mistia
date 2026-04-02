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
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
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
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
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
}

struct RemoteRowVersion: Codable {
    let id: UUID
    let updatedAt: Date
    let deletedAt: Date?
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
