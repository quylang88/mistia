# APK 1 credit-card push foundation evidence — 2026-09-23

This slice follows offline credit-card profile management and adds a separately
gated sync path for `credit_card_profiles`. It does not enable production writes
or implement statements/payments, and it does not claim APK 1 completion.

## Scope and acceptance

- Added `ALLOW_CREDIT_CARD_CLOUD_WRITES`, defaulting to `false`. The PostgREST
  gateway independently rejects card-profile writes unless that exact domain is
  allowlisted. The injected profile coordinator also requires the wallet gate,
  preventing a staged build from attempting profile creation while linked
  wallet uploads are disabled.
- Added owner-scoped profile fetch/create/conditional-update through the shared
  PostgREST mutation boundary. Create uses an array payload and update uses
  record, owner and expected `sync_version` filters; explicit nulls and signed
  64-bit credit limits remain intact.
- Added a dedicated `CreditCardPushCoordinator` over the reviewed outbox state
  machine. It provides semantic ACK, create-race refetch, conditional update,
  deterministic local/remote conflict resolution, unresolved-conflict
  retention, bounded retry, cancellation propagation and exact stale-response
  protection without a second profile-specific implementation.
- Sync orders domain coordinators by the shared contract priority, now verified
  as category → wallet → credit-card profile → pull even if dependency
  injection supplies them in reverse order. This matches the profile's remote
  wallet dependency.

## iOS and contract parity review

The implementation was checked against `RemoteCreditCardProfile`, the iOS
outbox conflict/version rules, the `credit_card_profiles` shared entity schema,
and its push priority/dependency after `ledger_wallets`. No profile field is
removed from the payload by the generic gateway.

## TDD and automated verification

- Red phase: the new coordinator suite failed to compile because
  `CreditCardPushCoordinator` and `CreditCardPushSummary` did not exist.
- Focused green coverage: 4 TLS MockWebServer PostgREST tests, 4 coordinator
  tests and the updated sync-order test. They cover owner/record/version
  filters, array create versus object PATCH, explicit nulls, a limit above
  JavaScript's exact-integer range, version increment/ACK, retry retention,
  disabled-gate behavior and wallet-before-profile ordering.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache`: passed in 41 seconds;
  139 tests across 29 suites, 0 failures/errors/skips; Room Android-test sources
  compiled; lint reported no errors; debug APK assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using the
  installed Command Line Tools SDK.
- Strict iOS String Catalog codegen and Android resource generation checks
  passed. No localized copy changed in this slice.
- Focused Swift tests were not run because Xcode still reports an unaccepted
  license. No Swift production source changed.
- `git diff --check`: passed before documentation finalization.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`136a00be17ed9baf75a1cceeafa4b87083822147a1a0212ada70e00631a7a21c`.
The APK contains 634 files. Generated debug `BuildConfig` confirms the global,
category, wallet and credit-card cloud-write flags are all `false`.

## Device and cloud evidence

`/Users/quylang/Library/Android/sdk/platform-tools/adb devices -l` returned no
connected device. No `adb install -r`, Samsung verification or live conflict
test is claimed.

All HTTP behavior used a local TLS MockWebServer. No live Supabase request,
production write, migration, RLS/RPC change or deployment occurred.
