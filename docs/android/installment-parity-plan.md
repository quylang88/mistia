# Native installment parity

Full APK1–4 remains the objective. Completed owned installment due read slice:
`evidence/2026-10-14-installment-due-read.md` (APK53). Actual35-vector Swift/Kotlin
calendar/occurrence proof and native read view are complete locally, without device proof.

Owned mutation repository is completed locally (APK54):
`evidence/2026-10-14-installment-mutations.md`. Stable replay IDs, semantic stale/ACK
checks, raw snapshot CAS and owned plan/cycle tombstones preserve the expense ledger.

Native metadata editor/navigation is completed locally (APK55):
`evidence/2026-10-14-installment-editor.md`. Actual repository callbacks, stable ID,
owned savers, frozen currency, exact grouped minor input and confirmations are wired.
Eleven JVM cases execute; seven new Compose/Room fixtures compile only. Repository
reconstruction/process-death/device behavior still needs runtime Android verification.

Selected-month skip/undo is completed locally (APK56):
`evidence/2026-10-15-installment-skip.md`. Paid/linked duplicate guards, active-source
baseline, full snapshot CAS, atomic outbox and native scoped confirmations are wired.
Nineteen repository and five policy JVM cases execute; four Room and three Compose
additions compile only. Payment/undo and installment cloud push stay unfinished.

Plan push foundation is completed locally (APK57):
`evidence/2026-10-15-installment-plan-push.md`. Typed plan outbox/HTTP/DI/order and
independent source tombstones are tested. Source deletes with pending owned cycles
remain held; all installment child writes remain closed pending dedicated reconciliation.

Durable causal source-delete metadata is completed locally (APK58):
`evidence/2026-10-15-installment-delete-batch.md`. Room6 stores exact source/cycle
before-images, previous queues and an explicit member manifest atomically with deletes.
Storage uses bounded64KiB BLOB chunks with checksum/identity validation.
Sixteen model and seven actual SQLite cases execute; ten Room +one migration fixtures
package only. Test APK schemas1–6 now bundle correctly. Source ACK/reconciliation,
batch cleanup and legacy unproven-delete recovery are still unfinished; guards stay closed.

Atomic source ACK/history restoration is completed locally (APK59):
`evidence/2026-10-15-installment-source-ack.md`. Per-request batch fencing, owned
source/cycle/ledger reconciliation, raw-snapshot CAS, exact prior queues and newer-child
preservation are implemented. Runtime23 model +14 sync cases pass; ten new Room
fixtures compile/package only. Successful source deletion still retains its children
and batch for dedicated completion. Legacy unproven dependencies remain held.

Unfinished-batch source pull protection is completed locally (APK60):
`evidence/2026-10-15-installment-pull-pin.md`. A source with a durable owned batch
stays fenced after source ACK, across active/missing/deleted remote full snapshots;
normal pull resumes when the exact batch is cleared. Four new actual SQL cases pass;
six Room fixtures compile/package only. The future batch worker must use authoritative
fetches and explicit reconciliation rather than relying on generic pull to clear a batch.

Proven source-delete child completion is completed locally (APK61):
`evidence/2026-10-15-installment-delete-completion.md`. Sparse exact-version child
DELETE, retry/race/cancellation/lost-response handling and whole-batch Room ACK/cleanup
are composed inside the single due coordinator.16 model +23 worker +8 HTTPS cases
execute; seven Room fixtures compile/package only. All write flags remain false.
Active-source resurrection and legacy/corrupt-batch recovery still hold for explicit
resolution. Ordinary installment occurrence creation/edits remain disabled.

User decision (2026-10-15): installment payment must use a same-currency wallet on
BOTH Swift/iOS and Android. Enforce in selection, confirmation and persistence so a
stale/restored selection cannot spend another currency. No raw-minor cross-currency debit.

Same-currency installment wallet rule is completed on existing surfaces (APK62):
`evidence/2026-10-15-installment-same-currency.md`. Swift due/early payment selection
and current SwiftData preflight now enforce the user decision; Android picker, form,
repository and atomic metadata save validator enforce the same rule. Actual Android
payment/undo remains the next feature. Swift609 and unsigned iPhone app build pass;
Android1244 JVM tests pass; two Room +one Compose fixtures compile only.

Installment payment/undo repository is completed locally (APK63):
`evidence/2026-10-15-installment-payment-repository.md`. Actual FinanceRepository API,
source baseline/schedule, same-currency/current affordability, loan-repayment category,
atomic financial snapshots, receipt/statement/settlement/investment guards and stable
undo/repay IDs are implemented.22 new cases execute with49 bill regression cases;
four Room fixtures compile/package only. Ordinary occurrence/undo push and investment
fund confirmation remain unfinished.

