# Credit Card Available Credit Source of Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every displayed and validated credit-card available-credit value use the latest credit limit and the same ledger-derived current debt.

**Architecture:** Add a pure `TransactionLogic.creditCardBalance` result as the single calculation boundary over the existing `TransactionWalletBalanceIndex`. Route Management, Planning, transaction validation, and shared payment validation through that boundary while leaving statement amount/state logic in `PlanningLogic` unchanged.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Swift Package Manager, Xcode iOS app tests.

## Global Constraints

- Available credit is `latest credit limit - current debt`, clamped to zero.
- Current debt includes opening debt and every posted, active ledger delta, including card payments.
- A limit-only edit preserves current debt.
- An amount equal to available credit is valid; only a larger amount is rejected.
- Statement closing, due dates, payment occurrences, sync, and localization behavior remain unchanged.
- Do not edit `Mistia/Localizable.xcstrings` or `Mistia/Shared/CoreLogic/L10n.generated.swift`.

---

### Task 1: Add the pure credit-card balance contract

**Files:**
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift:3-23,1808-1823`
- Test: `Tests/MistiaCoreLogicTests/TransactionLogicTests.swift`

**Interfaces:**
- Consumes: `TransactionWalletSnapshot` and `TransactionWalletBalanceIndex`.
- Produces: `TransactionCreditCardBalance`, `TransactionLogic.creditCardBalance(creditLimitMinor:wallet:balanceIndex:)`, `TransactionLogic.creditCardOpeningDebtMinor(targetCurrentDebtMinor:wallet:balanceIndex:)`, and `TransactionCreditCardBalance.canCover(amountMinor:)`.

- [ ] **Step 1: Write the failing pure-logic regressions**

Add these tests before production code:

```swift
func testCreditCardBalanceIncludesOpeningDebtPurchasesAndPayments() {
    let card = TransactionWalletSnapshot(
        id: UUID(),
        kind: .creditCard,
        openingBalanceMinor: 20_000
    )
    let occurredAt = Date(timeIntervalSince1970: 1_783_728_000)
    let records = [
        makeRecord(
            primaryKind: .expense,
            amountMinor: 30_000,
            occurredAt: occurredAt,
            sourceWalletID: card.id,
            sourceWalletKind: .creditCard
        ),
        makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 10_000,
            occurredAt: occurredAt.addingTimeInterval(60),
            destinationWalletID: card.id,
            destinationWalletKind: .creditCard
        )
    ]
    let balanceIndex = TransactionLogic.walletBalanceIndex(
        wallets: [card],
        records: records
    )

    let balance = TransactionLogic.creditCardBalance(
        creditLimitMinor: 100_000,
        wallet: card,
        balanceIndex: balanceIndex
    )

    XCTAssertEqual(balance.currentDebtMinor, 40_000)
    XCTAssertEqual(balance.availableCreditMinor, 60_000)
}

func testCreditCardBalanceUsesLatestLimitAndAllowsExactAvailableAmount() {
    let card = TransactionWalletSnapshot(
        id: UUID(),
        kind: .creditCard,
        openingBalanceMinor: 50_000
    )
    let balanceIndex = TransactionLogic.walletBalanceIndex(
        wallets: [card],
        records: [TransactionRecordSnapshot]()
    )

    let balance = TransactionLogic.creditCardBalance(
        creditLimitMinor: 150_000,
        wallet: card,
        balanceIndex: balanceIndex
    )

    XCTAssertEqual(balance.currentDebtMinor, 50_000)
    XCTAssertEqual(balance.availableCreditMinor, 100_000)
    XCTAssertTrue(balance.canCover(amountMinor: 100_000))
    XCTAssertFalse(balance.canCover(amountMinor: 100_001))
}

