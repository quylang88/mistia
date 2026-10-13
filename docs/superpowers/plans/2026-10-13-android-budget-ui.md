# Native Android budget planning implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline. User TXT authorizes immediate implementation and per-slice commits.

**Goal:** Replace budget counts with usable monthly budget hierarchy and offline editor.

**Architecture:** Pure core-model projection ports Swift activeBudgetPlans, budgetBranchRows, reportedExpenseAmount and pace assessment. Compose reads repositories, uses saveable editor/month state and invokes budget repository mutations. Category icons are shared with existing management rendering rather than a divergent mapping.

**Tech Stack:** Kotlin/BigInteger/BigDecimal, Jetpack Compose Material3, Room repositories, shared xcstrings, JUnit/Compose instrumentation.

**Spec:** Original TXT; PlanningLogic.swift budget projection/pace; PlanningEditors.swift budget editor; PlanningSupport.swift frozen snapshots; CurrencyLogic.swift and TransactionLogic.swift reported spending.

## Global constraints
- All six cloud-write gates remain false; no production writes or deployment.
- Exact Long accounting, decimal conversion, no Double wire/accounting.
- Static UI copy comes from shared catalog only; preserve vi/en/ja.
- Owner-scoped budgets, categories, wallets and transactions.
- Current/past/future and carried-forward editing follow the iOS editor. Family aggregation/remote enablement remains the later cloud-first family slice; unavailable family data uses iOS personal fallback.

## Review focus
- Tokyo month boundaries and rollover spending intervals; latest continuity plan wins without mutating history.
- Frozen localized metadata remains stable; missing legacy snapshot fields fall back to live category hierarchy.
- Parent rows include branch expenses once; children do not duplicate summary totals.
- Current-wallet money versus report currencies: use reportedExpenseMinor semantics and source currency conversion, exclude adjustments/installment/card payments.
- Saveable draft recovery/account change isolation, read-only past budgets, destructive confirmation and save failure retention.

## Slice 3: native budget workflow
Files: core/model/BudgetPlanning.kt and tests; feature/planning/BudgetEditorState.kt, BudgetEditorSheet.kt, BudgetRows.kt, PlanningScreen.kt and tests; shared icon rendering as needed; MainActivity wiring; build scripts.
Interfaces: projectBudgets(owner, plans, categories, transactions, wallets, selectedMonth, referenceDate, zone, rates, language, adjustmentTitles, reportingCurrency) -> BudgetProjection. BudgetEditorState.from(plan, month, zone) and toDraft(zone) retain exact amounts and explicit edit intent.
- [x] Write projection RED tests for continuity, scope, snapshots, legacy hierarchy, month/rollover, branch totals, FX, spending exclusions, exact large amounts and Swift pace golden vectors.
- [x] Implement projection and verify GREEN; fix legacy allocation fallback if needed with repository regression.
- [x] Write editor-state RED tests for exact Long parsing, past/carry-forward actions and process restoration.
- [x] Implement native monthly cards, budget form/category picker, save/archive/delete confirmations and dismiss guard; wire repository/device/rate dependencies.
- [x] Review directly against Swift and through independent reviewer; fix findings with RED/GREEN tests.
- [x] Run full Android/Room/lint/assemble, contract and localization checks, focused Swift planning tests, diff checks; run available emulator UI/instrumentation without uninstalling user app.
- [x] Record evidence/remaining family/device limits, archive APK checksum, commit slice; continue savings.

User product decision: one currency per branch; block mixed-currency saves. This intentionally replaces Swift raw mixed-minor addition. Check carried continuity and future anchors as they can coexist. Form inherits branch currency and clears an amount when currency changes.

Device boundary: Compose UI test APK compiled; no ADB device was connected for execution. Emulator/Samsung UI and visual QA remain pending. Independent reviewer identified future-anchor currency conflict; RED reproduced and fixed. Reviewer could not finish final re-review due to service usage limit; final local diff review and regression checks completed.
