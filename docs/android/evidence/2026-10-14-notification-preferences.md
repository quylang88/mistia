# Native notification preferences — 2026-10-14

Branch: `codex/android-apk2-4-parity`; baseline `966d991`.

## Behavior and direct Swift review

Native Management → Notifications settings persists device-level master, four reminder choices and family choice using the Swift UserDefaults keys. Default master is off; first enable selects all reminders and disables family. Master disable preserves choices; last active group disabled resets first-enable history. Legacy missing details initialize separately on appearance, preserving family and normalizing active-group history. Compared directly with `Mistia/App/MistiaAppearance.swift` and `Mistia/Features/Settings/NotificationsSettingsView.swift`.

Android 13+ notification permission is requested from an explicit master-enable action, never opening settings or launching the app. Denial preserves the in-app choice. OS posting remains a separate unfinished slice.

Room checks the latest bill preference at notification commit. Disabled reminders suppress new/edited reminder copy and automatic success companions, while existing actionable history can resolve. Money payment and localized transaction title remain independent of reminder preference. Family inbox pull is gated before fetch and again before cache replacement, retaining cached history when disabled.

## Verification

Runtime RED/GREEN: five initial preference cases, disabled reminder history/resolution policy, disabled success companion preserving actual payment/title, two family pull races, legacy settings initialization regression. Final full Android: **808 JVM tests / 87 suites**, zero failures/errors; Room and planning/notifications/settings AndroidTests compiled; lintDebug and assembleDebug passed. Swift Notification: **13 tests** (8 data + 5 core) passed. Contracts **15**, Android localization, strict Swift localization, SQLite outbox **7**, notification schema/DAO **3**, and diff whitespace checks passed.

Logs: `/tmp/mistia-notification-preferences-{red,initialization-red,full,swift}.log`, `/tmp/mistia-notification-preference-{policy-red,money-red,gates-green,integration-green}.log`, `/tmp/mistia-notification-family-preference-red.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-notification-preferences-v40.apk`; verified debug package, versionCode40. SHA256: `60340dd403887265bd4f5005966336d1a5d5285a9def0338ce990be1e694d156`.

## Limits and remaining work

ADB has no devices. SharedPreferences recreation, Room late-preference transactions and Compose interaction tests compile only; no emulator/Samsung runtime or visual QA. Independent review remains pending reviewer availability; direct Swift comparison and self-review completed. Nine cloud-write flags remain false; no live Supabase writes/deploy/migration. Guarded foreground/background maintenance, OS delivery, family/card/investment actions, Fluent visual parity and full APK1–4 are unfinished. This milestone does not complete the goal.
