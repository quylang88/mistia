# Grouped savings target/current input — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `a9e6ecef`.

Savings goal JPY/VND target/current fields now group thousands when typing and opening existing records, matching the two Swift PlanningSavingsGoalEditorSheet MistiaCurrencyInputField controls. Target remains positive; signed current and blank current→zero semantics, original target timestamp/identity, owned saveable state and linked-wallet/repository behavior remain intact. Fractional imported currencies retain existing decimal input semantics. Malformed text remains visible and overflow fails without unit conversion. Reuses the common planning grouping selector; no accounting/network/schema/catalog change.

Runtime TDD:4 new state cases produced3 intended failures, then all9 goal-state cases passed. Covers supported exact >2^53 target/signed current, existing-record grouping/date/identity, owned restoration/blank current and malformed/overflow/imported USD behavior. Actual API36 savings CRUD fixture asserts grouped target/current both before save and after reopening, verifies exact persisted values, edits/deletes and retains existing wallet/outbox assertions. Focused native1pass,8.536seconds. Complete planning JVM suite passes.

Final **1383 JVM tests /131 suites**, zero failures/errors; Swift609, app lint/build, database/management/planning AndroidTest compilation, database/planning test APK assembly, contract15, both localization checks, SQLite7/3/11 helpers, packaged schemas1–6/bootstrap and whitespace pass. Direct Swift self review compared actual target/current fields, groupedInput and raw-minor parsing; imported non-JPY/VND parity is still an explicit separate gap. Existing native database122/planning33/management5 checkpoints cover their recorded artifacts; changed savings fixture was rerun here. Independent/Samsung/full visual/background/accessibility/process-kill/live-sync evidence remains pending.

Logs `/tmp/mistia-goal-grouped-input-{red,focused,native,full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-goal-grouped-input-v74.apk`, debug versionCode74: SHA256 `76e255a2d246f146aeb901c7df799c6bb7ac21a4769a6a9f14a6de8344984958`.

Executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-goal-grouped-input-test-v74.apk`: SHA256 `9af63b6b2f03191e10e392ec1e0e91abe40aa87c4653c2a45d2f9dbb2ccca184`.

Only emulator connected; all10 flagsfalse; no production write/deploy/migration. Next native calculator parity, remaining input/settings audit, paid writes/undo/duplicate/source/legacy recovery/atomicity, fund usage/maintenance, pending card currency choice, APK3/4/RC and full device gates. Goal remains active.
