import XCTest
@testable import MistiaCoreLogic

final class MistiaAppLockLogicTests: XCTestCase {
    func testSecretValidationAcceptsOnlyTheConfiguredSecretShape() {
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "1234", kind: .pin4), nil)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "123456", kind: .pin6), nil)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "Abc1234", kind: .customPassword), nil)

        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "123", kind: .pin4), .pin4RequiresFourDigits)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "12a4", kind: .pin4), .pin4RequiresFourDigits)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "12345", kind: .pin6), .pin6RequiresSixDigits)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "12345a", kind: .pin6), .pin6RequiresSixDigits)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "abc", kind: .customPassword), .customPasswordTooShort)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "Abc123", kind: .customPassword), .customPasswordTooShort)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "1234567", kind: .customPassword), .customPasswordMissingLetter)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "abcdefg", kind: .customPassword), .customPasswordMissingDigit)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "ABCDEFG1", kind: .customPassword), .customPasswordMissingLowercase)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "abcdefg1", kind: .customPassword), .customPasswordMissingUppercase)
        XCTAssertEqual(MistiaAppLockLogic.validationFailure(for: "Abcdefg", kind: .customPassword), .customPasswordMissingDigit)
    }

    func testBiometricRequiresExistingPIN4Credential() {
        XCTAssertTrue(
            MistiaAppLockLogic.requiresPIN4SetupBeforeBiometric(
                currentKind: nil,
                hasCredential: false
            )
        )
        XCTAssertTrue(
            MistiaAppLockLogic.requiresPIN4SetupBeforeBiometric(
                currentKind: .pin6,
                hasCredential: true
            )
        )
        XCTAssertFalse(
            MistiaAppLockLogic.requiresPIN4SetupBeforeBiometric(
                currentKind: .pin4,
                hasCredential: true
            )
        )
    }

    func testFailedAttemptsLockManualEntryForThirtySecondsAfterFiveFailures() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = MistiaAppLockFailureState(failedAttemptCount: 0, lockedUntil: nil)

        for _ in 0..<4 {
            state = MistiaAppLockLogic.recordFailedAttempt(from: state, now: now)
            XCTAssertFalse(MistiaAppLockLogic.isLockedOut(state, now: now))
        }

        state = MistiaAppLockLogic.recordFailedAttempt(from: state, now: now)

        XCTAssertEqual(state.failedAttemptCount, 5)
        XCTAssertEqual(state.lockedUntil, now.addingTimeInterval(30))
        XCTAssertTrue(MistiaAppLockLogic.isLockedOut(state, now: now.addingTimeInterval(29)))
        XCTAssertFalse(MistiaAppLockLogic.isLockedOut(state, now: now.addingTimeInterval(30)))
    }

    func testLockoutEscalatesEveryFiveFailedAttemptsUpToOneHour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = MistiaAppLockFailureState(failedAttemptCount: 0, lockedUntil: nil)
        let expectedDurations: [TimeInterval] = [
            30,
            60,
            5 * 60,
            10 * 60,
            20 * 60,
            30 * 60,
            60 * 60,
            60 * 60
        ]

        for lockoutIndex in expectedDurations.indices {
            let attemptStart = now.addingTimeInterval(TimeInterval(lockoutIndex * 10_000))
            for attemptOffset in 0..<4 {
                state = MistiaAppLockLogic.recordFailedAttempt(
                    from: state,
                    now: attemptStart.addingTimeInterval(TimeInterval(attemptOffset))
                )
                XCTAssertNil(state.lockedUntil)
            }

            let lockoutStart = attemptStart.addingTimeInterval(4)
            state = MistiaAppLockLogic.recordFailedAttempt(from: state, now: lockoutStart)

            XCTAssertEqual(state.failedAttemptCount, (lockoutIndex + 1) * 5)
            XCTAssertEqual(state.lockedUntil, lockoutStart.addingTimeInterval(expectedDurations[lockoutIndex]))
        }
    }

    func testSuccessfulAuthenticationClearsFailedAttemptsAndLockout() {
        let state = MistiaAppLockFailureState(
            failedAttemptCount: 5,
            lockedUntil: Date(timeIntervalSince1970: 1_800_000_030)
        )

        XCTAssertEqual(MistiaAppLockLogic.recordSuccessfulAuthentication(from: state), .empty)
    }

    func testCredentialVerificationUsesSaltedDerivedKeysWithoutStoringRawSecret() throws {
        let first = try MistiaAppLockCredential.make(
            kind: .pin4,
            secret: "1234",
            now: Date(timeIntervalSince1970: 1_800_000_000),
            saltGenerator: { Data(repeating: 0x01, count: 16) }
        )
        let second = try MistiaAppLockCredential.make(
            kind: .pin4,
            secret: "1234",
            now: Date(timeIntervalSince1970: 1_800_000_000),
            saltGenerator: { Data(repeating: 0x02, count: 16) }
        )

        XCTAssertTrue(first.verifies(secret: "1234"))
        XCTAssertFalse(first.verifies(secret: "0000"))
        XCTAssertNotEqual(first.saltData, second.saltData)
        XCTAssertNotEqual(first.derivedKeyData, second.derivedKeyData)
        XCTAssertNotEqual(first.derivedKeyData, Data("1234".utf8))
    }
}
