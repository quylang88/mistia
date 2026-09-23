# APK 1 receipt review arithmetic evidence — 2026-09-24

This bounded slice ports the iOS item-correction and standalone-discount
allocation rules into the shared Android receipt model. It is pure domain logic;
the Compose editors and persistence binding remain later work.

## Scope and parity

- Reviewing a purchase requires a nonblank printed name, positive quantity,
  positive original amount and a nonnegative discount no larger than the
  original. It stores quantity only above one and recomputes the final amount as
  `original - discount` in exact minor units.
- Reviewing a discount clears quantity, original amount and category, preserves
  the row as a standalone discount and stores its final amount as negative.
- Successful review clears only the item-level OCR/arithmetic missing fields;
  unrelated missing fields such as category remain visible for separate review.
- Proportional discount allocation targets positive purchase rows only, rejects
  invalid/oversized discounts, uses exact integer quotient/remainder arithmetic
  and assigns leftover minor units by largest remainder with original row order
  as the deterministic tie-break.
- Allocation accumulates existing purchase discounts, reconstructs a missing
  original amount when needed and zeroes (rather than deletes or merges) the
  standalone discount row, preserving its identity and printed OCR evidence.

## TDD and review evidence

- RED: the focused core-model test failed to compile because `reviewed` and
  `allocateReceiptDiscount` did not exist.
- GREEN: three added tests cover purchase correction/missing-field cleanup,
  standalone-discount correction/invalid purchase rejection and proportional
  allocation with deterministic remainder and total preservation.
- Direct Swift parity review used `BillItemAnalysisItem.reviewed` and
  `BillItemDiscountAllocator.allocatingDiscount` in
  `Mistia/Shared/CoreLogic/BillItemAnalysisModels.swift`.
- Mutation review: accepting discount greater than original, leaving category on
  a discount, making its final amount positive, truncating the leftover unit,
  deleting the discount row or changing the post-allocation total breaks a
  focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptAnalysisTest`: passed, including 3 new review tests.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 56 seconds (`709` tasks).
- Result XML: 250 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`7b9804451f7719fcb6880b9c36bd8320e68ed0656c61487fae278b605490cb3b`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

No UI editor used these operations, no receipt/transaction was persisted and no
live AI/production call, migration, deployment or device verification occurred.
Binding review edits and selection to persistence remains next; APK 1 and APK
2–4 remain incomplete.
