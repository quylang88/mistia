# Exact and available Overview assets implementation plan - slice111

Goal: the complete available-assets hero flow preserves exact cash plus remaining inventory, and never shows a partial number when an eligible component is unavailable.
Base: 022988f3436bc167bd97a6f73bfec2ea96fec9ca. Branch: codex/android-apk2-4-parity. User TXT authorizes autonomous local slices, runtime TDD, review/fix/check/evidence/commit, then continuation. The old superpowers plugin/helper files are no longer installed; perform the equivalent workflow directly.

## Design and constraints

- Return nullable BigInteger from overviewTotalAssets and overviewInventoryCost. Add a BigInteger overload of the strict OverviewMoney conversion helper; keep the Long overload as a delegating entry point. Wire/storage amounts stay signed Long, rates/quantities decimal strings. Zero needs no currency/FX; nonzero invalid/unsupported/missing conversion holds the complete total. Same-ISO imported money retains exact minor units.
- Preserve cash classification and active owned noncredit-wallet selection. Apply all source/destination/debt/family/shared/resale/future posted legs in exact wallet currency, then convert each final wallet balance once. This rounding differs deliberately from per-record monthly/day reporting. Keep signed cancellation exact, without clamping either balances or final totals.
- Inventory uses active owned channel/asset and latest owned position by occurred/created/UUID. No trades means zero. Unorderable calendars or malformed latest quantity/nonzero-position cost make inventory unavailable, never zero/partial or an older snapshot. Decimal quantity must be a string and cost an integer JSON number. Quantity <=0 contributes zero without requiring cost. Negative numeric cost remains max(cost,0), matching Swift normalization. Foreign/deleted/envelope-invalid rows do not poison owned positions; inactive parent components are excluded as before.
- Accounting currency metadata remains independent of cash opening parsing. Invalid existing metadata with nonzero inventory cannot be converted to zero or relabeled primary. A zero inventory needs no accounting currency; unknown inventory remains unknown.
- Hero shows full exact value or emdash plus vi/en/ja asset-availability hint/stateDescription, live rates/primary/wallet/position/archive updates, owner-keyed privacy and no writes. Public Screen keeps109 supported primary normalization. Preserve charts/details/selection/editor navigation.
- All10 write flags false. No push/deploy/migration/production write, Room6/SwiftDataV11/iOS751 unchanged. Version111 only after implementation. Continue full APK1-4/RC; no Samsung is not a local blocker.
- This closes aggregate/conversion/inventory availability, not global raw financial input filtering. OverviewFinancialInputs currently drops malformed wallet/ledger amounts/dates and can remove metadata before projections; preserve that mandatory subsequent audit, plus Recent legacy currency/import classifiers/global planning and remaining full goal.

## Direct Swift references and review focus

OverviewLogic.swift407-455, OverviewView.swift655-688, InvestmentLogic.swift397-420 and InvestmentModels.swift367. Preserve cash/family/debt/reporting snapshot behavior; exact nullable reporting intentionally corrects Swift overflow/missing-rate-zero under user financial correctness requirement. Investment CRUD/position rebuilding/RPC permissions remain separate.

Review focuses on exact >Long cash/inventory/conversion/cancellation, per-final-wallet rounding, sticky whole-total unknown and zero semantics, strict latest-position shape/order, accounting metadata, ownership/lifecycle/live repair/read-only invariants, and complete actual1.0/1.3 light/dark values/hints. Existing chart and editor flow must remain verified. No broad imported/raw/Samsung/cloud completion claims.

## Task 1 - complete exact assets hero flow

Files: OverviewAssets.kt, OverviewMoney.kt, OverviewAssetsTest.kt; new OverviewAssetsMoneyTest.kt; OverviewScreen.kt, OverviewHeroMetrics.kt; new OverviewAssetsMoneyScreenTest.kt and migrated existing assets fixtures; Localizable.xcstrings plus both generators; app version111. Evidence/progress/PNG artifacts.

- [x] Business model goldens on110 before main/API changes: 2MAX/2MIN, >Long per-wallet FX, cancellation, per-wallet rounding, unknown partial totals/recovery, same ISO/import/malformed codes, zeros/ownership/classifiers, inventory overflow/latest malformed/strict wire/calendar/no resurrection. Require actual runtime RED, not compilation/type errors.
- [x] Native baseline on110: exact cash+inventory/negative, partial-FX unknown/live repair, wallet/primary/accounting changes, malformed latest position/sold/archive recovery, owner replacement, unchanged Room/outbox; actual1.0/1.3 light/dark full-glyph values/hints and settled captures.
- [x] Minimal nullable exact model/conversion implementation; migrate prior15 assets goldens to exact/unknown, retain classifier/order/UUID tests. Focused existing Overview models GREEN.
- [x] Hero nullable display/hint and Screen propagation (never dropping inventory on invalid accounting metadata); generators/checks. Focused native GREEN and inspect final actual-density images.
- [x] Review diff directly against Swift and a fresh independent read-only slice review. One fix pass for findings with actual RED/GREEN, explicit minor/declined rulings and final checks; no rereview loop.
- [x] Full JVM/AndroidTest compile/package/lint/build, Swift610/contracts15/both strict l10n/SQLite7-3-11/Room6assets/whitespace; full Overview native and actual2editor integrations. APK metadata/manifest/DEX/checksums/executed identity/install-r/cold smoke. Evidence/progress and independent111 commit, immediately continue remaining goal.

Completion: actual12model8RED1sec ->85focused/8suitesGREEN; nativebaseline7/8RED47.148sec ->8/8GREEN19.1sec; freshreviewnoCritical/Important/newMinor. Final1573JVM/151,79Overview182.339sec,2editor9.943sec,Swift610/scripts/lint/build75sec+fixture4secGREEN. Six final-package actual130%PNGs refreshed/inspected; positive/negative alsofullglyph1.0. Three executed APK SHAs match archives,111install-r/coldStatusok1116ms/version confirmed. Independent111commit then rawfinancialinput audit/fullremaininggoal; no whole-goal completion.
