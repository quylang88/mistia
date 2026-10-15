# Grouped native wallet opening balance — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `3a930069`.

JPY/VND wallet opening balance now groups thousands while typing, matching the actual Swift new-wallet currency input. State presentation for existing wallets also groups the preserved original value; metadata edits still cannot rewrite opening balance. Exact signed Long, blank→zero, invalid punctuation/overflow validation and imported fractional ISO-currency semantics remain intact. Existing planning grouping implementation moved unchanged into core model with thin planning delegates, so monetary forms share one presentation helper. No accounting/network/schema/static-copy change.

Runtime TDD:4 new wallet-state cases produced3 intended failures, then all12 state cases pass. Covers >2^53 JPY/VND, signed Long.min, blank/lone-minus/malformed/overflow, importedUSD12.34→1234minor and immutable existing balance. Management/planning focused JVM suites pass. Actual API36 full management **6/6 cases pass in16.816seconds**, including new real Room wallet workflow: grouped exact9007199254740993 before Save, no wallet before Save, same minor afterward, one wallet outbox and no ledger entry. Compile setup initially used the wrong enum name in the new fixture; corrected to LEDGER_WALLET without changing assertions.

Full **1394 JVM /133 suites**, zero failures/errors; Swift610, app lint/build, database/management/planning AndroidTest compile, database/management test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room schemas1–6/bootstrap and whitespace pass. Direct self review compared Swift new-wallet balance input and exact raw-minor parsing, plus unchanged planning helper/delegates. Imported non-JPY/VND cross-platform currency normalization remains an explicit audit gap. Existing-wallet current-balance/adjustment UX and calculator action are separate unfinished parity work; this slice does not complete wallet UI or APK1. No new screenshot/full visual/Samsung/process-kill/live-sync proof; independent review remains pending.

Logs `/tmp/mistia-wallet-grouped-input-{red,focused,native,full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-wallet-grouped-input-v79.apk`, debug versionCode79: SHA256 `8c61348b00641e165b7f84a3370b7a2862ce62e4987e9e08256e1fbc060631cf`.

Executed management test APK `android/build/outputs/apk2/2026-10-15/mistia-management-wallet-grouped-input-test-v79.apk`: SHA256 `9509ca92b0dfc1402edb70d57a96db52567094b265005e72dec9d1a892911ecd`. Manifest/version/DEX verified.

Only API36 emulator connected; all10 flagsfalse; no Samsung/live Supabase writes/deploy/migration. Continue wallet calculator/balance UI, card/transaction monetary forms/settings, coupled payment cloud writes/recovery/fund usage/maintenance, pending card policy, APK3/4/RC and device gates. Full goal stays active.
