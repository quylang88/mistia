# Atomic Investment Cash Event Publication Implementation Plan

> Continue inline under the current no-delegation developer instruction. The current skill catalog does not expose the former Superpowers workflow; preserve its recorded TDD/evidence sequence without claiming an unavailable skill or external reviewer. Steps use checkbox syntax for tracking.

**Goal:** Publish existing offline investment deposit/withdrawal create/edit/delete through the existing atomic cash-event RPC and acknowledge only a proven complete result.

**Architecture:** A dedicated gated HTTPS port and typed four-entity local generation feed a cash-event coordinator. Separate owned read candidates must prove the canonical ledger/posting pair before one Room financial ACK. Generic financial writers and unrelated queues remain outside this authority.

**Tech Stack:** Existing Kotlin/Room/OkHttp/Compose/Supabase RPC/Swift reference and local pgTAP.

**Spec:** `docs/android/investment-cash-event-publication-design-2026-10-27.md`.

## Global Constraints

- Baseline ae00941a; existing codex/android-apk2-4-parity branch and inline execution method. User TXT opts out of repeated design/implementation approval questions.
- All11 cloud-write flags false; forcefalse only; no production write, deployment, migration or push. Do not rerun155 acceptance/freeze scripts after156 edits.
- Exact signed Long minor/versions; all cash currencies equal; existing five product decisions persist. Do not change Swift runtime to accommodate Android.
- Owner/caller/captured-session and whole generation/queue fences before and after every typed local write. Never fail/ACK a posthoc refreshed queue.
- Internal tasks compose one coherent event-publication slice; commit156 after full slice verification. Allocation posting RPC, family and full APK1–4/RC remain afterward.

## Review Focus

- Posting created_at differs between local save time and RPC ledger-created-time normalization: prove only this known creation rule; updates keep immutable identity.
- A ledger-only definite response/lost body cannot authorize an unrelated or newer posting: pin full candidate/receipt/source proof.
- Never-published deletion with orphan remote postings must remain queued; published tombstones must not require discarded local edits.
- Concurrent cash-capacity/root-link changes and pending cash/trade dependencies must retain work rather than apply permanent MAX or stale backoff.
- Generic transaction ingress/writers must reject or defer private cash ancestry and investment ledger roles; no financial domain laundering.

---

### Task 1: Closed owned cash-event network port

**Files:** Create model `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/InvestmentCashEventPublication.kt`; network `android/core/network/src/main/java/vn/com/quyln/mistia/core/network/SupabaseInvestmentCashEventClient.kt`; test sibling `.../src/test/java/vn/com/quyln/mistia/core/network/SupabaseInvestmentCashEventClientTest.kt`.

**Interfaces:** Produces `InvestmentCashEventProposal(transaction:CloudRecord,posting:CloudRecord)`, `InvestmentCashEventCloudSnapshot(owner:UserId,eventId:String,transaction:CloudRecord?,postings:List<CloudRecord>)`, and `InvestmentCashEventRemote.fetchEvent(owner,eventId,token)`, `mutateEvent(owner,proposal,expectedVersion,expectedPostingVersion,token)`, `deleteEvent(owner,eventId,expectedVersion,expectedPostingVersion,modifiedAt,deviceId,token)`; mutate/delete return `CloudRecord?`. Nullable expectedPostingVersion means no observed existing posting. No force argument.

- [x] Write positive runtime contract tests for VND50 deposit, VND20 withdrawal, exact9007199254740993 bases, explicit null body keys, optional observed posting map and forcefalse; owned complete short-page reads; positive delete wire; wrong session/currency/canonical posting/private/HTTP403/lost-body cases.
- [x] Run focused class; observe actual runtime RED, not compile/parser mistakes.
- [x] Implement strict closed port and pure shape helpers with exact SQL normalization and bounded owned pagination.
- [x] Run full model/network unit suites; expected zero failures/errors/skips.

### Task 2: Source-bound canonical proof and Room bookkeeping

**Files:** Add focused model result/receipt helpers and tests; extend `Contracts.kt`; implement typed methods in `MistiaDatabase.kt`; add dedicated cash-event Room instrumentation tests.

**Interfaces:** Consumes Task1 DTO/port. Produces `InvestmentCashEventPublicationSnapshot(owner,eventId,rows,pending,dirtyKeys)` with requireCoherent/requireUnchanged; LocalStore source, receipt, failure and atomic result methods carrying captured-session predicates. Exact signatures and canonical-only changed keys must be fixed in the task brief before edits.

- [x] Pin canonical sign50/−20, role/bucket/origin/currency/identity/version/time normalization, foreign/private/partial candidates, alive vs tombstone and unrelated queues with runtime RED.
- [x] Add durable bounded local ancestry only when needed for definite/lost responses; reject remote authority and strip outgoing private evidence.
- [x] Pin exact stale/newer queue, same-owner session replacement at the final write, caller cancellation and late database insert rollback in actual Room.
- [x] Implement minimal typed generation/receipt/failure/result transactions; focused and full core/Room verification must be green.

### Task 3: Coordinator and actual lifecycle integration

**Files:** New `InvestmentCashEventPushCoordinator.kt` and tests; actual cash-event publication Android integration test; `AppModule.kt` integration; ordinary investment ledger guard/ingress only as needed to preserve domain isolation.

**Interfaces:** Consumes Task1+2. Produces one domain coordinator integrated after prerequisites without duplicate-entity loss; preserves all7 summary counters and global+investment gates.

- [x] Reproduce actual repository/Room deposit/withdrawal queue retention before coordinator implementation; verify the six composite phases/all seven counters and current engine entity de-duplication wiring.
- [x] Add actual create/edit/delete/same-wallet, ready/pending root dependencies and ordered trade prerequisites, lost/late/newer response, unknown own later version, absence/orphan and full source race cases.
- [x] Implement closed CAS publication, full candidate proof/atomic ACK, exact original failure context and finite dependency scheduling/conflicts. No generic posting writer or unrelated queue ACK.
- [x] Pin future retry time, >100 due selection, gate/session/caller cancellation and both captured and current owner boundaries; run focused runtime RED→GREEN and full appropriate suites.

### Task 4: Independent source review and full slice acceptance

**Files:** New156 evidence, progress/handoff and APK versionCode155; source/APK/log manifests under new156 paths only.

- [x] Review direct Swift/effective SQL, add local independent cash-event pgTAP vectors as needed (never linked production). Stop Docker before native/build work.
- [x] Perform a separate inline read-only scoped review under the current no-delegation instruction; reproduce/fix important findings by TDD and green suites.
- [x] Full testDebugUnitTest, Room test compile, app lint/assemble, appropriate whole native packages, Swift627/current total and11scripts. Verify exact terminal native counts/no ignored, APK contents/cert/installed SHA and cold launch.
- [x] Update evidence/progress/handoff, commit156 independently, bind actual commit to frozen Android source manifest, then continue allocation publication and full APK1–4/RC.
