# Android atomic recurring bill payment / undo backend — 2026-10-13

Base: `f3cf28f`. VersionCode20. This slice exposes the complete offline API for ordinary wallet and credit-card bill payments; native payment UI follows separately.

## Behavior and Swift comparison

`BillPaymentRequest` identifies bill/month and optional wallet/amount override. Repository resolves the authoritative owned live source and pending scheduled cycle, rejects paid/skipped/linked cycles, foreign viewer envelopes, archived/default-invalid wallets, nonpositive/nil unresolved amounts and different currencies. Money values remain Long through ledger, occurrence and outbox. A >2^53 payment is tested exactly.

Swift references: `PlanningLogic.makePaymentDraft`, recurring bill `planningSnapshot`, `PlanningPersistenceSupport.saveDuePayment` / `undoDuePayment`, `DuePaymentSheet.pay`, `MistiaFinanceIconRegistry.categoryKey`, `MistiaBootstrap.ensureSystemCategory`, archived action guards. Payment creates a posted expense with the bill name at the payment instant. Category selection follows the bill system key, then active icon key, then legacy billing. Existing system metadata/legacy IDs remain intact; missing selected default and parent are seeded inside the same money batch, including archived legacy billing. Existing category tombstones are preserved and cause refusal rather than silent resurrection. Reporting overrides remain null, as in Swift's direct payment path; the exact expense amount is retained and source currency is explicit.

The existing transaction builder, wallet balance, credit-limit and paid-statement guards are reused. Supported payment atomically writes categories when necessary, ledger transaction, all owned pending occurrence duplicates, and their outbox rows. Paid occurrences snapshot amount/date and link to the one ledger ID. No wallet balance field is rewritten.

`BillMoneySnapshot` captures all 15 supported owner entity collections, including tombstones/viewer envelopes, plus owner receipt transaction IDs. Room rechecks complete snapshots inside the same transaction as writes. Currency/balance/category/source changes, new transactions, competing skips/payments, receipt insertions and account clearing invalidate the operation. Batch shape validates the live owned source, all mutation owners/identities, cycle links, source versions and insert-only system categories. There is no fallback to a split ledger/occurrence commit.

Undo tombstones every owned paid duplicate and distinct linked ordinary expense in one batch, preserving exact remote versions and DELETE mutations. It refuses archived source history, paid card statement locks, links used by another cycle, shared settlement metadata, investment postings and receipt cleanup dependencies. A repeated successful undo is idempotent.

Investment fund usage confirmation/accounting, shared transaction cleanup and receipt file cleanup are not implemented by this slice. These unsupported linked states fail before money writes and remain in the full parity scope. Missing catalog fails safely; application DI now supplies the bundled catalog. No native pay/undo button is claimed yet.

## Verification

- Initial seven new runtime tests: 7 failures at the explicit unavailable implementation (RED); all green after implementation.
- Custom-category fallback test: runtime RED at missing category, GREEN with atomic fallback/parent insertion.
- Receipt-linked and archived undo regression tests: runtime RED against prior implementation, GREEN after guards. Independent reviewer found archived-history P2; fixed and reviewed again, no remaining actionable P1/P2 in backend scope.
- 23 new JVM tests cover exact amounts/default override, currency, ownership, affordability/credit limits, paid/skipped/paused/unscheduled cycles, transaction/currency/skip/receipt races, cancellation, storage failure, undo versions/idempotency, shared-state refusal, archived history, statement locks and investment wallet guard.
- Full Android: 624 JVM tests /75 suites, zero failures; Room and planning UI test compilation, lint and assemble pass (724 tasks, final build38s).
- Three real Room tests compile: pay/reopen/undo, SQL trigger rollback when occurrence outbox insertion fails, and currency race. NOT executed: ADB inventory is empty. No emulator/Samsung money verification claimed.
- Full SwiftPM: 4+133+464=601 tests, zero failures. Expected oversell diagnostic is not a suite failure.
- Contracts15, Android localization, strict Swift localization and diff checks pass.
- All nine generated write flags false. No live Supabase writes, production migrations or deployments.

## Artifact

`android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-atomic-bill-payments-v20.apk`

SHA256: `97d00e49c2f2debf2f404661270121965d89b5881638a596000769ec2c2ac560`

Manifest verified: `vn.com.quyln.mistia.debug`, `0.2.0-apk2-debug`, versionCode20. APK dex includes payment repository/snapshot/result classes.

Local logs: `/tmp/mistia-bill-payment-red.log`, `/tmp/mistia-bill-payment-category-red.log`, `/tmp/mistia-bill-payment-undo-red.log`, `/tmp/mistia-bill-payment-v20-full.log`, `/tmp/mistia-bill-payment-swift-full.log`.

## Next slice

Native scoped payment amount/wallet sheet, confirmation, busy/error/discard states and pay/undo actions. Remaining investment/shared/receipt cleanup, maintenance/default-category reconciliation/startup, cards/installments, settings, APK3–4 and physical verification remain open.
