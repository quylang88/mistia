# Keep unfinished installment deletion sources fenced during pull — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `d13fde16`.

## Problem and correction

A successful source DELETE ACK leaves the source clean with no source queue, while its explicit causal batch and child DELETE queues remain. The generic full-snapshot replacement removed every clean source and could then insert an active remote source. This could expose an active plan over locally hidden paid cycles before dedicated batch reconciliation had run. A remote snapshot omitting the source could also remove the durable local source required for that reconciliation.

Pull now preserves a source row with an exact owner/plan match in `installment_delete_batches`, even after source ACK. The actual Room DELETE query excludes those rows. In the same transaction, incoming source rows are filtered by the same owned header IDs as well as pending mutation IDs, preventing an UPSERT from bypassing the DELETE protection. Source rows remain clean: no invented outbox mutation or causal membership is added. Source pull checks current owner before/after the transaction and rejects foreign entity/owner envelopes before changes. Cursor updates roll back with owner changes.

The guard uses durable header identity, not deletion clock/device or JSON inference. It continues to hold a source if its batch document is corrupt; explicit recovery must resolve that corruption. It does not pin another plan, another owner with the same ID, or a wallet/other entity with that ID. Once the exact batch is cleared by the atomic reconciler, normal replacement/removal resumes immediately. Full-pull cursors still describe the received remote snapshot; a held source is intentionally a local view of unresolved intent. The current engine always fetches full pages, so it does not skip later updates based on that cursor.

Direct review compared Swift source/due upsert, source-delete preservation of recorded expenses and Android push-before-full-pull ordering. Android's child write gate creates an unfinished batch interval that must remain fenced. This correction does not claim complete installment child synchronization or change Swift runtime behavior.

## Verification

Runtime TDD against actual production DAO SQL: the two pin/release cases failed with `0 != 1` before the query correction. Initial query extraction accidentally spanned multiple annotations; that fixture setup error was fixed before accepting the behavioral RED. Final **11 actual SQLite installment deletion checks** pass (four additions), covering post-ACK clean source retention, owner/entity isolation, immediate release after exact batch deletion, and no clock/device inference. Existing outbox7/notification3 SQLite checks pass. These checks execute SQL, not Kotlin/Room transaction orchestration.

Six new disk-Room fixtures compile/package only: active/missing/deleted remote snapshots across three pulls and disk reopen; normal pull after batch clear; unrelated plan/owner isolation; owner-flip rollback including cursor; foreign envelope rejection; corrupt batch still pinned. An initial fixture called an unavailable cursor DAO accessor; corrected to a test-only SQLite read before accepting compilation. No runtime device/emulator execution is claimed.

Full **1190 JVM tests /118 suites**, zero failures/errors; database/management/planning AndroidTest compilation; database assembleDebugAndroidTest; app lintDebug/assembleDebug pass. Packaged schemas1–6 and bootstrap catalog match source. Full Swift603 (4contract+133data+466core), contract15, both localization strict/check commands and whitespace checks pass. Room schema stays6; remote contracts and cloud flags are unchanged. Independent review remains pending availability.

Logs `/tmp/mistia-installment-pull-pin-{red,green,focused,full,swift}.log`.

App APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-pull-pin-v60.apk`, debug versionCode60 verified. SHA256 `b481b52bc9a64d7180f12201ca4dc23472ce9a5ed7a228d12c58530f786f64ea`.

Database test APK `android/build/outputs/apk2/2026-10-15/mistia-room-pull-pin-test-v60.apk`. SHA256 `3d49f78cda959768e9dc92fd19ea20feb69b9a0ed3c7d14d81a8ba675c97a8f7`.

## Remaining goal

Dedicated installment child deletion/push/completion, active-source resurrection reconciliation and explicit legacy/corrupt-batch recovery remain unfinished. The existing bill-only child coordinator/client discriminator stays closed to installment writes. A future batch worker must fetch authoritative source/cycle/ledger state directly and resolve/clear the exact batch atomically; generic pull cannot release the guard. Do not reuse bill undo's linked-ledger-delete policy: source deletion keeps recorded expenses.

Actual installment payment/undo/currency policy, maintenance/notifications, pending card currency choice, app currency/settings/forms and full APK1–4/RC remain unfinished. ADB empty; all10 flagsfalse. No emulator/Samsung/live Supabase verification, production write/deploy/migration. Full goal remains active.
