# Investment Buy Activity Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit every field of an existing investment buy while keeping its ID and buy kind fixed and atomically rebuilding both affected assets and wallets locally and in Supabase.

**Architecture:** Keep `InvestmentTradeEditorSheet` and `InvestmentPersistenceService.saveTrade` as the existing UI and local write boundaries. Replace the single-asset recalculation with one preflighted rebuild batch per affected asset, then update the same trade and reconcile its stable derived-ledger IDs. Replace the Supabase mutation RPC in a forward-only migration so it locks both asset histories deterministically, preserves optimistic concurrency, and rebuilds the old and new assets in one transaction.

**Tech Stack:** SwiftUI, SwiftData, XCTest, Swift Package Manager, PostgreSQL/PLpgSQL, Supabase CLI, pgTAP, Xcode.

---

## File Map

- Modify `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`: local red-green coverage for moving a buy, changing its wallet and values, rejecting kind changes, and rolling back insufficient-funds edits.
- Modify `Mistia/Shared/Persistence/InvestmentPersistence.swift`: permit relation edits for the same trade, keep kind immutable, preflight both asset histories, and reconcile both histories in one save.
- Modify `Mistia/Features/Investment/InvestmentHubView.swift`: enable the asset picker only for existing buys and refresh the exchange-rate snapshot when the selected asset changes currency.
- Modify `supabase/tests/database/investment_domain.sql`: pgTAP coverage for cross-asset/cross-wallet edits, immutable kind, stale versions, derived posting relations, and rollback.
- Create `supabase/migrations/20260810111705_allow_investment_buy_activity_edits.sql`: replace `mutate_investment_trade` without changing its signature or grants.

No SwiftData model, String Catalog, sync payload, or Supabase table change is required.

### Task 1: Add Local Persistence Regressions

**Files:**
- Modify: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`

- [ ] **Step 1: Add a failing cross-asset and cross-wallet edit test**

Add this test before the private fixture helpers:

```swift
func testEditingBuyMovesItBetweenAssetsAndWalletsAndRebuildsBothHistories() throws {
    let fixture = try makeFixture()
    let secondWallet = LedgerWallet(
        name: "Second funding",
        kind: .bank,
        iconSymbolName: "building.columns.fill",
        iconColorHex: "#111111",
        currencyCode: "JPY",
        openingBalanceMinor: 1_000
    )
    fixture.context.insert(secondWallet)
    let secondChannel = try InvestmentPersistenceService.createChannel(
        ownerUserID: fixture.ownerID,
        name: "Second shop",
        iconSymbolName: "shippingbox.fill",
        iconColorHex: "#9A67FF",
        primaryCurrencyCode: "JPY",
        context: fixture.context
    ).channel
    let secondAsset = try InvestmentPersistenceService.createAsset(
        ownerUserID: fixture.ownerID,
        channelID: secondChannel.id,
        name: "Item B",
        currencyCode: "JPY",
        context: fixture.context
    )
    let movedBuy = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 3,
        gross: 120,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )
    let remainingBuy = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 1,
        gross: 50,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )
    let correctedDate = fixture.start.addingTimeInterval(100)
    let result = try InvestmentPersistenceService.saveTrade(
        ownerUserID: fixture.ownerID,
        draft: InvestmentTradeDraft(
            id: movedBuy.id,
            channelID: secondChannel.id,
            assetID: secondAsset.id,
            kind: .buy,
            quantity: 4,
            grossAmountMinor: 200,
            currencyCode: "JPY",
            accountingGrossAmountMinor: 200,
            accountingCurrencyCode: "JPY",
            fundingWalletID: secondWallet.id,
            note: "Corrected buy",
            occurredAt: correctedDate,
            createdAt: movedBuy.createdAt
        ),
        rates: [],
        now: correctedDate.addingTimeInterval(1),
        context: fixture.context
    )

    let storedMovedBuy = try XCTUnwrap(fetchTrade(id: movedBuy.id, fixture))
    XCTAssertEqual(storedMovedBuy.id, movedBuy.id)
    XCTAssertEqual(storedMovedBuy.kind, .buy)
    XCTAssertEqual(storedMovedBuy.channelID, secondChannel.id)
    XCTAssertEqual(storedMovedBuy.assetID, secondAsset.id)
    XCTAssertEqual(storedMovedBuy.quantity, 4)
    XCTAssertEqual(storedMovedBuy.grossAmountMinor, 200)
    XCTAssertEqual(storedMovedBuy.occurredAt, correctedDate)
    XCTAssertEqual(storedMovedBuy.fundingWalletID, secondWallet.id)
    XCTAssertEqual(storedMovedBuy.note, "Corrected buy")
    XCTAssertEqual(storedMovedBuy.positionQuantityAfter, 4)
    XCTAssertEqual(storedMovedBuy.positionCostBasisAfterMinor, 200)

    let storedRemainingBuy = try XCTUnwrap(fetchTrade(id: remainingBuy.id, fixture))
    XCTAssertEqual(storedRemainingBuy.assetID, fixture.asset.id)
    XCTAssertEqual(storedRemainingBuy.positionQuantityAfter, 1)
    XCTAssertEqual(storedRemainingBuy.positionCostBasisAfterMinor, 50)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 950)
    XCTAssertEqual(try balance(secondWallet, fixture), 800)
    XCTAssertTrue(result.walletIDs.contains(fixture.fundingWallet.id))
    XCTAssertTrue(result.walletIDs.contains(secondWallet.id))

    let posting = try XCTUnwrap(
        fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .first { $0.tradeID == movedBuy.id && $0.deletedAt == nil }
    )
    XCTAssertEqual(posting.assetID, secondAsset.id)
    XCTAssertEqual(posting.walletID, secondWallet.id)
    XCTAssertEqual(posting.amountMinor, -200)
}
```

- [ ] **Step 2: Add immutable-kind, rollback, and same-asset reconciliation tests**

Add:

```swift
func testEditingExistingTradeCannotChangeBuyIntoSell() throws {
    let fixture = try makeFixture()
    _ = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 2,
        gross: 200,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )
    let editedBuy = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 1,
        gross: 50,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )

    XCTAssertThrowsError(
        try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: editedBuy.id,
                channelID: fixture.channel.id,
                assetID: fixture.asset.id,
                kind: .sell,
                quantity: 1,
                grossAmountMinor: 70,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 70,
                accountingCurrencyCode: "JPY",
                capitalReturnWalletID: fixture.capitalWallet.id,
                occurredAt: fixture.start.addingTimeInterval(2),
                createdAt: editedBuy.createdAt
            ),
            rates: [],
            context: fixture.context
        )
    ) { error in
        XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
    }
    XCTAssertEqual(try fetchTrade(id: editedBuy.id, fixture)?.kind, .buy)
}

