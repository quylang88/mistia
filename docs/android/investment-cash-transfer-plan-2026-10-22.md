# Investment Cash Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. Continue the user-authorized inline execution method.

**Goal:** Native source-equivalent creation of investment cash deposit/withdrawal with exact previews and atomic ledger/posting/outbox persistence.
**Architecture:** Extend132 four-entity owner snapshot with an exact preview/planner and one CAS commit seam. Keep rendering/read lifecycle shared, add a focused saveable native form and real actions.
**Tech Stack:** Kotlin/BigInteger/Compose/Room/coroutines; existing Swift source and contracts.
**Spec:** docs/android/investment-cash-transfer-design-2026-10-22.md

## Global Constraints

- Existing codex/android-apk2-4-parity branch; baseline4c8109de. Preserve prior work; no new checkout/permission/delegation round.
- All11 cloud flagsfalse, Room6; no production/deploy/migration/RPC/write or push.
- Exact read BigInteger, wire Long; a single transfer maximum cannot exceed Long.MAX_VALUE.
- Eligible selected/linked/system owned/live/unarchived, valid matching ISO; selected noncredit/noninvestment. Same-wallet transfer valid.
- Final whole-branch fresh review and APK1–4/RC remain open. Per-slice author source review + full appropriate verification/commit required.

## Review Focus

1. Huge exact money cannot overflow per-record maximum; Task1 tests max+max and Long.MIN requests.
2. Same-wallet transfer must change allocation without changing actual cash; Task1/2/3 prove self-pair and two rows only.
3. A response lost after commit must not duplicate or silently accept partial/reused event; Task1 replay field/date/null corruption and Task2 CAS/retry tests.
4. Foreign body/owner or normalized mixed currency cannot become valid wallet/amount; Task1 raw boundaries and Task2 owner-replacement tests.
5. Backdated time/restored note/amount cannot become a new event or different consent; Task1 timestamps, Task3 restoration and pending action tests.

### Task 1: exact preview and atomic mutation plan

**Files:** core/model InvestmentCashTransfer.kt / InvestmentCashTransferPlan.kt and InvestmentCashTransferTest.kt / InvestmentCashTransferPlanTest.kt; InvestmentCashReadSnapshot.kt unchanged except optional requireUnchanged helper if needed.
**Interfaces:** consumes InvestmentCashReadSnapshot, investmentCashAllocation, investmentPersistedProfit, financeWalletBalancesRaw, strict investmentLinkedWalletRecord. Produces InvestmentCashTransferDirection, InvestmentCashTransferPreview, investmentCashTransferPreview(direction,requestedMinor:Long,realizedProfitMinor:BigInteger,availableInvestmentMinor:BigInteger,linkedBookedMinor:BigInteger,sourceActualMinor:BigInteger,sourceInvestmentMinor:BigInteger); then draft/request/plan and planInvestmentCashTransfer(snapshot,request,deviceId,now).

- [x] Add scalar tests first: deposit(realized5000,available3200,sourceActual10000,sourceInvestment2000,request1800)→maximum1800/ordinary8000/valid; request1801 invalid. Withdrawal booked2500 request2500 valid, request2501 invalid even with other available cash. Negative values clamp limit/request appropriately; max+max read values stay exact while max wire limit Long.MAX_VALUE.
- [x] Run :core:model:testDebugUnitTest --tests '*InvestmentCashTransferTest'; expect runtime unsupported RED, then minimum scalar implementation and GREEN.
- [x] Add snapshot/planner tests before implementation: same-wallet deposit500 keeps actual10000/allocation+500; other-wallet withdrawal300 lowers linked actual/allocation300 and raises selected actual300; exactly ledger+posting+queues2, signed manual booked posting, null trade/asset and exact versions/nulls. Invalid amount/mixed currency/owner/stale visible dependency/partial event/backdated malformed dates fail without plan. Valid committed replay no-op; each replay monetary/reference/date/null mismatch fails. Watch runtime RED, implement, focused+model suite GREEN.

### Task 2: repository and Room CAS

**Files:** Contracts.kt, database InvestmentCashTransferRepository.kt, Repositories.kt, MistiaDatabase.kt, corresponding JVM/Room tests.
**Interfaces:** consumes Task1 draft/request/plan and132 cashSnapshot4. Produces InvestmentRepository.saveCashTransfer(owner,request,deviceId,now):Result<Unit> and LocalStore.commitInvestmentCashTransfer(expected,request,deviceId,now):Boolean. Repository re-reads current4 and validates scope/visible source; Room rechecks whole4 within transaction and applies2 records+outbox.

- [x] Unsupported API runtime JVM+Room RED: exact2 owned rows/queues, consistent observation, foreign-owner rejection, current owner swapped before/after read/commit, CAS competitor, failed middle write rolls back, replay duplicates no writes.
- [x] Minimum implementation then focused JVM/actual Room GREEN. Keep old131 mutation3 unchanged and gate settingsfalse.

### Task 3: actual native actions/form and delivery

**Files:** feature/investment InvestmentCashTransferSheet.kt, InvestmentScreen.kt/shared cash read sections, native test file; app version/progress/evidence.
**Interfaces:** consumes same cashLoad4 from132 and Task1/2. Produces working deposit/withdraw actions, saveable direction/event/source wallet/amount/note/date/creation/visible consent and resumed pending flow after real linked picker.

- [x] Actual missing-flow native RED: same/other-wallet deposit/withdraw ledger/allocation/actual totals and queue2; eligible currency/owner options; entered amount over maximum disabled, max button exact; same-wallet explanation/date/note; canceled no writes. Implement minimum then GREEN.
- [x] Runtime tests for source changes while open, unreadable read/retry, save failure/retry/restoration same event/draft, duplicated taps, owner replacement/late old success, link-first resume. Preserve all existing131/132 tests and assertions; scroll actual virtualized rows as needed.
- [x] Native EN/VI/JA lightdark actual font130/320dp full money/glyph/bounds/nonoverlap tests, inspect original captures and fix findings via TDD. No placeholder history/edit/delete/reconcile controls.
- [x] Full appropriate JVM/Room compile/assembly/lint/app/Swift/contracts/l10n/store/schema/assets checks and affected native regressions; direct complete diff/Swift review/fixes. Version133 update install-r/COLD/archive+installed hashes and truthful evidence/progress, separate local commit; continue protected ordinary outflows/history/trades/private images/RPC and remaining full goal.
