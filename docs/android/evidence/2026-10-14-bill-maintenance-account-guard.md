# Bill maintenance current-account guard — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `4237572`.

## Completed behavior

Added injectable singleton `BillMaintenanceCoordinator`, a serial local entry point for future foreground/background callers. Signed-out, restoring and failure states do no maintenance. Each queued caller captures the current owner only after acquiring the lock, then obtains the device ID and current time. Account changes/sign-out cancel suspended repository work. Same-owner token refresh continues. An immediate non-suspending account change is checked again before returning a report. Repository failures remain failures; cancellation propagates.

Production Room bill money and reminder batch commits now read the active auth owner inside the database transaction, before writes and again before transaction completion. A stale owner throws cancellation and rolls back money, cycle, outbox and notification writes together. This also protects manual bill money operations. Default optional guard preserves non-app fixture use; AppModule always supplies actual auth state. No new tables or cloud writes.

Reviewed directly against the active-user snapshot boundary in `Mistia/Shared/Notifications/MistiaDueMaintenance.swift` and recurring bill maintenance. Swift's main-actor snapshot scope is implemented with Android owner checks, coroutine cancellation and Room atomic rollback. Background scheduling and native hook wiring are deliberately still unfinished; this slice establishes the required guard before enabling them.

## Verification

Runtime TDD RED: four coordinator behavior failures (wrong auth states, account switch, sign-out and queued caller); GREEN: all eight coordinator tests, including refreshed token, immediate account flip and failure/cancellation regressions. Full Android **816 JVM / 88 suites**, zero failures. Room compile, lintDebug and assembleDebug pass. Two new Room tests cover before-write and after-write account changes for both financial commit and reminder commit; **compiled only**, not run. Swift Planning **53**, contracts **15**, both localization checks, SQLite outbox **7** and notification DAO/schema **3** pass. `git diff --check` clean.

Logs: `/tmp/mistia-bill-maintenance-coordinator-{red,green}.log`; `/tmp/mistia-bill-maintenance-account-{full,room,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-account-guard-v41.apk`, versionCode41/package verified. SHA256 `9eea865463f21c03b3485e0735fe6d5a1de47b7d34a7a07082b03e6f2cebb833`.

## Limits

No ADB/emulator/Samsung present. No runtime Room rollback, Compose or visual/device verification. Independent review remains pending; direct Swift/self-review completed. Nine cloud write flags remain false, no live Supabase write/deploy/migration. Foreground/background maintenance hooks, cold-process auth restoration, time-zone changes, OS delivery and full APK1–4 parity remain open. Goal remains active.
