# Same-currency installment payment rule on iOS and Android — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `9f1d0388`.

## User decision and behavior

User explicitly chose same-currency wallets for installment settlement on **both iOS and Android**. Currency comparison trims whitespace, normalizes case and requires a three-letter ASCII currency shape. It never converts or copies raw minor amounts between different currencies. Imported records remain readable and their stored currencies/amounts are not rewritten by validation.

Swift's due payment sheet now filters installment wallets, suppresses an invalid default and requires the current selection to remain eligible at submission. The installment editor applies the same filter and save guard. Early payment now passes the wallet actually selected in that editor instead of silently falling back to the due snapshot's old wallet. Persistence invokes `PlanningInstallmentPaymentSupport.validateWallet` before fund usage, category creation, transaction creation or occurrence changes. This helper fetches the current live/unarchived installment from SwiftData, rejects missing/deleted sources and deleted/card wallets, then compares its current currency with the selected wallet. A stale UI snapshot cannot bypass the rule. Existing bill logic remains in its path; card settlement policy is still pending.

Android's installment wallet picker excludes differently denominated wallets, including the preferred ID. Form submission catches a stale/restored mixed-currency selection with the shared localized error. Repository save validates the preferred payment wallet against the current source currency, and the raw snapshot mutation validator enforces the same invariant at the Room boundary. A wallet currency change during commit causes CAS failure followed by revalidation, without an installment/outbox write. Existing legacy mixed-currency default metadata stays intact until explicitly edited or deleted; saving it requires a compatible wallet. Deletion/skip and read-only history are not blocked or converted by this new save rule.

Android **does not yet implement actual installment payment/undo**. This slice enforces its existing default-wallet/form/repository/atomic validation surfaces and establishes the rule for the next payment implementation; it is not an Android installment money-movement completion claim. Native payment repository/UI will use this same rule before ledger writes.

The error copy comes only from the shared vi/en/ja catalog. Swift and Android accessors/resources were regenerated.

## Actual iOS build issue found and fixed

The first unsigned generic-iPhone build failed at `GenerateStringSymbols`: existing `planning.installmentEditor.amountPreview` used Android-only `%1$s` in the shared catalog. Corrected the source to `%@`, then regenerated. Android still receives its positional `%1$s` from its generator; Swift now gets a typed formatting function. An actual English/Vietnamese/Japanese formatting regression passes with exact large displayed values. The subsequent complete iOS application build succeeded with `CODE_SIGNING_ALLOWED=NO`; this proves compilation of the SwiftUI/persistence call sites, not device UI execution. The build script's incidental source CFBundleVersion change was verified to affect only that value and restored to the pre-build751; no signing settings or project build phases changed.

## Verification

Runtime TDD: the Swift policy vector test failed on mismatched/invalid currencies against the permissive stub; four actual SwiftData cases produced seven failed assertions before persistence validation (matching-only case already passed). After implementation, policy/SwiftData cases pass: cross-currency rejection before mutations, stale persisted currency change, normalized imported metadata and exact Long preservation, missing/deleted/archived source and deleted/card wallet rejection. These are macOS SwiftData runtime tests of the production preflight helper; they do not execute the entire SwiftUI save flow or a physical iOS device payment.

Android policy test failed against a permissive stub; repository new-create/existing-default and commit-race cases failed against the old save path; restored-editor rejection failed before the form guard. Final policy vectors, three new repository cases, two new editor cases and a direct atomic mutation-validator case pass. Older amount/baseline fixtures now use matching wallet currencies, preserving their original exact-money assertions under the selected rule.

Final **1244 JVM tests /122 suites**, zero failures/errors; full Android unit tests, Room/management/planning AndroidTest compilation, database assembleDebugAndroidTest, app lintDebug/assembleDebug pass. The final model suite rerun includes the review-added atomic-validator case after the aggregate run. Two new Room fixtures and one Compose restoration/picker fixture compile only; existing USD editor instrumentation seeds a USD wallet. No Android device/emulator instrumentation was executed.

Full Swift **609** (4contract+137data+468core), actual unsigned generic-iPhone app build, contract15, both localization checks and whitespace checks pass. Existing actual SQLite outbox7/notification3/installment-deletion11 checks pass. Packaged Room schemas1–6 and bootstrap catalog match source. No Room/SwiftData schema migration, remote contract, production schema or cloud gate change. Independent review remains pending availability.

Logs `/tmp/mistia-installment-currency-{swift-red,swift-green,android-red,layers-red,android-green,ios-build,ios-build-green,full,swift-full,model-final}.log`.

Android APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-same-currency-v62.apk`, debug versionCode62 verified. SHA256 `ea0859dd43ef3327d38ff516dfe53d45fc9e142d287403a726ee0f3282ff0d7d`.

Database test APK `android/build/outputs/apk2/2026-10-15/mistia-room-installment-currency-test-v62.apk`. SHA256 `345819886a225e5aa1cd4ed11f509ada3aad9d56228f859c2c886dcb315a8bbe`.

## Remaining goal

Continue actual Android installment payment/undo and ordinary occurrence push using the selected rule, current affordability and atomic financial dependency/receipt/statement guards; then active-source resurrection and explicit legacy/corrupt-batch recovery. Maintenance/notifications, pending card currency choice, app currency/settings/forms, APK1–4/RC and independent/Samsung/visual/background checks remain unfinished. All10 flagsfalse; ADB empty; no production write/deployment/migration or physical-device proof. Full goal stays active.
