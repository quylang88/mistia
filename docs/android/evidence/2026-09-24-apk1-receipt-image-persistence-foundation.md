# APK 1 local receipt-image persistence foundation evidence — 2026-09-24

This bounded slice establishes the local file/metadata persistence layer needed
to attach the analyzed bill only after a transaction saves successfully.

## Scope and behavior

- Added a platform-neutral `TransactionReceiptImageRepository` contract and
  metadata record with stable receipt/transaction/owner identity, file names,
  JPEG content type, byte count and timestamps.
- `LocalTransactionReceiptImageRepository` writes the prepared full JPEG and
  thumbnail into app-private `filesDir/ReceiptImages`, while Room stores only
  metadata. File names are transaction-scoped, unique and path-validated.
- Replacement writes both new files before replacing metadata. If metadata
  persistence fails, both new files are removed and the previous receipt stays
  readable. After success, superseded files are deleted.
- Single-receipt deletion and owner-scoped account cleanup remove full image,
  thumbnail and metadata without touching another owner's receipt.
- Room schema v3 adds `transaction_receipt_images`, an owner index and a unique
  transaction index. `MIGRATION_2_3` and its Android migration-test declaration
  compile against the exported v3 schema.
- Hilt exposes one singleton repository; no screen or transaction save path
  consumes it in this foundation slice.

## TDD and parity evidence

- RED 1: focused JVM tests failed at Kotlin compilation because the receipt
  record, repository and metadata store did not exist.
- GREEN 1: replace/failure/delete tests passed after the file repository and
  Room metadata adapter were added.
- RED 2: the owner-cleanup test failed at Kotlin compilation because
  `deleteAccount` and owner metadata queries did not exist.
- GREEN 2: all four focused tests passed, including another-owner preservation.
- Direct iOS comparison used `TransactionReceiptImageStore.swift` and
  `TransactionReceiptImage` in `ManagementModels.swift`; Android follows the
  same local file-plus-record boundary rather than adding image bytes to cloud
  transaction payloads.
- Mutation review: persisting metadata before both files, keeping superseded
  files, deleting another owner's files or accepting an unsafe file token/path
  violates focused assertions or repository validation.
- `git diff --check`: passed.

## Automated release gate

- Focused `LocalTransactionReceiptImageRepositoryTest`: passed, 4/4 after both
  recorded RED runs.
- Room Android-test Kotlin compilation passed, including the v2→v3 migration
  test source. It was not executed because no Android target/`adb` is available.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 52 seconds (`709` tasks).
- Result XML: 273 JVM tests across 48 suites, 0 failures, 0 errors, 0 skipped.
  Android lint and debug APK assembly also completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`a3d6f14cbc0c7eb8eec9214ec88c5e754f3c709d506af69dc88aad0abc375663`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` remains unavailable, so Room v2→v3 migration execution, app-private file
behavior and UI integration are not device-verified. No receipt is attached to
a transaction yet. No live Edge Function/Gemini call, production cloud write,
production migration or deployment occurred. Save-flow attachment,
preview/removal, debt/lend persistence and APK 1 closure remain outstanding;
APK 1 and APK 2–4 are incomplete.
