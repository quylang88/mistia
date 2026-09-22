# APK 1 offline wallet management slice — 2026-09-22

Starting point: `afce6aa`, after prerequisite Swift fixture commit `11d9568`.
This evidence covers non-credit wallet offline create/edit/archive only. It
does not claim APK 1 completion.

## Implemented behavior

- Typed all `ledger_wallets` contract fields, preserving unknown wire kinds and
  system/investment fields while blocking `creditCard` and `investment` from
  this regular editor.
- Kept money as signed `Long` minor units. Decimal input uses `BigDecimal` and
  ISO currency fraction digits; fractional JPY and overflow are rejected
  instead of rounded or converted through `Double`.
- Normalized UUIDs, currency and timestamps; cleared optional bank fields are
  emitted as explicit JSON nulls. Edits retain ID, creation time, sort order,
  remote base version and system fields.
- Added owner-scoped record lookup plus one Room transaction that writes the
  local wallet and coalesced outbox row. Account A data/outbox is not visible to
  account B. Archive is a normal upsert with `is_archived=true`, not deletion.
- Added the grouped wallet list/empty state and create/edit/archive sheet with
  iOS wallet defaults, conditional bank field, archive confirmation, all 13
  wallet icon choices and the shared 10-color preset palette.

## Parity review and corrections

Review against `ManagementView.walletsSection`,
`ManagementWalletEditorSheet`, `WalletDraft`, `LedgerWalletKind` and the wallet
cloud contract found and fixed three important mismatches:

1. Changing away from bank now clears bank-only name/preset fields.
2. Editing wallet metadata cannot rewrite an existing opening balance. iOS
   creates a balance-adjustment transaction; Android will add that in the
   transaction slice.
3. Rows/editor now render the stored `icon_symbol_name`; custom icons no longer
   silently fall back to the wallet kind.

The list currently displays opening balance because APK 1 transaction balance
aggregation is not implemented yet. Credit-card and investment rows remain
visible but require their later dedicated flows. Cloud wallet push,
retry/conflict handling and server verification remain gated.

## Automated verification

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug`: passed, 51 unit tests, 0 failures, 0 lint
  errors, debug APK assembled.
- Focused wallet suites passed model validation/serialization, owner isolation,
  outbox coalescing/archive, kind/icon state, bank validation and exact JPY/USD
  parsing. The real in-memory Room instrumented suite compiles.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities.
- Android localization generation check and strict Swift localization check:
  passed with no generated changes.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`:
  passed 4 + 133 + 460 = 597 tests, 0 failures.
- `git diff --check`: passed.

Artifact before the slice commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`d9c2b9effc4156a1a961addc997dcc45eca99f4402aa1a4ec60fa6050eff61f9`.

## Device and cloud gates

`adb devices -l` returned no connected device. The Room instrumented test and
visual/create/edit/archive checks therefore remain pending on the Samsung. Use
`adb install -r` when it reconnects so the verified Google session and local
data are retained.

`BuildConfig.ALLOW_CLOUD_WRITES` remains `false`. No wallet mutation was sent
to Supabase, and no production migration, RPC, RLS, OAuth or deployment change
was made.
