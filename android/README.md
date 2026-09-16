# Mistia Android

Native Android client for Mistia. It shares backend/data/localization contracts with the Swift app, but not runtime code.

## Requirements

- JDK 17
- Android SDK 36, Build Tools 36.x, Platform Tools
- `local.properties` with `sdk.dir=...`

Supabase configuration is resolved in this order at build time:

1. `MISTIA_SUPABASE_URL` and `MISTIA_SUPABASE_ANON_KEY` environment variables.
2. `mistia.supabase.url` and `mistia.supabase.anonKey` in untracked `local.properties`.
3. The existing `../Mistia/MistiaSyncConfig.plist` used by the iOS app.

No service-role key is accepted or required.

## Commands

```bash
./gradlew :app:assembleDebug
./gradlew test
cd .. && Scripts/generate-android-l10n.swift --check
```

APK 0 is intentionally pull-only. The write path stays disabled until its feature gate has contract/golden coverage.
