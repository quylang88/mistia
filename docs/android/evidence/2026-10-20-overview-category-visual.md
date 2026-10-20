# Category visual details, transaction-count caption and native test scheduling - slice118

2026-10-20; codex/android-apk2-4-parity; base db016de8. Full APK1-4/RC remains active.

## Visual behavior and direct review

Category back button now includes chevron, category icon and name in its capsule; empty category state includes pie icon above centered explanatory text. Canvas sectors use a vertical color gradient, rounded path corners7/4 for prominent/other slices,2dp chart inset, existing radius1/0.92, background circle/border and dominant-color shadow12dp/y5, dark/light alpha0.28/0.18. Existing positive5+Other, exact BigInteger amount/percentage denominators, dimensionless visual ratios, physical pie-angle selection/haptics, root/oneleveldrill/back/month/availability behavior retained. Amounts never enter Float wire/accounting; Float only draws ratios/colors/geometry. Existing responsive layout and complete large money at130% retained.

Shared catalog key overview.overview.transactions is used only in SwiftDaySheet2113 and AndroidDaySheet; its old Cashflow/ThuChi/収支 caption incorrectly described a transaction count. It now says Transactions/Giao dịch/取引件数; both generators run. iOS receives the shared localized caption/fallback, with no iOS runtime behavior change; no iOS simulator UI verification claimed.

Parent inspected actual focused images and found new back icon rendered legacy fork.knife as ellipsis. Native bitmap equality test reproduced1382 differing pixels versus canonical food catalog icon. Shared CategoryIcon now passes an uncatalogued raw SF symbol through existing native family resolver; nativefood render matches canonical representation. This does not certify fidelity of the full147icon catalog/asset pack; broader native asset/legacy icon audit remains.

Direct Swift Core/UI/MistiaCategorySpendingChartView65-100/153-176/309-350 and MistiaFinanceIcons995-1055 reviewed: chevron/category tile, empty icon/type, gradients/inset/radius/corners/shadow and legacy-symbol meaning. Native Material icon/tile rendering remains approximate rather than a pixel-identical SF/asset port. New24PNG fixtures render real Compose chart/sheet components with actual resources/density; they are not MainActivity root navigation captures. Existing realRoom Overview category/day suites prove application composition/routing separately. Broader statusbar/fullscreen/iconpack/olderfont/Eventbadge audit remains.

Parent reviewed final immutable source/test patch SHA256 `5e4fcbf065616ea18d3c326a355ab0ada3b451c3b9c28cca945339a66e92a9a8`; old113e14...pre-harness patch is superseded. No independent agent review executed/approval claimed; finalwholebranch independent audit remains outstanding.

## Actual TDD, failure diagnosis and final checks

Baseline117 native4/4 intended RED5.988sec: incorrect countcaption, flat interiorpixel gradient, missingback categoryicon and emptyicon. Minimal implementation ->4/4GREEN6.843sec. Extended root/drill/empty/daycaption actual130%vi/en/ja lightdark plus oldcategory12 ->18focusedGREEN40.08sec. Parentlegacyiconfinding ->1nativeRED1.648sec/1382pixels ->minimalfallbacksymbolfix ->7newnativeGREEN16.2sec. Structural icon tags prove presence only; actual pixelgradient/equality and rendered screenshots provide additional visual proof.

The first whole125 run did NOT pass: instrumentation process crashed during historical weekly swipe at test118. Surface error was Modifier.Node.runDetachLifecycle during Activity destruction. Captured PID9900 log establishes an earlier ComposeInternal exception at18:12:18.413: SnapshotStateObserver accessed from arch_disk_io_0 instead of the main thread, with TestMonotonicFrameClock/ApplyingContinuationInterceptor resuming the test Recomposer on the Room thread; subsequent teardown error at18:12:44. Isolated original test passed2.449sec. New twelve-cycle prepend/remove/mount/unmount regression control passed11.47sec on old harness; this was not a new runtime RED. No weekly production pager change was made without causal evidence.

