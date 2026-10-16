# Exact expense/income reporting conversion persistence — 2026-10-16

Branch `codex/android-apk2-4-parity`; baseline `9e286128`; APK92.

TransactionDraft now accepts an explicit reporting currency/amount for ordinary income and expense. A different target requires a positive exact Long amount and conversion mode; APP_RATE requires a positive supplied rate and valid optional date, while MANUAL permits nil rate/date and defaults new reporting provider to manual. The record/outbox keep source wallet money separate from reporting money. An explicit same-source target clears old reporting pair and FX metadata. Ordinary internal transfer clears prior expense reporting pair and rejects incoming reporting inputs, matching Swift assignment. Shared metadata validation also retains existing internal-transfer requirements.

Compatibility for existing callers is explicit: when reporting input is absent, an existing complete conversion can survive a metadata edit only while kind/status/amount/source wallet/source currency remain unchanged. A monetary edit without refreshed reporting input is rejected, avoiding stale converted money. These guards do not create a replacement exchange rate or silently clear imported conversion data. Settlement reportingExpense/reportingIncome overrides and investment/family workflows remain separate.

Direct Swift: `Mistia/Features/Transactions/TransactionEditorSheet.swift`3160–3197 validates manual/app reporting conversion;3918–3962 assigns reporting fields and metadata for income/expense;3980–3998 clears reporting on internal transfer. New input uses the existing serialized reporting fields/nullable contract. No Room/schema/network/Swift runtime change or external query.

TDD: added API fields without behavior, then21 model cases produce9 intended runtime REDs for missing reporting pair/metadata, incomplete inputs, invalid app rate/date, same-currency/transfer clearing, stale money edits and metadata preservation. Three actual Room cases first produce3 intended assertion REDs for absent expense/income reporting money and retained stale reporting after same-currency change. Focused cases then pass. Independent read-only reviewer initially found one Minor evidence gap: tests had checked returned records/outbox but did not read transaction rows back. All3 now compare persisted observed owner transactions to the fully asserted record; manual balance is calculated from observed wallets/transactions. Reviewer confirms no remaining finding.

Final **1435 JVM/134suites**, zero failures/errors; **182/182 full Room native cases in3.201seconds** and **17/17 full transaction native cases in54.244seconds** pass on API36 emulator. Native controls cover source9007199254740993/reporting18014398509481986, unchanged original wallet/currency, exact source balance9214364837600034814, explicit nil manual metadata, income app snapshot/provider/date, same-currency clearing, owner isolation and baseVersion9007199254740993. Swift610 (4+137+469), lint/build, database/management/planning/transaction AndroidTest compile, database/transaction APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room schemas1–6/bootstrap and whitespace pass.

Logs `/tmp/mistia-reporting-fx-{model-red,native-red-build,native-red,focused,native-focused,full,swift,readback-build,room-native-final,transactions-native-final}.log`. Final executed database artifact includes added readback assertions, rebuilt after the first full build.

Archived metadata/manifest/DEX-verified artifacts in `android/build/outputs/apk2/2026-10-16/`:

- `mistia-0.2.0-apk2-reporting-fx-model-v92.apk`, versionCode92, SHA256 `eea9aaaf3f0766295a6efa3a95bcfc87f30497b587d4a94d0292e6447e4f9b3b`.
- Executed `mistia-database-reporting-fx-model-test-v92.apk`, SHA256 `19e4606288669ef691e718bc31dbe23a4945d6b6e82a68e949d09fed88dd0dc1`.
- Executed `mistia-transactions-reporting-fx-model-test-v92.apk`, SHA256 `512eef12ceb8b326aeae59744e7c265085a9472742db1c1c2794caa35fae951b`.

App92 not installed; latest preserving-data update/cold-launch smoke90. API36 only; no Samsung/live Supabase/production write/deploy/migration. All10 cloud flagsfalse; Room6/SwiftDataV11/iOS751 unchanged. This slice proves the real persistence/API contract; the native reporting form and device currency preferences still need connection next. Imported-currency normalization, investment allocation, editor-opening version tokens, prior management startup concern84, full APK1–4 and RC remain open. Goal stays active; continue native reporting form and currency settings.
