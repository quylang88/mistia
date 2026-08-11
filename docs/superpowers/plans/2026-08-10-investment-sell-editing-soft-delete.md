# Investment Sell Editing and Soft Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit every business field of an existing investment sell and soft-delete existing investment buys or sells from their editor, while preserving immutable Buy/Sell kind and consistent local/cloud accounting.

**Architecture:** Reuse `InvestmentPersistenceService.saveTrade` and `deleteTrade`, which already own local dual-asset rebuilds and soft deletion, and reuse the existing Supabase `mutate_investment_trade` and `delete_investment_trade` RPCs. Extend only the trade editor: allow the existing asset picker for sells, pass a successful delete callback back to `InvestmentHubView`, and use the shared `MistiaDestructiveActionSection` for native confirmation. Lock the cloud behavior in pgTAP rather than adding a redundant migration.

**Tech Stack:** SwiftUI, SwiftData, XCTest, Swift Package Manager, Apple String Catalog, Supabase PostgreSQL/pgTAP, existing custom sync outbox.

---

## File Structure

- Modify `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`: regression coverage for moving sells across assets/wallets, immutable sell kind, insufficient target position rollback, and soft deletion of buys/sells.
- Modify `supabase/tests/database/investment_domain.sql`: pgTAP contract coverage for sell move, immutable kind, oversell rollback, and the existing trade-delete RPC.
- Modify `Mistia/Localizable.xcstrings`: localized title, description, and native-confirmation copy for the investment-trade delete section.
- Modify generated `Mistia/Shared/CoreLogic/L10n.generated.swift`: regenerated output only; never hand-edit it.
- Modify `Mistia/Features/Investment/InvestmentHubView.swift`: enable the asset picker for existing sells, add the shared destructive section to the editor, wire a successful soft-delete callback, and remove the card context-menu delete bypass.

No SwiftData model, sync payload, table, RLS policy, or Supabase migration changes are required. The current `mutate_investment_trade` already permits an asset move without a kind change, and `delete_investment_trade` already performs a permission-checked soft delete with one asset rebuild.

### Task 1: Lock Local Sell-Edit and Soft-Delete Semantics

