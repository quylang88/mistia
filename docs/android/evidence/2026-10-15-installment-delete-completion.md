# Complete proven installment source-deletion batches — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `4abdc702`.

## Completed local implementation

A dedicated worker handles only installment child DELETE queues proven by a persisted causal source-delete batch after the source queue finishes. It is composed inside the existing due-domain coordinator, retaining one coordinator per entity in SyncEngine (installment source priority80, due90, then full pull). Ordinary installment UPSERT/explicit undo/legacy unproven deletes remain held. Bill behavior retains its existing path; the installment worker has its own default-disabled capability.

The planner validates complete owned snapshots, batch membership, source/cycle identity and selected month, exact payload/base/clock/actor consistency and retry readiness. It reads the authoritative source and eligible cycles. Missing remote rows are confirmed absence; existing tombstones ACK as authoritative; later remote child edits win under the deleted source; local delete winners PATCH only deletion metadata using exact remote Long version CAS. No create fallback exists. Repeat conditional races stop after two attempts. Source checks surround child requests, and an active source at either check becomes a scoped conflict, preserving the local source pull pin and batch. These are individual remote CAS operations, not a cross-row remote transaction: a parent can still change after the last read; complete resurrection recovery is a separate remaining path.

All child ACKs, source refresh, exact header/chunk cleanup and queue removal commit in one owner-guarded Room transaction using complete source/cycle/ledger raw snapshots, all relevant queues and the exact original batch ID. Newer child mutations stay outside the old batch's write set. A partial remote success leaves every local child queue and batch intact until the whole batch can commit. Lost responses, cancellation after an applied remote delete and retry reconstruct from authoritative state without issuing duplicate deletes. Retry/error persistence is scoped to the same full snapshot/batch; stale failures cannot affect a new identical queue, and persistence errors propagate without generic fallback.

The worker never reads or writes remote ledger rows and never changes local expenses; paid cycle status, frozen amount/date/link and other remote business fields remain unchanged by sparse deletion. This matches Swift installment source deletion's recorded-expense retention and generic version/conflict/tombstone behavior; it deliberately does not reuse bill payment undo's requirement to delete the linked expense.

Network adds a separate default-false installment-occurrence-delete capability in addition to the due entity gate. It permits only conditional PATCH with the exact seven metadata/discriminator fields, canonical owner/record/actor UUIDs, valid timestamps and increasing numeric Long version. Installment creates and full UPSERTs stay prohibited even if installment is supplied in the broad due-source list. Bill/card/ledger writes cannot be enabled by this capability. App composition requires global+due+installment+wallet flags for this path; bill capabilities remain separate. All ten actual generated flags remain false.

## Verification

Runtime TDD: initial16 model cases produced12 intended failures against the stub (negative-only assertions already rejected unsupported operations), then all16 passed. Initial15 worker cases produced13 assertion failures against its inert stub, then passed. Initial fixture interface compilation was corrected before accepting runtime RED. Review expanded worker cases to23, covering multi-child partial success, repeated races, one-due-coordinator composition, ordinary/unproven holds, persistence failure, lost response after applied delete, malformed DELETE representation, cancellation after applied delete and idempotent retry. Initial8 HTTPS cases produced4 intended failures against the old disabled/unrestricted paths; all8 pass after the scoped capability and response identity check. A review fixture's suspend-lambda type error was corrected before accepting its runtime results.

Final **1237 JVM tests /121 suites**, zero failures/errors; full Android unit tests; Room/management/planning AndroidTest compilation; database assembleDebugAndroidTest; app lintDebug/assembleDebug pass. Seven added disk-Room fixtures compile/package only: successful cleanup/reopen/expense retention; write rollback; owner-flip rollback; stale ledger/request batch CAS; newer child preservation; scoped failure persistence; active source/foreign owner rejection. No Android instrumentation runtime is claimed.

Actual SQLite outbox7/notification3/installment-deletion11 checks pass; these execute SQL, not the new Kotlin transaction orchestration. Test APK contains source-matching Room schemas1–6 and bootstrap catalog. Full Swift603 (4contract+133data+466core), contract15, both localization checks and whitespace checks pass. Direct source/diff review compared Swift installment deletion, frozen occurrence values, generic delete/conflict and sync ordering. Independent review remains pending availability. No Swift runtime behavior changed in this slice.

Logs `/tmp/mistia-installment-completion-{model-red,model-green,push-red,push-green,http-red,http-green,focused,review,full,swift}.log`.

App APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-delete-completion-v61.apk`, debug versionCode61 and planner/worker DEX presence verified. SHA256 `a6055759c36b122e9b4d19edbcf006ab86b1c034d8bd3d94817f6756b580316b`.

Database test APK `android/build/outputs/apk2/2026-10-15/mistia-room-delete-completion-test-v61.apk`. SHA256 `7c0ad2d146ac8d9b862dc74e7a16e1fd7e4279b61b88e91151703bf260e3e347`.

## Remaining full goal

Active-source resurrection recovery and explicit legacy/corrupt/missing-queue recovery UI are unfinished; those paths remain held with scoped attention state. Ordinary installment occurrence push, actual payment/undo, maintenance/notifications, pending card currency choice, app currency/settings/forms, APK1–4/RC and independent/Samsung/visual/background evidence remain unfinished. The user has now selected same-currency installment payment for both iOS and Android; implement that explicitly next, including stale-selection persistence guards.

ADB empty; no device/emulator/live Supabase verification, production write/deploy/migration. Full goal stays active.
