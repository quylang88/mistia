# APK 1 offline transaction repository evidence — 2026-09-23

This slice connects the typed transaction/FX contract to owner-scoped Room and
the existing read-only transaction list. It does not add the create/edit UI or
enable cloud writes, and it does not claim APK 1 completion.

## Scope and acceptance

- Added typed `observeTransactions` ordered by occurred time, creation time and
  stable ID, excluding archived rows. Pulled malformed records are isolated at
  the mapping boundary rather than parsed ad hoc by Compose.
- Added `saveTransaction`, which resolves the existing transaction, source and
  destination wallets, and category only from the active owner's local
  snapshots before invoking the typed mutation rules. Cross-account IDs cannot
  satisfy a dependency.
- Save uses the existing Room `commitMutation` transaction, atomically replacing
  the local row and coalesced outbox row. Edits retain the server base version;
  clearing same-currency FX fields writes explicit JSON nulls.
- The transaction list now consumes typed transaction and wallet streams. It
  retains the iOS-aligned source-leg amount/currency projection for internal
  transfers and no longer reaches into raw JSON for title/date/wallet IDs.

## TDD and automated verification

- Red phase: the repository suite failed to compile before
  `observeTransactions` and `saveTransaction` existed.
- Focused green coverage: owner-scoped create/outbox behavior, edit base-version
  retention with explicit FX nulls, and rejection of dependencies found only
  in another account. A new Room instrumentation test compiles and verifies the
  saved row, outbox row and account isolation through the production store.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache`: passed in 1m 16s; 148
  tests across 31 suites, 0 failures/errors/skips; Room Android-test sources
  compiled; lint reported no errors; debug APK assembly succeeded.
- Android contract and strict iOS/Android localization generation checks passed.
  No localized copy changed.
- Focused Swift tests were not run because Xcode still reports an unaccepted
  license. No Swift production source changed.
- `git diff --check`: passed before documentation finalization.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`8db61e8fc13d7f5d911a6cc3a7fce77d58eea97cd790567a4c45fbfff8042570`.
The APK contains 634 files. Existing cloud-write flags remain `false`; a
transaction write gate is still absent.

## Device and cloud evidence

ADB returned no connected device. The Room instrumentation test was compiled
but not executed, and no Samsung UI behavior is claimed.

No live Supabase request, production write, migration, RLS/RPC change or
deployment occurred.
