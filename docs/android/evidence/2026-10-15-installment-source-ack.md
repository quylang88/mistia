# Atomic installment source ACK and history restoration — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `74b24390`.

## Completed local behavior

Installment source DELETE now has a dedicated, opt-in reconciliation path. Native composition selects this implemented path while every cloud write flag remains false. A request captures its opaque causal batch ID before remote IO in an immutable coroutine context, including explicit absence for independent deletes. Concurrent pushes cannot replace that context. Late responses for an identical source queue belonging to a different batch are stale before child reads; scoped failure persistence also checks batch identity and the complete current queue atomically. A scoped storage failure propagates without falling back to an unfenced generic write. Cancellation is checked before local ACK and after noncooperative remote responses.

When an active remote plan wins, the planner reconciles only cycle DELETE intents proven by the durable batch and still matching the current queue. It validates owner/entity/ID/version, source kind, source/month linkage, source currency and creation anchor. Newer child mutations are preserved. A prior local child winner restores its exact before-image and retry/error/observed-identity metadata; an authoritative child winner becomes clean local history. A confirmed missing remote child becomes a metadata repair UPSERT preserving paid status, exact frozen amount, date and linked transaction. Legacy nil-linked paid and zero/nil snapshot values remain representable. Unknown causal queues remain held, rather than grouped by timestamp/device.

Required authoritative cycle and ledger reads distinguish not-fetched from confirmed absence. A paid linked marker needs an owned live posted expense, or a matching valid pending local posted-expense intent with exact version/clock/actor proof. Draft/income/archived/absent financial footprints cannot expose paid history. A deleted authoritative cycle linked to a live expense is a conflict. Financial drift between local and server ledger snapshots defers ACK until normal pull refreshes the local footprint; metadata-only ledger changes do not block restoration. Reconciliation never writes ledger rows or performs currency conversion.

Room commits source ACK, matching child restoration/queue changes and exact batch/chunk cleanup in one transaction, guarded by complete owner-scoped source/cycle/ledger raw snapshots, queues and batch identity. Owner changes and child-write failures roll back every change. If the source deletion succeeds, source ACK retains pending child tombstones, the batch and recorded expenses for the dedicated child cleanup path. Room schema remains6; no remote contract/schema or migration changed.

Creation anchor comparison permits strictly sub-microsecond representation differences. This addresses a stale initial-create ACK followed by PostgreSQL timestamp representation; actual currency changes and anchor differences of one microsecond or greater remain conflicts. PostgreSQL documents timestamp/timestamptz resolution as one microsecond: [official date/time types](https://www.postgresql.org/docs/current/datatype-datetime.html). No amount tolerance was introduced.

The existing conflict resolver implementation moved into core/model for shared use. The sync public API delegates to the same policy; full coordinator regressions passed. Generic outbox defaults retain their existing domain behavior, with cancellation-aware ACK and scoped failure/ACK extension points.

## Verification and limits

Runtime TDD: initial18 model cases produced17 intended failures against stubs, then passed. A creation-time precision regression failed before the tolerance correction. Review added a failing pending-ledger version/clock/actor case before proof validation. Final23 model cases pass. Initial12 sync cases produced8 behavioral assertion failures plus2 coroutine timeouts on the inert path; those timeouts are not counted as behavioral RED evidence. The scheduling fixtures now assert request entry explicitly. Initial implementation passed all12. Later stale-failure and scoped-persistence regressions each failed before their fixes; final14 sync cases pass, including concurrent immutable contexts and late noncooperative cancellation.

Final **1190 JVM tests /118 suites**, zero failures/errors. Full Android unit tests; database/management/planning AndroidTest Kotlin compilation; database assembleDebugAndroidTest; app lintDebug/assembleDebug pass. Ten added disk-Room fixtures compile and package only: atomic restore/cascade cleanup/reopen, child-write rollback, owner-flip rollback, ledger CAS, retry/batch CAS, deleted-source retention, prior queue restoration, newer-child preservation, missing-child repair, scoped failure fencing. These fixtures have not executed on an Android device or emulator.

Existing actual SQLite outbox7/notification3/installment-deletion7 checks pass; these execute SQL and do not prove the new Kotlin Room transaction logic. Packaged Room schemas1–6 and bootstrap catalog match source. Full Swift603 (4contract+133data+466core), contract15, both localization checks and whitespace checks pass. Direct review compared Swift installment deletion, source/due upsert and frozen paid fields; independent review remains pending availability. No runtime iOS behavior was changed.

Logs `/tmp/mistia-installment-source-{ack-red,ack-data-green,ack-precision-red,push-red,ack-green,proof-red,failure-red,final-focused,persistence-red,ack-full,ack-swift}.log`.

App APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-source-ack-v59.apk`, debug versionCode59, ACK model/context DEX presence verified. SHA256 `595c45de53edaf3f6bbd2dff860770ab10af5e50cc17e2f4fa649a70e7d8509b`.

Database test APK `android/build/outputs/apk2/2026-10-15/mistia-room-source-ack-test-v59.apk`. SHA256 `752f5ff59a401f1bc48614de7e8ffa2fc38ad9e6f3fb1e4278d93e44cf8082e9`.

## Remaining full goal

Installment child push remains closed by the existing bill-only coordinator/client discriminator. Successful-source-delete child completion and batch cleanup, remote resurrection handling, explicit legacy unproven-delete recovery, actual installment payment/undo/currency policy and maintenance/notifications remain unfinished. Do not reuse bill undo's linked-ledger deletion requirement for source deletion, which keeps expenses.

Pending card currency choice, app currency/settings/monetary form audit, APK1–4/RC, Samsung/visual/background and independent review remain unfinished. All10 write flagsfalse; ADB empty; no emulator/Samsung/live cloud evidence, production writes, deployment or production migration. Full goal stays active.
