# APK 1 receipt Photo Picker evidence — 2026-09-24

This bounded slice connects Android's system Photo Picker contract to the
existing URI/bitmap receipt preparation pipeline without exposing an
incomplete receipt workflow in the transaction editor.

## Scope and behavior

- `ReceiptPhotoPickerButton` uses `PickVisualMedia` for the final remaining
  slot and `PickMultipleVisualMedia` for two to five remaining slots. It asks
  only for images and does not request broad media/storage permission.
- Selected `Uri` values are prepared immediately while their temporary grants
  are valid. Work is owned by the composable coroutine scope; cancellation is
  propagated rather than converted into a receipt failure.
- The shared five-image limit matches the iOS itemized bill flow. Results keep
  picker order, cap processing to the current remaining capacity and report
  excess selections explicitly.
- A typed image-preparation failure or a provider read failure is isolated to
  its selection so other valid images remain usable. Provider failures map to
  the existing decode-failure category without exposing provider details.
- The control uses the existing `transactions.aibill.addBills` String Catalog
  key. No catalog or generated localization source changed.

The reusable control is intentionally not routed from `TransactionsScreen`
yet. Showing an "Add receipt image" action in the ordinary editor would imply
attachment persistence that Android has not implemented, while exposing an AI
entry before CameraX and review/apply exist would leave a misleading partial
workflow. The upcoming analysis screen will consume this control together with
the camera source and review state.

## TDD and review evidence

- RED: the focused test target failed to compile because
  `prepareReceiptPhotoSelections`, picker limits/modes and result types did not
  exist.
- GREEN: five focused tests cover single/multiple/disabled mode selection,
  five-image/remaining-capacity enforcement, stable selection order, partial
  typed/provider failures, zero-capacity behavior and cancellation propagation.
- Mutation review: removing the cap, reordering results, aborting after one bad
  image, swallowing cancellation or choosing a multiple contract for the final
  slot each breaks a focused assertion.
- Compose integration is framework-compiled and linted. A real picker launch
  and content-provider read remain device evidence and are not claimed here.

## Automated release gate

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed in 43 seconds (`709` tasks).
- Result XML: 227 tests across 42 suites, 0 failures, 0 errors, 0 skipped.
- Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- The full localization skill audit still cannot run under Command Line Tools
  because `xcstringstool` is unavailable. The active full Xcode toolchain is
  blocked until its license is accepted; this limitation is not claimed as a
  passing audit.
- `git diff --check`: passed.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`99a21327adee9ba394c3e37d47cd70201edfab3e8699c46ef8c8285f3c8249ff`.
The APK contains 634 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

No Photo Picker UI was launched on a device, no receipt was analyzed, no
transaction or image was persisted, and no cloud request/write/deployment was
performed. Samsung verification is deferred per the user's direction. CameraX
capture and the native review/apply/persistence flow remain; APK 1 and APK 2–4
remain incomplete.
