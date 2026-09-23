# APK 1 native transaction editor evidence — 2026-09-23

This slice adds the first native create/edit surface on top of the typed
transaction contract and atomic local repository. It supports only ordinary
expense, income and internal-transfer records. It does not enable transaction
cloud writes or claim APK 1 completion.

## Scope and acceptance

- Added a saveable editor state with iOS-aligned posted-expense defaults,
  deterministic type transitions and exact currency minor-unit parsing through
  `BigDecimal`. Editing preserves transaction IDs, timestamps and exact FX
  decimal strings rather than round-tripping through binary floating point.
- Added a Material 3 bottom sheet with localized type/title/amount/note fields,
  native date and time pickers, owner-scoped active wallet selection and active
  child-category selection. Income and transfer sources exclude credit cards;
  credit cards remain valid expense sources and transfer destinations, matching
  the iOS direction contract.
- Cross-currency internal transfers expose destination amount and exchange-rate
  input. New cross-currency records use manual mode and retain the exact rate;
  an existing app-rate record can be preserved, but Android automatic rate
  lookup is deliberately deferred until a typed rate source exists.
- Saves use `FinanceRepository.saveTransaction`, which writes the local record
  and coalesced outbox mutation atomically. Changing to a same-currency transfer
  clears destination amount and all stale FX metadata at the model boundary.
- Only ordinary expense/income/internal-transfer records are editable. Family
  transfers, debt, settlement-owned, archived and deleted records remain
  read-only so incomplete APK 3 or server-owned semantics cannot be rewritten.
- Corrected the shared model boundary to require expense/income categories to
  be child categories, matching the iOS editor. Repository and Room fixtures
  now seed the required parent-child hierarchy.
- Reused generated resources from `Mistia/Localizable.xcstrings`; no catalog or
  generated localization source was edited by hand.

## Deliberate next slices

- The editor does not yet calculate current wallet balance, available credit or
  paid credit-card statement locks. Those must be implemented from the actual
  current-balance/statement rules before the UI claims affordability parity;
  historical balance must not be substituted for the current-balance rule.
- Automatic app-rate lookup and refresh remain absent. The UI never fabricates
  an app provider/rate; new cross-currency entries are manual until that source
  is implemented.
- Archive remains unavailable until paid-statement, bill-payment and related
  server-owned guards are represented. Receipt capture/analysis is also a later
  APK 1 slice.

## TDD and automated verification

- Red phase: `TransactionEditorStateTest` failed compilation before the state
  existed; the run also found that `feature:transactions` lacked its JUnit test
  dependency.
- Focused green coverage verifies new defaults, kind-dependent stale-field
  clearing, exact cross-currency minor units/rate strings, edit mapping,
  required wallet/category selection, and the ordinary-record edit boundary.
  Existing model tests additionally prove parent categories are rejected.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache`: passed in 1m 5s; 156
  tests across 32 suites, 0 failures/errors/skips; Room Android-test sources
  compiled; lint reported no errors; debug APK assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using the
  installed Command Line Tools SDK.
- Strict iOS String Catalog codegen and Android resource generation checks both
  passed. No localized copy changed.
- Focused Swift tests were not run because Xcode still reports an unaccepted
  license. No Swift production source changed.
- `git diff --check`: passed before documentation finalization.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`cea832cf82823489d1b940e1666ca86b4205531733cab957cfd481c69ed36f67`.
The APK contains 634 files. Generated debug `BuildConfig` confirms the global,
category, wallet and credit-card cloud-write flags are all `false`; a
transaction write gate does not exist yet.

## Device and cloud evidence

`/Users/quylang/Library/Android/sdk/platform-tools/adb devices -l` returned no
connected device. No Samsung UI behavior or instrumentation execution is
claimed.

No live Supabase request, production write, migration, RLS/RPC change or
deployment occurred.
