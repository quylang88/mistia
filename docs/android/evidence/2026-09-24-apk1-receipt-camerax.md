# APK 1 receipt CameraX evidence — 2026-09-24

This bounded slice adds lifecycle-aware native receipt capture using CameraX
and feeds the captured JPEG through the same preparation contract used by the
system Photo Picker.

## Scope and behavior

- The version catalog pins the current stable CameraX `1.6.2` artifacts for
  core, Camera2, lifecycle and `PreviewView`. The module uses the official
  `Preview + ImageCapture + ProcessCameraProvider` lifecycle pattern.
- `ReceiptCameraButton` checks optional camera hardware before requesting the
  already-declared `CAMERA` permission. Denial, unavailable hardware, provider
  binding failure and capture failure are distinct typed results for the future
  analysis screen.
- The sheet binds only the back camera while composed and unbinds its own
  preview/capture use cases on disposal. `PreviewView` uses compatible mode for
  predictable rendering inside Compose.
- A capture uses quality-oriented JPEG output in an isolated app-cache
  `receipt-captures` directory. It is passed as a file URI to
  `AndroidReceiptImagePreparer`, preserving CameraX EXIF rotation handling.
- Every temporary file is deleted after successful preparation, typed/provider
  failure or coroutine cancellation. Sheet disposal and CameraX capture-error
  callbacks also perform idempotent cleanup.
- The UI reuses existing String Catalog keys for receipt title, cancel and take
  photo. No catalog or generated localization source changed.

Like the Photo Picker foundation, this control is not yet routed from the
ordinary transaction editor. Camera capture belongs to the itemized AI flow,
and exposing it before review/apply and persistence exist would strand a user
after capture.

## TDD and review evidence

- RED: the focused target failed to compile because the camera entry action,
  capture-file factory and preparation/cleanup function did not exist.
- GREEN: five focused JVM tests cover permission/hardware decisions, unique
  isolated `.jpg` targets, successful cleanup, typed-failure cleanup and
  cancellation cleanup/propagation.
- Mutation review: requesting permission on a camera-less device, reusing an
  output path, writing outside the isolated directory or omitting any cleanup
  branch breaks a focused assertion.
- CameraX Compose/framework code compiled and passed Android lint. Preview,
  permission dialog, back-camera binding, shutter, rotation and actual image
  quality require physical-device evidence and are not claimed here.

## Automated release gate

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed in 4 minutes 37 seconds (`709`
  tasks; the new CameraX dependency graph was rebuilt).
- Result XML: 232 tests across 43 suites, 0 failures, 0 errors, 0 skipped.
- Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully. Existing deprecation warnings in `core:auth` and the
  native-library strip notice remain unrelated and non-fatal.
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
`4939d447f0e00c94b32a17f999f0a160e47438d0887d130869cce3dc323d1020`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

No camera was opened or permission decision made on a device, no receipt was
analyzed, no transaction/image was persisted and no cloud request/write or
deployment occurred. Samsung verification remains deferred per the user's
direction. The native analysis/review/apply flow is next; APK 1 and APK 2–4
remain incomplete.
