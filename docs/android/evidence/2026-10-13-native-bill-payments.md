# Android native bill payment / undo — 2026-10-13

Base: `eece51c`. VersionCode21. Builds on the atomic ordinary/credit wallet payment backend.

## Native behavior and Swift comparison

Planning bill rows expose Pay for pending cycles and Undo Payment for paid cycles. Archived history and skipped cycles suppress money actions. The Material3 sheet shows bill/category icon and color, name, captured cycle month, local payment start/deadline and amount. Unknown amount requires positive exact major-unit input; known amount is displayed without editing. Only owned live nonarchived same-currency wallets appear, including credit cards; system investment wallets are excluded pending investment workflow parity.

Pay opens a confirmation with exact amount and wallet. The request always carries the displayed minor amount, including known defaults, so a concurrent bill amount update cannot replace the approved amount. The repository retains authoritative ownership/currency/balance/CAS checks. Undo displays its destructive-history confirmation in a separate sheet and uses its own callback.

Busy state prevents repeat submission/dismissal. Failure stays in the sheet with localized currency/wallet/amount/affordability/credit-limit/statement messages and retry. Changed wallet/amount drafts require discard confirmation. Sheet identity is owner/bill/cycle/undo scoped; saved form and navigation reject different owners, bills, cycles or malformed month. Restored navigation waits for both source and occurrence loading before deciding whether the source/status disappeared. Current source status prevents reopening stale paid/archive requests, and old owner sheet coroutine scopes are disposed.

Compared directly with Swift `DuePaymentSheet` field/default/wallet/error/dismissal rules and `PlanningLogic.makePaymentDraft`; hero/category presentation and date window follow the available source metadata. Existing localized keys reused, no generated localization edits. Material3 rendering/visual equivalence still needs device QA.

## Verification

- Form foundation runtime RED: 4/5 tests failed at unavailable functions; GREEN after implementation.
- Confirmed known amount regression runtime RED: null request override failed expected exact >2^53 amount; GREEN after capturing displayed amount.
- Six new JVM tests cover cross-month cycle identity, exact integer and fractional minor parsing, invalid/nonpositive/overflow input, same-currency/owner/archive/deleted wallet eligibility, stale source/status, saveable scope and navigation restore.
- Full Android: 630 JVM tests /76 suites, zero failures; Room/planning Android test compilation, lint and APK build pass (724 tasks; final12s).
- Four Compose UI tests compile: confirmation/exact callback and failure, unknown amount eligibility/currency picker, discard, separate undo callback. NOT executed: no ADB devices. Three backend Room tests remain compile-only.
- Focused Swift PlanningLogic53 tests pass. Contract15, Android localization, strict Swift localization and diff checks pass.
- Independent static review: no actionable P1/P2 in native slice; confirmed captured amount/wallet/month and lifecycle guards. No reviewer test execution claimed.
- All nine generated write gates false; no production or live cloud mutation/deployment.

## Artifact

`android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-native-bill-payments-v21.apk`

SHA256: `ed4e73fd0fc9ae74c2ee78f9e00eee54cc17c65dcb5962fce5465855d998d00f`

Manifest `vn.com.quyln.mistia.debug`, `0.2.0-apk2-debug`, versionCode21. Payment sheet/state/backend classes present in APK dex.

Logs: `/tmp/mistia-bill-payment-state-red.log`, `/tmp/mistia-bill-payment-confirmed-amount-red.log`, `/tmp/mistia-bill-payment-native-final.log`, `/tmp/mistia-bill-payment-native-ui-compile.log`, `/tmp/mistia-bill-payment-native-swift.log`.

## Remaining full goal

System category legacy-ID reconciliation and startup bootstrap next. Investment fund confirmation/accounting, shared/receipt undo cleanup, auto-pay/notifications/due maintenance, cards/installments, configured currency/settings and APK3–4 remain open. Full APK1–4 goal is not complete; physical/UI/live sync verification remains distinct.
