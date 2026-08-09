# Investment Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Investment asset-centric, calculate and show weighted-average unit cost from total order amounts, remove opening-position and fee inputs, and replace the dense dashboard with the approved compact month-based layout.

**Architecture:** Keep `InvestmentPersistenceService` as the only write boundary and keep total order amounts unchanged throughout wallet validation, currency conversion, ledger posting, and accounting. Add pure derived position and calendar helpers in `MistiaCoreLogic`, then make `InvestmentHubView` consume those helpers through focused SwiftUI components. Preserve legacy opening and fee fields for SwiftData/Supabase compatibility while new records use zero values.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Apple String Catalog, MistiaCoreLogic Swift Package.

---

## File Map

- Modify `Mistia/Shared/CoreLogic/InvestmentLogic.swift`: derived average unit cost and selected-month interval helpers.
- Modify `Tests/MistiaCoreLogicTests/InvestmentLogicTests.swift`: red-green calculation and month-selection regressions.
- Modify `Mistia/Shared/Persistence/InvestmentPersistence.swift`: default new asset opening values to zero.
- Modify `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`: total-order, zero-opening, and legacy-fee persistence regressions.
- Modify `Mistia/Features/Investment/InvestmentHubView.swift`: period state, compact dashboard, asset rows, activity filtering, asset editor, and fee-free trade editor.
- Modify `Mistia/Localizable.xcstrings`: precise total-order and position-detail copy in Vietnamese, English, and Japanese; remove newly dead investment input keys.
- Regenerate `Mistia/Shared/CoreLogic/L10n.generated.swift` from the String Catalog.

### Task 1: Derive Average Unit Cost in Core Logic

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/InvestmentLogicTests.swift`
- Modify: `Mistia/Shared/CoreLogic/InvestmentLogic.swift`

- [ ] **Step 1: Write failing unit-cost tests**

Add these tests before `testSummaryFallsBackToCostBasisWithoutValuation()`:

```swift
func testPositionAverageUnitCostUsesRemainingCostBasisAndQuantity() {
    let position = InvestmentAssetPositionSnapshot(
        id: UUID(),
        channelID: UUID(),
        quantity: 3,
        remainingCostBasisMinor: 120,
        marketValueMinor: nil
    )

    XCTAssertEqual(position.averageUnitCostMinor, 40)
}

func testWeightedAverageUnitCostSurvivesPartialSale() throws {
    let sellID = UUID()
    let start = Date(timeIntervalSince1970: 4_500)
    let calculations = try InvestmentAccountingEngine.calculationMap(
        trades: [
            trade(kind: .buy, quantity: 2, gross: 100, occurredAt: start),
            trade(kind: .buy, quantity: 1, gross: 80, occurredAt: start.addingTimeInterval(1)),
            trade(id: sellID, kind: .sell, quantity: 1, gross: 90, occurredAt: start.addingTimeInterval(2))
        ]
    )
    let remaining = try XCTUnwrap(calculations[sellID])
    let position = InvestmentAssetPositionSnapshot(
        id: UUID(),
        channelID: UUID(),
        quantity: remaining.positionQuantityAfter,
        remainingCostBasisMinor: remaining.positionCostBasisAfterMinor,
        marketValueMinor: nil
    )

    XCTAssertEqual(remaining.positionQuantityAfter, 2)
    XCTAssertEqual(remaining.positionCostBasisAfterMinor, 120)
    XCTAssertEqual(position.averageUnitCostMinor, 60)
}

