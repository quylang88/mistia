# APK 1 transaction push foundation evidence — 2026-09-23

This slice wires the existing transaction outbox into the shared conflict-safe
cloud push engine. It deliberately leaves the transaction production gate off
and does not claim full transaction or APK 1 parity.

## Scope and safety boundary

- Added `TransactionPushCoordinator` for `CloudEntity.LEDGER_TRANSACTION`.
  It delegates to the same generic outbox engine already used by category,
  wallet and credit-card profile pushes.
- New transaction rows create at sync version 1. Existing rows update only
  against the fetched remote version. Exact semantic matches acknowledge
  without another write; conflicts, stale acknowledgements, retry backoff and
  safe error codes remain centralized in `OutboxPushCoordinator`.
- Transaction push runs after category, wallet and credit-card profile push and
  before pull. This preserves the remote foreign-key dependency order for
  source/destination wallets and categories.
- Added `ALLOW_TRANSACTION_CLOUD_WRITES`, defaulting to `false`. Both the
  coordinator and PostgREST writable-entity allowlist additionally require the
  category and wallet domain gates. Enabling only the transaction flag cannot
  send a request.
- No migration, RLS/RPC change, production request or cloud mutation occurred.
  All five generated debug write gates remain `false`.

## TDD and automated verification

- RED: the focused sync test failed compilation because
  `TransactionPushCoordinator` and `TransactionPushSummary` did not exist.
- GREEN: transaction-specific tests now cover create/acknowledge with preserved
  wallet/category IDs and amount, conditional update versioning, retryable
  network failure retention, and disabled-gate no-op behavior.
- The sync-order regression passes with input coordinators deliberately
  shuffled and proves category -> wallet -> card profile -> transaction -> pull.
- Shared generic coordinator tests continue to cover semantic-match
  acknowledgement, HTTP 409 conflict resolution, unresolved conflict retention,
  stale responses, permanent errors and bounded retry behavior.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed from a clean build in 3m 27s; 168
  tests across 34 suites, 0 failures/errors/skips; Room Android-test sources
  compiled; lint reported no errors; debug assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using
  Command Line Tools. Strict iOS String Catalog and Android localization checks
  passed; no localized copy changed.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`ddfeca1f1dcd9174cf24f89063fc723e39c7e54045240c7f5ffcfb1855ce3ee4`.
The APK contains 634 files.

## Samsung verification

ADB reported Samsung `SM-F776Q` (`R5GL72ERETZ`). `adb install -r` updated the
debug APK successfully with the existing certificate and retained app data.
A launcher cold start completed in 588 ms, Mistia `MainActivity` became the
resumed activity, and the authenticated Vietnamese overview rendered with its
transaction navigation and recent-transaction section. No crash was recorded.

The device run verifies packaging, Hilt wiring and authenticated cold launch.
It is intentionally not a live transaction-push test because the transaction,
wallet, category, credit-card and legacy global write gates are all disabled.
