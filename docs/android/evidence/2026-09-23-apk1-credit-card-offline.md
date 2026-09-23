# APK 1 offline credit-card profile evidence — 2026-09-23

This slice adds native offline credit-card account management after the wallet
and category slices. It does not enable credit-card cloud push, statements or
payments, and it does not claim APK 1 completion.

## Scope and acceptance

- Added typed `credit_card_profiles` mapping with the exact cloud field names,
  signed 64-bit minor units and sync versions, explicit JSON nulls, canonical
  UUIDs/timestamps, and all six iOS card-network wire values.
- A save builds a linked `ledger_wallets` credit-card row and profile row while
  preserving each record's independent base version, creation timestamp and
  the profile's existing `auto_pay_enabled`. New cards use the iOS defaults:
  closing day 10, payment day 26 and auto-pay enabled.
- Room commits both local records and both coalesced outbox rows in one
  transaction. The aggregate boundary rejects cross-owner data, a non-card
  linked wallet, a mismatched wallet/profile pair, invalid days/limit/last-four
  digits, archived/card/self payment sources, invalid currency and invalid
  color.
- The management screen now observes owner-scoped profiles, offers separate
  wallet and credit-card entry points, routes card rows to a dedicated native
  Compose editor, and displays issuer/last-four plus the card's labelled credit
  limit instead of presenting its zero metadata opening balance as useful card
  state.
- The editor covers name, issuer, network, last four digits, credit limit,
  currency, statement/payment days, same-owner active non-card payment source,
  notes and the shared wallet color palette. Existing generated Android
  resources are used for static copy; the String Catalog and generated files
  did not need changes.

Credit-limit-versus-current-debt validation, payment-source-change confirmation
with outstanding debt, and credit-card archive guards depend on transaction and
statement parity that Android does not yet have. The editor therefore does not
offer card archive in this slice instead of weakening the iOS protections.

## iOS parity review

The implementation was compared directly with:

- `CreditCardProfile` in `ManagementModels.swift` and
  `RemoteCreditCardProfile` in `MistiaSyncModels.swift`;
- `CreditCardNetwork` in `FinanceEnums.swift`;
- `WalletDraft` defaults and the credit-card editor/save path in
  `ManagementEditors.swift`;
- `MistiaWalletPickerAccessLogic` for payment-source eligibility; and
- `credit_card_profiles` in the shared cloud-entity contract and Supabase
  schema.

## TDD and automated verification

- Red phase: the editor-state suite failed to compile before
  `CreditCardEditorState` and its validation contract existed. Model and
  repository suites likewise failed to compile before the typed contract,
  repository methods and aggregate Room commit boundary were implemented.
- Focused green coverage: 4 model tests, 3 repository tests and 4 editor-state
  tests. They cover explicit nulls/`Long` values, independent base versions,
  owner isolation, atomic aggregate delegation, invalid card/payment-source
  rules, iOS day defaults, last-four normalization and editor mapping. The new
  Room instrumentation test compiles and verifies both records and outbox rows.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache`: passed after removing
  only regenerable Gradle/build artifacts when the first lint attempt exhausted
  disk space; 131 tests across 27 suites, 0 failures/errors/skips; Room Android
  test sources compiled; lint reported no errors; debug APK assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using the
  installed Command Line Tools SDK.
- Android resource generation check, strict iOS String Catalog codegen,
  `xcstringstool` dry-run compilation and the localization source audit all
  passed. `xcstringstool` was invoked directly from Xcode because Command Line
  Tools does not include that executable.
- Focused Swift tests were not run: Xcode still reports that its license has not
  been accepted. No Swift production source changed in this slice.
- `git diff --check`: passed before documentation finalization.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`7cb05b94caa88292de4b175a8b5a1efcd7b10a643e166fc36572546cade91737`.
The APK contains 634 files. Generated debug `BuildConfig` confirms
`ALLOW_CLOUD_WRITES`, `ALLOW_WALLET_CLOUD_WRITES`, and
`ALLOW_CATEGORY_CLOUD_WRITES` are all `false`.

## Device and cloud evidence

`/Users/quylang/Library/Android/sdk/platform-tools/adb devices -l` returned no
connected device. No `adb install -r`, Room instrumentation execution or
Samsung visual/create/edit verification is claimed.

No live Supabase request, production write, database migration, RLS/RPC change,
OAuth change or deployment occurred. Credit-card outbox rows remain local while
the domain-specific push gate/coordinator is still absent.
