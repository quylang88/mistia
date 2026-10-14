# Local recurring bill maintenance executor — 2026-10-14

FinanceRepository.maintainRecurringBills now scans owned bill/occurrence snapshots,
plans previous/current cycle events and executes automatic payment intents through
the existing atomic money repository using automatic=true. There are no amount or
wallet overrides. The payment boundary rechecks current schedule, enabled/pause,
currency, amount, balances/card limits, investment protection and full dependency
snapshot. The executor serializes its calls, returns each payment Result, then
re-reads current cycle status before returning reminder events. A manual payment
that wins an auto race therefore suppresses stale reminders. Cancellation
propagates. Valid viewer payload owners are excluded; account partitions stay
separate. No HTTP/cloud writes occur.

This follows MistiaRecurringBillMaintenance.swift run/attemptAutoPay's pending
cycle/date and payment path. Persistent notification batching, localized automatic
transaction titles and foreground/background hooks are still pending. The API
is not scheduled automatically yet. Payment reports are transient: durable success
notifications must commit with money, or be recovered durably, before hooks enable.

Verification:

- Five runtime RED failures against empty executor -> GREEN; sixth test covers
  public FinanceRepository delegation, owner scope, exact >2^53 payment and replay.
- Real local repository tests: successful atomic expense/cycle, repeat suppression,
  insufficient-balance failure with retained deadline reminder, currency mismatch,
  concurrent manual payment with no duplicate/stale reminder, cancellation.
- Full Android762 JVM/81 suites,0 failures/errors; database/planning AndroidTest
  compilation, lintDebug and assembleDebug pass (724 tasks).
- Swift Planning53, contracts15, both l10n checks, actual SQLite/schema7 methods,
  diff check pass. ADB empty; no Android runtime/live cloud verification.
- Independent review remains unavailable due usage limit; direct Swift/self-review
  completed. All nine cloud gatesfalse; Room schema4. Full APK1–4 incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-maintenance-executor-v34.apk` (vn.com.quyln.mistia.debug, versionCode34).
SHA256: `aee559186672a977adfbefa2d5d3894bd8a4096ae8db1463cc0cba17bcd697a3`.
