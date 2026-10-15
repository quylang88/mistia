# Durable installment source-delete provenance — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `539a9d5b`.

## Completed local foundation

Native installment source deletion now records an explicit local batch together with source/cycle tombstones and their outbox rows in the existing Room transaction. The batch contains an opaque UUID, the exact source and each affected live cycle before deletion, the proposed DELETE mutations, previous pending queues (including retry/error/observed-remote metadata), and a child-ID manifest. This is causal membership from the actual validated write set, not a timestamp/device heuristic. An earlier undo tombstone with the same clock/device is excluded, as are unrelated, foreign and aliased records.

The strict format-versioned codec preserves exact Long amounts/versions, nullable fields, unknown financial payload fields and prior queue metadata. Storage separates a small header from ordered BLOB chunks of at most64KiB, with byte/count/SHA256 validation before strict UTF-8 decoding. Large documents keep each SQLite value bounded; missing/duplicate/corrupt chunks fail closed. A >2MiB Unicode fixture round trips exactly. It validates source/cycle/owner/actor/base/clock/frozen-field consistency, duplicate/missing members and manifest identity. Prior queue actors must match their saved financial payload. Known remote identity remains representable at sync version0. No local batch fields are added to financial/cloud payloads; the15 remote entities/contracts are unchanged.

Room captures prior queue state and clean/remote provenance inside the same raw-snapshot CAS transaction, inserts the batch without replacement, then writes tombstones/outbox and rechecks the current owner. A failed outbox insertion or owner change rolls back the entire transaction. An existing unresolved batch cannot be overwritten. The owned read API checks current owner before/after decoding and verifies stored column/batch/payload identity; malformed metadata fails closed. Account clear removes only that owner's local batch data. An independent source deletion creates no empty batch; replay of an already deleted source retains the original intent.

## Local Room migration and test assets

Room version5→6 adds only local batch-header/chunk tables, scoped indices and a child foreign key with cascade cleanup. Room-generated initialization enables foreign keys; owner/exact-batch deletion cascades only its chunk rows. It preserves existing financial rows, queues, retry flags and notifications. Legacy pending deletes receive **no invented causal membership**; they remain held by the existing source-delete dependency guard pending a deliberate recovery path. No Supabase/production schema migration was performed.

Review found that the database AndroidTest APK omitted every exported Room schema despite successful Kotlin compilation. A packaged-artifact assertion failed with missing1–6. Added the schema directory to AndroidTest assets while retaining the generated system-category fixture. `check-android-room-test-assets.py` now verifies all six packaged schemas against source plus the bootstrap catalog. This makes the migration fixtures ready to load their assets; it does not prove instrumentation execution.

## Verification

Runtime TDD:12 initial model cases produced9 intended failures against stubs; the negative-only assertions already rejected unsupported operations. All12 passed after implementation. Review added a failing prior-actor regression before the actor check; four later chunk-storage cases failed against stubs and then passed, bringing the model total to16. Six initial SQLite cases failed on the missing production migration; a later chunk-table regression failed on the absent table. Final7 pass against actual migration/DAO SQL and exported v6 schema. An initial fixture assumption about optional schema indices was corrected before accepting the SQLite RED; that setup error is not counted as behavioral evidence. The APK-asset regression failed against the actual packaged test APK, then passed after the source-set fix.

Final **1153 JVM tests /116 suites**, zero failures/errors. Full Android unit tests, Room/management/planning AndroidTest compilation, database assembleDebugAndroidTest, app lintDebug/assembleDebug pass. Ten new disk-Room/transaction fixtures and one5→6 MigrationTestHelper fixture compile and package only: exact causal/prior queue capture; outbox rollback; owner flip during batch insertion; owned reads; disk reopen/replay; owner clear; unresolved batch collision; malformed identity/format; independent deletion; large Unicode document split/readback. They have not run on an Android device/emulator.

Actual SQLite helper covers old data/queue preservation, schema/index shape, owner lookup/clear, exact stale-safe delete, owner-scoped uniqueness, chunk cascade cleanup and multi-table rollback. It executes SQL, not Kotlin/Room capture logic. Existing actual SQLite outbox7/notification3 checks also pass. Full Swift603 (4contract+133data+466core), contract15, both localization checks and whitespace checks pass. Direct source/diff review compared Swift installment deletion/frozen occurrence fields and sync DTO separation; independent review remains pending availability.

The interrupted aggregate invocation had no live Gradle wrapper, an idle daemon and an empty log on inspection; the full run was started only after confirming that state. Logs `/tmp/mistia-installment-delete-batch-{red,green,sql-red,actor-red,focused,room-compile,full,final,swift,test-apk-red,test-apk-green,assets-red,chunks-red,chunks-green,chunk-sql-red,chunks-final}.log`.

App APK: `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-delete-batch-v58.apk`; debug package/versionCode58 verified. SHA256 `8398382c99ca3d6424753805f55f0a7f4039fd2068b75a70844e028a4e752958`.

Archived database test APK: `android/build/outputs/apk2/2026-10-15/mistia-room-delete-batch-test-v58.apk`; packaged six schemas and bootstrap catalog verified. SHA256 `d404ca08994b172bc75b54af4d4a72120c42c4ad93dc1bae1c8ead3159a8d6bd`.

## Remaining goal

Causal metadata is durable; atomic source-ACK/child restoration, batch completion/cleanup, legacy unproven-delete recovery and installment occurrence push are not implemented yet. Source deletes with pending cycles and all installment child writes remain held. Do not release those guards merely because a batch exists. Future reconciliation must preserve newer child mutations and posted expenses when a remote active source wins, and keep source-delete membership distinct from explicit skip/payment undo.

Actual installment payment/undo/currency handling, maintenance audit, pending card settlement policy, app currency/settings/forms, APK1–4/RC and independent/device/visual checks remain unfinished. All10 write flagsfalse; ADB empty; no device/live cloud verification, production write/deploy/migration. Full goal stays active.
