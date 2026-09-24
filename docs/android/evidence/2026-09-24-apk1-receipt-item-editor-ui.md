# APK 1 native receipt item editor evidence — 2026-09-24

This bounded slice connects the tested receipt-item editor contract to the
native review sheet and adds an explicit reviewed-row deletion path.

## Scope and behavior

- Each analyzed row now has an `Edit item` action opening a scrollable Material
  3 dialog. It edits original and translated names, purchase/discount type,
  purchase quantity, original row amount and discount amount.
- All labels/actions use generated Android resources sourced from Mistia's
  String Catalog; no new hardcoded user-facing copy was introduced.
- The final amount is recomputed live from the accepted draft. Save stays
  disabled for a blank name, invalid quantity, invalid currency precision,
  over-discounted purchase or zero standalone discount.
- Literal `rawLineText` is displayed read-only as printed evidence and is
  preserved through save.
- Save replaces the stable row identity; `Remove item` deletes it. Both actions
  clear only the affected bill's selection and preserve sibling bill state.

## TDD and parity evidence

- RED: the focused test target failed at Kotlin compilation because
  `removeItemForReview` did not exist.
- GREEN: the new deletion test plus the five item-editor contract tests passed,
  covering target deletion and sibling identity/selection preservation.
- Feature Kotlin compilation passed with the new dialog and review-sheet
  binding.
- Direct iOS comparison used `AIBillItemEditorSheet` and its row edit trigger in
  `AIBillAnalysisView.swift`; Android exposes the same editable facts, final
  amount preview, literal printed text, Save/Cancel and destructive removal.
- Mutation review: deleting the wrong row, retaining target selection, clearing
  sibling selection or allowing an invalid draft enables a focused failure.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptItemEditorStateTest`: passed, 6/6 after the recorded RED run.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute (`709` tasks).
- Result XML: 267 tests across 47 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`cd92c8c3d5e3ba0b3c9d5ad5a2ba68d692fec0f96cca390a61d50caa2bdd5df7`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` remains unavailable, so no emulator/Samsung interaction, keyboard,
scrolling or dark-mode visual behavior is claimed. No live Edge Function/Gemini
call, production cloud write, migration or deployment occurred. Discount
allocation controls, receipt-image persistence and debt/lend persistence remain
outstanding; APK 1 and APK 2–4 are incomplete.
