# Immediate bill maintenance on notification preference changes — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `680f8d0`.

## Behavior

Application now observes user changes to master/reminder group/detail choices and invokes the actual guarded bill maintenance coordinator immediately while master remains enabled. The bill detail does not gate money; its existing Room gate controls only presentation. Master disable cancels an in-flight preference pass without starting new due work. Foreground/background automatic money remains independently enabled by bill auto-pay settings.

Each signed-in owner gets a fresh preference baseline: startup/sign-in already has its normal maintenance pass, and a gesture from the old owner is never replayed for the replacement owner. Same-owner token refresh, family choice without master change, and history bookkeeping do not restart bill work. Legacy detail initialization is observed as a settings change. Non-cancellation local errors leave the observer available for the next change; cancellation propagates.

BillMaintenanceCoordinator accepts optional expectedOwner and verifies it after acquiring the shared mutex. A queued old-owner preference gesture cannot begin money work for a new account. Application supplies the initiating owner for these callbacks; existing foreground/background callers continue capturing their current owner normally.

Compared directly with Swift `NotificationsSettingsView.swift` master/reminder/detail onChange and runDueMaintenanceIfNeeded. This milestone wires the existing bill pass; card/budget maintenance and targeted family inbox refresh are still separate unfinished work.

## Verification

Seven runtime RED failures → GREEN: six preference observer cases plus queued replacement-owner regression. Full Android **898 JVM /97 suites**, zero failures/errors; Room/app AndroidTest compilation, lintDebug and assembleDebug pass. Swift Notification13, contracts15, both l10n checks, actual SQLite outbox7/notification3 and whitespace checks pass. Logs `/tmp/mistia-immediate-bill-preferences-{red,full,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-immediate-bill-preferences-v48.apk`; debug package/versionCode48 verified. SHA256 `b2972303504e160d391a7b5012b30b7a6921fdce288220845d81fe1521ec6ff2`.

## Limits and next work

ADB empty; no emulator/Samsung. Real settings-to-money timing/Compose and OS native delivery remain device-unverified; AndroidTests compile only. Independent review pending availability; direct Swift/self-review completed. Nine cloud flagsfalse; no live Supabase write/deploy/migration. Remaining APK2 credit-card statement/installment/budget maintenance/UI, family inbox preference refresh/actions, APK3–4 domains and full visual/device parity remain incomplete. Goal active.
