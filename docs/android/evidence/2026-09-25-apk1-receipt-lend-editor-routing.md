# APK 1 receipt Lend editor routing evidence — 2026-09-25

This bounded slice connects reviewed receipt rows in Lend mode to the native
standalone debt editor and the existing local receipt-backed save pipeline. It
does not claim the remaining iOS locked-group/completion UI or APK 1 closure.

## Scope and parity

- Receipt review now exposes native Expense and Lend modes. Changing mode
  re-normalizes the current selection in candidate order. Lend permits mixed
  purchase categories and disables category editing, but retains the existing
  one-bill, one-wallet, positive-total and reviewed-result guards.
- `ReceiptReviewState.transactionLaunch` projects the selected quantities using
  the active mode and resolves `receiptAttachmentBillId` back to that exact
  bill's `PreparedReceiptImage`. The create action stays disabled if either the
  transaction draft or matching image cannot be resolved.
- The editor bridge accepts only the already-supported Expense shape or the
  exact posted `transfer/debt/lend` shape. Lend carries merchant, exact minor
  units, occurrence time and source wallet while leaving destination and
  category empty.
- Saveable editor state now includes debt intent and counterparty. A receipt
  Lend displays a locked Lend context, accepts bank/cash and credit-card source
  wallets, requires a counterparty and sends debt intent/counterparty through
  `TransactionDraft`. Destination and FX controls are absent.
- Standalone posted Lend records can be reopened in the same native editor.
  Settlement-owned records, family transfer, unsupported debt intents and
  non-posted debt stay read-only.
- `TransactionsScreen` routes both supported receipt modes through the existing
  `TransactionReceiptEditorState.pending` and `saveReceiptBackedTransaction`
  path. The exact image is persisted before the transaction under one UUID;
  image failure blocks the transaction and a later transaction failure or
  cancellation triggers the existing best-effort compensation.

Direct parity review used iOS `AIBillAnalysisView` mode normalization and exact
bill-image handoff plus `TransactionEditorSheet`'s locked debt prefill,
counterparty, debt-wallet and receipt-persistence behavior.

## TDD and review trail

- RED: the focused feature tests failed at Kotlin compilation because the
  generic mode-aware launch, debt editor bridge, debt state fields and
  counterparty validation did not exist.
- GREEN: focused selection/editor tests cover exact-image Expense and Lend
  launches, mixed-category Lend projection, required counterparty, emitted debt
  draft, standalone Lend edit eligibility and save/restore of debt editor state.
- Review found that the editor originally rejected only a whitespace-empty
  counterparty, so a punctuation-only value could reach receipt persistence
  before the repository rejected it. A focused regression failed first; the
  editor now uses the shared domain counterparty normalizer and rejects values
  such as `！ -- ` before any persistence begins.
- Final review after that correction reported no Critical or Important finding.
- The entire `feature:transactions` unit suite passed after Compose binding.
- `git diff --check`: passed.

## Automated release gate

- Full Android command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 54 seconds (`709` tasks: 27 executed, 682
  up-to-date).
- Result XML: 307 JVM tests across 50 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test source compilation, Android lint and debug APK assembly
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains: the Xcode license is not accepted and Command Line Tools do not
  provide `xcstringstool`; the full audit is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`d9968041e3dba5d62385aa5f76692d780a2a9945e5ec16be889cd2d8541f4584`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` is unavailable, so the mode selector, debt editor, receipt attachment and
dark-mode presentation were not exercised on an emulator or Samsung device.
No live Gemini/Edge Function request, Supabase write, migration or deployment
occurred. The Android review currently launches directly from a valid
selection; iOS-style locked allocation groups and marking allocations created
only after a successful editor save remain the next APK 1 parity slice.
