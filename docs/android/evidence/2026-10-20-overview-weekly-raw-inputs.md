# Truthful raw weekly spending admission - slice115

2026-10-20; codex/android-apk2-4-parity; base d755c162131c58121d5e17af2a719e2acae6d3a6. Full APK1-4/RC remains active.

## Behavior and direct Swift review

Weekly chart consumes strict raw reporting effects shared with114 monthly admission rather than a filtered typed list. Required unreadable expense/classification/eligibility/currency retains whole-week unavailability; readable expense survives unused income override/destination money/created calendar. Explicit reporting expense can remove original-money dependency. Income-only unknowns and proved zero expense never poison spending or require FX/calendar. Amounts remain strict JSON Long wire numbers and BigInteger reporting aggregation, per-record FX rounding/cancellation preserved.

A known dated unknown expense creates its historical week. Unplaceable expense holds all known/current weeks using an explicit hasUnplacedExpense flag, without inventing a date or replacing known points with null placeholders. Whole week total is unavailable; graph exposes the generic localized114 reporting hint and keeps range/pager, hiding axes/bars/callout/day actions. Selection clears when availability changes even if the known points remain equal; date repair cannot resurrect an old callout. Text semantics expose the replaced chart state without redundant repeated descriptions.

Shared raw extraction preserves owner/entity/canonical envelope/body identity, tombstone/archive/status, per-direction field dependencies and currency/kind metadata independent of opening. OverviewMonthlyEffect is renamed to read-only OverviewReportingEffect; typed public monthly/weekly entry points retain prior valid-input behavior. Consumer cutoffs are independent: monthly excludes future months; weekly includes posted future dates up to current Sunday, including next month/year, and excludes future weeks before money validation. Unrepresentable calendar remains unplaced/unknown rather than being silently dropped.

One review finding: unknown primary classification unnecessarily held an independently proved zero expense when only income was uncertain. Zero proof is now per direction, preserving monthly expense0/incomeunknown as well as weekly0. This is a known zero result, not fallback/coercion of unreadable money. No reporting snapshot is persisted or used for balances.

Direct Swift: OverviewLogic.swift457-554 (Monday-Sunday pages, posted reported-expense/day aggregation/future-withinweek),808-824 (reporting conversion/day values), TransactionLogic.swift1423-1469 (original/override/debt classification). Readable financial behavior and history/selection/physical gestures remain, intentionally correcting malformed partial0/missingFX/overflow under financial correctness. Existing Screen nonempty-day guard is retained; original-day/category raw admission is not certified by this weekly fix.

## Actual TDD and checks

Nine JVM baseline cases on114:8 actual monetary runtime RED1sec, foreign/inactive/future/income-only control passed. Native baseline6/6 intended money/availability RED39.014sec on114. A missing getOrNull test import was a separate compile diagnostic fixed before successful baseline package2sec; not counted as runtime RED.

Implementation -> initial133 focused JVM/14suites GREEN8sec and native6/6 GREEN14.96sec. Review zero-direction finding: new10th JVM case1/10 actual runtime RED1sec (expected0/actualnull), dedicated new native1/1 RED6.78sec. Separate fixture packaging followed the intentionally failing unit task before installing the new test; no stale APK baseline claim. Per-direction zero fix ->134 focused JVM GREEN2sec and **16/16 focused native GREEN34.45sec** (new7 +monthly raw5 +wallet metadata4). Year-boundary and Tokyo-local Monday controls added: feature57 GREEN1sec; core78 remained GREEN (135 focused tests/14suites). No further production findings.

Parent reviewed complete immutable source patch SHA256 `b6ab27e3d78cdde2cef50977963debfb4d481a98e24eeb0d3c247b467a87510a` and direct Swift. No independent115 agent review executed; existing reviewer usage failure is documented in112 and final independent wholebranch audit remains outstanding. No approval claimed.

Full **1623JVM/156suites**, zero failures/errors/skips; required Room/management/planning/overview/transactions/settings AndroidTest compile/package and lint/build GREEN140sec. Swift610 (4contract/137data/469core), contracts15, both strict localization checks, SQLite7/3/11, Room6 assets and whitespace passed. Final whole Overview **103/103 GREEN270.1sec**, actual recent/day -> stored editor -> exact Room/outbox **2/2 GREEN7.81sec**. Native snapshots cover both owners' wallet/ledger/category raw rows/outbox, live raw money/status/draft/calendar/metadata/owner changes, physical callout taps/history, no stale selection, actual1.3 localized hint/full-glyph and six settled captures. Six final-production en/vi/ja light/dark PNGs in overview-weekly-raw-2026-10-20/ pulled after the whole run and all inspected.

Main115 installed with adb install-r preserving data; cold MainActivity Status:ok1160ms, version115/min26/target36 confirmed. All3 installed base.apk SHA256 values match the final archives below. No source edits after final checks.

## Artifacts and remaining scope

Ignored archives android/build/outputs/apk2/2026-10-20/, mistia-overview-weekly-raw-v115-SHA256SUMS.txt/badging/outputmetadata/installedSHA records. Manifest and main20/Overview9/transaction11 DEX entries inspected.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-weekly-raw-v115.apk|dbaf21318d5a9beb2ad038d255c2a9f2919b6b499fbf9bb914083b35b6ab800b|
|mistia-overview-weekly-raw-test-v115.apk|f9a83e54d51cd0c67fa7ed3f22ef67a411941130b92e5a4ad9622863cc18c0e3|
|mistia-overview-weekly-raw-transaction-test-v115.apk|cfa57f0b38e00e2c85602fd82e46114a014c36100ad271af460a52c57daf2047|

All10writeflagsfalse; Room6/SwiftDataV11/iOS751 unchanged. API36 ARM64 emulator transport12 only, no Samsung/liveSupabase/productionwrite/deploy/migration claim. Existing original day raw filtering can still omit unreadable amount/created/unused fields or show partial/zero after corruption while a sheet is already open; day count/ordering/unknown rows/editor repair remain mandatory next work. Category raw can still omit unknown-only historical months/grouping/money, despite monthly model history; category availability/navigation/visual minors also remain required. Broader source-wallet/import/legacy/classifier/financial-domain/global planning, cross-flow loading/atomicity, family/event/investment/receipts/Overview walletcards/budget/due/config, day Event badge/older sheet actual-font audit/device/background/RC/final independent wholebranch review remain. No whole financial UI or goal completion claim.

Logs /tmp/mistia-overview-weekly-raw-* distinguish baseline unit/native RED, zero-direction supplemental RED, focused GREEN and final host/native/editor/Swift/cold smoke. ADB exit0 alone never substitutes for JUnit footers. Continue next consumer and full APK1-4/RC immediately after this separate local commit.
