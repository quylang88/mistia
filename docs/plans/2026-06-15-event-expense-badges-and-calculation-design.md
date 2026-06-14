# Design: Event Expense Badges & Calculations

## Problem Statement
When a transaction is linked to a split-expense event, its actual cost to the user is the split share (`reportingExpenseMinor`), not the raw transaction amount (`amountMinor`). The application's Overview, Family Overview, and Budget progress calculations need to use the actual split amount. Additionally, transactions linked to an event should display a neat native Apple-style badge in lists and inside the transaction editor.

## Proposed Design

### 1. Reusable Badge Component
We will introduce `MistiaMiniBadge` as a generic capsule badge with glassmorphism style in `MistiaReusableListComponents.swift`. It accepts a title and a tint color, rendering beautifully on both light and dark themes.

### 2. Transaction Lists Badge Integration
- **Transactions Screen**: In `TransactionCashflowRow` (`TransactionsView.swift`), if `record.settlementGroupID != nil`, display a teal `MistiaMiniBadge` with the title "Sự kiện" (L10n.transactions.settlement.eventTitle).
- **Overview Screen**: In `OverviewDayTransactionRow` (`OverviewView.swift`), display the same teal badge next to the transaction title if `transaction.settlementGroupID != nil`.

### 3. Transaction Details Modal Integration
In `TransactionEditorSheet.swift`:
- Fetch all active `SettlementGroup`s using a SwiftData Query.
- If the current transaction is linked (`settlementGroupID != nil`), find the corresponding event and display a form row showing the event title inside a teal badge.

### 4. Calculation Alignment
In `PlanningLogic.swift` (personal/family budget calculations):
- Update `PlanningBudgetSpendingIndex.init` for family transactions to filter for transactions where their reported expense amount (via `reportedExpenseAmount`) is non-zero.
- Update `familySpentForCategoryName` to aggregate using the actual split share (`reportingExpenseMinor` if present) instead of raw `amountMinor`.
