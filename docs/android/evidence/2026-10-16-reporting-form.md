# Native reporting conversion form — 2026-10-16

Branch `codex/android-apk2-4-parity`; baseline `b31ec425`; APK93.

Income/expense now use a separate reporting amount bound to the supplied primary currency. Manual conversion exposes the converted amount and JPY/VND calculator, preserves exact Long values and writes no rate/date, provider manual. APP_RATE calculates from the current real pair while hiding extra amount/rate inputs, matching Swift. Source, destination and reporting calculator drafts remain separate; owner/record/kind/wallet/currency/mode/primary scope and cancellation checks preserve draft isolation. The public primary parameter defaults to JPY; actual device settings integration is the next slice.

Direct Swift comparison: TransactionEditorSheet manual-only converted field, reporting validation and assignments; income/expense source and reporting money remain distinct. Existing automatic-transfer tests now assert absence of the extra fields while retaining exact persisted amount/snapshot assertions.

TDD: eight initial state runtime REDs and eight actual native REDs; independent review found old reporting money could be relabeled under a different primary currency (VND source, USD200minor becoming JPY2). Added two JVM and two native runtime REDs for that path and currency-code normalization. Reporting text now carries its original currency, mismatched manual money clears on open and is rejected at draft conversion until explicitly re-entered. Same-source primary clears stale reporting metadata. Owner/primary saved-state envelopes prevent cross-scope restoration. Reviewer re-reviewed fixes and reported no remaining Critical/Important/Minor finding.

Eleven new native workflows cover exact >2^53 manual reporting/calculator/persisted Room/outbox/balance, inverse automatic income, edit restoration, primary/owner switch isolation, missing automatic rate/manual recovery, transfer automatic fields, busy save and light/dark fontScale1.3. Legacy automatic-preview assertions were updated to the directly observed Swift UI. A fixture initially expected a substring with a full-text assertion; corrected to the complete localized label without weakening any money assertion.

Visual QA exposed Android's deprecated-target warning over the standalone library test activity: its manifest targeted26 although app target36. Transaction testOptions now explicitly target36; aapt and installed-package dumpsys confirm36. A stale warning belonging to the previous own-fixture installation persisted after update; its UIAutomator-confirmed OK button was dismissed once, without suppressing warnings or resetting app/device data. Fresh target36 visual run passes; all four new PNGs were inspected with no overlay, readable large exact values, accessible actions in light/dark at130%. Earlier obscured screenshots are not physical UI proof. A temporary accessibility root probe returned null in the runner and was removed; that diagnostic failure is not feature RED evidence. Other modules' test targets and the older management startup concern remain separate open RC work.

Images in `reporting-form-2026-10-16/`: reporting and calculator, light/dark, font130. Screenshots are emulator fixture evidence, not Samsung or authenticated app end-to-end proof.

Full **1445 JVM/134suites**, zero failures/errors; Swift610 (4contract+137data+469core); lint/build, database/management/planning/transaction AndroidTest compile, database/transaction APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room1–6/bootstrap and whitespace pass. No Room production changes; full182 Room native last passed in92. Full final **28/28 transaction native cases in93.740seconds** pass on the target36 executed artifact.

Logs `/tmp/mistia-reporting-form-{state-red,native-red-build,native-red,focused-build,native-first,target-red-build,target-native-red,full-final,swift,verified,target-sdk-build,visual-native-final,native-final}.log`. The initial final28 run had27 passes and the full-label fixture assertion failure above; final artifact includes that correction and target36.

Metadata/manifest/DEX-verified archives `android/build/outputs/apk2/2026-10-16/`:

- `mistia-0.2.0-apk2-reporting-form-v93.apk`, versionCode93, SHA256 `09fa56f95a988284e2cf4c20d425168127a07412c11a0bf3dfe3790478679486`.
- Executed `mistia-transactions-reporting-form-test-v93.apk`, target36, SHA256 `715d80d985f44ed164eeed84efebb1222cb033513056aa4d933de1d4a1af61ab`.

App93 installed with preserving-data install-r; cold MainActivity launch Status ok in896ms and installed version93 confirmed. This is launch smoke only. API36 only; no Samsung/live Supabase/production write/deploy/migration. All10 cloud flagsfalse; Room6/SwiftDataV11/iOS751 unchanged. Currency settings, enabled-currency consumers/aggregates, imported currency, investment allocation, editor-opening baselines, prior management startup concern and full APK1–4/RC remain open. Goal stays active; continue currency preferences/settings.
