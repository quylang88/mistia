# Slice155 — coordinate investment metadata retirement

Baseline `479d72fa71e62f9246197121183a70abf4dac086`, branch `codex/android-apk2-4-parity`, main154. Full APK1–4/RC remains active. This is a disabled publication foundation; all11 cloud-write flags remain false. Separate investment cash publication, remaining family/receipt/background/settings/security/signing and physical Samsung RC remain afterward.

## Behavior

One engine entry publishes channel → asset → trade → asset → channel, retaining every summary counter. Locally closed or reassigned trades can publish before the queued archive of their original asset/channel when separately fetched owned active metadata proves the exact prerequisites. The atomic financial ACK recomputes that proof against the original whole generation; it never consumes metadata or unrelated cash queues.

Combined metadata edits use an active proposal derived from the exact pending archive. A bounded private preparation marker is committed with the row and queue before HTTP. Only the matching definite response, or a later owned read matching that preparation, can rebase the metadata base version. The final archive remains queued. Newer name/restore/photo edits, business timestamps, retry generation and owner/session authority remain protected. Remote reads reject private markers; outgoing dedicated requests strip them.

JPEG publication uses actual file-cache authority and immutable Storage upload before the active metadata RPC. Keep may adopt the compared owned server photo while retiring only an unchanged already fulfilled local image declaration. Newer explicit Replace/Remove intent cannot be replaced by an older stage response. Cleanup waits for matching final acknowledgement.

Final archives require complete owned asset/trade history, keyset pages until empty even with a short server page, and FIFO closure per asset/unit. Pending dependencies include the old cloud asset of a moved trade. An individually valid but fractured cross-read history defers without changing the queue. The server archive guard remains authoritative; HTTP400 from the actual final archive write can retry, while active-stage400 and403 retain normal classification. Each due metadata queue gets one turn, avoiding permanent starvation behind100 deferred archives; future retries remain excluded.

## Runtime evidence

Actual repository + Room + authenticated local HTTPS tests reproduced the initial close/archive cycle, combined rename staging, archive guard race, lost/late replies and photo Keep regression before their fixes. The fixture uses production model planners for financial fields and is **not an independent SQL arithmetic oracle**.

Additional runtime RED→GREEN covers historical ledger-title comparison after rename (3model cases, baseline display comparison only), DELETE mutation kind for tombstoned unit-repair extras (2model cases), stage source read/cancellation propagation (3sync cases), captured-session transaction rollback for asset ACK/failure/receipt and channel ACK/failure (5actual Room cases), and100 blocked asset/channel queues starving a due move target (2actual integration cases).

Legacy NULL active history labels then rebuilds before DELETE: original trade2 → unit label/rebuild4 → tombstone5, one actual DELETE at base4, no synthetic resurrection. Already deleted legacy history receives only its label increment and no additional DELETE. Existing/renamed/new target channel+asset cases keep funding70 and retire the old branch only after the move. New channel creation includes the existing canonical root-wallet publisher before the five phases. A future metadata retry is not queried or written during the all-due selection.

Fresh reviewer `review_retirement155` statically reviewed immutable patch SHA256 `89971134fa4bb58a516acda09b949795667d1e493128455b63a941d8ef7df02d` and reported one P2: an asset/trade cross-read race could permanently fail an archive. Actual Room/HTTPS reproduction had permanentFailures1 versus0, and a model test reproduced the missing typed distinction. The fix preserves a typed changed-history signal through the network boundary and defers only that incomplete relation. The same scenario now retains its queue, observes the concurrent open position on a fresh read, and finishes after that position closes. Foreign/private/malformed data stays rejected. No second reviewer pass was run; the author verified the fix by TDD. The reviewer explicitly set aside full APK1–4/RC, remaining cash publication and production enablement; those remain in the active goal.

Focused integration44/44 passed64.709s with exact per-test statuses and no ignored cases (`/tmp/mistia155-focused44-native.log/json`). Final host `testDebugUnitTest`, Room test compilation, app lint/build and both native packages passed3m3s. Actual XML:2566JVM/236suites, zero failures/errors/skips. Full unfiltered `swift test --jobs2`:627=4+151+472, zero failures. All11 contract/localization/outbox/notification/installment/icon/unit-fold/Room scripts returned0, sequentially. Room6/SwiftDataV11 and Swift runtime sources are unchanged. Final full native/APK acceptance is recorded below. After a test-only input refinement, the same full Gradle command passed again16s with the same2566JVM/236suites and zero failures/errors/skips. Swift627 and11script results are retained because all their source inputs and production code are unchanged.

Failed fixture/command attempts are excluded from product RED counts: wrong shell working directory; copied paid cloud trades sharing a funding leg; existing asset RPC POST mistaken for channel create409; singleton-array channel POST parsing; returning unrelated cloud trades instead of the RPC's affected histories; attempting to construct a cloud BUY from locally archived channel metadata. These were corrected before the44-case pass. The43-case run with3failures was not accepted.

