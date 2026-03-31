import SwiftUI
import UIKit

enum MistiaAppStorageKey {
    static let appearanceMode = "mistia.appearance.mode"
    static let hideQuickCreate = "mistia.chrome.hideQuickCreate"
    static let didSeedManagementCategories = "mistia.management.didSeedCategories"
}

enum MistiaAppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Tự động"
        case .dark:
            "Tối"
        case .light:
            "Sáng"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic:
            "Theo giao diện hệ thống"
        case .dark:
            "Luôn dùng nền tối"
        case .light:
            "Luôn dùng nền sáng"
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