Native payment/undo flow is completed locally (APK64):
`evidence/2026-10-15-installment-payment-ui.md`. Owned navigation, fixed exact amount
matching Swift, same-currency picker, frozen confirmation and actual repository callbacks,
wallet draft/discard, busy/cancellation and changed-cycle guards are wired.10 JVM cases
execute; nine new Compose/Room fixtures compile/package only. No device/visual proof.

Gated ordinary skip/undo metadata synchronization is implemented locally (APK65):
`evidence/2026-10-15-installment-skip-sync.md`. Dedicated worker and network capability,
complete owner/source/month paging, observed sibling holds, source/snapshot/CAS fences and
atomic Room ACK/retry are wired inside the one due coordinator.13 model +21 worker
+10 HTTPS +one broad-delegate regression execute; six Room fixtures compile/package only.
Paid occurrence and payment-undo synchronization remain held. PostgREST per-record CAS
is not a parent/month atomic transaction; cross-record races and duplicate recovery still
require completion before enabling writes. All10 flags remain false.

Installment financial mutation coherence is enforced at the actual Room boundary (APK66):
`evidence/2026-10-15-installment-money-contract.md`. Exact paid expense/marker amounts,
links and clocks, complete duplicate/expense undo, preserved financial tombstones and
consistent actor/version metadata are validated.10 new JVM cases execute; three added
Room fixtures compile/package only. Paid cloud ACK remains a separate next feature.
The pending wallet/category transaction dependency guard is completed locally in APK67:
`evidence/2026-10-15-transaction-dependency-guard.md`. UPSERT defers before fetch and
before each write while owned direct dependencies remain pending; DELETE is independent.
Nine added cases execute, including mid-fetch arrivals/create/base/forced update variants.
Missing-remote-parent repair is separate open work. Paid occurrence ACK remains next.

ACK-only installment paid-history reconciliation is implemented locally (APK68):
`evidence/2026-10-15-installment-paid-ack.md`. Complete owned plan/due/ledger/wallet/
queue/batch snapshots, exact amount/currency/dependency checks and atomic Room ACK/retry
can acknowledge existing consistent server history, completed undo or restore a paid
marker after a lost ledger-delete conflict.14 policy +11 worker cases execute; five new
Room fixtures compile/package only. No remote paid-write capability was added. New paid
creation/live paid deletion, cross-record atomicity and full duplicate recovery remain open.

Next coherent slices:

1. Continue the currency/settings and monetary-input audit across remaining forms.
   The actual Swift installment currency field groups raw minor integers for all
   currencies; the new editor matches valid input with a formatted preview, rejecting
   ambiguous punctuation and overflow instead of silently changing the amount.
2. Integrate investment fund confirmation with installment payment and continue
   maintenance/notification audit. Bill/installment same-currency choices are accepted;
   card product question remains pending. Native installment payment/undo is wired locally;
   device/process-death/visual verification and coupled cloud completion remain open.
3. Coupled paid installment occurrence/payment-undo push, remote resurrection and legacy
   recovery. Successful proven source-delete child completion is implemented in APK61. Current bill-only child gate and legacy
   unproven-source dependency guard deliberately hold the unsafe paths. A source-delete remote winner must reconcile exact dependent child
   deletion intents without losing newer edits or hiding paid history under an active
   plan. Use the persisted causal batch and exact current queue comparisons; timestamp/
   device coincidence is insufficient. Restore only matching delete intents, preserve
   newer child mutations, validate authoritative source/cycle/ledger ownership and commit
   source ACK plus child restoration/queue changes atomically. Complete/clear only the
   matching batch after safe outcomes; retain an explicit recovery path for legacy
   pending deletes that have no proven batch. Do not infer one during migration.
   Do not merely enable the shared source list or reuse bill linked-ledger undo preflight.
   Preserve posted expenses on source deletion. Then inspect actual Swift maintenance/
   notifications and integrate only its supported behaviors. All flags remain false.
4. Samsung/visual/background checks when a device is available; independent review
   when available. Never treat compile-only AndroidTests as runtime verification.

After each slice: runtime RED/GREEN, focused/full applicable checks, direct Swift/diff
review, evidence/progress, separate local commit, then continue APK1–4. All ten current
cloud flags stay false; no production write, deployment or migration is authorized.
