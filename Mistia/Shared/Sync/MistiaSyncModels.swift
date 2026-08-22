import CryptoKit
import Foundation

private enum MistiaSyncSerializationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Unable to serialize or decode the Mistia sync payload."
    }
}

nonisolated enum MistiaStableUUIDOrdering {
    @inline(__always)
    static func precedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
        var lhsBytes = lhs.uuid
        var rhsBytes = rhs.uuid
        return withUnsafeBytes(of: &lhsBytes) { lhsBuffer in
            withUnsafeBytes(of: &rhsBytes) { rhsBuffer in
                lhsBuffer.lexicographicallyPrecedes(rhsBuffer)
            }
        }
    }
}

nonisolated enum MistiaISO8601DateCoding {
    private static let withFractionalSecondsCacheKey = "MistiaISO8601DateCoding.withFractionalSeconds"
    private static let withoutFractionalSecondsCacheKey = "MistiaISO8601DateCoding.withoutFractionalSeconds"

    static func date(from value: String) -> Date? {
        formatter(
            cacheKey: withFractionalSecondsCacheKey,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        ).date(from: value)
            ?? formatter(
                cacheKey: withoutFractionalSecondsCacheKey,
                formatOptions: [.withInternetDateTime]
            ).date(from: value)
    }

    static func stringWithFractionalSeconds(from date: Date) -> String {
        formatter(
            cacheKey: withFractionalSecondsCacheKey,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        ).string(from: date)
    }

    fileprivate static func formatter(
        cacheKey: String,
        formatOptions: ISO8601DateFormatter.Options
    ) -> ISO8601DateFormatter {
        let threadDictionary = Thread.current.threadDictionary
        if let cached = threadDictionary[cacheKey] as? ISO8601DateFormatter {
            return cached
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = formatOptions
        formatter.timeZone = .gmt
        threadDictionary[cacheKey] = formatter
        return formatter
    }
}

nonisolated protocol MistiaRemoteRow: Codable, Sendable {
    static var entity: MistiaSyncEntity { get }

    var id: UUID { get }
    var userID: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
    var syncVersion: Int64 { get set }
    var lastModifiedByDeviceID: UUID? { get set }
}

nonisolated struct RemoteLedgerWallet: MistiaRemoteRow {
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
    var systemPurposeRawValue: String? = nil

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
        case systemPurposeRawValue = "system_purpose_raw_value"
    }
}

nonisolated extension RemoteLedgerWallet {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kindRawValue = try container.decode(String.self, forKey: .kindRawValue)
        iconSymbolName = try container.decode(String.self, forKey: .iconSymbolName)
        iconColorHex = try container.decode(String.self, forKey: .iconColorHex)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        openingBalanceMinor = try container.decode(Int64.self, forKey: .openingBalanceMinor)
        institutionDisplayName = try container.decodeIfPresent(String.self, forKey: .institutionDisplayName)
        institutionPresetKey = try container.decodeIfPresent(String.self, forKey: .institutionPresetKey)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
        systemPurposeRawValue = try container.decodeIfPresent(String.self, forKey: .systemPurposeRawValue)
    }
}

nonisolated struct RemoteCreditCardProfile: MistiaRemoteRow {
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
    var autoPayEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    init(
        userID: UUID,
        id: UUID,
        issuerName: String,
        networkRawValue: String,
        last4: String,
        creditLimitMinor: Int64,
        statementClosingDay: Int,
        paymentDueDay: Int,
        notes: String?,
        walletID: UUID?,
        paymentSourceWalletID: UUID?,
        autoPayEnabled: Bool = true,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        syncVersion: Int64,
        lastModifiedByDeviceID: UUID?
    ) {
        self.userID = userID
        self.id = id
        self.issuerName = issuerName
        self.networkRawValue = networkRawValue
        self.last4 = last4
        self.creditLimitMinor = creditLimitMinor
        self.statementClosingDay = statementClosingDay
        self.paymentDueDay = paymentDueDay
        self.notes = notes
        self.walletID = walletID
        self.paymentSourceWalletID = paymentSourceWalletID
        self.autoPayEnabled = autoPayEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncVersion = syncVersion
        self.lastModifiedByDeviceID = lastModifiedByDeviceID
    }

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
        case autoPayEnabled = "auto_pay_enabled"
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
        issuerName = try container.decode(String.self, forKey: .issuerName)
        networkRawValue = try container.decode(String.self, forKey: .networkRawValue)
        last4 = try container.decode(String.self, forKey: .last4)
        creditLimitMinor = try container.decode(Int64.self, forKey: .creditLimitMinor)
        statementClosingDay = try container.decode(Int.self, forKey: .statementClosingDay)
        paymentDueDay = try container.decode(Int.self, forKey: .paymentDueDay)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        walletID = try container.decodeIfPresent(UUID.self, forKey: .walletID)
        paymentSourceWalletID = try container.decodeIfPresent(UUID.self, forKey: .paymentSourceWalletID)
        autoPayEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPayEnabled) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }
}

