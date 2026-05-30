import Foundation
import SwiftData

@Model
final class LedgerWallet: Identifiable, Hashable {
    static func == (lhs: LedgerWallet, rhs: LedgerWallet) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Attribute(.unique) var id: UUID
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
    var remoteVersion: Int64
    var creditCardProfile: CreditCardProfile?

    init(
        id: UUID = UUID(),
        name: String,
        kind: LedgerWalletKind,
        iconSymbolName: String,
        iconColorHex: String,
        currencyCode: String = "JPY",
        openingBalanceMinor: Int64 = 0,
        institutionDisplayName: String? = nil,
        institutionPresetKey: String? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.iconSymbolName = iconSymbolName
        self.iconColorHex = iconColorHex
        self.currencyCode = currencyCode
        self.openingBalanceMinor = openingBalanceMinor
        self.institutionDisplayName = institutionDisplayName
        self.institutionPresetKey = institutionPresetKey
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

    var kind: LedgerWalletKind {
        get { LedgerWalletKind(rawValue: kindRawValue) ?? .cash }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class CreditCardProfile {
    @Attribute(.unique) var id: UUID
    var issuerName: String
    var networkRawValue: String
    var last4: String
    var creditLimitMinor: Int64
    var statementClosingDay: Int
    var paymentDueDay: Int
    var notes: String?
    var autoPayEnabled: Bool = true
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64
    var wallet: LedgerWallet?
    var paymentSourceWallet: LedgerWallet?

    init(
        id: UUID = UUID(),
        issuerName: String = "",
        network: CreditCardNetwork = .visa,
        last4: String = "",
        creditLimitMinor: Int64 = 0,
        statementClosingDay: Int = 25,
        paymentDueDay: Int = 10,
        notes: String? = nil,
        autoPayEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0,
        wallet: LedgerWallet? = nil,
        paymentSourceWallet: LedgerWallet? = nil
    ) {
        self.id = id
        self.issuerName = issuerName
        self.networkRawValue = network.rawValue
        self.last4 = last4
        self.creditLimitMinor = creditLimitMinor
        self.statementClosingDay = statementClosingDay
        self.paymentDueDay = paymentDueDay
        self.notes = notes
        self.autoPayEnabled = autoPayEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
        self.wallet = wallet
        self.paymentSourceWallet = paymentSourceWallet
    }

    var network: CreditCardNetwork {
        get { CreditCardNetwork(rawValue: networkRawValue) ?? .visa }
        set { networkRawValue = newValue.rawValue }
    }
}

@Model
final class TransactionCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var nameEnglish: String?
    var nameJapanese: String?
    var pendingTranslationSourceName: String?
    var pendingTranslationSourceLanguageRawValue: String?
    var kindRawValue: String
    var iconSymbolName: String
    var iconColorHex: String
    var favoriteRawValue: Bool?
    var parentCategory: TransactionCategory?
    @Relationship(deleteRule: .nullify, inverse: \TransactionCategory.parentCategory) var childCategories: [TransactionCategory] = []
    var hierarchyRoleRawValue: String?
    var systemKey: String?
    var isSystem: Bool
    var cloudSyncEnabled: Bool
    var sortOrder: Int
    var isArchived: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var remoteVersion: Int64

    init(
        id: UUID = UUID(),
        name: String,
        nameEnglish: String? = nil,
        nameJapanese: String? = nil,
        pendingTranslationSourceName: String? = nil,
        pendingTranslationSourceLanguageRawValue: String? = nil,
        kind: TransactionCategoryKind,
        iconSymbolName: String,
        iconColorHex: String,
        isFavorite: Bool = false,
        parentCategory: TransactionCategory? = nil,
        hierarchyRole: TransactionCategoryHierarchyRole? = nil,
        systemKey: String? = nil,
        isSystem: Bool = false,
        cloudSyncEnabled: Bool = false,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.nameEnglish = nameEnglish
        self.nameJapanese = nameJapanese
        self.pendingTranslationSourceName = pendingTranslationSourceName
        self.pendingTranslationSourceLanguageRawValue = pendingTranslationSourceLanguageRawValue
        self.kindRawValue = kind.rawValue
        self.iconSymbolName = iconSymbolName
        self.iconColorHex = iconColorHex
        self.favoriteRawValue = isFavorite
        self.parentCategory = parentCategory
        self.hierarchyRoleRawValue = hierarchyRole?.rawValue
        self.systemKey = systemKey
        self.isSystem = isSystem
        self.cloudSyncEnabled = cloudSyncEnabled
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
    }

    var kind: TransactionCategoryKind {
        get { TransactionCategoryKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }

    var isFavorite: Bool {
        get { favoriteRawValue ?? false }
        set { favoriteRawValue = newValue }
    }

    var hierarchyRole: TransactionCategoryHierarchyRole {
        get {
            if let hierarchyRoleRawValue,
               let storedRole = TransactionCategoryHierarchyRole(rawValue: hierarchyRoleRawValue) {
                return storedRole
            }
            return parentCategory == nil ? .parent : .child
        }
        set {
            hierarchyRoleRawValue = newValue.rawValue
        }
    }
}

@Model
final class LedgerTransaction {
    @Attribute(.unique) var id: UUID
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
    var deletedAt: Date?
    var remoteVersion: Int64
    var counterpartyName: String?
    var normalizedCounterpartyKey: String?
    var isArchived: Bool
    var archivedAt: Date?

    @Relationship(deleteRule: .nullify) var sourceWallet: LedgerWallet?
    @Relationship(deleteRule: .nullify) var destinationWallet: LedgerWallet?
    @Relationship(deleteRule: .nullify) var category: TransactionCategory?

    init(
        id: UUID = UUID(),
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        entryStatus: TransactionEntryStatus = .posted,
        title: String = "",
        note: String? = nil,
        amountMinor: Int64,
        sourceCurrencyCode: String? = nil,
        destinationCurrencyCode: String? = nil,
        destinationAmountMinor: Int64? = nil,
        reportingCurrencyCode: String? = nil,
        reportingAmountMinor: Int64? = nil,
        conversionModeRawValue: String? = nil,
        exchangeRateDecimalString: String? = nil,
        exchangeRateProvider: String? = nil,
        exchangeRateDate: String? = nil,
        occurredAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        remoteVersion: Int64 = 0,
        sourceWallet: LedgerWallet? = nil,
        destinationWallet: LedgerWallet? = nil,
        category: TransactionCategory? = nil,
        counterpartyName: String? = nil,
        normalizedCounterpartyKey: String? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.primaryKindRawValue = primaryKind.rawValue
        self.transferSubtypeRawValue = transferSubtype?.rawValue
        self.debtIntentRawValue = debtIntent?.rawValue
        self.entryStatusRawValue = entryStatus.rawValue
        self.title = title
        self.note = note
        self.amountMinor = amountMinor
        self.sourceCurrencyCode = sourceCurrencyCode
        self.destinationCurrencyCode = destinationCurrencyCode
        self.destinationAmountMinor = destinationAmountMinor
        self.reportingCurrencyCode = reportingCurrencyCode
        self.reportingAmountMinor = reportingAmountMinor
        self.conversionModeRawValue = conversionModeRawValue
        self.exchangeRateDecimalString = exchangeRateDecimalString
        self.exchangeRateProvider = exchangeRateProvider
        self.exchangeRateDate = exchangeRateDate
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.remoteVersion = remoteVersion
        self.sourceWallet = sourceWallet
        self.destinationWallet = destinationWallet
        self.category = category
        self.counterpartyName = counterpartyName
        self.normalizedCounterpartyKey = normalizedCounterpartyKey
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }

    var primaryKind: TransactionPrimaryKind {
        get { TransactionPrimaryKind(rawValue: primaryKindRawValue) ?? .expense }
        set { primaryKindRawValue = newValue.rawValue }
    }

    var transferSubtype: TransactionTransferSubtype? {
        get {
            guard let transferSubtypeRawValue else { return nil }
            return TransactionTransferSubtype(rawValue: transferSubtypeRawValue)
        }
        set {
            transferSubtypeRawValue = newValue?.rawValue
        }
    }

    var debtIntent: TransactionDebtIntent? {
        get {
            guard let debtIntentRawValue else { return nil }
            return TransactionDebtIntent(rawValue: debtIntentRawValue)
        }
        set {
            debtIntentRawValue = newValue?.rawValue
        }
    }

    var entryStatus: TransactionEntryStatus {
        get { TransactionEntryStatus(rawValue: entryStatusRawValue) ?? .posted }
        set { entryStatusRawValue = newValue.rawValue }
    }
}

@Model
final class TransactionReceiptImage {
    @Attribute(.unique) var id: UUID
    var transactionID: UUID
    var imageFileName: String
    var thumbnailFileName: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        transactionID: UUID,
        imageFileName: String,
        thumbnailFileName: String,
        contentType: String = "image/jpeg",
        byteCount: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.transactionID = transactionID
        self.imageFileName = imageFileName
        self.thumbnailFileName = thumbnailFileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
