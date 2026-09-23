# APK 1 transaction and FX contract evidence — 2026-09-23

This slice establishes the typed Android contract and validation boundary for
ordinary expenses, income and internal transfers. It deliberately precedes
repository/editor work so money, wallet direction and FX semantics are tested
before the UI can create records. It does not enable transaction cloud writes
or claim APK 1 completion.

## Scope and acceptance

- Added all `ledger_transactions` cloud fields with exact snake-case keys,
  explicit nullable values and signed 64-bit money/version fields. The model
  preserves reporting, settlement, counterparty, archive, creator/modifier and
  device metadata even though later Android slices do not edit those advanced
  domains yet.
- Added exact iOS wire values for primary kind, transfer subtype, debt intent,
  entry status and currency conversion mode.
- Added owner-scoped mutation validation for active wallets/categories,
  positive amounts, posted completeness, expense/income category-kind matching,
  and canonical UUID/UTC timestamps. Draft entries match iOS by allowing a
  positive amount before title, wallet and category are complete.
- Matched the wallet direction guards: a credit card can fund an expense, but
  cannot receive income or send an internal transfer. Internal transfers need
  distinct source/destination wallets; a credit card remains a valid payment
  destination.
- Same-currency transfers clear destination-amount and FX metadata. Cross-
  currency transfers require a positive destination amount, conversion mode,
  positive base-10 exchange rate and an ISO date when supplied. Decimal rate
  strings are retained exactly rather than converted through binary floating
  point.
- Family-transfer and debt mutations are intentionally rejected by this
  ordinary transaction draft. Those cloud-first workflows belong to APK 3 and
  must not be approximated by a local-only path.

## iOS and contract parity review

The implementation was compared with `LedgerTransaction`,
`RemoteLedgerTransaction`, `TransactionRecordSnapshot`,
`TransactionLogic.isTransactionComplete`, wallet balance-direction logic,
`MistiaCurrencyConversionMode`, and the shared `ledger_transactions` entity
schema/dependencies.

## TDD and automated verification

- Red phase: the six-test model suite failed to compile before the typed record,
  draft, enums, mutation and validation errors existed.
- Focused green coverage: full payload round-trip with explicit nulls and
  `Long.MAX_VALUE`, posted expense links, exact cross-currency metadata,
  same-currency stale-FX clearing, invalid credit-card/same-wallet/missing-FX
  combinations, and incomplete local drafts.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache`: passed in 1m 19s; 145
  tests across 30 suites, 0 failures/errors/skips; Room Android-test sources
  compiled; lint reported no errors; debug APK assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using the
  installed Command Line Tools SDK.
- Strict iOS String Catalog codegen and Android resource generation checks
  passed. No localized copy changed.
- Focused Swift tests were not run because Xcode still reports an unaccepted
  license. No Swift production source changed.
- `git diff --check`: passed before documentation finalization.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`06f0a5186ad6442b4ffa1dab3923ffc6b8d9b057d205c084aa1590f410fda5d2`.
The APK contains 634 files. Generated debug `BuildConfig` confirms the global,
category, wallet and credit-card cloud-write flags are all `false`; a
transaction write gate does not exist yet.

## Device and cloud evidence

`/Users/quylang/Library/Android/sdk/platform-tools/adb devices -l` returned no
connected device. No Samsung or instrumentation execution is claimed.

No live Supabase request, production write, migration, RLS/RPC change or
deployment occurred.