**Files:**
- Modify: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift:530-866`
- Modify: `Mistia/Shared/Persistence/InvestmentPersistence.swift` only if a new regression exposes a persistence defect.

- [ ] **Step 1: Write the sell move, immutable kind, and rollback regression tests**

Add these methods before `testEditingExistingTradeCannotChangeBuyIntoSell`. Add the small `saveTrade` helper overload shown below so the tests can create rows in either asset without duplicating draft construction.

```swift
func testEditingExistingSellMovesItBetweenAssetsAndCapitalWalletsAndRebuildsBothHistories() throws {
    let fixture = try makeFixture()
    let secondCapitalWallet = LedgerWallet(
        name: "Second capital", kind: .bank,
        iconSymbolName: "building.columns.fill", iconColorHex: "#333333",
        currencyCode: "JPY", openingBalanceMinor: 0
    )
    fixture.context.insert(secondCapitalWallet)
    let secondChannel = try InvestmentPersistenceService.createChannel(
        ownerUserID: fixture.ownerID, name: "Second shop",
        iconSymbolName: "shippingbox.fill", iconColorHex: "#9A67FF",
        primaryCurrencyCode: "JPY", context: fixture.context
    ).channel
    let secondAsset = try InvestmentPersistenceService.createAsset(
        ownerUserID: fixture.ownerID, channelID: secondChannel.id,
        name: "Item B", currencyCode: "JPY", context: fixture.context
    )

    let originalBuy = try saveTrade(
        fixture: fixture, kind: .buy, quantity: 2, gross: 100,
        fundingWalletID: fixture.fundingWallet.id, occurredAt: fixture.start
    )
    _ = try saveTrade(
        fixture: fixture, asset: secondAsset, channel: secondChannel,
        kind: .buy, quantity: 4, gross: 160,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )
    let originalSell = try saveTrade(
        fixture: fixture, kind: .sell, quantity: 1, gross: 150,
        capitalWalletID: fixture.capitalWallet.id,
        occurredAt: fixture.start.addingTimeInterval(2)
    )
    let correctedDate = fixture.start.addingTimeInterval(3)

    let result = try InvestmentPersistenceService.saveTrade(
        ownerUserID: fixture.ownerID,
        draft: InvestmentTradeDraft(
            id: originalSell.id, channelID: secondChannel.id, assetID: secondAsset.id,
            kind: .sell, quantity: 3, grossAmountMinor: 260,
            currencyCode: "JPY", accountingGrossAmountMinor: 260,
            accountingCurrencyCode: "JPY",
            capitalReturnWalletID: secondCapitalWallet.id,
            note: "Corrected sale", occurredAt: correctedDate,
            createdAt: originalSell.createdAt
        ),
        rates: [], now: correctedDate.addingTimeInterval(1), context: fixture.context
    )

    let storedSell = try XCTUnwrap(fetchTrade(id: originalSell.id, fixture))
    XCTAssertEqual(storedSell.id, originalSell.id)
    XCTAssertEqual(storedSell.kind, .sell)
    XCTAssertEqual(storedSell.channelID, secondChannel.id)
    XCTAssertEqual(storedSell.assetID, secondAsset.id)
    XCTAssertEqual(storedSell.quantity, 3)
    XCTAssertEqual(storedSell.grossAmountMinor, 260)
    XCTAssertEqual(storedSell.occurredAt, correctedDate)
    XCTAssertEqual(storedSell.capitalReturnWalletID, secondCapitalWallet.id)
    XCTAssertEqual(storedSell.note, "Corrected sale")
    XCTAssertEqual(storedSell.releasedCostBasisMinor, 120)
    XCTAssertEqual(storedSell.realizedProfitLossMinor, 140)
    XCTAssertEqual(storedSell.positionQuantityAfter, 1)
    XCTAssertEqual(storedSell.positionCostBasisAfterMinor, 40)

    let rebuiltOriginalBuy = try XCTUnwrap(fetchTrade(id: originalBuy.id, fixture))
    XCTAssertEqual(rebuiltOriginalBuy.positionQuantityAfter, 2)
    XCTAssertEqual(rebuiltOriginalBuy.positionCostBasisAfterMinor, 100)
    XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 0)
    XCTAssertEqual(try balance(secondCapitalWallet, fixture), 120)
    XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 140)
    XCTAssertTrue(result.walletIDs.contains(fixture.capitalWallet.id))
    XCTAssertTrue(result.walletIDs.contains(secondCapitalWallet.id))

    let activePostings = try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
        .filter { $0.tradeID == originalSell.id && $0.deletedAt == nil }
    XCTAssertEqual(Set(activePostings.map(\.assetID)), [secondAsset.id])
    XCTAssertTrue(activePostings.contains { $0.walletID == secondCapitalWallet.id })
}

func testEditingExistingSellToInsufficientTargetPositionLeavesOriginalStateUnchanged() throws {
    let fixture = try makeFixture()
    let secondChannel = try InvestmentPersistenceService.createChannel(
        ownerUserID: fixture.ownerID, name: "Second shop",
        iconSymbolName: "shippingbox.fill", iconColorHex: "#9A67FF",
        primaryCurrencyCode: "JPY", context: fixture.context
    ).channel
    let secondAsset = try InvestmentPersistenceService.createAsset(
        ownerUserID: fixture.ownerID, channelID: secondChannel.id,
        name: "Item B", currencyCode: "JPY", context: fixture.context
    )
    _ = try saveTrade(
        fixture: fixture, kind: .buy, quantity: 2, gross: 100,
        fundingWalletID: fixture.fundingWallet.id, occurredAt: fixture.start
    )
    _ = try saveTrade(
        fixture: fixture, asset: secondAsset, channel: secondChannel,
        kind: .buy, quantity: 1, gross: 40,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )
    let originalSell = try saveTrade(
        fixture: fixture, kind: .sell, quantity: 1, gross: 150,
        capitalWalletID: fixture.capitalWallet.id,
        occurredAt: fixture.start.addingTimeInterval(2)
    )

    XCTAssertThrowsError(
        try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: originalSell.id, channelID: secondChannel.id, assetID: secondAsset.id,
                kind: .sell, quantity: 2, grossAmountMinor: 300,
                currencyCode: "JPY", accountingGrossAmountMinor: 300,
                accountingCurrencyCode: "JPY",
                capitalReturnWalletID: fixture.capitalWallet.id,
                occurredAt: fixture.start.addingTimeInterval(3),
                createdAt: originalSell.createdAt
            ),
            rates: [], context: fixture.context
        )
    ) { error in
        XCTAssertEqual(error as? InvestmentAccountingError, .insufficientPosition)
    }

    let storedSell = try XCTUnwrap(fetchTrade(id: originalSell.id, fixture))
    XCTAssertEqual(storedSell.assetID, fixture.asset.id)
    XCTAssertEqual(storedSell.channelID, fixture.channel.id)
    XCTAssertEqual(storedSell.quantity, 1)
    XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 50)
    XCTAssertEqual(try fetchTrade(id: originalSell.id, fixture)?.deletedAt, nil)
}

