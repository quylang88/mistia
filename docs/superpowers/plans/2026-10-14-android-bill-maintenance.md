# Android recurring bill maintenance

Goal: match MistiaRecurringBillMaintenance.swift pending-cycle scanning, safe
same-currency automatic payment and persistent idempotent notification behavior.
Keep all nine cloud write gates false and perform no production writes.

1. Pure maintenance event planner in core/model/BillMaintenance.kt consumes owned
   bill/occurrence snapshots, reference Instant and ZoneId. Use previous/current
   local cycle months only, skip terminal/paused/archived/deleted/viewer bills.
   Emit auto-pay intents only on configured normalized date, payment-start/deadline
   reminders with Swift keys and overdue daily keys. Preserve exact Long amounts.
   Runtime RED/GREEN tests cover cross-month deadlines, local midnight keys,
   normalized auto-pay, terminal filtering and one-time windows. Intent output is
   not an actual payment or notification; gate those claims separately.
2. Repository/orchestrator executes auto-pay through existing atomic payment
   repository with current wallet balance, same currency and investment protection.
   Recheck owner/cycle/dependencies before money writes. Coalesce repeated runs and
   failures; maintain paid/skip/undo notification cleanup. No duplicate ledger IDs.
3. Persistent notification batch and native display permission flow: exact Swift
   notification keys/kinds/source metadata, owner scoped and repeat-safe. Background
   and foreground hooks must cancel on account change and not show stale alerts.
4. Per slice full Android/Swift/contracts/l10n/SQLite checks, evidence and commit.
   Independent reviewer is currently unavailable due usage limit; record this
   limitation and complete review when available. Device checks remain pending.


Storage/model milestone: local notification schema5 and exact owner batch CAS,
read/unread/resolved model semantics are implemented and verified. Remaining:
notification copy and action metadata from bill events; success notification must
commit with money or have durable recovery before enabling automatic hooks.
Resolve read state from fresh notification snapshots so a late maintenance pass
cannot overwrite a user's newer read/resolved action. Then native center and
foreground/background scheduling, account cancellation and permission flow.


Automatic success companion now commits in the Room money transaction, with
localized production presentation, exact bill/wallet/month guards and preserved
read state. Next persist failure/reminder reports from fresh notification
snapshots and resolve paid/skipped/paused actionable rows. Native center/hooks
must enforce current account, permission/preferences and no stale reminder writes.


Reminder/failure batch milestone: localized production formatter, fresh bill/cycle/
notification snapshot CAS with retries, protected read state and stale failure/
reminder suppression are implemented. Native center must expose groups and local
read actions, then bill action sheet and immediate manual pay/skip resolution.
Do not enable automatic scheduling before current-account cancellation and
notification preferences are wired. Existing independent review queue remains.


Native local center slice: add NotificationCenter grouping/visibility model with
Swift group IDs, latest preview/newest-group order and oldest-to-newest detail
storage, then date sections rendered newest first. Read repository captures exact
visible records at invocation and retries CAS without marking new or replaced
arrivals. Wire Overview bell/unread badge and an owner-keyed native navigation
route, group opening/read-all/pull refresh/back behavior. Compose tests compile
only until device available. Payment/top-up actions, Fluent visual assets, family
remote records and maintenance/preferences hooks remain separate remaining work.


Bill notification actions milestone: native current-data payment and destination-
only internal top-up wrappers, owner/cycle guards and atomic manual pay/skip/pause
notification resolution are implemented. One-time legacy pause and malformed
failure cycle regressions fixed with runtime RED/GREEN. Next wire reminder
preferences and guarded foreground/background maintenance; verify account changes,
cancellation, duplicate runs, disabled reminders and device notification delivery.


Notification preferences milestone: durable device choices, explicit-enable permission
request, commit-time bill notification gates and before/after family inbox pull gates
are implemented. Legacy appearance initializes missing details without resetting family.
Next implement current-account guarded foreground/background bill maintenance, with
cancellation, offline support, duplicate invocation and no notification-master gate on
money. Then OS delivery and remaining notification domains. Independent review/device
verification and full APK1–4 remain pending.


Current-account guard milestone: injectable serial coordinator cancels suspended
maintenance on auth-owner changes and checks immediate races; production Room
money/reminder transactions check active owner before and after writes. Runtime
coordinator tests pass; Room rollback tests compile only. Next wire foreground
resume/day/preference triggers and a background worker with reliable cold-process
auth restoration. Keep money independent of reminder master and preserve current
owner guards through every hook. Then OS delivery and remaining APK domains.
