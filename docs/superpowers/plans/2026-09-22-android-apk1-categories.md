# Android APK 1 Category Slice Implementation Plan

**Goal:** Replace the category count placeholder with account-scoped offline category hierarchy management matching the iOS create/edit/favorite/archive workflow.

**Architecture:** Add a typed category contract and draft validator in `core:model`; extend the offline finance repository with category operations over the existing atomic record+outbox boundary; render expense/income parent cards and a Compose editor in `feature:management`. Category cloud push remains a later domain-gated slice.

## Acceptance criteria

- All `transaction_categories` contract fields round-trip, including explicit null translations/parent/system fields and preserved system metadata.
- Create/edit rejects blank or normalized duplicate names; children require an active same-kind parent; parents can never be favorite.
- Existing category hierarchy role is immutable in the editor, matching iOS. New categories may be parent or child; kind changes reset an incompatible parent and update an untouched default icon/color.
- Parent/child sorting matches iOS (`sort_order`, then `created_at`). Favorite toggle is child-only.
- Archive is an upsert and is blocked by active children or active references from transactions, budgets, or recurring bills.
- Record and outbox writes remain atomic and owner-scoped. Category cloud writes stay disabled.

## Tasks

### 1. Typed contract and validation

- [x] Write failing model tests for round-trip fields, explicit nulls, hierarchy validation, default icon changes, and system metadata preservation.
- [x] Implement category record/draft/mutation models.
- [x] Run the model suite.

### 2. Offline repository and blockers

- [x] Write failing repository tests for owner isolation, duplicates, child-parent validation, favorite, archive blockers, and coalesced base version.
- [x] Implement category repository operations over the existing owner-scoped local flows and atomic mutation boundary; no additional broad snapshot API was needed.
- [x] Run database unit tests and compile Room instrumented tests.

### 3. iOS-parity management UI

- [x] Write editor-state tests.
- [x] Add expense/income hierarchy cards, favorite toggle, parent/child add/edit, canonical icon/color controls, archive confirmation and validation feedback.
- [x] Run feature tests, full Android checks, review against iOS, fix findings, update evidence and commit this slice separately.