func testEditingBuyWithInsufficientNewWalletLeavesOriginalStateUnchanged() throws {
    let fixture = try makeFixture()
    let lowBalanceWallet = LedgerWallet(
        name: "Low balance",
        kind: .cash,
        iconSymbolName: "banknote.fill",
        iconColorHex: "#222222",
        currencyCode: "JPY",
        openingBalanceMinor: 10
    )
    fixture.context.insert(lowBalanceWallet)
    let original = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 1,
        gross: 100,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )

    XCTAssertThrowsError(
        try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: original.id,
                channelID: fixture.channel.id,
                assetID: fixture.asset.id,
                kind: .buy,
                quantity: 2,
                grossAmountMinor: 50,
                currencyCode: "JPY",
                accountingGrossAmountMinor: 50,
                accountingCurrencyCode: "JPY",
                fundingWalletID: lowBalanceWallet.id,
                occurredAt: fixture.start.addingTimeInterval(1),
                createdAt: original.createdAt
            ),
            rates: [],
            context: fixture.context
        )
    ) { error in
        XCTAssertEqual(error as? InvestmentPersistenceError, .insufficientFunds)
    }

    let stored = try XCTUnwrap(fetchTrade(id: original.id, fixture))
    XCTAssertEqual(stored.quantity, 1)
    XCTAssertEqual(stored.grossAmountMinor, 100)
    XCTAssertEqual(stored.fundingWalletID, fixture.fundingWallet.id)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 900)
    XCTAssertEqual(try balance(lowBalanceWallet, fixture), 10)
}

