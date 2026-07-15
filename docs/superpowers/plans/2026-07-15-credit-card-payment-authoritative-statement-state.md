# Credit Card Payment-Authoritative Statement State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make credit-card statement paid state depend on an active payment transaction while preserving valid manual and member-created inferred payments.

**Architecture:** `PlanningLogic` remains the pure transaction-to-statement resolver and returns only an active explicit or inferred payment ID. `MistiaCreditCardStatementMaintenance` persists that result by linking valid payments or resetting stale paid occurrences before auto-pay decisions. Ledger debt remains transaction-only.

**Tech Stack:** Swift 6, SwiftData, XCTest, Swift Package Manager, Xcode iOS simulator tests.

## Global Constraints

- A paid occurrence without an active posted internal transfer into the card is invalid.
- An active payment may be explicitly linked or inferred from destination card, amount coverage, and timing after statement close.
- `created_by_user_id` may identify a family member and must not invalidate the payment.
- Do not create synthetic transactions, change RLS, change statement dates, add partial-payment behavior, or add localized copy.
- Do not modify live Supabase data as part of this implementation.

---

### Task 1: Require transaction-backed statement payment

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/PlanningLogicTests.swift`
- Modify: `Mistia/Shared/CoreLogic/PlanningLogic.swift`

**Interfaces:**
- Consumes: active `TransactionRecordSnapshot` values already passed to `PlanningLogic.creditCardStatementItems(...)`.
- Produces: `PlanningCreditCardStatementSnapshot.status` and `.linkedTransactionID` backed only by a matching active payment record.

- [ ] **Step 1: Write the failing pure-logic regression**

Add `testCreditCardStatementDoesNotTrustPaidOccurrenceWithoutActivePayment()` to `PlanningLogicTests`. Create one card charge and a paid occurrence whose `linkedTransactionID` is absent from `records`, then assert:

```swift
XCTAssertEqual(statement?.status, .pending)
XCTAssertEqual(statement?.state, .overdue)
XCTAssertNil(statement?.linkedTransactionID)
```

Update existing tests that intentionally model a paid statement to include a posted internal transfer whose ID matches the occurrence link. Keep `testCreditCardStatementIsPaidByPostedTransferAfterClosingEvenWhenLate()` as the inferred-payment reference.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter PlanningLogicTests/testCreditCardStatementDoesNotTrustPaidOccurrenceWithoutActivePayment
```

Expected: FAIL because the statement is currently `.paid` solely from the occurrence status.

- [ ] **Step 3: Implement the minimal active-payment resolver**

In the private `creditCardStatementItem(...)`, resolve payment as:

```swift
let linkedPayment = occurrence?.linkedTransactionID.flatMap { linkedID in
    sortedPaymentRecords.first { record in
        record.id == linkedID
            && isMatchingCreditCardPaymentRecord(
                record,
                amountMinor: amount,
                closingDate: closingDate,
                calendar: calendar
            )
    }
}
let resolvedPayment = linkedPayment ?? firstMatchingCreditCardPaymentRecord(
    amountMinor: amount,
    closingDate: closingDate,
    sortedPaymentRecords: sortedPaymentRecords,
    calendar: calendar
)
let status: PlanningDueOccurrenceStatus = resolvedPayment == nil ? .pending : .paid
let linkedTransactionID = resolvedPayment?.id
```

Extract the existing amount/date predicate into:

```swift
private static func isMatchingCreditCardPaymentRecord(
    _ record: TransactionRecordSnapshot,
    amountMinor: Int64,
    closingDate: Date,
    calendar: Calendar
) -> Bool
```

Use the same helper from `firstMatchingCreditCardPaymentRecord(...)` so explicit and inferred payments follow identical validity rules.

- [ ] **Step 4: Verify GREEN and related statement behavior**

Run:

```bash
swift test --filter PlanningLogicTests
```

Expected: all `PlanningLogicTests` pass, including explicit-link, inferred-payment, stale-occurrence, and legacy-month cases.

- [ ] **Step 5: Commit Task 1**

```bash
git add Tests/MistiaCoreLogicTests/PlanningLogicTests.swift Mistia/Shared/CoreLogic/PlanningLogic.swift
git diff --cached --check
git commit -m "fix: require active credit card payment records"
```

---

### Task 2: Reconcile persisted occurrences with resolved payments

**Files:**
- Modify: `MistiaTests/SessionStoreOfflineTests.swift`
- Modify: `Mistia/Shared/Notifications/MistiaCreditCardStatementMaintenance.swift`

**Interfaces:**
- Consumes: `PlanningCreditCardStatementSnapshot.status` and `.linkedTransactionID` from Task 1 plus `MistiaDueMaintenanceSnapshot.activeTransactions`.
- Produces: persisted `DueOccurrenceRecord` state that is paid only when linked to an active resolved payment.

- [ ] **Step 1: Write failing maintenance regressions**

Add two async tests to `SessionStoreOfflineTests`:

1. `testCreditCardStatementMaintenanceResetsPaidOccurrenceWhenLinkedPaymentWasDeleted`: insert a card charge, a soft-deleted matching transfer, and a paid occurrence linked to that transfer. Run maintenance and assert:

