# Persistent recurring-bill notification batch — 2026-10-14

Maintenance can now persist reminder/failure notifications through production
AppModule configuration using existing VI/EN/JA strings and exact amount/local
date formatting. Currency mismatch, missing amount/wallet, insufficient balance/
card credit and investment confirmation failures get appropriate localized copy.
No raw technical exception text is shown. Success notifications remain atomic
with money in the preceding slice.

The planner recomputes current reminder events from fresh owned raw bill/cycle
rows. A reported auto failure is eligible only while its exact original event
still matches a fresh pending auto event. Paid/skipped cycles, paused/archived/
deleted/missing bills and changed schedules with no payable cycle resolve old
local actionable rows while preserving success/history and existing read state.
Structured action metadata uses real bill/month/wallet/current currency and nulls.

Room captures bills, occurrences and notifications in one snapshot. Commit checks
full raw row equality (including same-clock changes) and read state inside one
transaction before notification replacement. The repository retries up to3 times
from fresh snapshots without rerunning money payments. Cancellation propagates.

Verification:

- Model runtime5 REDs -> GREEN; stale-report test remains green. Additional schedule
  change runtimeRED -> GREEN and full raw/read/cycle snapshot CAS regression.
- Three integrated real-local repository cases pass: durable repeated reminder,
  manual payment racing batch (retry drops stale alert), read racing batch (retry
  preserves read). Exact >2^53 amount body and owner/viewer guards are covered.
- New Room bill/cycle/read-race test compiles only. No Android runtime claims.
- Full Android780 JVM/83 suites,0 failures/errors; Room/planning AndroidTest compile,
  lintDebug and assembleDebug pass (724 tasks). Swift Notification13, contracts15,
  both l10n checks, actual SQLite notification3/outbox7 methods and diff check pass.
- Direct Swift comparison: MistiaRecurringBillMaintenance.run/upsertNotification/
  resolveNotifications and MistiaRecurringBillNotificationBatch.upsert. Schedule
  changes additionally resolve alerts for cycles that are no longer payable.
- Independent review pending (reviewer usage limit); self-review done. ADB empty;
  no device/live Supabase/production writes. Nine flagsfalse; Room schema5.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-notification-batch-v37.apk` (vn.com.quyln.mistia.debug, versionCode37).
SHA256: `d45c480e5fc3c20b6a9c9f241dc9f98a10a9318f6e28d2a94b88af4c603c0ea0`.

Full APK1–4 incomplete. Next: native grouped notification center/read actions,
manual-pay/skip immediate resolution, reminder preferences and foreground/
background scheduling with current-account cancellation.
