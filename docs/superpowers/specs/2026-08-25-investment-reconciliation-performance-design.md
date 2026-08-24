# Investment Reconciliation Performance Design

**Date:** 2026-08-25

## Goal

Remove the approximately 1.2-second tab-switch hitch observed on a physical iPhone after Investment reconciliation was added, while preserving Investment accounting, FIFO inventory, wallet postings, family visibility, synchronization, and recovery behavior.

## Evidence and Root Cause

The active working-tree changes call `InvestmentPersistenceService.reconcileAllTrades` synchronously from `onAppear` in `InvestmentHubView`, `InvestmentWalletDetailView`, and `ManagementView`. Tab navigation therefore enters a persistence operation before the destination can remain responsive.

`reconcileAllTrades` currently:

- fetches every active Investment trade, asset, and wallet for its scope;
- groups and sorts complete trade histories;
- recalculates FIFO-derived accounting for every trade;
- performs per-trade fetches for ledger transactions, postings, ownership, and audit records;
- assigns fresh `updatedAt` values to derived rows even when their business values are unchanged;
- saves the context, invalidating broad `@Query` collections retained by the native tab shell.

This is code-review evidence on the current branch. The user-visible delay was observed on a physical iPhone; no Instruments trace has yet been captured, so the exact before/after duration remains device-measurement work.

## Selected Approach

Use targeted, idempotent reconciliation at mutation and synchronization boundaries. Navigation must never trigger accounting repair.

Rejected alternatives:

- Running full reconciliation in a background task would remove direct main-thread blocking but retain unnecessary reads, writes, battery cost, and later view invalidations.
- Caching SwiftUI render snapshots alone would reduce downstream recomputation but leave the synchronous persistence hotspot intact.

## Navigation Boundary

Remove `reconcileAllTrades` from the `onAppear` handlers of:

- `InvestmentHubView`;
- `InvestmentWalletDetailView`;
- `ManagementView`.

These handlers may continue to manage view-owned UI state such as quick-create visibility. Switching tabs, pushing Investment screens, or reopening a cached tab must not fetch, rebuild, or save Investment accounting data.

## Local Mutation Boundary

Existing local Buy, Sell, edit, and delete operations remain authoritative. They already know the affected asset history and rebuild the required calculations and ledger legs within the persistence transaction.

No domain behavior changes:

- Buy and Sell kind stays immutable during edits.
- Gross purchase amount remains the total order amount.
- Units remain separate FIFO inventories.
- Derived cost basis and realized profit/loss use the same accounting engine.
- Ledger transactions, wallet postings, ownership records, and audit records retain their existing identities and values.

## Remote Synchronization Boundary

Remote Investment rows are applied first. The sync layer collects the identifiers of owners/assets whose active trade inputs actually changed, then reconciles each affected asset once after the batch has been applied.

For a single remote trade mutation, reconcile only that trade's affected asset history. Do not call a full-owner or full-database rebuild.

Incoming rows that are skipped by conflict/version checks must not schedule reconciliation. Incoming postings remain applied through their existing sync path; reconciliation must not erase or duplicate valid manual cash-allocation postings.

## Idempotent Persistence

Reconciliation compares desired derived values with stored values before assigning them. A repeated reconciliation over already-correct data must:

- leave trade-derived fields unchanged;
- leave derived ledger and posting rows unchanged;
- preserve their `updatedAt` timestamps;
- produce no inserted, updated, deleted, or outbox mutation identifiers;
- avoid calling `ModelContext.save()` when the context has no changes.

When a value differs, reconciliation updates only the affected row. Timestamp changes therefore continue to represent real domain changes and retain correct last-write-wins synchronization semantics.

## Legacy and Recovery Repair

Full reconciliation remains available as an explicit repair mechanism for incomplete legacy data, but it is not tied to navigation.

If automatic repair is required, run it once per repair-version using a worker-owned `ModelContext` outside the main actor. Fetch predicates must narrow the input to active Investment rows that can require repair. Persistent SwiftData models must not cross actor boundaries; the worker returns only value-semantic mutation identifiers for normal ownership/outbox handling.

The first optimization pass does not add a recurring repair scheduler unless a failing migration or recovery test proves it is required. Existing correct stores should do zero repair work.

## Observability

Add an `OSSignposter` interval around batch/repair reconciliation with the affected asset and trade counts. The signpost must not include user-entered names or financial amounts.

The signpost distinguishes:

- targeted reconciliation caused by a local or remote mutation;
- explicit legacy/recovery repair.

It must never appear solely because the user switched tabs.

## Error Handling

- Local persistence operations continue surfacing their existing typed errors and localized guidance.
- Remote reconciliation failure follows the current sync failure/reporting path; it must not block tab navigation.
- A failed targeted reconciliation must not silently mark unrelated assets as repaired.
- Recovery work is retryable because reconciliation is idempotent and uses stable derived identifiers.

## Verification

Use red-green tests before production changes.

1. A no-op reconciliation over correct Buy/Sell history reports no mutations and preserves all timestamps.
2. Repeating reconciliation produces the same accounting, ledger, posting, ownership, and audit values.
3. Changing one trade rebuilds only its affected asset; an unrelated asset and its derived records remain untouched.
4. Batch application of multiple changed trades for one asset reconciles that asset once after all rows are present.
5. A remotely skipped row schedules no reconciliation.
6. Buy/Sell totals, FIFO unit separation, remaining cost basis, realized profit/loss, and wallet balances match the existing persistence contracts.
7. Source-contract coverage prevents `reconcileAllTrades` from returning to tab/screen `onAppear` handlers.
8. A synthetic large-history test records targeted versus full-rebuild duration and mutation counts. Results are reported as synthetic, not as physical-device measurements.
9. Run focused Investment core-logic, persistence, sync compatibility, and migration tests, then `swift test`, `git diff --check`, and the generic iOS app build.
10. On a physical iPhone using a Release build, capture the same repeated tab-switch flow before and after. The acceptance target is no visible pause attributable to Investment reconciliation and no reconciliation signpost emitted by navigation alone.

## Out of Scope

- Changing Investment UI or product terminology.
- Changing accounting formulas, FIFO semantics, amount interpretation, wallet rules, family permissions, or RLS.
- Removing explicit repair capability.
- Claiming a measured device improvement without a comparable Release trace or physical-device observation.
