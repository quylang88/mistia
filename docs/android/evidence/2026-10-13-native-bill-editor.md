# Native recurring bill editor and planning navigation — 2026-10-13

Planning now exposes budget/due/goals in Swift order, with due submodes
bills/credit cards/installments. Cards/installments remain count placeholders,
explicitly incomplete. Bills use existing monthly scheduling projection, display
amount or nil-amount label, paid/skipped/neutral-pending state, payment start,
explicit deadline and auto-pay date. Paused bills have a separate edit section.
Archived paid history stays visible with no mutable Edit action.

Native Material3 bill sheet supports name/category/optional amount, recurring or
one-time schedule, day/date/deadline, first-current/next-month choice, frequency,
auto-pay day/date and payment wallet. Shared icons/color and existing generated
Vietnamese/English/Japanese strings are reused. Quick picks follow Swift's26
system keys with latest eligible expense-child row per key and current selected
category prepended when absent. Deleted/foreign categories and wallets excluded;
archived current selections preserved. Existing edit currency is retained.
New bill default remainsJPY pending settings/default-currency parity.

Create/edit/pause/resume/archive call the existing atomic offline repository;
archive unpaid guard remains authoritative. Busy controls, save errors retaining
draft, discard confirmation and lifecycle confirmation added. State and captured
edit payload use owner-scoped savers; malformed/foreign/archived/deleted captured
edit cannot open a mutable form. Explicit auto-pay DatePicker range is bounded
to local payment window; UTC picker dates convert back to local calendar days.

Source review: PlanningView tab/due order, PlanningEditors bill sheet/draft/
normalization and picker, MistiaCategoryPicker.billQuickPickCategories and
FinanceEnums recurringBillQuickPickDefaults. Reviewer identified and verified
corrections for decimal keyboard, mutable archive-history editor, status/nil
amount/date details and auto-pay selectable range. Pending rows use neutral
'Cần trả' rather than mislabel historical unpaid cycles as Upcoming.

TDD: native workflow test written before sheet (compileRED missing sheet API);
UI runtime cannot run because ADB empty. Unit navigation runtimeRED followed by
GREEN; reviewer archive/deletion regression runtimeRED followed by GREEN.
Imported fractional-currency exact minor units covered. Two native UI tests
(create exact amount through real Room and save-failure/discard dark1.3font) are
compiled, not executed. Existing savings workflow tab moved from1 to2.

Final full Android unit/lint/build/Room/UI compile and52 Swift PlanningLogic
checks, contract15, Android/strict Swift localization and diff checks recorded
below after verification. No emulator/Samsung runtime verification claimed.
All eight write gates false; no production requests/writes/migrations/deployment.

Remaining: pay/skip/undo, timing badges/due summaries, due maintenance and actual
auto-pay execution/notifications, card/installment workflows, currency preference,
category legacy-ID reconciliation/startup seed and APK3–4. Bootstrap dependency
is still open; new offline accounts may have no quick picks until seeding is
wired safely. This slice works with eligible local/imported categories and does
not claim fresh-account/default-category or complete APK2 parity.

Verification: final571 JVM tests/72 suites, zero failures/errors; Android full
checks pass724tasks/12s. Swift PlanningLogic52 pass. Contract/localization/diff
checks pass. ADB empty; UI tests only compiled. Debug package
vn.com.quyln.mistia.debug, versionCode16/versionName0.2.0-apk2-debug.
Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-native-bill-editor-v16.apk
SHA-256: 63f461c0fb21d8252efdc63e922f5b577770ce0b3ecd60948e46f6ac2a63b0ec
One packaged shared category catalog; eight generated write gates false.
