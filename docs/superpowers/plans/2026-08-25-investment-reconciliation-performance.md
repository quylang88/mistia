# Investment Reconciliation Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Investment reconciliation from tab navigation and make remote/repair reconciliation targeted and idempotent without changing accounting or sync semantics.

**Architecture:** Keep existing local Buy/Sell persistence authoritative. Navigation performs no accounting work; remote sync collects only applied trade asset IDs and reconciles those histories once after a batch. A shared idempotent write policy prevents unchanged derived transactions, postings, ownership, and audit rows from receiving new timestamps.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, OSLog signposts, Swift Package Manager, Xcode 26.

---

## File Map

- Create `MistiaTests/InvestmentNavigationPerformanceGuardTests.swift`: source-contract regression preventing persistence calls from tab/screen appearance hooks.
- Modify `Mistia/Features/Investment/InvestmentHubView.swift`: remove full reconciliation from the hub and wallet-detail appearance paths while retaining UI-state hooks.
- Modify `Mistia/Features/Management/ManagementView.swift`: remove full reconciliation from tab appearance.
- Modify `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`: targeted-scope, idempotence, timestamp, accounting-parity, and synthetic-scale regressions.
- Modify `Mistia/Shared/Persistence/InvestmentPersistence.swift`: add targeted reconciliation, reuse the accounting engine, gate derived writes, and add reconciliation signposts.
- Extend `MistiaTests/InvestmentNavigationPerformanceGuardTests.swift`: source-contract proof that only rows accepted by sync schedule targeted reconciliation.
- Modify `Mistia/Shared/Sync/MistiaSyncLocalStore.swift`: collect applied asset IDs and reconcile after batch application; target one asset for a single remote trade.
- Preserve `MistiaInfo.plist`: do not stage or modify the user's build-number change.

## Task 1: Remove Persistence Work From Navigation

**Files:**
- Create: `MistiaTests/InvestmentNavigationPerformanceGuardTests.swift`
- Modify: `Mistia/Features/Investment/InvestmentHubView.swift:307-325`
- Modify: `Mistia/Features/Investment/InvestmentHubView.swift:2835-2842`
- Modify: `Mistia/Features/Management/ManagementView.swift:635-648`

- [ ] **Step 1: Write the failing navigation source-contract test**

```swift
import XCTest

final class InvestmentNavigationPerformanceGuardTests: XCTestCase {
    func testTabAndInvestmentAppearanceHooksDoNotRunAccountingReconciliation() throws {
        for relativePath in [
            "Investment/InvestmentHubView.swift",
            "Management/ManagementView.swift"
        ] {
            let source = try featureSource(relativePath: relativePath)
            XCTAssertFalse(
                source.contains("InvestmentPersistenceService.reconcileAllTrades"),
                "\(relativePath) must not run full Investment reconciliation from navigation or appearance hooks."
            )
        }
    }

    private func featureSource(relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot
                .appendingPathComponent("Mistia")
                .appendingPathComponent("Features")
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/InvestmentNavigationPerformanceGuardTests
```

Expected: FAIL because both feature files currently contain `InvestmentPersistenceService.reconcileAllTrades` in `onAppear`.

- [ ] **Step 3: Remove only the reconciliation calls**

Keep the Investment hub appearance hook as:

```swift
.onAppear {
    uiState?.requestQuickCreateHidden(true, id: viewID)
}
```

Keep the wallet-detail appearance hook as:

```swift
.onAppear {
    uiState?.requestQuickCreateHidden(true, id: viewID)
}
```

Delete the entire no-longer-needed Management hook:

```swift
.onAppear {
    try? InvestmentPersistenceService.reconcileAllTrades(context: modelContext)
}
```

Do not change `.task(id: ownerUserID)`, permission refresh, quick-create visibility, or navigation state.

- [ ] **Step 4: Re-run the test and verify GREEN**

Run the Step 2 command again.

Expected: `InvestmentNavigationPerformanceGuardTests` passes with zero failures.

- [ ] **Step 5: Commit the guard**

The removed calls restore the two feature files to their committed state, so stage the new regression test and confirm no unrelated file is staged:

