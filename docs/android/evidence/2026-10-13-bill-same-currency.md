# Bill payment same-currency policy — Android and Swift — 2026-10-13

Binding user decision: a bill may be paid only using a wallet in the bill's
currency, on both platforms. There is no automatic FX reinterpretation of minor
units. Imported mismatched links remain data, but are ineligible for payment.

Swift adds one nonempty/trimmed/case-normalized eligibility predicate. Bill editor
picker filters wallets and save validates currency. DuePaymentSheet filters
wallets, refuses a mismatched default and disables pay for an ineligible selected
wallet. PlanningPersistenceSupport.saveDuePayment fetches the current bill and
checks currency before balance, investment, transaction, occurrence or ownership
writes. Existing card/installment paths are not subjected to the bill-only rule.

Static review found an auto-pay bypass: maintenance created ledger directly.
Actual simulator RED showed wrong-currency auto-pay created ledger and paid
occurrence. Maintenance now checks before any balance/investment work, reports
localized auto-pay failure, and attemptAutoPay rechecks before insertion. After
fix, ledger/occurrence assertions passed; initial notification assertion still
failed because reminders were disabled in test defaults. Fixture now explicitly
enables/restores reminder preferences. Final two real SwiftData integration tests
pass on a cloned iPhone17e/iOS27 simulator: wrong-currency automatic payment
creates no ledger/occurrence and emits failure; manual persistence throws the
currency error before ledger/occurrence/ownership writes. Synthetic in-memory
stores and disconnected test SessionStore, no production mutation in these tests.

Android bill repository validates the retained existing currency against payment
wallet before record/outbox mutation; draft currency cannot bypass edit currency.
Native picker filters wallet currency and shows the new localized mismatch error.
Shared helper is the policy entry point for the still-unimplemented Android pay
repository; no Android payment-execution parity claim is made in this slice.

TDD: Swift eligibility runtimeRED thenGREEN; Android create/edit repo runtimeRED2
thenGREEN. Static reviewer corrected auto-payP1 and re-reviewed with no remaining
P1/P2 across implemented editor/manual/automatic paths. Vietnamese/English/
Japanese message added to shared catalog and generated sources.

Checks:601 Android JVM tests/74 suites, zero failures/errors; Room/UI compile,
lintDebug and assembleDebug pass724tasks/61s. Swift PlanningLogic53 pass. iOS app
build succeeded and2 named simulator integration tests pass. Contract15,
Android l10n/strict Swift generation and git diff --check pass. ADB empty,
Android instrumented tests unexecuted; no Samsung claim. Nine Android write flags
false. No production deployment/migration or cloud write performed.

Full SwiftPM suite was additionally run:4 feedback +133 data-support +464 core
=601 tests; one failure in
MistiaMigrationPlanTests.testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees.
Focused rerun reproduces CoreData134504 unknown coordinator model version at
MistiaDataStack.openContainer:552. V7 fixture/migration sources were unchanged by
this currency patch. Causality/baseline remains to be investigated; do not call
full Swift suite green. Prior fixture autoreleasepool repair is already present.
Other insufficientPosition diagnostics belong to expected oversell rejection
checks, not this failure. Next step is isolate schema/lifetime/cache evidence
before changing production migration or weakening a test.

Xcode's build script changed source CFBundleVersion during local verification;
only that generated value was restored to its pre-task value, preserving other
source edits. No incidental build-number source change committed.

APK:android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-bill-same-currency-v19.apk
Package vn.com.quyln.mistia.debug, versionCode19/versionName0.2.0-apk2-debug.
SHA-256:8685b38230598f70cbd3b06dce53bbcd2fa6bb617fb5461a4bcaacf8adc8d799

Remaining: V7 full-suite failure, Android actual bill payment/undo with atomic
money/outbox, maintenance/cards/installments/currency settings, category legacy
identity/startup and APK3–4 plus final device checks. Full goal remains active.


Follow-up: the full Swift V7 gate is now resolved by the separately reviewed
investment migration plan slice. See
`2026-10-13-swift-investment-migration-plan.md` for schema collision evidence,
real-store regression and full SwiftPM601-test success. The original failure
above records the result at the currency slice checkpoint.