func testCreditCardOpeningDebtPreservesCurrentDebtAfterLimitOnlyEdit() {
    let card = TransactionWalletSnapshot(
        id: UUID(),
        kind: .creditCard,
        openingBalanceMinor: 20_000
    )
    let purchase = makeRecord(
        primaryKind: .expense,
        amountMinor: 30_000,
        occurredAt: Date(timeIntervalSince1970: 1_783_728_000),
        sourceWalletID: card.id,
        sourceWalletKind: .creditCard
    )
    let balanceIndex = TransactionLogic.walletBalanceIndex(
        wallets: [card],
        records: [purchase]
    )

    XCTAssertEqual(
        TransactionLogic.creditCardOpeningDebtMinor(
            targetCurrentDebtMinor: 50_000,
            wallet: card,
            balanceIndex: balanceIndex
        ),
        20_000
    )
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter TransactionLogicTests/testCreditCardBalance
```

Expected: compilation fails because `TransactionLogic.creditCardBalance` and `TransactionCreditCardBalance` do not exist.

- [ ] **Step 3: Implement the minimal pure calculation**

Add beside `TransactionWalletBalanceIndex`:

```swift
nonisolated struct TransactionCreditCardBalance: Equatable {
    let currentDebtMinor: Int64
    let availableCreditMinor: Int64

    func canCover(amountMinor: Int64) -> Bool {
        amountMinor <= availableCreditMinor
    }
}
```

Add beside `effectiveBalance` and `walletBalanceIndex`:

```swift
static func creditCardBalance(
    creditLimitMinor: Int64,
    wallet: TransactionWalletSnapshot,
    balanceIndex: TransactionWalletBalanceIndex
) -> TransactionCreditCardBalance {
    let currentDebtMinor = max(balanceIndex.balance(for: wallet), 0)
    return TransactionCreditCardBalance(
        currentDebtMinor: currentDebtMinor,
        availableCreditMinor: max(creditLimitMinor - currentDebtMinor, 0)
    )
}

static func creditCardOpeningDebtMinor(
    targetCurrentDebtMinor: Int64,
    wallet: TransactionWalletSnapshot,
    balanceIndex: TransactionWalletBalanceIndex
) -> Int64 {
    let postedDelta = balanceIndex.balance(for: wallet) - wallet.openingBalanceMinor
    return max(targetCurrentDebtMinor - postedDelta, 0)
}
```

- [ ] **Step 4: Run the focused and full core-logic tests and verify GREEN**

Run:

```bash
swift test --filter TransactionLogicTests/testCreditCardBalance
swift test --filter TransactionLogicTests
```

Expected: both new tests pass and the existing `TransactionLogicTests` suite remains green.

- [ ] **Step 5: Commit the pure contract**

```bash
git add Mistia/Shared/CoreLogic/TransactionLogic.swift Tests/MistiaCoreLogicTests/TransactionLogicTests.swift
git commit -m "fix: centralize credit card available credit"
```

---

### Task 2: Route Management and Planning displays through the ledger balance

**Files:**
- Create: `MistiaTests/CreditCardAvailableCreditTests.swift`
- Modify: `Mistia/Features/Planning/PlanningSupport.swift:680-771`
- Modify: `Mistia/Features/Management/ManagementView.swift:147-159,236-287`
- Modify: `Mistia/Features/Management/ManagementEditors.swift:40-47,612-647`
- Modify: `Mistia/Features/Planning/PlanningEditors.swift:2179-2214`

**Interfaces:**
- Consumes: `TransactionLogic.creditCardBalance(creditLimitMinor:wallet:balanceIndex:)` from Task 1.
- Produces: Management and Planning snapshots whose `currentDebtMinor` and `availableCreditMinor` match transaction validation after a limit edit.

- [ ] **Step 1: Write the failing app-level regression**

Create `MistiaTests/CreditCardAvailableCreditTests.swift`:

```swift
import XCTest
@testable import Mistia

@MainActor
final class CreditCardAvailableCreditTests: XCTestCase {
    func testPlanningSnapshotUsesLedgerDebtAndLatestLimit() {
        let wallet = LedgerWallet(
            name: "Card",
            kind: .creditCard,
            iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.creditCard.defaultColorHex,
            openingBalanceMinor: 20_000
        )
        let profile = CreditCardProfile(
            creditLimitMinor: 150_000,
            wallet: wallet
        )
        wallet.creditCardProfile = profile
        let occurredAt = Date(timeIntervalSince1970: 1_783_728_000)
        let purchase = TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Purchase",
            note: nil,
            amountMinor: 30_000,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: wallet.id,
            sourceWalletKind: .creditCard,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )

        let snapshot = wallet.planningCreditCardSnapshot(
            records: [purchase],
            occurrences: []
        )

        XCTAssertEqual(snapshot?.currentDebtMinor, 50_000)
        XCTAssertEqual(snapshot?.availableCreditMinor, 100_000)
    }
}
```

- [ ] **Step 2: Run the app regression and verify RED**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/CreditCardAvailableCreditTests \
  test
```

