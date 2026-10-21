# Consistent raw budget spending — slice121

Branch `codex/android-apk2-4-parity`, base `fa05c73e`. Full APK1–4/RC goal remains active.

## Behavior

Budget display now consumes plans, ledger, source wallets and category metadata from one owner-scoped Room query, including historical tombstones. This prevents mixed wallet/ledger generations during an atomic mutation. The repository checks snapshot ownership and scope before emission. Unsupported stores fail explicitly. No schema version changes or read-side record/outbox writes.

The raw effect adapter keeps required money/status/calendar/currency/classification uncertainty unavailable instead of dropping malformed rows or treating quoted numbers as valid money. A valid reporting-expense override does not require damaged unused original/income/destination fields. Known neutral, excluded, unrelated and zero records preserve known totals. Historical archived wallets still provide required currency/kind; an absent legacy source reference permits the existing JPY fallback, whereas a required orphan or explicit unreadable currency cannot. Aggregation and conversion remain exact BigInteger with nullable results.

Category metadata for reading is separate from strict stored editor payloads. Direct child identity can still prove spending when only its parent relationship is unreadable; parent totals remain unavailable. Canonical-equivalent/Unicode-whitespace names match Swift grouping. Shared generated/card title comparison now handles decomposed Vietnamese/Japanese without changing stored title bytes; fullwidth English and halfwidth Japanese controls remain ordinary expenses, as verified by the Foundation probe.

Loading, wrong-owner emissions and failed reads withhold totals. Retry reads current Room rows; a failure after a valid snapshot clears the old amounts. Stored edits reload strict raw plan identity from the same snapshot. Existing strict editor category/transaction streams remain for mutations. The recent-category picker ignores unreadable recency dates instead of crashing, while budget money for the unplaceable expense remains unavailable.

This covers the personal budget reader. Conservative template/alias holds remain; independent usable fields of otherwise unreadable plans, broader continuity/import metadata, family budgets, Savings/Due read availability and actual Overview sections/config remain unfinished. No financial-domain/APK gate completion is implied.

## TDD and direct review

- Snapshot repository2/2 runtimeRED; actual Room2/2RED0.257s observed four mixed JPY16500/VND100 pairs during16 atomic writes and omitted malformed deletion. One-query producer: JVM2+28repository GREEN; actualRoom2/2GREEN0.265s.
- Raw expense baseline12 cases/8 intended failures2s; four known-money/neutral/unused controls passed. Added canonical-title control:13/9 failures2s. Native10/9 business failures59.546s; unchanged unused-field control passed. Native title1/1RED6.805s, expected0 actual7.
- Loaded-then-failed baseline1/1RED6.843s, expected unavailable actual7. Initial new native12/12GREEN22.207s after screen integration.
- Recent picker regression reproduced DateTimeParseException before date guard. Deletion review added malformed timestamp-string vector: focused unit1/1RED3s (expected unavailable actual0) before budget-only timestamp validation; legacy Overview default remains unchanged. Compiler/helper diagnostics and corrected random-ID fixture are not counted as business RED.
- Direct reference: Swift PlanningLogic244–383/936–1038/1291–1415; TransactionLogic1345–1455/1536–1560; TransactionGeneratedTitle104–134. Shared classification enumeration extracted unchanged except names/visibility; Overview wrappers preserve legacy identity policy. Foundation probe confirms title normalization boundaries. Final complete source/test patch SHA256 `5cb605d025faee8cf05b6d05cc8e80b1adfeb84e7ad3f136c67e18df619e95f8` reviewed; no independent whole-branch approval claimed.

## Final verification

Full Android host commands terminal0/BUILD SUCCESSFUL121s,110s after deletion fix,7s after native harness change: **1689JVM/162suites zero failures/errors/skips**, required AndroidTest compile/package, lint and main assembly. Swift **610** (4/137/469), contracts15entities, both strict localization generators, SQLite7/3/11, Room6schemas and whitespace passed.

The first native54 run had53pass/1calculator-open failure154.4s. Its captured bounds changed from y1383–1493 to y841–951 during IME relayout. The arithmetic/save fixture now calls the real button semantics action; it does not certify physical hit testing. The superseded old Overview run was explicitly stopped to rerun final packages; its process-crashed cancellation footer is not a passing result. Final native/visual/artifact results follow.

Logs `/tmp/mistia-budget-raw-spending-*`. All10writeflagsfalse; Room6/SwiftDataV11/iOS751unchanged. EmulatorAPI36ARM64transport13 only; no Samsung/live Supabase/production write/deploy/migration.


Final Room **2/2GREEN0.259s** and Planning **54/54GREEN177.166s**. All12 final en/vi/ja light/dark actual130% PNGs refreshed and inspected with complete glyph assertions. These verify financial fixture content; MainActivity/header/system-inset positioning and general hit targets remain separate UI work.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-budget-raw-spending-v121.apk|0c087a6811073f5de6bc4d14ee3f76f666f7ea623835e420bf54a7f1f56020fb|
|mistia-budget-raw-spending-test-v121.apk|9c7102130de6c22fca9679f178d0d75effcf59b80dc780993a4f7188573d0124|
|mistia-overview-budget-raw-spending-test-v121.apk|2a3bf5c475083964d9cae88a9b03de56f6d658fdc4b46bd98c4e07497f39c7af|
|mistia-budget-snapshot-room-test-v121.apk|b328b2f0761804d0cbb68db0ce1bc266570d0730a3762037ec449e266f7744b9|

Archives in ignored `android/build/outputs/apk2/2026-10-21/`; main20DEX/planning9/Overview9/database5, manifests inspected. All3 installed native test APK hashes match archives. Final Overview **126/126GREEN303.165s**. Main121 install-r preserved data; cold `Status: ok`, `LaunchState: COLD`,1646ms; installed version121/min26/target36 confirmed. Main installed SHA also matches archive. All four package hashes therefore match executed/installed artifacts.

Next: actual Overview budget watchlist from this same scoped reader, followed by due/investment/preparing/config sections and remaining APK1–4/RC work. Full goal remains active; no gate completion claim.
