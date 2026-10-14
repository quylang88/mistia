# Automatic bill payment repository guards — 2026-10-14

`BillPaymentRequest.automatic` defaults false. Automatic requests may not
supply amount or wallet overrides; the repository reads current configured values
from its full owner-scoped money snapshot, requires auto-pay enabled/unpaused and
the resolved local automatic date equal to today. It retains existing same-currency,
amount, balance/card limit, investment, category, statement lock and cycle guards.
The full snapshot is rechecked in the money transaction, so disabling auto-pay
while committing cannot write an expense or occurrence. Repeated attempts observe
the paid cycle and cannot create a second expense. Manual behavior stays default.

This mirrors Swift maintenance's auto-pay date/enabled selection while placing
checks at the atomic money boundary to reject stale/background attempts. The
scheduler/notification executor is still pending; no automatic background hook
was enabled by this slice. Automatic transaction title localization and persistent
success/failure notifications remain part of that integration.

Verification:

- Runtime3 REDs -> GREEN: disabled/wrong date/paused refusal, override refusal,
  today-only payment and repeat suppression. Fourth test verifies concurrent
  disable invalidates the whole atomic money batch through existing snapshot CAS.
- Full Android756 JVM/81 suites,0 failures/errors; database/planning AndroidTest
  compilation, lintDebug, assembleDebug exit0 (724 tasks).
- Swift Planning53, contracts15, both localization checks, actual SQLite/schema7
  methods and diff check pass. ADB empty; no Android runtime/live cloud execution.
- Independent review still outstanding due reviewer usage limit. Self-reviewed
  against Swift MistiaRecurringBillMaintenance.run/attemptAutoPay.
- Nine cloud flagsfalse, schema4. Full APK1–4 remains incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-auto-payment-guards-v33.apk` (vn.com.quyln.mistia.debug, versionCode33).
SHA256: `7cf362f262a63997ad9b7052417156be3fbb6ff0fd7793239f9bb0312360698c`.

Next: local maintenance executor, notification persistence/cleanup, localized
transaction title and native foreground/background hooks; independent review when
available and final device verification.
