# APK 1 receipt item editor contract evidence — 2026-09-24

This bounded slice establishes the tested domain contract for editing one
analyzed receipt row before its native Compose dialog is connected.

## Scope and behavior

- `ReceiptItemEditorState` starts from an analyzed item without mutating it and
  exposes editable original/translated names, line type, quantity, original
  row amount and discount amount.
- Amount text uses the transaction editor's exact currency-aware formatter and
  parser. USD `12.34` and `0.35` become exactly 1,234 and 35 minor units with no
  rounding; excessive precision is rejected.
- Purchase edits require a nonblank name, positive quantity and original amount,
  plus a nonnegative discount no greater than the original amount.
- Switching to a standalone discount ignores hidden purchase-only inputs,
  removes quantity/original amount/category and emits a negative final amount.
  A zero discount remains review-invalid and cannot be committed.
- Saving a valid edited row preserves `lineId`, `rawLineText`, confidence and
  unrelated metadata, clears resolved item-review flags through the shared
  `reviewed(...)` model, and invalidates only the edited bill's selection.

## TDD and parity evidence

- RED: the focused test target failed at Kotlin compilation because
  `ReceiptItemEditorState` and `updateItemForReview` did not exist.
- GREEN: five new tests cover literal `3@` Japanese OCR preservation, JPY
  purchase recomputation, exact USD decimals, purchase-to-discount
  normalization, invalid input rejection and target-only selection invalidation.
- Direct iOS comparison used `AIBillItemEditorSheet` in
  `Mistia/Features/Transactions/AIBillItemReview.swift`: the Android contract
  exposes the same editable facts and delegates final arithmetic/type cleanup
  to the same ported reviewed-item semantics.
- Mutation review: rewriting raw OCR, accepting a zero quantity, rounding a
  third USD decimal, keeping category on a discount or clearing sibling
  selection breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptItemEditorStateTest`: passed, 5/5 after the recorded RED run.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 58 seconds (`709` tasks).
- Result XML: 266 tests across 47 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`51c5cbeb5f8f3a88c7e40a81b1f9dcbf70199153cbd84d7730d41b8032997a71`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` remains unavailable, so no emulator/Samsung editor behavior is claimed.
No Compose editor was added in this slice. No live Edge Function/Gemini call,
production cloud write, migration or deployment occurred. Item-editor UI,
discount allocation controls, receipt-image persistence and debt/lend
persistence remain outstanding; APK 1 and APK 2–4 are incomplete.
