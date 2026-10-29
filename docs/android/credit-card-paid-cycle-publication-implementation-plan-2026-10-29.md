# Card paid-cycle publication Implementation Plan —168

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. The human already chose continuous inline execution and one immediate commit per completed slice.

**Goal:** Publish and acknowledge the real paid card-cycle marker after its confirmed financial group without creating or changing money.

**Architecture:** A pure owned-snapshot planner authorizes the marker using actual posted money and complete cycle membership. A dedicated compared RPC closes the read/write race. A closed transport, typed Room acknowledgement and due composite worker preserve queue generations and account scope.

**Tech Stack:** Kotlin/JVM17, Room6, coroutines, kotlinx JSON, HTTPS/PostgREST, local PostgreSQL/Supabase CLI2.122.0, pgTAP, Android API36 ARM64; Swift/Xcode parity checks.

**Spec:** `docs/android/credit-card-paid-cycle-publication-design-2026-10-29.md`; original user TXT `/Users/quyln/.codex/attachments/14a5e42d-74ef-4419-b511-5b60da3154aa/pasted-text-1.txt`.

## Global Constraints

- Work in `/Users/quyln/Project/mistia` on `codex/android-apk2-4-parity`; base `a6553d3519a488e14fef37da2492e914fa97f357`. Preserve WIP; no push/reset/deployment/production writes.
- All11 write flagsfalse; generic card paid writes stay disabled. Same currency card/payment/source. Ordinary-money FX unchanged.
- Exact numeric Long, explicitnull, immutable owner/ID/birth, frozen historical month/amount/date. No money, profile or charge rewrite.
- Own disposable local Supabase only;84 existing migrations immutable. All configured/effective published ports127.0.0.1. Never overlap Docker, Gradle/Swift/Xcode, emulator.
- Actual RED→GREEN, complete coherent168 verification and fresh review before immediate independent local commit; tasks do not create incomplete slice commits.
- FullAPK1–4/RC goal remains active. No Samsung/liveSupabase/iOSUI runtime claims.

## Review Focus

- A delayed old active marker after transfer undo must fail at the actual server boundary (Task2 authenticated late-write/race tests).
- A lost old reply followed by a genuinely new payment may reuse the cycle only when the old linked payment is no longer live and strict causal history is proved (Task1 and2 distinct-payment/tombstone tests).
- An archived historical wallet or changed current profile/charge must preserve valid already-posted history, without bypassing unpublished financial dependencies (Task1 and4 history/readiness tests).
- A legacy due-month sibling, including outside one requested month/page, must not double-label a payment (Task1 and3 full membership/paging tests).
- A late reply after owner rotation or local edit must never consume a newer queue or hide a local persistence failure (Task3 Room/worker cancellation/rollback tests).

### Task 1: Pure card publication authority

**Files:** Create `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/CardPaymentPublication.kt`, focused `CardPaymentPublicationSnapshot.kt`/`CardPaymentPublicationProof.kt` if needed; test `android/core/model/src/test/java/vn/com/quyln/mistia/core/model/CardPaymentPublicationTest.kt`.

**Interfaces:** Consumes `CloudRecord`, `QueuedMutation`, `DueOccurrenceRecord`, `LedgerTransactionRecord`, `LedgerWalletRecord`, `cashEventInstant`. Produces `CardPaymentPublicationSnapshot(owner:UserId,cardId:String,recordsByEntity:Map<CloudEntity,List<CloudRecord>>,queues:List<QueuedMutation>,dirtyKeys:Set<Pair<String,String>>)`, `CardPaymentPublicationObservation(cycles:List<CloudRecord>,ledger:Map<String,CloudRecord?>,wallets:Map<String,CloudRecord?>)`, `planCardPaymentPublication(source,queued,observed,zone:ZoneId):CardPaymentPublicationDecision`, decision NeedLedger/NeedWallet/Write(payload,expectedVersion)/Acknowledge(record)/Deferred(reason)/Conflict(reason), `requireCardPaymentPublicationResult(source,queued,observed,zone,result)` and remote `publish(source,queued,observed,zone,accessToken):CloudRecord?`.

- [x] Write tests asserting new marker amount9007199254740993/version1 from exact transfer; observed0 conditional update; semantic actual ACK; full-owned snapshot/queue equality; missing dependency reads; same currency/ordinary posted/internalTransfer; exact birth/paidAt; legacy overpayment; profile/charge/archive history; pending related money/allocation queues; same/legacy-month siblings; undo0 tombstone fence and positive absence; unknown newer tombstone; causal same/different-payment recovery; closed result.
- [x] Run `cd android && ./gradlew :core:model:testDebugUnitTest --tests '*CardPaymentPublicationTest'`. Expected first compile failure for missing authority (not runtime RED); add closed non-authorizing API skeleton, rerun and observe actual missing-authority assertion RED.
- [x] Implement the typed snapshot/financial proof/planner, with complete card-level cycle inspection and explicit dependency decisions. Run same command; Expected all new testsPASS. Add regressions before fixes for discovered behavior.
- [x] Run focused authority plus existing `*InstallmentPaymentPublicationTest` and `*CreditCardStatementPaymentTest`; Expected allPASS. Record actual outputs/decisions in evidence/ledger. Task completion is a verified subtask;168 remains uncommitted until Task4.