## Direct references and limits

Swift `Mistia/Features/Investment/InvestmentHubView.swift:1394`–1437 independently queues locally closed asset/channel archives. `InvestmentPersistenceService.deleteTrade` supplies the historical title comparison reference; Android still validates exact financial amounts, currencies, roles and identities. Effective SQL `20260809175651_remove_legacy_investment_fields.sql:72`–127 supplies the archive guard, `20260822040000_add_atomic_investment_asset_rpc.sql:66`–74 requires an active channel, and `20260822050000_add_investment_units.sql:263`–285 labels all NULL trades including tombstones (+1) then rebuilds active trades (+1).

No Swift runtime, database schema or SQL migration changed. Accepted154's local77 migrations/7pgTAP files/278assertions remain historical evidence; they have not been rerun for155. Actual local HTTPS/Storage tests are not live Supabase or production-write evidence. All five previously settled currency rules remain unchanged. Accepted154/main153 artifacts are immutable.

## Final acceptance and frozen artifacts

Android patch40files/227709bytes against the baseline: SHA256 `8d79023fd09c65a73f04c7916a01acee70b6720627bcd5ec7d1d6f2c13eb691c`. Candidate directory `android/build/outputs/apk2/2026-10-27/slice155-candidate-8d79023fd09c/` contains immutable source/APKs/badging/signing evidence. Main154 SHA256 `e80a0a53ffe67ae85fa04441c8771047a9734296f56cf826d2c3e3f355f87348`, min26/target36/20DEX/36479432bytes. Debug signing certificate SHA256 `72064998df2a813facabae5e30fd1e7f7631c920e719d6bcb90008aa45d0235e`.

All three APKs were updated with `adb install -r`, then installed bytes pulled and hashed against build/archive. The first full Room451/451 passed14.624s. The first full Investment run completed1389.492s with261passes and one failure: `InvestmentSaleScreenTest.aCurrentCommittedRetrySurvivesMetadataOnlyAssetAndWalletAcks` timed out waiting for the form to close after pointer activation. That failed run and its39-file candidate `1bc138ff29d1` remain immutable historical evidence, not accepted output. Three focused repetitions on the identical installed APK passed (logs `mistia155-sale-retry-unchanged-{1,2,3}.log`). The analogous Purchase test already used the real accessibility OnClick to avoid an IME/reflow target moving between scroll and pointer injection (commit `0e7253964`, slice152 evidence). The Sale counterpart now uses that same action, asserts the callback succeeds, and retains exactly2successful saves, unchanged rows/queues, enabled/read/intent authority and the same5second deadline. It passed11.416s. No product UI behavior was changed or declared fixed. The full rerun on the40-file candidate passed: Room451/451 in20.041s and Investment262/262 in1546.98s, total713, exact per-case statuses and no ignored cases. All three build/archive/installed hashes still match after the suites, and frozen Android source is unchanged. No Samsung is connected. The initial freeze harness stopped before install/native because it expected `minSdkVersion`; this aapt emits `sdkVersion`. The parser now accepts both documented labels with the same required26 value; source/APKs are unchanged.

Main154 cold launch returned COLD Statusok (timing is observational):

```text
Starting: Intent { cmp=vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity }
Status: ok
LaunchState: COLD
Activity: vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity
TotalTime: 2280
WaitTime: 2281
Complete
```

Accepted aliases,40-file source manifest/patch,131copied logs and all hashes are recorded in `android/build/outputs/apk2/2026-10-27/slice155-artifacts.json`, `slice155-source.patch/json` and `slice155-logs/`. Main APK: `mistia-0.2.0-apk2-debug-v154.apk`. Initial failed155 and accepted154 artifacts remain immutable. API36ARM64 emulator only; this does not establish Samsung, live Supabase, production write or full APK1–4/RC acceptance.

## Recorded rulings and remaining work

- Select all due owned metadata once from the coherent snapshot: promoting only the move target could still starve the final original archive after trade ACK. The cost is more work per pass for large backlogs; other domains and future backoff stay unchanged.
- Activate the Retry accessibility action in the metadata/no-op authority test, matching the existing Purchase test. This case proves real callback/repository behavior and exact no-op data, while other form tests retain pointer input coverage. It does not prove pointer hit-testing in this particular case.
- The reviewer set aside whole APK1–4/RC readiness, remaining cash publication and production enablement. These remain explicit work in the active goal; accepting this disabled local foundation does not close those gates. No deferred minor review findings were reported.

Continue separate cash-event/allocation publication, remaining family/receipts/background/settings/security/signing and final physical Samsung RC. The full goal is not complete.
