# Settlement Debt Row Editing Implementation Plan

**Goal:** Remove manual participant-share editing and allow users to edit each automatically generated debt amount directly, without changing expense reporting, debt direction, or permitting zero.

**Architecture:** Keep `SettlementLogic.sharedExpenseSettlement` as the sole source of participant shares and automatic debt directions. Apply positive amount overrides only to the generated settlement suggestions, keyed by payer and receiver, then persist those effective suggestions while retaining the automatic split result for reporting.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, String Catalog

---

## Task 1: Replace participant-share overrides with debt-amount overrides

**Files:**
- Modify: `Mistia/Shared/CoreLogic/TransactionLogic.swift`
- Modify: `Tests/MistiaCoreLogicTests/SettlementLogicTests.swift`
- Modify: `MistiaTests/TransactionLogicTests.swift`

1. Add failing tests proving a debt override changes only the matching suggestion.
2. Add failing tests proving payer/receiver direction and participant shares remain unchanged.
3. Add failing tests proving zero or negative overrides are rejected by core derivation.
4. Run focused tests and confirm they fail for the missing API.
5. Add a stable suggestion identifier based on payer and receiver.
6. Add an effective-suggestions helper that accepts only positive amount overrides.
7. Remove `shareOverrideMinor`, manual-share redistribution helpers, and their tests.
8. Run focused tests and confirm they pass.

## Task 2: Move inline editing to generated debt rows

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift`

1. Replace participant-share editing state with debt-row editing state keyed by suggestion identifier.
2. Keep the automatic split result unchanged for expense reporting.
3. Derive effective settlement suggestions by applying committed positive overrides.
4. Remove participant-share rows and the total-difference row.
5. Add edit/save controls beside each generated debt amount.
6. On edit, focus and select the full amount in the currency input.
7. Reject empty, invalid, or zero values without saving or changing direction.
8. Make `Chia lại chi phí` clear every debt override and restore automatic amounts.
9. Include debt edits in the unsaved-changes guard.

## Task 3: Persist effective debts and reconcile stale principal rows

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift`

1. Finalize using effective debt suggestions instead of automatic suggestion amounts.
2. Preserve `splitResult` participant shares when creating expense reporting records.
3. Match existing principal debt records by settlement group and counterparty.
4. Update amount, role, and intent to match each effective suggestion.
5. Archive stale principal debt records no longer represented by an effective suggestion.
6. Include updated and archived principal records in audit and sync operations.

## Task 4: Update localization

**Files:**
- Modify: `Mistia/Resources/Localizable.xcstrings`
- Modify: `Mistia/Generated/L10n.generated.swift`

1. Remove participant-share edit and total-difference strings.
2. Add debt edit and debt save accessibility labels in English, Japanese, and Vietnamese.
3. Reuse the existing greater-than-zero validation message.
4. Regenerate typed localization accessors.

## Task 5: Verify the complete flow

1. Run focused settlement logic tests.
2. Run localization validation/generation checks.
3. Run `git diff --check`.
4. Build the Mistia app target with code signing disabled.
5. Review the final diff for unrelated changes.
6. Commit the implementation in scoped commits.
