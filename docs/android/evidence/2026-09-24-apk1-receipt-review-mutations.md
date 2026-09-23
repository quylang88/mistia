# APK 1 receipt review mutation evidence — 2026-09-24

This bounded slice connects typed review arithmetic to immutable per-bill review
session transitions. It gives the upcoming Compose editors one tested state API
instead of embedding mutation rules in UI callbacks.

## Scope and behavior

- A bill can update its selected wallet and payable total independently.
- Category changes target one item ID, item review replaces one matching row,
  proportional discount allocation delegates to the shared exact arithmetic,
  and removal deletes only the requested row.
- Every operation is scoped by stable bill ID. Unknown bills or bills without an
  analysis result are unchanged, and sibling bill objects remain untouched.
- Result-level metadata and evidence not being edited remain intact, including
  raw receipt OCR and each item's literal printed row text.
- Applying the concrete Japanese fixture retains `3@ ミルク 198`, assigns the
  chosen category, distributes the `クーポン -41` discount to the purchase,
  updates 594 to 553, zeroes the discount row and then removes only that row
  when explicitly requested.

## TDD and review evidence

- RED: the focused target failed to compile because the wallet, total, category,
  item, allocation and removal transitions did not exist.
- GREEN: one end-to-end immutable-state test covers the full edit chain and
  asserts sibling identity plus literal OCR/result metadata preservation.
- Direct parity review used the corresponding bindings and
  `updateItemCategory`, `updateItem`, `allocateDiscount` and `removeItem`
  operations in the iOS `AIBillAnalysisView`.
- Mutation review: replacing all rows, mutating a sibling, erasing raw OCR,
  losing the category, merging/deleting the discount implicitly or removing
  the wrong item breaks the focused test.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptReviewStateTest`: passed, 6/6.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 52 seconds (`709` tasks).
- Result XML: 251 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`d63d0e799bb467db53f50f072e17023a86e84fb824373c0ce6d93eda08e9b556`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

The transitions are not yet exposed through Compose editors or connected to
transaction persistence. No live AI/production call, migration, deployment or
device verification occurred. UI binding remains next; APK 1 and APK 2–4 remain
incomplete.
