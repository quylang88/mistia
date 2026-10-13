# APK 2 recurring bill typed contract — 2026-10-13

Added all 28 recurring_bill_plans schema/RemoteRecurringBillPlan fields with
explicit nullable clears for category/amount/schedule/deadline/auto-pay/wallet/
pause/resume/device/deletion. Long money/version values remain lossless; strict
UUID/instant/scalar decoding rejects malformed optional fields instead of
silently defaulting. Only legacy missing/null is_paused defaults false, matching
Swift custom decoder. Valid ISO8601 offsets remain lossless.

Unknown/empty/legacy pausedRecurring schedule raw values are retained; resolved
schedule defaults recurring except exact oneTime. Resolved paymentStartDay uses
dueDay fallback. Resolved explicit deadline matches RecurringBillPlan: recurring
requires differing due/payment days, one-time requires a later local calendar
day with both dates present. No schedule/pause wire values are rewritten.

TDD missing typed model RED followed by GREEN. Six tests cover complete key set,
nullable clears, signed endpoints/large version, all populated independent
schedule/auto-pay/pause/resume fields, required fields, malformed optional fields,
legacy defaults, unknown raw schedule and Tokyo deadline day boundaries.
Direct local review against RemoteRecurringBillPlan CodingKeys/custom encoder/
decoder, RecurringBillPlan and PlanningBillScheduleKind completed. No independent
reviewer approval is claimed while review service is usage-limited.

Full Android testDebugUnitTest, Room Android-test compilation, lintDebug and
assembleDebug passed (713 tasks/39s). 448 JVM tests across 62 suites, zero failures.
52 Swift PlanningLogic tests pass; contract15, Android/strict Swift localization
generation and diff checks pass. No ADB device. All seven existing write flags
remain false; this typed slice adds no bill cloud mutation path. No emulator/
Samsung bill execution, live Supabase write, migration or deployment.

Next: due occurrence contract and scheduling/payment window foundation, then
repository pause/resume/archive safeguards, gated push and native bill forms.
Bills, installments/statements, remaining APK3–4 and final UI/device gates remain
incomplete. Previous archived native savings APK v9 is not a bill-complete build.
