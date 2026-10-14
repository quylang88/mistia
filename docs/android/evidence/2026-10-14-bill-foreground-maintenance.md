# Foreground recurring-bill maintenance — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `70eb5e9`.

## Completed behavior

MainActivity injects the singleton account-guarded bill maintenance coordinator. Its signed-in, owner-keyed effect now runs within `repeatOnLifecycle(RESUMED)`: synchronize once per resumed foreground session, then run actual local recurring-bill maintenance immediately and every minute. Each pass receives fresh current time through the coordinator. Later ticks do not repeat network sync. Backgrounding cancels the lifecycle pass; owner change cancels the owner effect and coordinator work, while Room checks current auth before/after money and reminder writes.

A failed sync result or non-cancellation network exception still allows cached local maintenance. Local storage failures retry at the next tick. Cancellation always propagates. No notification preference gates the money hook; existing Room preference gates control only generated inbox notifications. Existing repository cycle/CAS guards prevent repeated ledger charges across ticks. No foreground OS notification posting is added here.

Direct Swift review: `Mistia/App/MistiaApp.swift` active scene hook, `Mistia/Shared/Notifications/MistiaDueMaintenance.swift` and `MistiaRecurringBillMaintenance.swift`: active-user local maintenance calls bill automatic payment independently of reminder preference. Android foreground minute polling additionally covers a local date rollover while the app stays open. Device time-zone changes within the same process still require follow-up because repository ZoneId currently comes from construction.

## Verification

Five runtime TDD RED failures → five GREEN cases: sync/local ordering and periodic execution without repeated network, offline result fallback, thrown network fallback, cancellation during sync, local storage retry. Full Android **821 JVM / 89 suites**, zero failures/errors; Room and app AndroidTests compile, lintDebug and assembleDebug pass. Swift Planning **53**, contracts **15**, both localization checks, SQLite outbox **7**, notification schema/DAO **3**, and diff whitespace pass.

Logs: `/tmp/mistia-bill-foreground-{red,full,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-foreground-v42.apk`; debug package and versionCode42 verified. SHA256 `38aba6b67f8eefcd6749219d298ce2189a597b92c4b09f862f33a143fac82eba`.

## Limits and next slice

No connected ADB/emulator/Samsung; actual lifecycle/payment timing and visual/device QA remain unverified. Room/Compose AndroidTests compile only. Independent review remains pending; self/direct Swift review completed. Nine cloud flags remain false; no live Supabase writes/deployment/migration. Background worker with cold-process auth restoration, OS notification delivery, preference-change immediate triggers, process-local time-zone changes, card/budget maintenance and full APK1–4 remain unfinished. Goal stays active.
