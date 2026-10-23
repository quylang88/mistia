# Ordinary transaction lifecycle implementation plan

> Required execution: superpowers:executing-plans inline; observed TDD, one scoped final fresh review. User TXT authorizes autonomous design/implementation/local complete-slice commit without renewed approval.

Goal: actual ordinary transaction archive/restore/delete with exact atomic investment effects and receipt safety.
Architecture: reuse138 seven-entity read/derived planner, add a lifecycle-specific pure plan and Room commit; actual editor and Management route share action confirmation handling.
Tech: Kotlin/Compose/Room/coroutines, Swift reference, current Java17/min26/target36.
Spec: docs/android/transaction-lifecycle-design-2026-10-23.md.

Global constraints: preserve codex/android-apk2-4-parity/current work; all11cloud gatesfalse; Room6/SwiftDataV11; no production writes/deploy/migrations/push; no partial helper commit. Preserve all approved currency decisions.

Review focus: known-success after sync ACK, net downstream income/date effects, manual/tombstone canonical identities, restoration with deleted/archived dependencies or credit payments, receipt deletion concurrent with owner/image replacement. Each belongs to the tests below; no separate per-task agents.

## Task1 — pure lifecycle plan
Files: new core/model TransactionInvestmentLifecyclePlan.kt and test; reuse InvestmentFundUsagePlan.kt, TransactionInvestmentSavePlan.kt.
Interfaces: enum TransactionLifecycleAction; data TransactionInvestmentLifecycleRequest(expected:LedgerTransactionRecord,action,operationAt:String,accountingCurrency:String,adjustmentTitle:String,consent:InvestmentFundUsageConsent?); planTransactionInvestmentLifecycle(snapshot:TransactionInvestmentSaveSnapshot,request,deviceId,now,statementZone):TransactionInvestmentSavePlan.
- [x] Write focused tests: existing expense70/use30 -> archive primary+consumption tombstone and30 restore review; apply -> restore30 review -> active exact replay no writes; delete archived primary DELETE; stale visible expected/foreign/generated/manual identities rejected; unknown/creator/Long ACK preserved. Income archival recomputes downstream allocation. Restore insufficient exact cash/card limit/paid occurrence/duplicate card payment rejected.
- [x] Run model focused; expect explicit unsupported runtime RED before body implementation, not compile errors.
- [x] Implement minimal raw-preserving lifecycle planner, expected semantic checks, replay proof and restored dependency/affordability/paid validation; run fullmodel GREEN.

## Task2 — actual seven-entity Room/repository boundary
Files: Contracts.kt, Repositories.kt, MistiaDatabase.kt; new TransactionInvestmentLifecycleRoomTest.kt.
Consumes Task1 request/plan. Produces FinanceRepository.prepareTransactionLifecycle/saveTransactionLifecycle; LocalStore.commitTransactionInvestmentLifecycle(expectedSnapshot,request,deviceId,now,statementZone).
- [x] Actual Room tests: no consent no writes; archive/restore/delete primary+derived+outbox atomic; last-derived trigger rollback; source and owner-at-final-fence races; actual caller Job cancellation; orphan queue; known result ACK replay/consistent observer. Repository unsupported store never generic fallback.
- [x] Runtime native unsupported RED, implement recomputed full7 CAS and caller/owner fences, then full relevant JVM/Room GREEN.

## Task3 — shared actual lifecycle confirmation and receipt handling
Files: new feature/transactions TransactionLifecycleActionDialog.kt and TransactionLifecycleSave.kt; native TransactionLifecycleReceiptTest.kt/TransactionLifecycleEditorTest.kt.
Consumes Task2 typed request. Produces callback used by editor and archived destination, preserving original owned receipt snapshot and stable operationAt.
- [x] Runtime native RED: canceled archive preserves editor/draft/files/queues; archive/restore keep image; deletion after known financial commit conditionally unlinks original image, lost response and concurrent newer/foreign image preserve safe result.
- [x] Implement minimum explicit confirmation/fund review/retry with current owner/DI/caller checks; do not restore consent/action automatically. Native GREEN.

## Task4 — actual editor and Management archive destination
Files: TransactionEditorSheet.kt, StoredTransactionEditorRoute.kt, TransactionsScreen.kt, new ArchivedTransactionsRoute.kt; ManagementScreen.kt/MainActivity.kt; source localization and generated outputs if needed.
Consumes shared action dialog/Task2 repository. Produces actual archive entry on both editor routes and Management archived-cashflow navigation.
- [x] Native runtime missing UI RED: archive70/use30 -> hide active row; Management list -> restore consent -> active row and owned outbox; archived delete removes row/image only after commit; owned load/error/empty/retry/source conflict/DI/process recreation preserve private drafts and no duplicate writes.
- [x] Implement actual routes/actions and source copy/art, then all affected native tests GREEN.

## Task5 — acceptance and commit
- [x] EN/VI/JA lightdark actualfont130/320dp visuals, separated≥48dp controls/full amounts/glyphs/line ends/no hidden mutation; inspect originals.
- [x] Full testDebugUnitTest/Room compile/app lint/build/contracts/Android+strictSwiftl10n/focused or full Swift as appropriate; source/diff scoped fresh review and one RED→GREEN correction pass. Follow verification-before-completion.
- [x] Version138 APK update/archive/checksum/install-r/coldstart, separate emulator/Samsung/cloud limits; update evidence/progress/handoff. Mark tasks only with actual evidence. Commit complete139 independently and continue nextslice.

Accepted final evidence: docs/android/evidence/2026-10-23-transaction-lifecycle.md; all acceptance checks complete. This document belongs to the dedicated complete139 local commit; continue recurring-bill fund payment/undo next. No full-goal completion claim.
