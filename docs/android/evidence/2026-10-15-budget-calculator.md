# Native budget amount calculator — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `5d63b612`.

Budget JPY/VND amount fields now open the native Compose calculator. It follows the actual Swift calculator keypad, operator precedence, integer-only positive commit, localized validation, clear/backspace/operator replacement and equals behavior. OK updates the editor draft; only explicit budget Save writes through the repository. Cancel preserves the original draft. Owned saveable expression state retains exact large amounts and closes across owner changes. Imported fractional currencies do not expose this integer-only calculator; their existing input semantics remain unchanged.

Shared core evaluation uses BigDecimal, bounded Foundation-style decimal coefficients/exponents and Long commits, with no Double conversion. The shared 36-vector contract is executed against both actual Swift MistiaAmountCalculatorLogic and Kotlin: precedence, recurring fractions, zero/negative/fractional results, division zero, Int64 boundary, >2^53, token sanitation and decimal range behavior. Six keypad-state tests cover editing/restoration invariants. These vectors validate their cases, not every possible Foundation Decimal operation. No Swift runtime behavior was changed.

Runtime TDD: evaluator stub failed the initial contract; added range vectors exposed another failure before the bounded-range implementation passed. All six keypad-state cases first failed against the stub. Three native budget cases first failed because the calculator entry point was absent, then passed after implementation. Final native test package includes screenshot capture and dark fontScale1.3. Final complete planning suite: **36/36 actual API36 emulator cases pass in119.426seconds**.

Direct self review compared `Mistia/Shared/CoreLogic/MistiaAmountCalculatorLogic.swift`, `Mistia/Core/UI/MistiaAmountCalculatorSheet.swift`, the shared currency input control and Swift budget editor. Static accessibility labels clear/deleteDigit were added to the sole xcstrings catalog in vi/en/ja; both platform outputs were regenerated. Screenshots inspected: `2026-10-15-budget-calculator/light.png` and `dark-font130.png`. Keys/title/cancel remain visible; long fractional display scrolls horizontally. This is scoped emulator visual evidence; full visual/iOS/accessibility/process-kill/Samsung parity remains pending.

Full **1390 JVM tests /133 suites**, zero failures/errors; Swift **610** (4 contract,137 data,469 core), Android lint/build, database/management/planning AndroidTest compilation, database/planning test APK assembly, contract15, both localization strict checks, SQLite7/3/11 helpers, packaged Room schemas1–6/bootstrap and whitespace pass.

Logs `/tmp/mistia-calculator-{model-red,range-red,range-green,input-red,core-focused,native-red,native-green}.log`; final `/tmp/mistia-budget-calculator-{full,swift,native-full}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-budget-calculator-v75.apk`, debug versionCode75: SHA256 `7d2b74d27638c57b0f20293d4048ad4b4a0f67498ebf720fba470139b50b5de1`.

Executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-budget-calculator-test-v75.apk`: SHA256 `fa02f135e5d5151d1e0bd9193a4652d281a3531c9d229b1e08168f4d5bfdeed5`. APK manifest/version/DEX verified.

Only API36 emulator connected; all10 flagsfalse; no Samsung/live Supabase writes/deploy/migration. Calculator integration for other forms, imported-currency audit, paid remote writes/undo/recovery/atomicity, fund usage/maintenance, card policy, APK3/4/RC and device gates remain open. Full goal stays active.
