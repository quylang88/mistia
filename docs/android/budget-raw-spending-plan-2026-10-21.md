# Raw Budget Spending Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, with TDD and final whole-branch review at the end of the full user goal.

**Goal:** Keep unavailable required budget spending truthful and consume one consistent owner-scoped read snapshot.

**Architecture:** Room emits the four budget input entities in one query. A raw effect adapter selects required money and feeds the existing exact core projector; current typed callers keep equivalent behavior. Shared raw classifier candidates move to core without changing Overview semantics.

**Tech Stack:** Existing Kotlin/Compose/Room6/coroutines/BigInteger/JSON; JDK17/min26/target36; no new dependency.

**Spec:** `docs/android/budget-raw-spending-design-2026-10-21.md`, original user TXT and accepted same-currency decisions.

## Global Constraints

- Stored/wire money remains signed Long; aggregate/conversion read amounts stay exact and nullable.
- All10writeflagsfalse; no production write/deploy/migration, no schema version change.
- Room is source of truth; UI calls repository only. Reads cannot mutate records/outbox.
- Owner/envelope/body identity is checked before grouping/deduplication; historical metadata remains scoped.
- Shared catalog is the only static copy source. Reuse `planning_installment_retry` only as its generic Retry label.
- Continue approved current branch and per-slice local commits. Do not recreate already completed119/120 work or pause for redundant design/execution consent.

## Review Focus

1. Quoted/null/overflow required money versus unused bad destination/income/created fields — assert unknown only where required, with literal7/0 controls.
2. Atomic wallet/ledger currency transitions — real Room emits only100JPY across JPY100/VND16500 pairs at165; owner/tombstone predicates tested at the repository boundary.
3. Required source metadata versus archived/unneeded wallet fields — VND165→JPY1, explicitJPY165 unaffected by unused opening/kind except card titles, missing/invalid required source stays unknown.
4. Unreadable category/reference/parent data — never a confident mismatch/omitted spend or crash; canonical/custom matching and neutral0 controls.
5. Loading/error/retry/late owner emissions and stored editor identity — no stale totals, no false0, no Create/default amount on stored taps, no read/outbox mutation.

### Task 1: Add a consistent owner-scoped budget read snapshot

**Files:** Create core model `BudgetReadSnapshot.kt`; modify `BudgetMutations.kt`, `Contracts.kt`, database `BudgetRepository.kt` and `MistiaDatabase.kt`; tests in database `src/test/.../BudgetReadSnapshotTest.kt` and `src/androidTest/.../BudgetReadSnapshotRoomTest.kt` (full package vn/com/quyln/mistia/core/database).

**Interfaces:** `BudgetReadSnapshot(owner:UserId, rows:List<CloudRecord>)`, `records(entity:CloudEntity):List<CloudRecord>`, companion `entities:Set<CloudEntity>` exactly BUDGET_PLAN/LEDGER_TRANSACTION/LEDGER_WALLET/TRANSACTION_CATEGORY. `BudgetRepository.observeBudgetReadSnapshot(owner:UserId):Flow<BudgetReadSnapshot>` and corresponding LocalStore method. Production Room uses a single owner/entity-IN query including tombstones. Repository retains raw field damage, filters scope, and rejects a snapshot whose owner differs. Unsupported implementations fail explicitly rather than fabricate an empty loaded snapshot.

- [x] Write new repository/native tests before fixes. A legacy adapter may expose current multi-flow behavior solely to obtain runtime baseline evidence. Assert owned four-entity rows/tombstones, excluded foreign/body mismatch, and the JPY100/VND16500 atomic invariant.
- [x] Run `:core:database:testDebugUnitTest --tests "*BudgetReadSnapshotTest"` and `:core:database:assembleDebugAndroidTest`; direct runner class `vn.com.quyln.mistia.core.database.BudgetReadSnapshotRoomTest`. Record actual business RED or a passing control; no compile failure counted as RED.
- [x] Add the production query/producer and owner guards; test complete raw rows and no mutation/outbox side effects.
- [x] Run focused GREEN. This producer and Task2 are one budget-reader slice, committed after full vertical verification below.

### Task 2: Project raw budget expenses and wire the actual screen

