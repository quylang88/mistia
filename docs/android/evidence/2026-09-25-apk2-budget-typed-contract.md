# APK 2 budget typed contract evidence — 2026-09-25

This first APK 2 slice establishes the native budget cloud and allocation
contract. It does not add persistence, UI or a cloud-write path.

## Scope and parity

- `BudgetPlanRecord` covers all budget-plan fields published by the shared
  cloud schema, including hierarchy snapshots, family-spending scope,
  archival/tombstone metadata and signed 64-bit minor units/sync versions.
- Payload generation emits explicit JSON nulls for every cleared optional.
  Cloud decoding requires the same non-optional fields as iOS; only the legacy
  `includes_family_spending` field defaults to `false` when absent.
- UUIDs and UTC timestamps are validated during decode. Required strings must
  be non-empty, while optional localized snapshot strings preserve an empty
  value exactly as Swift `decodeIfPresent(String.self, ...)` does.
- Allocation snapshots prefer the frozen category identity over the current
  relation and derive the branch from the frozen parent/role metadata.
- Parent and child budget limits are checked within the selected local calendar
  month and branch, excluding the budget being edited. Totals use exact
  `BigInteger` arithmetic, so signed-64 overflow cannot make an invalid child
  allocation appear valid; diagnostic values alone are clamped to `Long`.

## TDD and review trail

- RED 1: the new model tests did not compile before the typed record,
  round-trip and allocation-validation contracts existed.
- GREEN 1: payload round-trip, explicit nulls, signed-64 boundaries,
  parent/child constraints, month/branch filtering and edit exclusion passed.
- RED 2: review regressions failed because live category identity won over its
  snapshot, saturating addition accepted an overflowing child total, and
  missing required cloud fields silently became empty/zero/false.
- GREEN 2: snapshot precedence, exact arithmetic and strict required decoders
  passed, including legacy family-scope fallback.
- RED 3: an empty optional snapshot string decoded on iOS but threw on Android.
- GREEN 3: optional strings now preserve empty values without weakening
  required string, UUID or timestamp validation.
- Two review passes resolved all reported findings; the final narrow review
  reported no findings. `git diff --check` passed.

## Automated release gate

- Full Android command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 3 minutes 21 seconds (`709` tasks).
- Result XML: 318 JVM tests across 51 suites. Room Android-test source
  compilation, Android lint and debug APK assembly completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains: the Xcode license is not accepted and Command Line Tools do not
  provide `xcstringstool`; the full audit is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`afa20949fb08fefa0b2959e8e65ce95cf73aa4cb6457ff90a1d9f74cda2d5dfa`.
The APK contains 653 files. Generated debug `BuildConfig` confirms the global,
category, wallet, credit-card and transaction cloud-write flags remain `false`.

## Verification boundary

`adb` is unavailable, so no emulator or Samsung behavior is claimed. No
production Supabase request, write, migration, RLS/RPC/Edge Function change or
deployment occurred. Budget Room persistence, outbox/push coordination and UI
remain later APK 2 slices; APK 2–4 remain incomplete.
