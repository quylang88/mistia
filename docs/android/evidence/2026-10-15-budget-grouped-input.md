# Grouped exact budget input — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `761fc20d`.

Budget JPY/VND input now groups thousands while typing and when opening an existing budget, matching Swift PlanningBudgetEditorSheet's MistiaCurrencyInputField. Existing positive amount parsing, exact minor units, month/identity/rollover semantics, single-currency branch inheritance and input clearing on currency changes remain intact. Fractional imported currencies retain existing Android decimal parsing/display behavior; their broader Swift parity remains a separate audit gap. Malformed/overflow inputs stay visible and fail validation. Shared the supported-currency grouping selector with bills; installment's grouping body is unchanged. No accounting/repository/network/schema change.

Runtime TDD:4 new state cases produced3 intended REDs (fractional-import control already passed), then all10 budget-state cases passed. Covers exact >2^53 JPY/VND typing, branch clear, owner-scoped restore, invalid/zero/negative/overflow, imported USD13.75→1375minor and grouped existing budget/source month/identity. Actual API36 budget CRUD fixture now creates9007199254740993minor, asserts grouped input and persisted exact Long, reopens grouped, edits600 and deletes with the expected outbox tombstone. Native focused1pass,8.509seconds. No assertions were removed. Existing whole planning JVM suite passes after common helper extraction.

Final **1379 JVM tests /131 suites**, zero failures/errors; Swift609, app lint/build, database/management/planning AndroidTest compilation, database/planning test APK assembly, contract15, both localization checks, SQLite7/3/11 helpers and packaged schemas1–6/bootstrap pass. Whitespace check found and removed one trailing blank line after helper relocation. Direct Swift review compared PlanningBudgetEditorSheet and KeyboardModifiers.MistiaCurrencyInputField, including the discovery of its still-missing Android calculator action. Calculator parity is queued as a separate functional slice. Independent review and full Samsung/visual/background/accessibility gates remain pending. Existing database122/planning33/management5 emulator checkpoints describe their exact earlier artifacts; only the changed budget workflow was rerun here.

Logs `/tmp/mistia-budget-grouped-input-{red,focused,native,full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-budget-grouped-input-v73.apk`, debug versionCode73: SHA256 `57c634750e6a6126416788365f4224de714dd90833bf9d700cacffe476a3c25a`.

Executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-budget-grouped-input-test-v73.apk`: SHA256 `515b584aa1067a1cccb360109c023082c900e87e9533a37a65a0cffdaeb9cd98`.

Only emulator connected; all10 flagsfalse; no production writes/deploy/migration. Savings grouping, calculator/input/settings parity, paid writes/undo/duplicate/source/legacy recovery/atomicity, fund usage/maintenance, pending card choice and full APK1–4/RC remain unfinished. Goal stays active.