nonisolated struct RemoteTransactionCategory: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .category

    var userID: UUID
    var id: UUID
    var name: String
    var nameEnglish: String?
    var nameJapanese: String?
    var kindRawValue: String
    var iconSymbolName: String
    var iconColorHex: String
    var isFavorite: Bool
    var familyBudgetSpendingEnabled: Bool
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

    init(
        userID: UUID,
        id: UUID,
        name: String,
        nameEnglish: String? = nil,
        nameJapanese: String? = nil,
        kindRawValue: String,
        iconSymbolName: String,
        iconColorHex: String,
        isFavorite: Bool,
        familyBudgetSpendingEnabled: Bool = false,
        parentCategoryID: UUID?,
        hierarchyRoleRawValue: String?,
        systemKey: String?,
        isSystem: Bool,
        sortOrder: Int,
        isArchived: Bool,
        archivedAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        syncVersion: Int64,
        lastModifiedByDeviceID: UUID?
    ) {
        self.userID = userID
        self.id = id
        self.name = name
        self.nameEnglish = nameEnglish
        self.nameJapanese = nameJapanese
        self.kindRawValue = kindRawValue
        self.iconSymbolName = iconSymbolName
        self.iconColorHex = iconColorHex
        self.isFavorite = isFavorite
        self.familyBudgetSpendingEnabled = familyBudgetSpendingEnabled
        self.parentCategoryID = parentCategoryID
        self.hierarchyRoleRawValue = hierarchyRoleRawValue
        self.systemKey = systemKey
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncVersion = syncVersion
        self.lastModifiedByDeviceID = lastModifiedByDeviceID
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case nameEnglish = "name_english"
        case nameJapanese = "name_japanese"
        case kindRawValue = "kind_raw_value"
        case iconSymbolName = "icon_symbol_name"
        case iconColorHex = "icon_color_hex"
        case isFavorite = "is_favorite"
        case familyBudgetSpendingEnabled = "family_budget_spending_enabled"
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
        nameEnglish = try container.decodeIfPresent(String.self, forKey: .nameEnglish)
        nameJapanese = try container.decodeIfPresent(String.self, forKey: .nameJapanese)
        kindRawValue = try container.decode(String.self, forKey: .kindRawValue)
        iconSymbolName = try container.decode(String.self, forKey: .iconSymbolName)
        iconColorHex = try container.decode(String.self, forKey: .iconColorHex)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        familyBudgetSpendingEnabled = try container.decodeIfPresent(Bool.self, forKey: .familyBudgetSpendingEnabled) ?? false
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

nonisolated struct RemoteLedgerTransaction: MistiaRemoteRow {
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
    var sourceCurrencyCode: String?
    var destinationCurrencyCode: String?
    var destinationAmountMinor: Int64?
    var reportingCurrencyCode: String?
    var reportingAmountMinor: Int64?
    var conversionModeRawValue: String?
    var exchangeRateDecimalString: String?
    var exchangeRateProvider: String?
    var exchangeRateDate: String?
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var createdByUserID: UUID
    var lastModifiedByUserID: UUID
    var counterpartyName: String?
    var normalizedCounterpartyKey: String?
    var settlementGroupID: UUID?
    var settlementObligationID: UUID?
    var settlementRoleRawValue: String?
    var reportingExpenseMinor: Int64?
    var reportingIncomeMinor: Int64?
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
        case sourceCurrencyCode = "source_currency_code"
        case destinationCurrencyCode = "destination_currency_code"
        case destinationAmountMinor = "destination_amount_minor"
        case reportingCurrencyCode = "reporting_currency_code"
        case reportingAmountMinor = "reporting_amount_minor"
        case conversionModeRawValue = "conversion_mode_raw_value"
        case exchangeRateDecimalString = "exchange_rate_decimal_string"
        case exchangeRateProvider = "exchange_rate_provider"
        case exchangeRateDate = "exchange_rate_date"
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdByUserID = "created_by_user_id"
        case lastModifiedByUserID = "last_modified_by_user_id"
        case counterpartyName = "counterparty_name"
        case normalizedCounterpartyKey = "normalized_counterparty_key"
        case settlementGroupID = "settlement_group_id"
        case settlementObligationID = "settlement_obligation_id"
        case settlementRoleRawValue = "settlement_role_raw_value"
        case reportingExpenseMinor = "reporting_expense_minor"
        case reportingIncomeMinor = "reporting_income_minor"
        case sourceWalletID = "source_wallet_id"
        case destinationWalletID = "destination_wallet_id"
        case categoryID = "category_id"
        case deletedAt = "deleted_at"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        primaryKindRawValue = try container.decode(String.self, forKey: .primaryKindRawValue)
        transferSubtypeRawValue = try container.decodeIfPresent(String.self, forKey: .transferSubtypeRawValue)
        debtIntentRawValue = try container.decodeIfPresent(String.self, forKey: .debtIntentRawValue)
        entryStatusRawValue = try container.decode(String.self, forKey: .entryStatusRawValue)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        sourceCurrencyCode = try container.decodeIfPresent(String.self, forKey: .sourceCurrencyCode)
        destinationCurrencyCode = try container.decodeIfPresent(String.self, forKey: .destinationCurrencyCode)
        destinationAmountMinor = try container.decodeIfPresent(Int64.self, forKey: .destinationAmountMinor)
        reportingCurrencyCode = try container.decodeIfPresent(String.self, forKey: .reportingCurrencyCode)
        reportingAmountMinor = try container.decodeIfPresent(Int64.self, forKey: .reportingAmountMinor)
        conversionModeRawValue = try container.decodeIfPresent(String.self, forKey: .conversionModeRawValue)
        exchangeRateDecimalString = try container.decodeIfPresent(String.self, forKey: .exchangeRateDecimalString)
        exchangeRateProvider = try container.decodeIfPresent(String.self, forKey: .exchangeRateProvider)
        exchangeRateDate = try container.decodeIfPresent(String.self, forKey: .exchangeRateDate)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        createdByUserID = try container.decodeIfPresent(UUID.self, forKey: .createdByUserID) ?? userID
        lastModifiedByUserID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByUserID) ?? createdByUserID
        counterpartyName = try container.decodeIfPresent(String.self, forKey: .counterpartyName)
        normalizedCounterpartyKey = try container.decodeIfPresent(String.self, forKey: .normalizedCounterpartyKey)
        settlementGroupID = try container.decodeIfPresent(UUID.self, forKey: .settlementGroupID)
        settlementObligationID = try container.decodeIfPresent(UUID.self, forKey: .settlementObligationID)
        settlementRoleRawValue = try container.decodeIfPresent(String.self, forKey: .settlementRoleRawValue)
        reportingExpenseMinor = try container.decodeIfPresent(Int64.self, forKey: .reportingExpenseMinor)
        reportingIncomeMinor = try container.decodeIfPresent(Int64.self, forKey: .reportingIncomeMinor)
        sourceWalletID = try container.decodeIfPresent(UUID.self, forKey: .sourceWalletID)
        destinationWalletID = try container.decodeIfPresent(UUID.self, forKey: .destinationWalletID)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(primaryKindRawValue, forKey: .primaryKindRawValue)
        try container.encode(transferSubtypeRawValue, forKey: .transferSubtypeRawValue)
        try container.encode(debtIntentRawValue, forKey: .debtIntentRawValue)
        try container.encode(entryStatusRawValue, forKey: .entryStatusRawValue)
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(sourceCurrencyCode, forKey: .sourceCurrencyCode)
        try container.encode(destinationCurrencyCode, forKey: .destinationCurrencyCode)
        try container.encode(destinationAmountMinor, forKey: .destinationAmountMinor)
        try container.encode(reportingCurrencyCode, forKey: .reportingCurrencyCode)
        try container.encode(reportingAmountMinor, forKey: .reportingAmountMinor)
        try container.encode(conversionModeRawValue, forKey: .conversionModeRawValue)
        try container.encode(exchangeRateDecimalString, forKey: .exchangeRateDecimalString)
        try container.encode(exchangeRateProvider, forKey: .exchangeRateProvider)
        try container.encode(exchangeRateDate, forKey: .exchangeRateDate)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(createdByUserID, forKey: .createdByUserID)
        try container.encode(lastModifiedByUserID, forKey: .lastModifiedByUserID)
        try container.encode(counterpartyName, forKey: .counterpartyName)
        try container.encode(normalizedCounterpartyKey, forKey: .normalizedCounterpartyKey)
        try container.encode(settlementGroupID, forKey: .settlementGroupID)
        try container.encode(settlementObligationID, forKey: .settlementObligationID)
        try container.encode(settlementRoleRawValue, forKey: .settlementRoleRawValue)
        try container.encode(reportingExpenseMinor, forKey: .reportingExpenseMinor)
        try container.encode(reportingIncomeMinor, forKey: .reportingIncomeMinor)
        try container.encode(sourceWalletID, forKey: .sourceWalletID)
        try container.encode(destinationWalletID, forKey: .destinationWalletID)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(archivedAt, forKey: .archivedAt)
        try container.encode(syncVersion, forKey: .syncVersion)
        try container.encode(lastModifiedByDeviceID, forKey: .lastModifiedByDeviceID)
    }
}

nonisolated struct RemoteSettlementGroup: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .settlementGroup

    var userID: UUID
    var id: UUID
    var kindRawValue: String
    var statusRawValue: String
    var title: String
    var currencyCode: String
    var occurredAt: Date
    var totalMinor: Int64
    var expectedMinor: Int64
    var settledMinor: Int64
    var organizerUserID: UUID?
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isArchived: Bool
    var archivedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case kindRawValue = "kind_raw_value"
        case statusRawValue = "status_raw_value"
        case title
        case currencyCode = "currency_code"
        case occurredAt = "occurred_at"
        case totalMinor = "total_minor"
        case expectedMinor = "expected_minor"
        case settledMinor = "settled_minor"
        case organizerUserID = "organizer_user_id"
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated struct RemoteSettlementParticipant: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .settlementParticipant

    var userID: UUID
    var id: UUID
    var groupID: UUID
    var displayName: String
    var normalizedKey: String?
    var memberUserID: UUID?
    var isSelf: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64
    var lastModifiedByDeviceID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case groupID = "group_id"
        case displayName = "display_name"
        case normalizedKey = "normalized_key"
        case memberUserID = "member_user_id"
        case isSelf = "is_self"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