Expected: the assertions fail because the statement-based path reports transaction-only debt instead of opening debt plus ledger activity.

- [ ] **Step 3: Make `planningCreditCardSnapshot` use the shared ledger calculation**

Keep the public signature compatible but make occurrences statement-only input by ignoring it for current balance:

```swift
func planningCreditCardSnapshot(
    records: [TransactionRecordSnapshot],
    occurrences _: [PlanningDueOccurrenceSnapshot]
) -> PlanningCreditCardAccountSnapshot? {
    let walletSnapshot = TransactionWalletSnapshot(
        id: id,
        kind: kind,
        openingBalanceMinor: openingBalanceMinor
    )
    let balanceIndex = TransactionLogic.walletBalanceIndex(
        wallets: [walletSnapshot],
        records: records
    )
    return planningCreditCardSnapshot(balanceIndex: balanceIndex)
}
```

Inside `planningCreditCardSnapshot(balanceIndex:)`, replace the duplicated subtraction with:

```swift
let walletSnapshot = TransactionWalletSnapshot(
    id: id,
    kind: kind,
    openingBalanceMinor: openingBalanceMinor
)
let balance = TransactionLogic.creditCardBalance(
    creditLimitMinor: profile.creditLimitMinor,
    wallet: walletSnapshot,
    balanceIndex: balanceIndex
)
```

Populate the returned account with `balance.currentDebtMinor` and `balance.availableCreditMinor`.

- [ ] **Step 4: Align the Management row snapshot**

In `ManagementView.renderSnapshot`, delete the statement-specific `storedOccurrences`, `occurrenceSnapshots`, `recordSnapshots`, and `PlanningLogic.calculateCreditCardDebtAndAvailable` path. Use the already-built `balanceIndex`:

```swift
var balancesByID: [UUID: Int64] = [:]
for (wallet, walletSnapshot) in zip(activeWallets, activeWalletSnapshots) {
    if wallet.kind == .creditCard, let profile = wallet.creditCardProfile {
        balancesByID[wallet.id] = TransactionLogic.creditCardBalance(
            creditLimitMinor: profile.creditLimitMinor,
            wallet: walletSnapshot,
            balanceIndex: balanceIndex
        ).currentDebtMinor
    } else {
        balancesByID[wallet.id] = balanceIndex.balance(for: walletSnapshot)
    }
}
```

`ManagementWalletRow.availableCreditMinor` can remain unchanged because it now receives the canonical current debt.

- [ ] **Step 5: Align both credit-card editors**

Replace each editor's statement-based `calculateDebtAndAvailable` body with the shared ledger path:

