# Investment Screen Redesign Design

**Date:** 2026-08-10

## Goal

Make the Investment feature asset-centric and easy to scan. A user creates an empty asset, records each buy using the quantity and the total amount paid for that order, then sees the current quantity, remaining capital, and weighted-average unit cost for the position.

## Confirmed Product Semantics

- A new asset starts with zero quantity and zero capital.
- The Add Asset form contains only channel, asset name, and currency.
- Symbol, opening quantity, and opening capital are removed from the form.
- A buy amount is the total amount paid for the whole order, not a per-unit amount.
- Example: quantity `3` and total paid `120` produces a unit cost of `40` and position capital of `120`.
- After multiple buys, the displayed unit cost is the weighted-average cost of the open position:

  `remaining position cost basis / current position quantity`

- A partial sale releases cost using the existing weighted-average accounting engine, so the remaining position keeps the correct average unit cost.
- A sell amount remains the total proceeds received for the sale.
- Fees are removed from all new and edited trade UI. New trades use zero fees.
- Stored historical fees remain in the data model and continue to affect historical balances and profit/loss. Editing an old trade preserves its stored fee rather than silently rewriting history.

## Compatibility Strategy

The existing `InvestmentAsset` opening fields and `InvestmentTrade` fee fields remain in the persistence and sync models. Removing them would require a destructive local and Supabase migration and could change existing accounting history.

New assets explicitly persist `openingQuantity = 0` and `openingCostMinor = 0`. New trades explicitly persist zero fee values. Existing records retain their stored values. This design does not require a Supabase schema or RLS change.

## Screen Structure

The approved direction is the compact overview layout (visual option A).

### Period Control

- Replace Day / Month / All Time with Month / All Time.
- Month is selected by default.
- The selected month initially points to the current calendar month.
- Month mode shows previous and next month navigation around a localized month-and-year label.
- The selected month filters trade history and realized profit/loss.
- All Time shows all trade history and all realized profit/loss.
- Current holdings, current remaining capital, current market value, and unrealized profit/loss always describe the current portfolio. They do not pretend to be historical month-end snapshots.

### Portfolio Summary

Replace the current five-card grid and realized-profit chart with one compact summary card:

- Primary value: capital currently held in open positions.
- Secondary value: current market value.
- Secondary value: unrealized profit/loss.
- Realized profit/loss for the selected period appears as a compact supporting metric when nonzero.
- Investment wallet access remains available from an overflow or supporting action instead of occupying a full-width metric card.

The chart is removed. Its information density does not help the primary task of understanding quantity, capital, and average unit cost.

### Asset List

Each active asset row shows:

- Asset name.
- Current quantity.
- Weighted-average unit cost.
- Remaining capital held in the position.
- Current market value when a valuation exists.
- Unrealized profit/loss when a valuation exists.

When quantity is zero, the row does not divide by zero and displays no average unit cost. Tapping a row retains the current valuation action. Edit, valuation maintenance, and archive actions remain available through the context menu.

### Primary Actions

- A compact Buy action opens the existing buy editor.
- A compact Sell action opens the existing sell editor and remains disabled when no positive position exists.
- The navigation-bar plus button adds an asset directly when channels already exist.
- Channel creation/management, channel filtering, the investment wallet, and archived items move to an overflow menu or appear only when relevant.
- If more than one active channel exists, channel filtering is available without permanently consuming horizontal screen space.
- Existing family view/create/edit permission behavior remains unchanged.

### Activity

- Activity is filtered by the selected month in Month mode and is unfiltered in All Time mode.
- Each row shows asset, date, quantity, and total order amount.
- Sell rows continue to show realized profit/loss.
- Empty selected months show a compact empty state instead of hiding the whole portfolio.

## Editors

### Add Asset

The editor contains:

- Channel.
- Asset name.
- Currency.

The editor no longer contains symbol, opening quantity, or opening capital. Editing an existing asset continues to protect channel and currency when the asset has history.

### Buy and Sell

The trade editor contains:

- Asset.
- Buy / Sell kind for a new trade.
- Quantity.
- Total order amount.
- Date.
- Note.
- Funding wallet for buys or capital-return wallet for sells.

The amount label must make total-order semantics explicit in Vietnamese, English, and Japanese. The fee field is absent.

## Calculation and Validation

The persistence boundary continues to receive total gross amounts. The amount must not be multiplied by quantity before wallet validation, currency conversion, ledger posting, or accounting recalculation.

Validation rules remain:

- Quantity must be greater than zero.
- Total order amount must be greater than zero.
- A sale cannot exceed the available quantity.
- The selected funding wallet must cover the total buy amount.
- Currency conversion applies to the total order amount.
- A zero-quantity position does not calculate an average unit cost.

Average unit cost is a derived presentation value and is not stored. It is calculated from the accounting engine's current position quantity and remaining cost basis, preventing duplicated or stale state.

## Implementation Boundaries

- Keep `InvestmentPersistenceService` as the shared write boundary.
- Add a small pure core-logic helper or snapshot property for average unit cost so its rounding and zero-quantity behavior are unit tested.
- Add a pure period-selection helper for current-month defaulting and selected-month intervals.
- Refactor the main SwiftUI screen into focused summary, period control, asset row, and activity components while preserving existing editor and permission behavior.
- Keep String Catalog as the source of truth and regenerate `L10n.generated.swift` through the existing Mistia localization workflow.

## Error Handling

- Existing localized persistence errors remain the single source for invalid wallet, insufficient funds, missing exchange rate, and invalid trade input failures.
- Invalid quantity or total amount keeps Save disabled.
- A missing exchange rate surfaces the existing localized alert.
- Historical fees are preserved on edit even though the fee input is no longer shown.
- Month navigation never changes or rewrites stored data.

## Verification

Add red-green regressions that prove:

1. Buying quantity `3` for total `120` produces position capital `120`, average unit cost `40`, and a wallet debit of `120`.
2. Multiple buys at different totals produce the correct weighted-average unit cost.
3. A partial sale retains the correct average unit cost for the remaining position.
4. New assets start with zero opening quantity and zero opening capital.
5. New trades persist zero fees, while editing a legacy trade preserves its stored fee.
6. Month mode defaults to the current month and constructs the interval for the selected month rather than the device's current month.
7. Month filtering affects activity and realized profit/loss, while current position metrics remain current.

Run the focused core-logic and persistence tests first, then the full Swift Package test suite and a generic iOS app build. Perform a simulator-sized visual check of the redesigned screen if the local simulator environment is available.

## Out of Scope

- Reconstructing historical month-end portfolio positions.
- Removing legacy opening or fee columns from SwiftData or Supabase.
- Changing investment family permissions, sync routing, RLS, or notification behavior.
- Changing the weighted-average accounting method.
