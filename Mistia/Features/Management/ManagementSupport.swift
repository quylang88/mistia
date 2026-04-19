import Foundation
import SwiftUI
import UIKit

struct ManagementCategorySeed {
    let name: String
    let kind: TransactionCategoryKind
    let iconSymbolName: String
    let fallbackSystemName: String
    let iconColorHex: String
    let pickerGroup: MistiaFinanceIconGroup
    let systemKey: MistiaSystemCategoryKey?
    let startsArchived: Bool

    init(
        name: String,
        kind: TransactionCategoryKind,
        iconSymbolName: String,
        fallbackSystemName: String,
        iconColorHex: String,
        pickerGroup: MistiaFinanceIconGroup,
        systemKey: MistiaSystemCategoryKey? = nil,
        startsArchived: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.iconSymbolName = iconSymbolName
        self.fallbackSystemName = fallbackSystemName
        self.iconColorHex = MistiaIconColorPalette.presetHex(forDefault: iconColorHex)
        self.pickerGroup = pickerGroup
        self.systemKey = systemKey
        self.startsArchived = startsArchived
    }
}

struct ManagementCategoryParentSeed {
    let name: String
    let kind: TransactionCategoryKind
    let iconSymbolName: String
    let fallbackSystemName: String
    let iconColorHex: String
    let pickerGroup: MistiaFinanceIconGroup
    let systemKey: MistiaSystemCategoryParentKey
}

struct JapaneseBankPreset: Identifiable, Hashable {
    let key: String
    let name: String

    var id: String { key }
}

enum ManagementDataActionKind: String, Identifiable, CaseIterable {
    case archivedItems
    case exportData
    case importData
    case backupRestore
    case deleteAllData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .archivedItems:
            mistiaLocalized(vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム")
        case .exportData:
            mistiaLocalized(vi: "Xuất dữ liệu", en: "Export data", ja: "データを書き出す")
        case .importData:
            mistiaLocalized(vi: "Nhập dữ liệu", en: "Import data", ja: "データを取り込む")
        case .backupRestore:
            mistiaLocalized(vi: "Sao lưu & khôi phục", en: "Backup & restore", ja: "バックアップ & 復元")
        case .deleteAllData:
            mistiaLocalized(vi: "Xóa tất cả dữ liệu", en: "Delete all data", ja: "すべてのデータを削除")
        }
    }

    var iconSymbolName: String {
        switch self {
        case .archivedItems:
            "archivebox"
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
        case .archivedItems:
            Color(hex: "#A0A0A0")
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

    static let defaultCategoryParentSeeds: [ManagementCategoryParentSeed] =
        MistiaSystemCategoryParentKey.activeDefaults.map { systemKey in
            ManagementCategoryParentSeed(
                name: systemKey.title,
                kind: systemKey.kind,
                iconSymbolName: systemKey.iconSymbolName,
                fallbackSystemName: systemKey.fallbackSystemName,
                iconColorHex: MistiaIconColorPalette.presetHex(forDefault: systemKey.iconColorHex),
                pickerGroup: systemKey.pickerGroup,
                systemKey: systemKey
            )
        }

    static let defaultCategorySeeds: [ManagementCategorySeed] =
        MistiaSystemCategoryKey.activeDefaults.map { systemKey in
            ManagementCategorySeed(
                name: systemKey.title,
                kind: systemKey.kind,
                iconSymbolName: systemKey.iconSymbolName,
                fallbackSystemName: systemKey.fallbackSystemName,
                iconColorHex: systemKey.iconColorHex,
                pickerGroup: systemKey.pickerGroup,
                systemKey: systemKey
            )
        }
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
        case .cash, .payPay, .eWallet, .prepaid, .investment, .crypto, .other:
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
                return mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード")
            }
        }
    }

    var footnoteText: String? {
        guard kind == .creditCard, let profile = creditCardProfile else { return nil }
        return mistiaLocalized(
            vi: "Chốt sao kê ngày \(profile.statementClosingDay), thanh toán ngày \(profile.paymentDueDay)",
            en: "Statement closes on day \(profile.statementClosingDay), payment due on day \(profile.paymentDueDay)",
            ja: "締め日は毎月 \(profile.statementClosingDay) 日、支払日は毎月 \(profile.paymentDueDay) 日です"
        )
    }
}

extension TransactionCategory {
    var iconColor: Color {
        Color(hex: iconColorHex)
    }

    var mistiaSystemCategoryParentKey: MistiaSystemCategoryParentKey? {
        guard let systemKey else { return nil }
        return MistiaSystemCategoryParentKey(rawValue: systemKey)
    }

    var mistiaSystemCategoryKey: MistiaSystemCategoryKey? {
        guard let systemKey else { return nil }
        return MistiaSystemCategoryKey(rawValue: systemKey)
    }

    var localizedDisplayName: String {
        if let mistiaSystemCategoryParentKey {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let knownDefaultNames = Set(mistiaSystemCategoryParentKey.knownDefaultNames())
            if knownDefaultNames.contains(trimmedName) {
                return mistiaSystemCategoryParentKey.localizedTitle(for: .current)
            }
        }

        guard let mistiaSystemCategoryKey else { return name }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownDefaultNames = Set(mistiaSystemCategoryKey.knownDefaultNames())
        guard knownDefaultNames.contains(trimmedName) else { return name }
        return mistiaSystemCategoryKey.localizedTitle(for: .current)
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
