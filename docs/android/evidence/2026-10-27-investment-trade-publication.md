# Slice154 — closed investment trade publication

Baseline `9b1647392ba809ed4b233340bdd8604a83bf3d2e`, branch `codex/android-apk2-4-parity`, main153. This slice publishes trade intents and reconciles their complete derived financial results when metadata prerequisites are ready. APK1–4/RC remains active. Offline close/archive and move/archive with dirty asset/channel prerequisites require the next integration slice; separate investment cash RPC publication also remains unfinished. All11 write flags remain false.

## Behavior and authority

The closed owned HTTPS port uses existing `mutate_investment_trade` and `delete_investment_trade` RPCs with forcefalse and exact Long CAS versions. It validates identity, session, caller, gate, zero/positive money, quantity/unit, date, FX and wallet shapes; preserves explicit nulls and unknown business fields; excludes eleven derived financial fields and private local evidence from requests. Reads use bounded keyset pagination until an empty page, including when the server returns fewer rows than requested. No generic financial writer is opened.

The source snapshot covers all nine planner entities, every owner queue beyond the usual due100 cap, and exact dirty keys. Typed Room source/failure/receipt/result methods check the entire generation and captured session/caller/owner at transaction entry and completion. A late reply may record definite causal evidence without consuming a newer proposal or changing its business/base/retry stamps. Remote ingress rejects private local journal keys before replacing clean trade snapshots.

Publication requires complete owned affected asset histories and a mathematically coherent FIFO result. Canonical trade, ledger and posting roles, IDs, currencies, amounts, retirement and references must agree before one atomic Room transaction imports financial results and removes exact matching queues. Unrelated cash-operation queues remain pending. Cross-table reads are candidates rather than an assumed atomic database snapshot: inconsistent candidates retain local work for retry.

Bounded causal parents distinguish proven own earlier writes from unknown own later writes. Definite closed DELETE observations certify only unchanged peer intent with exact version+1, actor, operation timestamp and membership; they do not authorize financial imports. Safe intermediate FIFO scheduling defers dependent edits, publishes an eligible peer first, and retries after progress. Deferred failures retain their original decision snapshot. HTTP status classification precedes IOException handling.

When both local and server records are deleted, semantic matching uses validated identity and immutable microsecond created-at. A discarded unpublished note, amount or reassignment need not be uploaded before deletion. The actual server tombstone and financial rows are imported; alive opaque fields and causal-parent fingerprints retain exact comparison.

## Runtime RED → GREEN

- Strict intent/closed HTTP contract tests exposed missing validation, half-microsecond timestamp rounding and lost response-body handling before fixes. Local PostgreSQL establishes actual create2, update proposed+1 and delete compared+1 rules; closed DELETE returns only its requested tombstone while rebuilding peers.
- Typed Room source/failure9, result ACK9 and receipt9 cases were observed RED against unsupported methods, then GREEN with stale-generation, owner/session/caller rollback and failed-write coverage. Remote journal ingress and final pull fences each had actual HTTP/Room RED→GREEN regressions.
- Independent review found three P2s. Captured sibling ancestry had actual model RED→GREEN. Four oldest-first local BUY deletions had actual Room/HTTPS RED before closed-delete trace wiring, then GREEN with requested bases2/4/6/8. Dependent BUY10/SELL10→BUY5/SELL5 had actual Room/HTTPS RED, then GREEN with SELL5 published before BUY5.
- Discarded note/amount before delete had actual model2 and Room/HTTPS2 RED→GREEN; reassignment-before-delete is also covered. HTTP403 classification and dependency400 deferral had actual unit RED→GREEN. An older deferred400 decision applied to a newer note had actual unit RED→GREEN by retaining its original source generation.
- Final focused actual repository+Room+authenticated local HTTPS integration19/19 passed5.662s before the last deferred-source safety fix. The final full native packages include that fix. Cases cover positive/zero BUY/SELL, JPY70/VND11550 paired funding, SELL release28/profit52, both-asset reassignment, late/lost replies, gate/session revocation, absent/published deletion, reverse SALE/BUY deletion and dependent edits. The fixture uses real repository/model projections and is not an independent SQL arithmetic oracle; SQL tests are separate evidence.

