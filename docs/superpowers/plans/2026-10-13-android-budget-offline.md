# Android budget offline implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline. User's TXT authorizes continued implementation and per-slice commits without further design approval.

**Goal:** Persist owner-scoped budget mutations and their outbox entries atomically, matching the iOS editor.

**Architecture:** Add BudgetRepository through FinanceRepository delegation; use existing generic Room cloud records. A batch mutation boundary commits budgets and category side effects together. Preserve remote versions and frozen category metadata.

**Tech Stack:** Kotlin, Room, coroutines, JUnit, Swift reference implementation.

**Spec:** Original attached TXT; Mistia/Features/Planning/PlanningEditors.swift (save, autoCreateParentBudgetIfNeeded, deleteBudget, archiveBudget), PlanningSupport.swift (refreshCategorySnapshot), contracts/schema/cloud-entities.json.

## Global constraints
- All cloud write gates remain false. No production request, migration or deployment.
- Signed Long money/version values; explicit nullable payload keys.
- Owner-scoped dependencies, local records and outbox.
- Preserve current HEAD (82a9313) and user changes; commit each verified slice.
- Shared xcstrings is the sole static copy source.

## Review focus
- Stale/foreign IDs cannot become a new mutation under another owner.
- Month boundaries use the local zone, including Tokyo UTC midnight offsets.
- Carried-forward edits preserve the historical source and its remote base version.
- Parent auto-creation rejects overflowing totals without partial persistence.
- Family scope is monotonic on save; deleting the final current-month branch budget clears its category scope atomically. New family enablement requires the later refreshed family flow.

## Slice 1: offline budget repository
Files: core/model/BudgetMutations.kt, core/model/Contracts.kt, core/database/BudgetRepository.kt, core/database/Repositories.kt, core/database/MistiaDatabase.kt; JVM BudgetRepositoryTest and instrumented BudgetRoomTest.
Interfaces: FinanceRepository extends BudgetRepository with observeBudgets, saveBudget(owner, draft, device, now), archiveBudget(owner, id, device, now), deleteBudget(owner, id, device, now). LocalStore.commitMutations(List<Pair<CloudRecord, PendingMutation>>) is one atomic transaction.
- [x] Write failing repository tests for scope, frozen snapshots, coalescing/base version, duplicate/amount/branch guards, past read-only, carry-forward creation, auto-parent and archive/delete.
- [x] Run focused JVM test and record expected missing-interface RED.
- [x] Implement BudgetDraft, mutation generation, repository and Room atomic batch.
- [x] Run focused tests GREEN and Room source compilation.
- [x] Review against Swift; add regressions for overflow and failed batch rollback.
- [x] Run full Android unit/lint/assemble, contract and both localization checks; focused Swift if toolchain supports it; git diff --check; adb devices -l.
- [x] Update progress/evidence, include APK checksum and exact verification boundaries, commit slice.

## Continuation
After this commit, immediately implement budget push (separate default-false gate, shared outbox coordinator and transport tests), then native planning budget projection/editor. Continue savings, recurring bills, installments, statements, due maintenance/notifications, APK3 family workflows and APK4 resale workflows in dependency-bounded slices. Consult current iOS behavior before every slice; do not promote a physical-device gate based on local checks.
