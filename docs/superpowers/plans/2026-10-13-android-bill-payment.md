# Bill payment / undo payment next slice

Source: DuePaymentSheet.pay/undoPayment, PlanningPersistenceSupport.saveDuePayment,
validateSourceWalletCanCoverPayment/undoDuePayment, PlanningLogic.makePaymentDraft
and existing Android transaction builder/balance/FX/account scope. Build on
commitBillCycleMutations snapshot checks and typed bill/occurrence contract.

- [ ] Read complete Swift payment/transaction amount pairing and card/investment
  handling before declaring parity. Identify exact payment date, source wallet,
  expense category, title, amount override, currency and audit fields.
- [ ] RED unit tests: pending cycle payment creates posted expense + paid
  occurrence in one atomic outbox batch; exact >2^53 amounts, nil amount override,
  category and wallet owner scopes, insufficient ordinary/card balances, invalid
  wallet/category/archive/schedule and existing paid/skipped protection.
- [ ] Add typed payment draft/result and repository building via existing shared
  transaction logic. Recheck bill/cycle/wallet/category/balance dependency
  snapshots inside the Room transaction; no stale mutation may overwrite a
  concurrent payment or user edit. Never split ledger and occurrence writes.
- [x] User product decision supersedes previous FX alternatives: payment must
  use a wallet in the SAME bill currency, for Android AND Swift. Existing Swift
  manual/auto-pay and both bill editor guards are implemented and verified.
- [ ] Android pay execution must invoke billPaymentCurrenciesMatch against
  the authoritative bill and wallet inside the atomic money transaction;
  picker filtering alone never suffices. Preserve exact wallet amount/currency
  pairing and occurrence snapshot; reject mismatched imported defaults.
- [ ] Undo payment tombstones all owned matching paid occurrences and linked
  ledger records atomically with versions/tombstone DELETE outbox preservation.
  Honor transaction statement locks, family/shared money/receipt/investment
  cleanup dependencies; reject unsupported active linked state safely and keep
  the full requirement open until implemented.
- [ ] Native payment amount/wallet/details/confirmation, nil default amount,
  pay/undo actions with busy/error and scoped drafts. Compile real Room/UI tests;
  execute if a device is actually connected, otherwise preserve pending gates.
- [ ] Separately gated due-occurrence push, semantic conflict/cancellation/retry
  and dependency order transaction-before-occurrence; all production gates false.
- [ ] Full Android/Swift/contract/localization/lint/build, independent source
  review, evidence/progress, artifact/checksum and per-slice commit.

Other open dependencies stay in scope: category legacy-ID reconciliation/startup,
fresh-account defaults, currency settings, due maintenance, cards/installments,
APK3–4 and physical checks. No production writes/migrations/deployments.


2026-10-13 backend checkpoint: ordinary/credit wallet pay + undo APIs and atomic
money CAS implemented;23 new tests/full624 Android +601 Swift green. Category
system-key/icon/fallback behavior compared directly with Swift. Room SQL rollback
and reopen/race tests compile but await device execution. Native UI is next;
investment/shared/receipt cleanup remains explicitly unavailable and guarded.
Evidence: docs/android/evidence/2026-10-13-atomic-bill-payments.md.


2026-10-13 native checkpoint: pay/undo sheet/actions are implemented and verified
with6 new JVM tests/full630 Android,4 compiled Compose tests and53 Swift Planning
cases. Confirmed amounts are explicit request overrides to preserve user intent
across concurrent source edits. Device UI/visual QA and investment/shared/receipt
cleanup remain open. Continue legacy system-category reconciliation/startup next.