func testEditingExistingSellCannotChangeSellIntoBuy() throws {
    let fixture = try makeFixture()
    _ = try saveTrade(
        fixture: fixture, kind: .buy, quantity: 2, gross: 100,
        fundingWalletID: fixture.fundingWallet.id, occurredAt: fixture.start
    )
    let sell = try saveTrade(
        fixture: fixture, kind: .sell, quantity: 1, gross: 150,
        capitalWalletID: fixture.capitalWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )

    XCTAssertThrowsError(
        try InvestmentPersistenceService.saveTrade(
            ownerUserID: fixture.ownerID,
            draft: InvestmentTradeDraft(
                id: sell.id, channelID: fixture.channel.id, assetID: fixture.asset.id,
                kind: .buy, quantity: 1, grossAmountMinor: 100,
                currencyCode: "JPY", accountingGrossAmountMinor: 100,
                accountingCurrencyCode: "JPY", fundingWalletID: fixture.fundingWallet.id,
                occurredAt: fixture.start.addingTimeInterval(2), createdAt: sell.createdAt
            ),
            rates: [], context: fixture.context
        )
    ) { error in
        XCTAssertEqual(error as? InvestmentPersistenceError, .invalidTradeInput)
    }
    XCTAssertEqual(try fetchTrade(id: sell.id, fixture)?.kind, .sell)
}
```

Change the existing helper signature and draft values to accept an optional target asset/channel:

```swift
private func saveTrade(
    fixture: Fixture,
    asset: InvestmentAsset? = nil,
    channel: InvestmentChannel? = nil,
    kind: InvestmentTradeKind,
    quantity: Decimal,
    gross: Int64,
    fundingWalletID: UUID? = nil,
    capitalWalletID: UUID? = nil,
    occurredAt: Date,
    rates: [MistiaExchangeRate] = []
) throws -> InvestmentTradeDraft {
    let resolvedAsset = asset ?? fixture.asset
    let resolvedChannel = channel ?? fixture.channel
    let draft = InvestmentTradeDraft(
        channelID: resolvedChannel.id,
        assetID: resolvedAsset.id,
        kind: kind,
        quantity: quantity,
        grossAmountMinor: gross,
        currencyCode: resolvedAsset.currencyCode,
        accountingGrossAmountMinor: gross,
        accountingCurrencyCode: "JPY",
        fundingWalletID: fundingWalletID,
        capitalReturnWalletID: capitalWalletID,
        occurredAt: occurredAt,
        createdAt: occurredAt
    )
    _ = try InvestmentPersistenceService.saveTrade(
        ownerUserID: fixture.ownerID, draft: draft, rates: rates, context: fixture.context
    )
    return draft
}
```

- [ ] **Step 2: Run the new sell-edit tests to characterize the existing shared persistence boundary**

Run:

```bash
swift test --filter InvestmentPersistenceTests/testEditingExistingSell
```

Expected: both move and rollback tests pass. The shared local persistence path added for editable buys already handles either immutable kind; a failure identifies the exact persistence defect to fix before UI work.

- [ ] **Step 3: Write the buy/sell soft-delete regressions**

Add these methods after the sell editing tests:

```swift
func testDeletingBuySoftDeletesTradeAndRestoresFundingWallet() throws {
    let fixture = try makeFixture()
    let buy = try saveTrade(
        fixture: fixture, kind: .buy, quantity: 2, gross: 100,
        fundingWalletID: fixture.fundingWallet.id, occurredAt: fixture.start
    )

    let result = try InvestmentPersistenceService.deleteTrade(
        ownerUserID: fixture.ownerID, tradeID: buy.id,
        now: fixture.start.addingTimeInterval(1), context: fixture.context
    )

    let storedBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
    XCTAssertNotNil(storedBuy.deletedAt)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 1_000)
    XCTAssertEqual(result.deletedTradeIDs, [buy.id])
    XCTAssertTrue(
        try fixture.context.fetch(FetchDescriptor<LedgerTransaction>())
            .filter { $0.financialDomain == .investment }
            .allSatisfy { $0.deletedAt != nil }
    )
    XCTAssertTrue(
        try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .filter { $0.tradeID == buy.id }
            .allSatisfy { $0.deletedAt != nil }
    )
}

