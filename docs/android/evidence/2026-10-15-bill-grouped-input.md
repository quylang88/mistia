# Grouped bill amount input — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `ac2a7184`.

Recurring bill editor now groups raw minor integers while typing and when opening existing JPY/VND bills, matching Swift PlanningBillEditorSheet's MistiaCurrencyInputField. No storage/scaling/validation/cloud change: optional blank remains null, exact Long values survive, currency changes still clear incompatible input, and imported fractional currencies retain the existing Android decimal input semantics. Malformed punctuation/letters remain visible for validation instead of being silently stripped or reinterpreted. Extracted the existing installment grouping body into a small shared planning helper; installment behavior/tests remain unchanged.

Runtime TDD: five new bill-state cases produced four expected REDs; the imported USD decimal-control case already passed. Final16 bill-state cases plus complete planning JVM suite pass. Covers grouping >2^53 JPY/VND, existing bill presentation, blank/sign/zero/malformed/overflow handling, unchanged USD13.75→1375minor, owned saveable state and optional clearing. Actual API36 bill metadata workflow passes with an explicit grouped field assertion and exact persisted Long amount. Inspected/saved `2026-10-15-bill-grouped-input/bill-editor-light.png`; grouped amount fits the captured viewport. The screenshot is scrolled, so no full-screen visual parity claim.

Final **1375 JVM tests /131 suites**, zero failures/errors; Swift609, app lint/build, database/management/planning AndroidTest compile/database and planning test APK assembly, contract15, both localization checks, SQLite7/3/11 helpers and packaged database schemas1–6/bootstrap pass. Actual focused native workflow1pass in6.628seconds. Existing previous database122/planning33/management5 native checkpoints are not rerun wholesale for this unchanged accounting scope; full OS process-kill/Samsung/live-sync gates remain open. Direct self review compared the actual Swift field, groupedInput and raw-minor save parser. Imported non-JPY/VND Swift parity remains a documented separate audit gap. Independent review remains pending.

Logs `/tmp/mistia-bill-grouped-input-{red,focused,native,full,swift}.log`. Room6/SwiftData V11/remote15 unchanged; no Swift runtime/catalog/schema change.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-bill-grouped-input-v72.apk`, debug versionCode72: SHA256 `61ebb0e4e819187e20e93d89963b41d02bfe4e014c3ad74fc1ef6a532ad227d0`.

Executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-bill-grouped-input-test-v72.apk`: SHA256 `1d44737310a426b608e4b820e3c54da02843e13e02dabf24b0a51bb6dab9ef7c`.

Only emulator connected; all10 flagsfalse. No production writes/deploy/migration. Budget/savings monetary grouping, imported currency audit/settings, paid remote writes/undo/duplicate/source/legacy recovery/atomicity, fund usage/maintenance, pending card choice, APK3/4/RC and full device/visual/background/accessibility gates remain open. Goal remains active.
