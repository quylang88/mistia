import Foundation
import SwiftData

enum LedgerAccountKind: String, CaseIterable, Identifiable, Codable {
    case cash
    case payPay
    case bank
    case creditCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash:
            "Tiền mặt"
        case .payPay:
            "PayPay"
        case .bank:
            "Ngân hàng"
        case .creditCard:
            "Credit card"
        }
    }

    var defaultIconSymbolName: String {
        switch self {
        case .cash:
            "banknote.fill"
        case .payPay:
            "wallet.pass.fill"
        case .bank:
            "building.columns.fill"
        case .creditCard:
            "creditcard.fill"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .cash:
            "#2DAA9E"
        case .payPay:
            "#F26A5A"
        case .bank:
            "#5B7BFF"
        case .creditCard:
            "#7C85A3"
        }
    }

    var balanceFieldTitle: String {
        switch self {
        case .creditCard:
            "Dư nợ hiện tại"
        default:
            "Số dư ban đầu"
        }
    }
}

enum TransactionCategoryKind: String, CaseIterable, Identifiable, Codable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            "Chi tiêu"
        case .income:
            "Thu nhập"
        }
    }
}

enum CreditCardNetwork: String, CaseIterable, Identifiable, Codable {
    case visa
    case mastercard
    case jcb
    case americanExpress
    case unionPay
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visa:
            "Visa"
        case .mastercard:
            "Mastercard"
        case .jcb:
            "JCB"
        case .americanExpress:
            "American Express"
        case .unionPay:
            "UnionPay"
        case .other:
            "Khác"
        }
    }
}

@Model
final class LedgerAccount {
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
    var createdAt: Date
    var updatedAt: Date
    var creditCardProfile: CreditCardProfile?

    init(
        id: UUID = UUID(),
        name: String,
        kind: LedgerAccountKind,
        iconSymbolName: String,
        iconColorHex: String,
        currencyCode: String = "JPY",
        openingBalanceMinor: Int64 = 0,
        institutionDisplayName: String? = nil,
        institutionPresetKey: String? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: LedgerAccountKind {
        get { LedgerAccountKind(rawValue: kindRawValue) ?? .cash }
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
    var createdAt: Date
    var updatedAt: Date
    var account: LedgerAccount?
    var paymentSourceAccount: LedgerAccount?

    init(
        id: UUID = UUID(),
        issuerName: String = "",
        network: CreditCardNetwork = .visa,
        last4: String = "",
        creditLimitMinor: Int64 = 0,
        statementClosingDay: Int = 25,
        paymentDueDay: Int = 10,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        account: LedgerAccount? = nil,
        paymentSourceAccount: LedgerAccount? = nil
    ) {
        self.id = id
        self.issuerName = issuerName
        self.networkRawValue = network.rawValue
        self.last4 = last4
        self.creditLimitMinor = creditLimitMinor
        self.statementClosingDay = statementClosingDay
        self.paymentDueDay = paymentDueDay
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.account = account
        self.paymentSourceAccount = paymentSourceAccount
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
    var kindRawValue: String
    var iconSymbolName: String
    var iconColorHex: String
    var isSystem: Bool
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: TransactionCategoryKind,
        iconSymbolName: String,
        iconColorHex: String,
        isSystem: Bool = false,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.iconSymbolName = iconSymbolName
        self.iconColorHex = iconColorHex
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: TransactionCategoryKind {
        get { TransactionCategoryKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }
}
