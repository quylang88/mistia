# APK 1 transaction affordability evidence — 2026-09-23

This slice ports the current-balance and available-credit boundary used when
saving ordinary Android expenses and internal transfers. It does not add paid
statement locks, transaction cloud push or any production write.

## Scope and acceptance

- Added a typed wallet-balance index matching iOS `TransactionLogic`: ordinary
  wallets seed from opening balance, credit cards seed from zero debt, and only
  posted/non-archived/non-deleted records contribute.
- The index includes every qualifying record regardless of `occurredAt`. A
  backdated expense therefore succeeds when today's balance can cover it and is
  rejected when today's balance cannot; no historical-balance rule is used.
- Expense and income apply opposite cash directions. Internal transfers debit
  the source amount and credit `destinationAmountMinor` when present, otherwise
  the source amount. Transfer into a credit card reduces debt. Family/debt
  records already present from sync are included with the matching iOS balance
  directions, including shared-expense principal exclusion and the
  resale-receivable reporting-expense rule.
- Editing excludes the existing transaction before evaluating the replacement,
  preventing the old outflow from being counted twice.
- Non-card expense/internal-transfer outflows require current balance at least
  equal to the requested amount. Credit-card expenses require a linked active
  profile and compare the amount with `max(limit - max(debt, 0), 0)`.
- Repository enforcement happens after typed mutation validation and before the
  atomic Room commit, so a rejected save creates neither a record update nor an
  outbox mutation. The editor maps insufficient balance and credit-limit errors
  to existing generated String Catalog copy.

Paid credit-card statement periods remain a separate guard because Android does
not yet have the statement model. Investment-fund confirmation behavior also
remains tied to the later APK 4 investment write slice; this evidence does not
claim those behaviors.

## TDD and automated verification

- Red phase 1: the five-test model suite failed compilation before
  `TransactionWalletBalanceIndex` and `requireAffordable` existed.
- Red phase 2: the repository accepted a 501 JPY backdated expense after a
  future-dated 1,000 JPY expense had reduced a 1,500 JPY current balance; the
  test expected `INSUFFICIENT_WALLET_BALANCE`.
- Focused green coverage verifies date-independent current balance, edit
  exclusion, draft/archive filtering, cross-currency card payment direction,
  card limit-minus-debt, repository rejection and linked-profile lookup.
- The Room instrumentation fixture now seeds a real opening balance so the
  production save path remains executable on device rather than merely
  compiling around the new rule.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache`: passed in 1m 17s; 164
  tests across 33 suites, 0 failures/errors/skips; Room Android-test sources
  compiled; lint reported no errors; debug APK assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using the
  installed Command Line Tools SDK.
- Strict iOS String Catalog codegen and Android resource generation checks both
  passed. No localized copy changed.
- `git diff --check`: passed before documentation finalization.
- Focused physical-device instrumentation passed on Samsung `SM-F776Q`
  (Android 17): `TransactionRoomTest`, 1 test, `BUILD SUCCESSFUL` in 8s.
- The unfiltered `:core:database:connectedDebugAndroidTest` run executed all 12
  device tests and exposed one unrelated infrastructure failure:
  `MistiaDatabaseMigrationTest` cannot find the packaged Room schema asset
  `MistiaDatabase/1.json`. The affordability Room test passed; this evidence
  records but does not hide or misattribute the separate migration-test issue.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`f57752e53a59888147cc4b7d13c613b9f6fecce77129b0bfacc2f60e47dfed15`.
The APK contains 634 files. Generated debug `BuildConfig` confirms the global,
category, wallet and credit-card cloud-write flags are all `false`; a
transaction write gate does not exist yet.

## Physical-device and cloud evidence

ADB detected Samsung `SM-F776Q` (`R5GL72ERETZ`). Initial safe update installation
failed with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: the installed debug certificate
SHA-256 began `72064998`, while this Mac's APK certificate begins `334269be`.
After the user explicitly authorized deletion, `vn.com.quyln.mistia.debug` was
uninstalled (removing its local data/session), then this APK installed
successfully. Package manager reports version `0.1.2-apk0-debug` (code 3), and
the Vietnamese launch screen renders without crash or overflow at 1080×2520.

The initial Google attempt reproduced the expected registration blocker because
this APK's SHA-1
`84:EE:48:1E:2A:17:C4:5E:0E:52:27:71:2F:5F:58:7F:7B:19:0B:4E` did not match
the older Android client. The user then registered the current package/SHA-1 in
Google Cloud and retried on the same installed APK. Device logs now prove the
complete native auth boundary:

```
GOOGLE_TOKEN_RECEIVED
GOOGLE_EXCHANGE_STARTED
GOOGLE_EXCHANGE_SUCCEEDED
```

`MainActivity` remained the resumed activity, the signed-in `Thu chi` screen
showed pulled cloud transactions, and the native `Thu chi mới` bottom sheet
opened at 1080x2520 with expense/income/internal-transfer controls, title and
amount fields, and localized cancel/save actions. No transaction was submitted
during the visual check. The focused Room save-path instrumentation then passed
on the same Samsung device.

No production write, migration, RLS/RPC change or deployment occurred. All
existing cloud-write gates remained disabled; the live checks exercised Google
token retrieval, the Supabase auth exchange and read-only pull only.