func testZeroQuantityHasNoAverageUnitCost() {
    let position = InvestmentAssetPositionSnapshot(
        id: UUID(),
        channelID: UUID(),
        quantity: 0,
        remainingCostBasisMinor: 0,
        marketValueMinor: nil
    )

    XCTAssertNil(position.averageUnitCostMinor)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter InvestmentLogicTests/testPositionAverageUnitCostUsesRemainingCostBasisAndQuantity
```

Expected: compilation fails because `InvestmentAssetPositionSnapshot` has no `averageUnitCostMinor` member.

- [ ] **Step 3: Implement the minimal derived property**

Add this computed property to `InvestmentAssetPositionSnapshot` in `Mistia/Shared/CoreLogic/InvestmentLogic.swift`:

```swift
var averageUnitCostMinor: Int64? {
    guard quantity > 0, remainingCostBasisMinor >= 0 else { return nil }
    var value = Decimal(remainingCostBasisMinor) / quantity
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 0, .plain)
    let number = NSDecimalNumber(decimal: rounded)
    guard number != .notANumber,
          number.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending else {
        return nil
    }
    return number.int64Value
}
```

- [ ] **Step 4: Run all Investment logic tests and verify GREEN**

Run:

```bash
swift test --filter InvestmentLogicTests
```

Expected: all `InvestmentLogicTests` pass, including the weighted-average and zero-quantity cases.

- [ ] **Step 5: Commit the isolated calculation change**

```bash
git add Mistia/Shared/CoreLogic/InvestmentLogic.swift Tests/MistiaCoreLogicTests/InvestmentLogicTests.swift
git commit -m "feat: derive investment average unit cost"
```

### Task 2: Model Selected-Month Intervals as Pure Logic

**Files:**
- Modify: `Tests/MistiaCoreLogicTests/InvestmentLogicTests.swift`
- Modify: `Mistia/Shared/CoreLogic/InvestmentLogic.swift`

- [ ] **Step 1: Write failing month-interval tests**

Add:

```swift
func testInvestmentMonthIntervalUsesSelectedMonth() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 18)))

    let interval = InvestmentPeriodLogic.monthInterval(containing: selected, calendar: calendar)

    XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: interval.start), DateComponents(year: 2025, month: 2, day: 1))
    XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: interval.end), DateComponents(year: 2025, month: 3, day: 1))
}

func testInvestmentMonthNavigationMovesFromNormalizedMonthStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 31)))

    let next = InvestmentPeriodLogic.month(byAdding: 1, to: selected, calendar: calendar)

    XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2025, month: 2, day: 1))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --filter InvestmentLogicTests/testInvestmentMonthIntervalUsesSelectedMonth
```

Expected: compilation fails because `InvestmentPeriodLogic` does not exist.

- [ ] **Step 3: Implement the calendar helper**

Append this type before `InvestmentCurrencyConversion`:

```swift
nonisolated enum InvestmentPeriodLogic {
    static func monthInterval(
        containing date: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> DateInterval {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let candidateEnd = calendar.date(byAdding: .month, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: max(candidateEnd, start.addingTimeInterval(1)))
    }

    static func month(
        byAdding value: Int,
        to date: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        let start = monthInterval(containing: date, calendar: calendar).start
        return calendar.date(byAdding: .month, value: value, to: start) ?? start
    }
}
```

- [ ] **Step 4: Run the focused suite and verify GREEN**

```bash
swift test --filter InvestmentLogicTests
```

Expected: all Investment logic tests pass.

- [ ] **Step 5: Commit the period helper**

```bash
git add Mistia/Shared/CoreLogic/InvestmentLogic.swift Tests/MistiaCoreLogicTests/InvestmentLogicTests.swift
git commit -m "feat: add investment month selection logic"
```

### Task 3: Lock Down Total-Order and Compatibility Persistence

**Files:**
- Modify: `Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift`
- Modify: `Mistia/Shared/Persistence/InvestmentPersistence.swift`

- [ ] **Step 1: Add persistence regressions before changing the asset API**

Add these tests before `testTradeRejectsSourceCurrencyThatDoesNotMatchAsset()`:

```swift
func testBuyUsesTotalOrderAmountWithoutMultiplyingByQuantity() throws {
    let fixture = try makeFixture()
    let draft = try saveTrade(
        fixture: fixture,
        kind: .buy,
        quantity: 3,
        gross: 120,
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start
    )
    let trade = try XCTUnwrap(fetchTrade(id: draft.id, fixture))

    XCTAssertEqual(trade.positionQuantityAfter, 3)
    XCTAssertEqual(trade.positionCostBasisAfterMinor, 120)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 880)
}

