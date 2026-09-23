# APK 1 receipt item selection evidence — 2026-09-24

This bounded slice ports the iOS itemized-receipt selection, allocation, group
locking and transaction-prefill contract into Kotlin. It does not yet write a
transaction or expose selection controls in the Compose sheet.

## Scope and parity

- Expense selection requires a usable item, one source wallet and one category
  across all selected purchase rows. A standalone discount row has no category
  but may join purchases from the same wallet.
- Lend selection permits mixed purchase categories and discounts while still
  requiring a single wallet. Its prefill is a debt transfer with lend intent,
  matching iOS; Android persistence for that non-internal transfer remains a
  later domain boundary and is not claimed here.
- Changing modes normalizes selection in candidate order and drops incompatible
  rows. Created, locked, zero-amount, unavailable or wallet-less candidates are
  not selectable.
- Quantity allocation uses integer minor units and deterministic remainder
  distribution: allocating 1/2/3 units from a 101-minor, three-unit row yields
  34/68/101, with no rounding loss.
- A locked group stores exact quantity/amount allocations and is rejected when
  selected rows sum to zero or below. This prevents a discount-only transaction.
- Transaction prefills sum signed purchase/discount amounts, require a purchase
  category for expense, reuse a shared merchant/date, fall back for mixed or
  missing metadata and attach a receipt only when all rows came from one bill.

## TDD and review evidence

- RED: the focused target failed to compile because the selection IDs,
  candidates, mode, group, draft and `ReceiptItemSelectionLogic` did not exist.
- GREEN: six focused JVM tests cover expense grouping, lend grouping,
  mode-change normalization, discount arithmetic/single-bill attachment,
  lend/mixed-metadata prefill and exact quantity allocation/nonpositive-group
  rejection.
- Direct Swift parity review used `BillItemSelectionLogic` and its focused tests
  in `Tests/MistiaCoreLogicTests/BillItemAnalysisTests.swift`.
- Mutation review: accepting another wallet/category, dropping a discount sign,
  rounding 101/3 incorrectly, accepting a discount-only group, carrying a
  multi-bill image attachment or using non-shared merchant/date metadata breaks
  a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptItemSelectionTest`: passed, 6/6.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 51 seconds (`709` tasks).
- Result XML: 247 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No user-facing string changed. The known full localization-audit limitation
  remains (unaccepted full-Xcode license; no `xcstringstool` in Command Line
  Tools) and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`2b3732a73adfe1752f052491d4aec31a32cf78e24b59a8d56c7b3c25acc3e760`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

Selection is not yet bound to review controls, item correction or repository
persistence. No live AI call, production write, migration, deployment or
device verification occurred. Those UI/apply steps remain next; APK 1 and APK
2–4 remain incomplete.
