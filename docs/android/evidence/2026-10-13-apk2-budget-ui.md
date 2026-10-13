# APK 2 native budget workflow — 2026-10-13

## Implementation
Monthly native hierarchy, exact spending/FX projection, progress/pace colors,
parent allocation, category icons shared with management, localized frozen
labels, legacy live-category fallback and carried-forward plan selection.
Compose editor provides exact minor input, category hierarchy/search/recent/
favorites, month/rollover, owner-scoped saved drafts, save failure retention,
unsaved dismissal confirmation and date-sensitive archive/delete confirmation.
Original record payload is captured to preserve edit identity across repository
changes; missing records fail rather than silently recreating them.

Direct Swift comparison: PlanningLogic.activeBudgetPlans/budgetBranchRows/
budgetPaceAssessment; PlanningSupport.reportedExpenseAmount; PlanningEditors
budget form/actions/frozen labels; MistiaCategoryPicker recent/favorite ordering;
TransactionLogic adjustment, installment, loan and card-payment exclusions.
Accounting uses Long with BigInteger/BigDecimal intermediate operations;
Float is limited to rendering progress. Summary currently uses JPY; app-wide
currency settings are still later RC work. Family aggregation is later APK 3;
unavailable family data uses the personal fallback.

## Approved product decision and TDD
User explicitly selected “Mỗi nhánh chỉ dùng một tiền tệ; chặn lưu khác tiền tệ”.
This deliberately tightens iOS behavior, which sums raw mixed-currency minors.
Repository blocks mismatches before any record/outbox mutation. Form inherits
branch currency, disables alternatives in established branches and clears typed
amount when currency changes. Currency checks include current carried continuity
and future anchors, preventing an earlier new budget from conflicting later.
Existing imported mixed-currency records are not rewritten. No iOS runtime
behavior or server schema changed.

Observed RED/GREEN: projection/pace API; legacy month normalization, live parent
metadata, canonical loan exclusion; legacy allocation cap; scoped restoration;
frozen editor paths; quick picker ranking; same-month, carried and future branch
currency rejection; currency-changing input clearing. All now pass.
Independent reviewer identified frozen-path and mixed-currency problems and
future-anchor loophole; fixed with regression tests. Reviewer hit service usage
limit during final re-review, so no completed independent final approval is
claimed. Final local diff/Swift comparison and regression checks completed.

## Validation
- Full Android testDebugUnitTest, Room Android-test compilation, planning
  Android-test APK assembly, lintDebug and assembleDebug: BUILD SUCCESSFUL,
  742 tasks, 38s. 387 JVM tests across 56 suites, zero failures.
- Swift PlanningLogicTests: 52/52 passed using full Xcode.
- 15-entity contract, Android localization and strict Swift localization
  generation checks passed; git diff --check passed.
- versionCode 6, all six financial cloud-write flags remain false.
- Compose instrumentation tests compile: actual Room-backed create/edit/delete,
  failed-save retention and dismissal confirmation in dark 1.3 font scale.
  ADB has no connected device, so these UI tests and screenshots have NOT run.
  Prior slice Room emulator evidence remains valid but does not prove UI.
- No Samsung verification, live Supabase write, migration or deployment.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-budget-ui-v6.apk
SHA-256: 54fdd0d9b3b0972b53c2271e4bb7ad6a43417c03ad50d79a725ac51bf80a1454

APK 2 savings/bills/installments/statements and APK 3–4 remain incomplete.
UI visual/emulator/Samsung checks remain explicit final device gates.