```swift
XCTAssertEqual(occurrence.status, .pending)
XCTAssertNil(occurrence.paidAt)
XCTAssertNil(occurrence.linkedTransactionID)
```

2. `testCreditCardStatementMaintenanceLinksMemberCreatedManualPaymentWhenAutoPayIsDisabled`: insert an active manual transfer into the card, a pending unlinked occurrence, owner scopes for the card owner, and a `TransactionAuditRecord` whose creator is another family member. Keep `autoPayEnabled = false`, run maintenance, and assert:

```swift
XCTAssertEqual(occurrence.status, .paid)
XCTAssertEqual(occurrence.linkedTransactionID, payment.id)
XCTAssertEqual(occurrence.paidAt, payment.occurredAt)
```

- [ ] **Step 2: Run both tests and verify RED**

Run:

```bash
xcodebuild -quiet -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath /tmp/mistia-card-payment-state-red \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MistiaTests/SessionStoreOfflineTests/testCreditCardStatementMaintenanceResetsPaidOccurrenceWhenLinkedPaymentWasDeleted \
  -only-testing:MistiaTests/SessionStoreOfflineTests/testCreditCardStatementMaintenanceLinksMemberCreatedManualPaymentWhenAutoPayIsDisabled \
  test
```

Expected: the stale occurrence remains paid and the manual/member-created payment remains pending/unlinked.

- [ ] **Step 3: Implement occurrence reconciliation**

Build one lookup before iterating statements:

```swift
let activeTransactionByID = Dictionary(
    snapshot.activeTransactions.map { ($0.id, $0) },
    uniquingKeysWith: { existing, candidate in
        existing.updatedAt >= candidate.updatedAt ? existing : candidate
    }
)
```

Immediately after `upsertClosedStatementOccurrence(...)`, reconcile before the `autoPayEnabled` guard:

```swift
if let paymentID = statement.linkedTransactionID,
   let payment = activeTransactionByID[paymentID] {
    markOccurrencePaid(
        occurrence,
        for: statement,
        linkedTransaction: payment,
        modelContext: modelContext,
        sessionStore: sessionStore,
        calendar: calendar
    )
} else {
    markOccurrencePendingIfNeeded(
        occurrence,
        for: statement,
        modelContext: modelContext,
        sessionStore: sessionStore,
        calendar: calendar
    )
}
```

Make `markOccurrencePaid(...)` change-aware so repeated maintenance runs do not queue redundant sync writes. Add `markOccurrencePendingIfNeeded(...)` to set statement month, amount, and due date while clearing stale `paidAt` and `linkedTransactionID`; save and call `recordUpsert` only when a field changed.

- [ ] **Step 4: Verify GREEN and no duplicate auto-payment regression**

Run the two focused tests from Step 2, then:

```bash
xcodebuild -quiet -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath /tmp/mistia-card-payment-state-maintenance \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MistiaTests/SessionStoreOfflineTests/testCreditCardStatementMaintenanceReusesExistingAutoPaymentTransaction \
  test
```

Expected: all selected maintenance tests pass and only one payment transaction exists.

- [ ] **Step 5: Commit Task 2**

```bash
git add MistiaTests/SessionStoreOfflineTests.swift Mistia/Shared/Notifications/MistiaCreditCardStatementMaintenance.swift
git diff --cached --check
git commit -m "fix: reconcile credit card payment occurrences"
```

---

### Task 3: Full verification and integration

**Files:**
- Verify: `Mistia/Shared/CoreLogic/PlanningLogic.swift`
- Verify: `Mistia/Shared/Notifications/MistiaCreditCardStatementMaintenance.swift`
- Verify: `Tests/MistiaCoreLogicTests/PlanningLogicTests.swift`
- Verify: `MistiaTests/SessionStoreOfflineTests.swift`

**Interfaces:**
- Consumes: completed Tasks 1 and 2.
- Produces: verified implementation ready to merge into `develop`.

- [ ] **Step 1: Run package regressions**

```bash
swift test --filter PlanningLogicTests
swift test --filter TransactionLogicTests
```

Expected: zero failures.

- [ ] **Step 2: Run focused iOS tests**

```bash
xcodebuild -quiet -project Mistia.xcodeproj -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath /tmp/mistia-card-payment-state-final-tests \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MistiaTests/SessionStoreOfflineTests/testCreditCardStatementMaintenanceResetsPaidOccurrenceWhenLinkedPaymentWasDeleted \
  -only-testing:MistiaTests/SessionStoreOfflineTests/testCreditCardStatementMaintenanceLinksMemberCreatedManualPaymentWhenAutoPayIsDisabled \
  -only-testing:MistiaTests/SessionStoreOfflineTests/testCreditCardStatementMaintenanceReusesExistingAutoPaymentTransaction \
  -only-testing:MistiaTests/CreditCardAvailableCreditTests \
  test
```

Expected: zero failures.

- [ ] **Step 3: Run hygiene and build checks**

```bash
/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
git diff --check
xcodebuild -quiet -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/mistia-card-payment-state-final-build \
  build
```

Expected: localization check passes, diff check is clean, and build exits 0.

- [ ] **Step 4: Merge and cleanup**

From the main checkout, merge the implementation branch into `develop`, rerun the focused regressions on the merged result, remove the `.worktrees/` worktree, prune registrations, and delete the temporary branch.
