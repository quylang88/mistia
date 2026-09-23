# APK 1 receipt selection projection evidence — 2026-09-24

This bounded slice projects analyzed review state into the iOS-parity selection
contract and adds deterministic whole-line toggle behavior for the upcoming
Compose controls.

## Scope and behavior

- Review bills and item rows are projected in their original order with stable
  compound bill/item IDs, selected wallet, category, merchant and occurred date.
- Purchase quantity defaults to one and preserves the AI quantity when present.
  A partial selection derives its amount through the exact minor-unit allocation
  rule; the fixture selects two of three units from 101 minor units as 68.
- Discounts remain one signed negative candidate with no category. Unselected
  rows represent their full currently available amount, matching the iOS
  snapshot contract.
- Toggling selects the full available row quantity, toggles an existing row off,
  rejects candidates from another bill and delegates wallet/category/discount
  compatibility to the shared selection rules.
- Normalization remains stable in displayed candidate order, so a rejected
  toggle never silently drops an already valid selection.

## TDD and review evidence

- RED: the focused target failed to compile because review projection and
  `toggleSelection` did not exist.
- GREEN: two added tests cover ordered quantity/amount projection and toggle
  semantics for same-bill discount, cross-bill rejection, category mismatch and
  deselection.
- Direct Swift parity review used `BillItemSelectionSnapshot`,
  `selectableIDs(mode:)`, `allocationAmount` and the selection callbacks in
  `AIBillAnalysisView`.
- Mutation review: flattening bill identity, rounding 101/3 down, allowing a
  second bill, allowing another expense category, rejecting a compatible
  discount or dropping the anchor selection breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `ReceiptItemSelectionTest`: passed, 8/8.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 57 seconds (`709` tasks).
- Result XML: 253 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`2c5cf7148d26d111b88672acfdcc2257576a7754e987a9d41d2f522b7d859d8b`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

The projection is not yet rendered as selection controls and no prefill was
opened or persisted. No live AI/production call, migration, deployment or
device verification occurred. Compose binding is next; APK 1 and APK 2–4 remain
incomplete.
