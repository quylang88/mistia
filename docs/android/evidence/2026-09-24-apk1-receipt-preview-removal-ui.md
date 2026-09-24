# APK 1 saved-receipt preview/removal evidence — 2026-09-24

This bounded slice binds the tested receipt-editor state contract to the native
transaction editor. It covers local saved-receipt loading, thumbnail/full-image
preview and explicit deferred removal. It does not claim device visuals or APK
1 completion.

## Scope and behavior

- Opening an existing transaction loads owner-scoped receipt metadata first.
  No metadata means no image-file reads and no receipt section.
- A stored thumbnail is rendered in a Material 3 card with generated localized
  copy and a platform-formatted file size. Tapping it opens a full-image dialog.
  Full-image bitmap decoding runs on `Dispatchers.Default`; the thumbnail uses
  the repository's already bounded thumbnail bytes.
- Remove clears a pending analyzed image immediately. For a stored receipt it
  records delete intent; Save persists the transaction first and deletes the
  local receipt only after that save succeeds. A failed transaction save leaves
  the receipt untouched, and a later deletion failure remains retryable.
- Activity recreation saves only three booleans: pending-image requirement,
  stored-receipt presence and deferred-delete intent. Large image bytes are not
  placed in saved state. A restored pending receipt without bytes still refuses
  a silent receipt-less save; a restored stored receipt reloads its preview.
- If metadata exists but the image or thumbnail file is missing/corrupt, the UI
  shows the localized load error while preserving stored-receipt presence and
  the Remove action. Saving without pressing Remove does not delete metadata.
- Cancellation from metadata/image/thumbnail loading and transaction/deletion
  persistence is propagated rather than converted into an ordinary error.

## TDD and review evidence

- RED 1: loader tests did not compile before `loadStoredReceiptEditorState`
  existed. They specify absent-metadata short-circuiting, ordered full/thumbnail
  loading and no partial preview on file failure.
- GREEN 1: the initial loader/UI binding passed 13 focused
  `TransactionReceiptEditorStateTest` cases and app Kotlin compilation.
- Review found an important recovery gap: after metadata succeeded but a file
  read failed, returning only failure hid Remove and made the orphaned receipt
  impossible to clear.
- RED 2: the recovery assertion, Saver round-trip cases and cancellation case
  failed to compile before the load-result/state helpers existed.
- GREEN 2: load now returns semantic state plus an optional error. Metadata
  presence survives file failure, Saver round trips omit bytes, cancellation
  skips subsequent file work, and all 15 focused cases plus app compilation
  pass.
- `git diff --check`: passed.

## Automated release gate

- Full Android command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute (`709` tasks).
- Result XML: 296 JVM tests across 50 suites, 0 failures, 0 errors, 0 skipped.
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
`d5089f3d371aca30ca28533e909aa633c10522e78dd0d459ca98d0310d045aae`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` is unavailable, so thumbnail/full preview, removal, Activity recreation
and dark-mode contrast were not exercised on an emulator or Samsung device. No
live Edge Function/Gemini call, production cloud write, production migration,
RLS/RPC change or deployment occurred. The receipt debt/lend path and remaining
APK 1 closure checks are still pending; APK 1 and APK 2–4 remain incomplete.
