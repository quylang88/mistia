# APK 1 Android receipt bitmap and URI codec evidence — 2026-09-24

This bounded slice turns the platform-neutral receipt preparation policy into
an Android framework implementation suitable for the upcoming Photo Picker and
CameraX integration.

## Scope and safety boundary

- `AndroidReceiptImagePreparer` reads a `content://` or other resolver-backed
  URI on `Dispatchers.IO`, rejects empty input and stops after 24 MiB rather
  than calling an unbounded `readBytes()`.
- `AndroidReceiptImageCodec` reads bitmap bounds first and selects a power-of-two
  `inSampleSize` before allocation. The decoded longest side is targeted at or
  below 3,000 px, limiting peak pixel memory before the shared preparation
  policy runs.
- Framework `ExifInterface` orientation is applied for mirrored and 90/180/270°
  inputs. Every rendered frame is copied onto an opaque white ARGB canvas so
  transparent source pixels cannot become unreadable black JPEG regions.
- JPEG encoding delegates quality and size decisions to the already tested
  iOS-equivalent policy.
- The codec now exposes a non-throwing release hook. The generic preparer tracks
  distinct decoded/rendered frames by identity and recycles them in reverse
  order on success, typed failure or coroutine cancellation.

No picker/camera UI, runtime permission, transaction persistence, Edge Function
call, Supabase write, schema/deployment change or production state is included.

## TDD and review evidence

- Model RED: the resource-release test failed to compile before
  `ReceiptImageCodec.release` existed. GREEN proves source, analysis and
  thumbnail frames are released after success; the same `finally` owns failure
  and cancellation cleanup.
- URI RED verification: removing the bounded reader caused the focused feature
  target to fail compilation; restoring it returned the target GREEN. Tests
  cover exact-limit acceptance, over-limit rejection and empty input.
- Self-review identified decompressed bitmap size as a separate OOM boundary
  from compressed input bytes. The decode-sampling test failed before
  `calculateBitmapSampleSize` existed, then passed for no-sample, 2× and 8×
  cases after bounds-first decode was added.
- The Android bitmap implementation is framework-compiled and linted. Pixel/
  EXIF behavior still requires instrumentation with concrete fixture images in
  the Photo Picker/CameraX slice; it is not claimed from JVM tests.

## Automated release gate

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: final post-review run passed in 53s (`709`
  tasks).
- Result XML: 222 tests across 41 suites, 0 failures, 0 errors, 0 skipped.
- Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- `swift Scripts/check-android-contracts.swift`: passed with 15 entities.
- Android localization generation and strict iOS localization codegen checks
  passed. No String Catalog or generated localization source changed. The full
  audit's `xcstringstool` step remains unavailable under Command Line Tools and
  is not claimed.
- `git diff --check`: passed.

Final artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`693577daae285ae8016e9424a222a95bf4cb8524b9debfa3655c2e6b79a494a8`.
The APK contains 634 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

Per the user's direction, Samsung verification is deferred. This evidence does
not claim a URI was selected or a camera image captured on-device. The next
slice connects Photo Picker to this loader, followed by CameraX and the native
itemized review/apply flow. APK 1 and APK 2–4/RC remain incomplete.
