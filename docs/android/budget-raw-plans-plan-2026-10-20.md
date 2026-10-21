# Preserve unavailable raw budget plans — slice120

Base `bc8ce5fa`, branch `codex/android-apk2-4-parity`; main119 installed and final checks recorded. Full APK1–4/RC remains active. No agents, production writes, deployment or schema change.

The strict budget persistence parser can omit unreadable required money/month/eligibility before the read projection sees it. A damaged newest template can revive an older known limit; an only damaged plan can appear as zero/no budgets. Add a consumer-specific raw projection and read-only repository stream preserving uncertain body deletion after owner/identity checks. Retain strict persistence and editor parsers. Required unknown plan/read loading holds the whole budget summary and branch list, with the existing generic unavailable hint; never claim no budgets or expose an older stable row until repair. Known archived/deleted/foreign/future plans are neutral. Valid exact typed projection remains119.

Start with runtime JVM failures through an adapter equivalent to current strict-mapNotNull intake and actual Room PlanningScreen failures before wiring the new reader. Test numeric Long money, latest-invalid continuity, month/eligibility, loading, known exclusion controls, read-only repair and both owner/outbox boundaries. Verify the raw repository API cannot filter malformed deletion or leak foreign/body-mismatched records. Default repository adapter retains existing fake compatibility; production must override with owner-scoped raw rows. No sanitized financial/editor placeholders.

This is a conservative whole-plan availability guard. It does not certify full raw ledger/wallet/category completeness, independently usable fields of an otherwise unreadable template, atomic read sets, family budgets, imported continuity normalization or Savings/Due availability. Further work must reduce unnecessary holds without reintroducing false known totals. Swift planning active/continuity/spending/branch behavior reviewed directly in119; Swift currency normalization174 also only supportsJPY/VND (do not claim fullISO continuity parity).

After focused GREEN: direct diff/Swift review, fix findings, full JVM/lint/build and appropriate native budget/editor/currency regressions, Swift610/contracts/localization/SQLite/Room assets, final APK120/version/install-r/cold/archive-installed SHA, evidence/progress/separate local commit, then continue remaining local scope.


## Task 1: Preserve raw template availability and exact stored editor routes

Spec: `/Users/quyln/.codex/attachments/14a5e42d-74ef-4419-b511-5b60da3154aa/pasted-text-1.txt` and its full original TXT; existing user money decisions remain binding. Base `bc8ce5fa`.

- [x] Reproduce baseline intake: eight JVM cases/six business failures, raw repository one failure, real Room native three failures.
- [x] Implement owner-scoped raw rows, guarded projection and loading availability; initial JVM8+repository28/native3 GREEN.
- [x] Review findings: unplaceable/nonpositive plans, foreign duplicate ordering and delayed typed-stream editor route; JVM11/three failures and native6/three failures reproduced before fixes.
- [x] Implement the reviewed guards and strict raw stored editor reload; focused build terminal0/BUILD SUCCESSFUL3s.
- [x] Run final new native6 and focused budget/editor/calculator/currency regressions. Actual6GREEN9.826s and42GREEN166.223s. Expected: actual `OK (6 tests)` and `OK (42 tests)` footers, no record/outbox mutation from reads.
- [x] Review final Swift/diff behavior and fix important findings with RED→GREEN; positive-limit guard matches PlanningEditors325, source/template/strict editor identity reviewed.
- [x] Run the full JVM suite, Room/feature AndroidTest compilation, lint/build, Swift, contracts and localization/SQLite/assets checks. Actual1673/160suites zero failure/error/skip; host144s,Swift610 and scripts GREEN on2026-10-21. Expected: all commands exit0, zero test failures/errors/skips; inspect actual counts.
- [x] Archive APK120/main+planning test, verify version/manifest/DEX/SHA, install-r/cold and compare installed checksums. Expected: Statusok/version120 and exact archive matches; emulator-only evidence if Samsung remains absent.
- [x] Update evidence/progress and stage verified slice. Commit/task-done completion is recorded in git and this plan ledger, then remaining APK1–4/RC work continues.

Final task verification command: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home android/gradlew -p android testDebugUnitTest :core:database:compileDebugAndroidTestKotlin :core:database:assembleDebugAndroidTest :feature:management:compileDebugAndroidTestKotlin :feature:planning:assembleDebugAndroidTest :feature:overview:compileDebugAndroidTestKotlin :feature:transactions:compileDebugAndroidTestKotlin :feature:settings:compileDebugAndroidTestKotlin :app:lintDebug :app:assembleDebug --max-workers=1`.
