# APK 1 wallet push foundation evidence — 2026-09-22

## Scope and acceptance

This slice makes regular-wallet outbox entries safe to push while leaving the
wallet production gate disabled. It does not claim APK 1 completion or live
Supabase/device verification.

- `RemoteMutationStore` implements owner-scoped GET, array POST create, and
  optimistic PATCH filtered by `id`, `user_id`, and `sync_version`.
- Create writes `sync_version=1`; update writes the next version. The existing
  wallet serializer continues to preserve signed 64-bit minor units and
  explicit JSON nulls.
- Room reads only due wallet entries for the signed-in owner. ACK and failure
  updates compare the exact owner/entity/id/modified time/base version/device
  and attempt count captured before the request.
- A successful ACK removes the exact outbox entry and installs the server row
  in one transaction. If an edit coalesces while a request is in flight, the
  stale response changes neither the new outbox entry nor the local row.
- Transient transport/408/429/5xx failures get a bounded 30-second-to-6-hour
  exponential retry. Other 4xx responses are not retried automatically.

## iOS and Supabase review

Compared with `MistiaSyncCoordinator.processUpsertMutation` and
`SupabaseRemoteStore.fetchSingleRow/createRow/updateRow`:

- Android uses the same record/owner/version filters, POST array body,
  `Prefer: return=representation`, semantic equality ACK, version increment,
  and timestamp/version authority ordering.
- A local-winner resolution uses conditional PATCH against the just-read remote
  version rather than iOS's force-upsert. This preserves the same result when
  the row is unchanged and is safer if another writer wins between read/write.
- A POST `409` race refetches the winning row and enters conflict resolution.
- An unresolved conflict is retained locally with
  `conflict_same_clock_version_different_payload` and a disabled automatic
  retry. Unlike iOS, Android does not yet persist both payloads in a separate
  conflict table or expose a review screen; that is explicitly still pending.

The Supabase changelog and current Data API/RLS guidance were reviewed. This
slice adds no SQL, grants, policies, functions or schema migrations. Tests use
TLS MockWebServer only; no production endpoint was called.

## Review findings fixed

1. ACK initially risked deleting a coalesced edit if it matched only the
   record key. Exact compare-and-delete plus the surrounding Room transaction
   now prevents that loss.
2. A create race initially treated HTTP 409 as a permanent opaque failure.
   It now refetches and resolves the actual server winner.
3. The pre-existing sync worker classified every `SupabaseHttpException` as
   retryable because it subclasses `IOException`. The retry policy now checks
   PostgREST status first, so 401/409 stop while 408/429/5xx retry.

## Automated verification

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug`: passed; 65 unit tests, 0 failures, 0
  errors, 0 lint errors, and the Room Android test source compiled.
- Wallet network tests assert bearer auth, owner filters, array POST, explicit
  nulls, exact 64-bit values, conditional version filters, and disabled-gate
  rejection before any network request.
- Wallet coordinator tests cover create, update, semantic ACK, unresolved
  conflict retention, transient retry, create races and disabled-gate behavior.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities.
- Android and strict Swift localization generation checks: passed with no
  generated changes.
- `swift test --filter MistiaSyncOutboxTests`: passed 5/5. The full 597-test
  Swift suite already passed in the immediately preceding Swift fixture slice;
  no Swift source changed here.
- `git diff --check`: passed.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`753b251851207c4669ccb155490c21174089532205239f77b153fb2157aef70e`.

## Device and cloud gates

`adb devices -l` returned no connected device. No `adb install -r`, Room
instrumented execution, or wallet UI/cloud behavior was claimed for Samsung.

Both `BuildConfig.ALLOW_WALLET_CLOUD_WRITES` and the legacy global
`ALLOW_CLOUD_WRITES` remain `false`. Consequently login/startup/manual sync
continue to preserve pending wallet mutations and pull remote snapshots without
sending a wallet write. No production migration or deployment occurred.
