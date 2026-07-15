# Credit Card Available Credit Source of Truth

## Problem

Mistia currently derives credit-card available credit through two different paths. The Management UI can show a value derived from unpaid statement data, while transaction validation derives debt from the wallet opening balance and posted transaction deltas. After a credit-limit edit, the displayed available credit can therefore be greater than the amount accepted by the transaction editor.

## Desired behavior

- Available credit is always `latest credit limit - current debt`, clamped to zero.
- Current debt includes the wallet opening debt and every posted, active transaction delta, including credit-card payments.
- Changing only the credit limit must not change current debt.
- An expense equal to the displayed available credit is valid; only a larger amount is rejected.
- Statement calculations remain responsible for statement state and amount due, not the card's spendable balance.

## Design

Add a small pure calculation surface in `TransactionLogic` that accepts the latest credit limit, a wallet snapshot, and the existing wallet-balance index. It returns current debt and available credit from the same ledger balance already used by transaction validation.

Use this calculation everywhere in the affected flow:

- Management wallet rows and wallet editor balance snapshots.
- Planning credit-card rows/editor snapshots that show or edit the current limit and available credit.
- Transaction editor validation for ordinary expenses and credit-card-backed debt flows.
- Shared payment validation where credit-card available credit is checked.

When an existing card is saved after a limit edit, preserve its effective current debt. If the editor must derive a new opening balance from an explicitly entered available-credit value, subtract the posted transaction delta from the target debt using the same ledger calculation. This prevents a limit-only change from silently rewriting debt.

## Error handling

Keep the existing localized over-limit alert. Missing credit-card profile data continues to provide zero available credit and reject spending safely. No String Catalog changes are required.

## Testing

Follow red-green TDD with focused pure-logic regressions:

1. A card with opening debt and posted activity reports the same available credit used by validation.
2. Raising the limit changes available credit by the same delta while preserving current debt.
3. An amount equal to the new available credit passes; an amount one minor unit higher fails.
4. Existing wallet-balance and Planning logic tests continue to pass.

Run the focused tests first, then the relevant Swift package suite, localization check only if localized files unexpectedly change, `git diff --check`, and a generic unsigned iOS build.

## Scope

This change does not alter statement closing, due-date, payment-occurrence, sync, or localization behavior. It only establishes a single source of truth for current credit-card debt and spendable available credit.
