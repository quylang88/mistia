# APK 1 receipt image preparation evidence — 2026-09-24

This slice ports the deterministic image-budget algorithm used by Mistia's iOS
itemized bill flow. It is the tested policy layer for the upcoming Android URI,
Photo Picker and CameraX integration.

## Scope and behavior

- A generic `ReceiptImageCodec<Frame>` boundary owns platform decode,
  orientation-normalized frames, opaque scaling and JPEG encoding.
- `ReceiptImagePreparer` first limits the analysis frame to a 3,000 px longest
  side, then tries JPEG qualities 0.90, 0.82, 0.74, 0.66, 0.58, 0.50 and 0.42.
- If the 3,800,000-byte budget is still exceeded, it scales the normalized frame
  by 0.86 and retries without crossing the 900 px OCR floor.
- An image already below 900 px is still encoded and accepted if it fits; the
  floor applies only to further downscaling.
- The accepted analysis frame is returned as `image/jpeg` with its dimensions,
  plus a 240 px thumbnail encoded at quality 0.68.
- Decode, invalid-dimension, scaling, encoding and irreducibly-large failures
  are distinct. Coroutine cancellation is checked before decode and throughout
  quality/dimension loops.

This slice intentionally contains no Android `Bitmap`, URI access, EXIF code,
picker/camera UI, persistence, Edge Function call or production state change.
The concrete codec must normalize orientation and render transparency onto an
opaque white background before this policy can be used in the UI.

## TDD and review evidence

- Initial focused tests failed to compile before the codec/preparer contract
  existed.
- GREEN tests cover initial normalization, exact byte-boundary acceptance,
  quality descent before resizing, dimension fallback, thumbnail policy,
  irreducibly-large images, all typed local failures and cancellation.
- Self-review found that a readable source smaller than 900 px was incorrectly
  rejected before its first encode. A regression test failed, then passed after
  separating “encode current frame” from “may resize again.”

## Automated release gate

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed in 1m 59s (`709` tasks).
- Result XML: 217 tests across 40 suites, 0 failures, 0 errors, 0 skipped.
- Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- `swift Scripts/check-android-contracts.swift`: passed with 15 entities.
- Android localization generation check and strict iOS localization codegen
  check passed. No String Catalog or generated localization file changed. The
  broader audit's `xcstringstool` subcheck remains unavailable under Command
  Line Tools until the full Xcode toolchain/license is usable; it is not claimed.
- `git diff --check`: passed.

Final artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`6ddafc30d116850e2db6818dad182c0e6f99c69968d839a7f4aca0d7055294dc`.
The APK contains 634 files. This model-only slice does not alter any cloud-write
gate; the generated debug gates remain disabled as recorded in the immediately
preceding receipt-client evidence.

## Remaining boundary

No Samsung check is claimed, per the user's current direction. The next slice
must implement the Android framework codec and bounded URI reads, followed by
Photo Picker/CameraX and the native analysis review/apply flow. APK 1 and later
APK 2–4/RC gates remain incomplete.
