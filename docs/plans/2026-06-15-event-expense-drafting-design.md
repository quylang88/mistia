# Event Expense Drafting and Unlinking Design

This design document outlines the changes required to draft expense linking/unlinking inside the Event (Shared Expense) editor modal, saving changes to the database only when the user explicitly clicks the "checkmark" (Save) button.

## Requirements

1. **In-Memory Drafting**: Any addition, link, deletion, or unlinking of expenses in the Event editor modal must be performed in memory first.
2. **Atomic Saving**: Database persistence, model saves, and sync mutation queuing should only happen when the user clicks the checkmark (Save) button.
3. **No Unsaved Changes on Cancel**: Clicking Cancel or dismissing the modal should discard all staged linking and unlinking edits without leaving any side effects in the local SQLite database or syncing partial modifications to Supabase.
4. **Correct Dismissal Warning**: The dismiss guard must warn the user of unsaved changes if they add or remove expense links and attempt to dismiss without saving.

## Design

### Approach

We will track the linked transaction IDs in memory using `@State` properties:
- `initialLinkedBillIDs: Set<UUID>`: Tracks the bill IDs that were linked in the database when the sheet opened.
- `currentLinkedBillIDs: Set<UUID>`: Tracks the bill IDs that are currently linked in the editor session (starts identical to `initialLinkedBillIDs`).

When an expense is unlinked (via swiping to delete an existing linked bill):
- We simply remove its ID from `currentLinkedBillIDs`. No database updates or sync operations are performed.

When the user clicks the checkmark (Save):
1. **Identify Detached Bills**: `let detachedBillIDs = initialLinkedBillIDs.subtracting(currentLinkedBillIDs)`.
2. **Detach in Database**: For each detached bill, clear its `settlementGroupID`, `settlementRoleRawValue`, etc., and record ownership.
3. **Handle Newly Added Bills**: Process `billRows` (created or attached existing bills) as before.
4. **Recalculate Group Total**: Calculate the group total by summing the amount of all currently linked bills (both the original ones still in `currentLinkedBillIDs` and the newly added ones).
5. **Persist Atomic Update**: Save all modified transactions (created, attached, and detached) and the group together using `persistPreparedSharedExpense`.

If the user discards changes:
- No database update occurs. The dismiss guard works automatically because `sharedExpenseDismissalSnapshot.linkedBillIDs` derives from `currentLinkedBillIDs`, causing a mismatch when comparing with the baseline snapshot.

## Proposed Code Changes

### [SettlementSheets.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/SettlementSheets.swift)

- Add state variables:
  ```swift
  @State private var currentLinkedBillIDs: Set<UUID> = []
  @State private var initialLinkedBillIDs: Set<UUID> = []
  ```
- Update `loadSharedExpenseDraftIfNeeded()` to initialize both state variables.
- Update the computed property `linkedSharedExpenseBills` to filter using `currentLinkedBillIDs` instead of querying the database directly.
- Add `detachBillDraft(_ bill: LedgerTransaction)` which removes the bill ID from `currentLinkedBillIDs`.
- Update the swipe action on existing linked bills to call `detachBillDraft(bill)` instead of `detachBill(bill)`.
- Update `saveSharedExpense()` to calculate `detachedBills`, clear their settlement properties, sum the total from all currently active linked bills, and pass the combined list to `persistPreparedSharedExpense`.
