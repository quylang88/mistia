# APK 2 bill scheduling and due occurrence foundation — 2026-10-13

Typed all 15 RemoteDueOccurrenceRecord fields, exact signed Long snapshots/
versions, explicit nullable clears and strict required/optional scalar/UUID/
instant decoding. Unknown raw enums and legacy month strings remain lossless;
resolved source/status use Swift creditCard/pending fallbacks.

Owner-scoped recurring bill rows match PlanningLogic recurringBillDueItems,
recurringBillWindow, autoPayDate/normalizedAutoPayDate, preferredOccurrence and
hasUnpaidBillCyclesThroughCurrentMonth. Covers local month/frequency and first/
resume anchors; month-end/leap-day clamping; deadlines extending into next month;
one-time exact timestamps and optional deadline; auto-pay inclusive window;
paused exclusion; archived paid-history preservation bypassing changed schedule;
first terminal duplicate preference and occurrence amount/transaction snapshots.
Foreign/deleted bills and occurrences cannot contribute to the projection.

Unpaid archive guard checks scheduled cycles through current month, capped at
paused month where appropriate; skipped still counts unpaid. It advances by
frequency rather than scanning irrelevant monthly gaps, with the same result
as Swift. Resumed plans start at resume month without backfilling paused months.
No records/history are mutated by these pure calculations.

TDD observed missing APIs RED. Ten new focused tests pass (three wire, seven
scheduling) using direct Swift golden cases. An initial nullable Long assertion
used an Int literal and was corrected after inspecting its exact failure; no
production behavior fix is claimed for that test fixture correction. Direct
local review against Swift source and 52 PlanningLogic tests completed.

Full Android testDebugUnitTest, Room test compilation, lintDebug and assembleDebug
passed (713 tasks/37s); 458 JVM tests across 64 suites, zero failures.
52 Swift PlanningLogic tests, contract15, Android/strict Swift localization
checks and git diff --check pass. All seven write gates false; ADB empty.
No emulator/Samsung bill behavior, production request/write, migration/deployment
or independent final reviewer approval is claimed.

Next offline bill save/pause/resume/archive repository and outbox; then gated
push, native bill form/payment and due maintenance/notifications. The rest of
APK2–4 and final physical/UI gates remain incomplete.
