# Overview budget watchlist — slice122

Branch `codex/android-apk2-4-parity`, base `789e4063`. Full APK1–4/RC goal remains active.

## Behavior

Overview now shows the actual budget watchlist in place of the APK0 wallet/category count placeholder. Known stable-only/empty budgets hide the section. Alarms use the same owner-scoped raw budget snapshot and exact projection as Planning; there is no duplicate financial calculation or feature-to-feature dependency. The three raw-reader bodies moved unchanged into core:model, checked byte-for-byte after package/import/visibility changes; Planning has compatibility delegates and retains its strict stored edit path.

Selection preserves original branch currency money, keeps one parent/only-child row, ranks exceeded before caution, then exact signed progress and locale name, maximum3. It does not round through Double or sum children twice. Unknown health remains visible ahead of known alarms and never becomes stable0; unreadable whole projection shows the existing generic availability hint. A missing reporting-summary FX conversion cannot erase a readable JPY branch alert.

The native section uses existing catalog labels, shared icons, Swift pink/orange/green tints, exact formatted spent/limit, percentage, bounded progress and days left. Unavailable amounts/health show dash/neutral with no progress. Loading/error/owner replacement do not retain old private totals; failed reads allow Retry. Alert rows are noninteractive, matching the Swift BudgetRow. This slice covers the personal watchlist only. Actual upcoming dues/investment/preparing/config sections, family semantics and full root UI parity remain unfinished.

## TDD and direct review

- Initial absent-section core adapter:8/8 actual assertionRED2s. Literal tests cover stable filtering, rank/max3, distinct ratios above2^53, 2×Long.MAX exact money, unknown versus loaded empty, branch currency independent of summary FX, locale names, signed/zero-limit progress and one parent branch.
- Native baseline7/6 businessRED40.519s: alarms/required unknown/loading/error/owner/parent watchlist absent; stable-hidden control passed.
- Shared extraction +selector focused coreBudget/Overview/PlanningBudgetRaw GREEN4s. Initial cross-module currency smartcast compiler diagnostic fixed with a local immutable value; no compiler error counted as RED. Native wiring focusedpackage2s;7/7GREEN12.14s.
- Initial new native8/8GREEN17.146s includes real Room updates, category archive/plan archive, current retry rows, wrong-owner/late emissions, parent limits and summary-FX independence, plus12 en/vi/ja light/dark actual130% exact/unavailable image cases. Record/outbox snapshots unchanged by reads.
- Direct reference: Swift OverviewLogic1093–1154/1331–1351; OverviewView793–796/2298–2377; OverviewSupport149–161. Source/test immutable patch SHA256 `fe674423bf1a8c95c94622e2afe847ffc6198bc8e5657df8613f0f38a8ace174` reviewed. No independent whole-branch approval claimed; that remains at full goal completion.

## Verification and artifacts

Full Android host command terminal0/BUILD SUCCESSFUL73s: **1697JVM/163suites zero failures/errors/skips**, required AndroidTest compile/package, Room compilation, lint/main assembly. Swift610/contracts15/bothstrictlocalization/SQLite7-3-11/Room6schemas/whitespace passed. All12 final component images inspected: exact2×Long.MAX spent/limit,200%, full locale labels and unknown hints complete at actual130%. Component crops do not certify MainActivity header/system-insets, general icons or every hit target.

New native8 pass as above. First existing126Overview run125pass/1obsolete count-placeholder expectation failure293.598s: owner-switch fixture still demanded the removed12345 wallet-count text. Removed only the obsolete count input/assertions and renamed the fixture; its private-row-before/absent-after owner switch and empty replacement state assertions remain. Host fullcheck after test-only correction GREEN13s; production APK unchanged. Corrected owner-switch case1/1GREEN2.074s. Planning54/54GREEN207.876s on the extracted reader. Before the final visual review, full134/134GREEN342.03s established the owner-fixture correction. Final visual **135/135OverviewGREEN349.122s** and final **54/54PlanningGREEN205.979s** after the corrections below. Main122install-r preserved data; cold `Status: ok`/`LaunchState: COLD`,1346ms; installed version122/min26/target36 and all3 installed/archive SHA256 matches confirmed. Archives under ignored `android/build/outputs/apk2/2026-10-21/`; manifests checked, main122/min26/target36/main20DEX/Overview9/planning9.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-budget-focus-v122.apk|cdc3874ae211d6843a77af0732a509b55030fb9fae9f0859216d799931eb638f|
|mistia-overview-budget-focus-test-v122.apk|faeca6dc5d3c5c79e97c9d038beb14ea716d154c8056c79de00800fa26945f28|
|mistia-planning-overview-budget-focus-test-v122.apk|a8f36b308603b72ef900a7ba39d11a9cbdf58e71dbc02ad171ba78bafcfcb56e|

All10writeflagsfalse; Room6/SwiftDataV11/iOS751unchanged. API36ARM64emulatortransport13 only; no Samsung/liveSupabase/production write/deploy/migration. Logs `/tmp/mistia-overview-budget-focus-*`. Conservative inherited template/alias holds and broader financial/family/Savings/Due/read-set semantics stay explicit open work. This is one actual Overview section, not an APK gate/domain completion.


## Visual review correction

Direct inspection of OverviewView2611–2641, MistiaReusableListComponents17–34, MistiaGlass184–198 and MistiaFinanceIcons995–1055 found the initial generic card had its16sp title inside the body and40dp round icons. A new actual native geometry test first failed1/1in1.946s (expected13sp, actual16sp) before the fix. Import/DpRect test-helper compiler diagnostics were corrected before that runtime RED.

The final watchlist has a13sp bold uppercase header with0.6sp tracking outside the card,8dp gap,22dp flat grouped card,14dp row insets and30dp rounded icon tiles. Shared CategoryIcon gained optional shape/glyph/alpha parameters; defaults preserve existing consumers. The watchlist uses Swift legacy/fallback geometry and category catalog tint where available. Full147asset fidelity and cross-platform rounded-font identity remain separate work; no all-icons or root UI parity claim. Known progress has no Material stop marker/gap. New native9/9GREEN20.465s includes the geometry and all12 refreshed130% locale/theme images, all inspected after the correction. Full host after final style correction terminal0/GREEN52s;1697JVM/163suites remain clean. Final archived/installed Overview hash matches the new package; Final Overview **135/135GREEN349.122s** on that same installed package. Final Planning54GREEN205.979s and main cold/hash verification complete as recorded above.


Final-style Planning first54 run had53pass/1Savings CRUD edit-save timeout225.807s; the unchanged isolated case passed1/1in8.36s. That timeout did not establish a production cause. Its CRUD fixture now asserts entered200/save-enabled and invokes the real exposed save semantics action; stored values/delete/outbox checks remain. No Savings runtime logic changed or physical save hit-target fix claimed. Host after this test-only change terminal0/GREEN5s, main/Overview APK bytes unchanged; final Planning package hash updated in the table. Final full54/54GREEN205.979s, with all stored/delete/outbox assertions retained.


Next: reproduce and guard a stale bill confirmation/source change before exposing the upcoming-dues payment route; then continue actual bill/installment/card due sections, investment/preparing/config and remaining APK1–4/RC scope. No new product currency rule inferred, no gate/domain completion claim. Separate123work, not part of this watchlist patch.
