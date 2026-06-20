import CommonCrypto
import Foundation
import Security

nonisolated enum MistiaAppLockSecretKind: String, CaseIterable, Codable, Equatable, Sendable {
    case pin4
    case pin6
    case customPassword
}

nonisolated enum MistiaAppLockSecretValidationFailure: Equatable, Sendable {
    case pin4RequiresFourDigits
    case pin6RequiresSixDigits
    case customPasswordTooShort
    case customPasswordMissingLetter
    case customPasswordMissingDigit
    case customPasswordMissingUppercase
    case customPasswordMissingLowercase
}

nonisolated struct MistiaAppLockFailureState: Equatable, Sendable {
    static let empty = MistiaAppLockFailureState(failedAttemptCount: 0, lockedUntil: nil)

    let failedAttemptCount: Int
    let lockedUntil: Date?
}

nonisolated enum MistiaAppLockCredentialError: Error, Equatable {
    case invalidSecret(MistiaAppLockSecretValidationFailure)
    case randomGenerationFailed(OSStatus)
    case keyDerivationFailed(Int32)
}

nonisolated struct MistiaAppLockCredential: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let defaultIterationCount = 120_000
    static let saltByteCount = 16
    static let derivedKeyByteCount = 32

    let version: Int
    let kind: MistiaAppLockSecretKind
    let saltData: Data
    let derivedKeyData: Data
    let iterationCount: Int
    let createdAt: Date
    let updatedAt: Date

    static func make(
        kind: MistiaAppLockSecretKind,
        secret: String,
        now: Date = Date(),
        iterationCount: Int = defaultIterationCount,
        saltGenerator: () throws -> Data = secureRandomSalt
    ) throws -> MistiaAppLockCredential {
        if let failure = MistiaAppLockLogic.validationFailure(for: secret, kind: kind) {
            throw MistiaAppLockCredentialError.invalidSecret(failure)
        }

        let saltData = try saltGenerator()
        let derivedKeyData = try deriveKey(
            secret: secret,
            saltData: saltData,
            iterationCount: iterationCount
        )

        return MistiaAppLockCredential(
            version: currentVersion,
            kind: kind,
            saltData: saltData,
            derivedKeyData: derivedKeyData,
            iterationCount: iterationCount,
            createdAt: now,
            updatedAt: now
        )
    }

    func replacingSecret(_ secret: String, kind newKind: MistiaAppLockSecretKind, now: Date = Date()) throws -> MistiaAppLockCredential {
        try MistiaAppLockCredential.make(
            kind: newKind,
            secret: secret,
            now: now
        )
    }

    func verifies(secret: String) -> Bool {
        guard MistiaAppLockLogic.validationFailure(for: secret, kind: kind) == nil,
              let candidate = try? Self.deriveKey(
                secret: secret,
                saltData: saltData,
                iterationCount: iterationCount
              )
        else {
            return false
        }

        return constantTimeEquals(candidate, derivedKeyData)
    }

    private static func secureRandomSalt() throws -> Data {
        var data = Data(count: saltByteCount)
        let status = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, saltByteCount, baseAddress)
        }
        guard status == errSecSuccess else {
            throw MistiaAppLockCredentialError.randomGenerationFailed(status)
        }
        return data
    }

    private static func deriveKey(
        secret: String,
        saltData: Data,
        iterationCount: Int
    ) throws -> Data {
        var derivedKey = Data(count: derivedKeyByteCount)
        let status = derivedKey.withUnsafeMutableBytes { derivedBuffer -> Int32 in
            saltData.withUnsafeBytes { saltBuffer -> Int32 in
                guard let derivedBaseAddress = derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let saltBaseAddress = saltBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return Int32(kCCMemoryFailure)
                }

                return secret.withCString { secretPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        secretPointer,
                        secret.utf8.count,
                        saltBaseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterationCount),
                        derivedBaseAddress,
                        derivedKeyByteCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw MistiaAppLockCredentialError.keyDerivationFailed(status)
        }
        return derivedKey
    }

    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }

        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }
}

nonisolated enum MistiaAppLockLogic {
    static let maxFailedAttempts = 5
    static let lockoutDuration: TimeInterval = 30

    static func validationFailure(
        for secret: String,
        kind: MistiaAppLockSecretKind
    ) -> MistiaAppLockSecretValidationFailure? {
        switch kind {
        case .pin4:
            return isNumeric(secret, count: 4) ? nil : .pin4RequiresFourDigits
        case .pin6:
            return isNumeric(secret, count: 6) ? nil : .pin6RequiresSixDigits
        case .customPassword:
            return passwordValidationFailure(for: secret)
        }
    }

    static func requiresPIN4SetupBeforeBiometric(
        currentKind: MistiaAppLockSecretKind?,
        hasCredential: Bool
    ) -> Bool {
        !(hasCredential && currentKind == .pin4)
    }

    static func isLockedOut(
        _ state: MistiaAppLockFailureState,
        now: Date = Date()
    ) -> Bool {
        guard let lockedUntil = state.lockedUntil else { return false }
        return now < lockedUntil
    }

    static func recordFailedAttempt(
        from state: MistiaAppLockFailureState,
        now: Date = Date()
    ) -> MistiaAppLockFailureState {
        let failedAttemptCount = state.failedAttemptCount + 1
        let lockedUntil = failedAttemptCount >= maxFailedAttempts
            ? now.addingTimeInterval(lockoutDuration)
            : nil
        return MistiaAppLockFailureState(
            failedAttemptCount: failedAttemptCount,
            lockedUntil: lockedUntil
        )
    }

    static func recordSuccessfulAuthentication(
        from state: MistiaAppLockFailureState
    ) -> MistiaAppLockFailureState {
        .empty
    }

    static func shouldPresentLock(
        isEnabled: Bool,
        hasCredential: Bool,
        isUnlocked: Bool
    ) -> Bool {
        isEnabled && hasCredential && !isUnlocked
    }

    private static func isNumeric(_ value: String, count: Int) -> Bool {
        value.count == count && value.allSatisfy(\.isNumber)
    }

    private static func passwordValidationFailure(for secret: String) -> MistiaAppLockSecretValidationFailure? {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 6 else {
            return .customPasswordTooShort
        }

        let scalars = trimmed.unicodeScalars
        let hasLetter = scalars.contains(where: CharacterSet.letters.contains)
        let hasDigit = scalars.contains(where: CharacterSet.decimalDigits.contains)
        let hasUppercase = scalars.contains(where: CharacterSet.uppercaseLetters.contains)
        let hasLowercase = scalars.contains(where: CharacterSet.lowercaseLetters.contains)

        if !hasLetter {
            return .customPasswordMissingLetter
        }
        if !hasDigit {
            return .customPasswordMissingDigit
        }
        if !hasUppercase {
            return .customPasswordMissingUppercase
        }
        if !hasLowercase {
            return .customPasswordMissingLowercase
        }
        return nil
    }
}