```bash
git add MistiaTests/InvestmentNavigationPerformanceGuardTests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "perf: keep investment reconciliation out of navigation"
```

Expected staged path: only `MistiaTests/InvestmentNavigationPerformanceGuardTests.swift`.

## Task 2: Add Asset-Scoped Reconciliation

**Files:**
- Modify: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift:1360-1505`
- Modify: `Mistia/Shared/Persistence/InvestmentPersistence.swift:1043-1109`

- [ ] **Step 1: Write failing targeted-scope tests**

Add these tests to `InvestmentPersistenceTests`:

```swift
func testTargetedReconciliationRepairsOnlyRequestedAssetHistory() throws {
    let fixture = try makeFixture()
    let secondAsset = try InvestmentPersistenceService.createAsset(
        ownerUserID: fixture.ownerID,
        channelID: fixture.channel.id,
        name: "Item B",
        currencyCode: "JPY",
        context: fixture.context
    )
    let firstBuy = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 2,
        gross: 100,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )
    let secondBuy = try saveTrade(
        fixture: fixture,
        asset: secondAsset,
        kind: .buy,
        quantity: 3,
        gross: 300,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )
    let first = try XCTUnwrap(fetchTrade(id: firstBuy.id, fixture))
    let second = try XCTUnwrap(fetchTrade(id: secondBuy.id, fixture))
    let secondUpdatedAt = second.updatedAt
    let secondCostBasis = second.positionCostBasisAfterMinor

    first.positionCostBasisAfterMinor = -1
    try fixture.context.save()

    let result = try InvestmentPersistenceService.reconcileTrades(
        assetIDs: [fixture.asset.id],
        ownerUserID: fixture.ownerID,
        now: fixture.start.addingTimeInterval(100),
        context: fixture.context
    )

    XCTAssertEqual(try fetchTrade(id: firstBuy.id, fixture)?.positionCostBasisAfterMinor, 100)
    XCTAssertEqual(try fetchTrade(id: secondBuy.id, fixture)?.positionCostBasisAfterMinor, secondCostBasis)
    XCTAssertEqual(try fetchTrade(id: secondBuy.id, fixture)?.updatedAt, secondUpdatedAt)
    XCTAssertTrue(result.tradeIDs.contains(firstBuy.id))
    XCTAssertFalse(result.tradeIDs.contains(secondBuy.id))
}

func testTargetedReconciliationWithNoAssetIDsDoesNoWork() throws {
    let fixture = try makeFixture()
    _ = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 1,
        gross: 100,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )

    let result = try InvestmentPersistenceService.reconcileTrades(
        assetIDs: [],
        ownerUserID: fixture.ownerID,
        context: fixture.context
    )

    XCTAssertEqual(result, InvestmentPersistenceResult())
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
swift test --filter 'InvestmentPersistenceTests.testTargetedReconciliation'
```

Expected: compile failure because `reconcileTrades(assetIDs:ownerUserID:now:context:)` does not exist.

- [ ] **Step 3: Extract one shared reconciliation implementation**

Add the targeted API and retain `reconcileAllTrades` only as an explicit repair wrapper:

```swift
@discardableResult
static func reconcileTrades(
    assetIDs: Set<UUID>,
    ownerUserID: UUID? = nil,
    now: Date = .now,
    context: ModelContext
) throws -> InvestmentPersistenceResult {
    guard !assetIDs.isEmpty else { return InvestmentPersistenceResult() }

    let trades: [InvestmentTrade]
    if let ownerUserID {
        trades = try context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in
                    trade.ownerUserID == ownerUserID && trade.deletedAt == nil
                }
            )
        ).filter { assetIDs.contains($0.assetID) }
    } else {
        trades = try context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in trade.deletedAt == nil }
            )
        ).filter { assetIDs.contains($0.assetID) }
    }

    return try reconcile(
        trades: trades,
        now: now,
        context: context
    )
}

