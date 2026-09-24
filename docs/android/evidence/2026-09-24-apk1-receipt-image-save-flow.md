# APK 1 analyzed-receipt save-flow evidence — 2026-09-24

This bounded slice attaches the exact analyzed bill image to a newly created
expense transaction through the native transaction editor. It does not add
saved-receipt preview/removal, debt/lend persistence or cloud image sync.

## Scope and behavior

- `ReceiptReviewState.expenseTransactionLaunch` first reuses the guarded
  expense-draft projection, then resolves `receiptAttachmentBillId` back to the
  exact `PreparedReceiptImage` held by that reviewed bill.
- `ReceiptAnalysisSheet` enables creation only when both the transaction draft
  and its source image resolve. `TransactionsScreen` keeps that image only for
  the resulting new-transaction editor and clears it for normal new/edit and
  dismissal paths.
- The save coordinator requires a new draft, assigns one UUID, persists the
  full JPEG/thumbnail, then saves the transaction with that same UUID. Receipt
  failure prevents the transaction save, so retry cannot create a duplicate
  transaction after a late image failure.
- If transaction persistence fails after the receipt succeeds, best-effort
  cleanup removes the new receipt. The original transaction error remains the
  returned failure; cleanup failure is attached as suppressed diagnostic
  context rather than replacing it.
- A saveable receipt-required marker survives Activity recreation. Because the
  large image bytes intentionally stay out of the saved-state Bundle, a
  restored editor whose in-memory image is gone refuses to save rather than
  silently taking the ordinary receipt-less transaction branch.
- Receipt or transaction cancellation triggers best-effort cleanup in a
  `NonCancellable` context and then rethrows the original cancellation;
  cleanup failure remains suppressed diagnostic context.
- Direct iOS comparison used `AIBillAnalysisView.createTransaction` and
  `TransactionEditorSheet.persistReceiptDraftIfNeeded`: iOS passes the selected
  bill image into the editor and persists its receipt draft before saving the
  transaction context. Android preserves that ordering while compensating for
  its separate file/Room and transaction repository boundaries.

## TDD and review evidence

- RED 1: the exact-image selection test failed at Kotlin compilation because
  `expenseTransactionLaunch` and its launch model did not exist.
- GREEN 1: the review state returned the exact selected bill image together
  with the already validated expense draft.
- RED 2: save-flow tests failed at Kotlin compilation because
  `saveReceiptBackedTransaction` did not exist.
- GREEN 2: four coordinator cases passed: shared preassigned ID and ordering,
  receipt failure short-circuit, transaction-failure cleanup, and cleanup-error
  suppression.
- RED 3: the combined lifecycle/cancellation regression test source failed at
  Kotlin compilation because the missing-image guard did not exist. Review of
  the pre-fix coordinator also confirmed that `runCatching` converted
  cancellation into a failed `Result`, with no receipt-stage compensation.
- GREEN 3: the restored-editor guard and both receipt/transaction cancellation
  paths passed, with cleanup occurring before cancellation propagation.
- Focused selection/coordinator tests and `:app:compileDebugKotlin` passed.
- Mutation review: swapping a different bill image, saving the transaction
  before its receipt, continuing after receipt failure, skipping rollback or
  replacing the original save error would violate focused assertions.
- `git diff --check`: passed.

## Automated release gate

- Full command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 57 seconds (`709` tasks).
- Result XML: 281 JVM tests across 49 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test source compilation, Android lint and debug APK assembly
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`71e38ba9339f2f037dca3ab3ac4fa580eb6ff368970082aa2f34c4dc89b5f388`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` remains unavailable, so this save flow and app-private receipt files were
not exercised on an emulator or Samsung device. A process death between the
separate receipt and transaction commits can still leave an orphan receipt;
device-backed cleanup hardening remains future work. No live Edge
Function/Gemini call, production cloud write, production migration or
deployment occurred. Saved-receipt preview/removal, debt/lend persistence and
APK 1 closure remain outstanding; APK 1 and APK 2–4 are incomplete.
