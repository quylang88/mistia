# Truthful raw cash inputs for Overview assets - slice112

2026-10-20; branch `codex/android-apk2-4-parity`, base `a59822814dcb629f3ea4d5129f650c63da24001e`. APK1-4/RC remains active. Final whole-suite/editor/installed identity results are recorded below only after execution.

## Behavior and direct Swift review

Overview assets now reads raw cash-specific inputs instead of the reporting filter. An unreadable eligible cash opening, required posted balance leg, required wallet reference or unknown cash eligibility holds the complete assets total. Strict JSON integer Long amounts reject numeric strings/fractions/overflow; known foreign, deleted, archived, credit, draft or unselected components cannot poison active owned cash. Envelope/entity/canonical UUID/body identity are checked before availability, with absent/null legacy identity accepted only from the trusted matching envelope. Explicit mismatches are excluded. Invalid tombstone/archive shapes hold potential cash.

Cash admission reads only fields used by wallet balances. Invalid calendar data and unused reporting/destination fields no longer discard a valid cash leg; future posted entries still count. Family direction, debt lend/repay/borrow/collect, shared principal neutrality and resale cost (nonnegative reporting expense, absent cost zero) preserve Swift behavior. Only required owned balance legs are validated. Credit opening/liability is excluded, while readable owned credit currency metadata remains usable for incoming legacy pairs even if its unused opening is unreadable.

A missing internal-transfer destination amount may reuse source minor units only when nonzero source/destination currency identity is established. Cross-currency missing pairing is unavailable instead of copying raw source minors; explicit paired destination and zero/foreign-destination controls remain exact. The pure typed assets entry point has the same pairing guard. Present malformed source-currency JSON cannot silently turn into an absent legacy code for a required incoming fallback. Unused malformed source currency does not poison a readable explicit destination pair. This narrow guard does not certify all imported source/wallet currency mismatch cases.

Screen retains111 exact BigInteger aggregation, final-wallet-once rounding, inventory dependency, localized availability hint/stateDescription and adaptive formatting. Owner changes clear prior private composition; raw repair/archive/status/FX changes recompute. No display operation writes financial data or outbox. Reporting/month/week/day/category admission is deliberately unchanged here and remains mandatory next work; its raw omission issues are not certified by this cash fix.

Direct Swift references: `OverviewLogic.swift`407-455; `TransactionLogic.swift`2035-2153 (posted/nonarchived wallet index, source/destination/family/debt legs),1495-1534 (shared/resale principal and purchase cost). Missing optional subtype/intent is neutral as Swift's optional switch. User financial correctness requires conservative unavailable values for malformed required inputs and unpaired currencies, rather than reproducing incorrect partial sums or Swift raw-minor fallback. No schema, persistence, cloud or iOS changes in112.

## Actual TDD and checks

Initial feature7 cases:6 actual runtime RED1sec against the old-behavior wrapper (excluded/unselected control passed); extended11 cases:10 runtime RED1sec. Pure destination3 cases:1 actual business RED1sec (901 instead of unavailable), same-ISO/explicit-pair/zero/foreign controls passed. Native baseline7 cases all intended business RED45.312sec on111 production; then7 GREEN14.99sec. No compile-only RED is claimed.

Parent inspection found credit currency metadata lost by excluding its unreadable unused opening: supplemental12th feature case1/12 runtime RED1sec and dedicated native1/1 money RED6.853sec. Separate fixture packaging followed the expected failed unit task, so a stale APK was never installed as baseline proof. Metadata-only credit snapshot repair produced110 focused JVM/12 suites GREEN2sec and15 focused native GREEN32.506sec (new8 plus older7 assets tests). Existing malformed-cash goldens migrated to unavailable -> explicit raw repair, preserving no-write assertions and independent inventory currency coverage.

