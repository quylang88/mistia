# Owned installment due read view — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `c66a9ee`.

## Completed behavior

Planning → Due → Installments now shows actual owned installments for the selected month instead of a record-count placeholder. It displays exact per-cycle/frozen amounts in each plan's own currency, paid/skipped badges and local due-date/day labels for pending rows. Owned archived/deleted plans and foreign/deleted occurrences are excluded. Paid/skipped rows retain their amount/status/link projection and are static in this read slice; they do not expose a dummy payment/edit handler. Empty, initial loading and localized retry/error states are present. Owner/repository keys isolate Compose state; month/zone changes reset loading before rendering, and a resumed-minute clock refreshes current local day/time zone.

Added the16-field RemoteInstallmentPlan codec, with strict required scalar/UUID/time types, full envelope/payload identity matching, exact Long amount/version, nullable clears and Int range checking. Existing legacy nonpositive frequency/total values are retained by the codec and interpreted like Swift scheduling. No imported plan is resaved. Raw unknown fields remain in storage; toPayload represents the16 current known fields and is not a claim of arbitrary unknown-field round-trip mutation support.

The typed repository uses the shared owned Finance read boundary, skips malformed rows, hides archived/tombstoned plans and orders by actual creation instants then ID. Review found lexical creation sorting could misorder imported offset timestamps; a reproduced failing regression drove an Instant comparator fix. No plan, money, occurrence, outbox, schema or cloud-write behavior changed.

## Shared business proof

`contracts/golden/installment-due-v1.json` has **35 shared vectors**, read by Kotlin Parameterized tests and a new XCTest invoking actual Swift PlanningLogic.installmentDueItems. Both adapters apply the personal/live/!archived visibility used by PlanningView before calculation. Vectors cover monthly/quarterly/finite schedules, pre-creation/end-of-plan months, legacy0/negative frequencies and cycle counts, short/leap month/day clamps, creation-day-versus-month anchoring, Japan/Vietnam same-instant anchor differences, DST offsets, frozen zero/pending/paid/skipped amounts, duplicate occurrence precedence, unrelated/deleted/foreign rows, unknown status fallback, pending links, >Double precision, currency/source metadata and due/name ordering. A paid occurrence cannot invent an unscheduled cycle.

Occurrence selection matches Swift: the first nonpending occurrence replaces a pending duplicate; the first settled occurrence then remains authoritative. Scheduled date is recalculated from the current plan/month; occurrence scheduledDate is not substituted. Frozen amount overrides even when zero, and nil falls back to the current per-cycle amount. sourceKind=installment/categorySystemKey=loan_repayment are verified in both implementations.

Direct comparison: PlanningModels.InstallmentPlan; PlanningSupport.planningSnapshot; PlanningLogic installmentDueItems/makeInstallmentDueItem/isScheduledMonth/occurrenceMap/preferredOccurrence/scheduledDate; PlanningView installment visibility/DueRowsSection/PlanningDueRow; PlanningSupport tone rules and MistiaFinanceIcons installment tokens. Android uses mapped native Material icons and an approximate mint status color; Fluent/pixel/device parity remains unfinished.

## Verification

Runtime TDD: initial39 model/vector cases produced32 intended failures (empty-schedule cases already passed the empty stub);3 typed-read cases failed against an empty repository stub. A new offset-sort regression then produced1 intended failure before its fix. Final **1032 JVM tests /107 suites**, zero failures/errors:44 added cases (35 shared+5 codec+4 repository). Full Android tests, Room/management/planning AndroidTest compilation, lintDebug and assembleDebug pass after review fixes.

Two new Compose checks and one actual Room repository check compile only: exact paid display/read-only/empty transition; same-instant Japan/Vietnam day labels; imported Int64/nullable metadata read without outbox writes. They were not executed on a device/emulator.

Focused Swift vector XCTest passed initially34 vectors; full Swift **603 tests** (4contract+133data+466core) includes the final35-vector fixture. Contracts15, both localization checks, actual SQLite outbox7/notification3 and whitespace checks pass. Error/retry copy comes from shared xcstrings en/ja/vi with both generators run.

Logs `/tmp/mistia-installment-model-{red,green,read-red,read-green,offset-red,full,final,swift-vectors,swift-full}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-installment-due-read-v53.apk`; debug package/versionCode53 verified. SHA256 `cc7202e4fd0215299bdc1080fedc3937b748dcea905ea0fa4a378bd16cfec7f4`.

## Remaining gates

Installment create/edit/delete, skip/undo, actual payment/undo, money affordability/dependency/CAS/receipt/investment protections, due notifications, push/outbox domain gate and complete navigation/forms remain unfinished. Payment currency behavior is not implemented or inferred by this read-only projection. The separate card settlement currency question remains pending. Full APK1–4/RC goal stays active.

ADB empty; no emulator/Samsung/language/zone/background/visual runtime verification. Independent review pending availability; self/direct Swift review completed. Nine cloud flagsfalse; no live Supabase write/deploy/migration. This slice completes the owned due read view and its model proof, not the full installment domain or APK2.