@discardableResult
static func reconcileAllTrades(
    ownerUserID: UUID? = nil,
    now: Date = .now,
    context: ModelContext
) throws -> InvestmentPersistenceResult {
    let trades: [InvestmentTrade]
    if let ownerUserID {
        trades = try context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in
                    trade.ownerUserID == ownerUserID && trade.deletedAt == nil
                }
            )
        )
    } else {
        trades = try context.fetch(
            FetchDescriptor<InvestmentTrade>(
                predicate: #Predicate<InvestmentTrade> { trade in trade.deletedAt == nil }
            )
        )
    }
    return try reconcile(trades: trades, now: now, context: context)
}
```

Move the current grouping/calculation body into:

```swift
private static func reconcile(
    trades: [InvestmentTrade],
    now: Date,
    context: ModelContext
) throws -> InvestmentPersistenceResult {
    guard !trades.isEmpty else { return InvestmentPersistenceResult() }

    let requestedAssetIDs = Set(trades.map(\.assetID))
    let assets = try context.fetch(
        FetchDescriptor<InvestmentAsset>(
            predicate: #Predicate<InvestmentAsset> { asset in asset.deletedAt == nil }
        )
    ).filter { requestedAssetIDs.contains($0.id) }
    let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    let wallets = try context.fetch(
        FetchDescriptor<LedgerWallet>(
            predicate: #Predicate<LedgerWallet> { wallet in wallet.deletedAt == nil }
        )
    )
    var walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
    var systemWalletByOwnerID: [UUID: LedgerWallet] = [:]
    var result = InvestmentPersistenceResult()

    for (assetID, assetTrades) in Dictionary(grouping: trades, by: \.assetID) {
        guard let asset = assetsByID[assetID] else { continue }
        let systemWallet: LedgerWallet
        if let cached = systemWalletByOwnerID[asset.ownerUserID] {
            systemWallet = cached
        } else {
            systemWallet = try ensureSystemWallet(
                ownerUserID: asset.ownerUserID,
                currencyCode: asset.currencyCode,
                now: now,
                context: context
            )
            systemWalletByOwnerID[asset.ownerUserID] = systemWallet
            walletsByID[systemWallet.id] = systemWallet
        }

        let sortedTrades = assetTrades.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.createdAt < $1.createdAt
        }
        let calculations = try InvestmentAccountingEngine.calculationMap(
            trades: sortedTrades.map(InvestmentTradeInput.init)
        )

        for trade in sortedTrades {
            guard let calculation = calculations[trade.id] else { continue }
            trade.releasedCostBasisMinor = calculation.releasedCostBasisMinor
            trade.realizedProfitLossMinor = calculation.realizedProfitLossMinor
            trade.positionQuantityAfter = calculation.positionQuantityAfter
            trade.positionCostBasisAfterMinor = calculation.positionCostBasisAfterMinor
            result.tradeIDs.insert(trade.id)
            try reconcileLedgerLegs(
                ownerUserID: trade.ownerUserID,
                trade: trade,
                assetName: asset.name,
                systemWallet: systemWallet,
                walletsByID: walletsByID,
                now: now,
                context: context,
                result: &result
            )
        }
    }

    try context.save()
    return result
}
```

- [ ] **Step 4: Re-run focused persistence tests**

```bash
swift test --filter InvestmentPersistenceTests
```

Expected: all `InvestmentPersistenceTests` pass.

- [ ] **Step 5: Continue to the idempotence RED test before committing**

Do not commit the scoped but still non-idempotent implementation separately. Continue directly to Task 3 so the branch never records an intermediate reconciliation implementation that violates the approved spec.

## Task 3: Make Repair Writes Idempotent

**Files:**
- Modify: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`
- Modify: `Mistia/Shared/Persistence/InvestmentPersistence.swift:93-101,1688-2229`

- [ ] **Step 1: Write the failing no-op/timestamp regression**