```swift
private func calculateDebtAndAvailable(
    for wallet: LedgerWallet,
    creditLimitMinor: Int64
) -> (debt: Int64, available: Int64) {
    let walletSnapshot = TransactionWalletSnapshot(
        id: wallet.id,
        kind: wallet.kind,
        openingBalanceMinor: wallet.openingBalanceMinor
    )
    let balanceIndex = TransactionLogic.walletBalanceIndex(
        wallets: [walletSnapshot],
        records: storedTransactions.lazy
            .filter { $0.deletedAt == nil }
            .map(\.snapshot)
    )
    let balance = TransactionLogic.creditCardBalance(
        creditLimitMinor: creditLimitMinor,
        wallet: walletSnapshot,
        balanceIndex: balanceIndex
    )
    return (balance.currentDebtMinor, balance.availableCreditMinor)
}
```

Remove `ManagementWalletEditorSheet.storedOccurrences`, which becomes unused. Keep `PlanningCreditCardEditorSheet.storedOccurrences` because its save flow still updates due occurrences.

In each editor's existing-card save branch, replace the inline opening-debt algebra with the tested helper:

```swift
let targetDebtMinor = max(creditLimitMinor - availableCreditMinor, 0)
let walletSnapshot = TransactionWalletSnapshot(
    id: wallet.id,
    kind: wallet.kind,
    openingBalanceMinor: wallet.openingBalanceMinor
)
let balanceIndex = TransactionLogic.walletBalanceIndex(
    wallets: [walletSnapshot],
    records: storedTransactions.lazy
        .filter { $0.deletedAt == nil }
        .map(\.snapshot)
)
let currentDebtMinor = TransactionLogic.creditCardOpeningDebtMinor(
    targetCurrentDebtMinor: targetDebtMinor,
    wallet: walletSnapshot,
    balanceIndex: balanceIndex
)
```

This explicitly preserves the existing opening debt when only the credit limit changes.

- [ ] **Step 6: Run the regression and relevant package tests**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/CreditCardAvailableCreditTests \
  test
swift test --filter PlanningLogicTests
```

Expected: the app regression passes and statement-specific Planning tests remain green.

- [ ] **Step 7: Commit display and editor alignment**

```bash
git add MistiaTests/CreditCardAvailableCreditTests.swift \
  Mistia/Features/Planning/PlanningSupport.swift \
  Mistia/Features/Management/ManagementView.swift \
  Mistia/Features/Management/ManagementEditors.swift \
  Mistia/Features/Planning/PlanningEditors.swift
git commit -m "fix: align displayed credit card availability"
```

---

### Task 3: Route every affected validation through the shared contract

**Files:**
- Modify: `Mistia/Features/Transactions/TransactionEditorSheet.swift:3058-3254`
- Modify: `Mistia/Features/Planning/PlanningSupport.swift:285-317`
- Test: `Tests/MistiaCoreLogicTests/TransactionLogicTests.swift`
- Test: `MistiaTests/PlanningDuePaymentPersistenceTests.swift`

**Interfaces:**
- Consumes: `TransactionCreditCardBalance.canCover(amountMinor:)` from Task 1 and canonical snapshots from Task 2.
- Produces: identical limit handling for normal expenses, resale purchase cost, lend/repay debt flows, and shared due-payment persistence.

- [ ] **Step 1: Strengthen the regression at the persistence boundary**

Add a test that uses opening debt and a newly raised profile limit. Save an amount exactly equal to canonical available credit and assert one transaction and one occurrence are created. Use the same in-memory `ModelContainer` and `PlanningDuePaymentDraft` construction already present in `PlanningDuePaymentPersistenceTests`:

```swift
func testSaveDuePaymentAcceptsExactAvailableCreditAfterLimitIncrease() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let card = LedgerWallet(
        name: "Card",
        kind: .creditCard,
        iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
        iconColorHex: LedgerWalletKind.creditCard.defaultColorHex,
        openingBalanceMinor: 20_000
    )
    let profile = CreditCardProfile(creditLimitMinor: 100_000, wallet: card)
    card.creditCardProfile = profile
    context.insert(card)
    context.insert(profile)
    try context.save()

    profile.creditLimitMinor = 120_000
    let draft = PlanningDuePaymentDraft(
        primaryKind: .expense,
        transferSubtype: nil,
        title: "Purchase",
        amountMinor: 100_000,
        sourceWalletID: card.id,
        destinationWalletID: nil,
        categorySystemKey: .billing
    )

    try PlanningPersistenceSupport.saveDuePayment(
        draft: draft,
        sourceKind: .recurringBill,
        sourceID: UUID(),
        selectedMonth: makeDate(year: 2026, month: 7, day: 1),
        scheduledDate: makeDate(year: 2026, month: 7, day: 25),
        wallets: [card],
        occurrences: [],
        modelContext: context,
        actorUserID: nil,
        calendar: calendar
    )

    XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerTransaction>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<DueOccurrenceRecord>()).count, 1)
}
```

- [ ] **Step 2: Run the persistence regression before refactoring**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/PlanningDuePaymentPersistenceTests \
  test
```

