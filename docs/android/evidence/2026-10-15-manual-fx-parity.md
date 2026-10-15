# Amount-only manual FX parity — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `ad9c2e7d`; APK89.

Direct Swift audit (`Mistia/Features/Transactions/TransactionEditorSheet.swift`1277–1304,3207–3224) found manual internal transfers ask only destination money and persist nil rate/date with provider `manual`. Android previously required an extra rate. Manual editor now accepts an exact positive destination amount without a rate, removes the extra input and clears stale rate/date metadata on save. APP_RATE still requires a positive actual rate and preserves its snapshot/provider/date; its rate preview stays read-only. Raw model drafts continue retaining valid supplied legacy manual metadata, outside editor normalization.

TDD: core model12/repository14/editor28 focused cases first produce4 intended JVM failures (nullable manual rate, repository explicit null payload, blank rate form and stale metadata normalization). APP_RATE missing-rate control already passes. Two native Compose cases initially fail for inability to save with blank rate and unexpected extra rate field. One older manual form expectation was updated from a stored rate/date to nil to match the direct Swift contract; all source/destination money assertions retained. Final **1425 JVM/134suites**, zero failures/errors; **164/164 actual Room tests in3.002seconds** and **11/11 transaction native tests in25.971seconds** pass on API36 emulator, including >2^53 source/destination pairs, owner restoration/callback guards and app-rate regressions.

Swift610 (4contract+137data+469core), app lint/build, database/management/planning/transaction AndroidTest compile, database/transaction APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room schemas1–6/bootstrap and whitespace pass. Independent read-only reviewer `review_manual_fx89` reports no Critical/Important/Minor issue.

Local Supabase contract audit used the Supabase skill and current official changelog index, without any live query or write. Migration `20260527130921_multi_currency_transactions.sql` declares these FX columns nullable. The positive-rate trigger in `20260809090000_investment_domain.sql` is limited to investmentTransfer settlement rows and returns for ordinary transfers. Android generic sync carries the serialized explicit JsonNull fields. No schema/network/SDK change or migration is needed or made; this is not live Supabase verification.

Logs `/tmp/mistia-manual-fx-{jvm-red,native-red-build,native-red,focused,full,swift,room-native,transactions-native}.log`. The focused log includes the obsolete manual-rate expectation failure before its contract correction; final full/native logs are green.

Archived metadata/manifest/DEX-verified APKs under `android/build/outputs/apk2/2026-10-15/`:

- `mistia-0.2.0-apk2-manual-fx-parity-v89.apk`, versionCode89, SHA256 `e65820b909c290300aa0fabf93850a35d0ae5f375b4603f14c7d99da1e76d5bb`.
- Executed `mistia-database-manual-fx-parity-test-v89.apk`, SHA256 `dda3c3a525cd58450cfa06cb0520fc7a5c5cc102c17366fbce4296447626f259`.
- Executed `mistia-transactions-manual-fx-parity-test-v89.apk`, SHA256 `36aa4aa7e152e9c36f554e94b533cb0a681d104f3b0149f731fd18d7040c06e7`.

Only API36 emulator connected; app89 not installed, latest update/cold-launch smoke85. No Samsung/live cloud/production write/deploy/migration. All10 flagsfalse, Room6/SwiftDataV11/iOS751 unchanged. Management initial row-delivery timeout from84 remains unproven; no remediation claim. Ordinary transaction calculator, reporting FX, transaction atomic-save races, remaining APK1–4 and RC remain open. Goal stays active; continue calculator next.
