# APK 0 Samsung session — 2026-09-20

This session follows the new-Mac preflight report. Physical connection,
fresh installation and signed-out launch have passed. Authentication,
cloud reads and full APK 0 parity remain pending; this is not a complete
release-gate certification.

## Device and artifact

| Field | Observed value |
| --- | --- |
| Manufacturer | `samsung` |
| Model | `SM-F776Q` |
| Product / device | `b8qjpnx` / `b8q` |
| Android | `17` |
| Android API | `37` |
| One UI property | `ro.build.version.oneui=90000` (raw device value) |
| adb state | `device`, physical USB transport |
| Application ID | `vn.com.quyln.mistia.debug` |
| Installed version | `0.1.0-apk0-debug` |
| Installed versionCode | `1` |
| minSdk / targetSdk | `26` / `36` |
| Source commit | `2ffe485d1ff271c2f61ee623cc0fe9b93106b88b` |
| First install / update | `2026-09-20 11:09:47` (device-reported time) |
| APK SHA-256 | `8e729b19cd7eb0f22e6067ecef9a53a19cf752b7d4645de08a702f92decfa638` |

The existing staged README and preflight report were preserved. No
product-code changes were needed for installation. Cloud finance writes
remain disabled.

## Executed flows

1. `adb devices -l` reported the Samsung in `device` state.
2. Queried manufacturer/model/Android release/API/One UI properties.
3. Checked for existing Mistia packages; none were returned.
4. `./gradlew :app:installDebug` succeeded: `Installed on 1 device`,
   exit 0. No uninstall or application-data reset was performed.
5. `adb shell monkey -p vn.com.quyln.mistia.debug 1` launched the app,
   exit 0.
6. Activity inspection showed Mistia's `MainActivity` as the resumed
   activity; its app process was running.
7. Inspected a screenshot and UI hierarchy: Vietnamese welcome, email,
   password, disabled sign-in button for empty fields, and password reset
   action were visible. No crash screen was shown.
8. Asked the user to enter the test-account credentials directly on the
   phone. No password was requested in chat or entered through adb.
9. Scanned 502 app-process log lines in memory: no `FATAL EXCEPTION`,
   JWT-shaped token or credential-field pattern was detected. Raw logs
   were not printed or committed. This limited signed-out scan does not
   certify authenticated flows or receipt processing.
10. A later UI-state check still reported the welcome/sign-in screen.
    Only screen-state booleans were logged; field contents were not
    printed or saved.

This proves a fresh installation and signed-out launch only. It does not
prove login, restored sessions, authenticated cloud reads, account
isolation, offline recovery, accessibility, or the later APK gates.

## Read-path review finding

Static review found that both `OverviewScreen` and `TransactionsScreen`
format `amount_minor` while preferring `reporting_currency_code` over
`source_currency_code`. For different source/reporting currencies, this
can label an unconverted source amount with the wrong currency. Swift's
transaction row pairs the source amount with its source currency (and
has separate incoming-transfer behavior). Add a regression test and fix
the Android pairing before accepting cross-currency read parity. This
finding has not yet been reproduced with authenticated device data or
fixed; it is not a passed test.

## Local evidence

Ignored local files under `android/build/reports/preflight/2026-09-20/`:

- `install-samsung.log`: successful installation command output.
- `samsung-apk0-launch.png`: signed-out launch screenshot.
- `samsung-apk0-launch.xml`: signed-out UI hierarchy captured before the
  user was asked to enter credentials.

The screenshot stream included an adb/screencap multiple-display warning
before the PNG header. Only that transport prefix was removed to make the
PNG readable; image pixels were not modified.

`contracts/feature-parity.yml` has not been promoted to a passed gate.
