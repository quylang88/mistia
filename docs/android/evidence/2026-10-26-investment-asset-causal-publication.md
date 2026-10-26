# Slice152 — causal asset publication

Baseline `53556917`; implementation branch `codex/android-apk2-4-parity`. Final acceptance is recorded below.

## Observed problem and correction

The user's TXT explicitly requires retaining newer mutations after late responses. Three real Room/private files/authenticated local HTTPS tests reproduced lost newer name/photo proposals on the next cycle when an older RPC's server timestamp00:30 outranked concurrent local00:15. This extends slice151 coverage, whose existing late-rename fixture used local01:00 and passed; historical151 acceptance is not rewritten.

A local bounded64-parent fingerprint journal is produced with the actual asset/outbox mutation. Strict schema/owner/id/device/Long/deleted/hash checks reject malformed evidence; business no-op probes do not grow it. Both owned private keys are stripped from wire data and refused on dedicated/generic remote ingress. Only the asset coordinator uses causal matching; ordinary shared and other-device conflict policies remain. Unproven own newer server payloads hold an explicit conflict instead of silently consuming current work. Existing photo/cache upload/ACK/cleanup authority is unchanged.

A subsequent runtime test exposed the compared-base gap: an old localbase0 proposal first CASes server7→8 while a rename arrives. A definite successful-RPC receipt now appends actual returned fingerprint/version in an owner/caller-fenced Room transaction to the newer coherent row+exactqueue. It preserves every business value, dirty/received-at stamp, base, attempt, retry date/error and device. No generic financial queue is ACKed. Unknown lost-reply version gaps cannot fabricate confirmation and remain pending for conflict handling.

## Runtime RED→GREEN

- `/tmp/mistia152-ancestor-rpc-clock-red-native.log`:3tests/3assertion failures, same local00:15/server00:30 problem in rename, lost reply and new photo.
- `/tmp/mistia152-parent-model-red.log`:10tests/2failures for missing real producer marker and wire stripping; both corrected.
- `/tmp/mistia152-parent-first-green.log`: model and network pass;6sync fixture failures identified same-device fixtures conflating true other-device winners and overly broad own holding. Same-device local winners/equal semantics retain existing behavior; real other-device remote-winner fixtures now declare another actor. `/tmp/mistia152-parent-second-green.log` passes model/network/sync and test package.
- `/tmp/mistia152-parent-red2-native.log`:11integration/1failure, the new higher-compared-base receipt test; original3 pass. `/tmp/mistia152-receipt-green-native.log`:11/11GREEN2.261s after definite receipt.
- `/tmp/mistia152-room-focused-native.log`:42/42GREEN0.972s, including6new receipt/ingress tests for exact new queue stamps, forged payload/version, owner replacement, late queue failure and final caller cancellation rollback.
- Expanded10model parent tests cover exactLong beyond2^53, actor/version/deletion/fingerprint mismatch, Keep versus explicit-image hash,64cap/dedup, no-op probe, confirmed version, malformed/unknown/foreign/oversized marker, opaque data and normalized archived instants. HTTPS tests cover both private keys and dedicated/generic ingress.
- Test-only compile smart-cast errors were corrected. The new HTTPS fixture initially proposed an unchanged version (correctly rejected), then dequeued the same recorded request twice through a two-key predicate; corrected to advanced version and one captured request. These are excluded from product-regression claims.

## Full-suite fixture investigation

The first final full201run completed in1013.049s with199success and2failures: `photoPreviewAndActionsRemainCompleteInThreeLanguagesBothThemesAtActual130And320Dp` could not see the remove button immediately after a configuration dispatch/scroll, and `aCurrentCommittedRetrySurvivesMetadataOnlyAssetAndWalletAcks` timed out waiting for the form to close after pointer activation. That run and every initial source/APK are preserved as slice152-initial-artifacts.json and `/tmp/mistia152-full-investment-initial-native.log`; it is not accepted as a green full suite. Both passed on the identical APK in a focused2run31.168s (`/tmp/mistia152-full-failures-focused-native.log`).

Only the tests were refined: wait until the actual remove button is scroll-reachable after asynchronous remeasurement (all original font/full-text/image/width assertions remain); activate the actual Retry accessibility OnClick rather than a pointer whose target may move with IME/reflow, and additionally require exactly2successful saves. The latter still fails if live intent/read/stock/repository authority rejects Retry. These changes align input with each test's contract; no product UI behavior was changed or declared fixed. A test-only static Assert qualifier compile error was corrected. Final host build5s passes; focused2GREEN26.749s (`/tmp/mistia152-fixture-final-focused-native.log`). Full201rerun is pending.

