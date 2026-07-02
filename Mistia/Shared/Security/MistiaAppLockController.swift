import Foundation
import LocalAuthentication
import Observation

nonisolated protocol MistiaAppLockCredentialStoring {
    func loadCredential() throws -> MistiaAppLockCredential?
    func saveCredential(_ credential: MistiaAppLockCredential) throws
    func removeCredential() throws
}

nonisolated enum MistiaAppLockBiometryKind: Equatable {
    case none
    case faceID
    case touchID
    case opticID
}

nonisolated protocol MistiaAppLockBiometricAuthenticating {
    var kind: MistiaAppLockBiometryKind { get }
    func authenticate(reason: String) async -> Bool
}

nonisolated enum MistiaAppLockControllerError: Error, Equatable {
    case authenticationRequired
    case missingCredential
}

nonisolated struct MistiaAppLockKeychainCredentialStore: MistiaAppLockCredentialStoring {
    private static let account = "mistia.app-lock.credential"

    private let keychain: KeychainStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        keychain: KeychainStore = KeychainStore(
            service: "vn.com.quyln.mistia.app-lock",
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
    ) {
        self.keychain = keychain
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadCredential() throws -> MistiaAppLockCredential? {
        guard let data = try keychain.data(for: Self.account) else { return nil }
        return try decoder.decode(MistiaAppLockCredential.self, from: data)
    }

    func saveCredential(_ credential: MistiaAppLockCredential) throws {
        let data = try encoder.encode(credential)
        try keychain.set(data, for: Self.account)
    }

    func removeCredential() throws {
        try keychain.removeData(for: Self.account)
    }
}

nonisolated struct SystemMistiaAppLockBiometricAuthenticator: MistiaAppLockBiometricAuthenticating {
    var kind: MistiaAppLockBiometryKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}

@MainActor
@Observable
final class MistiaAppLockController {
    private let defaults: UserDefaults
    private let credentialStore: any MistiaAppLockCredentialStoring
    private let biometricAuthenticator: any MistiaAppLockBiometricAuthenticating
    private let now: () -> Date
    private let failureStateEncoder = JSONEncoder()
    private let failureStateDecoder = JSONDecoder()

    private(set) var isLocked = false
    private(set) var lockCycle = 0
    private(set) var failureState = MistiaAppLockFailureState.empty

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any MistiaAppLockCredentialStoring = MistiaAppLockKeychainCredentialStore(),
        biometricAuthenticator: any MistiaAppLockBiometricAuthenticating = SystemMistiaAppLockBiometricAuthenticator(),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.biometricAuthenticator = biometricAuthenticator
        self.now = now
        refreshConfiguration()
    }

    var isEnabled: Bool {
        defaults.bool(forKey: MistiaAppStorageKey.appLockEnabled)
    }

    var isBiometricEnabled: Bool {
        defaults.bool(forKey: MistiaAppStorageKey.appLockBiometricEnabled)
    }

    var configuredSecretKind: MistiaAppLockSecretKind? {
        guard let rawValue = defaults.string(forKey: MistiaAppStorageKey.appLockSecretKind) else {
            return nil
        }
        return MistiaAppLockSecretKind(rawValue: rawValue)
    }

    var biometryKind: MistiaAppLockBiometryKind {
        biometricAuthenticator.kind
    }

    var shouldPresentLock: Bool {
        MistiaAppLockLogic.shouldPresentLock(
            isEnabled: isEnabled,
            hasCredential: hasCredential,
            isUnlocked: !isLocked
        )
    }

    var hasCredential: Bool {
        ((try? credentialStore.loadCredential()) ?? nil) != nil
    }

    var requiresCodeSetupBeforeBiometric: Bool {
        MistiaAppLockLogic.requiresCredentialSetupBeforeBiometric(
            currentKind: configuredSecretKind,
            hasCredential: hasCredential
        )
    }

    func canOfferBiometricEnrollmentAfterSetup(for kind: MistiaAppLockSecretKind) -> Bool {
        biometricAuthenticator.kind != .none && !isBiometricEnabled
    }

    func refreshConfiguration() {
        guard isEnabled else {
            isLocked = false
            failureState = .empty
            clearPersistedFailureState()
            return
        }

        guard let credential = try? credentialStore.loadCredential() else {
            clearPreferences()
            isLocked = false
            failureState = .empty
            return
        }

        defaults.set(credential.kind.rawValue, forKey: MistiaAppStorageKey.appLockSecretKind)
        failureState = loadPersistedFailureState()
        isLocked = true
    }

    func configure(kind: MistiaAppLockSecretKind, secret: String) throws {
        let credential = try MistiaAppLockCredential.make(kind: kind, secret: secret, now: now())
        try credentialStore.saveCredential(credential)
        defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.set(kind.rawValue, forKey: MistiaAppStorageKey.appLockSecretKind)
        if defaults.object(forKey: MistiaAppStorageKey.appLockBiometricEnabled) == nil {
            defaults.set(false, forKey: MistiaAppStorageKey.appLockBiometricEnabled)
        }
        failureState = .empty
        clearPersistedFailureState()
        isLocked = false
    }

    @discardableResult
    func verify(secret: String) -> Bool {
        guard !MistiaAppLockLogic.isLockedOut(failureState, now: now()) else {
            return false
        }

        guard let credential = try? credentialStore.loadCredential() else {
            clearPreferences()
            isLocked = false
            failureState = .empty
            return false
        }

        guard credential.verifies(secret: secret) else {
            failureState = MistiaAppLockLogic.recordFailedAttempt(from: failureState, now: now())
            persistFailureState()
            return false
        }

        unlock()
        return true
    }

    func authenticateWithBiometrics(reason: String) async -> Bool {
        guard isEnabled,
              isBiometricEnabled,
              configuredSecretKind != nil,
              hasCredential,
              biometricAuthenticator.kind != .none
        else {
            return false
        }

        let didAuthenticate = await biometricAuthenticator.authenticate(reason: reason)
        if didAuthenticate {
            unlock()
        }
        return didAuthenticate
    }

    func setBiometricsEnabled(_ isEnabled: Bool) throws {
        guard !isLocked else {
            throw MistiaAppLockControllerError.authenticationRequired
        }

        guard isEnabled else {
            defaults.set(false, forKey: MistiaAppStorageKey.appLockBiometricEnabled)
            return
        }

        guard let credential = try credentialStore.loadCredential() else {
            clearPreferences()
            throw MistiaAppLockControllerError.missingCredential
        }
        defaults.set(true, forKey: MistiaAppStorageKey.appLockBiometricEnabled)
        defaults.set(credential.kind.rawValue, forKey: MistiaAppStorageKey.appLockSecretKind)
    }

    func disableAfterAuthentication() throws {
        guard !isLocked else {
            throw MistiaAppLockControllerError.authenticationRequired
        }

        try credentialStore.removeCredential()
        clearPreferences()
        failureState = .empty
        isLocked = false
    }

    func lockIfNeeded() {
        guard isEnabled else {
            isLocked = false
            return
        }

        guard hasCredential else {
            clearPreferences()
            isLocked = false
            return
        }

        guard !isLocked else { return }
        isLocked = true
        lockCycle += 1
    }

    func unlock() {
        failureState = MistiaAppLockLogic.recordSuccessfulAuthentication(from: failureState)
        clearPersistedFailureState()
        isLocked = false
    }

    private func clearPreferences() {
        defaults.set(false, forKey: MistiaAppStorageKey.appLockEnabled)
        defaults.removeObject(forKey: MistiaAppStorageKey.appLockSecretKind)
        defaults.removeObject(forKey: MistiaAppStorageKey.appLockBiometricEnabled)
        clearPersistedFailureState()
    }

    private func loadPersistedFailureState() -> MistiaAppLockFailureState {
        guard let data = defaults.data(forKey: MistiaAppStorageKey.appLockFailureState),
              let state = try? failureStateDecoder.decode(MistiaAppLockFailureState.self, from: data)
        else {
            clearPersistedFailureState()
            return .empty
        }

        return state
    }

    private func persistFailureState() {
        guard let data = try? failureStateEncoder.encode(failureState) else { return }
        defaults.set(data, forKey: MistiaAppStorageKey.appLockFailureState)
    }

    private func clearPersistedFailureState() {
        defaults.removeObject(forKey: MistiaAppStorageKey.appLockFailureState)
    }
}