```swift
func testRepeatedTargetedReconciliationIsANoOpAndPreservesDerivedTimestamps() throws {
    let fixture = try makeFixture()
    let buy = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 2,
        gross: 100,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )
    let sell = try saveTrade(
        fixture: fixture,
        kind: .sell,
        quantity: 1,
        gross: 80,
        capitalWalletID: fixture.capitalWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )
    let ledgerBefore = Dictionary(uniqueKeysWithValues:
        try fixture.context.fetch(FetchDescriptor<LedgerTransaction>()).map { ($0.id, $0.updatedAt) }
    )
    let postingBefore = Dictionary(uniqueKeysWithValues:
        try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>()).map { ($0.id, $0.updatedAt) }
    )
    let tradeBefore = Dictionary(uniqueKeysWithValues:
        try fixture.context.fetch(FetchDescriptor<InvestmentTrade>()).map { ($0.id, $0.updatedAt) }
    )

    let result = try InvestmentPersistenceService.reconcileTrades(
        assetIDs: [fixture.asset.id],
        ownerUserID: fixture.ownerID,
        now: fixture.start.addingTimeInterval(1_000),
        context: fixture.context
    )

    XCTAssertEqual(result, InvestmentPersistenceResult())
    XCTAssertFalse(fixture.context.hasChanges)
    XCTAssertEqual(
        Dictionary(uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<LedgerTransaction>()).map { ($0.id, $0.updatedAt) }),
        ledgerBefore
    )
    XCTAssertEqual(
        Dictionary(uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>()).map { ($0.id, $0.updatedAt) }),
        postingBefore
    )
    XCTAssertEqual(
        Dictionary(uniqueKeysWithValues: try fixture.context.fetch(FetchDescriptor<InvestmentTrade>()).map { ($0.id, $0.updatedAt) }),
        tradeBefore
    )
    XCTAssertEqual(try fetchTrade(id: buy.id, fixture)?.positionCostBasisAfterMinor, 100)
    XCTAssertEqual(try fetchTrade(id: sell.id, fixture)?.realizedProfitLossMinor, 30)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
    XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 80)
}
```

- [ ] **Step 2: Run and verify RED**

```bash
swift test --filter InvestmentPersistenceTests.testRepeatedTargetedReconciliationIsANoOpAndPreservesDerivedTimestamps
```

Expected: FAIL because current derived upserts assign `updatedAt = now` and report every row as touched.

- [ ] **Step 3: Add an explicit write policy and mutation outcome**

```swift
private enum InvestmentDerivedWritePolicy {
    case always
    case ifChanged
}

private struct InvestmentUpsertOutcome<Model> {
    let model: Model
    let didMutate: Bool
}

@discardableResult
private static func assignIfChanged<Root: AnyObject, Value: Equatable>(
    _ value: Value,
    to keyPath: ReferenceWritableKeyPath<Root, Value>,
    on root: Root
) -> Bool {
    guard root[keyPath: keyPath] != value else { return false }
    root[keyPath: keyPath] = value
    return true
}

private static func applyCalculationIfNeeded(
    _ calculation: InvestmentTradeCalculation,
    to trade: InvestmentTrade
) -> Bool {
    var didMutate = false
    didMutate = assignIfChanged(
        calculation.releasedCostBasisMinor,
        to: \.releasedCostBasisMinor,
        on: trade
    ) || didMutate
    didMutate = assignIfChanged(
        calculation.realizedProfitLossMinor,
        to: \.realizedProfitLossMinor,
        on: trade
    ) || didMutate
    didMutate = assignIfChanged(
        InvestmentDecimalCoding.string(from: calculation.positionQuantityAfter),
        to: \.positionQuantityAfterDecimalString,
        on: trade
    ) || didMutate
    didMutate = assignIfChanged(
        calculation.positionCostBasisAfterMinor,
        to: \.positionCostBasisAfterMinor,
        on: trade
    ) || didMutate
    return didMutate
}
```

- [ ] **Step 4: Gate derived ledger and posting writes**

Add `writePolicy: InvestmentDerivedWritePolicy = .always` to `reconcileLedgerLegs`. Replace direct upsert calls inside it with outcome-producing variants. The ledger comparison must include every field the existing writer owns:

```swift
private static func ledgerTransactionMatches(
    _ transaction: LedgerTransaction,
    primaryKind: TransactionPrimaryKind,
    role: InvestmentLedgerLegRole,
    title: String,
    amountMinor: Int64,
    sourceWallet: LedgerWallet,
    destinationWallet: LedgerWallet?,
    destinationAmountMinor: Int64?,
    reportingAmountMinor: Int64,
    reportingCurrencyCode: String,
    occurredAt: Date
) -> Bool {
    transaction.primaryKind == primaryKind
        && transaction.transferSubtype == (primaryKind == .transfer ? .internalTransfer : nil)
        && transaction.debtIntent == nil
        && transaction.entryStatus == .posted
        && transaction.title == title
        && transaction.note == nil
        && transaction.amountMinor == max(amountMinor, 0)
        && transaction.reportingExpenseMinor == 0
        && transaction.reportingIncomeMinor == 0
        && transaction.sourceCurrencyCode == sourceWallet.currencyCode
        && transaction.destinationCurrencyCode == destinationWallet?.currencyCode
        && transaction.destinationAmountMinor == destinationAmountMinor
        && transaction.reportingCurrencyCode == reportingCurrencyCode
        && transaction.reportingAmountMinor == reportingAmountMinor
        && transaction.category == nil
        && transaction.sourceWallet?.id == sourceWallet.id
        && transaction.destinationWallet?.id == destinationWallet?.id
        && transaction.settlementGroupID == nil
        && transaction.settlementObligationID == nil
        && transaction.settlementRoleRawValue == role.rawValue
        && transaction.occurredAt == occurredAt
        && transaction.deletedAt == nil
        && !transaction.isArchived
        && transaction.archivedAt == nil
}
```

For `.ifChanged`, return `didMutate: false` without assignments when this comparison succeeds. For `.always` or a mismatch, perform the existing complete assignment block and set `updatedAt = now`.

Use these complete comparisons for the posting and cash-metadata paths:

```swift
private static func postingMatches(
    _ posting: InvestmentWalletPosting,
    ownerUserID: UUID,
    eventID: UUID,
    tradeID: UUID?,
    assetID: UUID?,
    walletID: UUID,
    ledgerTransactionID: UUID,
    role: InvestmentPostingRole,
    amountMinor: Int64,
    currencyCode: String,
    accountingAmountMinor: Int64,
    accountingCurrencyCode: String,
    occurredAt: Date
) -> Bool {
    posting.ownerUserID == ownerUserID
        && posting.eventID == eventID
        && posting.tradeID == tradeID
        && posting.assetID == assetID
        && posting.walletID == walletID
        && posting.ledgerTransactionID == ledgerTransactionID
        && posting.role == role
        && posting.amountMinor == amountMinor
        && posting.currencyCode == MistiaCurrencyLogic.normalizedCode(currencyCode)
        && posting.accountingAmountMinor == accountingAmountMinor
        && posting.accountingCurrencyCode
            == MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        && posting.occurredAt == occurredAt
        && posting.deletedAt == nil
}

private static func cashMetadataMatches(
    _ metadata: InvestmentCashPostingMetadata,
    ownerUserID: UUID,
    bucket: InvestmentCashBucket,
    origin: InvestmentCashPostingOrigin
) -> Bool {
    metadata.ownerUserID == ownerUserID
        && metadata.cashBucket == bucket
        && metadata.cashOrigin == origin
}
```

For `.ifChanged`, return an unchanged outcome when these comparisons succeed. Otherwise execute the current full assignment block and update `updatedAt`. Keep wrapper overloads returning only the model for non-reconciliation call sites so fund usage and cash transfer behavior remains unchanged.

Inside `reconcileLedgerLegs`, add IDs to `InvestmentPersistenceResult` only when the corresponding outcome has `didMutate == true`. Guard trade ledger-reference assignments with `assignIfChanged`; add the trade ID only when a reference changes.

- [ ] **Step 5: Avoid no-op ownership/audit timestamp bumps**

Keep the existing `recordTransactionOwnership` path for `.always`. For `.ifChanged`, call it only when the ledger row changed or ownership/audit metadata is absent or has the wrong owner:

```swift
private static func transactionMetadataNeedsRepair(
    transactionID: UUID,
    ownerUserID: UUID,
    context: ModelContext
) throws -> Bool {
    let scopeID = OwnedRecordScope.scopeID(entity: .transaction, recordID: transactionID)
    let scope = try context.fetch(
        FetchDescriptor<OwnedRecordScope>(
            predicate: #Predicate<OwnedRecordScope> { record in record.id == scopeID }
        )
    ).first
    let audit = try TransactionAuditStore.fetch(
        transactionID: transactionID,
        context: context
    )
    return scope?.ownerUserID != ownerUserID
        || audit?.createdByUserID != ownerUserID
        || audit?.lastModifiedByUserID != ownerUserID
}
```