func testEditingBuyWithinSameAssetReusesOneDerivedLedgerAndPosting() throws {
    let fixture = try makeFixture()
    let original = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 3,
        gross: 120,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )
    let correctedDate = fixture.start.addingTimeInterval(10)

    _ = try InvestmentPersistenceService.saveTrade(
        ownerUserID: fixture.ownerID,
        draft: InvestmentTradeDraft(
            id: original.id,
            channelID: fixture.channel.id,
            assetID: fixture.asset.id,
            kind: .buy,
            quantity: 2,
            grossAmountMinor: 90,
            currencyCode: "JPY",
            accountingGrossAmountMinor: 90,
            accountingCurrencyCode: "JPY",
            fundingWalletID: fixture.fundingWallet.id,
            note: "Same asset correction",
            occurredAt: correctedDate,
            createdAt: original.createdAt
        ),
        rates: [],
        context: fixture.context
    )

    let fundingLedgerID = InvestmentLedgerIdentity.derivedID(eventID: original.id, component: "funding")
    let fundingPostingID = InvestmentLedgerIdentity.derivedID(eventID: original.id, component: "funding-posting")
    let activeLedgers = try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
        .filter { $0.id == fundingLedgerID && $0.deletedAt == nil }
    let activePostings = try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
        .filter { $0.id == fundingPostingID && $0.deletedAt == nil }
    XCTAssertEqual(activeLedgers.count, 1)
    XCTAssertEqual(activeLedgers.first?.amountMinor, 90)
    XCTAssertEqual(activePostings.count, 1)
    XCTAssertEqual(activePostings.first?.amountMinor, -90)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 910)
}
```

- [ ] **Step 3: Run the focused tests and verify the intended failures**

```bash
swift test --filter InvestmentPersistenceTests/testEditingBuyMovesItBetweenAssetsAndWalletsAndRebuildsBothHistories
swift test --filter InvestmentPersistenceTests/testEditingExistingTradeCannotChangeBuyIntoSell
```

Expected: the move test fails with `invalidTradeInput` because asset/channel are currently immutable; the kind test fails because the current persistence path accepts a kind change when another buy covers the sale.

### Task 2: Implement Atomic Local Dual-Asset Rebuilds

**Files:**
- Modify: `Mistia/Shared/Persistence/InvestmentPersistence.swift:364-515`
- Test: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`

- [ ] **Step 1: Load the original trade and enforce only immutable kind**

In `saveTrade`, replace the relation-immutability guard with this ordering:

```swift
let draftID = draft.id
let storedTrade = try context.fetch(
    FetchDescriptor<InvestmentTrade>(
        predicate: #Predicate<InvestmentTrade> { trade in
            trade.id == draftID && trade.ownerUserID == ownerUserID
        }
    )
).first
if let storedTrade, storedTrade.kind != draft.kind {
    throw InvestmentPersistenceError.invalidTradeInput
}
let originalWalletIDs = Set([
    storedTrade?.fundingWalletID,
    storedTrade?.capitalReturnWalletID
].compactMap { $0 })

let targetAsset = try fetchAsset(id: draft.assetID, ownerUserID: ownerUserID, context: context)
guard let targetAsset,
      targetAsset.deletedAt == nil,
      !targetAsset.isArchived,
      targetAsset.channelID == draft.channelID else {
    throw InvestmentPersistenceError.missingAsset
}

var originalAsset: InvestmentAsset?
if let storedTrade, storedTrade.assetID != targetAsset.id {
    originalAsset = try fetchAsset(
        id: storedTrade.assetID,
        ownerUserID: ownerUserID,
        context: context
    )
    guard originalAsset != nil else {
        throw InvestmentPersistenceError.missingAsset
    }
}
try validateTradeSource(draft: draft, asset: targetAsset)
```

- [ ] **Step 2: Preflight both affected accounting histories before mutating models**

Replace the current `existingTrades`/single-calculation block with:

```swift
let targetTrades = try activeTrades(
    assetID: targetAsset.id,
    ownerUserID: ownerUserID,
    context: context
)
let targetTradesWithoutEditedTrade = targetTrades.filter { $0.id != draft.id }
let targetCalculations = try InvestmentAccountingEngine.calculationMap(
    trades: targetTradesWithoutEditedTrade.map(InvestmentTradeInput.init) + [draft.accountingInput]
)

let originalRemainingTrades: [InvestmentTrade]
let originalCalculations: [UUID: InvestmentTradeCalculation]
if let originalAsset {
    originalRemainingTrades = try activeTrades(
        assetID: originalAsset.id,
        ownerUserID: ownerUserID,
        context: context
    ).filter { $0.id != draft.id }
    originalCalculations = try InvestmentAccountingEngine.calculationMap(
        trades: originalRemainingTrades.map(InvestmentTradeInput.init)
    )
} else {
    originalRemainingTrades = []
    originalCalculations = [:]
}
```

Pass `storedTrade`, not a target-asset lookup, to funding validation:

```swift
try validateFundingCapacity(
    draft: draft,
    fundingWallet: fundingWallet,
    fundingAmountMinor: fundingAmountMinor,
    excludingTrade: storedTrade,
    allWallets: wallets,
    context: context
)
```

Keep this validation before `apply(draft:to:)`.

- [ ] **Step 3: Update the existing model and reconcile each affected asset once**

Use the stored model when editing:

