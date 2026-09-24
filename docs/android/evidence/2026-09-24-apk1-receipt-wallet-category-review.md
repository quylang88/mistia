# APK 1 receipt wallet/category review evidence — 2026-09-24

This bounded slice lets a user correct missing or incorrect receipt wallet and
purchase-category metadata before selecting rows for an expense transaction.

## Scope and behavior

- Each analyzed bill exposes a native Material 3 wallet choice menu populated
  from the same ordered, active, owner-scoped wallet candidates sent to receipt
  analysis. Archived/deleted wallets and the investment-profit system wallet do
  not re-enter through the review UI.
- Each purchase row exposes an expense child-category choice menu using the
  same active, owner-scoped, balance-adjustment-excluding candidates and
  locale-resolved names sent to the AI. Discount rows remain uncategorized.
- The current wallet/category is visible; a missing value uses the existing
  generated choose-wallet/choose-category copy.
- Changing wallet or category invalidates only that bill's current selection.
  This prevents a selection built against stale grouping metadata from being
  applied, while preserving any sibling-bill selection state.
- Literal OCR row text, amount, quantity and discount facts remain unchanged by
  these metadata corrections.

## TDD and review evidence

- RED: focused `ReceiptReviewStateTest` failed to compile because the guarded
  wallet/category review reducers did not exist.
- GREEN: two added tests prove each edit updates the target metadata, clears
  only target-bill selection and preserves sibling selection.
- Direct iOS review used `walletRow`, the item category menu and
  `BillItemSelectionSnapshot` behavior in `AIBillAnalysisView`.
- Mutation review: retaining stale target selection, clearing all selection, or
  mutating the sibling bill breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptReviewStateTest`: passed, 7/7.
- Feature debug Kotlin compilation passed after Compose binding.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 2 seconds (`709` tasks).
- Result XML: 259 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`a21adc976c039bea45a3159764f934d166e640e7cfcf90f75840945f59a29510`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` is not installed on this host, so no emulator/Samsung menu, camera or
Photo Picker behavior is claimed. No live Edge Function/Gemini call, production
cloud write, migration or deployment occurred. Total and item fact editors,
discount allocation, receipt-image persistence and debt/lend persistence remain
outstanding; APK 1 and APK 2–4 are incomplete.