### Task 2: Compared PostgreSQL mutation

**Files:** Create additive85 migration via pinnedCLI; add `supabase/tests/database/card_paid_cycle_publication.sql` and `Scripts/tests/test_card_paid_cycle_races.py`; evidence in168 document.

**Interfaces:** Consumes Task1 closed15field marker, expectedpresence/version and actual dependency/membership observations. Produces `public.mutate_card_paid_cycle(p_cycle jsonb,p_expected_version bigint,p_expected_presence boolean,p_expected_ledger jsonb,p_expected_wallets jsonb,p_expected_cycles jsonb) returns jsonb` plus narrow invoker all-month card membership serialization trigger.

- [x] Preserve actual84 late-write control: live payment succeeds, deleted payment and deleted card incorrectly accepted (2runtimeRED). Add failing authenticated RPC cases for actor/globalID/presence0/birth/strict fields, active/tombstone/history/causal transition and no-money writes. Expected missingRPC only until migration skeleton, then actual assertionsRED.
- [x] Implement locks/compared write and closed ACL; prove invoker vs explicit definer using actual foreign/global-ID tests. No profile/charge rewrite or arbitrary global unique cleanup. Expected focused pgTAPallPASS.
- [x] Run actual parallel mutation/undo/wallet/membership/globalID races, including negative controls disabling the new relevant protection in a rolled-back local transaction or disposable reset. Expected serialized outcome and demonstrated negative-control failure; handle40P01/40001 as bounded retry.
- [x] Fresh own-local85 reset, allSQL contracts/full pgTAP and all existing/new races; local advisor baseline/new comparison. Expected allPASS, no persistent synthetic owners, before/afterloopback proof. Stop Docker before Gradle. Record actual test counts/hashes.

### Task 3: Closed transport, Room ACK and sync worker

**Files:** Create `android/core/network/src/main/java/vn/com/quyln/mistia/core/network/SupabaseCardPaymentPublicationClient.kt`, `android/core/sync/src/main/java/vn/com/quyln/mistia/core/sync/CardPaymentPublicationCoordinator.kt`, corresponding JVM tests and `android/core/database/src/androidTest/java/vn/com/quyln/mistia/core/database/CardPaymentPublicationRoomTest.kt`; modify `Contracts.kt`, existing Room localstore, due composite and appDI using installment publication patterns without a generic card fallback.

**Interfaces:** Consumes Task1 types and Task2 RPC. Produces typed LocalStore snapshot/acknowledgement/failure methods that revalidate whole captured generations atomically, closed HTTPS remote implementation and worker integrated before generic due handling with full candidate discovery/card-cycle pagination. Reuse existing gates; every prerequisite gate checked at worker and transport boundaries.

- [x] Write exact transport/payload/Long/null/gates/session/malformed-response/error tests; Room exact-source/late-edit/rollback/cancellation tests; worker >100/paging/lost-reply/owner/session/caller/deferred/scopedfailure tests. Run each first against closed skeleton; Expected actual assertionsRED, not only compile errors.
- [x] Implement minimal transport/Room/worker and DI preserving due deletion/bill/installment order and unpublished financial dependency holds. Expected all new focused JVM and actual nativeRoom testsPASS.
- [x] Run focused old installment/financial/due regression suites, Roomcompile and nativeRoom. Expected allPASS and no mutation to unrelated queues. Record APK/source fences for native evidence.

### Task 4: End-to-end parity and acceptance

**Files:** Extend `InvestmentOrdinaryAllocationPublicationIntegrationTest.kt`; maintain168 evidence, handoff/progress, immutable artifact manifest and this plan's ledger. Directly review corresponding Swift manual/due/maintenance calculation and payment methods.

**Interfaces:** Consumes Tasks1–3 actual repository/Room/HTTPS/RPC-compatible worker; produces independently reviewable accepted168 commit/mainAPK165 plus exact immutable source/commit/artifact/test binding.

- [x] Existing real transfer70/allocation−30/missing marker1testRED0.520s becomesGREEN with the actual new worker. Add lostreply/newerintent/undo/history/long/membership lifecycle regressions before implementation fixes; Expected actual client-visible outcomes with no duplicate money.
- [x] Run full `./gradlew testDebugUnitTest`, appropriate Room/testAPK compilation, `:app:lintDebug`, `:app:assembleDebug`, contract/localization checks, full Swift and actual universal iOSSimulatorapp build, complete3APK native suites under observed readiness. Expected allPASS; accurately record any earlier failing attempts and exact rerun conditions. No speculative timeout patches.
- [x] Review full immutable diff directly against Swift, dispatch one fresh whole-slice reviewer per requesting-code-review, classify findings by user impact and fix material findings withRED→GREEN plus full affectedsuite. Expected no unaddressed material findings.
- [x] Final diff/source/gates/ADB/resource checks; create immutableAPK165/testarchives/manifest/evidence, updatehandoff/progress, immediate `git commit -m 'feat(android): publish card statement paid markers atomically'`, bind actualcommit/tree. Expected one complete independent168 commit with verified artifact/source identity. Continue next fullscope slice.
