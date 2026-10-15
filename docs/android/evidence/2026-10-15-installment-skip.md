# Native installment skip/undo — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `c75dc17f`.

## Completed workflow

Pending installment rows now offer Skip; skipped rows offer Undo skip. Both open a native confirmation naming the item and selected month. Paid rows retain their separate metadata edit action and have no skip action. Busy confirmation disables repeated submission and dismissal; localized vi/en/ja failures retain the dialog. Owner/month/zone changes cancel the prior dialog scope, and the existing cancellation guard prevents a late noncooperative result from dismissing a new confirmation. The metadata editor retains its separate owner-scoped saved state.

Real repository APIs capture one operation clock, zone and creation UUID across three raw-snapshot CAS attempts. They validate an active owned source and the user's semantic baseline, accepting metadata-only ACK changes. Unscheduled finite/frequency/pre-anchor cycles are rejected. Every owned live matching occurrence participates; any paid status, linked transaction or paidAt blocks both skip and undo, including conflicting duplicates. Foreign payloads/envelope aliases, other source kinds/months, unrelated records and existing tombstones remain untouched. Malformed owned related rows fail closed.

Skip changes every live pending duplicate to skipped, refreshes the scheduled date, clears amount/paidAt/transaction link with explicit nulls, and preserves original creation/version/unknown payload fields. With no live cycle it creates one owned occurrence. Repeated skip acknowledges the existing skipped record without rewriting its newer timestamp/outbox mutation. Undo tombstones every live skipped duplicate while preserving frozen fields; pending siblings stay intact. Repeated undo is an ACK, and a later skip allocates a new live identity rather than repurposing a tombstone. No plan, wallet, transaction or balance mutation occurs.

## Atomic/account boundary

InstallmentCycleSnapshot reuses the complete raw plan/wallet/occurrence snapshot. Its policy reconstructs the entire permitted intent and rejects omitted duplicates, extra plan/ledger writes, changed actor/base/clock/payload/frozen metadata, ID collisions and incomplete/foreign snapshots. Room validates policy, compares all raw tables and commits occurrence plus outbox in one transaction, checking current owner before/after writes. Unsupported stores fail closed; cancellation propagates. All10 cloud flags remain false; bill-only due source/client gates hold the new installment outbox entries. No installment push registration or production write was enabled.

Concurrent repository attempts converge on one skipped record. A late older operation acknowledges the newer winner without replacing its clock/outbox mutation. A paid insert racing skip or payment racing undo is recaptured and blocks the obsolete intent. A timezone change during retry cannot change the already captured cycle calendar.

## Direct Swift comparison

Reviewed PlanningView's installment DueRowsSection actions, DuePaymentSheet.skip/undoSkip, PlanningSupport.saveDueSkip/undoDueSkip/upsertOccurrence, installment scheduling and notification resolution. Valid pending duplicate skip uses nil amount/link/paidAt as in Swift; undo marks every matching skipped occurrence deleted. Android also guards conflicting paid/linked duplicates, malformed ownership and CAS races. It leaves historical tombstones untouched and creates a new identity on skip after undo; Swift's broad upsert searches matching historical records, which is not copied as a resurrection/hidden-write path. Neither operation creates or reverses an expense.

Swift's skip helper invokes the recurring-bill notification resolver, whose actual predicate is bill-specific (`mistia.bill.*`, bill resource type/kinds). This slice does not invent installment notification resolution or automatic payment. Installment payment/undo, dedicated push preflight, and the actual maintenance/notification scope still require their own implementation/audit.

## Verification

Runtime TDD:16 initial repository cases produced15 intended failures against the unsupported API stubs; the malformed-data failure assertion already failed closed. After implementation, all16 passed. The calendar-capture case and two explicit cross-repository/payment races expanded the final repository set to19; all19 pass. Five pure mutation-policy cases pass. Final **1102 JVM tests /113 suites**, zero failures/errors.

Full Android unit tests, Room/management/planning AndroidTest compilation, lintDebug and assembleDebug pass. Four new actual Room fixtures compile only: skip/undo outbox coalescing with unchanged source/ledger; outbox-trigger rollback; owner flip during SQL rollback; actual concurrent occurrence insertion rejecting a captured intent. Three new Compose fixtures compile only: actual skip/undo confirmations with Room/outbox; paid row has metadata edit and no skip; late noncooperative completion after month replacement leaves a new confirmation open. No AndroidTest/device execution is claimed.

Full Swift603 (4contract+133data+466core), contract15, both localization checks, actual SQLite outbox7/notification3 and whitespace checks pass. Direct source/diff self-review completed; independent review remains pending availability. Logs `/tmp/mistia-installment-cycle-{red,green,policy,focused,races,full,final,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-skip-v56.apk`; debug package/versionCode56 verified. SHA256 `325d09809b6c501d05b7d03d85d91bf8d3bb416a6d69ba282c3381517d94f413`.

## Remaining goal

Actual installment payment/undo and safe currency handling, dedicated push/dependency/delete preflight, maintenance/notification audit, pending card settlement policy, app currency/settings and monetary-form audit, full APK1–4/RC and independent/device/visual QA remain unfinished. ADB empty; no emulator/Samsung/live cloud verification, production write, deploy or migration. The full goal stays active.
