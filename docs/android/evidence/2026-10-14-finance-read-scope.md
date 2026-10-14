# Personal Finance repository read scoping — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `3907968`.

## Reproduced problem and fix

Personal Finance raw streams and four typed streams trusted the LocalStore row partition. A cached row with an owned envelope but foreign/missing payload owner, a different payload ID or a payload tombstone could still reach Overview/Management/Transactions or their counts. Tests reproduce this with deliberately inconsistent envelopes; no production account data was used.

All15 CloudEntity raw Finance streams now require the expected entity, envelope owner and full UUID payload owner/ID matching the envelope/session. Both envelope and payload tombstones exclude live rows. UUID case/whitespace differences normalize only for comparison; the raw record is returned unchanged. Missing/null/non-string/short UUID identities fail closed. Wallet/category/profile/transaction streams and delegated budget/goal/bill/due live streams use the same predicate before decoding. Historical category metadata uses the same identity check while deliberately retaining owned archived/deleted categories.

Finance entity counts now derive from those same validated live raw streams, rather than trusting a SQL row count that cannot inspect payload identity. Counts include only the15 personal financial entities, remain sorted and omit zero entries. They react when payload ownership changes without a storage count change; unchanged aggregate counts are coalesced. This creates15 cold local stream subscriptions while a count observer is active; it avoids extra writes or rereading snapshots from a count-change signal. The UI currently uses these counts for financial domain summaries.

Family viewer/subject collections remain in their separate repository. Mutation snapshots, persisted rows, outbox, schema and all cloud gates are unchanged; an invalid row is hidden by these read APIs, not deleted/repaired. LocalStore's low-level snapshot/count APIs retain their existing semantics. Existing pending mutations/unknown fields/Long versions are preserved.

## Direct comparison and review

`contracts/schema/cloud-entities.json` requires id/user_id for all15 personal entities and separates read-only family collections. Swift SupabaseRemoteStore fetches use the subject user_id filter and single-row id+subject filters; MistiaSyncCoordinator category-reference handling checks each typed row.userID against ownerUserID. The new local check enforces that same identity boundary before presenting cached Android data. Self-review covered raw/typed/delegated paths, metadata retention, counts and family separation; independent review remains pending availability.

## Verification

Runtime RED `/tmp/mistia-finance-read-scope-red.log`: **22 tests,21 expected failures**, including all15 raw entities,4 typed collection paths, counts and metadata aliases; existing UUID-case raw acceptance passed. GREEN added a live count-observation regression and expanded malformed identity inputs: **23 new JVM cases**. Full Android **988 JVM tests /104 suites**, zero failures/errors; Room/management/planning AndroidTests compile; lintDebug/assembleDebug pass. Existing budget, goal, bill, card, category, wallet and transaction regression suites remain green.

Two new actual DAO+repository Room tests compile only: envelope/payload owner separation plus validated counts without storage/outbox repair, and archived/deleted metadata retention with aliased IDs excluded. Initial fixture compilation lacked required wallet currencyCode; explicit JPY fixtures fixed it, then compilation passed. No Room test execution/device proof is claimed.

Full Swift **602 tests** (4contract+133data+465core), contracts15, both localization checks, actual SQLite outbox7/notification3 and git diff --check pass. Logs `/tmp/mistia-finance-read-scope-{red,green,full,swift,room-compile}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-finance-read-scope-v52.apk`; debug package/versionCode52 verified. SHA256 `7178cdbe4d06afcd35f6d5d0a4a3ca5efb40cb971c65ebef5f3f903699b57ebe`.

## Limits and remaining work

ADB empty; no emulator/Samsung account/visual/runtime checks. Nine cloud write flagsfalse; no live Supabase write/deploy/migration. This is a personal Finance read-boundary fix, not a claim that every mutation/family/investment/RC scope is complete. Card payment/maintenance/pending currency policy, installments, independent review/device QA and remaining full APK1–4/RC requirements stay open.
