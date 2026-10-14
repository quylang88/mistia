# Background recurring-bill maintenance — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `a488144`.

## Completed behavior

MistiaApplication schedules one unique periodic local bill job with WorkManager KEEP policy, hourly interval and exponential retry backoff. The job has no network or notification-permission constraint. WorkManager owns persistence/restart scheduling; actual execution time is OS-controlled rather than an exact alarm.

BillMaintenanceWorker resolves a real singleton task through a Hilt application entry point, including in a cold process; it has no Activity or static SyncRuntime dependency. The task first waits for shared initial session restoration, then executes the existing current-owner guarded local bill coordinator. Signed-out work succeeds without restoring old secure cache or paying. Storage/repository failures retry; cancellation propagates. Individual automatic payment failures remain report outcomes with durable notification copy, not repeated money operations from the worker wrapper. Existing repository snapshot/CAS and cycle guards, coordinator mutex and Room active-owner pre/post checks remain in force. Money runs independently of reminder preference and OS notification permission.

Compared directly with Swift `MistiaSyncBackgroundScheduler` expiration/cancellation and OS scheduling, `MistiaApp` backgroundRefresh callback and `MistiaDueMaintenance` active-user local bill pass. This Android slice adds local due work without requiring a cloud pull. Existing cloud sync worker remains separate.

## Verification

Five runtime TDD RED failures → all six background pipeline tests GREEN: cold restore ordering, signed-out cache protection, restore error, repository error, account switch preventing later effects, cancellation during restore. Tests compose the actual restoration and maintenance coordinators. Full Android **840 JVM / 91 suites**, zero failures/errors; Room/app AndroidTest compilation, lintDebug and assembleDebug pass. Swift Planning **53**, contracts **15**, both localization checks, actual SQLite outbox **7** and notification DAO/schema **3**, whitespace checks pass.

Logs: `/tmp/mistia-bill-background-{red,full,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-background-v44.apk`; debug package/versionCode44 verified. SHA256 `0f8827969f3511c5d1c29280534aeb3f5a85c6d4b4fc8ed801832be98b82247d`.

## Limits and remaining scope

No ADB/emulator/Samsung. WorkManager actual enqueue, OS job timing, cold-process/boot execution and Room rollback are not runtime-device verified; AndroidTests compile only. No OS notification posting yet. Independent review remains pending availability; direct Swift/self-review completed. Nine cloud-write flagsfalse; no live Supabase write/deploy/migration. Immediate preference triggers, dynamic device ZoneId, OS delivery, remaining notification domains, visual/device verification and full APK1–4 remain unfinished. Goal stays active.
