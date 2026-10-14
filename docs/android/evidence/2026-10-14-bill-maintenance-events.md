# Recurring bill maintenance event planner — 2026-10-14

Pure `recurringBillMaintenanceEvents` matches the pending-cycle/date pass in
MistiaRecurringBillMaintenance.swift: previous and current local cycle months,
owner-scoped live/unpaused/unarchived bills, pending occurrences only, normalized
auto-pay day, payment-start/deadline reminder and daily overdue resurfacing.
Exact amount snapshots remain Long. Payment/overdue keys match Swift. The local
auto-pay attempt key is an intent identifier only, not a persisted success alert.
One-time bills are considered in their actual payment cycle. Terminal paid/skipped
cycles do not create intents. No money or notification is written by this model.

Verification:

- Runtime RED:5 tests /4 expected failures with empty planner; implementation GREEN.
  Tests cover previous-cycle deadline across month, normalized auto-pay/start,
  local midnight overdue key changes, exact >2^53 amount, terminal/paused/archive/
  deleted/viewer scope and one-time previous-month/older-month exclusion.
- Full Android752 JVM/81 suites,0 failures/errors; Room/planning AndroidTest
  compilation, lintDebug and assembleDebug pass (724 tasks).
- Xcode Swift Planning53 tests pass, contracts15, both localization checks,
  actual SQLite/schema7 methods, git diff --check pass.
- Independent reviewer still unavailable due usage limit; self-review only for
  this slice. Independent review remains outstanding for startup and this planner.
- ADB empty; no emulator/Samsung/live Supabase or production writes. Nine flags
  false, Room schema4. Full APK1–4 remains incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-maintenance-events-v32.apk` (vn.com.quyln.mistia.debug, versionCode32).
SHA256: `4fda33fe35f9f24d7cabcf111569ac2ff1afd7ca0e34b647786a964c0b272857`.

Next: execute auto-pay through atomic money repository with current schedule/date,
wallet/currency/balance/investment guards, then persistent notification batching
and native foreground/background integration. These intents alone are not
operational auto-pay or notification delivery.