The original review's claim that its dependent-edit trace caused permanent backoff was corrected: the inherited IOException made that old response retryable. The runtime ordering failure was real. Current status-first handling and dependency scheduling are separately tested. Compile/parser mistakes are excluded from product RED counts.

## Direct reference review and limits

Swift `Mistia/Shared/Sync/SupabaseRemoteStore.swift:480` and `:676` provide the closed mutate/delete requests. Effective SQL is `20260822030000_allow_zero_amount_investment_promotional_buys.sql`, its unit extension `20260822050000`, and the DELETE body in `20260809090000_investment_domain.sql:1362`. Shared Android rebuild keeps existing callers' unit normalization; remote-result proof opts into preserving legacy unit labels. PostgreSQL microsecond half-even dates are used for scheduling and fingerprints. No Swift runtime, schema or migration was changed.

Independent read-only reviewer `review_trade_publication154` verified frozen follow-up patch SHA256 `0930c4d92cad95b55c4926646fe04facbc7bec0fb67899cc2136e1bd4f19d9f8`, found all three findings resolved and no remaining introduced P1/P2 within this closed trade foundation. The reviewer ran no builds/tests and explicitly accepted the staged disabled boundary, with metadata retirement/cash integration left in the active goal. This is not a whole-branch or production-readiness verdict.

Local SQL: all77 existing migrations and7 pgTAP files/278 assertions PASS, including27 new trade publication/time assertions. No production connection, schema deployment or migration. CLI local binding/network setup was corrected before tests; all our five containers and Docker Desktop were stopped afterward, with volumes retained, before resuming the emulator.

Final host `testDebugUnitTest`, Room test compilation, app lint/build and both native test packages passed57s. Actual XML:2525JVM/231suites, zero failures/errors/skips. Swift full unfiltered `swift test --jobs2`:627=4+151+472, zero failures; Swift source is unchanged after that run. All11 contract/localization/outbox/notification/installment/icon/unit-fold/Room scripts return0. Room6/SwiftDataV11 unchanged. All five user currency decisions remain in force.

## Final acceptance and frozen artifacts

Android source:31files/305464 patch bytes against the baseline, SHA256 `e8f8ed8929d9840215be8165bf5e36a6d442e8fc0bd922441485d56e2d74b8eb`. Candidate directory `android/build/outputs/apk2/2026-10-27/slice154-candidate-e8f8ed8929d9/` contains immutable source/APKs/badging/signing evidence. Main153: min26/target36/20DEX/37268929bytes, SHA256 `359985b2cf9d175da4ebe2dfd41194e7eea7723710616f81ff666219f679380e`. Debug certificate SHA256 `72064998df2a813facabae5e30fd1e7f7631c920e719d6bcb90008aa45d0235e` matches accepted153.

All three APKs were installed with `adb install -r`, then their installed baseAPK bytes pulled and hashed against build/archive before native testing. No data clear/uninstall. A freeze harness first expected obsolete aapt `sdkVersion` output instead of actual `minSdkVersion`; it stopped before manifest/install/native and was corrected. No source/APK change was needed, and that parser failure is excluded from native evidence.

Final full native: Room436/436 GREEN10.997s and Investment237/237 GREEN991.384s, total673, zero failures/ignored cases. Both exact terminal counts and per-case statuses were verified. All three build/archive/installed hashes still match after the suites; frozen Android source is unchanged. Main153 cold launch returned COLD Statusok; its time is observational, not a benchmark. Accepted aliases, source manifest, copied logs and hashes are in `android/build/outputs/apk2/2026-10-27/slice154-artifacts.json`, `slice154-source.patch/json` and `slice154-logs/`.

```text
Starting: Intent { cmp=vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity }
Status: ok
LaunchState: COLD
Activity: vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity
TotalTime: 1125
WaitTime: 1126
Complete
```

API36ARM64 emulator only. No Samsung, live Supabase, production write/deploy/migration/push, or OAuth/account-switch replay. Native emulator success does not establish Samsung or full APK1–4/RC acceptance. Continue metadata retirement coordination, separate cash RPC, remaining family/receipts/background/settings/security/signing and final physical-device RC.
