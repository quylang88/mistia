# Mistia Android

Native Android client for Mistia. It shares backend/data/localization contracts with the Swift app, but not runtime code.

## Requirements

- JDK 17
- Android SDK 36, Build Tools 35.0.0, Platform Tools (matching CI)
- `local.properties` with `sdk.dir=...`

## New Mac setup

Do not rely on SDKs, keystores or build caches from another Mac. For a
Homebrew installation of JDK 17 and the Android command-line tools:

```bash
brew install openjdk@17 android-commandlinetools android-platform-tools
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
sdkmanager --sdk_root="$ANDROID_HOME" "platforms;android-36" "build-tools;35.0.0" "platform-tools"
```

Accept the SDK license when prompted. Create `android/local.properties`
with `sdk.dir` pointing at this Mac's SDK, preserving any existing local
configuration. This file is ignored by Git. Android Studio is optional for
the command-line build.

Swift regression tests require the full Xcode toolchain, including its
SwiftData macro plugin. Complete Xcode's license and first-launch setup,
then use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for
the Swift test command if `xcode-select -p` still points at Command Line
Tools.

Supabase CLI and Docker are needed for local database/RLS/RPC verification,
not for building the production-configured app. The existing
`supabase/config.toml` must not be reinitialized.

## Backend configuration

Supabase configuration is resolved in this order at build time:

1. `MISTIA_SUPABASE_URL` and `MISTIA_SUPABASE_ANON_KEY` environment variables.
2. `mistia.supabase.url` and `mistia.supabase.anonKey` in untracked `local.properties`.
3. The existing `../Mistia/MistiaSyncConfig.plist` used by the iOS app.

No service-role key is accepted or required.

## Commands

```bash
# From android/, with JAVA_HOME set to JDK 17:
./gradlew testDebugUnitTest :app:lintDebug :app:assembleDebug
./gradlew :app:installDebug
adb shell monkey -p vn.com.quyln.mistia.debug 1

# From the repository root:
swift Scripts/check-android-contracts.swift
swift Scripts/generate-android-l10n.swift --check
swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift --strict-keys --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Cloud writes are enabled per domain only after that domain's contract, retry,
conflict and physical-device gates pass. The wallet push path is wired but
`ALLOW_WALLET_CLOUD_WRITES` remains disabled in the current build; the legacy
global `ALLOW_CLOUD_WRITES` switch also remains disabled.

## Physical Samsung gate

Before feature implementation, verify `adb devices -l` lists the Samsung
in `device` state. On the phone, enable USB debugging, unlock it and
accept the RSA prompt. macOS does not require a Samsung USB driver.
An empty list or `unauthorized` state does not qualify as device evidence.

Record the manufacturer, model, Android version/API, One UI version when
available, app version/versionCode, source commit and test results under
`docs/android/evidence/`. The user enters the test-account password
directly on the phone. A successful build alone does not pass the device
gate or establish cloud/iOS parity.
