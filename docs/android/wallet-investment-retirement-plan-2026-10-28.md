# Wallet Investment Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish pending confirmed investment cash before the old holder's final archive, preserving the offline archive and exact queues across automatic sync.
**Architecture:** Source-proven active ordinary wallet prerequisites retain final archived metadata intent; existing closed financial publishers consume only validated prerequisite proofs, then ordinary wallet publication finishes retirement. Runtime characterization precedes product implementation.
**Tech Stack:** Existing Kotlin/Compose/Room/OkHttp HTTPS; JDK17/API36 emulator, Swift parity references and local SQL where needed.
**Spec:** `docs/android/wallet-investment-retirement-design-2026-10-28.md`, original attached APK1–4 TXT and accepted161 evidence.

## Global Constraints

- Baseline175adf5d8b1c2d20085a3878050bd6f3f921cc16, same codex branch; preserve all accepted artifacts.
- All11writeflagsfalse; no production write/deploy/push and no repeated routine approval.
- Real local mutation/outbox and typed exact-generation Room changes are atomic; preserve newer owner/session/caller intents.
- Ordinary wallet preparation cannot enable financial writes or resurrect an actual remote archive/tombstone.
- Do not overlap Docker, Gradle/Swift and emulator work on this16GiB machine.
- Independent commit follows the complete functional slice and its required checks; task tests alone are not acceptance.

## Review Focus

- Archive immediately after an offline move: actual three automatic cycles must publish real ledger/pair before archive and clear only matching queues.
- Absent remote wallet/lost preparation reply: prove an own insert without consuming the archive or recreating a retired identity.
- Investment gate disabled with pending cash: defer retirement, no financial request through wallet gate.
- Newer wallet/root/financial intent during response: preserve the entire newer generation and final archive.
- Unrecognized reservation, stale currency or different-device winner: hold safely, no partial ACK or force overwrite.

### Task 1: Reproduce the pending financial wallet archive lifecycle

**Files:** Modify `android/feature/investment/src/androidTest/java/vn/com/quyln/mistia/feature/investment/InvestmentLinkedWalletMovePublicationIntegrationTest.kt` and add fixtures only as needed.
**Interfaces:** Consume existing `OfflineFirstInvestmentRepository.changeLinkedWallet`, `OfflineFirstFinanceRepository.archiveWallet`, `WalletPublicationPushCoordinator.pushPending`, `InvestmentPublicationPushCoordinator.pushPending` and actual Room/HTTPS clients. Produce a real failing lifecycle regression and the precise source/queue/request order that Task2 must repair.

- [x] Add `offlineMoveThenArchivePublishesFinancialPairBeforeFinalWalletArchiveAcrossAutomaticCycles`: old holder has50booked, confirm move50, archive old holder at00:06; after three wallet→investment cycles assert no queues, local+remoteoldwallet archived, one realledger and exact−50/+50pair, pair request precedes archive request. Keep initial local archive asserted before sync. Fixture rejects an archive while its cloud holder retains50, matching verified SQL behavior.
- [x] Compile test APK, stop Gradle, boot emulator and run this exact test. Expected runtime FAIL because current wallet-first archive cannot complete and closed financial readiness defers. A compile/fixture failure is not RED; correct it first.
- [x] Record actual RED/source observations in the plan ledger; preserve the test and avoid changing product code until the failure is understood.

### Task 2: Implement source-proven active prerequisites and final retirement

**Files:** New focused wallet-retirement model/coordinator files alongside existing core/model and core/sync; typed LocalStore/Room prepare/rebase methods; existing ordinary wallet/composite/closed financial readiness and app DI as required. Follow established metadata staging patterns without widening generic financial writes.
**Interfaces:** Consume Task1's exact lifecycle and complete owned financial source snapshots. Produce a typed prerequisite proof/journal with exact wallet source, queue, compared remote version and own active-business fingerprint; typed Room prepare/rebase retains the archived row and queue while updating only proven remote base metadata. Readiness must consume this proof rather than an unconditional archived-wallet exception.

- [x] Add model/Room/network/coordinator failures for the five Review Focus cases, existing active remote and never-published wallet, cancellation/lost response/backoff, >100 unrelated queues, complete reservation retirement and known trade/cash/reconciliation dependencies. Observe RED before each behavior change.
- [x] Implement the smallest typed mechanism supported by those failures; existing active remote authority needs no active rewrite. No resurrection, force, final-intent loss or cross-domain gate bypass.
- [x] Run focused suites and the real Task1 lifecycle until GREEN, including repeated no-op cycles and all existing161 publication cases. Update exact interfaces/rulings in the ledger if characterization changes the proposed mechanism.

### Task 3: Accept and commit the complete slice

**Interfaces:** Consume the green lifecycle and immutable source candidate. Produce a verified artifact/evidence and independent local commit; whole APK1–4 goal remains active.

- [x] Run full Gradle testDebugUnitTest/Room compile/lint/app+affected native APK builds,627Swift and all contract/localization/store/icon/fold/asset checks. Run local SQL reset/full tests/races only if SQL changes or a new integrity concern requires it; preserve exact inherited proof otherwise.
- [x] Direct Swift/source/diff review and independent read-only review attempt (unavailable usage-limit; no independent verdict); fix demonstrated Important/Critical findings with runtime RED→GREEN.
- [x] Freeze source/APKs, install-r and verify installed/build/archive hashes before/after full appropriate native runs, compiled11falseflags and cold launch. Record every failed run and verification limitation.
- [x] Update evidence/progress/handoff, commit the functional slice immediately and bind actual commit/tree to its ignored artifact manifest. Continue editable allocations/family/remaining RC work.

Execution note: actual frozen runner inventory is504Room/343Investment/35Management (882), not the initial estimated881; counts are derived from runner enumeration and baseline/current Test annotations. All882fullnative passed with unchanged source/APKs; after-install hashes and cold launch passed. Independent read-only reviewer failed usage-limit before any review. Direct executor Swift/diff review completed with this limitation recorded; user TXT requires direct review and permits continued local work. No independent verdict is claimed; remaining external review does not justify blocking other authorized progress.
