# APK 1 category-name translation evidence — 2026-09-23

This slice follows the category push foundation and implements the remote
category-name translation lifecycle as a separate, reviewable change. It does
not enable a financial cloud-write domain or claim APK 1 completion.

## Scope and acceptance

- Saving a category immediately persists the iOS-equivalent localized fallback
  and atomically coalesces both the category sync mutation and an account-
  scoped translation request. Room schema v2 adds
  `category_translation_outbox`; migration 1→2 only creates that local table
  and its owner/due-time index.
- `SupabaseCategoryNameTranslator` posts `name` and `source_language` (`vi`,
  `en`, or `ja`) to `/functions/v1/translate-category-name`, with the existing
  anon key and refreshed bearer session. It trims the three snake-case result
  fields and never includes the response body in an exception message or
  persisted retry code.
- The coordinator checks the current local category's exact `updated_at`
  before the request and again inside the Room apply transaction. A late
  response cannot overwrite a newer edit, consume its replacement translation
  task, or remove its newer cloud mutation.
- Missing/unchanged translations and every service, auth, decoding or network
  failure remain pending with exponential retry from 30 seconds up to 6 hours,
  matching iOS's keep-pending behavior. Coroutine cancellation is rethrown.
  A mutex coalesces management-entry, post-save and sync-triggered runs.
- Maintenance scans at most 200 active owner-scoped categories and matches the
  iOS source heuristic for older/pulled records missing localized names:
  Japanese text first, then an English legacy name, otherwise Vietnamese. It
  excludes archived, deleted and system categories and uses insert-if-absent
  so a newer local request wins.
- Translation runs before category push during Sync Now. The management screen
  also starts maintenance on entry and schedules it after a successful save,
  while the saved editor result remains available offline.

The iOS resolver first tries Apple's installed Translation framework. That API
does not exist on Android, so this slice implements the explicitly requested
remote branch while preserving the same fallback, maintenance, retry and
stale-response semantics.

## iOS parity review

The implementation was compared directly with:

- `CategoryNameTranslations.fallback`, `CategoryNameTranslationService`,
  `CategoryNameTranslationResolver`, and
  `CategoryNameTranslationMaintenance`;
- `ManagementEditors.save`, `scheduleCategoryNameTranslation`, and its
  `savedUpdatedAt` guard;
- `supabase/functions/translate-category-name/index.ts` request/response
  contract and fallback behavior.

## TDD and automated verification

- Red phase: model tests failed to compile before language wire values,
  fallback/merge models and legacy-source inference existed; network tests
  failed before the Edge Function client; coordinator tests failed before the
  queue/apply API and coordinator existed. Later regressions proved that a 401
  was incorrectly frozen and that concurrent maintenance translated one task
  twice before those behaviors were fixed.
- Focused green coverage: 4 model tests, 2 TLS MockWebServer client tests and 7
  coordinator tests. The 8-test category repository suite also verifies atomic
  owner-scoped translation enqueueing. Three Room translation tests and the
  migration test compile for instrumentation execution.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug`: final pass in 1m 16s; 120 unit tests across
  24 suites, 0 failures/errors/skips; Room Android-test sources compiled; lint
  reported no errors; debug APK assembly succeeded. The focused coordinator
  suite was rerun after the final cleanup and passed 7/7.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using
  the installed Command Line Tools SDK because Xcode itself requested license
  acceptance.
- `swift Scripts/generate-android-l10n.swift --check`: passed with the same
  explicit Command Line Tools SDK.
- Strict `Mistia/Localizable.xcstrings` generation check: passed with the same
  explicit Command Line Tools SDK.
- Focused Swift package tests were attempted but not claimed: Xcode's toolchain
  stopped at the unaccepted Xcode license, while the standalone Command Line
  Tools compiler lacks the `SwiftDataMacros` plugin. The same 22
  `MistiaSyncOutboxTests|MistiaSystemCategoryRemoteApplyTests` tests passed in
  the immediately preceding category-push slice; they were not rerun here.
- `git diff --check`: passed.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`09b88c1bcc544b5d8ec385711c293ceb17e8d7b032f4a00963381de63a5bba76`.
The APK contains 634 files. Generated debug `BuildConfig` confirms
`ALLOW_CLOUD_WRITES`, `ALLOW_WALLET_CLOUD_WRITES`, and
`ALLOW_CATEGORY_CLOUD_WRITES` are all `false`.

## Device and cloud evidence

`/Users/quylang/Library/Android/sdk/platform-tools/adb devices -l` returned no
connected device. No `adb install -r`, emulator run, Room instrumentation run,
or Samsung behavior is claimed.

All HTTP behavior was exercised against a local TLS MockWebServer. No live
Supabase request, Edge Function invocation, production database migration,
RLS/RPC change, OAuth change or deployment occurred.
