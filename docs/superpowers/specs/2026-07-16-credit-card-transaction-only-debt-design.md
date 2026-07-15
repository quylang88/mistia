# Credit Card Transaction-Only Debt

## Problem

Mistia currently models a credit card's current debt as a generic wallet opening balance plus posted transaction deltas. The card creation flows expose an editable available-credit field, convert that value into an opening debt, and persist it in `LedgerWallet.openingBalanceMinor`. Editing a card can rewrite that opening debt again.

This creates debt that is not represented by a transaction and therefore has no normal payment lifecycle. A real card observed on device has a stale opening value of 46,058 and active transaction debt of 25,916, so the Family UI reports 71,974 even though the transaction-backed debt is only 25,916. The same generic opening value also affects local wallet reducers and the Supabase current-balance snapshot.

## Required behavior

- Credit-card debt is created and reduced only by active, posted transactions.
- An expense or other debt-producing transaction against the card increases debt.
- A real internal-transfer payment into the card reduces debt.
- Statement status remains payment-authoritative: a statement becomes paid only when a valid payment transaction proves it.
- Current card debt is the posted transaction delta total, clamped to zero for display and spendable-credit calculations.
- Available credit is derived as `max(credit limit - current debt, 0)` and is never an editable source of debt.
- Creating or editing a credit card never reads or writes a card opening debt.
- Cash, bank, and other non-card wallets retain their existing opening-balance behavior.
- Owner and family-member views use the same transaction-only card balance rule.

## Domain design

### Remove the card opening-debt concept

Delete the card-specific helper that derives `openingBalanceMinor` from an entered available-credit value. Credit-card balance calculation must seed the wallet balance at zero, regardless of any generic opening value stored on the wallet row. The same conditional seed applies to both the direct effective-balance reducer and the indexed balance reducer so all consumers receive the same result.

`LedgerWallet.openingBalanceMinor` remains in the shared wallet persistence model because it is still the opening balance for cash, bank, and other non-card wallets. It is not a credit-card field semantically. Existing credit-card values are not reset to zero or bulk-rewritten; they become inert because no credit-card calculation, editor, report, or cloud snapshot reads them as debt.

Any fallback that returns a wallet's generic opening balance must also honor the wallet kind. A missing indexed card balance falls back to zero, while a missing non-card balance continues to fall back to its opening balance.

### Transaction semantics

The existing transaction delta rules remain authoritative:

- Posted active expenses sourced from a credit card increase card debt.
- Posted active internal transfers whose destination is the credit card reduce card debt.
- Draft, archived, or deleted transactions do not affect debt.
- An overpayment cannot produce negative displayed debt; debt clamps to zero and available credit does not exceed the configured limit.

No synthetic adjustment transaction is created to replace removed opening debt. If an existing card has historical debt that the user wants Mistia to track, the user must enter the corresponding real card transaction.

## UI and persistence design

### Management wallet editor

- Remove the editable available-credit input for new credit cards.
- Retain the ordinary opening-balance input only for non-card wallet kinds.
- Remove available-credit state and conversion logic from the wallet draft.
- Saving a new card uses the shared model's default storage value without presenting or deriving card opening debt.
- Saving an existing card updates card metadata and its profile but does not assign `openingBalanceMinor`.
- Remove card-specific branches from the balance-adjustment sheet. Credit cards remain ineligible for generic balance adjustment; repayment must be a real transfer transaction into the card.
- Keep calculated available credit in read-only wallet summaries and transaction validation.

### Planning credit-card editor

- Remove the editable/disabled available-credit field and its draft state.
- Remove limit-change and task hooks whose only purpose is to rewrite that draft field.
- Saving a card updates its profile and limit but never derives or assigns opening debt.
- A new card starts with no transaction-backed debt because it has no card transactions yet.
- Do not initialize payment amount or statement amount from available credit. Payment amounts continue to come from an actual due item or statement transaction data.
- Remove editor-only due snapshot code that reconstructs debt from limit minus the editable available value when it has no remaining consumer.