func testCreateAssetDefaultsOpeningPositionToZero() throws {
    let fixture = try makeFixture()
    let asset = try InvestmentPersistenceService.createAsset(
        ownerUserID: fixture.ownerID,
        channelID: fixture.channel.id,
        name: "Item B",
        symbol: nil,
        currencyCode: "JPY",
        context: fixture.context
    )

    XCTAssertEqual(asset.openingQuantity, 0)
    XCTAssertEqual(asset.openingCostMinor, 0)
}

func testEditingLegacyTradeCanPreserveStoredFee() throws {
    let fixture = try makeFixture()
    let tradeID = UUID()
    let initial = InvestmentTradeDraft(
        id: tradeID,
        channelID: fixture.channel.id,
        assetID: fixture.asset.id,
        kind: .buy,
        quantity: 3,
        grossAmountMinor: 120,
        feeMinor: 10,
        currencyCode: "JPY",
        accountingGrossAmountMinor: 120,
        accountingFeeMinor: 10,
        accountingCurrencyCode: "JPY",
        fundingWalletID: fixture.fundingWallet.id,
        occurredAt: fixture.start,
        createdAt: fixture.start
    )
    _ = try InvestmentPersistenceService.saveTrade(
        ownerUserID: fixture.ownerID,
        draft: initial,
        rates: [],
        context: fixture.context
    )
    var edited = initial
    edited.grossAmountMinor = 150
    edited.accountingGrossAmountMinor = 150
    _ = try InvestmentPersistenceService.saveTrade(
        ownerUserID: fixture.ownerID,
        draft: edited,
        rates: [],
        context: fixture.context
    )
    let stored = try XCTUnwrap(fetchTrade(id: tradeID, fixture))

    XCTAssertEqual(stored.feeMinor, 10)
    XCTAssertEqual(stored.accountingFeeMinor, 10)
    XCTAssertEqual(stored.positionCostBasisAfterMinor, 160)
    XCTAssertEqual(try balance(fixture.fundingWallet, fixture), 840)
}
```

- [ ] **Step 2: Run the new default-opening test and verify RED**

```bash
swift test --filter InvestmentPersistenceTests/testCreateAssetDefaultsOpeningPositionToZero
```

Expected: compilation fails because `createAsset` still requires `openingQuantity` and `openingCostMinor`.

- [ ] **Step 3: Default opening values at the persistence boundary**

Change the end of the `createAsset` parameter list to:

```swift
currencyCode: String,
openingQuantity: Decimal = 0,
openingCostMinor: Int64 = 0,
now: Date = .now,
context: ModelContext
```

Keep the existing validation and stored model fields unchanged.

- [ ] **Step 4: Run persistence tests and verify GREEN**

```bash
swift test --filter InvestmentPersistenceTests
```

Expected: all persistence tests pass; the quantity-3 order debits 120 rather than 360, new assets open at zero, and the legacy fee remains intact on edit.

- [ ] **Step 5: Commit persistence compatibility**

```bash
git add Mistia/Shared/Persistence/InvestmentPersistence.swift Tests/MistiaDataSupportTests/InvestmentPersistenceTests.swift
git commit -m "test: lock investment total order semantics"
```

### Task 4: Simplify Asset and Trade Editors

**Files:**
- Modify: `Mistia/Features/Investment/InvestmentHubView.swift`

- [ ] **Step 1: Remove opening and symbol state from `InvestmentAssetEditorSheet`**

Delete:

```swift
@State private var symbol = ""
@State private var openingQuantity = ""
@State private var openingCost = ""
```

Replace the asset form contents with:

```swift
Picker(L10n.investment.hub.channels, selection: $channelID) {
    ForEach(channels) { channel in
        Text(channel.name).tag(Optional(channel.id))
    }
}
.disabled(asset != nil && hasHistory)