```swift
let trade = storedTrade ?? InvestmentTrade(
    id: draft.id,
    ownerUserID: ownerUserID,
    channelID: draft.channelID,
    assetID: draft.assetID,
    kind: draft.kind,
    quantity: draft.quantity,
    grossAmountMinor: draft.grossAmountMinor,
    currencyCode: draft.currencyCode,
    accountingGrossAmountMinor: draft.accountingGrossAmountMinor,
    accountingCurrencyCode: draft.accountingCurrencyCode,
    occurredAt: draft.occurredAt,
    createdAt: draft.createdAt,
    updatedAt: now
)
if storedTrade == nil {
    context.insert(trade)
}
```

After applying the draft and rate snapshots, replace the single `refreshedTrades` loop with:

```swift
var touchedWalletIDs = originalWalletIDs
touchedWalletIDs.insert(systemWallet.id)
var result = InvestmentPersistenceResult(
    walletIDs: touchedWalletIDs,
    tradeIDs: [trade.id]
)
var rebuilds: [(
    asset: InvestmentAsset,
    trades: [InvestmentTrade],
    calculations: [UUID: InvestmentTradeCalculation]
)] = []
if let originalAsset {
    rebuilds.append((originalAsset, originalRemainingTrades, originalCalculations))
}
rebuilds.append((
    targetAsset,
    targetTradesWithoutEditedTrade + [trade],
    targetCalculations
))

let reconciledWallets = walletsByID.merging([systemWallet.id: systemWallet]) { current, _ in current }
for rebuild in rebuilds {
    for rebuiltTrade in rebuild.trades where rebuiltTrade.deletedAt == nil {
        guard let calculation = rebuild.calculations[rebuiltTrade.id] else { continue }
        rebuiltTrade.releasedCostBasisMinor = calculation.releasedCostBasisMinor
        rebuiltTrade.realizedProfitLossMinor = calculation.realizedProfitLossMinor
        rebuiltTrade.positionQuantityAfter = calculation.positionQuantityAfter
        rebuiltTrade.positionCostBasisAfterMinor = calculation.positionCostBasisAfterMinor
        if rebuiltTrade.id != trade.id {
            rebuiltTrade.updatedAt = now
        }
        try reconcileLedgerLegs(
            ownerUserID: ownerUserID,
            trade: rebuiltTrade,
            assetName: rebuild.asset.name,
            systemWallet: systemWallet,
            walletsByID: reconciledWallets,
            now: now,
            context: context,
            result: &result
        )
        result.tradeIDs.insert(rebuiltTrade.id)
    }
}

try context.save()
return result
```

This produces one rebuild when the asset is unchanged and exactly two when it changes.

- [ ] **Step 4: Run the focused persistence tests**

```bash
swift test --filter InvestmentPersistenceTests/testEditingBuyMovesItBetweenAssetsAndWalletsAndRebuildsBothHistories
swift test --filter InvestmentPersistenceTests/testEditingExistingTradeCannotChangeBuyIntoSell
swift test --filter InvestmentPersistenceTests/testEditingBuyWithInsufficientNewWalletLeavesOriginalStateUnchanged
swift test --filter InvestmentPersistenceTests/testEditingBuyWithinSameAssetReusesOneDerivedLedgerAndPosting
swift test --filter InvestmentPersistenceTests
```

Expected: all commands pass. The moved trade keeps its ID and buy kind, the old history ends at quantity `1`/capital `50`, the new history ends at quantity `4`/capital `200`, and wallet balances are `950` and `800`.

- [ ] **Step 5: Commit the local persistence behavior**

```bash
git add Mistia/Shared/Persistence/InvestmentPersistence.swift \
  Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift
git commit -m "feat: rebuild assets when editing investment buys"
```

### Task 3: Enable Every Approved Buy Field in the Editor

**Files:**
- Modify: `Mistia/Features/Investment/InvestmentHubView.swift:1209-1220,1285-1338`

- [ ] **Step 1: Enable asset editing only for existing buys**

Change the asset picker modifier from:

```swift
.disabled(trade != nil)
```

to:

```swift
.disabled(trade?.kind == .sell)
```

Leave the Buy / Sell picker disabled for every existing trade:

```swift
.disabled(trade != nil)
```

Quantity, total order amount, date, note, and wallet remain enabled by their existing controls.

- [ ] **Step 2: Refresh currency snapshots only when the asset changes the currency pair**

In `save()`, replace unconditional reuse of the existing exchange-rate metadata with:

```swift
let preservesExistingCurrencyPair = trade.map {
    MistiaCurrencyLogic.normalizedCode($0.currencyCode) == sourceCode
        && MistiaCurrencyLogic.normalizedCode($0.accountingCurrencyCode) == accountingCode
} ?? false
let exchangeRateDecimalString = preservesExistingCurrencyPair
    ? trade?.exchangeRateDecimalString
    : rateSnapshot(from: currency, to: accountingCurrencyCode, rates: rates)
let exchangeRateProvider = preservesExistingCurrencyPair
    ? trade?.exchangeRateProvider
    : rateProvider(from: currency, to: accountingCurrencyCode, rates: rates)
let exchangeRateDate = preservesExistingCurrencyPair
    ? trade?.exchangeRateDate
    : rateDate(from: currency, to: accountingCurrencyCode, rates: rates)
```

Pass those three local values directly into `InvestmentTradeDraft`. This preserves the historical snapshot for same-currency edits and prevents a moved trade from reusing a rate that belonged to the old asset currency.

- [ ] **Step 3: Build the Swift package and iOS target**

```bash
swift test --filter InvestmentPersistenceTests
xcodebuild \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: persistence tests pass and Xcode prints `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit the editor behavior**

```bash
git add Mistia/Features/Investment/InvestmentHubView.swift
git commit -m "feat: make investment buy details editable"
```

### Task 4: Add Supabase RPC Regressions

**Files:**
- Modify: `supabase/tests/database/investment_domain.sql`

- [ ] **Step 1: Expand the test fixture with a second funding wallet, channel, and asset**

Add wallets `30000000-0000-4000-8000-000000000103` with opening balance `1000` and `30000000-0000-4000-8000-000000000104` with opening balance `50`. Add channel `30000000-0000-4000-8000-000000000202` and asset `30000000-0000-4000-8000-000000000302`, owned by the existing investment owner and using JPY.

Use these exact fixture values:

```sql
('30000000-0000-4000-8000-000000000103',
 '30000000-0000-4000-8000-000000000001',
 'Second funding', 'bank', 'building.columns.fill', '#333333', 'JPY', 1000),
('30000000-0000-4000-8000-000000000104',
 '30000000-0000-4000-8000-000000000001',
 'Low balance', 'cash', 'banknote.fill', '#444444', 'JPY', 50)
```

```sql
('30000000-0000-4000-8000-000000000202',
 '30000000-0000-4000-8000-000000000001',
 'Second shop', 'shippingbox.fill', '#7A5AFF')
```

```sql
('30000000-0000-4000-8000-000000000302',
 '30000000-0000-4000-8000-000000000001',
 '30000000-0000-4000-8000-000000000202',
 'Card B', 'JPY')
```

- [ ] **Step 2: Add an RPC test that moves one buy and edits all approved fields**

After the existing oversell assertion and before family-permission tests, create trade `...0404` on asset A for quantity `2`, total `80`, wallet `...0101`, then call `mutate_investment_trade` again with the same ID and these corrected values:

```sql
jsonb_build_object(
    'id', '30000000-0000-4000-8000-000000000404',
    'user_id', '30000000-0000-4000-8000-000000000001',
    'channel_id', '30000000-0000-4000-8000-000000000202',
    'asset_id', '30000000-0000-4000-8000-000000000302',
    'kind_raw_value', 'buy',
    'quantity_decimal_string', '4',
    'gross_amount_minor', 200,
    'currency_code', 'JPY',
    'accounting_gross_amount_minor', 200,
    'accounting_currency_code', 'JPY',
    'funding_wallet_id', '30000000-0000-4000-8000-000000000103',
    'note', 'Corrected buy',
    'occurred_at', '2026-08-09T00:00:04Z',
    'created_at', '2026-08-09T00:00:03Z',
    'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
)
```

Assert with pgTAP that:

```sql
select is((select asset_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
          '30000000-0000-4000-8000-000000000302'::uuid,
          'edited buy moves to the selected asset');
select is((select kind_raw_value from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
          'buy', 'edited trade remains a buy');
select is((select position_quantity_after_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
          4::numeric, 'new asset position uses edited quantity');
select is((select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
          200::bigint, 'new asset capital uses edited total amount');
select is((select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000101'),
          880::bigint, 'old wallet is restored');
select is((select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000103'),
          800::bigint, 'new wallet is debited by the edited total');
select is((select asset_id from public.investment_wallet_postings where trade_id = '30000000-0000-4000-8000-000000000404' and deleted_at is null),
          '30000000-0000-4000-8000-000000000302'::uuid,
          'derived posting follows the new asset');
```

- [ ] **Step 3: Add immutable-kind, stale-version, and rollback assertions**

Add these exact assertions:

