# Android APK 1 Wallet Push Slice Implementation Plan

**Goal:** Make queued regular-wallet mutations safely pushable through a wallet-only feature gate, with iOS-equivalent optimistic concurrency, owner scoping, retry metadata, and no production writes enabled.

**Architecture:** Add a narrow `RemoteMutationStore` contract beside the pull store. Room exposes due outbox rows and compare-and-ack/fail operations so an in-flight response cannot erase a newer local edit. A wallet push coordinator handles only `ledger_wallets`; the existing sync engine invokes it before pull when the wallet gate is enabled. The app build keeps that gate disabled until physical-device verification.

**References:** `Mistia/Shared/Sync/MistiaSyncCoordinator.swift`, `Mistia/Shared/Sync/SupabaseRemoteStore.swift`, `contracts/schema/cloud-entities.json`, Supabase Data API/RLS documentation, and `docs/android/SESSION-HANDOFF-2026-09-22.md`.

## Acceptance criteria

- GET/POST/PATCH requests include bearer auth and explicit `user_id` ownership filters; PATCH also includes the expected `sync_version` filter.
- Wallet JSON keeps exact signed 64-bit minor units and explicit nulls. Create sends `sync_version=1`; update sends `base_version+1`.
- Only due `ledger_wallets` mutations for the signed-in owner are processed, oldest first. Other domains stay untouched.
- Successful ACK atomically replaces the local row with the server representation and removes only the exact mutation sent. A concurrent newer edit remains pending and is never overwritten.
- Transient failures retain the row and persist bounded exponential retry metadata. Version/create conflicts retain the local mutation for later conflict UI rather than overwriting either side.
- `ALLOW_WALLET_CLOUD_WRITES` remains `false` in this build. No production request, migration, RPC, or deployment is performed.

## Tasks

### 1. PostgREST wallet mutation contract

- [x] Add failing MockWebServer tests for owner-scoped fetch, array create, version-guarded update, explicit nulls, and disabled-domain rejection.
- [x] Add `RemoteMutationStore` and implement the three operations in `SupabasePostgrestRemoteStore`.
- [x] Run the focused network suite and review requests against iOS.

### 2. Race-safe Room outbox lifecycle

- [x] Add failing instrumented DAO tests for due ordering, exact ACK, concurrent-edit preservation, and retry metadata.
- [x] Add queued-mutation model plus `LocalStore` due/ack/fail methods and transactional Room implementation.
- [x] Compile/run the relevant database tests available on this host.

### 3. Wallet push coordinator and sync wiring

- [x] Add failing coordinator tests for create, conditional update, semantic ACK, conflict retention, retry backoff, owner/domain isolation, and disabled gate.
- [x] Implement coordinator, `syncNow()`, worker/manual-start wiring, Hilt bindings, and wallet-only build flag.
- [x] Run Android unit/lint/build/contract/localization checks; run device tests/install only if ADB is connected.

### 4. Review, evidence, commit

- [x] Review the complete diff and behavior against iOS; fix findings and rerun affected checks.
- [x] Update parity progress and add a slice evidence record including the disabled production gate and device status.
- [x] Run `git diff --check`, commit this slice separately, and only then start the next APK 1 slice.
