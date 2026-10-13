# APK 2 recurring bill typed contract

Match all 28 fields and custom RemoteRecurringBillPlan encode/decode in Swift.
Explicit null clearing for schedule/deadline/autopay/pause/resume/dependencies;
Long amounts/versions, strict UUID/date/scalar types, legacy is_paused defaults
false only. Preserve unknown schedule raw values; resolved schedule falls back
recurring as RecurringBillPlan does. Derived explicit deadline matches Swift
local-day rules without changing saved wire values.

- [x] RED wire round trip, exact nullable clears/signed endpoints, required/
  malformed fields, legacy pause flag, unknown raw schedule and local deadline.
- [x] Minimal typed model and GREEN.
- [x] Full checks, direct Swift review/focused planning tests, contract/generators,
  evidence/progress and commit. Continue due occurrences/scheduling foundation,
  then repository pause/resume/archive guards, push and native forms/payment.

All seven write gates stay false. No production calls or deployments.