```sql
select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'kind_raw_value', 'sell',
                'funding_wallet_id', null,
                'capital_return_wallet_id', '30000000-0000-4000-8000-000000000102'
            )
            from public.investment_trades trade
            where trade.id = '30000000-0000-4000-8000-000000000404'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Investment trade kind is immutable',
    'an existing buy cannot become a sell'
);

select is(
    (
        select count(*)::bigint
        from public.mutate_investment_trade(
            (
                select to_jsonb(trade) || jsonb_build_object('note', 'Stale overwrite')
                from public.investment_trades trade
                where trade.id = '30000000-0000-4000-8000-000000000404'
            ),
            (
                select sync_version - 1
                from public.investment_trades
                where id = '30000000-0000-4000-8000-000000000404'
            ),
            false
        )
    ),
    0::bigint,
    'a stale edit returns no trade row'
);
select is(
    (select note from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    'Corrected buy',
    'a stale edit does not overwrite current fields'
);

select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'gross_amount_minor', 500,
                'accounting_gross_amount_minor', 500,
                'funding_wallet_id', '30000000-0000-4000-8000-000000000104'
            )
            from public.investment_trades trade
            where trade.id = '30000000-0000-4000-8000-000000000404'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Insufficient wallet balance',
    'an underfunded edit rolls back the RPC'
);
select is(
    (select gross_amount_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    200::bigint,
    'failed edit leaves the stored amount unchanged'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000103'),
    800::bigint,
    'failed edit leaves the active funding wallet unchanged'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000104'),
    50::bigint,
    'failed edit leaves the rejected wallet unchanged'
);
```

- [ ] **Step 4: Run the pgTAP file before adding the migration**

```bash
supabase test db supabase/tests/database/investment_domain.sql --local
```

Expected: the new move test fails with `Investment trade asset and channel are immutable`. Existing assertions continue to pass up to that point.

### Task 5: Replace the Cloud Mutation RPC

**Files:**
- Create: `supabase/migrations/20260810111705_allow_investment_buy_activity_edits.sql`
- Test: `supabase/tests/database/investment_domain.sql`

- [ ] **Step 1: Create a forward-only replacement migration**

Use this complete migration body:

```sql
create or replace function public.mutate_investment_trade(
    p_trade jsonb,
    p_expected_version bigint default null,
    p_force boolean default false
)
returns setof public.investment_trades
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    incoming public.investment_trades%rowtype;
    existing public.investment_trades%rowtype;
    asset_row public.investment_assets%rowtype;
    wallet_row public.ledger_wallets%rowtype;
    system_wallet public.ledger_wallets%rowtype;
    now_value timestamptz := timezone('utc'::text, now());
    required_scope text;
    original_asset_id uuid;
    first_asset_id uuid;
    second_asset_id uuid;
begin
    if actor_id is null then raise exception 'Not authenticated'; end if;
    incoming := jsonb_populate_record(null::public.investment_trades, p_trade);
    if incoming.id is null or incoming.user_id is null or incoming.asset_id is null or incoming.channel_id is null then
        raise exception 'Incomplete investment trade';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('investment-trade:' || incoming.id::text, 0));
    select * into existing from public.investment_trades where id = incoming.id;
    original_asset_id := coalesce(existing.asset_id, incoming.asset_id);
    if original_asset_id::text <= incoming.asset_id::text then
        first_asset_id := original_asset_id;
        second_asset_id := incoming.asset_id;
    else
        first_asset_id := incoming.asset_id;
        second_asset_id := original_asset_id;
    end if;
    perform pg_advisory_xact_lock(
        hashtextextended(lower(incoming.user_id::text || ':' || first_asset_id::text), 0)
    );
    if second_asset_id <> first_asset_id then
        perform pg_advisory_xact_lock(
            hashtextextended(lower(incoming.user_id::text || ':' || second_asset_id::text), 0)
        );
    end if;
    select * into existing from public.investment_trades where id = incoming.id for update;
    original_asset_id := coalesce(existing.asset_id, incoming.asset_id);

    required_scope := case when existing.id is null then 'create' else 'edit' end;
    if not public.has_investment_permission(incoming.user_id, required_scope) then
        raise exception 'Investment % permission is required', required_scope;
    end if;
    if existing.id is not null and existing.user_id <> incoming.user_id then
        raise exception 'Investment owner is immutable';
    end if;
    if existing.id is not null and existing.kind_raw_value <> incoming.kind_raw_value then
        raise exception 'Investment trade kind is immutable';
    end if;
    if existing.id is not null and p_expected_version is not null
       and existing.sync_version <> p_expected_version and not p_force then
        return;
    end if;
    if existing.id is null and p_expected_version is not null and p_expected_version <> 0 and not p_force then
        return;
    end if;

    select * into asset_row from public.investment_assets
    where id = incoming.asset_id
      and user_id = incoming.user_id
      and channel_id = incoming.channel_id
      and deleted_at is null
      and is_archived = false
      and exists (
          select 1 from public.investment_channels channel
          where channel.id = incoming.channel_id
            and channel.user_id = incoming.user_id
            and channel.deleted_at is null
            and channel.is_archived = false
      );
    if asset_row.id is null then raise exception 'Investment asset/channel mismatch'; end if;

    select * into system_wallet
    from public.ledger_wallets
    where id = public.investment_system_wallet_id(incoming.user_id)
      and user_id = incoming.user_id
      and system_purpose_raw_value = 'investmentProfit'
      and deleted_at is null;
    if system_wallet.id is null then raise exception 'System Investment Wallet not found'; end if;

    if incoming.kind_raw_value not in ('buy', 'sell')
       or incoming.quantity_decimal_string::numeric <= 0
       or incoming.gross_amount_minor <= 0
       or incoming.accounting_gross_amount_minor <= 0
       or incoming.occurred_at is null
       or upper(incoming.currency_code) <> upper(asset_row.currency_code)
       or upper(incoming.accounting_currency_code) <> upper(system_wallet.currency_code)
       or (
            upper(incoming.currency_code) = upper(incoming.accounting_currency_code)
            and incoming.gross_amount_minor <> incoming.accounting_gross_amount_minor
       )
       or (
            upper(incoming.currency_code) <> upper(incoming.accounting_currency_code)
            and (
                coalesce(incoming.exchange_rate_decimal_string, '') = ''
                or incoming.exchange_rate_decimal_string::numeric <= 0
                or round(
                    incoming.gross_amount_minor::numeric
                    * incoming.exchange_rate_decimal_string::numeric
                )::bigint <> incoming.accounting_gross_amount_minor
            )
       ) then
        raise exception 'Invalid investment trade input';
    end if;

    if incoming.kind_raw_value = 'buy' then
        if incoming.funding_wallet_id is null or incoming.capital_return_wallet_id is not null then
            raise exception 'A buy requires one funding wallet';
        end if;
        select * into wallet_row from public.ledger_wallets
        where id = incoming.funding_wallet_id
          and user_id = incoming.user_id
          and deleted_at is null
          and is_archived = false;
    else
        if incoming.capital_return_wallet_id is null or incoming.funding_wallet_id is not null then
            raise exception 'A sale requires one capital return wallet';
        end if;
        select * into wallet_row from public.ledger_wallets
        where id = incoming.capital_return_wallet_id
          and user_id = incoming.user_id
          and deleted_at is null
          and is_archived = false
          and system_purpose_raw_value is null
          and kind_raw_value <> 'creditCard';
    end if;
    if wallet_row.id is null then raise exception 'Investment wallet selection is invalid'; end if;
    if not public.can_operate_wallet(wallet_row.id) then raise exception 'wallet.use is required'; end if;

    insert into public.investment_trades (
        id, user_id, channel_id, asset_id, kind_raw_value, quantity_decimal_string,
        gross_amount_minor, currency_code, accounting_gross_amount_minor,
        accounting_currency_code, exchange_rate_decimal_string,
        exchange_rate_provider, exchange_rate_date, funding_wallet_id, capital_return_wallet_id,
        funding_to_accounting_rate_decimal_string, accounting_to_capital_return_rate_decimal_string,
        note, occurred_at, created_at, updated_at, deleted_at, sync_version,
        last_modified_by_device_id
    ) values (
        incoming.id, incoming.user_id, incoming.channel_id, incoming.asset_id,
        incoming.kind_raw_value, incoming.quantity_decimal_string, incoming.gross_amount_minor,
        upper(incoming.currency_code), incoming.accounting_gross_amount_minor,
        upper(incoming.accounting_currency_code),
        incoming.exchange_rate_decimal_string, incoming.exchange_rate_provider,
        incoming.exchange_rate_date, incoming.funding_wallet_id, incoming.capital_return_wallet_id,
        incoming.funding_to_accounting_rate_decimal_string,
        incoming.accounting_to_capital_return_rate_decimal_string,
        nullif(btrim(incoming.note), ''), incoming.occurred_at,
        coalesce(incoming.created_at, now_value), now_value, null,
        case when existing.id is null
            then 1
            else greatest(existing.sync_version + 1, coalesce(incoming.sync_version, 0))
        end,
        incoming.last_modified_by_device_id
    ) on conflict (id) do update set
        channel_id = excluded.channel_id,
        asset_id = excluded.asset_id,
        kind_raw_value = excluded.kind_raw_value,
        quantity_decimal_string = excluded.quantity_decimal_string,
        gross_amount_minor = excluded.gross_amount_minor,
        currency_code = excluded.currency_code,
        accounting_gross_amount_minor = excluded.accounting_gross_amount_minor,
        accounting_currency_code = excluded.accounting_currency_code,
        exchange_rate_decimal_string = excluded.exchange_rate_decimal_string,
        exchange_rate_provider = excluded.exchange_rate_provider,
        exchange_rate_date = excluded.exchange_rate_date,
        funding_wallet_id = excluded.funding_wallet_id,
        capital_return_wallet_id = excluded.capital_return_wallet_id,
        funding_to_accounting_rate_decimal_string = excluded.funding_to_accounting_rate_decimal_string,
        accounting_to_capital_return_rate_decimal_string = excluded.accounting_to_capital_return_rate_decimal_string,
        note = excluded.note,
        occurred_at = excluded.occurred_at,
        updated_at = now_value,
        deleted_at = null,
        sync_version = excluded.sync_version,
        last_modified_by_device_id = excluded.last_modified_by_device_id;

    if existing.id is not null and original_asset_id <> incoming.asset_id then
        perform public.investment_rebuild_asset(
            incoming.user_id,
            original_asset_id,
            actor_id,
            incoming.last_modified_by_device_id,
            now_value
        );
    end if;
    perform public.investment_rebuild_asset(
        incoming.user_id,
        incoming.asset_id,
        actor_id,
        incoming.last_modified_by_device_id,
        now_value
    );

    update public.investment_wallet_postings
    set asset_id = incoming.asset_id,
        updated_at = now_value,
        sync_version = sync_version + 1,
        last_modified_by_device_id = incoming.last_modified_by_device_id
    where user_id = incoming.user_id
      and trade_id = incoming.id
      and asset_id is distinct from incoming.asset_id;

    return query
    select * from public.investment_trades
    where user_id = incoming.user_id
      and deleted_at is null
      and asset_id in (original_asset_id, incoming.asset_id)
    order by occurred_at, created_at, id;
end;
$$;

revoke execute on function public.mutate_investment_trade(jsonb, bigint, boolean) from public, anon;
grant execute on function public.mutate_investment_trade(jsonb, bigint, boolean) to authenticated;
```

