# App Lock Foreground Biometric Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically request biometric authentication once whenever Mistia locks after entering the background.

**Architecture:** Track each real unlocked-to-locked transition with an observable controller-owned lock-cycle integer. Use that integer as the SwiftUI lock screen identity so presentation-local automatic-attempt state is recreated once per cycle without coupling biometric authentication to `.active` scene-phase events.

**Tech Stack:** Swift 6, SwiftUI, Observation, LocalAuthentication, XCTest, Xcode 26

---

## File Structure

- Modify `Mistia/Shared/Security/MistiaAppLockController.swift`: own and advance the lock-cycle identity at the security state boundary.
- Modify `Mistia/App/MistiaApp.swift`: bind the lock overlay identity to the current lock cycle.
- Modify `MistiaTests/MistiaAppLockControllerTests.swift`: cover lock-cycle transition semantics.

### Task 1: Add Lock-Cycle Transition Semantics

**Files:**
- Modify: `MistiaTests/MistiaAppLockControllerTests.swift`
- Modify: `Mistia/Shared/Security/MistiaAppLockController.swift`

- [ ] **Step 1: Write the failing regression test**

Add this test inside `MistiaAppLockControllerTests` before `makeDefaults()`:

```swift
func testLockCycleAdvancesOnlyForEachUnlockedToLockedTransition() throws {
    let defaults = makeDefaults()
    let credential = try MistiaAppLockCredential.make(
        kind: .pin4,
        secret: "1234",
        saltGenerator: { Data(repeating: 0x08, count: 16) }
    )
    defaults.set(true, forKey: MistiaAppStorageKey.appLockEnabled)
    defaults.set("pin4", forKey: MistiaAppStorageKey.appLockSecretKind)
    let controller = MistiaAppLockController(
        defaults: defaults,
        credentialStore: AppLockCredentialStoreSpy(credential: credential),
        biometricAuthenticator: AppLockBiometricAuthenticatorSpy(kind: .faceID)
    )

    let launchCycle = controller.lockCycle
    controller.lockIfNeeded()
    XCTAssertEqual(controller.lockCycle, launchCycle)

    XCTAssertTrue(controller.verify(secret: "1234"))
    controller.lockIfNeeded()
    XCTAssertEqual(controller.lockCycle, launchCycle + 1)

    controller.lockIfNeeded()
    XCTAssertEqual(controller.lockCycle, launchCycle + 1)

    XCTAssertTrue(controller.verify(secret: "1234"))
    controller.lockIfNeeded()
    XCTAssertEqual(controller.lockCycle, launchCycle + 2)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/MistiaAppLockControllerTests/testLockCycleAdvancesOnlyForEachUnlockedToLockedTransition
```

Expected: compilation fails because `MistiaAppLockController` has no `lockCycle` member.

- [ ] **Step 3: Implement the minimal controller behavior**

Add the observable state beside `isLocked`:

```swift
private(set) var isLocked = false
private(set) var lockCycle = 0
private(set) var failureState = MistiaAppLockFailureState.empty
```

Update the successful branch of `lockIfNeeded()` so it ignores duplicate lock requests and advances only on a real transition:

```swift
guard !isLocked else { return }
isLocked = true
lockCycle += 1
```

- [ ] **Step 4: Run the focused controller test class and verify GREEN**

Run:

```bash
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/MistiaAppLockControllerTests
```

Expected: all `MistiaAppLockControllerTests` pass with zero failures.

### Task 2: Recreate the Automatic Biometric Attempt Per Lock Cycle

**Files:**
- Modify: `Mistia/App/MistiaApp.swift`

- [ ] **Step 1: Bind the lock screen identity to the controller cycle**

Change the root lock overlay to:

```swift
MistiaAppLockScreen()
    .environment(appLockController)
    .id(appLockController.lockCycle)
```

This intentionally preserves `MistiaAppLockScreen`'s existing `didAttemptBiometric` guard: it remains exactly-once within one cycle and resets only when a new background lock creates a new identity.

- [ ] **Step 2: Run the focused controller tests again**

Run:

```bash
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/MistiaAppLockControllerTests
```

Expected: all controller tests pass with zero failures and the app target compiles as part of the test build.

### Task 3: Full Verification

**Files:**
- Verify: `Mistia/Shared/Security/MistiaAppLockController.swift`
- Verify: `Mistia/App/MistiaApp.swift`
- Verify: `MistiaTests/MistiaAppLockControllerTests.swift`

- [ ] **Step 1: Check the patch for accidental or malformed changes**

Run:

```bash
git diff --check
git diff -- Mistia/Shared/Security/MistiaAppLockController.swift Mistia/App/MistiaApp.swift MistiaTests/MistiaAppLockControllerTests.swift
```

Expected: `git diff --check` exits successfully and the diff contains only lock-cycle state, overlay identity, and regression coverage.

- [ ] **Step 2: Build the generic iOS app target**

Run:

```bash
xcodebuild \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **` with exit code 0.

- [ ] **Step 3: Commit the implementation**

```bash
git add Mistia/Shared/Security/MistiaAppLockController.swift Mistia/App/MistiaApp.swift MistiaTests/MistiaAppLockControllerTests.swift docs/superpowers/plans/2026-07-02-app-lock-foreground-biometric.md
git commit -m "fix: retry biometric unlock after background"
```
