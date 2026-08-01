# Mistia Shared Performance Hot Paths Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce main-thread input/render work and sync CPU allocations without changing Mistia behavior.

**Architecture:** Keep the optimizations inside existing shared primitives so all current call sites benefit automatically. Replace regex-based currency sanitization with an ASCII scalar scan, cache decoded exchange-rate payloads by raw `Data`, and compare UUID raw bytes instead of allocating UUID strings inside sort comparators.

**Tech Stack:** Swift 6, Foundation, CryptoKit, Swift Package Manager, XCTest, Xcode iOS build.

## Global Constraints

- Preserve current currency parsing, grouping, exchange-rate, and snapshot fingerprint semantics.
- Treat performance conclusions as synthetic benchmarks or code-review inference unless an Instruments trace exists.
- Add focused regression coverage before production changes and verify the package plus iOS app target.
- Do not commit automatically; leave the verified diff for the automation owner.

---

### Task 1: Currency Input Sanitization

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/MistiaLocalizationTests.swift`
- Modify: `Mistia/Shared/CoreLogic/CurrencyFormatting.swift`

**Interfaces:**
- Consumes: arbitrary user-entered currency text.
- Produces: `MistiaCurrencyInputFormatting.sanitizedDigitsAndSign(from:) -> String` and unchanged grouped/parsed values.

- [ ] **Step 1: Write the failing sanitizer test**

```swift
func testCurrencyInputSanitizationKeepsOnlyASCIIDigitsAndLeadingMinus() {
    XCTAssertEqual(
        MistiaCurrencyInputFormatting.sanitizedDigitsAndSign(from: " -1,2a３4 "),
        "-124"
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MistiaLocalizationTests/testCurrencyInputSanitizationKeepsOnlyASCIIDigitsAndLeadingMinus`

Expected: compile failure because the sanitizer is private.

- [ ] **Step 3: Replace regex and reverse-buffer grouping**

```swift
static func sanitizedDigitsAndSign(from input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    var result = ""
    result.reserveCapacity(trimmed.utf8.count)
    if trimmed.first == "-" { result.append("-") }
    for scalar in trimmed.unicodeScalars where scalar.value >= 48 && scalar.value <= 57 {
        result.unicodeScalars.append(scalar)
    }
    return result
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter MistiaLocalizationTests`

Expected: all localization/currency formatting tests pass.

### Task 2: Decoded Exchange-Rate Cache

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/MistiaLocalizationTests.swift`
- Modify: `Mistia/Shared/CoreLogic/CurrencyLogic.swift`

**Interfaces:**
- Consumes: raw exchange-rate JSON `Data` from `UserDefaults`.
- Produces: `MistiaCurrencySettings.cachedRates(from:) -> [MistiaExchangeRate]`, reused by `cachedRates(defaults:)`.

- [ ] **Step 1: Write the failing cache invalidation test**

```swift
func testCachedRatesFromDataRefreshesWhenPayloadChanges() throws {
    let first = try JSONEncoder().encode([makeRate(value: "165")])
    let second = try JSONEncoder().encode([makeRate(value: "170")])
    XCTAssertEqual(MistiaCurrencySettings.cachedRates(from: first).first?.rateDecimalString, "165")
    XCTAssertEqual(MistiaCurrencySettings.cachedRates(from: second).first?.rateDecimalString, "170")
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MistiaLocalizationTests/testCachedRatesFromDataRefreshesWhenPayloadChanges`

Expected: compile failure because the raw-data API does not exist.

- [ ] **Step 3: Add a lock-protected last-payload cache**

Implement a private `@unchecked Sendable` cache object guarded by `NSLock`; decode only when raw `Data` differs and retain only the latest payload/result pair.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter MistiaLocalizationTests`

Expected: cached data remains correct and refreshes when payload changes.

### Task 3: Allocation-Free UUID Sort Comparator

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/MistiaLocalizationTests.swift`
- Modify: `Mistia/Shared/Sync/MistiaSyncModels.swift`
- Modify: `Mistia/Shared/Sync/MistiaSyncCoordinator.swift`

**Interfaces:**
- Consumes: two `UUID` values.
- Produces: `MistiaStableUUIDOrdering.precedes(_:_:) -> Bool` matching canonical UUID string ordering without string allocation.

- [ ] **Step 1: Write the failing deterministic ordering test**

```swift
func testStableUUIDOrderingMatchesCanonicalByteOrder() throws {
    let values = try ["ff000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000001"]
        .map { try XCTUnwrap(UUID(uuidString: $0)) }
    XCTAssertEqual(
        values.sorted(by: MistiaStableUUIDOrdering.precedes).map(\.uuidString),
        ["00000000-0000-0000-0000-000000000001", "FF000000-0000-0000-0000-000000000000"]
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MistiaLocalizationTests/testStableUUIDOrderingMatchesCanonicalByteOrder`

Expected: compile failure because `MistiaStableUUIDOrdering` does not exist.

- [ ] **Step 3: Implement raw-byte ordering and replace sync comparators**

Compare each UUID's 16-byte representation with `lexicographicallyPrecedes`, then use the helper for all `MistiaRemoteSnapshot.fingerprint` collection sorts and family-owner ID ordering.

- [ ] **Step 4: Run sync/date focused tests and verify GREEN**

Run: `swift test --filter MistiaLocalizationTests`

Expected: all tests pass, including deterministic ordering and ISO8601 coverage.

### Task 4: Final Verification and Automation Memory

**Files:**
- Modify: `/Users/quylang/.codex/automations/performance-audit/memory.md`

**Interfaces:**
- Consumes: final diff and fresh test/build evidence.
- Produces: verified audit summary and follow-up measurement targets.

- [ ] **Step 1: Run package tests**

Run: `swift test`

Expected: zero failures.

- [ ] **Step 2: Build the iOS app**

Run: `xcodebuild -project Mistia.xcodeproj -scheme Mistia -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Check patch integrity**

Run: `git diff --check`

Expected: no output and exit code 0.

- [ ] **Step 4: Update automation memory**

Record the three optimized paths, technical decisions, synthetic benchmark evidence, verification output, and Instruments follow-up targets with the current run time.