Section {
    TextField(L10n.investment.asset.namePlaceholder, text: $name)
    Picker(L10n.investment.asset.currency, selection: $currencyCode) {
        ForEach(MistiaCurrencySettings.enabledCurrencyCodes(), id: \.self) { code in
            Text(code).tag(code)
        }
    }
    .disabled(asset != nil && hasHistory)
}
```

- [ ] **Step 2: Make hydration and creation preserve compatibility fields**

Replace `hydrate()` with:

```swift
private func hydrate() {
    channelID = asset?.channelID ?? selectedChannelID ?? channels.first?.id
    name = asset?.name ?? ""
    currencyCode = asset?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
}
```

In the existing-asset branch, stop assigning `asset.symbol`. In the new-asset branch, replace the opening-value parsing and currency conversion with:

```swift
let asset = try InvestmentPersistenceService.createAsset(
    ownerUserID: ownerUserID,
    channelID: channelID,
    name: name,
    symbol: nil,
    currencyCode: currencyCode,
    context: modelContext
)
```

This leaves a legacy symbol untouched when editing an old asset and creates all new assets with no symbol and a zero opening position.

- [ ] **Step 3: Remove the fee control from `InvestmentTradeEditorSheet`**

Delete the fee state, its input field, and fee hydration:

```swift
@State private var fee = ""
MistiaCurrencyInputField(L10n.investment.trade.fee, text: $fee)
fee = MistiaCurrencyInputFormatting.groupedInput(String(trade.feeMinor))
```

- [ ] **Step 4: Preserve legacy fee and exchange-rate snapshots when editing**

At the start of `save()`, replace gross/fee conversion with:

```swift
let currency = asset.currencyCode
let grossMinor = grossAmount.currencyInputToMinorUnits(currencyCode: currency)
let feeMinor = trade?.feeMinor ?? 0
let accountingFee = trade?.accountingFeeMinor ?? 0
let rates = MistiaCurrencySettings.rates()
let sourceCode = MistiaCurrencyLogic.normalizedCode(currency)
let accountingCode = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
let exchangeRateDecimalString = trade?.exchangeRateDecimalString
    ?? rateSnapshot(from: currency, to: accountingCurrencyCode, rates: rates)

let accountingGross: Int64
if sourceCode == accountingCode {
    accountingGross = grossMinor
} else {
    guard let exchangeRateDecimalString,
          let rate = InvestmentDecimalCoding.decimal(from: exchangeRateDecimalString),
          let converted = try? InvestmentCurrencyConversion.convertedMinor(grossMinor, rate: rate) else {
        onError(L10n.investment.error.missingExchangeRate)
        return
    }
    accountingGross = converted
}
```

Set the draft snapshot fields to:

```swift
feeMinor: feeMinor,
accountingFeeMinor: accountingFee,
exchangeRateDecimalString: exchangeRateDecimalString,
exchangeRateProvider: trade?.exchangeRateProvider
    ?? rateProvider(from: currency, to: accountingCurrencyCode, rates: rates),
exchangeRateDate: trade?.exchangeRateDate
    ?? rateDate(from: currency, to: accountingCurrencyCode, rates: rates),
```

New trades therefore use zero fees; edited legacy trades retain their stored source and accounting fee plus the source-to-accounting rate snapshot that validates them.

- [ ] **Step 5: Run focused persistence tests and a compile check**

```bash
swift test --filter InvestmentPersistenceTests
swift build
```

Expected: all tests pass and `InvestmentHubView.swift` compiles without the removed asset/fee state.

- [ ] **Step 6: Commit editor simplification**

```bash
git add Mistia/Features/Investment/InvestmentHubView.swift
git commit -m "feat: simplify investment entry forms"
```

### Task 5: Replace Day-Based Dashboard with Selected-Month Layout

**Files:**
- Modify: `Mistia/Features/Investment/InvestmentHubView.swift`

- [ ] **Step 1: Remove chart-only code and add selected-month state**

Delete `import Charts`, the `.day` enum case and title branch, `InvestmentRealizedChartPoint`, `InvestmentMetricCard`, `chartUnit`, `chartPoints`, and `realizedChart`.

Add:

```swift
@State private var selectedMonth = Date()
```

Replace `selectedDateInterval` with:

```swift
private var selectedDateInterval: DateInterval? {
    switch period {
    case .month:
        InvestmentPeriodLogic.monthInterval(containing: selectedMonth, calendar: calendar)
    case .allTime:
        nil
    }
}