nonisolated struct RemoteBudgetPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .budgetPlan

    var userID: UUID
    var id: UUID
    var categoryID: UUID?
    var categoryIDSnapshot: UUID?
    var categoryNameSnapshot: String?
    var categoryNameEnglishSnapshot: String?
    var categoryNameJapaneseSnapshot: String?
    var categoryPathSnapshot: String?
    var categoryPathEnglishSnapshot: String?
    var categoryPathJapaneseSnapshot: String?
    var categoryIconSymbolNameSnapshot: String?
    var categoryColorHexSnapshot: String?
    var categoryParentIDSnapshot: UUID?
    var categoryParentNameSnapshot: String?
    var categoryParentNameEnglishSnapshot: String?
    var categoryParentNameJapaneseSnapshot: String?
    var categoryParentIconSymbolNameSnapshot: String?
    var categoryParentColorHexSnapshot: String?
    var categoryHierarchyRoleSnapshotRawValue: String?
    var categoryIsParentSnapshot: Bool?
    var includesFamilySpending: Bool
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

    init(
        userID: UUID,
        id: UUID,
        categoryID: UUID?,
        categoryIDSnapshot: UUID? = nil,
        categoryNameSnapshot: String? = nil,
        categoryNameEnglishSnapshot: String? = nil,
        categoryNameJapaneseSnapshot: String? = nil,
        categoryPathSnapshot: String? = nil,
        categoryPathEnglishSnapshot: String? = nil,
        categoryPathJapaneseSnapshot: String? = nil,
        categoryIconSymbolNameSnapshot: String? = nil,
        categoryColorHexSnapshot: String? = nil,
        categoryParentIDSnapshot: UUID? = nil,
        categoryParentNameSnapshot: String? = nil,
        categoryParentNameEnglishSnapshot: String? = nil,
        categoryParentNameJapaneseSnapshot: String? = nil,
        categoryParentIconSymbolNameSnapshot: String? = nil,
        categoryParentColorHexSnapshot: String? = nil,
        categoryHierarchyRoleSnapshotRawValue: String? = nil,
        categoryIsParentSnapshot: Bool? = nil,
        includesFamilySpending: Bool = false,
        monthAnchor: Date,
        limitMinor: Int64,
        rolloverEnabled: Bool,
        currencyCode: String,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        syncVersion: Int64,
        lastModifiedByDeviceID: UUID?
    ) {
        self.userID = userID
        self.id = id
        self.categoryID = categoryID
        self.categoryIDSnapshot = categoryIDSnapshot
        self.categoryNameSnapshot = categoryNameSnapshot
        self.categoryNameEnglishSnapshot = categoryNameEnglishSnapshot
        self.categoryNameJapaneseSnapshot = categoryNameJapaneseSnapshot
        self.categoryPathSnapshot = categoryPathSnapshot
        self.categoryPathEnglishSnapshot = categoryPathEnglishSnapshot
        self.categoryPathJapaneseSnapshot = categoryPathJapaneseSnapshot
        self.categoryIconSymbolNameSnapshot = categoryIconSymbolNameSnapshot
        self.categoryColorHexSnapshot = categoryColorHexSnapshot
        self.categoryParentIDSnapshot = categoryParentIDSnapshot
        self.categoryParentNameSnapshot = categoryParentNameSnapshot
        self.categoryParentNameEnglishSnapshot = categoryParentNameEnglishSnapshot
        self.categoryParentNameJapaneseSnapshot = categoryParentNameJapaneseSnapshot
        self.categoryParentIconSymbolNameSnapshot = categoryParentIconSymbolNameSnapshot
        self.categoryParentColorHexSnapshot = categoryParentColorHexSnapshot
        self.categoryHierarchyRoleSnapshotRawValue = categoryHierarchyRoleSnapshotRawValue
        self.categoryIsParentSnapshot = categoryIsParentSnapshot
        self.includesFamilySpending = includesFamilySpending
        self.monthAnchor = monthAnchor
        self.limitMinor = limitMinor
        self.rolloverEnabled = rolloverEnabled
        self.currencyCode = currencyCode
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncVersion = syncVersion
        self.lastModifiedByDeviceID = lastModifiedByDeviceID
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case categoryID = "category_id"
        case categoryIDSnapshot = "category_id_snapshot"
        case categoryNameSnapshot = "category_name_snapshot"
        case categoryNameEnglishSnapshot = "category_name_english_snapshot"
        case categoryNameJapaneseSnapshot = "category_name_japanese_snapshot"
        case categoryPathSnapshot = "category_path_snapshot"
        case categoryPathEnglishSnapshot = "category_path_english_snapshot"
        case categoryPathJapaneseSnapshot = "category_path_japanese_snapshot"
        case categoryIconSymbolNameSnapshot = "category_icon_symbol_name_snapshot"
        case categoryColorHexSnapshot = "category_color_hex_snapshot"
        case categoryParentIDSnapshot = "category_parent_id_snapshot"
        case categoryParentNameSnapshot = "category_parent_name_snapshot"
        case categoryParentNameEnglishSnapshot = "category_parent_name_english_snapshot"
        case categoryParentNameJapaneseSnapshot = "category_parent_name_japanese_snapshot"
        case categoryParentIconSymbolNameSnapshot = "category_parent_icon_symbol_name_snapshot"
        case categoryParentColorHexSnapshot = "category_parent_color_hex_snapshot"
        case categoryHierarchyRoleSnapshotRawValue = "category_hierarchy_role_snapshot_raw_value"
        case categoryIsParentSnapshot = "category_is_parent_snapshot"
        case includesFamilySpending = "includes_family_spending"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        categoryIDSnapshot = try container.decodeIfPresent(UUID.self, forKey: .categoryIDSnapshot)
        categoryNameSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryNameSnapshot)
        categoryNameEnglishSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryNameEnglishSnapshot)
        categoryNameJapaneseSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryNameJapaneseSnapshot)
        categoryPathSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryPathSnapshot)
        categoryPathEnglishSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryPathEnglishSnapshot)
        categoryPathJapaneseSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryPathJapaneseSnapshot)
        categoryIconSymbolNameSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryIconSymbolNameSnapshot)
        categoryColorHexSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryColorHexSnapshot)
        categoryParentIDSnapshot = try container.decodeIfPresent(UUID.self, forKey: .categoryParentIDSnapshot)
        categoryParentNameSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryParentNameSnapshot)
        categoryParentNameEnglishSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryParentNameEnglishSnapshot)
        categoryParentNameJapaneseSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryParentNameJapaneseSnapshot)
        categoryParentIconSymbolNameSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryParentIconSymbolNameSnapshot)
        categoryParentColorHexSnapshot = try container.decodeIfPresent(String.self, forKey: .categoryParentColorHexSnapshot)
        categoryHierarchyRoleSnapshotRawValue = try container.decodeIfPresent(String.self, forKey: .categoryHierarchyRoleSnapshotRawValue)
        categoryIsParentSnapshot = try container.decodeIfPresent(Bool.self, forKey: .categoryIsParentSnapshot)
        includesFamilySpending = try container.decodeIfPresent(Bool.self, forKey: .includesFamilySpending) ?? false
        monthAnchor = try container.decode(Date.self, forKey: .monthAnchor)
        limitMinor = try container.decode(Int64.self, forKey: .limitMinor)
        rolloverEnabled = try container.decode(Bool.self, forKey: .rolloverEnabled)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }
}

