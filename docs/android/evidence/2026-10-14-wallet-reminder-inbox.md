# Persistent next-morning wallet reminders — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `9b301d0`.

## Completed behavior

Added actual low-cash-wallet inbox maintenance, invoked after bills from both foreground and the cold-process worker. Only owned, live, unarchived cash wallets with posted balance<=0 receive reminders. Existing Long balance index handles expense/income/FX/debt without converting minor values to Double. Archived shared-expense generated debt entries are excluded using owned settlement-group archive metadata, matching Swift transaction visibility.

Each pass captures current device ZoneId and schedules the next local 09:00 (today strictly before nine, otherwise next day), including DST calendar changes. Stable Swift keys/source/resource IDs, production localized title and existing exact amount formatting are used. Specialized wallet upsert advances createdAt to the next morning and updates copy while preserving read/readAt/action history, as Swift does. Obsolete dueSoon records are removed. Missing/deleted/archived or foreign wallet reminders are removed only while wallet reminder preference is enabled; disabled preferences retain wallet history. Recovered positive wallets retain history but yield no native schedule target.

Room snapshots the full raw wallet/transaction/settlement-group/notification dependencies atomically. CAS rechecks all dependencies and read state before replacing local notifications; repository retries with a fresh plan up to3 times. Current owner is checked before/after commits and in the repository. The latest wallet preference is checked at commit: disabling it prevents new/edited wallet copy while permitting obsolete cleanup. No ledger or cloud outbox mutation. Existing inbox center observes the persisted records and hides future local reminders until createdAt.

Direct Swift comparison: `MistiaLocalNotificationScheduler.swift` nextLocalMorning, low-wallet selection, specialized upsert/stale/obsolete cleanup; `MistiaDueMaintenance.swift` balance snapshot; `TransactionLogic.swift` archived shared-expense filtering. Bill notifications remain inbox-only. Native Android OS alarm/posting is still unfinished: `scheduled` describes intended future targets, not delivered OS notifications.

## Verification

Runtime TDD RED→GREEN: seven planner failures, archived shared-event filter failure, four repository failures and one background hook-order failure. Final15 added JVM cases: model9/repository5/background1. Full Android **861 JVM/93 suites**, zero failures/errors; Room, notifications and app AndroidTests compile; lintDebug/assembleDebug pass. Three new Room tests cover wallet/transaction/group CAS races, late-disabled preference and post-write owner-change rollback; **compiled only**. Swift Notification13 (8data+5core), contracts15, both l10n checks, SQLite outbox7/notification3 and whitespace checks pass.

Logs: `/tmp/mistia-wallet-reminder-plan-{red,green}.log`, `/tmp/mistia-wallet-reminder-archive-red.log`, `/tmp/mistia-wallet-reminder-repository-{red,green}.log`, `/tmp/mistia-wallet-reminder-background-hook-red.log`, `/tmp/mistia-wallet-reminder-{full,room,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-wallet-reminder-inbox-v46.apk`; package/versionCode46 verified. SHA256 `0331900f0285d1168d2b1325d5388b305750d170ec69ee50ee359949106b1266`.

## Limits and next step

No ADB/emulator/Samsung. AndroidTests compile only; no actual OS scheduling, delivery, permission/device or visual QA. Independent review remains pending availability; direct Swift/self-review completed. Nine cloud flagsfalse; no live Supabase write/deploy/migration. Next wire native next-morning schedule/delivery/cleanup with owner+latest balance/preference/permission checks, then immediate preference triggers and remaining APK2–4 domains. Full APK1–4 goal remains active.