### User-facing text

No new copy is required. If removing the inputs leaves String Catalog keys unused, remove only the dead keys from `Mistia/Localizable.xcstrings` and regenerate `Mistia/Shared/CoreLogic/L10n.generated.swift` through the existing localization pipeline. Keys still used for read-only available-credit displays remain.

## Family and reporting behavior

Family aggregation already derives card debt from wallet balance snapshots. Once the shared reducers seed cards at zero, both owner and member views calculate the same transaction-only debt. The implementation must also audit direct opening-balance fallbacks and exported wallet summaries so a stale generic card opening value cannot reappear when an index entry is missing or in a statement/report column.

Read-only available-credit displays remain useful and continue to show the latest limit minus transaction-backed debt. This change removes editable available credit, not the calculated value.

## Supabase design

Create a new migration that replaces `mistia_calculate_wallet_current_balance` without changing its public signature or grants. For a credit card, the raw debt seed is zero plus active posted transaction deltas. For other wallet kinds, the raw balance remains `p_opening_balance_minor` plus transaction deltas.

After replacing the function, recalculate `ledger_wallets.current_balance_minor` for existing wallets through the same function. Credit-card snapshots will therefore become available credit derived from the limit and transaction-backed debt. The migration must not reset, null, or otherwise rewrite `ledger_wallets.opening_balance_minor`; the column remains shared infrastructure for non-card wallets.

The existing transaction/profile triggers continue to refresh snapshots. No RLS or family-permission changes are required.

## Error and edge-case handling

- A card with a stale nonzero generic opening value and no active transactions has zero debt and its full configured limit available.
- A card whose payment exceeds active debt has zero displayed debt and full configured limit available.
- A card without a profile has zero available credit under the existing safe behavior.
- Changing only the credit limit changes available credit but never changes debt.
- Changing a wallet kind to credit card immediately makes its generic opening value inert. Changing away from credit card restores the normal non-card interpretation of the shared opening field; no destructive data rewrite occurs during kind changes.
- Existing synced card rows may continue carrying an old generic opening value, but that value must not affect local or cloud card results.

## Testing

Follow red-green TDD with focused regressions:

1. A credit-card snapshot with stale opening value 46,058 and active transaction debt 25,916 reports debt 25,916, not 71,974.
2. A card with a nonzero stored opening value and no transactions reports zero debt and full available credit.
3. Purchases increase debt and real internal-transfer payments reduce it; deleted, archived, and draft transactions remain excluded.
4. Cash and bank snapshots continue including their opening balances.
5. A missing balance-index entry falls back to zero for a card and to opening balance for a non-card wallet.
6. Limit-only edits change available credit without changing transaction-backed debt.
7. Management and Planning creation/edit persistence do not derive or rewrite card opening debt.
8. Family aggregation reports the same card debt for the owner and a viewing family member.
9. The Supabase calculator ignores opening balance for cards, preserves it for non-card wallets, and the backfill produces the expected available-credit snapshot.
10. Existing payment-authoritative statement tests continue proving that only a real payment transaction can mark a statement paid.

Run focused core-logic and app-target tests first, then the relevant Swift package suite, strict localization checks when catalog files change, SQL lint/diff verification for the migration, `git diff --check`, and an unsigned generic iOS build.

## Rollout

This is a semantic migration, not a destructive data cleanup. The app release and Supabase migration must ship together so local owner/member calculations and cloud family snapshots agree. Existing card opening values remain stored but are unreachable from card behavior. A rollback to older app code would read those stale values again, so rollback must also restore the prior cloud calculator or ship a forward fix rather than partially reverting one side.

## Out of scope

- Removing `openingBalanceMinor` from the shared wallet schema or from non-card wallet types.
- Resetting existing card opening values to zero.
- Creating synthetic transactions for historical opening debt.
- Changing statement closing, due-date, partial-payment, payment matching, ownership, or RLS rules.
- Removing calculated available-credit displays.
