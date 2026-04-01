import Foundation
import SwiftUI
import UIKit

struct ManagementCategorySeed {
    let name: String
    let kind: TransactionCategoryKind
    let iconSymbolName: String
    let iconColorHex: String
}

struct JapaneseBankPreset: Identifiable, Hashable {
    let key: String
    let name: String

    var id: String { key }
}

enum ManagementDataActionKind: String, Identifiable, CaseIterable {
    case exportData
    case importData
    case backupRestore
    case deleteAllData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exportData:
            "Xuất dữ liệu"
        case .importData:
            "Nhập dữ liệu"
        case .backupRestore:
            "Backup & khôi phục"
        case .deleteAllData:
            "Xóa tất cả dữ liệu"
        }
    }

    var iconSymbolName: String {
        switch self {
        case .exportData:
            "square.and.arrow.up.fill"
        case .importData:
            "square.and.arrow.down.fill"
        case .backupRestore:
            "externaldrive.fill.badge.icloud"
        case .deleteAllData:
            "trash.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .exportData:
            Color(hex: "#5B7BFF")
        case .importData:
            Color(hex: "#5FAEFF")
        case .backupRestore:
            Color(hex: "#2DAA9E")
        case .deleteAllData:
            Color(hex: "#F45C7E")
        }
    }
}

enum ManagementPresetData {
    static let iconSymbols: [String] = [
        "banknote.fill",
        "wallet.pass.fill",
        "building.columns.fill",
        "creditcard.fill",
        "car.fill",
        "fork.knife",
        "bag.fill",
        "airplane",
        "house.fill",
        "bolt.fill",
        "cross.case.fill",
        "briefcase.fill",
        "gift.fill",
        "heart.fill",
        "storefront.fill",
        "chart.line.uptrend.xyaxis",
        "party.popper.fill",
        "figure.walk",
        "tram.fill",
        "cart.fill",
        "film.fill",
        "book.fill",
        "graduationcap.fill",
        "gamecontroller.fill",
        "sparkles"
    ]

    static let japaneseBanks: [JapaneseBankPreset] = [
        JapaneseBankPreset(key: "mufg", name: "MUFG Bank"),
        JapaneseBankPreset(key: "smbc", name: "SMBC"),
        JapaneseBankPreset(key: "mizuho", name: "Mizuho Bank"),
        JapaneseBankPreset(key: "jp_post", name: "Japan Post Bank"),
        JapaneseBankPreset(key: "rakuten", name: "Rakuten Bank"),
        JapaneseBankPreset(key: "paypay_bank", name: "PayPay Bank"),
        JapaneseBankPreset(key: "sbi_shinsei", name: "SBI Shinsei Bank"),
        JapaneseBankPreset(key: "sbi_sumishin", name: "SBI Sumishin Net Bank"),
        JapaneseBankPreset(key: "seven_bank", name: "Seven Bank"),
        JapaneseBankPreset(key: "resona", name: "Resona Bank"),
        JapaneseBankPreset(key: "au_jibun", name: "au Jibun Bank")
    ]

