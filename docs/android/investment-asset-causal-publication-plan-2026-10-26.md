# Investment asset causal publication implementation plan

> Execute inline, following the user's existing autonomous slice/TDD/commit instruction. The plan records the regression-driven implementation; no new product decision is required.

**Goal:** Preserve a newer asset name/photo across an older RPC result, including server clock skew and lost replies.

**Architecture:** Local bounded parent fingerprints accompany the exact row/outbox generation. A closed asset conflict hook and typed atomic Room receipt preserve causal order without changing other-device/shared conflict policy.

**Tech stack:** Kotlin, kotlinx serialization/coroutines, Room6, existing asset RPC, MockWebServer TLS and API36 native instrumentation.

**Spec:** `investment-asset-causal-publication-design-2026-10-26.md`.

## Constraints and review focus

- Preserve exact Long/null/opaque payloads, owner/session/captured-caller fences and existing photo authority.
- All11cloud flags false; no production write/deploy/migration/push or repeat OAuth/account-switch setup.
- Verify new edits during actual RPC, lost reply, conditional compared-base gaps, bounded/malformed evidence and every queue retry stamp.
- A confirmed receipt must not become a generic ACK or consume financial queues; rollback after the first write is required.
- Distinguish emulator/local HTTPS evidence from live Supabase/Samsung; no whole APK1–4 completion claim.

## Task1: Producer evidence and closed coordinator

- [x] Add real Room/HTTPS regression tests for rename, lost reply and photo with local00:15/server00:30; observe3 runtime failures.
- [x] Add model producer/wire-strip tests; observe2 runtime failures.
- [x] Implement `InvestmentAssetPublicationParents.kt`; hook `investmentAssetChanged`; strip/refuse both private keys at network/Room ingress.
- [x] Add optional default-null `OutboxPushCoordinator.conflictDecisionOverride`; asset-only proven-parent decision and explicit unproven-own conflict.
- [x] Run model/network/sync plus integration; original3 GREEN. Preserve true other-device conflict fixtures.

## Task2: Definite higher-base receipt

- [x] Add real conditional7→8/newer rename regression; observe1 failure among11 integration tests.
- [x] Add `LocalStore.recordInvestmentAssetPublicationReceipt(q,sent,expected,remote)` with default no-op; Room atomically updates only private evidence in coherent current row+queue.
- [x] Invoke only after actual successful create/update, with session fences; real11integration GREEN.
- [x] Add strict/bounded/no-op/opaque/hash/instant model tests and dedicated/generic HTTPS ingress coverage.
- [x] Complete focused Room receipt tests: queue stamps, forged payload/version, owner replacement, late insert failure and final caller cancellation rollback.

## Task3: Acceptance and continuation

- [x] Scoped independent static review found no actionable introduced P1/P2; no whole-branch claim.
- [x] Full Android2312JVM/216zero, lint/build/native packages, Swift627zero and11script checks0; full logs/counts inspected and git diff --check passes.
- [x] Full Room and full Investment native suites on the actual built APKs, sequentially; inspect results without treating adb exit alone as success.
- [x] Archive/inspect/checksum/install-r matching APKs and source patch; update evidence/progress/handoff.
- [ ] Commit this slice independently; restore hashed canonical-root WIP and continue the full goal.
