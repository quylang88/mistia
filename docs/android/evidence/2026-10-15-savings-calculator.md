# Native savings calculator and Decimal parity corrections — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `8b60726b`.

Savings JPY/VND target/current fields now open the shared calculator. Its selected field and expression restore separately by owner/goal/currency/field. OK updates only that draft field, clears validation and closes; explicit Save persists through FinanceRepository. Cancel preserves signed current values and the untouched target. The calculator itself retains Swift's positive-only integer commit and ASCII digit sanitation (opening signed current -250 starts at250, Cancel preserves -250). Imported fractional currencies retain their existing input semantics without the integer-only tool.

Three actual native cases initially failed because both entry points were missing. Green workflows verify independent exact >2^53 target and current calculations, no record/outbox before Save, correct target/current persistence, signed-current cancel, negative-result rejection, selected-field restoration, no expression reuse when switching fields and owner reset. Complete planning suite **42/42 passes in183.634seconds** before the final arithmetic corrections below. That exact installed package was retained as the pre-precision test artifact. The final package reruns all9 calculator workflows across budget/bill/savings; **all9 pass in56.525seconds** on the final artifact.

Direct review expanded the shared actual Swift/Kotlin contract from36 to **86 vectors**. Found and corrected:

- A Decimal range failure followed by divide-zero must still report divisionByZero.
- Fixed38 significant-digit division differs from Foundation's coefficient×10^38 integer division,128-bit quotient fitting and pre-compaction exponent validation.35 direct runtime division probes found11 decimal differences before the correction; the contract was RED, then GREEN.
- Foundation's exponent normalization uses conservative whole16-bit limb headroom. Added6 normalization/exponent cases and a RED for the mismatched large normalized quotient. Addition/subtraction also follow that normalization, including tiny fractions around Int64.max and large cancellation. Four additive regressions now match Swift.
- Multiplication validates its operation exponent before compacting zeros;3 extra vectors exposed another RED and now pass.

The independent BigInteger/BigDecimal implementation follows the observed actual Swift model and the fixed [Foundation Swift6.2 arithmetic source](https://github.com/swiftlang/swift-foundation/blob/swift-6.2-RELEASE/Sources/FoundationEssentials/Decimal/Decimal%2BMath.swift). No floating-point accounting or Swift runtime change was added. Golden tests execute all86 results/errors/commit decisions against the actual Swift engine on this host; this is not exhaustive proof for every expression or future Foundation runtime.

Final full **1390 JVM /133 suites**, zero failures/errors; Swift610, app lint/build, database/management/planning AndroidTest compile, database/planning test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged schemas1–6/bootstrap and whitespace pass. Shared light/dark-font130 calculator images were inspected in APK75; no separate savings screenshot/full visual/Samsung/process-kill/live-sync proof is claimed here. Self review compared actual Swift savings fields, calculator UI/model and Foundation arithmetic; independent review remains pending.

Logs `/tmp/mistia-savings-calculator-{red-build,native-red,focused,native-full,native-final,86-full,86-swift-full,native-86-final}.log`; arithmetic `/tmp/mistia-calculator-{late-zero-red,division-red,normalization-red,product-red,86-green,86-swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-savings-calculator-v77.apk`, debug versionCode77: SHA256 `ba9c86a3725b273db93cf843ff0ff8c31c3e85c0b4e57aef094d54272cf56ae0`.

Final executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-savings-calculator-test-v77.apk`: SHA256 `c31afa467661884bb254100a481044e129a37cff2dfc6a844896a20b3df9590e`. Manifest/version/DEX verified.

Earlier42-case package `android/build/outputs/apk2/2026-10-15/mistia-planning-savings-calculator-pre-precision-test-v77.apk`: SHA256 `57c3665dd66d5ce017e5b77b802609e13340e5c26e98f85c674efc60411f9715`.

Final app APK installed with update-preserving `install -r` and cold MainActivity launch reports Status:ok on the isolated emulator (startup smoke only; no authenticated app workflow).

Only API36 emulator connected; all10 flagsfalse; no Samsung/live Supabase writes/deploy/migration. Installment/management/transaction calculator integration, imported-currency audit, coupled payment cloud writes/recovery, APK3/4/RC and device gates remain open. Goal stays active.
