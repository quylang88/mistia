# Native Android wallet reminder scheduling and delivery — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `4bab09d`.

## Completed behavior

Owned low-cash-wallet inbox targets now drive actual Android AlarmManager RTC_WAKEUP alarms for local09:00 with setAndAllowWhileIdle. Alarms are inexact/OS-controlled and require no exact-alarm special access. An unexported receiver enqueues unique WorkManager delivery. A Hilt entry point restores the cold-process session through the shared restoration gate before native delivery. Boot/date/time/time-zone receivers enqueue guarded local maintenance to rebuild schedules. Foreground and periodic bill/wallet maintenance use the same native scheduler through a repository decorator.

The delivery worker re-reads the current owned wallet/transaction/settlement snapshot and produces current localized content. Old owner, old local date/zone, early alarm, recovered/deleted/archived wallet, disabled master/detail, denied app permission or blocked channel cannot produce a native reminder. Content is checked again after posting; changed owner/policy/eligibility dismisses stale display. Unchanged content survives unrelated metadata updates. Read inbox history does not suppress the next daily OS reminder, matching Swift's scheduler. Bill notices remain inbox-only.

A durable device-private state file stores owner/wallet/time tickets and separate handled/delivered nonces, never notification body or financial amounts. Pending intents are tracked before OS scheduling. Due suppressed alarms are consumed, so later funding/permission changes cannot replay the old09:00 request. Delivery nonce persists before alarm cleanup; failed cancellation retains its tracked intent for safe retry. Stable per-owner/wallet tags and same-fireAt only-alert-once notification replacement protect normal retries; a new daily fireAt can alert again. OS posting and local state are separate system operations: this does not claim transactional exactly-once delivery across a crash at every instruction boundary.

A process-level observer reacts immediately to owner/master/wallet-detail and financial dependency changes, cancels old account/policy schedules/displays, and excludes inbox writes to avoid a feedback loop. Token refresh and unrelated preferences do not restart work; unchanged financial emissions are deduplicated. Cold Restoring state retains recovery tickets until auth resolves. Permission-result callback refreshes schedules after the explicit user permission action. Native notification content opens the app, as Swift has no per-wallet OS action route.

Direct Swift comparison: `MistiaLocalNotificationScheduler.swift` local09:00, low-wallet selection, content/source/keys and scheduled-reminder clearing; `MistiaDueMaintenance.swift`; `MistiaSyncBackgroundScheduler.swift` OS scheduling/cancellation. Android additionally validates latest data and current owner at posting instead of trusting old serialized content.

## Verification

TDD runtime RED→GREEN: native policy5 failures; controller7; observer5; unchanged-invalidation1; content-confirmation1; consumed funded/denied alarms2; cancellation recovery1. Final30 added JVM tests: model9, controller15, observer6. Full Android **891 JVM /96 suites**, zero failures/errors; Room and app AndroidTests compile, lintDebug and assembleDebug pass. Full Swift **601 tests** (4 contract+133data+464core), contracts15, both l10n checks, actual SQLite outbox7/notification3, whitespace checks pass.

Three new Android platform tests compile only: isolated state recreation, immutable owned alarm PendingIntent creation/cancellation, permission-granted notification channel/content/tag/dismissal (skips if permission absent). No actual device runtime. APK DEX confirms all new receiver/worker/platform/coordinator classes; merged manifest confirms unexported alarm/clock receivers, clock/boot actions and POST_NOTIFICATIONS/RECEIVE_BOOT_COMPLETED, with no exact-alarm permission. Nine cloud-write flags remain false.

Logs: `/tmp/mistia-native-wallet-{policy-red,coordinator-red,coordinator-green,observer-red,observer-green,observer-invalidation-red,delivery-confirmation-red,consumed-alarm-red,cancel-recovery-red,full,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-native-wallet-reminders-v47.apk`; package/versionCode47 verified. SHA256 `adbc4083778ffb402d01ea346d414e4fc6b1df7229c705a389ff8dde5adde210`.

## Limits and next work

ADB empty; no emulator/Samsung. Alarm/worker actual timing, idle/boot/force-stop behavior, sound, channel/permission UI, tap navigation, state recreation and visual QA remain device-unverified. AndroidTests compile only. Independent review remains pending availability; direct Swift/self-review completed. No live Supabase write/deploy/migration. Immediate bill/family preference actions, card statement/installment/budget maintenance, remaining APK3–4 domains and full visual/device parity remain unfinished. Goal stays active.
