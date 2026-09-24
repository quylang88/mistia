# APK 1 receipt discount allocation control evidence — 2026-09-24

This bounded slice exposes the already ported exact allocator in the native
receipt review UI and guards its review-state transition.

## Scope and behavior

- A standalone discount row shows `Allocate proportionally` only when the pure
  allocator confirms a positive discount can fit within positive purchase rows.
- Allocation uses integer minor units and deterministic largest-remainder order.
  In the concrete 100 + 300 − 41 fixture, purchase discounts become 10 and 31,
  final row amounts become 90 and 269, and the standalone discount row becomes
  zero while retaining its identity and 41-unit source amount.
- An allocated row shows the generated localized `Allocated` state instead of
  offering the action again.
- A valid allocation clears only selection belonging to the edited bill. An
  ineligible purchase/discount returns no update and preserves all state.

## TDD and parity evidence

- RED: focused `ReceiptReviewStateTest` failed at Kotlin compilation because
  `allocateDiscountForReview` did not exist.
- GREEN: two new tests cover exact allocation plus target-only selection
  invalidation, and invalid-row rejection with no state mutation.
- Feature Kotlin compilation passed with the review-sheet action and allocated
  state.
- Direct iOS comparison used `itemRow` and `allocateDiscount` in
  `AIBillAnalysisView.swift`; Android uses the same action/status distinction
  and the already ported allocator semantics.
- Mutation review: changing 10/31 remainder order, leaving the discount row
  negative, clearing sibling selection or mutating an invalid request breaks a
  focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptReviewStateTest`: passed after the recorded RED run.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 7 seconds (`709` tasks).
- Result XML: 269 tests across 47 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`ee16155f06708d970a7ffe8647bcd0fd3f95fb95347b49b2b1344d0a8f0f4b61`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` remains unavailable, so no emulator/Samsung action or visual behavior is
claimed. No live Edge Function/Gemini call, production cloud write, migration
or deployment occurred. Receipt-image persistence, debt/lend persistence and
APK 1 closure verification remain outstanding; APK 1 and APK 2–4 are incomplete.
