# Notification payment/top-up actions and immediate resolution — 2026-10-14

Native notification detail now routes bill payment-required/overdue rows to the
existing exact same-currency payment sheet, and automatic-payment failure rows to
the existing internal transfer editor with destination wallet preset only. Source,
amount and FX pairing remain user-entered/validated through the established
transaction workflow. Existing localized action hints distinguish pay and top-up.

Targets validate owner, resource/source identity, cycle, current bill/occurrences
and live wallet references. Historical notification amount/currency is not used
to write money. Paid/skipped/archived/deleted/paused recurring cycles refuse a new
payment target. One-time bills retain scheduler parity: a legacy pause flag does
not block manual payment. Malformed auto-failure cycle metadata refuses routing.
Owner-keyed wrappers load current data and cancel their scopes on owner change;
the root action key survives recreation while waiting for the owner snapshot.

Room resolves matching actionable cycle notifications inside payment and skip
transactions; local pause/archive/delete bill writes resolve the bill's actionable
notifications in their transaction. Success records and other cycles remain intact.
Undo/tombstone/pending/foreign writes do not falsely resolve active reminders.
These paths are atomic with record/outbox changes; maintenance remains a fallback
for remote changes. No cloud write gate changed.

Verification:

- Action routing initial runtime2 REDs -> GREEN, malformed top-up cycle RED ->
  GREEN and one-time legacy pause RED -> GREEN;7 action cases.
- Transfer preset runtimeRED -> GREEN: only destination set, internal-transfer
  mode, no invented source or amount. Terminal resolution runtimeRED -> GREEN,
  with undo/pending/foreign/other-cycle refusal coverage;2 cases.
- Full Android798 JVM/86 suites,0 failures/errors; database/planning/notification
  AndroidTest compile, lintDebug and assembleDebug pass (733 tasks).
- Room immediate-resolution and injected rollback tests compile only, each covers
  pay/skip/pause. Compose detail callback test compiles only; screen fixture uses
  relative past time to avoid device clock/date dependence. No runtime UI claims.
- Swift Planning53, contracts15, both l10n checks, SQLite notification3/outbox7 and
  diff check pass. Direct comparison: NotificationCenterView.handleRowTap,
  makeTransferTarget, opensDuePaymentSheet and recurring resolveNotifications.
- ADB empty; no Samsung/emulator/visual/live Supabase/production write QA. Nine
  flagsfalse; Room schema5. Independent review pending due usage limit; self-review
  completed. Full APK1–4 parity remains incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-notification-bill-actions-v39.apk` (vn.com.quyln.mistia.debug, versionCode39).
SHA256: `01360cf701dfccbe8fb267029c8e2041313901eea0adef98d64dcbf77a7ded9a`.

Next: reminder preferences and guarded foreground/background maintenance, then
remaining card/installment/settings/family/investment slices and visual/device QA.
