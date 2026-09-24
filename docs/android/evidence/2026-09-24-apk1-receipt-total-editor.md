# APK 1 receipt total editor evidence — 2026-09-24

This bounded slice adds native correction of the printed receipt total so an
otherwise valid bill can resolve its item/receipt-total mismatch before row
selection.

## Scope and behavior

- Every analyzed bill exposes an `Edit total` action backed by a native
  Material 3 dialog and generated String Catalog labels/help text.
- The editor formats existing minor units using the bill currency and parses
  input through the same exact currency-precision contract as the Android
  transaction editor. For example, USD `12.34` becomes exactly 1,234 minor
  units; zero, negative values and excess fractional precision are rejected.
- Saving updates only the targeted bill. It clears only that bill's current
  row selection so a draft cannot retain stale review totals, while sibling
  selection remains intact.
- Updating the printed total does not change item names, literal OCR, row
  amounts, quantities, categories or wallet selection.

## TDD and review evidence

- RED: focused `ReceiptReviewStateTest` failed to compile because
  `updateTotalForReview` did not exist.
- GREEN: two added tests cover USD exact precision plus target-only selection
  invalidation, and rejection of zero/excess precision.
- The shared transaction-editor minor-unit parser/formatter was made internal
  to prevent a second, drifting money parser.
- Direct iOS review used `AIBillTotalEditorSheet` and `updateBillTotal`; Android
  keeps its established decimal-major-unit editor convention while mapping
  exactly to stored minor units.
- Mutation review: accepting zero, rounding a third decimal, treating `12.34`
  as raw minor units or clearing sibling selection breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptReviewStateTest`: passed, 9/9.
- Feature debug Kotlin compilation passed after dialog binding.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 1 second (`709` tasks).
- Result XML: 261 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`c0f17edc4f6b65c81aadb9b9eb4faef637956f672073589b711472269406f305`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` remains unavailable, so no emulator/Samsung dialog or keyboard behavior
is claimed. No live Edge Function/Gemini call, production cloud write,
migration or deployment occurred. Item-fact editing, discount allocation,
receipt-image persistence and debt/lend persistence remain outstanding; APK 1
and APK 2–4 are incomplete.
