# Exact budget totals and unavailable amounts — slice 119

2026-10-20; branch `codex/android-apk2-4-parity`; base `caf690a9`.

## Behavior and scope

Budget read amounts, branch allocations, summary totals and pace now use nullable `BigInteger`. Two maximum signed Long expenses display 18,446,744,073,709,551,614 minor units without saturation. Converted records round independently before exact accumulation. Missing nonzero FX or a required uncertain classifier holds the affected whole amount; remaining and health cannot claim a known zero or stable state. Known independent parent limits and child allocations remain available. Zero and proved irrelevant expenses need no unused currency/calendar dependencies.

Currency lookup follows explicit source code, owned historical source wallet, then the established missing-metadata JPY legacy case. An invalid present currency does not silently become JPY. Archived wallet currency/kind remains available to historical spending. Owner/deleted filters remain. A reporting expense override retains existing budget semantics; generated adjustment/card and loan exclusions reuse the existing expense classifier. Finite candidates make future required enum values uncertain rather than neutral.

The UI uses complete exact money, an em dash and the existing generic unavailable hint, neutral health and no progress bar when a required amount is unknown. App locale supplies frozen localized names and month order. Read-only tests compare records and pending mutations for both owners through FX removal/repair, classifier repair and owner replacement. No placeholder read amount enters persistence, drafts or editor save payloads. Stored money remains signed Long; no schema or cloud change.

This slice consumes existing typed plan/transaction/category snapshots. Raw malformed money/eligibility, silently omitted plans, continuity/import identity, category relationship uncertainty, read-set loading/atomicity and family financial coverage require subsequent work. Savings and dues still use their independent legacy conversion behavior; their financial availability is not certified here. The obsolete budget missing-FX and saturation golden expectations were corrected deliberately, while valid existing month/rollover/exclusion/identity tests remain.

## TDD and review

- Baseline: new core eight cases produced seven business failures in 1 second; native four money cases all failed in 25.979 seconds.
- Initial exact implementation: core 34 focused tests passed. First native run exposed a matcher error: `assertTextContains` defaults to exact matching while summary semantics include a label. Its correction uses whole text equality or a complete `: amount` suffix. That harness failure is not a product RED.
- Future transfer classification review: ninth core case failed, and the corresponding native case failed in 12.951 seconds while the original four passed. Reusing finite candidates of the existing classifier fixed the false neutral zero; five native cases passed in 8.143 seconds.
- Three additional core acceptance controls cover independent parent allocation, irrelevant invalid calendars and required-only wallet kind uncertainty. Final new core suite has 12 cases; all 38 budget core tests passed.
- Actual 130% localized rendering found an app-locale bug and a stale budget test expecting a partial known total when a required rate is absent. The former is a product finding; the latter is an intentionally updated oracle. Savings' separate old partial-total expectation is explicitly retained as an open audit item. The focused 34 native tests passed in 124.779 seconds.
- Archived wallet review reproduced two native failures in 13.256 seconds: lost VND legacy source currency and lost credit-card kind. Passing owned historical metadata into the budget projection fixed both; all eight new native tests passed in 16.452 seconds.

The first whole Planning run completed 101 cases in 519.252 seconds with two failures; it is not passing evidence. An installment restoration case queried the merged button while only the unmerged node existed, and one bill late-save case timed out before its callback started. Both unchanged tests passed together in isolation in 18.157 seconds. Tests now wait for the merged loaded payment target, assert the selected bill category/wallet/amount, and explicitly settle the UI after Save. No timeout was enlarged, no repeat click added, and the original persistence/noncancellable account-isolation assertions remain. No precise cause of the intermittent bill submission timing is claimed. The final host command after these test readiness changes passed in 4 seconds. Earlier patch SHA159d... and planning test APK7dd... are superseded.

Planning's 14 existing Compose test fixtures now use the locally available v2 queued dispatcher, following the actual test-clock diagnosis in slice 118; no dependency upgrade. Image review then found the new font fixture lacked the app's inherited surface/content color. The fixture now supplies a Material Surface, matching the application Scaffold's background/content-color context, and resets the scroll before capture. This was a fixture correction, not a speculative production dark-mode change.

Direct Swift review: PlanningLogic 936–1038 pace, 1042–1210 continuity/rollover/rows and 1291–1415 branches, plus spending index and PlanningView summary. Exact read arithmetic and truthful missing-FX behavior deliberately correct existing Int64/Double/clamping/zero-conversion defects. Original stored editor identity and user-approved same-currency branch saving remain. Parent reviewed immutable Android source/test patch SHA256 `b15be798e00a4a19080dde5c14df0a81e864a043794e84da594d6b5b327d7eeb`. No independent agent review executed or approval claimed; whole-branch independent review remains outstanding.

## Final validation and artifacts

Final whole Planning: **101/101 GREEN in 583.418 seconds**, including both formerly failing cases. All12 final en/vi/ja light/dark actual130% financial screenshots were refreshed after the final Planning run and inspected; complete money/hint glyphs also have native assertions. These captures have differing financial viewport positions and do not certify header alignment, system insets or full MainActivity navigation. Final whole Overview: **126/126 GREEN in 348.826 seconds**. Actual stored-editor routes: **3/3 GREEN in 16.575 seconds**, including exact Room/outbox saves and refusal to write a placeholder for unreadable original money. Main119 installed with `adb install -r` preserving data; cold `Status: ok`, 1,978ms. Installed main/planning/overview/transactions base.apk SHA256 values all match the archived final artifacts. No production/test source changes followed final validation. Host full command passed in 66 seconds; post-fixture full command passed in 5 seconds. JVM XML totals: 1,660 tests / 159 suites, zero failures/errors/skips. Swift 610 and contracts 15, both localization generators, SQLite checks 7/3/11, Room six schema assets and whitespace passed.

The 18 tests in the two readiness-affected classes passed in 67.598 seconds. Archive contents and metadata confirm main20 / planning9 / overview9 / transactions11 DEX, Android manifests, min26/target36 and main version119. Archives are ignored local artifacts under `android/build/outputs/apk2/2026-10-20/`.

| Artifact | SHA256 |
|---|---|
| mistia-0.2.0-apk2-budget-exact-read-v119.apk | f9b9d59caf3391bf6738fdc5308df6dd911a03264974a98d2a4d1654352614fa |
| mistia-budget-exact-read-test-v119.apk | 1a3a644762623e227ffcd4a5ba601b05a97fcd0c75f38571cf92cfde88822771 |
| mistia-budget-exact-read-overview-test-v119.apk | 4a58305dc8c6176303949ab603380dc4ea5bc6476e79bf19c7b3eb34f52ea350 |
| mistia-budget-exact-read-transaction-test-v119.apk | 7a3aa03ae7eb80ec6f3456cc2dd2179bf7801e860d9e226898b6f2b2113faa22 |

All ten write flags remain false. Room 6 / SwiftData V11 / iOS build 751 unchanged. API 36 ARM64 emulator, transport 12; Samsung absent. No live Supabase, production write, deployment or migration verification claimed. Logs `/tmp/mistia-budget-exact-read-*` retain baseline, classifier/localization/archived review failures and final runs.

Full APK 1–4 and RC goal remains active. Next: consumer-specific raw budget admission before the real Overview budget watchlist. These images cover actual Room PlanningScreen financial content rather than MainActivity root navigation or system-inset certification. Actual Overview sections/configuration, family/event/investment/receipts, remaining visual/font coverage, device/background/release checks and final independent whole-branch audit remain.