When this helper is false and the ledger outcome is unchanged, do not call either upsert and do not add a mutation identifier.

- [ ] **Step 6: Run the complete persistence suite and verify GREEN**

```bash
swift test --filter InvestmentPersistenceTests
```

Expected: all tests pass, including unchanged FIFO, total-order, unit separation, wallet balance, deletion, and edit contracts.

- [ ] **Step 7: Commit scoped idempotent reconciliation**

```bash
git add \
  Mistia/Shared/Persistence/InvestmentPersistence.swift \
  Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift
git diff --cached --check
git commit -m "perf: make investment reconciliation targeted and idempotent"
```

## Task 4: Reconcile Only Applied Remote Trade Assets

**Files:**
- Modify: `MistiaTests/InvestmentNavigationPerformanceGuardTests.swift`
- Modify: `Mistia/Shared/Sync/MistiaSyncLocalStore.swift:873-896,1118-1125`

- [ ] **Step 1: Write the failing remote-apply source contract**

Add this method and shared-source reader to `InvestmentNavigationPerformanceGuardTests`:

```swift
func testSyncReconcilesOnlyTradeRowsAcceptedByConflictChecks() throws {
    let source = try sharedSource(relativePath: "Sync/MistiaSyncLocalStore.swift")
    let loopStart = try XCTUnwrap(source.range(of: "for row in snapshot.investmentTrades"))
    let postingStart = try XCTUnwrap(
        source[loopStart.lowerBound...].range(of: "for row in snapshot.investmentPostings")
    )
    let block = String(source[loopStart.lowerBound..<postingStart.lowerBound])
    let guardRange = try XCTUnwrap(block.range(of: "guard shouldApplyRemoteRow("))
    let insertRange = try XCTUnwrap(
        block.range(of: "appliedInvestmentAssetIDs.insert(row.assetID)")
    )

    XCTAssertLessThan(guardRange.lowerBound, insertRange.lowerBound)
    XCTAssertFalse(block.contains("snapshot.investmentTrades.isEmpty"))
    XCTAssertFalse(block.contains("reconcileAllTrades"))
    XCTAssertTrue(source.contains("assetIDs: [row.assetID]"))
}

private func sharedSource(relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
    return try String(
        contentsOf: repoRoot
            .appendingPathComponent("Mistia")
            .appendingPathComponent("Shared")
            .appendingPathComponent(relativePath),
        encoding: .utf8
    )
}
```

- [ ] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/InvestmentNavigationPerformanceGuardTests
```

Expected: FAIL because the source does not yet collect `appliedInvestmentAssetIDs` and still checks `snapshot.investmentTrades.isEmpty`.

- [ ] **Step 3: Collect applied asset IDs inside the existing guard**

Replace the bulk trade/reconciliation block with:

```swift
var appliedInvestmentAssetIDs: Set<UUID> = []
for row in snapshot.investmentTrades {
    guard shouldApplyRemoteRow(
        row,
        entity: .investmentTrade,
        existing: investmentTradeByID[row.id],
        protectedRecordIDs: protectedRecordIDs,
        preserveLocalNewerRows: preserveLocalNewerRows
    ) else { continue }
    upsertInvestmentTrade(row, context: context, tradeByID: &investmentTradeByID)
    appliedInvestmentAssetIDs.insert(row.assetID)
}
```

Keep the existing Investment posting loop, then reconcile once after it:

```swift
if !appliedInvestmentAssetIDs.isEmpty {
    try InvestmentPersistenceService.reconcileTrades(
        assetIDs: appliedInvestmentAssetIDs,
        now: .now,
        context: context
    )
}
```

For `.investmentTrade(let row)` in single-record apply, replace the full-owner call with:

```swift
try InvestmentPersistenceService.reconcileTrades(
    assetIDs: [row.assetID],
    ownerUserID: row.userID,
    now: .now,
    context: context
)
```

Do not use `try?`; let the existing throwing sync boundary abort the unsaved batch and retry rather than persist partially reconciled data.

- [ ] **Step 4: Run sync and persistence coverage**

```bash
swift test --filter InvestmentSyncCompatibilityTests
swift test --filter InvestmentPersistenceTests
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/InvestmentNavigationPerformanceGuardTests
```

Expected: both Swift Package suites and the app-target guard suite pass.

- [ ] **Step 5: Commit the sync boundary change**

```bash
git add \
  Mistia/Shared/Sync/MistiaSyncLocalStore.swift \
  MistiaTests/InvestmentNavigationPerformanceGuardTests.swift
