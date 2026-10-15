# Native installment payment and undo UI — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `150923d0`.

## Behavior

Pending installment rows open a native payment sheet; paid rows open a separate undo confirmation sheet; skipped rows retain only their skip/undo action. Real FinanceRepository callbacks use the guarded atomic payment/undo implementation from APK63. The sheet displays the frozen plan name, localized cycle month, exact formatted minor amount and a same-currency owned wallet picker. Card, investment, unknown, archived, deleted and foreign wallets are excluded. Investment fund usage remains a separate unfinished workflow.

Direct Swift review found a mismatch in the first draft: DuePaymentSheetTarget.requiresAmountInput is false for fixed installments and Swift amountRow is read-only. Android now likewise displays the fixed amount, with no editable payment amount field. A restored/tampered state cannot override that amount. This correction happened before this commit; the repository's optional amount override remains available for separately reviewed workflows. Values above2^53 retain exact Long precision; USD1375 minor is not rescaled. No Swift runtime/catalog/schema change is required in this slice.

Payment confirmation freezes the source baseline, month, selected wallet and exact amount. Current wallet eligibility is revalidated while confirmation is open and again by persistence. Failed payments keep the wallet choice and localized error. Busy state prevents duplicate confirmation/close. Wallet changes use an explicit discard/keep guard. Saveable navigation/form state is owner/source/month scoped and survives repository reconstruction/loading. Changing owner/month/zone disposes the old sheet and its coroutine; guardedInstallmentMutation checks cancellation after a non-cooperative callback before applying a result. An old result cannot dismiss a new month's sheet. A missing/changed current due row (status, amount, due date or linked transaction) disables payment/undo with the existing stale-cycle message; metadata-only source ACK is accepted. Repository baseline/CAS protections remain the financial authority.

## Verification

Runtime TDD: initial9 state cases produced7 intended feature failures against the stub. Implementation passed. Direct Swift review added a read-only fixed-amount regression (2 intended failures) and current-cycle confirmation regression (1 intended failure), then both passed. Final10 state cases execute for exact Long/currency, picker eligibility, current wallet revalidation, invalid/tampered amount, owner/source/month/status guards, dirty wallet tracking, owned savers, paid-history navigation and current target checks.

Nine new Compose/Room fixtures compile and package only: real payment/undo/repay IDs and derived wallet balance/outbox; restored wallet draft/discard/owner/month changes; excluded wallet picker; currency change during confirmation; duplicate/busy/failure handling; late NonCancellable undo after month change; loading/invalid frozen amount; skipped/paid row actions; changed-cycle undo hold. They have not executed on a device or emulator. The current-cycle UI check is an early guard; it does not replace the repository's atomic snapshot validation.

Final **1276 JVM tests /124 suites**, zero failures/errors. Full unit suite, database/management/planning AndroidTest compilation, database/planning test APK assembly and app lintDebug/assembleDebug pass. Full Swift609 (4contract+137data+468core), contract15 and both localization checks pass. Actual SQLite outbox7/notification3/installment-deletion11 checks pass; these helpers do not execute the new Compose fixtures. Packaged database test schemas1–6/bootstrap catalog match source. Direct self review compared DuePaymentSheet selection, default amount, fixed-amount presentation, month text, dismissal behavior, pay and undo paths. Independent review remains pending availability.

Logs: `/tmp/mistia-installment-payment-ui-state-red.log`, `...-state-green.log`, `/tmp/mistia-installment-payment-fixed-amount-red.log`, `/tmp/mistia-installment-payment-target-red.log`, `/tmp/mistia-installment-payment-ui-fixed-green.log`, `...-full.log`, `...-swift.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-payment-ui-v64.apk`: SHA256 `68661b8b5c2f54996747bc967f3fe6214fc0b97b355acf2ec9f6db53fdf1a72f`. Debug versionCode64 and actual payment-sheet DEX presence checked.

Database test APK `android/build/outputs/apk2/2026-10-15/mistia-room-installment-payment-ui-test-v64.apk`: SHA256 `4559bb0e4a3cbaa1cb2a9d34e5c7691313c8821fd9999d32ba3efea68d344c49` (unchanged database test code from APK63).

Planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-installment-payment-ui-test-v64.apk`: SHA256 `30e34f962b14c1b873dcb47115633e33dc051aeb19f1275e16d8757f41c5995b`; actual new fixture DEX presence checked.

## Remaining objective

All10 write flags remain false; no cloud writes/deployment/migration. ADB empty; no Samsung/emulator or visual/background execution claimed. Ordinary installment cycle UPSERT/explicit undo push, active-source resurrection and legacy/corrupt-batch recovery, maintenance/notifications and investment fund confirmation remain unfinished. Card settlement policy is still pending the user's answer. Remaining currency/settings/forms, full APK1–4/RC and independent/device/visual evidence remain open. Continue the next dependency slice immediately; the full goal is active.
