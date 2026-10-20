# Original-day raw expenses and truthful live details - slice116

2026-10-20; codex/android-apk2-4-parity; base515478adafffe8de09a416f133c5530e9dcfba2d. Full APK1-4/RC remains active.

## Behavior and review

Original-day admission now reads only its own required raw fields. Confirmed posted expense with unreadable original amount retains trusted identity, row/count1, unknown row money and whole total. Strict numeric JSON Long rejects quoted/fractional/null money. Nullable originalMinor explicitly distinguishes unreadable amount from legitimate0 even though read-only typed display metadata needs a placeholder. Arithmetic consumes nullable originalMinor/Money only; editing reloads storage by trusted id, never this display snapshot. Total uses shared exact BigInteger/per-record FX logic and returns unknown for unreadable original money. Known zero requires no currency/FX.

Unknown status/archive/deletion/classification or unplaceable occurred date preserves confirmed rows but exposes count-unavailable and holds total only for potentially nonzero contribution. No invented day/row or confident empty0 count. Known otherday/draft/foreign/deleted/investment/nonexpense stays neutral. Unreadable created clock is only ordering metadata: keep original money/count, occurred descending then readable created descending/null last, stable input ordering on ties. Unused reporting overrides/income/destination fields cannot discard original money. Original eligibility uses existing isOverviewExpenseSpending, independent of reporting overrides; shared finite classifier candidates preserve reporting behavior. Historical owner-safe currency/name metadata survives unused opening/kind damage; sheet no longer relabels VND165 as JPY165 or loses its Day VND wallet label.

Screen recomputes open sheet from raw records; nonempty-or-uncertain guard allows meaningful unavailable original details from a readable reporting-positive bar, while a reporting-only income still cannot open an empty original sheet. Row selection dismisses sheet before routing trusted id. Existing StoredTransactionEditorRoute already blocks unreadable original amount/created clock; actual new integration proves no form/save/zero mutation, unchanged raw Room/outbox for both owners. No editor production change needed. Quoted numeric wire editor strictness is not certified by this integration.

Generic amount-unavailable text replaces misleading FX-only hint; new localized entries-unavailable text and count semantics avoid claiming no transactions. Existing parent context/resources/density sheet fix retained. Direct Swift OverviewView395-432/1234-1240/2058-2150/2192-2270 and TransactionLogic1423-1435 reviewed: original eligibility/money/count, occurred/created sorting, original row details and dismiss-before-editor. Android intentionally corrects Swift raw-minor primary-label/overflow/malformed omissions. Day Event badge and historical count-label wording remain wider visual/family audit, not closed here.

Parent reviewed complete immutable production/test patch SHA256 `3fc31d150814a98ffc5570324b9b29f2ccf26a65c58562a4de8d0556805bc2b4`. No independent agent review executed/approval claimed; prior112 reviewer usage failure and final wholebranch independent audit remain outstanding.

## Actual TDD and final checks

Baseline behavior-preserving wrapper:9JVM cases,7actual runtime business RED1sec; original/reporting distinction and exclusions/exact-money controls passed. Native115baseline5/5actualmoney/count/row RED34.598sec; separate actual stored-editor integration1/1RED6.947sec because original sheet could not open. Successful baseline packaging before execution3sec/2sec. Implementation compile initially hit internal-money-helper visibility; moved original-total operation into public core day helper, no duplicate FX implementation; diagnostic is not counted as runtime RED.

Implementation initial9JVM GREEN, native5/5GREEN12.465sec. Added meaningful zero-count, paidfor/dependency, stable-order/metadata-owner controls ->12featurecases GREEN; extended native7/7GREEN24.969sec. Actual recent/day-readable exact-money Room/outbox and unreadable-day unavailable editor **3/3GREEN12.031sec**.

Final **1635JVM/157suites**,0failures/errors/skips; required Room/management/planning/overview/transactions/settings AndroidTest compile/package and lint/build **GREEN85sec**. Swift610 (4contracts/137data/469core), contracts15, both strict localization generators, SQLite7/3/11, Room6assets and whitespace passed. Final whole Overview **110/110GREEN255.895sec**. New native fixtures snapshot both owners wallet/ledger/category raw records and outbox around UI, exercise real400ms holds, live corrupt/repair/date/draft/status/unusedfields/currency/name/owner changes; actual1.3 layout/fullglyph checks and12settled en/vi/ja lightdark money/count captures. All12 final PNGs pulled after whole run and inspected in overview-day-raw-2026-10-20/.

Main116 installed-r preserving data, cold Status:ok1403ms, version116/min26/target36. All3 installed base.apk SHA256 match final archives. Manifest and main20/overview9/transaction11DEX checked. No production source edits after final checks.

## Artifacts and remaining scope

Ignored archives android/build/outputs/apk2/2026-10-20/, mistia-overview-day-raw-v116-SHA256SUMS.txt/badging/installedSHA.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-day-raw-v116.apk|7713f13131d38d88c35fd7ebbbce20e325dcb734e12948478d75f0aa3c9c0395|
|mistia-overview-day-raw-test-v116.apk|4787c8abdf8355d2d19262b23183252cb566a552055004edd0878d63258da7a9|
|mistia-overview-day-raw-transaction-test-v116.apk|ff4a203cdd61d0cb9834cb1d261e0da855142e0656a5b098f043add2cfe3a386|

All10writeflagsfalse; Room6/SwiftDataV11/iOS751 unchanged. API36ARM64emulatortransport12 only; no Samsung/liveSupabase/productionwrite/deploy/migration claim. No new approval pause. Logs /tmp/mistia-overview-original-day-* distinguish businessRED/compile diagnostic/focusedGREEN/finalhost/native/editor/Swift/cold.

Next mandatory category raw grouping/money/availability and unknown-only historical month navigation: monthly114 history alone does not fix category pager. Broader source-wallet/import/legacy/classifier/financialdomain/global planning, cross-flow loading/atomicity, fullfamily/event/investment/receipts/Overviewwalletcards/budget/due/config, visual minors/dayEventbadge/older sheet actualfont/device/background/RC and independent final wholebranch review remain. No whole financial UI or goal completion claim; separate116commit then immediately next consumer slice.
