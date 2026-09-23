# APK 1 receipt transaction prefill evidence — 2026-09-24

This bounded slice bridges a validated receipt expense draft into the existing
native transaction editor without widening the currently supported persistence
contract.

## Scope and behavior

- A receipt expense draft maps its merchant title, exact minor-unit amount,
  occurrence time, source wallet and child expense category into a new posted
  `TransactionEditorState`.
- Currency-aware formatting reuses the editor's existing minor-unit formatter,
  so zero-decimal JPY remains `1570` and currencies with fraction digits retain
  their editor-compatible decimal representation.
- Destination wallet, transfer subtype, debt intent and FX state remain empty
  for the ordinary expense flow.
- Receipt lend/debt drafts are rejected at this boundary. The Android
  transaction repository does not yet persist debt-transfer semantics, so this
  slice does not expose a path that would certainly fail or silently lose data.
- `TransactionEditorSheet` now accepts an optional initial state while keeping
  the ordinary new/edit call sites source-compatible. A restored editor state
  still wins through `rememberSaveable`, and an existing transaction still wins
  over a supplied prefill.

## TDD and review evidence

- RED: the focused editor-state test failed to compile because
  `toExpenseEditorState` did not exist.
- GREEN: two added tests cover every supported expense prefill field and the
  explicit rejection of a lend/debt draft.
- Mutation review: changing the kind/subtype/debt guards, dropping wallet or
  category, or formatting the amount as raw decimal minor units breaks a focused
  assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused `TransactionEditorStateTest`: passed.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 54 seconds (`709` tasks).
- Result XML: 255 tests across 46 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`aa8450a1078a65db78102932b3fc74e041f808b46759c4237c6be2376e9c8960`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

The receipt review screen does not yet render selection controls or route this
prefill into the transaction editor. Receipt image persistence, lend/debt
persistence, live AI/production calls and device verification did not occur.
Compose selection binding and routing are next; APK 1 and APK 2–4 remain
incomplete.
