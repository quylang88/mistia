# Native bill editor draft foundation — 2026-10-13

RecurringBillEditorState bridges saveable form inputs to the existing typed
RecurringBillDraft. Covers optional null amount, exact signed Long parsing,
existing currency/edit identity, local-calendar one-time dates, recurring
cross-month auto-pay choices, moving payment start with implicit due date and
clamped auto-pay, frequency and account-scoped save/restore.

Direct Swift review: PlanningEditors.PlanningBillDraft, normalizeAutoPayDraft,
normalizeOneTimePaymentStartChange, normalizedBillSchedule and save. Defaults
match day10, recurring, blank optional amount, current-month first schedule and
today's one-time dates. Explicit save normalizes local day. Imported recurring
frequency24 remains editable: Swift initializes max(frequency,1), while its UI
stepper only offers1–12. Android state preserves this imported value too.

TDD: API compile RED, six runtime failures from the missing state conversion,
GREEN6, then legacy frequency24 runtime RED and GREEN8 after parity correction.
Final Android full testDebugUnitTest:568 tests/72 suites, zero failures. Room/UI
instrumented Kotlin compile, lintDebug and assembleDebug pass (724tasks/11s).
Swift PlanningLogic52 pass, contract15 and Android/strict Swift localization
checks pass. git diff --check passes. ADB empty; no device/UI runtime claim.

This slice is a tested form state foundation. Sheet, native bill list/navigation,
category quick picker, lifecycle controls and UI workflow are next. No network,
startup/bootstrap or financial mutation behavior changed. VersionCode15,
all eight cloud-write gates remain false. No production request or deployment.
Independent read-only reviewer found no actionable P1/P2 in this bounded
state foundation after direct Swift comparison; it did not run Gradle or verify
UI/device behavior. Full APK1–4 goal remains active and incomplete.
