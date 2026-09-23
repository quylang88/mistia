# APK 1 native receipt review UI evidence — 2026-09-24

This bounded slice composes the existing acquisition, preparation, analysis and
review-state foundations into one native Material 3 sheet. The sheet remains
internal until editing/apply/persistence is implemented, so users cannot enter
an incomplete flow from the Transactions screen.

## Scope and behavior

- The sheet owns a five-image review session and presents native Photo Picker
  and CameraX actions, preparation feedback, an empty state, per-bill thumbnails
  and one batch Analyze action.
- Analysis builds the same live owner-scoped category/wallet candidate sets used
  by the request builder, obtains the signed-in token only through its injected
  callback and uses the sequential partial-success coordinator.
- Each bill renders merchant, total, selected wallet, literal printed row text,
  quantity, standalone discount markers, needs-review state and full raw OCR
  text. A multiple-receipt result is blocked instead of shown as valid review
  data.
- Retry reuses the prepared image and immediately analyzes only that reset bill.
  Pending/failed images can be removed without changing siblings. Typed auth,
  size, network, quota and generic analysis errors use existing String Catalog
  resources.
- A fatal pre-batch error clears progress only for bills in the started batch;
  completed bills remain intact. Unexpected failures are converted to the typed
  invalid-response state, while coroutine cancellation still propagates.
- Dismissal is disabled during active analysis and otherwise asks for explicit
  confirmation when any image has been added. The UI uses Material theme colors
  and Mistia cards, so light/dark contrast follows the shared native theme.
- No new user-facing string was hardcoded or added. Labels and messages all use
  the generated Android resources sourced from `Mistia/Localizable.xcstrings`.

The sheet is intentionally not routed yet: it can review AI output but cannot
correct rows or persist reviewed transactions. Exposing it now would strand the
user after analysis. The entry point will be enabled with the complete apply
flow.

## TDD and review evidence

- RED: the focused state target failed to compile because the fatal-batch
  transition did not exist.
- GREEN: the added focused test proves a quota/auth-style fatal failure clears
  progress and assigns failure/quota only to started bills, preserving an
  already completed sibling.
- Existing request/state tests continue to cover candidate filtering, ordered
  partial success, cancellation, five-image capacity, literal `3@` OCR and a
  standalone coupon discount row.
- Compose compilation caught and corrected an invalid layout-scope import
  before the full gate. Android lint then passed with the sheet included in the
  application artifact.
- Static UI review covered narrow action-row sizing, scrollability for five
  itemized bills, Material theme colors, error semantics, disabled actions
  during analysis and discard confirmation. No emulator or physical-device
  visual claim is made.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptReviewStateTest`: passed, 5/5.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 56 seconds (`709` tasks).
- Result XML: 241 tests across 45 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- The unchanged full localization-audit limitation remains: full Xcode needs
  its license accepted and Command Line Tools lacks `xcstringstool`. It is not
  claimed as a passing audit.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`769ffe1c86e57a75285bf426f1b915dc9e7a7ae7740187ede44017586bd05e23`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

No live Edge Function/Gemini request, transaction/image persistence, production
write, migration or deployment occurred. The sheet was not opened on a device
and Samsung verification remains deferred. Editable review/apply/persistence
and final routing are next; APK 1 and APK 2–4 remain incomplete.
