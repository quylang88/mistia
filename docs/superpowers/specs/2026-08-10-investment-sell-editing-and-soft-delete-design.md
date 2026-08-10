# Investment Sell Editing and Soft Delete Design

**Date:** 2026-08-10

## Goal

Allow an existing investment sell activity to be corrected completely without replacing its identity, and let users soft-delete either an existing buy or sell activity from the end of its editor. The trade kind remains fixed after creation.

## Confirmed Product Semantics

- Existing buys and sells keep their trade ID.
- The editable business fields for both kinds are asset, quantity, total order amount, date, wallet, and note.
- Buy / Sell kind is immutable after creation.
- The selected asset determines the selected trade's channel. Moving a trade does not create a replacement row.
- A moved sell must be valid against the quantity held by its new asset at the revised date. A sell that exceeds that quantity is rejected atomically.
- The total order amount remains the total for the order. Unit cost is derived and never independently editable.
- Delete means a soft delete: the trade and its derived accounting legs are marked deleted, disappear from active investment UI, and are synchronized to cloud. There is no restore UI.

## User Interface

`InvestmentTradeEditorSheet` remains the single editor for both new and existing investment trades.

For an existing buy or sell, asset, quantity, total order amount, date, wallet, and note remain editable. The asset picker is enabled for both kinds. The segmented Buy / Sell control stays disabled for every existing trade.

For every existing trade where the viewer has edit permission, the bottom of the form adds `MistiaDestructiveActionSection`, matching the existing cashflow archive treatment:

- A full-width red `Delete transaction` button.
- A short footer that explains the transaction is removed from active investment history.
- A native SwiftUI confirmation dialog with Cancel and destructive Delete actions.

The action does not appear for a new unsaved trade or a viewer without edit permission. A confirm deletes and dismisses the editor; a cancellation leaves the editor and draft unchanged. New localized strings are added through the String Catalog for the button, explanation, and confirmation message.

## Local Persistence Design

`InvestmentPersistenceService.saveTrade` already owns all asset-history rebuilds. It continues to enforce immutable owner and kind, determine the channel from the submitted asset, preflight every affected asset history, and persist once.

For an edited sell moved to a new asset, the same dual-asset rebuild path used for a buy applies:

1. Recalculate the old asset without the moved sell.
2. Recalculate the new asset with the revised sell.
3. Reject the save if that revised history would sell more than it holds.
4. Only then update the existing model, reconcile all changed positions, released cost, realized profit/loss, ledger transactions, and wallet postings, and save atomically.

`deleteTrade` remains the shared soft-delete boundary for both kinds. It marks the trade deleted, soft-deletes its derived ledger legs/postings, recalculates every remaining trade for the asset, and saves in one SwiftData transaction. The UI callback records the primary `investmentTrade` delete in the normal sync outbox; derived investment records remain owned by the investment RPC/rebuild path.

## Cloud Persistence Design

The existing `mutate_investment_trade` RPC already permits an asset move with immutable kind and rebuilds the old/new asset in one transaction. It requires no schema or function change for sell editing. The existing `delete_investment_trade` RPC already performs the required permission-checked soft delete and asset rebuild.

The implementation must add regression coverage for both RPC paths instead of creating redundant migrations. Existing RLS, `SECURITY DEFINER` hardening, ownership checks, family investment permission checks, optimistic versioning, and grants remain unchanged.

## Data Flow

1. The editor hydrates a stored buy or sell and leaves only the kind fixed.
2. The user may change all business fields, including the asset and its implied channel.
3. Saving calls the shared local persistence boundary with the same trade ID.
4. Local persistence validates and rebuilds the old/new histories, then records the normal upsert mutation.
5. The outbox uploads the mutation to `mutate_investment_trade`, which applies the corresponding transactional rebuild.
6. When deletion is confirmed, the editor calls back to the hub. The hub invokes `deleteTrade`, records a delete mutation, and dismisses the editor.
7. The outbox invokes `delete_investment_trade`; the remote trade and derived accounting become soft-deleted and the remote asset is rebuilt.

## Error Handling

- Save remains disabled for missing asset/wallet, non-positive quantity, or non-positive total amount.
- Existing local validation surfaces an invalid wallet, missing exchange rate, insufficient funds, or insufficient asset quantity through the established investment error path.
- Editing or deleting without edit permission remains unavailable in UI and rejected in persistence/cloud.
- A stale remote version follows the existing sync-conflict flow rather than overwriting data.
- A failed edit or delete cannot partially change a trade, wallet, ledger transaction, posting, position, cost basis, or profit/loss.

## Verification

Add red-green coverage for:

1. Moving an existing sell across assets/channels while changing quantity, total amount, date, capital-return wallet, and note; preserve trade ID and kind.
2. Rejecting a sell moved to an asset whose revised history cannot cover its quantity, with all original records unchanged.
3. Keeping kind immutable for sell-to-buy as well as buy-to-sell.
4. Soft-deleting a buy and soft-deleting a sell; verify deleted timestamp, reconciled remaining positions/cost basis, wallet balance, derived postings, and ledger rows.
5. The editor exposes editable asset selection for existing sells, fixed kind for existing buys/sells, and a destructive section only for an existing editable trade.
6. pgTAP coverage that the RPC accepts an edited sell relation move, rejects an oversell move atomically, and soft-deletes a sell through `delete_investment_trade`.

Run focused investment persistence tests, the full Swift package suite, full Supabase pgTAP suite, generic iOS build, then linked migration verification. No new migration should be pushed unless discovery shows the existing RPC behavior differs from the stated design.

## Out of Scope

- Restoring a deleted investment trade.
- Changing a buy into a sell or a sell into a buy.
- Permanently deleting user data from local storage or Supabase.
- Changing investment accounting method, permissions, or sync-conflict policy.
