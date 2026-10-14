# Atomic automatic-payment success notification — 2026-10-14

AppModule supplies existing VI/EN/JA resource strings for the automatic expense
title, success title and exact currency-formatted success body. The provider is
passed to both direct payment and maintenance payment repositories. Automatic
payment creates a local success record with Swift's stable bill/month key and
structured due action metadata using current configured bill/wallet values.
Manual payments keep their normal title and no success companion. Headless callers
without a presentation provider retain money-only behavior; production AppModule
always provides one. Reminder preference handling/native scheduling is still open.

The success record travels as an optional companion in BillMoneySnapshot.
Validation requires enabled/unpaused auto-pay, matching owner/bill/month/success
kind/source, configured wallet and currency, and live PAID occurrence writes.
Room saves expense/occurrence/outbox and this local notification inside the same
transaction. It reads existing notification state within that transaction and
upserts without resetting a user's read state. A notification insert failure
therefore rolls back the money batch. No notification enters the cloud outbox.

Verification:

- Runtime RED for missing localized title/companion -> GREEN. The test inspects
  the same money snapshot passed to commit and validates success key/metadata.
- Runtime RED for disabled auto-pay companion accepted at the transaction boundary
  -> GREEN. Foreign owner companion also rejects before writes.
- Two new Room tests compile only: money+notification reopen/repeat suppression;
  injected notification insert failure rolls back all records and outboxes. No
  Android runtime transaction execution is claimed without a device.
- Full Android769 JVM/82 suites,0 failures/errors; Room/planning AndroidTest compile,
  lintDebug and assembleDebug pass (724 tasks). Swift Planning53, contracts15,
  both l10n checks, actual SQLite notification3/outbox7 methods and diff check pass.
- ADB empty; no emulator/Samsung/live Supabase/production writes. Nine flagsfalse,
  Room schema5. Independent review remains pending due usage limit; self/direct
  Swift comparison against run/attemptAutoPay and notification batch completed.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-atomic-auto-notification-v36.apk` (vn.com.quyln.mistia.debug, versionCode36).
SHA256: `c6fe714e4c01f0288c4e9d42752e59ae038a731aee1179307bf4f31106c8f518`.

Full APK1–4 remains incomplete. Next: persistent reminder/failure generation and
paid/skipped/paused notification resolution, native notification center and
foreground/background hooks with account cancellation and preferences.
