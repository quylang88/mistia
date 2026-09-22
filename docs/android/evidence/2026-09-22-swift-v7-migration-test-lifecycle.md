# Swift V7 migration regression — 2026-09-22

Base commit: `afce6aa`. This prerequisite fixes the Swift gate recorded as
failing in the Android handoff; it does not change a production migration,
schema, or Android behavior.

## Root cause

`testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees` created a V7
`ModelContainer`, left its scope, and immediately opened the same SQLite URL
with the current schema and staged migration plan. A lexical `do` block does
not guarantee immediate release of the SwiftData/CoreData container and
persistent-store coordinator. In an isolated process this race produced
CoreData error 134504 (`unknown coordinator model version`). Running the full
class usually hid it because preceding migration tests changed release timing.

The fixture now creates and saves the V7 store inside `autoreleasepool`. This
deterministically releases the legacy container before the same URL is opened
for migration. The migration plan, assertions, and failure behavior are
unchanged; no test was skipped or weakened. The nearby
`insufficientPosition` diagnostic remains the expected result of the separate
atomic oversell-rejection test.

## Verification

- Before the fix, an isolated fresh-scratch run failed with CoreData 134504.
- After the fix, the same isolated fresh-scratch command passed: 1 test,
  0 failures.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  passed all targets: 4 + 133 + 460 = 597 tests, 0 failures.
- Diff review confirms the only Swift change is the fixture lifetime boundary
  (`do` to `autoreleasepool`); production persistence code is unchanged.