func testDeletingSellSoftDeletesTradeAndRestoresPositionCapitalAndProfit() throws {
    let fixture = try makeFixture()
    let buy = try saveTrade(
        fixture: fixture, kind: .buy, quantity: 2, gross: 100,
        fundingWalletID: fixture.fundingWallet.id, occurredAt: fixture.start
    )
    let sell = try saveTrade(
        fixture: fixture, kind: .sell, quantity: 1, gross: 150,
        capitalWalletID: fixture.capitalWallet.id,
        occurredAt: fixture.start.addingTimeInterval(1)
    )

    let result = try InvestmentPersistenceService.deleteTrade(
        ownerUserID: fixture.ownerID, tradeID: sell.id,
        now: fixture.start.addingTimeInterval(2), context: fixture.context
    )

    let storedBuy = try XCTUnwrap(fetchTrade(id: buy.id, fixture))
    let storedSell = try XCTUnwrap(fetchTrade(id: sell.id, fixture))
    XCTAssertNotNil(storedSell.deletedAt)
    XCTAssertEqual(storedBuy.positionQuantityAfter, 2)
    XCTAssertEqual(storedBuy.positionCostBasisAfterMinor, 100)
    XCTAssertEqual(try balance(fixture.capitalWallet, fixture), 0)
    XCTAssertEqual(try balance(try XCTUnwrap(fetchSystemWallet(fixture)), fixture), 0)
    XCTAssertEqual(result.deletedTradeIDs, [sell.id])
    XCTAssertTrue(
        try fixture.context.fetch(FetchDescriptor<InvestmentWalletPosting>())
            .filter { $0.tradeID == sell.id }
            .allSatisfy { $0.deletedAt != nil }
    )
}
```

- [ ] **Step 4: Run the delete regressions to characterize the existing soft-delete boundary**

Run:

```bash
swift test --filter InvestmentPersistenceTests/testDeleting
```

Expected: both tests pass. If an assertion fails, repair only `InvestmentPersistenceService.deleteTrade` or the helper it exposes, rerun these tests, then run the complete persistence suite.

- [ ] **Step 5: Run the complete local investment persistence suite**

Run:

```bash
swift test --filter InvestmentPersistenceTests
```

Expected: all investment persistence tests pass with no new SwiftData validation or accounting failures.

- [ ] **Step 6: Commit the characterized local contract**

```bash
git add Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift
git commit -m "test: cover editable investment sells and deletes"
```

### Task 2: Lock the Existing Cloud RPC Contract with pgTAP

**Files:**
- Modify: `supabase/tests/database/investment_domain.sql:80-540`
- Modify: `supabase/migrations/*` only if pgTAP proves the deployed/local function violates the contract.

- [ ] **Step 1: Extend the pgTAP fixture with a second capital-return wallet**

Append this wallet to the existing ordinary-wallet `values` list:

```sql
(
    '30000000-0000-4000-8000-000000000105',
    '30000000-0000-4000-8000-000000000001',
    'Second capital return', 'bank', 'building.columns.fill', '#555555', 'JPY', 0
)
```

- [ ] **Step 2: Add a sell relation-move and kind-immutability regression**

After the existing editable-buy assertions and before switching to the family actor, create `...0406` as a buy of asset A (`quantity_decimal_string = '2'`, total `100`, wallet `...0101`, time `00:00:05Z`), then create sell `...0405` against asset A (`quantity '1'`, total `150`, capital return wallet `...0102`, time `00:00:06Z`). Update that same sell ID with:

```sql
jsonb_build_object(
    'id', '30000000-0000-4000-8000-000000000405',
    'user_id', '30000000-0000-4000-8000-000000000001',
    'channel_id', '30000000-0000-4000-8000-000000000202',
    'asset_id', '30000000-0000-4000-8000-000000000302',
    'kind_raw_value', 'sell',
    'quantity_decimal_string', '3',
    'gross_amount_minor', 260,
    'currency_code', 'JPY',
    'accounting_gross_amount_minor', 260,
    'accounting_currency_code', 'JPY',
    'capital_return_wallet_id', '30000000-0000-4000-8000-000000000105',
    'note', 'Corrected sale',
    'occurred_at', '2026-08-09T00:00:07Z',
    'created_at', '2026-08-09T00:00:06Z',
    'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
)
```

Assert that the saved sale keeps ID and `kind_raw_value = 'sell'`, uses channel/asset `...0202`/`...0302`, stores all corrected fields, leaves asset A at quantity `2` and cost `100`, leaves asset B at quantity `1` and cost `50`, preserves `...0102` at `120`, credits `...0105` with `150`, and associates every active posting for `...0405` with asset B.

Then call `mutate_investment_trade` for `...0405` with `kind_raw_value = 'buy'`, a funding wallet, and no capital-return wallet. Assert SQLSTATE `P0001` and message `Investment trade kind is immutable`.

- [ ] **Step 3: Add an oversell-move rollback regression**

Call `mutate_investment_trade` for `...0405` with its stored JSON plus `quantity_decimal_string = '5'` and gross/accounting total `500`. Assert SQLSTATE `P0001` and `Sale exceeds the quantity held`. Then assert the stored sale is still asset B, quantity `3`, total `260`, capital-return wallet `...0105`, and asset B's active position/cost remains `1`/`50`.

- [ ] **Step 4: Add soft-delete RPC regressions for the sell and buy**

Call the existing function rather than patching tables directly:

```sql
select lives_ok(
    $$
    select * from public.delete_investment_trade(
        '30000000-0000-4000-8000-000000000405',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
        '2026-08-09T00:00:08Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'sale soft delete succeeds through the trade RPC'
);
```

Assert `...0405.deleted_at is not null`, asset B is restored to quantity `4` and cost `200`, wallet `...0105` is restored to `0`, and its active postings are gone. Repeat the call for buy `...0404`; assert it has `deleted_at`, asset B has zero active trades, wallet `...0103` returns to `1000`, and active postings for the buy are gone.

- [ ] **Step 5: Run pgTAP before considering a migration**

Run:

```bash
supabase test db supabase/tests/database/investment_domain.sql --local
```

Expected: PASS. This is a characterization test for already-deployed RPC behavior; do not create a migration if it passes. If it fails, create a forward-only migration with `supabase migration new <descriptive_name>`, preserve RPC signature/security/grants, reset local DB, and rerun this command before proceeding.

- [ ] **Step 6: Commit the cloud contract test**

```bash
git add supabase/tests/database/investment_domain.sql
git commit -m "test: cover investment sell edits and soft deletes"
```

### Task 3: Add Localized Editor Delete UI and Wire It to Soft Delete

**Files:**
- Modify: `Mistia/Localizable.xcstrings:42391-42400`
- Modify generated: `Mistia/Shared/CoreLogic/L10n.generated.swift`
- Modify: `Mistia/Features/Investment/InvestmentHubView.swift:560-585, 530-540, 753-770, 1144-1358`
- Reference: `Mistia/Core/UI/MistiaArchiveSection.swift:1-48`

- [ ] **Step 1: Add String Catalog entries and regenerate `L10n`**

Add these exact dotted keys to `Mistia/Localizable.xcstrings` with `vi`, `en`, and `ja` localizations:

| Key | Vietnamese | English | Japanese |
| --- | --- | --- | --- |
| `investment.trade.deleteAction` | `Xóa giao dịch` | `Delete transaction` | `取引を削除` |
| `investment.trade.deleteDescription` | `Giao dịch đã xóa sẽ không còn hiển thị trong lịch sử đầu tư.` | `Deleted transactions no longer appear in investment history.` | `削除した取引は投資履歴に表示されなくなります。` |
| `investment.trade.deleteConfirmation` | `Giao dịch này sẽ bị xóa khỏi lịch sử đầu tư. Bạn có muốn tiếp tục?` | `This transaction will be removed from investment history. Do you want to continue?` | `この取引を投資履歴から削除します。続けますか？` |

Regenerate only through the existing script:

```bash
swift Scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift
```

- [ ] **Step 2: Make existing sell assets editable and remove the unconfirmed card-delete bypass**

In `InvestmentTradeEditorSheet`, remove the current asset-picker disable modifier:

```swift
.disabled(trade?.kind == .sell)
```

Keep the Buy/Sell segmented picker disabled for every existing trade:

```swift
.disabled(trade != nil)
```

In the activity-card `contextMenu`, remove the entire trade delete/request-permission menu. Tapping the card remains the way to open the detail editor; the only delete interaction will be the confirmed destructive section in that editor.

- [ ] **Step 3: Add a successful delete callback from the sheet to the hub**

Change the sheet declaration to accept a callback that returns whether deletion completed:

```swift
let onDelete: (InvestmentTrade) -> Bool
```

Pass it from `sheetView`:

```swift
onDelete: { trade in
    delete(trade)
}
```

Change the hub helper to preserve the current local persistence and sync behavior while reporting success to the editor:

```swift
@discardableResult
private func delete(_ trade: InvestmentTrade) -> Bool {
    guard let ownerUserID else { return false }
    do {
        _ = try InvestmentPersistenceService.deleteTrade(
            ownerUserID: ownerUserID,
            tradeID: trade.id,
            context: modelContext
        )
        sessionStore.recordDelete(
            entity: .investmentTrade,
            recordID: trade.id,
            modifiedAt: trade.updatedAt,
            subjectUserIDOverride: ownerUserID
        )
        return true
    } catch {
        errorMessage = error.localizedDescription
        return false
    }
}
```

- [ ] **Step 4: Put the shared native destructive section at the end of the existing trade form**

After the wallet `Section` and before the `Form` closes, add:

```swift
if let trade, canEditExisting {
    MistiaDestructiveActionSection(
        buttonTitle: L10n.investment.trade.deleteAction,
        descriptionText: L10n.investment.trade.deleteDescription,
        popupMessage: L10n.investment.trade.deleteConfirmation,
        confirmationButtonTitle: L10n.common.delete
    ) {
        if onDelete(trade) {
            dismiss()
        }
    }
}
```

This gives the user the Apple native `confirmationDialog` behavior implemented by the shared component: destructive Delete and Cancel. It only renders for a saved trade with edit permission. A local delete failure keeps the sheet visible and uses the hub's existing error message path.

- [ ] **Step 5: Run localization and focused regression checks**

Run:

```bash
/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
swift Scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift \
  --strict-keys \
  --check
swift test --filter InvestmentPersistenceTests
```

Expected: localization check and generated-file check pass; all investment persistence tests remain green.

- [ ] **Step 6: Build the iOS app and inspect the form on an available simulator**

Run:

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices booted
```

Expected: build succeeds. If an iPhone simulator is already booted, open an existing Buy and Sell and verify: asset picker works for both, kind remains fixed, the red delete section appears only on saved editable trades, confirmation offers Cancel/Delete, and confirm removes the activity while Cancel preserves it. Do not boot, erase, or modify simulator state solely for this check.

- [ ] **Step 7: Commit editor and localization work**

```bash
git add Mistia/Features/Investment/InvestmentHubView.swift \
  Mistia/Localizable.xcstrings \
  Mistia/Shared/CoreLogic/L10n.generated.swift
git commit -m "feat: edit and delete investment sells"
```

### Task 4: Full Verification and Cloud Alignment

**Files:**
- Verify only; do not create a migration unless Task 2 exposed a failing cloud contract.

- [ ] **Step 1: Run all local tests and database tests**

Run:

```bash
swift test
supabase test db supabase/tests/database --local
git diff --check
```

Expected: Swift package suite has zero failures, all pgTAP files pass, and Git reports no whitespace errors.

- [ ] **Step 2: Verify linked Supabase alignment without touching production data**

Run:

```bash
supabase migration list --linked
supabase db push --linked --dry-run
```

Expected: local/remote migrations remain aligned through `20260810111705`; dry-run reports no migrations to apply. Do not run pgTAP fixtures against the linked database and do not push a migration when the dry run is up to date.

- [ ] **Step 3: Review the final diff and commit any only-if-needed migration repair**

Run:

```bash
git status --short --branch
git log --oneline -4
```

Expected: the three feature/test commits are present and the worktree is clean. If Task 2 required a repair migration, commit it separately only after local reset, pgTAP, linked dry-run, explicit linked push, and a final linked migration list all succeed.
