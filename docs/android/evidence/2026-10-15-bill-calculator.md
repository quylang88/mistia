# Native bill amount calculator — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `67558e3e`.

Recurring/one-time bill JPY/VND amount fields now open the shared native calculator, matching the actual Swift PlanningBillEditorSheet MistiaCurrencyInputField action. It preserves optional blank amount, exact Long minor parsing and owned editor state. Calculator OK updates only the draft and resets validation; explicit bill Save writes through FinanceRepository. Cancel keeps the original optional input. Focus clears before opening; busy disables the entry. Expression scope includes owner/bill/currency, and saved opening state resets on owner/record changes. Imported fractional currencies retain existing input behavior without exposing this integer-only tool.

Runtime TDD: all3 actual emulator cases failed at missing `bill.amount.calculator`, then all3 pass in21.85seconds. Real in-memory Room verifies exact9007199254740993+2→9007199254740995, no bill/outbox before Save and one afterward; fractional rejection then Cancel retains blank and persists null; saved expression restores exactly and owner change removes tool/draft with no record written. Existing calculator36 Swift/Kotlin vectors and six input-state regressions remain green.

Full **1390 JVM /133 suites**, zero failures/errors; Swift610, app lint/build, database/management/planning AndroidTest compile, database/planning test APK packaging, contract15, both localization checks, SQLite7/3/11, packaged schemas1–6/bootstrap and whitespace pass. Direct self review compared the actual Swift bill input and calculator callback behavior. Shared calculator light/dark-font130 images were inspected in APK75; no separate bill screenshot/full visual/Samsung/process-kill/live-sync proof is claimed here. APK75 full planning36 covers its artifact; changed bill calculator3 executed on this artifact.

Logs `/tmp/mistia-bill-calculator-{red-build,native-red,focused,native-green,full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-bill-calculator-v76.apk`, debug versionCode76: SHA256 `481ede98a21b41ff078015e386d5754e22ace6789f89262017a98dd7b9c4edc5`.

Executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-bill-calculator-test-v76.apk`: SHA256 `84b1d03eec9c31291904e695797bba3c067dd1ebce01c0a560620694e2af1135`. Manifest/version/DEX verified.

Only API36 emulator connected; all10 flagsfalse; no production write/deploy/migration. Savings/installment/other calculator integration, imported-currency audit, coupled payment cloud writes/recovery, APK3/4/RC and device gates remain open. Goal stays active.