- [ ] **Step 2: Rebuild the local database and run pgTAP**

```bash
supabase db reset --local
supabase test db supabase/tests/database/investment_domain.sql --local
supabase test db supabase/tests/database --local
```

Expected: the focused investment file and the complete database suite pass. The move updates both positions and wallets; kind changes, stale versions, and insufficient-funds edits do not partially mutate data.

- [ ] **Step 3: Commit the tested cloud behavior**

```bash
git add supabase/migrations/20260810111705_allow_investment_buy_activity_edits.sql \
  supabase/tests/database/investment_domain.sql
git commit -m "feat: sync editable investment buys"
```

### Task 6: Full Verification, Live Migration, and Interaction Check

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run all local automated checks**

```bash
swift test --filter InvestmentPersistenceTests
swift test
supabase test db supabase/tests/database --local
git diff --check
```

Expected: all Swift and pgTAP tests pass with zero failures, and `git diff --check` prints no output.

- [ ] **Step 2: Build the unsigned iOS app**

```bash
xcodebuild \
  -project Mistia.xcodeproj \
  -scheme Mistia \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify and apply the linked Supabase migration**

```bash
supabase migration list --linked
supabase db push --linked --dry-run
supabase db push --linked
supabase migration list --linked
```

Expected: the dry run lists only `20260810111705_allow_investment_buy_activity_edits.sql`; the push succeeds; the final list shows local and remote migration `20260810111705` aligned. Do not run destructive pgTAP fixtures against the linked production database.

- [ ] **Step 4: Verify the editor on an iPhone-sized simulator when available**

Check this exact flow:

```text
1. Open an existing Buy activity.
2. Confirm Buy/Sell is disabled and remains Buy.
3. Change asset, quantity, total order amount, date, funding wallet, and note.
4. Save and reopen the activity; every corrected field persists.
5. Confirm the old asset no longer includes the moved quantity/capital.
6. Confirm the new asset contains the corrected quantity/capital.
7. Confirm the old wallet is restored and the new wallet is charged the corrected total.
8. Attempt an edit with an underfunded wallet and confirm no field or balance changes.
```

Expected: all editable fields persist together, the kind never changes, and failed edits leave the previous state visible.

- [ ] **Step 5: Inspect final repository state**

```bash
git status --short
git log --oneline -6
```

Expected: the worktree is clean and the implementation commits are present on `develop`.