Expected: the new boundary test passes under existing behavior; retain it as integration coverage while the core RED test from Task 1 proves the missing shared contract. Do not change its expected result during the refactor.

- [ ] **Step 3: Replace Transaction Editor's three duplicated formulas**

Add one private adapter:

```swift
private func creditCardBalance(
    for wallet: LedgerWallet,
    balanceIndex: TransactionWalletBalanceIndex
) -> TransactionCreditCardBalance {
    TransactionLogic.creditCardBalance(
        creditLimitMinor: wallet.creditCardProfile?.creditLimitMinor ?? 0,
        wallet: TransactionWalletSnapshot(
            id: wallet.id,
            kind: wallet.kind,
            openingBalanceMinor: wallet.openingBalanceMinor
        ),
        balanceIndex: balanceIndex
    )
}
```

For the ordinary expense and lend/repay branches use:

```swift
if !creditCardBalance(
    for: sourceWallet,
    balanceIndex: validationBalanceIndex
).canCover(amountMinor: amountMinor) {
    alertMessage = L10n.transactions.transactioneditor.theAmountExceedsTheAvailableCreditOn
    return
}
```

For the resale branch use the same code with `purchaseCostMinor`. Keep the paid-statement guard before the balance check and keep non-credit-card validation unchanged.

- [ ] **Step 4: Replace shared payment persistence's duplicated formula**

In `validateSourceWalletCanCoverPayment`, replace the credit-card subtraction with:

```swift
if sourceWallet.kind == .creditCard {
    let balance = TransactionLogic.creditCardBalance(
        creditLimitMinor: sourceWallet.creditCardProfile?.creditLimitMinor ?? 0,
        wallet: sourceSnapshot,
        balanceIndex: balanceIndex
    )
    guard balance.canCover(amountMinor: amountMinor) else {
        throw PlanningPersistenceError.insufficientWalletBalance
    }
} else {
    guard balanceIndex.balance(for: sourceSnapshot) >= amountMinor else {
        throw PlanningPersistenceError.insufficientWalletBalance
    }
}
```

- [ ] **Step 5: Run focused regression suites**

Run serially to avoid the shared DerivedData build database lock:

```bash
swift test --filter TransactionLogicTests
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/CreditCardAvailableCreditTests \
  -only-testing:MistiaTests/PlanningDuePaymentPersistenceTests \
  test
```

Expected: all focused tests pass with no new warnings or failures.

- [ ] **Step 6: Run final static and build verification**

Run:

```bash
git diff --check
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `git diff --check` emits no output and the generic iOS build ends with `** BUILD SUCCEEDED **`.

Confirm with `git diff --name-only` that neither localization source nor generated localization code changed.

- [ ] **Step 7: Commit validation alignment**

```bash
git add Mistia/Features/Transactions/TransactionEditorSheet.swift \
  Mistia/Features/Planning/PlanningSupport.swift \
  MistiaTests/PlanningDuePaymentPersistenceTests.swift
git commit -m "fix: validate against current card availability"
```
