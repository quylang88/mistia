# APK 2 native savings workflow — 2026-10-13

Native planning tabs, goal summary, progress rows, monthly required amount,
target date, six goal icon tokens/colors matching FinanceIconRegistry, native
name/target/current/date/icon/wallet form and delete confirmation. Existing
currency immutable; new goals use current app default JPY (currency settings
remain RC work). Exact decimal input, signed current amount, owner-scoped saved
draft/navigation snapshot, captured edit identity, unsaved dismiss guard and
failed-save retention. Date picker uses Material UTC date selection converted
to local calendar; an unchanged original target instant remains lossless.
Linked-wallet list includes original preferred archived wallet, retains Swift
sortOrder/createdAt order and permits credit cards; repository enforces scope.

Direct references: GoalsTabContent/PlanningGoalRowView/PlanningGoalEditorSheet;
PlanningGoalDraft; PlanningLogic goalRows/goalSummary/monthsRemaining;
FinanceIconRegistry.goalOptions/descriptors; WalletPickerAccessLogic.
Family subject/roles/remote permissions remain APK3 work. Budget/savings tab
workflows are implemented; bills/installments tabs still show pending counts.
Pixel/interaction parity is not claimed without emulator/physical visual QA.

TDD: missing state/summary APIs observed RED. Five state tests cover exact
input/signed current/overflow, inclusive local date representation, account
restoration and captured edit snapshot. Summary tests cover FX, nearest goal,
missing rates, empty collection and exact signed overflow cancellation.
Local review discovered reporting conversion overflow became zero through the
transaction Long conversion API. Budget and savings regressions both failed
before a shared reporting-only BigInteger conversion fix. Intermediate sums
remain exact; only final display boundaries clamp to Long. Ledger transaction
conversion/writes and original cloud values are unchanged. Other review fixes:
wallet ordering, goal icon label and right-aligned monthly contribution.
No independent final reviewer approval is claimed while service is limited.

Four Compose tests compile (two budget, two savings): Room-backed create/edit/
delete/outbox and dark 1.3 font failure retention/discard guard. Screenshot hooks
exist but none executed: ADB empty. Separate file-backed savings Room reopen
test also remains unexecuted. No emulator/Samsung savings/UI claim.

Validation: full Android testDebugUnitTest, Room test compilation, planning test APK assembly,
lintDebug and assembleDebug passed, 742 tasks/11s on final run;
442 JVM tests across 61 suites, zero failures.
52 focused Swift PlanningLogic tests pass. Contract15, Android and strict Swift
localization generation and git diff --check pass. All seven write flags false,
versionCode9. No Supabase write, migration/deployment or auth configuration change.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-savings-ui-v9.apk
SHA-256: d037fc9e1c92ecae3dbd352ba8672a21782fbd5669fb48021c429eb0f88299aa

Continue recurring bills, installments, statements/due maintenance and APK3–4.
Final physical/UI verification and primary currency settings remain explicit.
