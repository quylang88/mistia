# APK 0 preflight on the new Mac — 2026-09-20

This is a host setup and baseline execution report. It does **not** certify
Samsung verification, production verification, or completion of APK 0/1.

## Source and scope

- Branch: `develop`.
- Commit: `2ffe485d1ff271c2f61ee623cc0fe9b93106b88b`.
- `git fetch origin`, `git checkout develop`, and `git pull --ff-only`
  succeeded; the checkout was already current and initially clean.
- Read the complete Android/contracts READMEs, feature parity ledger,
  all schema/golden files, Android CI workflow and `.gitignore`.
- Baseline application: `vn.com.quyln.mistia.debug`, version
  `0.1.0-apk0-debug`, versionCode `1`.
- No product source, iOS runtime, localization, schema, RLS or cloud write
  gate was changed. `ALLOW_CLOUD_WRITES` remains `false`.
- APK 1 → APK 2 → APK 3 → APK 4 → RC implementation has not started:
  the requested physical Samsung prerequisite remains unmet.

## Host preparation

| Component | Observation / action |
| --- | --- |
| Host | macOS 27.0, build 26A428, Apple silicon |
| Java | Installed Homebrew OpenJDK 17.0.20.1; use the `JAVA_HOME` below |
| Android command-line tools | Installed 22.0 (Homebrew archive 15859902) |
| Android SDK | Installed API 36 revision 2 at `~/Library/Android/sdk` |
| Build Tools | Installed 35.0.0, matching Android CI |
| Platform Tools / adb | Installed 37.0.1 / adb 1.0.41 |
| Android Studio | Not installed; command-line build uses the SDK directly |
| Gradle | Repository wrapper downloaded and ran Gradle 8.13 with JDK 17 |
| Local SDK configuration | Created ignored `android/local.properties`; no secrets added |
| Swift | Swift 6.4 available |
| Xcode | 27.0 (27A266a); user completed license/first launch, subsequent Swift test passed |
| Active developer directory | `/Library/Developer/CommandLineTools` |
| Docker | CLI 29.8.0 installed; daemon unavailable at initial inspection |
| Supabase CLI | Not installed / not found on PATH |
| Supabase client configuration | Existing iOS plist has HTTPS URL and publishable key; values were not printed |

JDK selection for this installation:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

The SDK license was accepted during SDK installation. No release keystore
was created. No Supabase initialization, login, linking or production
deployment was performed. Docker/Supabase setup is not needed to assemble
this production-configured APK 0.

## Checks completed

| Check | Result |
| --- | --- |
| `swift Scripts/check-android-contracts.swift` | PASS, 15 entities, exit 0 |
| `swift Scripts/generate-android-l10n.swift --check` | PASS, exit 0 |
| Swift localization generator with `--strict-keys --check` | PASS, exit 0 |
| `./gradlew testDebugUnitTest :app:lintDebug :app:assembleDebug` | PASS, exit 0, 6m 29s |
| Kotlin unit tests | PASS, 8 tests, 0 failures/errors/skips |
| Android lint | PASS with 27 warnings, no errors |
| APK signature verification (`apksigner verify --print-certs`) | PASS, debug certificate |
| `./gradlew :app:installDebug` | BLOCKED, exit 1: `No connected devices!` |
| `adb shell monkey -p vn.com.quyln.mistia.debug 1` | BLOCKED, exit 1: no devices/emulators found |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | PASS after user completed Xcode setup, exit 0, 597 tests, 0 failures |
| Initial Xcode test attempt | BLOCKED, exit 69: license not accepted; resolved by user |
| `swift test` with default Command Line Tools | FAILED before tests, exit 1: missing `SwiftDataMacros`; use full Xcode as above |
| `git diff --check` | PASS |

The initial Swift failures were toolchain/setup findings. After the user
completed Xcode setup, the full Xcode run passed `MistiaTests` (4),
`MistiaDataSupportTests` (133) and `MistiaCoreLogicTests` (460), totaling
597 tests with zero failures. No iOS source changes were needed.
`xcode-select -p` still points at Command Line Tools, so subsequent runs
must continue using the explicit Xcode `DEVELOPER_DIR` unless the user
changes the system selection.

Lint warnings: `AndroidGradlePluginVersion` (3), `GradleDependency` (10),
`NewerVersionAvailable` (12), `LockedOrientationActivity` (1),
`DiscouragedApi` (1). These are baseline findings, not a clean lint report.

## Rebuilt APK 0 artifact

- Retained path:
  `android/build/outputs/apk0/2026-09-20/mistia-0.1.0-apk0-debug-v1-2ffe485.apk`.
- Size: 26,614,231 bytes.
- APK SHA-256:
  `8e729b19cd7eb0f22e6067ecef9a53a19cf752b7d4645de08a702f92decfa638`.
- Adjacent `.apk.sha256` file contains the same checksum.
- This reproduces the unchanged APK 0 source/versionCode; it is not an
  APK 1 release and has not been installed or verified on Samsung.
- Debug certificate SHA-1:
  `354e9346c535cad69e6c086c203300781f5c4223`.
- Debug certificate SHA-256:
  `72064998df2a813facabae5e30fd1e7f7631c920e719d6bcb90008aa45d0235e`.
- Debug certificate generated on this Mac. OAuth registration for this
  certificate/package has not been verified. Google login and independent
  email/password login verification remain pending.
- If an existing APK is signed with a different certificate, do not
  uninstall it automatically or claim that update-with-data-retention
  passed. Obtain the matching signing key or agree a data-preserving test
  path with the user.

## Samsung prerequisite

`adb devices -l` returned an empty list, including after
`adb kill-server` / `adb start-server`. The macOS USB tree also showed no
attached phone at inspection time. Each requested `adb shell getprop`
command returned `adb: no devices/emulators found` (exit 1).

| Evidence field | Value |
| --- | --- |
| Manufacturer/model | Unavailable; no connected device |
| Android version/API | Unavailable |
| One UI version | Unavailable |
| Installed application version | Unavailable |
| Test flow | USB inventory, adb enumeration/restart, manufacturer/model/version/API/One UI queries |
| Result | BLOCKED; physical connection/USB debugging authorization needed |

The user was asked to connect/unlock the Samsung, enable USB debugging and
accept its RSA prompt. A test-account password must be entered directly on
the phone after installation, never provided through chat.

## Remaining release evidence

- Samsung install/launch and authenticated pulls of Overview,
  transactions, planning, family and investment.
- Cross-platform/cloud data comparison and account isolation.
- All APK 1 write flows, optional clears, dependency ordering, offline
  recovery, process death and three automatic sync cycles.
- Room migration, MockWebServer, WorkManager, Compose UI and instrumented
  coverage: the baseline currently contains only three unit-test classes
  (eight test methods); no tests from these additional suites exist yet.
- Full Samsung matrix, Google OAuth certificate registration/verification,
  and all later release gates remain pending.
- Supabase reset/pgTAP were not run: no backend changes were made, the CLI
  is absent, and the Docker daemon was not running. These remain mandatory
  before any relevant backend gate.

`contracts/feature-parity.yml` was left unchanged; no gate was promoted.
Raw local logs are kept in the ignored
`android/build/reports/preflight/2026-09-20/` directory.
