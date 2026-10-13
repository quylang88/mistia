# APK 2 gated recurring bill push

Independent ALLOW_RECURRING_BILL_CLOUD_WRITES=false, additionally require wallet
and category gates at coordinator and network allowlist. Priority70 after savings
before pull. Defer UPSERT when category or wallet outbox pending; DELETE bypasses.
Reuse conditional/tombstone engine. Compare typed Swift-equivalent semantic
fields with date instant normalization and missing optional/legacy pause defaults;
keep request/storage payload lossless. Validate complete bill wire rows before
ACK/conflict/write to match Swift typed decoding and protect corrupted local scope.

- [x] RED domain tests using full typed bill payloads: shared races/winners/ACK/
  retry/cancellation/tombstones/stale protection, both dependencies, legacy
  nullable defaults/ISO dates, corrupt local/remote data and genuine changes.
- [x] HTTPS MockWebServer contract/gate/scoping/null/Long/sparse delete tests.
- [x] Implement wrapper, defaults/validation hook, DI/gate/order and GREEN.
- [x] Full checks, focused Swift sync, direct local review, evidence/progress,
  APK checksum and commit; continue native bills/payment and due maintenance.

No production writes/deployments. Other domain defaults unchanged and false.
