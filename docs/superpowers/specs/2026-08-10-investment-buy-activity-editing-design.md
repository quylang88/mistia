# Investment Buy Activity Editing Design

**Date:** 2026-08-10

## Goal

Allow an existing investment buy activity to be corrected completely without replacing its identity. The user can change the asset, quantity, total order amount, purchase date, funding wallet, and note. The activity remains a buy and cannot be changed into a sell.

## Confirmed Product Semantics

- An edited activity keeps the same trade ID and remains a buy.
- The editable business fields are asset, quantity, total order amount, purchase date, funding wallet, and note.
- Buy / Sell kind is immutable after creation.
- The amount is the total paid for the order. Unit cost remains derived as:

  `total order amount / quantity`

- Changing the asset moves the existing trade to the selected asset. It does not delete the old trade and create a new one.
- Changing the asset also changes the trade's channel to the selected asset's channel.
- The change must reconcile the position and remaining cost basis of both the old asset and the new asset.
- Changing the wallet or total amount must reverse the old funding effect and apply the new funding effect through the existing derived-ledger reconciliation.
- Local and cloud persistence must be atomic. A failed edit leaves the original trade, asset positions, and wallet balances unchanged.

## User Interface

The existing trade editor remains the single entry point for creating and editing investment trades.

When editing an existing buy, the form allows changes to:

- Asset.
- Quantity.
- Total order amount.
- Purchase date.
- Funding wallet.
- Note.

The form presents the trade kind as a fixed `Buy` value. It must not provide an enabled control that can change the trade to a sell. Unit cost is a read-only derived value and is never accepted as an independent input.

Save remains unavailable when quantity or total order amount is not positive. The existing wallet, currency, permission, and exchange-rate validation continues to run at the shared persistence boundary so every calling surface gets the same result.

## Local Persistence Design

`InvestmentPersistenceService.saveTrade` remains the shared local write boundary. For an update it first loads the stored trade and captures its original asset, channel, kind, and funding relation before applying the draft.

The service enforces these invariants:

- An existing trade cannot change between buy and sell.
- Ownership remains immutable.
- The target asset exists, is eligible for the current user, and determines the target channel.
- The selected funding wallet is valid and can cover the edited total amount after the original trade's wallet effect is excluded.
- Quantity, total amount, currency conversion, and accounting inputs are valid.

Before mutating stored models, the service prepares and validates recalculation inputs for every affected asset:

- If the asset is unchanged, rebuild that asset once using the edited trade.
- If the asset changes, rebuild the old asset without the moved trade and rebuild the new asset with the edited trade.

Only after both calculations succeed does the service update the existing trade and reconcile affected trade snapshots, derived investment ledger entries, asset summaries, and wallet balances in one SwiftData save. The trade ID remains stable, and the normal update timestamp, sync version, and outbox behavior are preserved.

## Cloud Persistence Design

A forward-only Supabase migration replaces `mutate_investment_trade` without changing its public signature or adding schema columns.

The RPC will:

1. Load the existing trade and enforce the current owner, permission, and expected-version checks.
2. Reject an attempt to change the trade kind.
3. Validate the target asset, its channel, currency inputs, and funding wallet.
4. Serialize rebuilds for the old and new asset in a deterministic lock order when they differ.
5. Update the same trade row with the submitted editable fields.
6. Rebuild the old asset without the moved trade and the new asset with it, or rebuild once when the asset is unchanged.
7. Reconcile derived investment ledger rows and wallet postings inside the same database transaction.

Any validation or rebuild failure rolls back the RPC. Existing RLS, family permissions, ownership rules, grants, and sync-conflict semantics remain unchanged.

## Data Flow

1. The editor hydrates all editable fields from the stored buy activity.
2. The user changes any combination of asset, quantity, total amount, date, wallet, and note.
3. Saving submits one update draft with the original trade ID and fixed buy kind.
4. Local persistence preflights both affected asset calculations, applies the edit atomically, and records the normal sync mutation.
5. Supabase applies the same invariants and dual-asset rebuild when the outbox mutation is uploaded.
6. A remote version conflict is surfaced through the existing conflict flow rather than silently overwriting newer data.

## Error Handling

- Invalid quantity or total amount keeps Save disabled.
- An unavailable asset or wallet, insufficient wallet funds, missing exchange rate, invalid permission, or accounting failure surfaces through the existing localized investment error path.
- A stale remote version returns the existing conflict response.
- No partial wallet reversal, wallet debit, position rebuild, or trade update is accepted locally or remotely.
- If the target asset equals the original asset, the implementation must not rebuild or post the trade twice.

## Verification

Add red-green regression coverage for these scenarios:

1. Edit quantity, total order amount, date, wallet, and note while keeping the same asset; assert the same ID and fixed buy kind.
2. Move a buy from asset A to asset B and from wallet A to wallet B; assert that asset A no longer contains the trade's quantity or cost, asset B contains the edited quantity and cost, wallet A is restored, and wallet B is debited by the edited total.
3. Move a buy across channels by selecting an asset in another channel; assert that the trade relation and both positions are rebuilt correctly.
4. Reject a buy-to-sell change at both the local persistence boundary and the Supabase RPC.
5. Reject an edit when the target wallet cannot fund the edited order, leaving the original trade and all balances unchanged.
6. Reject a stale expected version without partial changes.
7. Exercise the same-asset path to prove that derived ledger rows are reconciled once rather than duplicated.
8. Exercise the Supabase RPC with pgTAP to prove both affected asset snapshots and wallet postings are correct after a move.

Run focused investment persistence tests first, then the full Swift test suite, Supabase pgTAP tests, and a generic iOS app build. Reverify the deployed Supabase function and database tests before making a production-readiness claim.

## Out of Scope

- Changing an existing buy into a sell or a sell into a buy.
- Editing or replacing ownership.
- Changing the investment accounting method.
- Adding an audit-log or compensating-trade user interface.
- Adding new database columns or migrating existing trade rows.
