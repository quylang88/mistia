import XCTest
@testable import Mistia

@MainActor
final class MistiaAppLockControllerTests: XCTestCase {
    func testConfigureStoresCredentialEnablesProtectionAndKeepsAppUnlocked() throws {
        let defaults = makeDefaults()
        let credentialStore = AppLockCredentialStoreSpy()
        let controller = MistiaAppLockController(
            defaults: defaults,
            credentialStore: credentialStore,
            biometricAuthenticator: AppLockBiometricAuthenticatorSpy()
        )

        try controller.configure(kind: .pin4, secret: "1234")

        XCTAssertTrue(defaults.bool(forKey: MistiaAppStorageKey.appLockEnabled))
        XCTAssertEqual(defaults.string(forKey: MistiaAppStorageKey.appLockSecretKind), "pin4")
        XCTAssertFalse(defaults.bool(forKey: MistiaAppStorageKey.appLockBiometricEnabled))
        XCTAssertEqual(credentialStore.savedCredential?.kind, .pin4)
        XCTAssertFalse(controller.isLocked)
    }

    func testEnabledControllerLocksAndVerifiesStoredPIN() throws {
        let defaults = makeDefaults()
        let credential = try MistiaAppLockCredential.make(
            kind: .pin4,
            secret: "1234",
            saltGenerator: { Data(repeating: 0x03, count: 16) }
        )
        defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.set("pin4", forKey: MistiaAppStorageKey.appLockSecretKind)
        let controller = MistiaAppLockController(
            defaults: defaults,
            credentialStore: AppLockCredentialStoreSpy(credential: credential),
            biometricAuthenticator: AppLockBiometricAuthenticatorSpy()
        )

        XCTAssertTrue(controller.isLocked)
        XCTAssertFalse(controller.verify(secret: "0000"))
        XCTAssertEqual(controller.failureState.failedAttemptCount, 1)
        XCTAssertTrue(controller.verify(secret: "1234"))
        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(controller.failureState, .empty)
    }

    func testBiometricSuccessUnlocksOnlyWhenEnabledForPIN4Credential() async throws {
        let defaults = makeDefaults()
        let credential = try MistiaAppLockCredential.make(
            kind: .pin4,
            secret: "1234",
            saltGenerator: { Data(repeating: 0x04, count: 16) }
        )
        defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.set("pin4", forKey: MistiaAppStorageKey.appLockSecretKind)
        defaults.set(true, forKey: MistiaAppStorageKey.appLockBiometricEnabled)
        let biometric = AppLockBiometricAuthenticatorSpy(kind: .faceID, result: true)
        let controller = MistiaAppLockController(
            defaults: defaults,
            credentialStore: AppLockCredentialStoreSpy(credential: credential),
            biometricAuthenticator: biometric
        )

        XCTAssertTrue(controller.isLocked)
        let didUnlock = await controller.authenticateWithBiometrics(reason: "Test unlock")

        XCTAssertTrue(didUnlock)
        XCTAssertEqual(biometric.authenticateCallCount, 1)
        XCTAssertFalse(controller.isLocked)
    }

    func testUnavailableBiometricFallsBackWithoutUnlocking() async throws {
        let defaults = makeDefaults()
        let credential = try MistiaAppLockCredential.make(
            kind: .pin4,
            secret: "1234",
            saltGenerator: { Data(repeating: 0x05, count: 16) }
        )
        defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.set("pin4", forKey: MistiaAppStorageKey.appLockSecretKind)
        defaults.set(true, forKey: MistiaAppStorageKey.appLockBiometricEnabled)
        let biometric = AppLockBiometricAuthenticatorSpy(kind: .none, result: true)
        let controller = MistiaAppLockController(
            defaults: defaults,
            credentialStore: AppLockCredentialStoreSpy(credential: credential),
            biometricAuthenticator: biometric
        )

        let didUnlock = await controller.authenticateWithBiometrics(reason: "Test unlock")

        XCTAssertFalse(didUnlock)
        XCTAssertEqual(biometric.authenticateCallCount, 0)
        XCTAssertTrue(controller.isLocked)
    }

    func testMissingCredentialSelfHealsByDisablingProtection() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.set("pin4", forKey: MistiaAppStorageKey.appLockSecretKind)
        defaults.set(true, forKey: MistiaAppStorageKey.appLockBiometricEnabled)

        let controller = MistiaAppLockController(
            defaults: defaults,
            credentialStore: AppLockCredentialStoreSpy(),
            biometricAuthenticator: AppLockBiometricAuthenticatorSpy()
        )

        XCTAssertFalse(defaults.bool(forKey: MistiaAppStorageKey.appLockEnabled))
        XCTAssertNil(defaults.object(forKey: MistiaAppStorageKey.appLockSecretKind))
        XCTAssertNil(defaults.object(forKey: MistiaAppStorageKey.appLockBiometricEnabled))
        XCTAssertFalse(controller.isLocked)
    }

    func testDisableRequiresUnlockedStateThenClearsCredentialAndPreferences() throws {
        let defaults = makeDefaults()
        let credential = try MistiaAppLockCredential.make(
            kind: .pin4,
            secret: "1234",
            saltGenerator: { Data(repeating: 0x06, count: 16) }
        )
        defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.set("pin4", forKey: MistiaAppStorageKey.appLockSecretKind)
        defaults.set(true, forKey: MistiaAppStorageKey.appLockBiometricEnabled)
        let credentialStore = AppLockCredentialStoreSpy(credential: credential)
        let controller = MistiaAppLockController(
            defaults: defaults,
            credentialStore: credentialStore,
            biometricAuthenticator: AppLockBiometricAuthenticatorSpy()
        )

        XCTAssertThrowsError(try controller.disableAfterAuthentication())
        XCTAssertTrue(controller.verify(secret: "1234"))
        try controller.disableAfterAuthentication()

        XCTAssertFalse(defaults.bool(forKey: MistiaAppStorageKey.appLockEnabled))
        XCTAssertNil(defaults.object(forKey: MistiaAppStorageKey.appLockSecretKind))
        XCTAssertNil(defaults.object(forKey: MistiaAppStorageKey.appLockBiometricEnabled))
        XCTAssertNil(credentialStore.credential)
        XCTAssertFalse(controller.isLocked)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MistiaAppLockControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class AppLockCredentialStoreSpy: MistiaAppLockCredentialStoring {
    var credential: MistiaAppLockCredential?
    private(set) var savedCredential: MistiaAppLockCredential?

    init(credential: MistiaAppLockCredential? = nil) {
        self.credential = credential
    }

    func loadCredential() throws -> MistiaAppLockCredential? {
        credential
    }

    func saveCredential(_ credential: MistiaAppLockCredential) throws {
        self.credential = credential
        savedCredential = credential
    }

    func removeCredential() throws {
        credential = nil
    }
}

private final class AppLockBiometricAuthenticatorSpy: MistiaAppLockBiometricAuthenticating {
    let kind: MistiaAppLockBiometryKind
    let result: Bool
    private(set) var authenticateCallCount = 0

    init(kind: MistiaAppLockBiometryKind = .none, result: Bool = false) {
        self.kind = kind
        self.result = result
    }

    func authenticate(reason: String) async -> Bool {
        authenticateCallCount += 1
        return result
    }
}
