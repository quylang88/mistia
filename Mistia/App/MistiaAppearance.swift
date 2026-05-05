import SwiftUI
import UIKit

enum MistiaAppStorageKey {
    static let appearanceMode = "mistia.appearance.mode"
    static let hideQuickCreate = "mistia.chrome.hideQuickCreate"
    static let mistiaShortcutEnabled = "mistia.shortcut.enabled"
    static let mistiaShortcutKind = "mistia.shortcut.kind"
    static let mistiaShortcutMemberUserID = "mistia.shortcut.member-user-id"
    static let didSeedManagementCategories = "mistia.management.didSeedCategories"
    static let currencyCode = "mistia.settings.currency.code"
    static let appLanguage = MistiaAppLanguage.userDefaultsKey
    static let syncAutoEnabled = "mistia.sync.auto.enabled"
    static let syncManualReviewRequired = "mistia.sync.manual-review-required"
    static let localModeProfileUserID = "mistia.local-mode.profile-user-id"
    static let localProfileDescriptors = "mistia.local-profile.descriptors"
    static let activeLocalProfileID = "mistia.local-profile.active-id"
    static let pendingSignupEmail = "mistia.auth.pending-signup-email"

    static let notificationsEnabled = "mistia.notifications.enabled"
    static let notificationsHadAnyGroupOn = "mistia.notifications.hadAnyGroupOn"
    static let notificationsGroupRemindersEnabled = "mistia.notifications.group.reminders.enabled"
    static let notificationsGroupFamilyEnabled = "mistia.notifications.group.family.enabled"
    static let notificationsReminderBudgetEnabled = "mistia.notifications.reminder.budget.enabled"
    static let notificationsReminderBillsEnabled = "mistia.notifications.reminder.bills.enabled"
    static let notificationsReminderCreditCardsEnabled = "mistia.notifications.reminder.creditCards.enabled"
    static let notificationsReminderWalletsEnabled = "mistia.notifications.reminder.wallets.enabled"
}

enum MistiaNotificationReminderKind: CaseIterable {
    case budget
    case bills
    case creditCards
    case wallets

    var storageKey: String {
        switch self {
        case .budget:
            MistiaAppStorageKey.notificationsReminderBudgetEnabled
        case .bills:
            MistiaAppStorageKey.notificationsReminderBillsEnabled
        case .creditCards:
            MistiaAppStorageKey.notificationsReminderCreditCardsEnabled
        case .wallets:
            MistiaAppStorageKey.notificationsReminderWalletsEnabled
        }
    }
}

enum MistiaNotificationPreferences {
    static func notificationsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: MistiaAppStorageKey.notificationsEnabled)
    }

    static func familyEnabled(defaults: UserDefaults = .standard) -> Bool {
        notificationsEnabled(defaults: defaults)
            && defaults.bool(forKey: MistiaAppStorageKey.notificationsGroupFamilyEnabled)
    }

    static func remindersEnabled(defaults: UserDefaults = .standard) -> Bool {
        notificationsEnabled(defaults: defaults)
            && defaults.bool(forKey: MistiaAppStorageKey.notificationsGroupRemindersEnabled)
            && MistiaNotificationReminderKind.allCases.contains {
                reminderEnabled($0, defaults: defaults)
            }
    }

    static func reminderEnabled(
        _ kind: MistiaNotificationReminderKind,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard notificationsEnabled(defaults: defaults),
              defaults.bool(forKey: MistiaAppStorageKey.notificationsGroupRemindersEnabled)
        else {
            return false
        }

        if defaults.object(forKey: kind.storageKey) == nil {
            return true
        }
        return defaults.bool(forKey: kind.storageKey)
    }

    static func setAllReminderDetails(
        _ isEnabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        MistiaNotificationReminderKind.allCases.forEach {
            defaults.set(isEnabled, forKey: $0.storageKey)
        }
    }
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
