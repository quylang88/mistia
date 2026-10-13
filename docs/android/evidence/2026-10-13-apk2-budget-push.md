# APK 2 budget push foundation — 2026-10-13

## Implementation and iOS parity
- Independent ALLOW_BUDGET_CLOUD_WRITES=false; both coordinator and PostgREST
  budget allowlist also require the category gate. Global and every other
  financial cloud-write flag remain false.
- Budget priority 50 follows category/wallet/card/transaction before pull.
  Pending selected-category outbox entries defer UPSERT without changing its
  retry state. Deletion requires no uploaded category dependency.
- Existing upserts reuse semantic ACK, create-race refetch, conditional version
  updates, deterministic winners, durable conflicts, retry and cancellation.
- Budget DELETE opts into Swift-equivalent tombstones. Missing remote ACKs
  locally without POST; deleted remote ACKs its authoritative representation.
  Live remote uses owner/id/version-filtered sparse PATCH; failed conditional
  PATCH refetches before winner resolution or synthesized missing-row ACK.
  A force-delete race keeps the conflict and its local tombstone durably.
- Sparse deletion only changes deletion/update timestamps, version/device and
  immutable request identity, preserving server semantic fields like iOS
  SupabaseRemoteStore.conditionalDelete.
- Remote identity is validated before ACK/conflict; version increments reject
  Long overflow before writing. Semantic UPSERT ACK now requires matching
  deletion state, avoiding loss of a later live edit to an older tombstone.
- Exact existing Room compare-and-ACK/failure protection preserves a newer
  mutation after an older response, including deletion responses.

Swift references: MistiaSyncCoordinator.swift processDeleteMutation;
SupabaseRemoteStore.swift conditionalDelete; MistiaSyncModels.swift budget
payloadFingerprint including deletedAt; shared schema pushPriority/dependencies.
No iOS runtime or server schema changed.

## TDD and review
Initial RED: missing budget coordinator. The minimal wrapper then exposed eight
runtime failures for unsupported DELETE states and version overflow. A foreign
response regression also failed before identity validation. Dependency deferral
was observed failing before the barrier. Independent review identified the live
edit/older tombstone semantic ACK bug; its regression failed, then passed after
the deletion-state guard. Final independent narrow review found no further
issue. All previously existing domain coordinator suites pass.

## Validation
- Full `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --console=plain --max-workers=1`: passed,
  709 tasks, 45s, JDK17.
- 363 JVM tests across 54 suites, zero failures: 22 budget push and nine budget
  HTTPS MockWebServer tests, including owner/version filters, explicit nullable
  snapshots, signed Long wire values, sparse tombstones and default-disabled
  writes. Sync engine dependency order test includes budget before pull.
- Focused Swift MistiaSyncOutboxTests and MistiaSyncTransactionConflictTests:
  14/14 passed with full Xcode DEVELOPER_DIR.
- 15-entity contract, Android localization, strict Swift localization and
  `git diff --check` pass. No localization source changed in this slice.
- Generated BuildConfig: versionCode 5; global/budget/category/wallet/card/
  transaction flags all false.

Artifact: `android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-budget-push-v5.apk`.
SHA-256: `6058c9c466073228cb02d5fcf3c6426d61e3b71fc7165d0adb5826a8374e83bc`.

## Emulator evidence and boundary
The earlier budget offline instrumentation install initially failed as the
emulator disconnected. It returned as emulator-5582, sdk_gphone64_arm64/API36.
`adb install --no-streaming -r` of database-debug-androidTest.apk succeeded.
Direct AndroidJUnitRunner execution of BudgetRoomTest returned `OK (2 tests)`:
second child + automatic parent persistence/repository recreation/account scope,
and rollback of the first record/outbox when the second mutation is invalid.
This is runtime Room verification on an emulator, not Samsung or UI evidence.
No target app uninstall occurred. No Samsung was connected, no live Supabase
budget write/request, migration, RPC/Edge Function change or deployment occurred.

Budget projection/editor and the other APK 2–4 domains remain pending. Gates
have not been promoted based on this local/mocked/emulator evidence.