**Files:** Create core `BudgetExpenseEffects.kt`, `FinanceRawInputs.kt`/`FinanceClassificationCandidates.kt` only as needed for unchanged shared extraction, planning `BudgetRawSpending.kt`/`BudgetReadLoad.kt`, `src/test/.../BudgetRawSpendingTest.kt` and `src/androidTest/.../BudgetRawSpendingScreenTest.kt`. Shared `financeGroupingName(String?):String` also preserves Swift canonical-equivalent/Unicode-whitespace label matching; existing Overview name normalization delegates unchanged. Modify core `BudgetPlanning.kt`, Overview raw helper/candidate wrappers, planning `BudgetRawPlans.kt`/`PlanningScreen.kt`, app versionCode121. Keep persistence models and other domain projections unchanged.

**Interfaces:** `BudgetExpenseEffect(id:String, ownerUserId:String, categoryId:String?, occurredAt:Instant?, sourceCurrencyCode:String?, expenseMinor:Long?, categoryMayBeUnknown:Boolean=false, branchMayBeUnknown:Boolean=false, branchIdentityKnown:Boolean=true)`. Append optional `expenseEffects:List<BudgetExpenseEffect>?=null` to `projectBudgets`; old typed callers derive equivalent effects. `budgetExpenseSource(record:LedgerTransactionRecord, categorySystemKey:String?, walletKind:WalletKind?, adjustmentTitles:Set<String>):OverviewReportingSource` reuses existing classifier/exclusions. `projectRawBudgetReadSnapshot(owner:UserId,snapshot:BudgetReadSnapshot?,month:YearMonth,reference:Instant,zone:ZoneId,rates:List<ExchangeRateSnapshot>,language:CategoryNameLanguage,adjustmentTitles:Set<String>,currency:String,deletedCategoryName:String=""):BudgetProjection`. Raw input factory emits nullable Long effects, never marker money. `BudgetReadLoad` Loading/Loaded(snapshot)/Failed with owner/repository/retry/lifecycle cancellation; failed read gets Retry, no old loaded snapshot. Screen uses snapshot rows for both projection and stored edit.

- [x] Write literal business tests for raw required fields/overrides/neutral fields/status/date/FX/metadata/owner and exact arithmetic; create an adapter equivalent to existing typed intake for runtime RED, without implementing the fixes first.
- [x] Add actual Room screen baseline tests: required malformed amount gives unavailable spent/remaining with known1000 limit; raw body deletion/status cannot vanish; repair remains read-only; a snapshot withheld/failed/retried or switched owner cannot publish stale/zero money.
- [x] Run RED commands and inspect reasons. Existing known0/unrelated/unused-field controls may pass; label those honestly.
- [x] Extract shared candidate enumeration unchanged, implement raw effect intake and core effect projection; keep legacy typed vectors. Wire one snapshot and explicit failed-read retry, strict stored id/amount path and report-only UI.
- [x] Run focused JVM/native GREEN; review direct Swift PlanningLogic244–383/936–1038/1291–1415 and current diff. Any important finding gets its own reproducible RED before fixing.
- [x] Run full JVM/required AndroidTest compile/package/lint/main build, relevant complete native budget and Overview regression suites, Swift610/contracts15/both strict localization/SQLite7-3-11/Room6assets/whitespace. Inspect exact test counts/terminal0, not ADB exit status alone.
- [x] Inspect localized actual130% images from final packages; archive APK121/main+executed native packages, check manifest/DEX/version/SHA, install-r/cold and compare installed SHA. Update evidence/progress and commit the coherent reader slice. Run task-done contract, then continue original APK1–4/RC scope.

Verification commands use existing JDK17/gradlew, current ADB transport13, AndroidJUnitRunner and the scripts in120 evidence. No parallel Gradle/source edits during a live build. Full task gate: `android/gradlew -p android testDebugUnitTest :core:database:compileDebugAndroidTestKotlin :core:database:assembleDebugAndroidTest :feature:management:compileDebugAndroidTestKotlin :feature:planning:assembleDebugAndroidTest :feature:overview:assembleDebugAndroidTest :feature:transactions:compileDebugAndroidTestKotlin :feature:settings:compileDebugAndroidTestKotlin :app:lintDebug :app:assembleDebug --max-workers=1` with JAVA_HOME set to the established JDK17.

Self-review: raw snapshot ownership/type signatures match producer and consumer; all five review input classes have tests above. No extra currency capability, family aggregation, cloud gate or mutation behavior is inferred. Existing user instruction to continue autonomously with technical judgments takes precedence over extra skill approval handoffs; genuine new product decisions still require the user.
