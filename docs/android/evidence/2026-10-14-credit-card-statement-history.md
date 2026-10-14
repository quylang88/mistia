# Native credit-card statement/history view — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `2d7370f`.

## Completed slice

Management card taps open an owner-scoped native statement route. A separate edit button retains the existing card editor. The view shows the selected spending month, exact Long payable amount, unclosed/payable/overdue/paid state, closing/due dates and owned linked-wallet name. Charges render in a grouped card with dates, category icons and negative amounts; paid history shows locks and has no transaction-edit action. Missing/foreign/deleted cards leave the route. An archived card or missing/foreign profile has no active statement. Empty pre-opening months and empty charge lists have localized states.

Month navigation is bounded from January ten years ago through the current local month, matching Swift. The native month/year dialog applies on Save and discards on Cancel. Only owner/card/month identifiers enter saved state; restoration rejects foreign identifiers or malformed months. A resumed-minute clock and current device zone refresh dates/status/bounds. Repository observation is lifecycle-aware, with explicit initial loading and localized retry on read/calculation failure rather than a false zero total. The view performs no financial writes.

## Swift comparison and self-review

Compared `ManagementCreditCardStatementView.swift`, `MistiaMonthNavigationControl.swift`, `MistiaLocalization.statementMonthYearString`, `MistiaAccent` and the existing planning model. Raw charge history intentionally retains posted expense adjustment rows that the payable total excludes, and excludes foreign/draft/archived/deleted/other-month rows. Raw archived linked-wallet names are retained when owned/live, matching storedWallets; foreign names are hidden. Paid rows are static as in Swift. State accents use Swift purple/light-purple, overdue/paid colors and dark/light opacity; spacing, grouped 22dp cards and hierarchy follow the reference. Android uses Material icons and a native dropdown month/year dialog; visual equivalence remains unverified.

Payment CTA, manual/automatic payment, undo and maintenance are separate unfinished money slices. They are not represented by a dummy action in this read-only view. Generated transaction-title translation is also still pending: current raw custom titles/category fallbacks are shown. The pending card currency question is distinct from the accepted same-currency bill rule. No card settlement policy is inferred from the bill answer.

## Verification

Runtime TDD: `/tmp/mistia-credit-statement-ui-state-red.log` has7 intended failures against helper stubs. GREEN focused and full checks pass: **941 JVM tests /100 suites**, zero failures/errors. Seven new tests cover actual statement projection, raw history, owner/profile/deletion/archive restrictions, paid history, state restoration and Tokyo/Vietnam month bounds. Full Android tests, Room/management/planning AndroidTest compilation, lintDebug and assembleDebug pass. Three new Compose tests cover exact >Double-precision paid display/locks, month cancellation/bounds and separate statement/edit callbacks; these **compile only**, with no device execution.

Full Swift **602 tests** (4contract+133data+465core), contracts15, both localization checks, actual SQLite outbox7/notification3 checks and git diff --check pass. New error/retry copy comes from shared xcstrings with en/ja/vi; both generators ran. Final accessibility/status-opacity adjustment received focused unit/Compose compilation and lint/build verification after the full checks.

Logs: `/tmp/mistia-credit-statement-ui-{state-red,state-green,build,full,swift,final}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-credit-statement-history-v50.apk`; package/versionCode50 verified with aapt. SHA256 `be3e36408b3ac839f56f0dd01060bcc9aa48ae58ec86dd868f4a6ca9b83c49d9`.

## Remaining gates

ADB empty; no emulator/Samsung runtime, screenshot, font-scale or dark/light visual verification. Independent review pending availability; direct Swift/self-review completed. All nine cloud write flags false; no live cloud write/deploy/migration. Card payment/maintenance, generated-title localization, installments and remaining APK1–4/RC work stay open. This slice does not complete APK2 or the overall goal.