Locally bundled Compose1.11.4 AAR exports v2.createComposeRule(CoroutineContext), verified via javap. All17Overviewnative fixtures now use that v2 entry point/StandardTestDispatcher, replacing legacy unconfined test execution. No library upgrade or future1.13configuration API used. Android documents queued v2 versus immediate v1 coroutine execution in its [migration guide](https://developer.android.com/develop/ui/compose/testing/migrate-v2) and [release article](https://android-developers.googleblog.com/2025/12/whats-new-in-jetpack-compose-december.html). These sources support the harness scheduling change; the specific wrong-thread diagnosis comes from this run's captured log. V2 weekly12+visual7 **19/19GREEN50.276sec** before final whole rerun. Transaction editor harness remains unchanged; wider test API migration is not claimed.

Final **1648JVM/158suites0fail/errors/skips**, required Room/management/planning/overview/transactions/settings AndroidTestcompile/package and lint/build GREEN46sec, final post-harness full command incrementalGREEN6sec. Swift610(4contracts/137data/469core), contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace passed; Swift/resources unchanged after those checks. Final whole Overview **126/126GREEN332.987sec**, including the formerly crashing history test and twelve-cycle regression. Actual recent/day-readable exactRoom/outbox +unreadableoriginal storededitor **3/3GREEN13.368sec**. ADB exit0/initialcrashed run is not testpass evidence; final actualJUnit footers used.

24settled final PNGs: category root/drill/empty and day-countcaption, each en/vi/ja light/dark at actualfontScale1.3, complete glyph assertions/physical pie/back behavior. Pulled after final whole run and ALL inspected in overview-category-visual-2026-10-20/. Earlier focused captures and pre-legacyfix icon images are not final evidence.

Main118install-r preserves data, coldStatusok1108ms/version118/min26/target36. All3installed base.apk SHA256 match final archives. Manifest/main20-overview9-transaction11DEX/outputmetadata checked. No production/testsource edits after final checks.

## Artifacts and continuing full scope

Ignored archives android/build/outputs/apk2/2026-10-20/, mistia-overview-category-visual-v118-SHA256SUMS.txt/badging/outputmetadata/installedSHA. Oldpre-v2OverviewtestSHAc537... is superseded.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-category-visual-v118.apk|6486a077de5dc129aa008a0ef6deec832450c1db818cb02d68a59d97472f6c94|
|mistia-overview-category-visual-test-v118.apk|e313891bed7d27d98f1138427c3d65dd6f4f5b85b659258e749a032caafd2cb2|
|mistia-overview-category-visual-transaction-test-v118.apk|bc6acd8c615ef31729ade64b61e5869d60a62efa3227846835bfc41611884a73|

All10writeflagsfalse; Room6/SwiftDataV11/iOS751 unchanged. API36ARM64emulatortransport12 only; noSamsung/liveSupabase/productionwrite/deploy/migration. Logs /tmp/mistia-overview-category-visual-* distinguish baseline/legacyRED/focusedGREEN/firstcrashedwhole/PIDlog/isolated/stress/v2focused/v2whole/host/editor/Swift/cold.

Next actual budget read correctness prerequisite for Overview watchlist: BudgetPlanning currently clamps Long aggregates and PlanningMoney returns0 for missingFX, normalizes unsupported/nullcode toJPY, and spending lacks owned-wallet sourcecurrency fallback. ActualJVM/nativeRED required before fixing. Broader raw budget/planning availability, imported/source-wallet/classifiers/financialdomain/loadingatomicity, family/event/investment/receipts/Overviewbudgetfocus/upcoming/preparing/config/device/background/RC/finalindependentreview remain.

Correction to stale prior carry-forward: direct Swift OverviewView716-808 renders configurable investment/preparingSettlements/budgetFocus/upcomingBills/recentTransactions after hero. There is no separate Overview wallet/card-list section. Android Wallets/cards wallet/category counters are APK0 placeholder and should be replaced by actual sections, not expanded into an invented wallet-list feature. Fullassetpack/Eventbadge/olderfont audit also remains. No fullfinancialUI or goalcompletion claim; separate118commit then immediate119budgetreadTDD/fullscopecontinuation.
