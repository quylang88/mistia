import SwiftUI
import UIKit

enum MistiaAppStorageKey {
    static let appearanceMode = "mistia.appearance.mode"
    static let hideQuickCreate = "mistia.chrome.hideQuickCreate"
    static let didSeedManagementCategories = "mistia.management.didSeedCategories"
    static let currencyCode = "mistia.settings.currency.code"
    static let appLanguage = MistiaAppLanguage.userDefaultsKey
    static let syncAutoEnabled = "mistia.sync.auto.enabled"
    static let sessionProfileOverridePrefix = "mistia.session.profile.override"
}

enum MistiaAppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            mistiaLocalized(vi: "Tự động", en: "Automatic", ja: "自動")
        case .dark:
            mistiaLocalized(vi: "Tối", en: "Dark", ja: "ダーク")
        case .light:
            mistiaLocalized(vi: "Sáng", en: "Light", ja: "ライト")
        }
    }

    var subtitle: String {
        switch self {
        case .automatic:
            mistiaLocalized(vi: "Theo giao diện hệ thống", en: "Follow system appearance", ja: "システム設定に合わせる")
        case .dark:
            mistiaLocalized(vi: "Luôn dùng nền tối", en: "Always use dark mode", ja: "常にダークモードを使う")
        case .light:
            mistiaLocalized(vi: "Luôn dùng nền sáng", en: "Always use light mode", ja: "常にライトモードを使う")
        }
    }

    var systemImage: String {
        switch self {
        case .automatic:
            "circle.lefthalf.filled"
        case .dark:
            "moon.stars.fill"
        case .light:
            "sun.max.fill"
        }
    }

    var accent: MistiaAccent {
        switch self {
        case .automatic:
            .indigo
        case .dark:
            .teal
        case .light:
            .amber
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            nil
        case .dark:
            .dark
        case .light:
            .light
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .automatic:
            .unspecified
        case .dark:
            .dark
        case .light:
            .light
        }
    }
}
