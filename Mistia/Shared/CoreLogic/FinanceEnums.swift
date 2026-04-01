import Foundation

enum LedgerWalletKind: String, CaseIterable, Identifiable, Codable {
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

    var defaultIconSymbolName: String {
        switch self {
        case .expense:
            "fork.knife"
        case .income:
            "briefcase.fill"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .expense:
            "#F59B3F"
        case .income:
            "#2DAA9E"
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

enum TransactionPrimaryKind: String, CaseIterable, Identifiable, Codable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            "Chi tiêu"
        case .income:
            "Thu nhập"
        case .transfer:
            "Chuyển tiền"
        }
    }

    var systemImage: String {
        switch self {
        case .expense:
            "arrow.up.right"
        case .income:
            "arrow.down.left"
        case .transfer:
            "arrow.left.arrow.right"
        }
    }
}

enum TransactionTransferSubtype: String, CaseIterable, Identifiable, Codable {
    case internalTransfer
    case debt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalTransfer:
            "Nội bộ"
        case .debt:
            "Công nợ"
        }
    }

    var systemImage: String {
        switch self {
        case .internalTransfer:
            "arrow.left.arrow.right.circle"
        case .debt:
            "person.2.wave.2.fill"
        }
    }
}

enum TransactionDebtIntent: String, CaseIterable, Identifiable, Codable {
    case lend
    case collect
    case borrow
    case repay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lend:
            "Cho vay"
        case .collect:
            "Thu nợ"
        case .borrow:
            "Đi vay"
        case .repay:
            "Trả nợ"
        }
    }

    var systemImage: String {
        switch self {
        case .lend:
            "arrow.up.right.circle.fill"
        case .collect:
            "arrow.down.left.circle.fill"
        case .borrow:
            "tray.and.arrow.down.fill"
        case .repay:
            "tray.and.arrow.up.fill"
        }
    }
}

enum TransactionEntryStatus: String, CaseIterable, Identifiable, Codable {
    case posted
    case draft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posted:
            "Đã ghi nhận"
        case .draft:
            "Bản nháp"
        }
    }
}

enum TransactionTimeScope: String, CaseIterable, Identifiable, Codable {
    case allTime
    case thisMonth
    case yesterday
    case today

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime:
            "Tất cả"
        case .thisMonth:
            "Tháng này"
        case .yesterday:
            "Hôm qua"
        case .today:
            "Hôm nay"
        }
    }
}

enum TransactionStatusScope: String, CaseIterable, Identifiable, Codable {
    case all
    case postedOnly
    case draftOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "Tất cả"
        case .postedOnly:
            "Đã ghi nhận"
        case .draftOnly:
            "Bản nháp"
        }
    }
}