git diff --cached --check
git commit -m "perf: scope investment reconciliation during sync"
```

## Task 5: Add Reconciliation Signposts and Synthetic Scale Evidence

**Files:**
- Modify: `Mistia/Shared/Persistence/InvestmentPersistence.swift`
- Modify: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`

- [ ] **Step 1: Add fixed-name privacy-safe signposts**

Add `import os` and this helper beside `InvestmentPersistenceService`:

```swift
private enum InvestmentReconciliationSignpost {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "Mistia",
        category: "InvestmentPerformance"
    )

    static func begin(_ name: StaticString, assetCount: Int, tradeCount: Int) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: name,
            signpostID: id,
            "assets=%{public}d trades=%{public}d",
            assetCount,
            tradeCount
        )
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
```

Pass a fixed `StaticString` into the private reconciliation function. Use `"Investment Targeted Reconciliation"` for `reconcileTrades` and `"Investment Full Reconciliation"` for the explicit repair wrapper. Begin after the input rows are resolved, and end with `defer`. Never log asset names, amounts, notes, wallet names, or user IDs.

- [ ] **Step 2: Add a deterministic synthetic-scale correctness test**

Add this complete synthetic fixture test:

```swift
func testTargetedReconciliationSyntheticScaleTouchesOnlyOneAsset() throws {
    let fixture = try makeFixture()
    var assets: [InvestmentAsset] = [fixture.asset]
    for index in 1..<40 {
        assets.append(
            try InvestmentPersistenceService.createAsset(
                ownerUserID: fixture.ownerID,
                channelID: fixture.channel.id,
                name: "Item \(index)",
                currencyCode: "JPY",
                context: fixture.context
            )
        )
    }

    var tradeIDsByAsset: [UUID: [UUID]] = [:]
    for (assetIndex, asset) in assets.enumerated() {
        for tradeIndex in 0..<10 {
            let trade = try saveTrade(
                fixture: fixture,
                asset: asset,
                kind: .buy,
                quantity: 1,
                gross: 1,
                fundingWalletID: fixture.fundingWallet.id,
                occurredAt: fixture.start.addingTimeInterval(
                    Double(assetIndex * 10 + tradeIndex)
                )
            )
            tradeIDsByAsset[asset.id, default: []].append(trade.id)
        }
    }

    let targetAssetID = assets[0].id
    let targetTradeID = try XCTUnwrap(tradeIDsByAsset[targetAssetID]?.last)
    let targetTrade = try XCTUnwrap(fetchTrade(id: targetTradeID, fixture))
    targetTrade.positionCostBasisAfterMinor = -1
    try fixture.context.save()

    let unrelatedTrades = try fixture.context.fetch(FetchDescriptor<InvestmentTrade>())
        .filter { $0.assetID != targetAssetID }
    let timestampsBefore = Dictionary(
        uniqueKeysWithValues: unrelatedTrades.map { ($0.id, $0.updatedAt) }
    )

    let clock = ContinuousClock()
    var result = InvestmentPersistenceResult()
    let elapsed = try clock.measure {
        result = try InvestmentPersistenceService.reconcileTrades(
            assetIDs: [targetAssetID],
            ownerUserID: fixture.ownerID,
            context: fixture.context
        )
    }

    XCTAssertEqual(result.tradeIDs, Set([targetTradeID]))
    XCTAssertEqual(result.ledgerTransactionIDs, Set<UUID>())
    XCTAssertEqual(result.postingIDs, Set<UUID>())
    XCTAssertTrue(
        unrelatedTrades.allSatisfy { $0.updatedAt == timestampsBefore[$0.id] }
    )
    XCTContext.runActivity(named: "Synthetic targeted reconciliation") { activity in
        activity.add(
            XCTAttachment(
                string: "elapsed=\(elapsed) assets=40 trades=400 targetAssets=1"
            )
        )
    }
}
```

