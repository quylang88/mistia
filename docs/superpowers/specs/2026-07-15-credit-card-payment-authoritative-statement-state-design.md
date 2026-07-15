# Credit Card Payment-Authoritative Statement State

## Problem

Credit-card statement state and current ledger debt can disagree. `PlanningLogic` currently accepts a matching paid `DueOccurrenceRecord` as proof that a statement is paid even when the linked payment transaction has since been deleted. The wallet balance engine correctly ignores deleted transactions, so the statement remains visually paid while its charges remain in current debt.

Live Supabase inspection found 15 active paid credit-card occurrences. Eleven referenced active posted card-payment transfers. Four occurrences for one card and one statement month referenced four payment transfers that were later soft-deleted, but the occurrences remained paid.

A separate live payment for 44,298 proves that a family member can create a valid card payment on behalf of the card owner. That transaction is active, posted, and transfers into the card. Its finance ownership remains with the owner of the source wallet and card, while `created_by_user_id` identifies the member. The matching statement occurrence is pending and is not explicitly linked to the payment, so valid member-created payments must continue to be recognized through transaction matching.

## Required behavior

- A statement is paid only when an active, posted internal transfer into that card proves payment.
- The payment may be explicitly linked by `DueOccurrenceRecord.linkedTransactionID` or inferred from the destination card, covered statement amount, and payment timing after statement close.
- The actor who created the transfer may be a family member. Creator identity must not invalidate a payment when the transaction is authorized and owned by the relevant finance owner.
- A paid occurrence whose linked transaction is missing, deleted, archived, draft, the wrong transaction type, or directed to another wallet is not payment evidence.
- When no valid payment remains, the occurrence returns to pending and clears `paidAt` and `linkedTransactionID`.
- When an active inferred payment exists, maintenance marks the occurrence paid and links it to that transaction, including for manual payments and member-created payments when auto-pay is disabled.
- Current credit-card debt remains the ledger opening debt plus active posted transaction deltas. Occurrence state never creates an implicit balance adjustment.

## Design

### Pure payment resolution

Keep statement payment resolution in `PlanningLogic`. For each statement, build the existing ordered set of active posted internal transfers whose destination is the card. Resolve payment in this order:

1. If the occurrence has `linkedTransactionID`, accept that transaction only when it exists in the active candidate set, occurred on or after statement close, and covers the statement amount.
2. Otherwise, use the existing inferred-payment rule: the earliest active candidate on or after statement close whose destination amount or source amount covers the statement.
3. Set statement status to paid only when one of those transaction-backed resolutions succeeds. Expose only the resolved active transaction ID as `linkedTransactionID`.

This removes `DueOccurrenceRecord.status` as independent payment proof while preserving explicit links as the preferred match.

### Persistence reconciliation

Extend `MistiaCreditCardStatementMaintenance` to reconcile persisted occurrences from transaction-backed statement results before the auto-pay decision:

- If the statement resolves to an active payment, mark the occurrence paid and link the resolved transaction regardless of whether auto-pay is enabled.
- If the statement has no active payment but the occurrence is paid or still carries a link/payment date, reset it to pending and clear stale payment fields.
- Persist and queue an occurrence upsert only when reconciliation changes data.
- Continue auto-payment only after reconciliation and only when the statement remains unpaid.

This repairs legacy and synced inconsistencies on the existing maintenance path without inventing payment transactions or directly rewriting wallet balances.

### Family payment semantics

Payment validity depends on transaction state and wallet relationships, not on `created_by_user_id`. A member-created transfer is valid when it is an active posted internal transfer into the card and matches the statement amount/timing. Ownership and RLS continue to use the existing transaction and wallet ownership model; no permission broadening or RLS migration is part of this change.

## Error and deletion handling

- Missing or stale linked transactions downgrade the occurrence to pending instead of silently preserving paid state.
- An unrelated transfer cannot satisfy a statement merely because the occurrence points to its ID.
- A valid inferred transfer can replace a stale explicit link and becomes the occurrence's new active link.
- Existing transaction deletion protections remain unchanged. Maintenance provides recovery for historical deletes, sync tombstones, and any deletion path that predates those protections.

## Testing

Follow red-green TDD with focused regressions:

1. A paid occurrence whose linked payment is absent from active records produces a pending statement with no linked transaction.
2. A paid occurrence whose linked transaction is active, posted, directed to the card, after close, and covers the amount remains paid.
3. An active matching transfer with a pending unlinked occurrence is inferred as payment; creator ownership is intentionally irrelevant to pure transaction matching.
4. Statement maintenance resets a stale paid occurrence to pending and clears payment fields.
5. Statement maintenance links an inferred manual/member-created payment and marks the occurrence paid even when auto-pay is disabled.
6. Wallet balance tests prove the active payment reduces debt and a soft-deleted payment does not.

Run focused `PlanningLogicTests` and `SessionStoreOfflineTests`, the credit-card balance regressions, `git diff --check`, Mistia localization checks, and an unsigned generic iOS build.

## Data and rollout

No live SQL data rewrite is required by the implementation. Existing devices repair stale occurrences through statement maintenance and queue the corrected occurrence for normal sync. Live data must not be changed manually as part of this code-only rollout.

## Out of scope

- Creating synthetic payment transactions for paid occurrences.
- Changing wallet ownership, family permission grants, or Supabase RLS policies.
- Changing statement closing dates, due-date rules, partial-payment semantics, or credit-limit calculations.
- Adding new localized copy.
