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

Next coherent slices:

1. Continue the currency/settings and monetary-input audit across remaining forms.
   The actual Swift installment currency field groups raw minor integers for all
   currencies; the new editor matches valid input with a formatted preview, rejecting
   ambiguous punctuation and overflow instead of silently changing the amount.
2. Actual selected-month payment/undo with transaction/category/occurrence
   atomic CAS, current affordability, paid card/receipt/investment/settlement guards,
   scoped frozen-history checks and deterministic currency policy. Do not copy raw minor
   values between currencies. Bill same-currency choice is accepted; card product question
   remains pending. Current installment read work does not decide settlement behavior.
3. Dedicated installment occurrence push and causal source-delete reconciliation.
   Current bill-only child gate and source-delete dependency guard deliberately hold
   the unsafe paths. A source-delete remote winner must reconcile exact dependent child
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
