# Shared credit-card statement model and paid guards — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `5fdcab6`.

## Completed behavior

Added owned credit-card statement computation shared by new statement/due-month APIs and existing transaction/bill paid-statement guards. Spending month closes in the following calendar month; dates clamp to local month length and legacy due-before-close schedules roll another month. Statement total uses posted live owned charges and card debt lending, excluding adjustment/installment spending. Exact Long sums fail on Int64 overflow. Available credit comes from the owned current balance index. Empty pre-opening months disappear, while positive backdated charges still produce history.

Payment matching uses posted internal transfers to the card after closing, with destinationAmountMinor for paired FX, earliest occurredAt/createdAt ordering and valid occurrence linked-payment preference. Canonical statement month takes precedence over legacy due month; stale amount snapshots are ignored. Individual covering payment is required; partial transfers are not summed, matching Swift. Paid/payable/unclosed/overdue state and the due-through-due+5 local-day automatic decision window are implemented. Selected due-month queries search the preceding two spending months, including unclosed amounts. These functions compute decisions; they do not execute automatic card payment.

Paid statement guard now uses this same engine. Live known card occurrences override legacy title fallback; debt lending never uses the legacy title heuristic. Foreign payload owners cannot freeze an active owner's payment. Existing title-based fallback remains for legacy expense/transfer history where Swift still uses it. Runtime review also found a new charge could increase proposed total beyond an already-settled payment and reopen the statement. Transaction and bill save checks now use the before-save records, as Swift TransactionEditorSheet does. They pass the operation reference time (and a captured calendar) instead of deriving validation from a different host clock.

Existing post-closing fixtures dated February26 for February spending were corrected to March26, based on the shared Swift vectors; expected locked behavior was retained. Legacy frozen paid-occurrence fixtures stay intact. No card payment creation, schema or cloud gate changed.

## Shared authoritative business vectors

`contracts/golden/credit-card-statements-v1.json` has **27 vectors**, read by Kotlin Parameterized tests and a new XCTest invoking actual Swift PlanningLogic/TransactionLogic. They verify next-month closing, due/closing day clamps, retry bounds and exact balance, missing source, pre-close and covering payments, paired FX destination amounts, non-aggregated partial payments, stale/canonical/legacy occurrences, linked/earliest payment choice, backdated opening, zero states, >Double precision, owner/draft/archive/deletion filters, debt collection and category/title exclusions. Japan/Vietnam vectors prove different local closing boundaries and different spending months for the same instant. Both implementations verify amount, available credit, dates, state/status/link and automatic decision.

Direct review: Swift PlanningLogic creditCardStatementItems/state/payment/autoDecision/selected-due-month; TransactionLogic charge/paid-title helpers; TransactionEditorSheet existing/validation snapshots and hasCreditCardStatementOccurrences. No Swift production code changed.

## Verification

TDD RED:23 initial shared vector failures;4 paid-guard regressions;2 before-save repository failures;2 due-month projection failures. GREEN final **934 JVM /99 suites**, zero failures/errors (36 added cases:27 shared+4 guard+4 planning+1 repository). Room/planning AndroidTests compile; lintDebug/assembleDebug pass. Full Swift **602 tests** (4contract+133data+465core), including the27-vector XCTest, pass. Contracts15, both l10n checks, actual SQLite outbox7/notification3 and whitespace checks pass.

Logs `/tmp/mistia-credit-statement-{vectors-red,vectors-green,guard-red,before-save-red,due-month-red,full,swift-vectors,swift-full}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-credit-statement-model-v49.apk`; debug package/versionCode49 verified. SHA256 `80630626882c49c9cd9c1ed82fa57faa3a1a783e266083eab5d294426bee1e5a`.

## Limits and remaining work

No ADB/emulator/Samsung. Room/Compose tests compile only; no live cloud or device/visual verification. Independent review pending availability; self/direct Swift review completed. Nine write flagsfalse, no Supabase write/deploy/migration. Native statement/history UI, actual manual/automatic payment and installment/card maintenance/outbox integration remain unfinished. A product question is pending about card settlement cross-currency policy (same-currency only versus manual FX with automatic same-currency only); statement calculation/read-only work is independent of that decision. Full APK1–4 goal stays active.
