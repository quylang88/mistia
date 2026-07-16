# Member Permission Instant Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every member-context permission request acknowledge taps immediately while preserving remote correctness and preventing duplicate submissions.

**Architecture:** Reserve the exact permission-request key in `FamilyContextStore` before any suspension, coalesce duplicates, and roll back provisional state on failure. Permission surfaces present cached or in-flight state synchronously and perform RPC/approval reconciliation in background tasks.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, Apple String Catalog

## Global Constraints

- Do not change Supabase RPCs, RLS policies, notification delivery, or permission semantics.
- All new user-facing copy must use English dotted String Catalog keys with `vi`, `en`, and `ja` values.
- A tap must update visible local state before remote session or RPC work completes.
- Duplicate requests are keyed by owner user ID, resource type, optional resource ID, and scope.
- Failed optimistic submissions must be retryable.

---

### Task 1: Optimistic, idempotent permission submission

**Files:**
- Modify: `Mistia/Shared/Family/FamilyContextStore.swift`
- Test: `MistiaTests/SessionStoreOfflineTests.swift`

**Interfaces:**
- Consumes: `FamilyPendingPermissionRequestKey`, `pendingPermissionRequestKeys`, `pendingPermissionRequests`, and `FamilyRemoteServicing.createFamilyPermissionRequest`.
- Produces: unchanged `requestPermission(...) async -> Bool` API with pre-suspension pending reservation, duplicate coalescing, and failure rollback.

- [ ] **Step 1: Write delayed-service regression tests**

Add tests that start `requestPermission(...)` in a task, yield while the service is suspended, and assert local pending state is already true. Submit the same key again and assert `createPermissionRequestCallCount == 1`. Add a failure test asserting the pending key is removed after the task returns false.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project Mistia.xcodeproj -scheme Mistia -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:MistiaTests/SessionStoreOfflineTests
```

Expected: the new immediate-pending and duplicate-coalescing assertions fail against the current post-RPC update.

- [ ] **Step 3: Implement the minimal store behavior**

In `requestPermission(...)`, compute the key and return true for an existing pending request. Insert the provisional key before `prepareRemoteSession`. On every pre-RPC or RPC failure, remove it only if no stored pending request record maps to that key. Preserve the existing upsert, cache persistence, and visible error behavior on success/failure.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Task 1 command again. Expected: all `SessionStoreOfflineTests` pass.

### Task 2: Immediate UI presentation and background approval refresh

**Files:**
- Modify: `Mistia/Features/Overview/OverviewView.swift`
- Modify: `Mistia/Features/Planning/PlanningView.swift`
- Modify: `Mistia/Features/Management/ManagementView.swift`
- Modify: `Mistia/Features/Transactions/TransactionsView.swift`
- Modify: `Mistia/Features/Transactions/TransactionEditorSheet.swift`
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift`
- Modify: `Mistia/Localizable.xcstrings`
- Generate: `Mistia/Shared/CoreLogic/L10n.generated.swift`
- Test: `MistiaTests/FamilyPermissionResolutionTests.swift`

**Interfaces:**
- Consumes: optimistic `FamilyContextStore.requestPermission(...)` and existing `resolvePendingPermissionBeforePrompt(...)`.
- Produces: synchronous cached-pending presentation, immediate in-flight alerts, and background result/reconciliation updates on every permission surface.

- [ ] **Step 1: Add failing presentation contract tests**

Add source-contract assertions for all six feature files: cached pending state must be assigned to the relevant prompt/alert before the task awaits remote resolution, and submission handlers must assign localized sending feedback before awaiting `requestPermission(...)`.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project Mistia.xcodeproj -scheme Mistia -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:MistiaTests/FamilyPermissionResolutionTests
```

Expected: source-contract tests fail because current pending branches and submission handlers await first.

- [ ] **Step 3: Add localized in-flight copy and generate L10n**

Add `shared.family.permissionRequest.sendingTitle` and `shared.family.permissionRequest.sendingMessage` with all three locales, then run:

```bash
swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift
```

- [ ] **Step 4: Move network work behind immediate UI state**

Across all listed feature files, show cached pending prompts/info synchronously and start approval refresh afterward. In each new-request handler, clear the permission prompt, assign the localized sending alert/message, then await `requestPermission(...)` and replace it with the existing success/failure result.

- [ ] **Step 5: Run focused permission tests and verify GREEN**

Run both focused test classes. Expected: all permission submission and resolution tests pass.

### Task 3: Full verification and commit

**Files:**
- Verify all modified files.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: a verified commit on the active `develop` branch.

- [ ] **Step 1: Run localization validation**

```bash
/Users/quylang/.codex/skills/mistia-string-catalog-l10n/scripts/check_mistia_l10n.sh
swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift --strict-keys --check
```

- [ ] **Step 2: Run full build and relevant tests**

```bash
xcodebuild -project Mistia.xcodeproj -scheme Mistia -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project Mistia.xcodeproj -scheme Mistia -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:MistiaTests/SessionStoreOfflineTests -only-testing:MistiaTests/FamilyPermissionResolutionTests
```

- [ ] **Step 3: Review repository hygiene**

```bash
git diff --check
git status --short
git diff --stat
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-16-member-permission-instant-feedback-design.md docs/superpowers/plans/2026-07-16-member-permission-instant-feedback.md Mistia/Shared/Family/FamilyContextStore.swift Mistia/Features/Overview/OverviewView.swift Mistia/Features/Planning/PlanningView.swift Mistia/Features/Management/ManagementView.swift Mistia/Features/Transactions/TransactionsView.swift Mistia/Features/Transactions/TransactionEditorSheet.swift Mistia/Features/Transactions/SettlementSheets.swift Mistia/Localizable.xcstrings Mistia/Shared/CoreLogic/L10n.generated.swift MistiaTests/SessionStoreOfflineTests.swift MistiaTests/FamilyPermissionResolutionTests.swift
git commit -m "fix: speed up member permission feedback"
```
