# APK 1 receipt review state evidence — 2026-09-24

This bounded slice adds the platform-neutral state contract that a native
Compose receipt-analysis screen can render and mutate. It sits between prepared
images/the analysis coordinator and later reviewed-transaction persistence.

## Scope and parity

- A review session owns up to five prepared bills, preserves acquisition order
  and stable caller-provided IDs, reports remaining capacity and treats any
  added bill as transient work for dismiss protection.
- Starting analysis selects only pending bills, leaves completed and
  multiple-bill-blocked entries alone, clears stale failures and marks the exact
  batch as analyzing.
- Ordered coordinator attempts are mapped back to their stable bill IDs.
  Successful responses are validated against currently available category and
  wallet IDs before becoming reviewable; invalid suggestions are cleared and
  surfaced through the result's missing-field contract.
- Multiple-receipt images become blocked entries without exposing their result
  as reviewable. Typed per-bill failures and quota metadata remain isolated from
  successful siblings.
- Literal OCR evidence stays in review state: the focused fixture retains the
  printed `3@ まろやかミルク 198` purchase row, quantity 3, the independent
  `クーポン -50` discount row and their original ordering/raw text.
- Retry clears result, selected wallet, quota, failure and multiple-bill state
  without replacing the prepared image. Removing one bill does not mutate its
  siblings.

## TDD and review evidence

- RED: the focused target failed to compile because `ReceiptReviewState`,
  `ReceiptReviewBill` and the analysis-batch API did not exist.
- GREEN: four focused JVM tests cover ordered five-image capping and dismiss
  state, pending-only batch creation, validated partial completion with literal
  OCR/discount preservation, and isolated retry/remove behavior.
- A parity-specific assertion was added after review: a pending image alone is
  transient unsaved work, matching the iOS dismiss guard. That assertion failed
  first, then passed after the state contract was corrected.
- Mutation review: accepting a sixth bill, analyzing completed/blocked bills,
  preserving invalid candidate IDs, collapsing the standalone discount,
  losing quantity notation, leaking one failure across siblings or retrying
  with a different image breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused command:
  `./gradlew :feature:transactions:testDebugUnitTest --tests
  'vn.com.quyln.mistia.feature.transactions.ReceiptReviewStateTest'
  --no-build-cache --no-daemon --max-workers=1 --console=plain`: passed, 4/4.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 51 seconds (`709` tasks).
- Result XML: 240 tests across 45 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No user-facing string was added. The full localization skill audit remains
  unavailable because full Xcode is blocked until its license is accepted and
  Command Line Tools does not contain `xcstringstool`; this is not claimed as a
  passing audit.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`d1dc8c176e9903462f5ba551003fd6f2248a6a3bc2b7b7d2ebbb1dbf54cfc842`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

The state is not yet routed to a Compose screen, and reviewed items are not yet
converted to or persisted as transactions. No live AI request, production
write, migration or deployment occurred. Samsung verification remains deferred
per the user's direction. UI orchestration is next; APK 1 and APK 2–4 remain
incomplete.