Main and Room APKs remain byte-identical to the first run. Final Investment test SHA256 `488e4dd8870ebed268d7337acc80a6cac7ead85e417c2f0b309cf9c07858f70b`. New frozen18-file Android patch55018bytes SHA256 `c3f156b2d3e17829c7d8bbe628b1084e387b57e9a2e7d42fbb4250dd8f918f15`. The initial16-file/51701byte patch is preserved separately and is not substituted for the final source.

Six final focused native PNG originals (EN/VI/JA × light/dark, actualfont1.3/320dp) were pulled before the full rerun reached the photo matrix, SHA-hashed in `android/build/outputs/apk2/2026-10-26/slice152-photo-focused/manifest.json` and each visually inspected. The actual preview and Remove Image labels are complete in all six. The top Asset Name label is above the deliberately scrolled viewport; this is not evidence of label layout clipping. Native text-layout assertions also check the optional-photo heading and Remove label, not just a screenshot montage. No image generation/OEM camera automation is involved.

## Review and limits

Direct author review compared `Mistia/Shared/Sync/SupabaseRemoteStore.swift:574` and `supabase/migrations/20260822040000_add_atomic_investment_asset_rpc.sql`: RPC uses expected CAS and servernow, increments existing+1. No Swift/SQL changes or migration. Supabase skill/current changelog and [official database function docs](https://supabase.com/docs/guides/database/functions) consulted; no relevant RPC contract change. Existing project policies and all five user currency decisions remain.

Fresh independent scoped static review (`review_asset_causal152`) found no actionable introduced P1/P2 across changed production files, journal, Room/coordinator/image contracts. It ran no build/native/Swift/Docker and makes no whole-branch clean claim.

All11cloud flags false. Local authenticated HTTPS fixture is not live Supabase. No Samsung, production write/deploy/migration/push or repeat OAuth/account-switch verification. Room6/SwiftDataV11 unchanged. Full APK1–4/RC remains active; resume preserved root-wallet prerequisite after this independent slice commit.

## Final acceptance

Host2312JVM/216suites,0failures/errors/skips; lint/main/Room+Investment packages BUILD SUCCESSFUL1m4s (`/tmp/mistia152-full-host.log`) plus final fixture host5s (`/tmp/mistia152-full-host-final2.log`), Swift627=4+151+472zero (`/tmp/mistia152-swift.log`) and11scripts0 (`/tmp/mistia152-final-checks.json`). FullRoom382/382GREEN8.724s and final fullInvestment201/201GREEN1204.728s,583native total, no ignored cases. The first full201run completed199success/2UI-fixture failures (button visibility after configuration/metadata Retry pointer activation); its immutable APKs/source/logs remain in slice152-initial-artifacts.json. Both passed on unchanged APK in a focused2run31.168s. Test-only synchronization now waits for real scroll reachability after configuration and activates the real Retry accessibility action with an added exact second-success assertion; focused2GREEN26.749s and the full rerun verify the revised fixture. Main/Room APKs are byte-identical to the initial run. No product UI fix or OEM-device verification is claimed from this fixture correction. Logs `/tmp/mistia152-full-room-native.log` and `/tmp/mistia152-full-investment-native.log`; copies/hashes retained under archive slice152-logs/ and manifest.

Frozen18-file Android patch55018bytes SHA256 `c3f156b2d3e17829c7d8bbe628b1084e387b57e9a2e7d42fbb4250dd8f918f15` against53556917; reviewed source still exactly matches built/tested source. Main151 min26/target36/20DEX, debug signing certificate SHA256 `72064998df2a813facabae5e30fd1e7f7631c920e719d6bcb90008aa45d0235e`, all11compiledflagsfalse. Main36217292bytes SHA256 `24d5b38fd102286889b0bd6401ef6254da6406f9dc9636fd1d73a284c3bf4694`. All3build/archive/installed APK hashes match; no uninstall/data clear, install-r only. Main cold launch (observational):

```text
Starting: Intent { cmp=vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity }
Status: ok
LaunchState: COLD
Activity: vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity
TotalTime: 1391
WaitTime: 1392
Complete
```

APK: `android/build/outputs/apk2/2026-10-26/mistia-0.2.0-apk2-investment-asset-causal-v151.apk`. Source/logs/full3APK manifests: slice152-source.patch/json and slice152-artifacts.json in the same archive. Existing151SQL77migrations/251assertions unchanged and not rerun this slice. No live Supabase, Samsung or whole-app/whole-branch/final APK1–4 acceptance is implied.