Fresh independent review was requested through existing reviewer `review_overview_monthly109`, immutable initial patch SHA256 `2d95e72a38c594c375970ba5126ae4c62b0baf9116c978f03c8d1176e43ce335`. The agent failed before findings due to its usage limit. There is no successful independent112 review; do not present this request as approval. Parent performed the complete diff/direct Swift review; final corrected Android patch SHA256 `7afa393649a33b0e925df11873ef8127ebcb95bf0aeec56ed4d91e85f6aebe2f`. It found the malformed explicit source-currency fallback above:13th feature case actual1/13 RED (expected null/actual20); extended credit native case actual1/1 RED6.676sec. One additional guard fixed it;13 feature cases and final15 focused native GREEN29.352sec. Explicit paired destination monetary control117 retained. First full87 GREEN183.042sec predates this last guard and is not final proof.

Final corrected host:1589 JVM tests/153 suites, zero failures/errors; required Room/management/planning/overview/transactions/settings AndroidTest compile/package, lint/build GREEN42sec (initial full host1588/153 GREEN73sec before final guard). Swift610 (4 contract/137 data/469 core), contracts15, both strict localization checks, SQLite7/3/11, Room6 assets and whitespace passed. Final packages min26/target36/version112, manifests and main20/Overview9/transaction11 DEX entries inspected; all10 generated write flags false.

Six settled actual1.3 en/vi/ja light/dark PNGs are in `overview-raw-cash-2026-10-20/`; localized hint and full-glyph repair2MAX are asserted in native tests. Final whole-suite refresh/inspection and installed identities are recorded in the final section after completion. Broader TalkBack/all locales/Samsung, cross-domain loading/atomicity, reporting raw omissions/import/global planning, category visual minors/day Event badge/older sheet actual-font audit, investment/family/event/receipt/device/RC and final independent whole-branch review remain required.

API36 ARM64 emulator only. Original emulator disappeared after the first completed87 test run (ADB empty and no qemu process); replacement AVD started only after verifying terminal absence, boot completed, transport12. Earlier transport11 does not remain assumed. No Samsung, live Supabase/production write/deploy/migration verification. Room6/SwiftDataV11/iOS751 unchanged. No full-goal completion claim.

## Final artifact identity

Ignored archives `android/build/outputs/apk2/2026-10-20/`; `mistia-overview-raw-cash-v112-SHA256SUMS.txt`, badging and output metadata saved.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-raw-cash-v112.apk|b3afa2d7adca8fef4407c869340b9924f37dcafe9abee6aab18386e21aee3b69|
|mistia-overview-raw-cash-test-v112.apk|ebd8802575291eb735b018e50dde53b4aa425388864cc30179b86419bcf007a1|
|mistia-overview-raw-cash-transaction-test-v112.apk|c80718c2a6db14fe78ee7f4bc5bfe95d0c9ebd231b3037748fd4b9cf7ee7ccf0|

Logs `/tmp/mistia-overview-asset-inputs-*` distinguish initial unit/native RED/GREEN, supplemental credit and source-currency RED, corrected final whole-suite/editor/host, Swift and cold smoke. ADB command success alone never substitutes for actual JUnit footers.

## Final executed verification

Final corrected whole Overview runner passed **87/87 in165.682sec**, with all eight raw-cash and seven older assets cases; actual recent/day-to-stored-editor integrations passed **2/2 in8.149sec**, exact Room/outbox assertions retained. All six final-package actual130% PNGs were pulled again and inspected complete in en/vi/ja light/dark. Main112 installed with `adb install -r` preserving data; cold MainActivity Status:ok,1014ms, version112/min26/target36 confirmed. All three installed base.apk SHA256 values match the final archives above. Only emulator transport12 is connected; no Samsung claim.

Review ledger: no additional parent diff/Swift findings after the source-currency guard. Absent optional neutral subtype/intent, shared-principal early exclusion, missing resale cost zero and unused-field independence intentionally preserve Swift cash semantics. Broader malformed reporting/calendar/classifier/import/source-wallet and loading issues remain mandatory; no false closure based on cash tests. Independent reviewer did not execute; whole-branch independent review remains outstanding. No source edits after final host/native/editor/artifact verification. Continue next slice immediately.