private var visibleTrades: [InvestmentTrade] {
    ownerTrades.filter { selectedDateInterval?.contains($0.occurredAt) ?? true }
}
```

- [ ] **Step 2: Replace the segmented picker with Month / All Time plus navigation**

Use:

```swift
private var periodControl: some View {
    VStack(spacing: 10) {
        Picker(L10n.investment.hub.activity, selection: $period) {
            ForEach(InvestmentHubPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)

        if period == .month {
            HStack {
                Button {
                    selectedMonth = InvestmentPeriodLogic.month(
                        byAdding: -1,
                        to: selectedMonth,
                        calendar: calendar
                    )
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    selectedMonth = InvestmentPeriodLogic.month(
                        byAdding: 1,
                        to: selectedMonth,
                        calendar: calendar
                    )
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
            }
            .foregroundStyle(MistiaAccent.purple.color)
        }
    }
}
```

- [ ] **Step 3: Replace the metric grid with one compact summary card**

Add this view near the existing private supporting views:

```swift
private struct InvestmentPortfolioSummaryCard: View {
    let summary: InvestmentPortfolioSummary
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.investment.hub.investedCapital)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                Text(summary.investedCapitalMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            HStack(spacing: 18) {
                metric(
                    title: L10n.investment.hub.marketValue,
                    value: summary.marketValueMinor.formattedCurrency(code: currencyCode)
                )
                metric(
                    title: L10n.investment.hub.unrealizedProfitLoss,
                    value: summary.unrealizedProfitLossMinor.formattedCurrency(code: currencyCode)
                )
            }
            if summary.realizedProfitLossMinor != 0 {
                metric(
                    title: L10n.investment.hub.realizedProfitLoss,
                    value: summary.realizedProfitLossMinor.formattedCurrency(code: currencyCode)
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [MistiaAccent.purple.color, MistiaAccent.purple.color.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

Expose it in `InvestmentHubView` as:

```swift
private var summaryCard: some View {
    InvestmentPortfolioSummaryCard(
        summary: portfolioSummary,
        currencyCode: accountingCurrencyCode
    )
}
```

- [ ] **Step 4: Add compact global Buy / Sell actions**

Add:

```swift
private var primaryActions: some View {
    HStack(spacing: 10) {
        Button {
            activeSheet = .trade(kind: .buy, id: nil)
        } label: {
            Label(L10n.investment.hub.buy, systemImage: "arrow.down.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MistiaAccent.purple.color)
        .disabled(!canCreate || ownerAssets.isEmpty)

        Button {
            activeSheet = .trade(kind: .sell, id: nil)
        } label: {
            Label(L10n.investment.hub.sell, systemImage: "arrow.up.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(MistiaAccent.purple.color)
        .disabled(!canCreate || ownerAssets.allSatisfy { position(for: $0).quantity <= 0 })
    }
    .font(.subheadline.weight(.semibold))
}
```

- [ ] **Step 5: Make each asset row show quantity, average cost, capital, value, and profit**

Inside `positionsSection`, construct the same snapshot used by the summary:

```swift
let snapshot = InvestmentAssetPositionSnapshot(
    id: asset.id,
    channelID: asset.channelID,
    quantity: position.quantity,
    remainingCostBasisMinor: position.costBasisMinor,
    marketValueMinor: latestValuation(for: asset)?.accountingMarketValueMinor
)
let detail: String
if let average = snapshot.averageUnitCostMinor {
    detail = L10n.investment.hub.positionDetails(
        InvestmentDecimalCoding.string(from: snapshot.quantity),
        average.formattedCurrency(code: accountingCurrencyCode)
    )
} else {
    detail = L10n.investment.hub.quantityOnly(
        InvestmentDecimalCoding.string(from: snapshot.quantity)
    )
}
```

Replace the current row text stacks with:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(asset.name)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
}
Spacer()
VStack(alignment: .trailing, spacing: 4) {
    Text(snapshot.remainingCostBasisMinor.formattedCurrency(code: accountingCurrencyCode))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    if let marketValue = snapshot.marketValueMinor {
        Text(marketValue.formattedCurrency(code: accountingCurrencyCode))
            .font(.caption)
            .foregroundStyle(.secondary)
        Text((marketValue - snapshot.remainingCostBasisMinor).formattedCurrency(code: accountingCurrencyCode))
            .font(.caption.weight(.semibold))
            .foregroundStyle(marketValue >= snapshot.remainingCostBasisMinor ? Color.green : Color.red)
    }
}
```

- [ ] **Step 6: Filter activity and add a compact period empty state**

Replace `ownerTrades.sorted(by: newestTradeFirst)` with `visibleTrades.sorted(by: newestTradeFirst)`. Include quantity in the activity subtitle:

```swift
Text(
    L10n.investment.hub.activityDetails(
        InvestmentDecimalCoding.string(from: trade.quantity),
        trade.occurredAt.formatted(date: .abbreviated, time: .shortened)
    )
)
.font(.caption)
.foregroundStyle(.secondary)
```

When `visibleTrades.isEmpty`, render:

```swift
Text(L10n.investment.hub.noActivityForPeriod)
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
```

- [ ] **Step 7: Compose the approved screen hierarchy**

Replace the `LazyVStack` contents with:

```swift
periodControl
summaryCard
primaryActions
positionsSection
activitySection
```

Remove the permanently visible channel chips and archived section. Keep channel filtering, channel edit/archive/restore, wallet access, and archived restore actions inside the existing toolbar menu; make the toolbar plus action open `.asset(nil)` directly when at least one channel exists, otherwise open `.channel(nil)`.

Replace `createMenu` with this overflow menu so it reuses the existing `archive`, `restore`, `.channel`, and `.wallet` paths instead of duplicating persistence logic:

```swift
private var managementMenu: some View {
    Menu {
        if ownerChannels.count > 1 {
            Section(L10n.investment.hub.channels) {
                Button {
                    selectedChannelID = nil
                } label: {
                    Label(
                        L10n.investment.hub.allChannels,
                        systemImage: selectedChannelID == nil ? "checkmark" : "square.grid.2x2"
                    )
                }
                ForEach(ownerChannels) { channel in
                    Button {
                        selectedChannelID = channel.id
                    } label: {
                        Label(
                            channel.name,
                            systemImage: selectedChannelID == channel.id ? "checkmark" : channel.iconSymbolName
                        )
                    }
                }
            }
        }

        if canCreate {
            Button(L10n.investment.hub.addChannel, systemImage: "square.stack.3d.up.badge.a") {
                activeSheet = .channel(nil)
            }
        }

        if canEdit {
            ForEach(ownerChannels) { channel in
                Menu(channel.name) {
                    Button(L10n.management.management.edit, systemImage: "pencil") {
                        activeSheet = .channel(channel.id)
                    }
                    Button(L10n.common.archive, systemImage: "archivebox", role: .destructive) {
                        archive(channel)
                    }
                }
            }

            if !archivedOwnerChannels.isEmpty || !archivedOwnerAssets.isEmpty {
                Section(L10n.management.managementarchiveditems.archivedItems) {
                    ForEach(archivedOwnerChannels) { channel in
                        Button(channel.name, systemImage: "arrow.uturn.backward") {
                            restore(channel)
                        }
                    }
                    ForEach(archivedOwnerAssets) { asset in
                        Button(asset.name, systemImage: "arrow.uturn.backward") {
                            restore(asset)
                        }
                        .disabled(!ownerChannels.contains { $0.id == asset.channelID })
                    }
                }
            }
        }

        Button(L10n.investment.hub.walletBalance, systemImage: "wallet.bifold") {
            activeSheet = .wallet
        }
    } label: {
        Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(L10n.investment.hub.channels)
}
```

Replace the trailing toolbar item with:

```swift
if canView {
    ToolbarItemGroup(placement: .topBarTrailing) {
        if canCreate {
            Button {
                activeSheet = ownerChannels.isEmpty ? .channel(nil) : .asset(nil)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(
                ownerChannels.isEmpty
                    ? L10n.investment.hub.addChannel
                    : L10n.investment.hub.addAsset
            )
        }
        managementMenu
    }
}
```

- [ ] **Step 8: Run core tests before localization generation**

```bash
swift test --filter InvestmentLogicTests
swift test --filter InvestmentPersistenceTests
```

Expected: all focused tests pass. The app target may not compile until Task 6 generates the new L10n APIs.

### Task 6: Update the Mistia String Catalog and Generate L10n

**Files:**
- Modify: `Mistia/Localizable.xcstrings`
- Regenerate: `Mistia/Shared/CoreLogic/L10n.generated.swift`

- [ ] **Step 1: Add and revise investment copy in the String Catalog**

Set `investment.trade.grossAmount` to:

```text
vi: Tổng tiền giao dịch
en: Total order amount
ja: 注文総額
```

Add:

```text
investment.hub.positionDetails
vi: %1$@ đơn vị · Bình quân %2$@
en: %1$@ units · Avg. %2$@
ja: %1$@単位・平均 %2$@

investment.hub.quantityOnly
vi: %@ đơn vị
en: %@ units
ja: %@単位

investment.hub.activityDetails
vi: %1$@ đơn vị · %2$@
en: %1$@ units · %2$@
ja: %1$@単位・%2$@

investment.hub.noActivityForPeriod
vi: Chưa có giao dịch trong thời gian này.
en: No transactions in this period.
ja: この期間の取引はありません。
```

Remove these keys only after `rg` confirms no Swift references remain:

```text
investment.hub.day
investment.asset.symbol
investment.asset.openingQuantity
investment.asset.openingCost
investment.trade.fee
```

- [ ] **Step 2: Generate the typed L10n API**

```bash
swift scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift \
  --strict-keys
```

Expected: generation succeeds and creates typed functions for `positionDetails`, `quantityOnly`, `activityDetails`, and `noActivityForPeriod`.

- [ ] **Step 3: Run Mistia localization checks**

```bash
/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
swift scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift \
  --strict-keys \
  --check
```

Expected: both commands pass with no hardcoded user-facing Swift strings or stale generated output.

- [ ] **Step 4: Build and run focused tests**

```bash
swift test --filter InvestmentLogicTests
swift test --filter InvestmentPersistenceTests
swift build
```

Expected: all commands pass.

- [ ] **Step 5: Commit UI and localization together**

```bash
git add Mistia/Features/Investment/InvestmentHubView.swift \
  Mistia/Localizable.xcstrings \
  Mistia/Shared/CoreLogic/L10n.generated.swift
git commit -m "feat: redesign investment dashboard"
```

### Task 7: Full Verification and Visual QA

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run the full Swift Package test suite**

```bash
swift test
```

Expected: all package tests pass with zero failures.

- [ ] **Step 2: Verify generated localization output again**

```bash
/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
swift scripts/generate-l10n.swift \
  --input Mistia/Localizable.xcstrings \
  --output Mistia/Shared/CoreLogic/L10n.generated.swift \
  --strict-keys \
  --check
```

Expected: both checks pass.

- [ ] **Step 3: Build the iOS app without signing**

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

- [ ] **Step 4: Perform simulator-sized visual and interaction checks when available**

Verify all of the following on an iPhone-sized simulator:

```text
1. Investment opens in Month mode on the current month.
2. Previous/next month changes the activity list and realized result.
3. All Time restores all activity.
4. The summary is one compact card with no chart.
5. Asset rows show quantity, average unit cost, remaining capital, and current value/profit when valued.
6. Add Asset has only channel, name, and currency.
7. Buy/Sell has no fee field and labels the amount as the total order amount.
8. Buying quantity 3 for total 120 displays average unit cost 40 and remaining capital 120.
9. Channel filtering, permissions, valuation, wallet access, archive, and restore remain reachable.
```

Expected: all checks match the approved compact layout; record any simulator-only blocker separately from code/test results.

- [ ] **Step 5: Inspect the final diff and repository state**

```bash
git diff --check
git status --short
git log --oneline -5
```

Expected: no whitespace errors; only intentional Investment, test, catalog, generated-L10n, spec, and plan changes are present.
