# Truthful raw cash inputs for Overview assets - slice112

Goal: close the upstream raw-cash omission path for the complete available-assets hero, building on111 exact/nullable aggregation. Full APK1-4/RC remains the objective; reporting/day/category raw-input issues are subsequent mandatory work, not waived.
Base a59822814dcb629f3ea4d5129f650c63da24001e on codex/android-apk2-4-parity. Main111 installed and verified. User authorizes local TDD/review/check/evidence/independent commit and immediate continuation. No new approval pause or checkout relocation.

## Design

Extract internal overviewAssetBalance(owner, rawRecords, rawWallets, currency, rates, inventoryCost, inventoryCurrency):BigInteger? at the existing feature admission boundary. First provide a behavior-preserving wrapper around current overviewFinancialInputs/overviewTotalAssets solely to compile business-value baseline tests, recording that no new behavior is implemented. Then replace its admission with cash-specific validation, and route Screen assets through it. Keep existing monthly/week/day/category intake unchanged in112; its omissions remain the next explicit audit.

Owned active noncredit wallets must have readable strict numeric Long openings. An eligible unreadable opening/unknown cash eligibility holds the whole assets value; known foreign/deleted/archived/credit wallets do not poison it. Currency conversion/zero semantics remain111. Respect envelope/payload owner/id identity, accepting absent legacy identity only from the matching trusted envelope and rejecting explicit mismatches before considering availability.

Cash transaction validation follows required balance legs, not unrelated reporting fields or calendar data: known posted/nonarchived owned records only; unresolved eligibility/required money for a potentially included wallet holds the whole total. Amounts must be integer JSON numbers in Long range, never numeric strings/default0. A missing/unselected or known foreign wallet leg cannot affect owned balances and does not poison them. Preserve debt/family/shared/resale branches; validate reporting_expense only when resale cash actually uses it. Invalid dates and unused reporting/destination metadata must not drop a known cash leg, since cash balance includes all posted dates. Reporting availability for those rows remains separate subsequent work.

Internal transfers use explicit readable destination minor units when required. Missing destination amount may reuse source amount only when source/destination currency identity is established; cross-currency missing destination is unavailable, never raw source minors in the destination wallet. Add the same safeguard to the pure assets function so direct typed consumers cannot bypass it. Imported source/wallet currency mismatches and wider classifier/wire audits stay explicitly mandatory if not resolved here.

Screen reuses111 asset emdash/hint/stateDescription and owner/live-rate/metadata/position behavior. No writes, storage/schema/remote changes; all10flagsfalse, Room6/SwiftDataV11/iOS751 unchanged. Version112 after implementation only. Preserve actual editor/weekly/day/category flow and financial/outbox invariants.

## Review focus

- No unreadable eligible cash component silently omitted, no default0/coerced numeric strings, no foreign/irrelevant component poisoning.
- Consumer-specific required legs preserve valid cash despite unrelated invalid dates/reporting fields; resale/debt/shared/family branches remain Swift-compatible.
- Explicit destination amount pairing and same-ISO fallback, exact overflow/rounding/cancellation from111 retained.
- Owner/envelope/tombstone/archive/status parsing, live raw repair/archive/owner replacement, no Room/outbox mutations.
- Full financial reporting/raw/import/classifier/flow-loading audits not certified by this cash-specific slice; final native/editor/APK identity and localized actual font checks remain required.

Direct references: SwiftOverview407-455, Transaction wallet-balance index and family/debt/resale cash helpers; verify exact source lines during implementation. User financial correctness intentionally corrects incomplete raw sums, not Swift overflow defects.

## Task 1 - complete raw cash assets flow

- [x] Add feature JVM business-value tests using the old-behavior wrapper; actual runtime RED for malformed eligible openings/amounts, strict number shapes, irrelevant clock/reporting fields, role-dependent legs, owner/zero/ineligible exclusions. Add pure-model actual RED for missing cross-currency destination amount, before fixes.
- [x] Native baseline on111 with malformed cash opening/posted leg, live repair/status/archive/owner, irrelevant fields and cross-destination pairing, unchanged raw rows/outbox and actual font/localized hint. Do not implement new behavior before actual baseline proof.
- [x] Minimal cash-specific admission/whole-value availability and pure destination guard; migrate old malformed-cash goldens to truthful results. Focused JVM and native GREEN.
- [x] Parent read-only diff/direct Swift comparison; independent request failed due to reviewer usage limit, recorded as outstanding (not approval). Source-currency finding fixed after actual RED; final checks and explicit rulings recorded.
- [x] Full JVM/AndroidTest compile/package/lint/build/Swift/contracts/l10n/SQLite/Room assets; whole Overview native and actual2editor integrations. Final artifact metadata/checksums/executed install-r/cold smoke, evidence/progress and independent112 commit. Continue reporting/raw/Recent/import/global planning and remaining APK1-4/RC.

## Review execution status

The fresh independent review was requested on complete immutable patch SHA256 2d95e72a38c594c375970ba5126ae4c62b0baf9116c978f03c8d1176e43ce335. The existing reviewer failed before producing findings because its usage limit was reached. This is not a successful independent review. Parent direct diff/Swift review continues; independent review remains outstanding for final branch audit, not a reason to stop other authorized local work. Parent identified malformed explicit source-currency JSON falling through into legacy wallet pairing; a13th feature JVM case actually failed (expectednull/actual20), and the existing credit native case was extended and actually failed at the new unavailable assertion in6.676sec. One cash-admission fix holds nonzero missing-destination pair when present explicit source currency has invalid wire type. Explicit paired destination remains independent of unused source code; absent/JsonNull legacy source and zero keep existing behavior.13 feature JVM cases and final15 focused native passed29.352sec after the fix; full corrected host/whole87/editor2 verification is in progress.

Final112:1589JVM/153suites, corrected87OverviewGREEN165.682sec, actual2editorGREEN8.149sec; finalhost42sec, Swift610/scripts pass. Six final actual130% en/vi/ja lightdark images refreshed/inspected. Main112 install-r/coldStatusok1014ms/version112 and all3installed/archiveSHAs matched. Evidence docs/android/evidence/2026-10-20-overview-raw-cash.md. Independent review unavailable as recorded. No blocker to continued authorized local development.
