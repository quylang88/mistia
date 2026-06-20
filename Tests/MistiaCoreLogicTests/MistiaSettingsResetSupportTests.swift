import XCTest
@testable import MistiaCoreLogic

final class MistiaSettingsResetSupportTests: XCTestCase {
    func testResetAppPreferencesRestoresDefaultsAndPreservesSessionFamilyProfileKeys() {
        let suiteName = "MistiaSettingsResetSupportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("dark", forKey: MistiaSettingsResetSupport.StorageKey.appearanceMode)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.hideQuickCreate)
        defaults.set("USD", forKey: MistiaSettingsResetSupport.StorageKey.currencyCode)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.syncAutoEnabled)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.mistiaShortcutEnabled)
        defaults.set("syncNow", forKey: MistiaSettingsResetSupport.StorageKey.mistiaShortcutKind)
        defaults.set(UUID().uuidString, forKey: MistiaSettingsResetSupport.StorageKey.mistiaShortcutMemberUserID)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.notificationsEnabled)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.notificationsGroupFamilyEnabled)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.appLockEnabled)
        defaults.set("pin4", forKey: MistiaSettingsResetSupport.StorageKey.appLockSecretKind)
        defaults.set(true, forKey: MistiaSettingsResetSupport.StorageKey.appLockBiometricEnabled)
        defaults.set(Data([4, 5, 6]), forKey: MistiaSettingsResetSupport.StorageKey.appLockFailureState)
        defaults.set("vi", forKey: MistiaAppLanguage.userDefaultsKey)
        defaults.set("vi", forKey: MistiaAppLanguage.backupUserDefaultsKey)

        let pendingInviteKey = "Mistia.pendingFamilyInviteToken"
        let localProfileRegistryKey = "mistia.local-profile.descriptors"
        let activeLocalProfileKey = "mistia.local-profile.active-id"
        let authStateKey = "mistia.test.auth-state"
        defaults.set("invite-token", forKey: pendingInviteKey)
        defaults.set(Data([1, 2, 3]), forKey: localProfileRegistryKey)
        defaults.set(UUID().uuidString, forKey: activeLocalProfileKey)
        defaults.set("session", forKey: authStateKey)

        MistiaSettingsResetSupport.resetAppPreferences(
            defaults: defaults,
            preferredLanguages: ["ja-JP"]
        )

        XCTAssertEqual(defaults.string(forKey: MistiaSettingsResetSupport.StorageKey.appearanceMode), "automatic")
        XCTAssertFalse(defaults.bool(forKey: MistiaSettingsResetSupport.StorageKey.hideQuickCreate))
        XCTAssertEqual(defaults.string(forKey: MistiaSettingsResetSupport.StorageKey.currencyCode), "JPY")
        XCTAssertFalse(defaults.bool(forKey: MistiaSettingsResetSupport.StorageKey.syncAutoEnabled))
        XCTAssertFalse(defaults.bool(forKey: MistiaSettingsResetSupport.StorageKey.mistiaShortcutEnabled))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.mistiaShortcutKind))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.mistiaShortcutMemberUserID))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.notificationsEnabled))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.notificationsGroupFamilyEnabled))
        XCTAssertFalse(defaults.bool(forKey: MistiaSettingsResetSupport.StorageKey.appLockEnabled))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.appLockSecretKind))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.appLockBiometricEnabled))
        XCTAssertNil(defaults.object(forKey: MistiaSettingsResetSupport.StorageKey.appLockFailureState))
        XCTAssertEqual(defaults.string(forKey: MistiaAppLanguage.userDefaultsKey), "ja")
        XCTAssertEqual(defaults.string(forKey: MistiaAppLanguage.backupUserDefaultsKey), "ja")

        XCTAssertEqual(defaults.string(forKey: pendingInviteKey), "invite-token")
        XCTAssertEqual(defaults.data(forKey: localProfileRegistryKey), Data([1, 2, 3]))
        XCTAssertNotNil(defaults.string(forKey: activeLocalProfileKey))
        XCTAssertEqual(defaults.string(forKey: authStateKey), "session")
    }
}