    static let defaultCategorySeeds: [ManagementCategorySeed] = [
        ManagementCategorySeed(name: "Ăn uống", kind: .expense, iconSymbolName: "fork.knife", iconColorHex: "#F59B3F"),
        ManagementCategorySeed(name: "Đi chơi", kind: .expense, iconSymbolName: "party.popper.fill", iconColorHex: "#F26A5A"),
        ManagementCategorySeed(name: "Du lịch", kind: .expense, iconSymbolName: "airplane", iconColorHex: "#5B7BFF"),
        ManagementCategorySeed(name: "Mua sắm", kind: .expense, iconSymbolName: "bag.fill", iconColorHex: "#FF7E67"),
        ManagementCategorySeed(name: "Di chuyển", kind: .expense, iconSymbolName: "train.side.front.car", iconColorHex: "#2DAA9E"),
        ManagementCategorySeed(name: "Nhà ở", kind: .expense, iconSymbolName: "house.fill", iconColorHex: "#7C85A3"),
        ManagementCategorySeed(name: "Hóa đơn", kind: .expense, iconSymbolName: "bolt.fill", iconColorHex: "#FFB13B"),
        ManagementCategorySeed(name: "Sức khỏe", kind: .expense, iconSymbolName: "cross.case.fill", iconColorHex: "#F45C7E"),
        ManagementCategorySeed(name: "Lương", kind: .income, iconSymbolName: "briefcase.fill", iconColorHex: "#2DAA9E"),
        ManagementCategorySeed(name: "Thưởng", kind: .income, iconSymbolName: "gift.fill", iconColorHex: "#F59B3F"),
        ManagementCategorySeed(name: "Freelance", kind: .income, iconSymbolName: "laptopcomputer", iconColorHex: "#5B7BFF"),
        ManagementCategorySeed(name: "Đầu tư", kind: .income, iconSymbolName: "chart.line.uptrend.xyaxis", iconColorHex: "#57B7FF"),
        ManagementCategorySeed(name: "Hoàn tiền", kind: .income, iconSymbolName: "arrow.counterclockwise.circle.fill", iconColorHex: "#7C85A3"),
        ManagementCategorySeed(name: "Bán hàng", kind: .income, iconSymbolName: "storefront.fill", iconColorHex: "#F26A5A"),
        ManagementCategorySeed(name: "Quà tặng", kind: .income, iconSymbolName: "heart.fill", iconColorHex: "#F45C7E"),
        ManagementCategorySeed(name: "Khác", kind: .income, iconSymbolName: "plus.circle.fill", iconColorHex: "#9A67FF")
    ]
}

extension LedgerWallet {
    var iconColor: Color {
        Color(hex: iconColorHex)
    }

    var formattedAmount: String {
        openingBalanceMinor.formattedCurrency(code: currencyCode)
    }

    var subtitleText: String? {
        switch kind {
        case .cash, .payPay:
            return nil
        case .bank:
            return institutionDisplayName
        case .creditCard:
            let issuer = creditCardProfile?.issuerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = creditCardProfile?.last4.trimmingCharacters(in: .whitespacesAndNewlines)

            switch (issuer?.isEmpty == false ? issuer : nil, suffix?.isEmpty == false ? suffix : nil) {
            case let (issuer?, suffix?):
                return "\(issuer) • \(suffix)"
            case let (issuer?, nil):
                return issuer
            case let (nil, suffix?):
                return "•••• \(suffix)"
            default:
                return "Thẻ tín dụng"
            }
        }
    }

    var footnoteText: String? {
        guard kind == .creditCard, let profile = creditCardProfile else { return nil }
        return "Chốt sao kê ngày \(profile.statementClosingDay), thanh toán ngày \(profile.paymentDueDay)"
    }
}

extension TransactionCategory {
    var iconColor: Color {
        Color(hex: iconColorHex)
    }
}

extension Color {
    init(hex: String) {
        let sanitized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        let value = UInt64(sanitized, radix: 16) ?? 0
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch sanitized.count {
        case 8:
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
            alpha = Double(value & 0x0000_00FF) / 255
        default:
            red = Double((value & 0xFF00_00) >> 16) / 255
            green = Double((value & 0x00FF_00) >> 8) / 255
            blue = Double(value & 0x0000_FF) / 255
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        UIColor(self).hexString
    }
}

extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#8A8A8E"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}

extension Int64 {
    func formattedCurrency(code: String) -> String {
        let uppercaseCode = code.uppercased()
        let fractionDigits = uppercaseCode == "JPY" ? 0 : 2
        let amount = decimalCurrencyAmount(fractionDigits: fractionDigits)
        let locale = Locale(identifier: uppercaseCode == "JPY" ? "ja_JP" : "en_US_POSIX")

        return amount.formatted(
            .currency(code: uppercaseCode)
                .precision(.fractionLength(fractionDigits))
                .locale(locale)
        )
    }

    private func decimalCurrencyAmount(fractionDigits: Int) -> Decimal {
        guard fractionDigits > 0 else { return Decimal(self) }

        var divisor = Decimal(1)
        for _ in 0..<fractionDigits {
            divisor *= 10
        }

        return Decimal(self) / divisor
    }
}
