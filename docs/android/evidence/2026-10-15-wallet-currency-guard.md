# Wallet currency edits with live ledger history — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `32fa23f9`.

Regular-wallet currency edits now match Swift ManagementWalletEditor.canEditWalletCurrency: a live unarchived transaction referencing the wallet as source OR destination locks currency. Unchanged-currency metadata edits still work; unrelated/other-owner/archived/consistently deleted rows do not lock it. Raw linked rows with malformed archive flags, conflicting/invalid deletion clocks or foreign payload identity within the owner partition stay conservatively held. No transaction status filter was invented.

The repository routes actual currency changes through a dedicated LocalStore capability that fails closed by default. Room compares the exact raw wallet baseline and reads current owned ledger references inside the same transaction as wallet/outbox writes, fences current owner before/after and rolls back on change. It preserves the original raw opening-money field and requires coherent envelope/pending/payload sync versions, preventing corrupt data from silently becoming zero or a forged base version. Same-currency saves retain their existing route. Complete existing-wallet currency edits require a loaded owner-stamped ledger in ManagementScreen; controls stay disabled while loading/history exists. Stale enabled forms get a localized currencyInUse rejection with unchanged record/queue. Sole xcstrings catalog gained one vi/en/ja key and outputs were regenerated; no Swift runtime change.

Runtime TDD:

- Actual original Room4 cases produced2 intended failures (source/destination currency edits incorrectly succeeded). Then4 passed. Expanded final8 covers current-history arrival after baseline capture, newer raw wallet/queue preservation, owner-change rollback, and corrupt/missing opening money or disagreeing wire clock. Corrupt-money review added another actual RED before raw-money/version guards passed.
- Nine JVM policy cases pass after6 initial REDs and one invalid-clock regression RED. Covers both links, owner/entity, archived/deleted, malformed flags/tombstones, missing fields and UUID case.
- Native UI initial RED showed VND enabled despite linked history. Final2 workflows verify lock→history removal→unlock→exact save, and stale enabled UI rejection with localized message/unchanged wallet/outbox.
- Full native management reruns exposed a startup regression: Room emitted the correct wallet with lifecycle RESUMED, while UI stayed at No wallets yet. Diagnostic traces/tree captured the case. Stable owner/repository-keyed wallet/category/card/ledger Flow instances fixed the reproduction; lifecycle-aware ledger collection retains the owner envelope. Temporary traces and attempted snapshot-flush workaround were removed; original5-second navigation and monetary assertions remain intact.

Final **1405 JVM /134 suites**, zero failures/errors; Swift610/86calculatorvectors, app lint/build, database/management/planning AndroidTest compile, database/management test APK assembly, contract15, both localization checks, SQLite7/3/11, schemas1–6/bootstrap and whitespace pass. **130/130 actual Room cases pass in2.724seconds** on API36 emulator, and final **13/13 management cases pass in36.546seconds**. Direct self review compared actual Swift live/unarchived source/destination rule, guarded persistence, owned loading and stale UI paths. Independent/full visual/Samsung/process-kill/live-sync verification remains pending.

Logs `/tmp/mistia-wallet-currency-{native-red,policy-red,clock-red,ui-red,corrupt-red,database-final-v2,management-final-stable,final-stable-full,swift}.log`; startup diagnostic `/tmp/mistia-wallet-currency-{management-diagnostic-v5,initial-tree,management-stable}.log` (tree uses `.txt`).

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-wallet-currency-guard-v81.apk`, debug versionCode81: SHA256 `0b7a30b5d299eedc8bd706d8e3eec242a8638a5312ea7d61ae7f23cbf8caa24d`.

Executed Room test APK `android/build/outputs/apk2/2026-10-15/mistia-room-wallet-currency-guard-test-v81.apk`: SHA256 `8aa34e6e62a546f980dcc6460028348d6a9cf6485a07bbe0cf9fe1e9d929fc25`.

Executed management test APK `android/build/outputs/apk2/2026-10-15/mistia-management-wallet-currency-guard-test-v81.apk`: SHA256 `8b7bc3103787ecb714f3b5040bcadcc40c172b6687ad34349f4fc66f4c91c8ed`. Manifest/version/new policy DEX verified for archived artifacts.

This guards this regular-wallet local edit path. Credit-card wallet currency edits, protected investment cash, transaction commits based on older wallet snapshots, remote cross-record races/recovery and full currency/import audit remain separate open work; no claim of universal financial atomicity. Existing-wallet balance adjustment, credit-limit/other calculator forms, coupled installment writes/fund usage/maintenance, pending card payment currency choice, APK3/4/RC and device gates also remain open.

Only isolated API36 emulator connected; all10 flagsfalse; no Samsung/live Supabase writes/deploy/migration. Full goal stays active; next credit-card currency history guard.
