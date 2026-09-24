# APK 1 receipt selection and editor routing evidence — 2026-09-24

This bounded slice exposes the existing receipt pipeline from Transactions,
adds selectable reviewed rows and routes a valid expense selection into the
native transaction editor for the existing offline save flow.

## Scope and behavior

- Transactions now exposes the generated String Catalog `AI Bill` action next
  to the ordinary new-transaction action. `MainActivity` supplies the injected
  receipt client and a freshly refreshed authenticated access token.
- Each valid analyzed row has a native Material 3 checkbox. Selection is
  constrained to one bill, one wallet and one purchase category; a standalone
  discount remains compatible with its purchase group.
- Bills whose total/items still require review cannot be selected or converted
  into a transaction. Multiple-receipt images and failed/pending bills remain
  blocked by the existing review state.
- The create action becomes enabled only when the selected rows produce a
  positive, valid expense draft. It closes the receipt sheet and opens the
  existing transaction editor with merchant, exact amount, date, wallet and
  category prefilled.
- Saving remains an explicit user action in the ordinary editor and uses the
  existing offline repository path. Lend/debt is deliberately not exposed
  because native Android debt-transfer persistence is not implemented yet.
- Retrying or removing a bill clears only that bill's selection so stale item
  IDs cannot be applied to a replacement result.

## TDD and review evidence

- RED: the focused selection test failed to compile because
  `expenseTransactionDraft` did not exist.
- GREEN: two added tests cover exact partial-quantity projection into a draft,
  and rejection of flagged/cross-bill selections.
- The tests use literal expected minor units and real review/selection domain
  objects; no mock behavior is asserted.
- Direct review compared the selection, grouping, receipt validation and
  transaction-prefill path with the iOS `AIBillAnalysisView` and its
  `BillItemSelectionSnapshot` contract.
- Mutation review: removing the single-bill guard, allowing `requiresReview`,
  skipping normalization or projecting full rather than selected quantity
  breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptItemSelectionTest`: passed, 10/10.
- Feature and app debug Kotlin compilation passed after the Compose binding.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 2 seconds (`709` tasks).
- Result XML: 257 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`499e7eee590d6513f762d8df667a9152867e1fdbd8b911d1675c697ff96c78c3`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb devices -l` could not run because `adb` is not installed on this host;
therefore no emulator or Samsung UI/camera/Photo Picker verification is
claimed. No live Edge Function/Gemini request, production cloud write,
migration or deployment occurred. Receipt-image persistence, editable review
controls and lend/debt persistence remain outstanding; APK 1 and APK 2–4 are
incomplete.
