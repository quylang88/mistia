# APK 2 separately gated savings goal push

Match Swift savingsGoal generic upsert/delete fingerprint and schema priority60,
linked_wallet_id dependency. Reuse proven OutboxPushCoordinator with tombstone
support; defer pending wallet dependencies for UPSERT, allow DELETE to proceed.
Add independent ALLOW_SAVINGS_GOAL_CLOUD_WRITES=false at coordinator and network
allowlist, also require wallet gate. Global ALLOW_CLOUD_WRITES remains false.

- [x] RED domain coordinator tests using complete typed goal payloads: create,
  conditional version, semantic ACK, races/winners/conflicts/retry/cancellation,
  stale replacement, exact Long, tombstones, foreign identity and dependencies.
- [x] HTTPS mock tests for owner/id/version filters, explicit null/Long, sparse
  deletion, independent default-disabled allowlist and foreign response.
- [x] Implement wrapper/gates/order and GREEN.
- [x] Full checks, focused Swift outbox/conflict tests, direct local review,
  evidence/progress, APK checksum/commit; continue native savings UI.

No production writes or deployments; emulator/Samsung checks only if available.
