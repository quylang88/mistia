# Android budget push implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline. TXT authorizes continued local implementation and per-slice commits.

**Goal:** Sync persisted budget create/edit/archive/delete mutations through a separately disabled write gate.

**Architecture:** BudgetPushCoordinator delegates upserts to the shared outbox engine. Opt-in tombstone deletes follow Swift processDeleteMutation, including missing/deleted remote ACK and conditional-delete races. Reuse owner-filtered PostgREST conditional PATCH with sparse delete payloads.

**Tech Stack:** Kotlin, Room outbox, coroutines, OkHttp, MockWebServer, JUnit.

**Spec:** contracts/schema/cloud-entities.json; MistiaSyncCoordinator.swift processDeleteMutation; SupabaseRemoteStore.swift conditionalDelete; budget offline plan/evidence.

## Global constraints
- ALLOW_CLOUD_WRITES=false; add ALLOW_BUDGET_CLOUD_WRITES=false; coordinator and transport budget writes additionally require category gate.
- No production write or deployment. Signed Long versions/minor units and explicit JSON nulls.
- Preserve compare-and-ACK protections and propagate cancellation.
- Budget follows category/wallet/card/transaction coordinators by published priority 50.

## Review focus
- Missing remote for deleted local budget ACKs locally without creating a server tombstone.
- Already deleted remote ACKs without an unnecessary PATCH.
- Same-semantic live remote must not ACK away a local tombstone.
- Conditional-delete races refetch before resolving; local/remote winners and unresolved conflicts retain exact stale-response checks.
- Newer local edit while response is pending must survive ACK/failure; version overflow must fail before any write.

## Slice 2: budget push
Files: core/sync/BudgetPushCoordinator.kt, DomainPushCoordinator.kt, budget coordinator tests, budget PostgREST tests, push ordering tests, app/AppModule.kt and app/build.gradle.kts.
Interfaces: BudgetPushCoordinator(LocalStore, RemoteMutationStore, writesEnabled, nowEpochMillis) implements DomainPushCoordinator; shared engine allowTombstoneDeletes defaults false for other domains.
- [x] Write coordinator tests for normal create/update/semantic ACK/retry/races/cancellation and disabled/account gates.
- [x] Write tombstone tests for missing/deleted remote, matching version delete, conditional/force races, winners and stale ACK.
- [x] Run focused tests, confirm RED for missing coordinator/interface.
- [x] Implement wrapper, opt-in delete state machine and sparse PATCH payload with exact version increment.
- [x] Add MockWebServer owner/id/version/explicit-null/Long/default-disabled tests and ordering coverage; run GREEN.
- [x] Add independent review, fix findings with RED/GREEN regressions.
- [x] Run full Android checks, Swift outbox/conflict references, contract/localization checks and diff check; check ADB.
- [x] Update evidence/progress, archive APK checksum, commit slice and continue budget UI.