nonisolated struct RemoteSavingsGoal: MistiaRemoteRow {
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

nonisolated struct RemoteRecurringBillPlan: MistiaRemoteRow {
    static let entity: MistiaSyncEntity = .recurringBillPlan

    var userID: UUID
    var id: UUID
    var name: String
    var iconSymbolName: String
    var categoryID: UUID?
    var amountMinor: Int64?
    var dueDay: Int
    var scheduleKindRawValue: String?
    var paymentStartDay: Int?
    var paymentStartDate: Date?
    var firstScheduledMonth: Date?
    var hasExplicitDueDate: Bool?
    var dueDate: Date?
    var autoPayEnabled: Bool?
    var autoPayDay: Int?
    var autoPayDate: Date?
    var frequencyMonths: Int
    var paymentWalletID: UUID?
    var currencyCode: String
    var isArchived: Bool
    var isPaused: Bool
    var pausedAt: Date?
    var resumeStartMonth: Date?
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
        case scheduleKindRawValue = "schedule_kind_raw_value"
        case paymentStartDay = "payment_start_day"
        case paymentStartDate = "payment_start_date"
        case firstScheduledMonth = "first_scheduled_month"
        case hasExplicitDueDate = "has_explicit_due_date"
        case dueDate = "due_date"
        case autoPayEnabled = "auto_pay_enabled"
        case autoPayDay = "auto_pay_day"
        case autoPayDate = "auto_pay_date"
        case frequencyMonths = "frequency_months"
        case paymentWalletID = "payment_wallet_id"
        case currencyCode = "currency_code"
        case isArchived = "is_archived"
        case isPaused = "is_paused"
        case pausedAt = "paused_at"
        case resumeStartMonth = "resume_start_month"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
        case lastModifiedByDeviceID = "last_modified_by_device_id"
    }
}

extension RemoteRecurringBillPlan {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconSymbolName = try container.decode(String.self, forKey: .iconSymbolName)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        amountMinor = try container.decodeIfPresent(Int64.self, forKey: .amountMinor)
        dueDay = try container.decode(Int.self, forKey: .dueDay)
        scheduleKindRawValue = try container.decodeIfPresent(String.self, forKey: .scheduleKindRawValue)
        paymentStartDay = try container.decodeIfPresent(Int.self, forKey: .paymentStartDay)
        paymentStartDate = try container.decodeIfPresent(Date.self, forKey: .paymentStartDate)
        firstScheduledMonth = try container.decodeIfPresent(Date.self, forKey: .firstScheduledMonth)
        hasExplicitDueDate = try container.decodeIfPresent(Bool.self, forKey: .hasExplicitDueDate)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        autoPayEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPayEnabled)
        autoPayDay = try container.decodeIfPresent(Int.self, forKey: .autoPayDay)
        autoPayDate = try container.decodeIfPresent(Date.self, forKey: .autoPayDate)
        frequencyMonths = try container.decode(Int.self, forKey: .frequencyMonths)
        paymentWalletID = try container.decodeIfPresent(UUID.self, forKey: .paymentWalletID)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        resumeStartMonth = try container.decodeIfPresent(Date.self, forKey: .resumeStartMonth)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        syncVersion = try container.decode(Int64.self, forKey: .syncVersion)
        lastModifiedByDeviceID = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedByDeviceID)
    }
}

