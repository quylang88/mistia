# APK 2 savings goal typed contract — 2026-10-13

Matched all 16 fields of contracts/schema/cloud-entities.json savings_goals and
Swift RemoteSavingsGoal. Exact signed Long money/version, explicit nullable
wallet/device/deletion fields, strict scalar/UUID/instant validation. Valid
ISO8601 offsets remain lossless, matching Swift decoding and existing records.

Pure projection filters owner/archive/tombstone, uses inclusive local target
month, exact ceiling contribution and ratio/date/localized-name sorting. It
retains manually saved currentSavedMinor rather than deriving wallet balance,
as Swift PlanningLogic.goalRows does. BigInteger prevents subtraction overflow
and Double precision loss; only an unrepresentable displayed monthly requirement
is clamped to Long.MAX_VALUE. Original cloud values remain lossless.

TDD RED: missing typed model/projection; malformed sort order exposed exception
classification; valid offset timestamp regression failed before parser fix.
Five focused tests now pass, including Tokyo month rollover, signed endpoints,
values above 2^53, completed goals and exact progress sorting. Direct local
review against RemoteSavingsGoal/goalRows/monthsRemaining completed. Independent
review service was usage-limited in preceding slice; no independent final
approval is claimed here.

Full Android testDebugUnitTest, Room test compilation, lintDebug, assembleDebug:
BUILD SUCCESSFUL, 713 tasks/33s; 392 JVM tests across 57 suites, zero failures.
52 focused Swift PlanningLogic tests, 15-entity contract, Android and strict
Swift localization generation and diff checks pass. All six write flags false.
No ADB device, emulator/Samsung execution, Supabase write, migration/deployment.

Savings offline repository, gated push, summary and native UI remain next;
other APK 2–4 scope remains incomplete. This slice adds no cloud write path.
