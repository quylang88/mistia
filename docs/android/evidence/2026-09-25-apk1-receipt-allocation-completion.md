# APK 1 receipt allocation completion evidence — 2026-09-25

This bounded slice ports iOS receipt allocation groups and successful-save-only
completion into the native Android receipt review. It does not claim APK 1
closure before the remaining checklist audit.

## Scope and parity

- Purchase rows with quantity greater than one now expose `x1...xN` selection.
  The selection contract clamps to currently available quantity and preserves
  the existing one-bill, wallet and Expense-category compatibility rules.
- Confirming a valid positive selection creates a locked group containing the
  exact per-item quantity/minor-unit allocations and the active Expense or Lend
  mode. The current selection clears only after the group is accepted.
- Candidate projection subtracts both created and locked allocations. Exact
  remainder distribution follows the iOS integer allocation rule; for example,
  a JPY 101 row with quantity three allocates 68 for two units and leaves 33.
- Locked groups render their localized amount/mode with Cancel and Add actions.
  Cancel removes only that group and restores its availability without marking
  any item created.
- Add opens the existing receipt-backed transaction editor while retaining the
  receipt review session below it. Dismissing or failing the editor leaves the
  group locked. Only a successful receipt plus transaction save sends a
  completion token back to review, merges that group's allocations into
  `createdAllocations`, removes the group and recomputes what remains.
- Fully locked or created rows expose localized state and cannot be selected or
  edited. Total, retry, item removal and discount reallocation are guarded once
  immutable allocation state exists; the existing iOS behavior for wallet and
  remaining-item category changes is retained.

Direct parity review used iOS `BillItemSelectionSnapshot`,
`confirmSelectionGroup`, `lockedGroupRow`, `createTransaction` and
`markPendingItemsCreated`. Independent review reported no Critical, Important
or Minor finding and confirmed successful-save-only completion and exact
remainder behavior.

## TDD trail

- RED 1: focused tests failed to compile because receipt bills had no locked or
  created allocations and no lock/cancel/complete/group-launch transitions.
- GREEN 1: focused tests cover exact created-plus-locked subtraction, group
  launch, cancellation restoration and completion of only the saved group.
- RED 2: the partial-quantity test failed to compile because the selection
  contract exposed only whole-line toggling.
- GREEN 2: quantity selection now clamps to availability, rejects cross-bill or
  otherwise incompatible additions, and drives the native quantity menu.
- The complete transactions feature suite passed after Compose integration.
- `git diff --check`: passed.

## Automated release gate

- Full Android command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 1 second (`709` tasks: 29 executed, 680
  up-to-date).
- Result XML: 311 JVM tests across 50 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test source compilation, Android lint and debug APK assembly
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. Dynamic `xN` notation matches the iOS
  verbatim quantity badge. The known full localization-audit limitation
  remains: the Xcode license is not accepted and Command Line Tools do not
  provide `xcstringstool`; the full audit is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`597dcd90901017b82c218981188250622f4eea6a2300f70cbd07a10a3e73ddf6`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` is unavailable, so the stacked receipt/editor sheets, quantity menu,
cancel/retry interaction, created/locked states and dark-mode contrast were not
exercised on an emulator or Samsung device. No live Gemini/Edge Function
request, Supabase write, migration or deployment occurred. The next bounded
step is an explicit APK 1 parity/checklist audit before starting APK 2.
