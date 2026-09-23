# APK 1 category push foundation evidence — 2026-09-23

This slice follows the offline category hierarchy commit and adds a safe,
domain-gated cloud push foundation. It does not enable production writes or
claim APK 1 completion.

## Scope and acceptance

- Added `BuildConfig.ALLOW_CATEGORY_CLOUD_WRITES=false` separately from
  `ALLOW_WALLET_CLOUD_WRITES=false` and the legacy
  `ALLOW_CLOUD_WRITES=false`. The app's network allowlist is built from those
  domain flags; enabling category does not enable wallet and vice versa.
- PostgREST category GET is filtered by record `id` and `user_id`; create uses
  an array body and owner filter; conditional PATCH filters `id`, `user_id`
  and `sync_version`. The client rejects a disabled category write before
  opening a network request.
- Category payloads preserve explicit nulls including localized names and
  hierarchy/system/archive fields. `sync_version` remains Kotlin `Long`, with
  create at version 1 and updates incremented from the accepted base version.
- Category and wallet use a shared outbox push state machine. It implements
  semantic ACK, 409 create-race refetch, conditional-update race handling,
  local/remote authority resolution, unresolved conflict retention, bounded
  retry, cancellation propagation, and exact compare-and-ACK so an old
  response cannot remove or overwrite a newer coalesced edit.
- Category mutations are sorted parent before child, matching
  `MistiaSyncCoordinator.sortedMutationsForPush`. The sync engine sorts domain
  coordinators by contract `pushPriority`, so category runs before wallet even
  if dependency injection supplies them in the opposite order.

## iOS parity review

The implementation was compared directly with:

- `MistiaSyncCoordinator.processUpsertMutation`,
  `sortedMutationsForPush`, and `categoryChildRecordIDsForPushSorting`;
- `SupabaseRemoteStore.fetchRecord`, `create`, and `conditionalUpdate`;
- `RemoteTransactionCategory` coding keys and 64-bit sync version;
- `MistiaSyncOutbox` entity priorities and exact category-before-wallet order.

Android deliberately keeps its previously documented safer local-winner
conditional PATCH instead of an unconditional force-upsert. If that second
conditional write loses a race, the mutation is retained as
`conflict_force_update_race` for review rather than discarded.

Remote category-name translation is not part of this slice. iOS combines its
local fallback, remote Edge Function request, retry metadata and an
`updatedAt` stale-response guard. Android will implement and test that complete
flow as a separate slice; no Edge Function was called here.

## TDD and automated verification

- Red phase: focused sync tests failed to compile because
  `CategoryPushCoordinator`, the generic domain push contract and engine
  coordinator ordering did not exist. The network category tests already
  exercised the reusable PostgREST path.
- Green phase: 12 category coordinator tests cover create/update, semantic
  ACK, parent-before-child order, create race, conditional and force-update
  races, local/remote/unresolved winners, stale response protection, retry,
  cancellation and the disabled gate. Five network tests cover owner filters,
  explicit nulls, 64-bit versions, conditional filters, independent allowlists
  and disabled-gate rejection. The engine regression proves category-before-
  wallet-before-pull ordering.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug`: passed in 4m 1s; 107 unit tests across 21
  suites, 0 failures, Room Android-test sources compiled, 0 lint errors, and
  debug APK assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities.
- `swift Scripts/generate-android-l10n.swift --check`: passed.
- `swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings
  --output Mistia/Shared/CoreLogic/L10n.generated.swift --strict-keys
  --check`: passed.
- `swift test --filter
  'MistiaSyncOutboxTests|MistiaSystemCategoryRemoteApplyTests'`: passed 22/22.
- `git diff --check`: passed.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`66a5ff252bc5da54f7bf07cd9b00c7bb4f8d73312753a534462c7762227f4900`.
The APK contains 634 files; generated debug `BuildConfig` confirms all three
cloud-write flags are `false`.

## Device and cloud evidence

`/Users/quylang/Library/Android/sdk/platform-tools/adb devices -l` started the
local daemon and returned no connected device. No `adb install -r`, Room
instrumented execution, emulator verification or Samsung behavior is claimed.

No live Supabase write, production migration, RLS change, RPC, Edge Function
call, OAuth change or deployment occurred. With the category gate disabled,
the built APK leaves pending category mutations local and performs no category
write request.
