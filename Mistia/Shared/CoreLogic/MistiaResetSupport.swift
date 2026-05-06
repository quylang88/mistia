import Foundation

enum MistiaSettingsResetSupport {
    enum StorageKey {
        static let appearanceMode = "mistia.appearance.mode"
        static let hideQuickCreate = "mistia.chrome.hideQuickCreate"
        static let mistiaShortcutEnabled = "mistia.shortcut.enabled"
        static let mistiaShortcutKind = "mistia.shortcut.kind"
        static let mistiaShortcutMemberUserID = "mistia.shortcut.member-user-id"
        static let currencyCode = "mistia.settings.currency.code"
        static let syncAutoEnabled = "mistia.sync.auto.enabled"
        static let notificationsEnabled = "mistia.notifications.enabled"
        static let notificationsHadAnyGroupOn = "mistia.notifications.hadAnyGroupOn"
        static let notificationsGroupRemindersEnabled = "mistia.notifications.group.reminders.enabled"
        static let notificationsGroupFamilyEnabled = "mistia.notifications.group.family.enabled"
        static let notificationsReminderBudgetEnabled = "mistia.notifications.reminder.budget.enabled"
        static let notificationsReminderBillsEnabled = "mistia.notifications.reminder.bills.enabled"
        static let notificationsReminderCreditCardsEnabled = "mistia.notifications.reminder.creditCards.enabled"
        static let notificationsReminderWalletsEnabled = "mistia.notifications.reminder.wallets.enabled"
    }

    static func resetAppPreferences(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        resetNotificationPreferences(defaults: defaults)

        defaults.set("automatic", forKey: StorageKey.appearanceMode)
        defaults.set(false, forKey: StorageKey.hideQuickCreate)
        defaults.set("JPY", forKey: StorageKey.currencyCode)
        defaults.set(false, forKey: StorageKey.syncAutoEnabled)
        defaults.set(false, forKey: StorageKey.mistiaShortcutEnabled)
        defaults.removeObject(forKey: StorageKey.mistiaShortcutKind)
        defaults.removeObject(forKey: StorageKey.mistiaShortcutMemberUserID)

        defaults.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        defaults.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        MistiaAppLanguage.persist(
            MistiaAppLanguage.infer(preferredLanguages: preferredLanguages),
            defaults: defaults
        )
    }

    static func resetNotificationPreferences(defaults: UserDefaults = .standard) {
        [
            StorageKey.notificationsEnabled,
            StorageKey.notificationsHadAnyGroupOn,
            StorageKey.notificationsGroupRemindersEnabled,
            StorageKey.notificationsGroupFamilyEnabled,
            StorageKey.notificationsReminderBudgetEnabled,
            StorageKey.notificationsReminderBillsEnabled,
            StorageKey.notificationsReminderCreditCardsEnabled,
            StorageKey.notificationsReminderWalletsEnabled
        ].forEach {
            defaults.removeObject(forKey: $0)
        }
    }
}
