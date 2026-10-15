# Native installment cycle calculator — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `c82f94de`.

Installment metadata amount-per-cycle now opens the shared native calculator, matching the actual Swift installment editor currency input action. The existing field uses grouped raw integer minor units for all currencies, so calculation preserves that unit and uses the existing ISO formatted preview. No major-unit conversion is introduced. OK changes only the draft; explicit Save updates plan metadata/outbox. Cancel preserves original text. Owner/id/currency expression state restores, identity or owner changes close the dialog and clear old draft; busy disables entry and focus clears before opening.

Runtime TDD: all4 new actual native cases failed on missing entry, then **15/15 actual API36 cases pass in63.073seconds** (calculator4 plus existing installment editor11). Real Room verifies exact >2^53 calculation and save/outbox, unchanged ledger/wallet; imported USD1375minor÷5→275minor with existing$2.75 preview, unchanged record/queue before Save; divide-zero rejection and Cancel; expression restoration plus separate id/owner reset. Imported non-JPY/VND formatting parity with Swift remains an explicit audit gap; the USD test verifies preservation of the existing Android ISO presentation/raw-minor semantics only.

Full **1390 JVM /133 suites**, zero failures/errors; Swift610 including all86 actual Swift/Kotlin calculator vectors, app lint/build, database/management/planning AndroidTest compile, database/planning test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged schemas1–6/bootstrap and whitespace pass. Direct self review compared actual Swift amountPerCycle input and shared calculator callback with Android metadata save/owned saver. Shared light/dark-font130 calculator screenshots were inspected in APK75; no separate installment screenshot/full visual/Samsung/process-kill/live-sync claim. Independent review remains pending. Calculator wiring for early payment and other forms remains separate; ordinary due payment retains its existing amount behavior.

Logs `/tmp/mistia-installment-calculator-{red-build,native-red,focused,native-green,full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-calculator-v78.apk`, debug versionCode78: SHA256 `4829f8965703f8b35ae70e498d6e6fdb756d815b0e147f08bdbca8da8e7ff169`.

Executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-installment-calculator-test-v78.apk`: SHA256 `fdbe9884307c75fa328a11ac8af3c62a08b13d3a0c6913436b01b7ab68b7e07f`. Manifest/version/DEX verified.

Only API36 emulator connected; all10 flagsfalse; no Samsung/live Supabase writes/deploy/migration. Management/transaction calculator and currency/settings audit, coupled paid writes/recovery/fund usage/maintenance, pending card policy, APK3/4/RC and full device gates remain open. Goal stays active.
