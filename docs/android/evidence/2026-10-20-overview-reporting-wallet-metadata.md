# Reporting wallet metadata independent of cash opening - slice113

2026-10-20; codex/android-apk2-4-parity; base1e98c8d2ceecb8a62a96b9cefe73cb5fd2c87f1f. Full APK1-4/RC remains active.

Monthly/week/category/day now retains owned wallet currency/kind metadata independently of unused opening readability. Before this fix a VND165 legacy-source expense could be relabelled JPY165 when the wallet opening was unreadable. At165JPY/VND the correct reporting value is1JPY, while the day row remains VND165. Invalid existing currency now reaches existing unavailable conversion instead of disappearing into legacyJPY; credit kind remains available to distinguish real credit spending from card-payment title exclusions. Archived wallet metadata remains historical.

The reporting-only ephemeral LedgerWalletRecord copy explicitly sets its unused opening placeholder0 before decoding; it never reads/coerces the original opening and is never persisted or used for balances. The data-class contract documents this restriction. All four Screen consumers were inspected. Assets has used raw cash admission since112 and still holds malformed eligible cash until actual opening repair. Identity/owner/entity/deleted/kind/archive admission and record parsing are unchanged. No financial/outbox/schema/cloud writes. Version113 only.

Direct Swift: OverviewSupport.swift113-153 resolves sourceCurrencyCode ?? sourceWallet.currencyCode and sourceWallet.kind independently from opening; TransactionLogic.swift1407-1430 uses credit kind in card-payment/spending classification; OverviewLogic.swift665-708 aggregates record amounts/source metadata without opening. Current Recent primary fallback matches OverviewLogic1247-1270 after the OverviewSupport source-wallet fallback. This observation does not certify the broader imported/legacy original-money/global primary consistency audit or malformed metadata policy.

## TDD and validation

New7 feature JVM cases on112:6 actual monetary runtime RED1sec (all four projections expected1/actual165; invalid currency expectednull/actual165; historical archived metadata), ownership/deletion/explicit-source control passed. Native4/4 intended money RED26.193sec on112: monthly both directions, weekly callout/day hold, category+credit-kind, invalid currency. A missing explicit theme argument was a separate compile diagnostic fixed before baseline packaging; not counted as runtime RED.

Minimum metadata-only projection -> feature30 tests/4suites GREEN5sec, all4 new native GREEN9.91sec. Native includes real Room/outbox snapshots for both owners and wallet/ledger/category, live cash opening repair, source currency transitions VND -> JPY -> invalid -> VND in an open day sheet, chart physical tap and400ms hold, original row money, archived metadata and owner replacement before new flows emit. No display writes; raw fixture changes explicit.

Parent reviewed complete immutable Android diff SHA256795ea85292c3363ac94a47581d2651291c1bc232b32288bc2142e56412c10add and direct Swift dependencies; no additional production findings. No independent113 agent review was executed because the prior existing reviewer failed due usage limit. Independent final whole-branch review remains outstanding; no approval claimed.

Full host **1596JVM/154suites**, no failures/errors; required Room/management/planning/overview/transactions/settings AndroidTest compile/package and lint/build GREEN27sec. Swift610 (4contract/137data/469core), contract15, both strict localization checks, SQLite7/3/11, Room6 assets and whitespace pass. Final whole Overview/editor/installed identity are appended after execution. Existing actual1.0/1.3/light/dark/localized money tests are included in the whole runner; no new UI layout is introduced and no new113 screenshot claim is made.

## Artifacts and limits

Ignored archives android/build/outputs/apk2/2026-10-20/, mistia-overview-reporting-metadata-v113-SHA256SUMS.txt/badging/outputmetadata. Manifest/min26/target36/version113 and main20/overview9/transaction11 DEX entries inspected.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-reporting-metadata-v113.apk|5b74c4d7aa5e24bc30972b834d0bea14e0c4814f170accadbdd09746b7726481|
|mistia-overview-reporting-metadata-test-v113.apk|cecb1c0ccf6f07d131ffb4cb029e4a234d05eefb11fed333f7ee96f00dd4b0a9|
|mistia-overview-reporting-metadata-transaction-test-v113.apk|f1667929e2fd75f7ff2132a936f9f93839d5202bedc3c51896fd5916f2d177b6|

API36 ARM64 emulator transport12 only, no Samsung/liveSupabase/productionwrite/deploy/migration. All10writeflagsfalse; Room6/SwiftDataV11/iOS751 unchanged. Broader malformed reporting amount/calendar/status/kind/identity admission and unused-field omission, imported/source-wallet/legacy/global planning/classifier and loading atomicity, family/event/investment/receipts/device/visual/RC and final independent wholebranch review remain mandatory. No goal completion claim.

Logs /tmp/mistia-overview-reporting-metadata-{unit-red,native-red-build,native-baseline-build,native-red,unit-native-green-build,native-green,host-final,swift,native-final,editor-final,cold-smoke}.log. ADB exit0 alone is not a JUnit pass.

## Final executed results

Whole Overview **91/91 GREEN184.438sec**, actual recent/day -> stored editor -> exact Room/outbox **2/2 GREEN8.111sec**. Main113 installed with adb install -r preserving data; cold MainActivity Status:ok1121ms, installed version113/min26/target36 confirmed. All3 installed base.apk SHA256 values match the final archived APKs above; installed hash record saved. No production edits after final checks.

Parent review ledger: unused metadata opening placeholder is restricted to reporting, every consumer inspected; raw assets112 remains authoritative for balances. Historical archived metadata and explicit source precedence preserve existing contract. Owner/body identity/tombstone/unknown kind filters are unchanged; their broader malformed-input/global consistency audit is still mandatory rather than certified by these tests. No additional finding/fix pass after focused GREEN. Independent review has not executed; final wholebranch audit outstanding. Continue monthly raw reporting availability/required-field admission next, then remaining full APK1-4/RC.