Record wall-clock duration only as an attachment, not a pass/fail threshold. The fixture's 400 buys cost one minor unit each, remaining below its funding wallet's opening balance.

Label this result synthetic in the final report; it is not evidence of physical-device frame time.

- [ ] **Step 3: Run the scale and full Investment tests**

```bash
swift test --filter InvestmentPersistenceTests
```

Expected: all tests pass and the synthetic activity reports elapsed time without enforcing a hardware-dependent threshold.

- [ ] **Step 4: Commit observability and scale coverage**

```bash
git add \
  Mistia/Shared/Persistence/InvestmentPersistence.swift \
  Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift
git diff --cached --check
git commit -m "test: cover investment reconciliation scale"
```

## Task 6: Layered Verification and Physical-iPhone Handoff

**Files:**
- Verify: all modified files
- Preserve: `MistiaInfo.plist`

- [ ] **Step 1: Run complete Swift Package tests**

```bash
swift test
```

Expected: all package tests pass with zero failures.

- [ ] **Step 2: Run focused app-target guards on a concrete simulator**

```bash
xcodebuild test \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:MistiaTests/InvestmentNavigationPerformanceGuardTests \
  -only-testing:MistiaTests/FamilyPermissionResolutionTests
```

Expected: both suites pass. If the wrapper appears stalled, inspect the generated `.xcresult` before retrying.

- [ ] **Step 3: Build the iOS application**

```bash
xcodebuild \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the exact diff and untouched user file**

```bash
git diff --check
git status --short
git diff -- MistiaInfo.plist
rg -n 'reconcileAllTrades' Mistia/Features Mistia/App
```

Expected:

- no whitespace errors;
- `MistiaInfo.plist` still contains only the user's pre-existing change;
- no feature or app view calls `reconcileAllTrades`;
- the full method remains available only as an explicit persistence repair API.

- [ ] **Step 5: Capture the physical-iPhone Release comparison**

Use the same physical iPhone and the same populated profile for both captures. In Xcode Instruments, select Time Profiler or Hitches, run a Release build, and repeat this focused flow five times:

```text
Overview -> Transactions -> Planning -> Management -> Overview
```

Acceptance evidence:

- no `Investment Full Reconciliation` or `Investment Targeted Reconciliation` interval begins solely from a tab tap;
- the main thread has no Investment persistence stack during the tab transition;
- visible tab response no longer exhibits the reported approximately 1.2-second pause;
- a deliberate remote Investment trade apply emits one targeted interval for the affected asset batch.

Apple recommends device profiling for higher-fidelity hitch data and using Time Profiler/Hitches for responsiveness analysis:

- <https://developer.apple.com/documentation/xcode/improving-app-responsiveness>
- <https://developer.apple.com/documentation/xcode/improving-your-app-s-performance>

- [ ] **Step 6: Update the performance-audit automation memory**

Append a concise pass summary to `/Users/quylang/.codex/automations/performance-audit/memory.md` containing:

```markdown
## 2026-08-25 Investment Reconciliation Tab Hitch

- Problem: Full Investment reconciliation ran synchronously from tab/screen `onAppear`, rewrote derived timestamps, and broadly invalidated cached SwiftUI tabs.
- Fix: Removed persistence from navigation, reconciled only applied remote trade asset IDs, and made repair writes idempotent.
- Verification: Record focused/full test counts, build result, synthetic fixture size/timing, and physical-device trace status separately.
- Expected impact: Tab navigation performs no Investment accounting work; sync cost scales with changed asset histories and no-op repair produces no model writes.
```

Only write this memory entry after fresh verification results are available; replace the verification sentence with the actual commands, counts, timings, and any unmeasured device gap.
