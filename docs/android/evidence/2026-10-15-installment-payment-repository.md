# Native installment payment/undo repository — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `8a8cefae`.

## Completed repository behavior

FinanceRepository now exposes typed installment payment/undo operations and the real repository delegates them to the implementation. A request includes the visible installment baseline, selected month, optional selected wallet and exact minor-unit amount override. The source must remain owned, live/unarchived and semantically unchanged since confirmation; a version/timestamp/actor-only ACK is accepted, with the established sub-microsecond creation-time representation tolerance. Changed amount/currency/schedule/default/name requires a refreshed confirmation. A bill with the same UUID cannot satisfy installment lookup.

The executor shares existing guarded expense/undo behavior with bills while using the actual installment record, native35-vector installment scheduling, `installment` occurrence discriminator and fixed `loan_repayment` system category. It does not create a synthetic bill or alter a cloud source payload. Existing bill APIs/defaults and bill-only automatic payment/notification semantics are preserved. Internal BillMoneySnapshot/commit API names remain for compatibility; the explicit source-kind field validates the actual source entity and occurrence membership. Installment commits skip bill notification resolution.

Payment validates the current same-currency wallet (selected override or default), excludes card/archived/deleted wallets, rejects pending cycles with paid/skipped/linked state, validates a positive exact Long amount, ensures the owned loan-repayment category/parent and checks current affordability. The shared financial guards retain receipt/investment/settlement and paid-statement protections. Investment-linked spending remains held until its existing confirmation/posting workflow is implemented; this slice does not invent investment fund movements. Currency mismatch is rejected before any money/category write.

Expense, category bootstrap and paid occurrence writes use one owner-guarded Room transaction, complete raw dependency snapshots and receipt metadata rechecks. No wallet opening balance is rewritten; balances derive from the posted expense. Unknown payload extensions and frozen financial history remain representable. Undo atomically tombstones the matching paid cycles and their supported linked expenses, refusing shared/receipt/settlement/investment/paid-statement states. Repeated undo is idempotent. Repayment after undo reuses the prior expense and occurrence IDs, keeps exact remote Long bases and advances the mutation clock when necessary, preventing a second expense while DELETE/UPSERT responses race.

## Verification

Runtime TDD: after correcting fixture-only missing category resources/unsupported metadata-snapshot setup, initial12 cases produced10 intended failures against the unavailable payment/undo API; two negative-only assertions already returned failure. Those setup errors are not counted as feature RED. Implementation passed the initial set. Review expanded to22 cases: exact >2^53 amount and positive override, same-currency override/default, current affordability, paid/skipped duplicate guards, unscheduled/invalid amounts, foreign/deleted/changed source, stable undo/repay IDs, idempotent undo, wallet CAS race, excluded wallet kinds/states, metadata-only ACK, atomic failure, shared occurrence, independent receipt/settlement guards, source-table collision, cancellation and exact Long/unknown-extension/monotonic-clock replay. A later model filter referenced no test class; corrected to run the complete model suite before accepting verification. The source-table collision fixture now seeds a valid bill through its existing repository.

Final **1266 JVM tests /123 suites**, zero failures/errors; full Android unit tests, database/management/planning AndroidTest compilation, database assembleDebugAndroidTest and app lintDebug/assembleDebug pass. Existing49 bill repository cases pass through the shared executor. Four new actual Room fixtures compile/package only: disk reopen/payment/undo/repay identity preservation; occurrence-outbox failure rolls back expense/category/paid marker; owner change before/after writes rolls back tables/outbox; wallet currency race rejects partial spending. These fixtures have not run on a device/emulator.

Full Swift609 (4contract+137data+468core), contract15, both localization checks and whitespace checks pass. Actual SQLite outbox7/notification3/installment-deletion11 checks pass; they do not execute the new Kotlin repository/Room orchestration. Database test APK contains source-matching schemas1–6/bootstrap catalog. Direct Swift review compared makePaymentDraft's loan-repayment category, saveDuePayment's posted expense/audit/occurrence/current affordability, same-currency preflight and undoDuePayment's occurrence/expense tombstones. Independent review remains pending availability. No Swift runtime/schema change in this slice; Room stays6 and remote contracts stay15.

Logs `/tmp/mistia-installment-payment-{red,green,focused,room-focused,full,swift}.log`.

App APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-payment-repository-v63.apk`, debug versionCode63 and repository/source-adapter DEX presence verified. SHA256 `774de1c2d6528e09738fa9c775997869ff6710494384946f0397581d9e7b3321`.

Database test APK `android/build/outputs/apk2/2026-10-15/mistia-room-installment-payment-test-v63.apk`. SHA256 `4559bb0e4a3cbaa1cb2a9d34e5c7691313c8821fd9999d32ba3efea68d344c49`.

## Remaining goal

Native installment payment/undo sheet/actions/navigation are not wired yet: implement immediately next with owned saved state, exact grouped minor input, same-currency picker, stale month/owner/result fencing, paid/skip confirmations and real repository callbacks. Ordinary installment occurrence UPSERT/explicit undo cloud push is still held; completed causal source-delete worker remains distinct. Do not enable the payment cloud gate without coupled ledger/occurrence tests and device evidence.

Active-source resurrection and explicit legacy/corrupt-batch recovery, maintenance/notifications, investment-fund confirmation integration, pending card currency choice, app currency/settings/forms, APK1–4/RC and independent/device/visual/background checks remain unfinished. All10 flagsfalse; ADB empty; no production write/deploy/migration or device/emulator verification. Full goal remains active.
