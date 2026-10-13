# Swift V7 migration plan isolation — 2026-10-13

Prerequisite discovered during full validation of bill currency rules. Base: `ee64a13`.

## Failure and diagnosis

The full SwiftPM suite failed in `testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees` with CoreData 134504, unknown coordinator model version. A fresh scratch build reproduced it. Ten isolated runs of the same binary failed seven times. Weak lifetime probes confirmed both legacy container and context were already released, so the earlier autoreleasepool fixture fix alone does not explain this regression on macOS 27.0.1 / Xcode 27.0.

Diagnostic comparison of source and regenerated SQLite model metadata identified only `LedgerTransaction` as different. Decoding the local synthetic stores' compressed `Z_MODELCACHE` archives showed the regenerated entity missing five current fields: `reportingExpenseMinor`, `reportingIncomeMinor`, `settlementGroupID`, `settlementObligationID`, and `settlementRoleRawValue`. That shape matches the frozen V5 ledger entity. The comprehensive plan registers both frozen V4/V5 and current ledger classes under the same entity name; the V7 source schema uses the current class. All diagnostic source edits were removed.

## Change and regression

`LaunchState.openContainer` now selects `MistiaInvestmentMigrationPlan` for existing V7/V8 stores. Its registered schemas are V7–V11 only. It reuses the same four custom investment stages, including validation, FIFO rebuild, and cash allocations. Legacy V4 handling, schema definitions, and lightweight opening of other store versions remain as before. No retry, store deletion, skipped test, or weakened validation was added.

The V7 fixture additionally stores an independent ledger record with non-null values in all five affected fields and verifies their preservation. Investment funding ledger records retain their existing recalculation assertions; settlement markers are deliberately tested on the independent record because funding rebuild assigns its own investment role.

The enhanced fixture failed with 134504 using the old comprehensive plan (runtime RED). The isolated investment plan passed the original fixture 20/20 process runs, then passed the enhanced fixture and full SwiftPM suite (runtime GREEN).

## Validation

- Full SwiftPM: 4 feedback + 133 data support + 464 core = 601 tests, zero failures.
- Focused source-store migration and oversell atomic rejection remain exercised in the full suite.
- Independent static review: no actionable P1/P2; confirmed exact migration stage reuse and V7/V8-only routing.
- Final enhanced fixture: 20/20 independent process runs pass. Focused migration class passes all 16 tests in both normal and fresh scratch builds, including oversell atomic rejection.
- iOS generic simulator app build: BUILD SUCCEEDED.
- Android full JVM/Room/UI compile/lint/assemble: BUILD SUCCESSFUL (724 tasks; cached checks appropriate to this Swift-only slice). Existing 601 JVM test results remain green.
- Android contracts (15 entities), Android localization and strict Swift localization generation checks pass; `git diff --check` passes.
- Xcode-generated CFBundleVersion bump was restored to its original value; no incidental build metadata change.
- No live cloud or production mutation. ADB inventory empty; no Samsung verification.

Local diagnostic logs: `/tmp/mistia-v7-clean-build.log`, `/tmp/mistia-v7-lifetime-repeat.log`, `/tmp/mistia-v7-schema-compare.log`, `/tmp/mistia-v7-modelcache-repeat.log`, `/tmp/mistia-v7-ledger-regression-red.log`, `/tmp/mistia-v7-isolated-plan-repeat.log`, `/tmp/mistia-v7-isolated-plan-full.log`.
