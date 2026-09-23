# APK 1 paid credit-card statement guards evidence — 2026-09-23

This slice ports the iOS transaction lock for paid credit-card statement
periods. The behavior was compared directly with
`PlanningLogic.paidCreditCardStatementForExpense` and
`TransactionEditorSheet.isLockedByStatement`.

## Scope and parity boundary

- A posted credit-card expense is locked when a posted internal-transfer
  payment into the same card occurs on or after the card closing date and
  covers the total active charges in that statement month.
- A paid `due_occurrence_records` row with `source_kind_raw_value=creditCard`
  directly locks its linked payment transaction, matching the primary iOS
  path. Owner, deletion and paid-status checks prevent cross-account or stale
  rows from locking a transaction.
- The legacy iOS fallback remains available for localized card-payment titles
  and explicit statement-month forms such as `02/2026`, Vietnamese, Japanese
  and English month names.
- The repository checks the existing record before edits. For new expenses it
  evaluates the proposed transaction set before affordability and before the
  atomic Room record/outbox write, so UI or caller bypass cannot reopen a paid
  period or enqueue an invalid mutation.
- The transaction list uses the same guard, replaces the date subtitle with the
  existing localized paid-statement explanation, and disables opening the
  native editor for the locked row.
- This slice adds no schema, migration, RPC, RLS or cloud-write behavior.

## TDD and automated verification

- RED 1: the focused model test failed compilation because
  `isLockedByPaidCreditCardStatement` did not exist.
- GREEN 1: model tests cover a sufficient post-closing payment, an insufficient
  payment, direct paid-occurrence linkage, owner isolation, balance-adjustment
  exclusion and credit-card debt-lending inclusion.
- RED 2: repository tests failed compilation because
  `PAID_CREDIT_CARD_STATEMENT` did not exist.
- GREEN 2: repository tests prove a paid-period expense cannot be edited, a new
  expense cannot be added while the covering payment still closes the period,
  and a linked payment transaction cannot be edited.
- Focused core-model, database-repository and transaction-feature tests passed.
- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed in 1m 51s; 177 tests across 35 suites,
  0 failures/errors/skips; Room Android-test sources compiled; lint reported no
  errors; debug assembly succeeded.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities, using
  Command Line Tools. Strict iOS String Catalog and Android localization checks
  passed; the slice reused existing generated localized strings.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`16e03f931876da077388bb6ed1e085eab9d5817b050f11730c52a858d8864a59`.
The APK contains 634 files.

## Samsung verification

ADB reported Samsung `SM-F776Q` (`R5GL72ERETZ`). `adb install -r` installed the
new APK successfully while preserving the authenticated session. A launcher
cold start completed in 531 ms and resumed Mistia `MainActivity`.

On the real authenticated transaction list, the `サイゼリヤ` row displayed:
`Khoản thu chi này thuộc sao kê thẻ tín dụng đã thanh toán nên không thể sửa
hoặc lưu trữ.` Tapping that row kept the app on `Thu chi`; no edit sheet opened,
and `MainActivity` remained the top resumed activity. This verifies the lock
against actual pulled account data rather than only a fixture.

No live Supabase mutation was attempted. The global and every domain cloud-write
gate remain disabled.
