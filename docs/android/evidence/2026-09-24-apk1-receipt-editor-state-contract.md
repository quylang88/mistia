# APK 1 receipt editor state-contract evidence — 2026-09-24

This document records the bounded state-contract slice at its commit. That
slice established the state and persistence ordering required by native
saved-receipt preview/removal but did not yet bind those controls into Compose.

## Scope and behavior

- `TransactionReceiptEditorState` distinguishes a new analyzed image from an
  already stored receipt while exposing one full/thumbnail preview payload.
- A pending new receipt remains required until explicitly removed. If Activity
  recreation drops its deliberately non-saveable large image bytes, save
  remains invalid rather than silently creating a receipt-less transaction.
- Removing a pending image clears only the new-image requirement. Removing a
  stored image clears its preview and schedules deletion on save; repeating
  remove cannot accidentally clear that scheduled deletion.
- `saveTransactionThenDeleteReceipt` saves the edited transaction first. It
  leaves the stored receipt untouched on transaction failure and returns a
  later deletion failure so the user can retry. Cancellation remains
  propagated rather than converted into an ordinary failed result.
- The state takes ownership of source bytes. Preview access and each save
  resolution return defensive copies, preventing preview decoding/mutation
  from changing the exact bytes persisted later. Preview equality and hashes
  compare byte content rather than `ByteArray` identity.
- Direct iOS comparison used `receiptDraft`, `shouldDeleteReceiptOnSave`,
  `removeReceiptDraft` and `persistReceiptDraftIfNeeded` in
  `TransactionEditorSheet.swift`; the Android contract preserves deferred
  stored-receipt removal without placing image bytes in transaction payloads.

## TDD evidence

- RED 1: six focused tests failed at Kotlin compilation because the typed
  editor state and transaction-then-delete coordinator did not exist.
- GREEN 1: pending/stored/remove/recreation and save-order/failure cases passed.
- RED 2: the repeated-remove assertion failed because a second remove cleared
  `deleteStoredOnSave`.
- GREEN 2: deletion intent now accumulates idempotently and all six focused
  tests pass.
- RED 3: mutation-isolation tests changed source, preview and returned-save
  arrays and observed the shared bytes; content-equal previews also compared
  unequal under Kotlin's default `ByteArray` identity semantics.
- GREEN 3: owned defensive copies plus content equality/hash passed, together
  with explicit transaction/deletion cancellation coverage; the focused suite
  now has ten tests.
- Mutation review: treating a stored preview as a new upload, deleting before
  transaction save, deleting after transaction failure, swallowing delete
  errors or clearing deletion intent on repeated remove violates assertions.
- `git diff --check`: passed.

## Automated release gate

- Full command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 55 seconds (`709` tasks).
- Result XML: 291 JVM tests across 50 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test source compilation, Android lint and debug APK assembly
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains and is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`3157ec9b5c2a5f15f501c18b8946048bc32a1cc8fffb940ee32c1964fa0275f0`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

At this slice boundary, `adb` was unavailable, so no editor preview/removal or
file deletion was exercised on an emulator or Samsung device. Compose binding,
saved-receipt loading, image decoding and full-size preview were intentionally
left to the subsequent slice. No live Edge Function/Gemini call, production
cloud write, production migration or deployment occurred; APK 1 and APK 2–4
were incomplete.
