# APK 2 offline savings goals — 2026-10-13

Typed owner-scoped observe/save/delete through atomic Room record+outbox commit.
Matched PlanningGoalEditor save/deleteGoal/nextSortOrder: trim required name,
positive target, manually saved current amount, linked-wallet nullable clear,
existing currency/created timestamp/version preservation, active goal sort order
and tombstone deletion. No wallet movement is generated from goal edits.
Archived preferred wallet can remain linked during editing; new archived,
foreign, deleted or forged-payload wallet links fail. Credit cards are not
excluded by this domain, matching availableWallets(excludesCreditCards:false).
Stale/deleted edit IDs fail instead of recreating records. Foreign payload owner
or mismatched identity is rejected even under a viewer envelope. Canonical
UUID identity is preserved across uppercase input and edit lookup.

TDD observed missing API RED; nine focused repository tests now pass. UUID
case regression failed before normalization fix. Atomic failure and coroutine
cancellation tested; signed amount/version precision, explicit clear, deletion,
archived preferred dependency, scope, stale edits and sort overflow covered.
Room instrumentation compiles a file-backed database close/reopen test for
record+outbox preservation, account isolation and tombstone replacement; it has
NOT run because no ADB device is connected. Shared atomic Room batch rollback
was executed on emulator in preceding budget evidence, not claimed as savings
execution. Direct local review against Swift completed; no independent reviewer
approval is claimed while review service is usage-limited.

Validation: 401 JVM tests across 58 suites; full Android testDebugUnitTest,
database Android-test APK assembly, lintDebug and assembleDebug passed,
731 tasks/42s. 52 Swift PlanningLogic tests, 15-entity contract, Android and
strict Swift localization generation plus diff checks passed.
VersionCode 7; all six write flags false. No emulator/Samsung savings execution,
Supabase write, migration/deployment or auth/OAuth change.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-savings-offline-v7.apk
SHA-256: eef03cf83d9f94f304cb30c67c008767ea07f3cf0df84ade1a36d2d4f1423cf4

Next: separately gated savings push, then native rows/editor/summary. Remaining
APK 2–4 domains and final physical/device/UI verification remain incomplete.