nonisolated struct RemoteInstallmentPlan: MistiaRemoteRow {
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

nonisolated struct RemoteDueOccurrenceRecord: MistiaRemoteRow {
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

struct RemoteRowVersion: Codable, Sendable {
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

nonisolated struct MistiaRemoteSnapshot: Codable, Sendable {
    let wallets: [RemoteLedgerWallet]
    let creditCardProfiles: [RemoteCreditCardProfile]
    let categories: [RemoteTransactionCategory]
    let settlementGroups: [RemoteSettlementGroup]
    let settlementParticipants: [RemoteSettlementParticipant]
    let transactions: [RemoteLedgerTransaction]
    let budgetPlans: [RemoteBudgetPlan]
    let savingsGoals: [RemoteSavingsGoal]
    let recurringBillPlans: [RemoteRecurringBillPlan]
    let installmentPlans: [RemoteInstallmentPlan]
    let dueOccurrences: [RemoteDueOccurrenceRecord]
    let investmentChannels: [RemoteInvestmentChannel]
    let investmentAssets: [RemoteInvestmentAsset]
    let investmentTrades: [RemoteInvestmentTrade]
    let investmentPostings: [RemoteInvestmentWalletPosting]

    private enum CodingKeys: String, CodingKey {
        case wallets
        case creditCardProfiles
        case categories
        case settlementGroups
        case settlementParticipants
        case transactions
        case budgetPlans
        case savingsGoals
        case recurringBillPlans
        case installmentPlans
        case dueOccurrences
        case investmentChannels
        case investmentAssets
        case investmentTrades
        case investmentPostings
    }

    init(
        wallets: [RemoteLedgerWallet],
        creditCardProfiles: [RemoteCreditCardProfile],
        categories: [RemoteTransactionCategory],
        settlementGroups: [RemoteSettlementGroup],
        settlementParticipants: [RemoteSettlementParticipant] = [],
        transactions: [RemoteLedgerTransaction],
        budgetPlans: [RemoteBudgetPlan],
        savingsGoals: [RemoteSavingsGoal],
        recurringBillPlans: [RemoteRecurringBillPlan],
        installmentPlans: [RemoteInstallmentPlan],
        dueOccurrences: [RemoteDueOccurrenceRecord],
        investmentChannels: [RemoteInvestmentChannel] = [],
        investmentAssets: [RemoteInvestmentAsset] = [],
        investmentTrades: [RemoteInvestmentTrade] = [],
        investmentPostings: [RemoteInvestmentWalletPosting] = []
    ) {
        self.wallets = wallets
        self.creditCardProfiles = creditCardProfiles
        self.categories = categories
        self.settlementGroups = settlementGroups
        self.settlementParticipants = settlementParticipants
        self.transactions = transactions
        self.budgetPlans = budgetPlans
        self.savingsGoals = savingsGoals
        self.recurringBillPlans = recurringBillPlans
        self.installmentPlans = installmentPlans
        self.dueOccurrences = dueOccurrences
        self.investmentChannels = investmentChannels
        self.investmentAssets = investmentAssets
        self.investmentTrades = investmentTrades
        self.investmentPostings = investmentPostings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wallets = try container.decode([RemoteLedgerWallet].self, forKey: .wallets)
        creditCardProfiles = try container.decode([RemoteCreditCardProfile].self, forKey: .creditCardProfiles)
        categories = try container.decode([RemoteTransactionCategory].self, forKey: .categories)
        settlementGroups = try container.decode([RemoteSettlementGroup].self, forKey: .settlementGroups)
        settlementParticipants = try container.decodeIfPresent([RemoteSettlementParticipant].self, forKey: .settlementParticipants) ?? []
        transactions = try container.decode([RemoteLedgerTransaction].self, forKey: .transactions)
        budgetPlans = try container.decode([RemoteBudgetPlan].self, forKey: .budgetPlans)
        savingsGoals = try container.decode([RemoteSavingsGoal].self, forKey: .savingsGoals)
        recurringBillPlans = try container.decode([RemoteRecurringBillPlan].self, forKey: .recurringBillPlans)
        installmentPlans = try container.decode([RemoteInstallmentPlan].self, forKey: .installmentPlans)
        dueOccurrences = try container.decode([RemoteDueOccurrenceRecord].self, forKey: .dueOccurrences)
        investmentChannels = try container.decodeIfPresent([RemoteInvestmentChannel].self, forKey: .investmentChannels) ?? []
        investmentAssets = try container.decodeIfPresent([RemoteInvestmentAsset].self, forKey: .investmentAssets) ?? []
        investmentTrades = try container.decodeIfPresent([RemoteInvestmentTrade].self, forKey: .investmentTrades) ?? []
        investmentPostings = try container.decodeIfPresent([RemoteInvestmentWalletPosting].self, forKey: .investmentPostings) ?? []
    }

    static let empty = MistiaRemoteSnapshot(
        wallets: [],
        creditCardProfiles: [],
        categories: [],
        settlementGroups: [],
        settlementParticipants: [],
        transactions: [],
        budgetPlans: [],
        savingsGoals: [],
        recurringBillPlans: [],
        installmentPlans: [],
        dueOccurrences: [],
        investmentChannels: [],
        investmentAssets: [],
        investmentTrades: [],
        investmentPostings: []
    )

    var totalRowCount: Int {
        wallets.count
            + creditCardProfiles.count
            + categories.count
            + settlementGroups.count
            + settlementParticipants.count
            + transactions.count
            + budgetPlans.count
            + savingsGoals.count
            + recurringBillPlans.count
            + installmentPlans.count
            + dueOccurrences.count
            + investmentChannels.count
            + investmentAssets.count
            + investmentTrades.count
            + investmentPostings.count
    }

    var activeRowCount: Int {
        wallets.activeRemoteRowCount
            + creditCardProfiles.activeRemoteRowCount
            + categories.activeRemoteRowCount
            + settlementGroups.activeRemoteRowCount
            + settlementParticipants.activeRemoteRowCount
            + transactions.activeRemoteRowCount
            + budgetPlans.activeRemoteRowCount
            + savingsGoals.activeRemoteRowCount
            + recurringBillPlans.activeRemoteRowCount
            + installmentPlans.activeRemoteRowCount
            + dueOccurrences.activeRemoteRowCount
            + investmentChannels.activeRemoteRowCount
            + investmentAssets.activeRemoteRowCount
            + investmentTrades.activeRemoteRowCount
            + investmentPostings.activeRemoteRowCount
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

    var activeSettlementGroups: [RemoteSettlementGroup] {
        settlementGroups.filter { $0.deletedAt == nil }
    }

    var activeSettlementParticipants: [RemoteSettlementParticipant] {
        settlementParticipants.filter { $0.deletedAt == nil }
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

    var activeInvestmentChannels: [RemoteInvestmentChannel] { investmentChannels.filter { $0.deletedAt == nil } }
    var activeInvestmentAssets: [RemoteInvestmentAsset] { investmentAssets.filter { $0.deletedAt == nil } }
    var activeInvestmentTrades: [RemoteInvestmentTrade] { investmentTrades.filter { $0.deletedAt == nil } }
    var activeInvestmentPostings: [RemoteInvestmentWalletPosting] { investmentPostings.filter { $0.deletedAt == nil } }

    var fingerprint: String {
        let normalized = MistiaRemoteSnapshot(
            wallets: wallets.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            creditCardProfiles: creditCardProfiles.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            categories: categories.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            settlementGroups: settlementGroups.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            settlementParticipants: settlementParticipants.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            transactions: transactions.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            budgetPlans: budgetPlans.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            savingsGoals: savingsGoals.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            recurringBillPlans: recurringBillPlans.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            installmentPlans: installmentPlans.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            dueOccurrences: dueOccurrences.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            investmentChannels: investmentChannels.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            investmentAssets: investmentAssets.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            investmentTrades: investmentTrades.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) },
            investmentPostings: investmentPostings.sorted { MistiaStableUUIDOrdering.precedes($0.id, $1.id) }
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(MistiaISO8601DateCoding.stringWithFractionalSeconds(from: date))
        }
        guard let data = try? encoder.encode(normalized) else {
            return UUID().uuidString
        }
        return Self.hexDigest(for: data)
    }

    private static func hexDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)

        for byte in digest {
            bytes.append(hexadecimalBytes[Int(byte >> 4)])
            bytes.append(hexadecimalBytes[Int(byte & 0x0f)])
        }

        return String(decoding: bytes, as: UTF8.self)
    }

    private static let hexadecimalBytes = Array("0123456789abcdef".utf8)
}

private extension Array where Element: MistiaRemoteRow {
    nonisolated var activeRemoteRowCount: Int {
        reduce(into: 0) { count, row in
            if row.deletedAt == nil {
                count += 1
            }
        }
    }
}

nonisolated enum MistiaSyncUploadRecord: Sendable {
    case wallet(RemoteLedgerWallet)
    case creditCardProfile(RemoteCreditCardProfile)
    case category(RemoteTransactionCategory)
    case settlementGroup(RemoteSettlementGroup)
    case settlementParticipant(RemoteSettlementParticipant)
    case transaction(RemoteLedgerTransaction)
    case budgetPlan(RemoteBudgetPlan)
    case savingsGoal(RemoteSavingsGoal)
    case recurringBillPlan(RemoteRecurringBillPlan)
    case installmentPlan(RemoteInstallmentPlan)
    case dueOccurrence(RemoteDueOccurrenceRecord)
    case investmentChannel(RemoteInvestmentChannel)
    case investmentAsset(RemoteInvestmentAsset)
    case investmentTrade(RemoteInvestmentTrade)
    case investmentPosting(RemoteInvestmentWalletPosting)

    var entity: MistiaSyncEntity {
        switch self {
        case .wallet:
            .wallet
        case .creditCardProfile:
            .creditCardProfile
        case .category:
            .category
        case .settlementGroup:
            .settlementGroup
        case .settlementParticipant:
            .settlementParticipant
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
        case .investmentChannel: .investmentChannel
        case .investmentAsset: .investmentAsset
        case .investmentTrade: .investmentTrade
        case .investmentPosting: .investmentPosting
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
        case .settlementGroup(let row):
            row.id
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): row.id
        case .investmentAsset(let row): row.id
        case .investmentTrade(let row): row.id
        case .investmentPosting(let row): row.id
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
        case .settlementGroup(let row):
            row.updatedAt
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): row.updatedAt
        case .investmentAsset(let row): row.updatedAt
        case .investmentTrade(let row): row.updatedAt
        case .investmentPosting(let row): row.updatedAt
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
        case .settlementGroup(let row):
            row.userID
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): row.userID
        case .investmentAsset(let row): row.userID
        case .investmentTrade(let row): row.userID
        case .investmentPosting(let row): row.userID
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
        case .settlementGroup(let row):
            row.deletedAt
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): row.deletedAt
        case .investmentAsset(let row): row.deletedAt
        case .investmentTrade(let row): row.deletedAt
        case .investmentPosting(let row): row.deletedAt
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
        case .settlementGroup(let row):
            row.syncVersion
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): row.syncVersion
        case .investmentAsset(let row): row.syncVersion
        case .investmentTrade(let row): row.syncVersion
        case .investmentPosting(let row): row.syncVersion
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
        case .settlementGroup(let row):
            row.lastModifiedByDeviceID
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): row.lastModifiedByDeviceID
        case .investmentAsset(let row): row.lastModifiedByDeviceID
        case .investmentTrade(let row): row.lastModifiedByDeviceID
        case .investmentPosting(let row): row.lastModifiedByDeviceID
        }
    }

    var parentID: UUID? {
        if case .category(let row) = self {
            return row.parentCategoryID
        }
        return nil
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
                row.nameEnglish ?? "",
                row.nameJapanese ?? "",
                row.kindRawValue,
                row.iconSymbolName,
                row.iconColorHex,
                row.isFavorite ? "1" : "0",
                row.familyBudgetSpendingEnabled ? "1" : "0",
                row.parentCategoryID?.uuidString.lowercased() ?? "",
                row.hierarchyRoleRawValue ?? "",
                row.systemKey ?? "",
                row.isSystem ? "1" : "0",
                "\(row.sortOrder)",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .settlementGroup(let row):
            return [
                entity.rawValue,
                row.kindRawValue,
                row.statusRawValue,
                row.title,
                row.currencyCode,
                Self.dateString(row.occurredAt),
                "\(row.totalMinor)",
                "\(row.expectedMinor)",
                "\(row.settledMinor)",
                row.organizerUserID?.uuidString.lowercased() ?? "",
                row.note ?? "",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .settlementParticipant(let row):
            return [
                entity.rawValue,
                row.groupID.uuidString.lowercased(),
                row.displayName,
                row.normalizedKey ?? "",
                row.memberUserID?.uuidString.lowercased() ?? "",
                row.isSelf ? "1" : "0",
                "\(row.sortOrder)",
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .transaction(let row):
            let fields: [String] = [
                entity.rawValue,
                row.primaryKindRawValue,
                row.transferSubtypeRawValue ?? "",
                row.debtIntentRawValue ?? "",
                row.entryStatusRawValue,
                row.createdByUserID.uuidString.lowercased(),
                row.title,
                row.note ?? "",
                "\(row.amountMinor)",
                row.sourceCurrencyCode ?? "",
                row.destinationCurrencyCode ?? "",
                row.destinationAmountMinor.map(String.init) ?? "",
                row.reportingCurrencyCode ?? "",
                row.reportingAmountMinor.map(String.init) ?? "",
                row.conversionModeRawValue ?? "",
                row.exchangeRateDecimalString ?? "",
                row.exchangeRateProvider ?? "",
                row.exchangeRateDate ?? "",
                Self.dateString(row.occurredAt),
                row.counterpartyName ?? "",
                row.normalizedCounterpartyKey ?? "",
                row.settlementGroupID?.uuidString.lowercased() ?? "",
                row.settlementObligationID?.uuidString.lowercased() ?? "",
                row.settlementRoleRawValue ?? "",
                row.reportingExpenseMinor.map(String.init) ?? "",
                row.reportingIncomeMinor.map(String.init) ?? "",
                row.sourceWalletID?.uuidString.lowercased() ?? "",
                row.destinationWalletID?.uuidString.lowercased() ?? "",
                row.categoryID?.uuidString.lowercased() ?? "",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ]
            return fields.joined(separator: "|")
        case .budgetPlan(let row):
            return [
                entity.rawValue,
                row.categoryID?.uuidString.lowercased() ?? "",
                row.categoryIDSnapshot?.uuidString.lowercased() ?? "",
                row.categoryNameSnapshot ?? "",
                row.categoryNameEnglishSnapshot ?? "",
                row.categoryNameJapaneseSnapshot ?? "",
                row.categoryPathSnapshot ?? "",
                row.categoryPathEnglishSnapshot ?? "",
                row.categoryPathJapaneseSnapshot ?? "",
                row.categoryIconSymbolNameSnapshot ?? "",
                row.categoryColorHexSnapshot ?? "",
                row.categoryParentIDSnapshot?.uuidString.lowercased() ?? "",
                row.categoryParentNameSnapshot ?? "",
                row.categoryParentNameEnglishSnapshot ?? "",
                row.categoryParentNameJapaneseSnapshot ?? "",
                row.categoryParentIconSymbolNameSnapshot ?? "",
                row.categoryParentColorHexSnapshot ?? "",
                row.categoryHierarchyRoleSnapshotRawValue ?? "",
                row.categoryIsParentSnapshot.map { $0 ? "1" : "0" } ?? "",
                row.includesFamilySpending ? "1" : "0",
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
        case .investmentChannel(let row):
            return [
                entity.rawValue,
                row.name,
                row.iconSymbolName,
                row.iconColorHex,
                "\(row.sortOrder)",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .investmentAsset(let row):
            return [
                entity.rawValue,
                row.channelID.uuidString.lowercased(),
                row.name,
                row.currencyCode,
                row.imagePath ?? "",
                row.defaultUnitLabel ?? "",
                "\(row.sortOrder)",
                row.isArchived ? "1" : "0",
                Self.dateString(row.archivedAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .investmentTrade(let row):
            return [
                entity.rawValue,
                row.channelID.uuidString.lowercased(),
                row.assetID.uuidString.lowercased(),
                row.kindRawValue,
                row.quantityDecimalString,
                row.unitLabel ?? "",
                "\(row.grossAmountMinor)",
                row.currencyCode,
                "\(row.accountingGrossAmountMinor)",
                row.accountingCurrencyCode,
                row.exchangeRateDecimalString ?? "",
                row.exchangeRateProvider ?? "",
                row.exchangeRateDate ?? "",
                row.fundingWalletID?.uuidString.lowercased() ?? "",
                row.capitalReturnWalletID?.uuidString.lowercased() ?? "",
                row.fundingWalletCurrencyCode ?? "",
                row.capitalReturnWalletCurrencyCode ?? "",
                row.fundingWalletAmountMinor.map(String.init) ?? "",
                row.capitalReturnWalletAmountMinor.map(String.init) ?? "",
                row.fundingToAccountingRateDecimalString ?? "",
                row.accountingToCapitalReturnRateDecimalString ?? "",
                row.fundingLedgerTransactionID?.uuidString.lowercased() ?? "",
                row.capitalReturnLedgerTransactionID?.uuidString.lowercased() ?? "",
                row.profitLossLedgerTransactionID?.uuidString.lowercased() ?? "",
                "\(row.releasedCostBasisMinor)",
                "\(row.realizedProfitLossMinor)",
                row.positionQuantityAfterDecimalString,
                "\(row.positionCostBasisAfterMinor)",
                row.note ?? "",
                Self.dateString(row.occurredAt),
                Self.dateString(row.deletedAt)
            ].joined(separator: "|")
        case .investmentPosting(let row):
            return [
                entity.rawValue,
                row.eventID.uuidString.lowercased(),
                row.tradeID?.uuidString.lowercased() ?? "",
                row.assetID?.uuidString.lowercased() ?? "",
                row.walletID.uuidString.lowercased(),
                row.ledgerTransactionID.uuidString.lowercased(),
                row.roleRawValue,
                "\(row.amountMinor)",
                row.currencyCode,
                "\(row.accountingAmountMinor)",
                row.accountingCurrencyCode,
                Self.dateString(row.occurredAt),
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
        case .settlementGroup(let row):
            return row.title
        case .settlementParticipant(let row):
            return row.displayName
        case .transaction(let row):
            if row.title.isEmpty {
                return L10n.shared.sync.mistiasync.unnamedTransaction
            }
            return row.title
        case .budgetPlan:
            return L10n.shared.sync.mistiasync.budgetPlan
        case .savingsGoal(let row):
            return row.name
        case .recurringBillPlan(let row):
            return row.name
        case .installmentPlan(let row):
            return row.name
        case .dueOccurrence:
            return L10n.shared.sync.mistiasync.dueOccurrence
        case .investmentChannel(let row): return row.name
        case .investmentAsset(let row): return row.name
        case .investmentTrade(let row): return row.kindRawValue == InvestmentTradeKind.buy.rawValue ? L10n.investment.hub.buy : L10n.investment.hub.sell
        case .investmentPosting: return L10n.investment.wallet.detailTitle
        }
    }

    func preparedForCreate(deviceID: UUID, lastModifiedByUserID: UUID? = nil) -> MistiaSyncUploadRecord {
        preparedForMutation(nextVersion: 1, deviceID: deviceID, lastModifiedByUserID: lastModifiedByUserID)
    }

    func remappingCategoryReferences(_ mappings: [UUID: UUID]) -> MistiaSyncUploadRecord {
        guard !mappings.isEmpty else { return self }

        switch self {
        case .wallet, .creditCardProfile, .settlementGroup, .settlementParticipant, .savingsGoal, .installmentPlan, .dueOccurrence,
             .investmentChannel, .investmentAsset, .investmentTrade, .investmentPosting:
            return self
        case .category(var row):
            if let replacementID = mappings[row.id] {
                row.id = replacementID
            }
            if let parentCategoryID = row.parentCategoryID,
               let replacementParentID = mappings[parentCategoryID] {
                row.parentCategoryID = replacementParentID
            }
            return .category(row)
        case .transaction(var row):
            if let categoryID = row.categoryID,
               let replacementCategoryID = mappings[categoryID] {
                row.categoryID = replacementCategoryID
            }
            return .transaction(row)
        case .budgetPlan(var row):
            if let categoryID = row.categoryID,
               let replacementCategoryID = mappings[categoryID] {
                row.categoryID = replacementCategoryID
            }
            return .budgetPlan(row)
        case .recurringBillPlan(var row):
            if let categoryID = row.categoryID,
               let replacementCategoryID = mappings[categoryID] {
                row.categoryID = replacementCategoryID
            }
            return .recurringBillPlan(row)
        }
    }

    func preparedForMutation(nextVersion: Int64, deviceID: UUID, lastModifiedByUserID: UUID? = nil) -> MistiaSyncUploadRecord {
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
        case .settlementGroup(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .settlementGroup(row)
        case .settlementParticipant(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            return .settlementParticipant(row)
        case .transaction(var row):
            row.syncVersion = nextVersion
            row.lastModifiedByDeviceID = deviceID
            if let lastModifiedByUserID {
                row.lastModifiedByUserID = lastModifiedByUserID
            }
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
        case .investmentChannel(var row):
            row.syncVersion = nextVersion; row.lastModifiedByDeviceID = deviceID; return .investmentChannel(row)
        case .investmentAsset(var row):
            row.syncVersion = nextVersion; row.lastModifiedByDeviceID = deviceID; return .investmentAsset(row)
        case .investmentTrade(var row):
            row.syncVersion = nextVersion; row.lastModifiedByDeviceID = deviceID; return .investmentTrade(row)
        case .investmentPosting(var row):
            row.syncVersion = nextVersion; row.lastModifiedByDeviceID = deviceID; return .investmentPosting(row)
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
        case .settlementGroup(let row):
            data = try encoder.encode(row)
        case .settlementParticipant(let row):
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
        case .investmentChannel(let row): data = try encoder.encode(row)
        case .investmentAsset(let row): data = try encoder.encode(row)
        case .investmentTrade(let row): data = try encoder.encode(row)
        case .investmentPosting(let row): data = try encoder.encode(row)
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw MistiaSyncSerializationError.invalidResponse
        }
        return json
    }

    static func decode(entity: MistiaSyncEntity, jsonString: String) throws -> MistiaSyncUploadRecord {
        let decoder = JSONDecoder.mistiaRemoteAPIDecoder
        guard let data = jsonString.data(using: .utf8) else {
            throw MistiaSyncSerializationError.invalidResponse
        }

        switch entity {
        case .wallet:
            return .wallet(try decoder.decode(RemoteLedgerWallet.self, from: data))
        case .creditCardProfile:
            return .creditCardProfile(try decoder.decode(RemoteCreditCardProfile.self, from: data))
        case .category:
            return .category(try decoder.decode(RemoteTransactionCategory.self, from: data))
        case .settlementGroup:
            return .settlementGroup(try decoder.decode(RemoteSettlementGroup.self, from: data))
        case .settlementParticipant:
            return .settlementParticipant(try decoder.decode(RemoteSettlementParticipant.self, from: data))
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
        case .investmentChannel: return .investmentChannel(try decoder.decode(RemoteInvestmentChannel.self, from: data))
        case .investmentAsset: return .investmentAsset(try decoder.decode(RemoteInvestmentAsset.self, from: data))
        case .investmentTrade: return .investmentTrade(try decoder.decode(RemoteInvestmentTrade.self, from: data))
        case .investmentPosting: return .investmentPosting(try decoder.decode(RemoteInvestmentWalletPosting.self, from: data))
        }
    }

    private static func dateString(_ date: Date?) -> String {
        guard let date else { return "" }
        return MistiaISO8601DateCoding.stringWithFractionalSeconds(from: date)
    }
}

nonisolated extension MistiaRemoteSnapshot {
    nonisolated var uploadRecords: [MistiaSyncUploadRecord] {
        uploadRecords(where: { _ in true })
    }

    nonisolated func uploadRecords(
        where shouldInclude: (MistiaSyncUploadRecord) -> Bool
    ) -> [MistiaSyncUploadRecord] {
        var records: [MistiaSyncUploadRecord] = []
        records.reserveCapacity(totalRowCount)
        appendUploadRecords(to: &records, where: shouldInclude)
        return records
    }

    nonisolated var uploadRecordsByStorageKey: [String: MistiaSyncUploadRecord] {
        var recordsByKey: [String: MistiaSyncUploadRecord] = [:]
        recordsByKey.reserveCapacity(totalRowCount)
        forEachUploadRecord { record in
            recordsByKey[record.storageKey] = record
        }
        return recordsByKey
    }

    nonisolated var uploadRecordStorageKeys: Set<String> {
        var keys: Set<String> = []
        keys.reserveCapacity(totalRowCount)
        forEachUploadRecord { record in
            keys.insert(record.storageKey)
        }
        return keys
    }

    nonisolated func containsUploadRecord(
        where predicate: (MistiaSyncUploadRecord) -> Bool
    ) -> Bool {
        for row in wallets where predicate(.wallet(row)) { return true }
        for row in creditCardProfiles where predicate(.creditCardProfile(row)) { return true }
        for row in categories where predicate(.category(row)) { return true }
        for row in settlementGroups where predicate(.settlementGroup(row)) { return true }
        for row in settlementParticipants where predicate(.settlementParticipant(row)) { return true }
        for row in transactions where !InvestmentLedgerLegRole.isServerDerivedRawValue(row.settlementRoleRawValue) && predicate(.transaction(row)) { return true }
        for row in budgetPlans where predicate(.budgetPlan(row)) { return true }
        for row in savingsGoals where predicate(.savingsGoal(row)) { return true }
        for row in recurringBillPlans where predicate(.recurringBillPlan(row)) { return true }
        for row in installmentPlans where predicate(.installmentPlan(row)) { return true }
        for row in dueOccurrences where predicate(.dueOccurrence(row)) { return true }
        for row in investmentChannels where predicate(.investmentChannel(row)) { return true }
        for row in investmentAssets where predicate(.investmentAsset(row)) { return true }
        for row in investmentTrades where predicate(.investmentTrade(row)) { return true }
        return false
    }

    nonisolated private func forEachUploadRecord(_ body: (MistiaSyncUploadRecord) -> Void) {
        for row in wallets { body(.wallet(row)) }
        for row in creditCardProfiles { body(.creditCardProfile(row)) }
        for row in categories { body(.category(row)) }
        for row in settlementGroups { body(.settlementGroup(row)) }
        for row in settlementParticipants { body(.settlementParticipant(row)) }
        for row in transactions where !InvestmentLedgerLegRole.isServerDerivedRawValue(row.settlementRoleRawValue) {
            body(.transaction(row))
        }
        for row in budgetPlans { body(.budgetPlan(row)) }
        for row in savingsGoals { body(.savingsGoal(row)) }
        for row in recurringBillPlans { body(.recurringBillPlan(row)) }
        for row in installmentPlans { body(.installmentPlan(row)) }
        for row in dueOccurrences { body(.dueOccurrence(row)) }
        for row in investmentChannels { body(.investmentChannel(row)) }
        for row in investmentAssets { body(.investmentAsset(row)) }
        for row in investmentTrades { body(.investmentTrade(row)) }
    }

    private func appendUploadRecords(
        to records: inout [MistiaSyncUploadRecord],
        where shouldInclude: (MistiaSyncUploadRecord) -> Bool
    ) {
        for row in wallets {
            let record = MistiaSyncUploadRecord.wallet(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in creditCardProfiles {
            let record = MistiaSyncUploadRecord.creditCardProfile(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in categories {
            let record = MistiaSyncUploadRecord.category(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in settlementGroups {
            let record = MistiaSyncUploadRecord.settlementGroup(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in settlementParticipants {
            let record = MistiaSyncUploadRecord.settlementParticipant(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in transactions {
            guard !InvestmentLedgerLegRole.isServerDerivedRawValue(row.settlementRoleRawValue) else { continue }
            let record = MistiaSyncUploadRecord.transaction(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in budgetPlans {
            let record = MistiaSyncUploadRecord.budgetPlan(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in savingsGoals {
            let record = MistiaSyncUploadRecord.savingsGoal(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in recurringBillPlans {
            let record = MistiaSyncUploadRecord.recurringBillPlan(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in installmentPlans {
            let record = MistiaSyncUploadRecord.installmentPlan(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in dueOccurrences {
            let record = MistiaSyncUploadRecord.dueOccurrence(row)
            if shouldInclude(record) { records.append(record) }
        }
        for row in investmentChannels { let record = MistiaSyncUploadRecord.investmentChannel(row); if shouldInclude(record) { records.append(record) } }
        for row in investmentAssets { let record = MistiaSyncUploadRecord.investmentAsset(row); if shouldInclude(record) { records.append(record) } }
        for row in investmentTrades { let record = MistiaSyncUploadRecord.investmentTrade(row); if shouldInclude(record) { records.append(record) } }
    }
}

nonisolated extension MistiaSyncUploadRecord {
    var storageKey: String {
        "\(entity.rawValue):\(id.uuidString.lowercased())"
    }
}

nonisolated extension MistiaSyncEntity {
    var displayTitle: String {
        switch self {
        case .wallet:
            return L10n.shared.sync.mistiasync.wallet
        case .creditCardProfile:
            return L10n.shared.sync.mistiasync.creditCard
        case .category:
            return L10n.shared.sync.mistiasync.category
        case .settlementGroup:
            return "Settlement"
        case .settlementParticipant:
            return "Settlement participant"
        case .transaction:
            return L10n.shared.sync.mistiasync.transaction
        case .budgetPlan:
            return L10n.shared.sync.mistiasync.budget
        case .savingsGoal:
            return L10n.shared.sync.mistiasync.goal
        case .recurringBillPlan:
            return L10n.shared.sync.mistiasync.bill
        case .installmentPlan:
            return L10n.shared.sync.mistiasync.installment
        case .dueOccurrenceRecord:
            return L10n.shared.sync.mistiasync.dueOccurrence
        case .investmentChannel, .investmentAsset, .investmentTrade, .investmentPosting:
            return L10n.investment.title
        }
    }
}

extension MistiaSyncConflictKind {
    var localizedTitle: String {
        switch self {
        case .createCreate:
            return L10n.shared.sync.mistiasync.duplicateCreate
        case .editEdit:
            return L10n.shared.sync.mistiasync.editedOnTwoDevices
        case .editDelete:
            return L10n.shared.sync.mistiasync.editedHereDeletedInCloud
        case .deleteEdit:
            return L10n.shared.sync.mistiasync.deletedHereEditedInCloud
        }
    }

    var localActionTitle: String {
        switch self {
        case .editDelete:
            return L10n.shared.sync.mistiasync.restoreRecord
        default:
            return L10n.shared.sync.mistiasync.useThisDeviceSVersion
        }
    }

    var remoteActionTitle: String {
        switch self {
        case .deleteEdit:
            return L10n.shared.sync.mistiasync.keepDeleted
        default:
            return L10n.shared.sync.mistiasync.useCloudVersion
        }
    }
}

extension JSONDecoder {
    fileprivate nonisolated static func threadCached(key: String, configure: () -> JSONDecoder) -> JSONDecoder {
        let threadDict = Thread.current.threadDictionary
        if let cached = threadDict[key] as? JSONDecoder { return cached }
        let decoder = configure()
        threadDict[key] = decoder
        return decoder
    }

    nonisolated static var mistiaSyncDecoder: JSONDecoder {
        threadCached(key: "MistiaSyncJSONDecoder.mistiaSyncDecoder") {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                if let date = MistiaISO8601DateCoding.date(from: value) {
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

    nonisolated static var mistiaBackupDecoder: JSONDecoder {
        threadCached(key: "MistiaSyncJSONDecoder.mistiaBackupDecoder") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                if let date = MistiaISO8601DateCoding.date(from: value) {
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

    nonisolated static var mistiaRemoteAPIDecoder: JSONDecoder {
        mistiaBackupDecoder
    }
}

extension JSONEncoder {
    fileprivate nonisolated static func threadCached(key: String, configure: () -> JSONEncoder) -> JSONEncoder {
        let threadDict = Thread.current.threadDictionary
        if let cached = threadDict[key] as? JSONEncoder { return cached }
        let encoder = configure()
        threadDict[key] = encoder
        return encoder
    }

    nonisolated static var mistiaSyncEncoder: JSONEncoder {
        threadCached(key: "MistiaSyncJSONEncoder.mistiaSyncEncoder") {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(MistiaISO8601DateCoding.stringWithFractionalSeconds(from: date))
            }
            return encoder
        }
    }

    nonisolated static var mistiaBackupEncoder: JSONEncoder {
        threadCached(key: "MistiaSyncJSONEncoder.mistiaBackupEncoder") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(MistiaISO8601DateCoding.stringWithFractionalSeconds(from: date))
            }
            return encoder
        }
    }

    static var mistiaRemoteAPIEncoder: JSONEncoder {
        mistiaBackupEncoder
    }
}

extension ISO8601DateFormatter {
    static var mistiaSyncWithFractionalSeconds: ISO8601DateFormatter {
        MistiaISO8601DateCoding.formatter(
            cacheKey: "MistiaSyncISO8601WithFractionalSecondsFormatter",
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
    }

    static var mistiaSyncWithoutFractionalSeconds: ISO8601DateFormatter {
        MistiaISO8601DateCoding.formatter(
            cacheKey: "MistiaSyncISO8601WithoutFractionalSecondsFormatter",
            formatOptions: [.withInternetDateTime]
        )
    }

    static var mistiaRemoteAPI: ISO8601DateFormatter {
        mistiaSyncWithFractionalSeconds
    }
}
