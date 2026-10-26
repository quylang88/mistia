# Slice153 — canonical investment-wallet publication

Baseline `0e7253964c05215fce08e47331ad73073a60cfa2`, branch `codex/android-apk2-4-parity`, main152. This record concerns the canonical investment wallet metadata prerequisite. APK1–4/RC remains active; trade/cash RPC/result reconciliation and family/RC work remain.

## Implemented behavior

The ordinary wallet writer continues to reject reserved investment identity/kind/purpose. A closed owner-scoped HTTPS port admits only `investmentSystemWalletId(owner)`, kind investment, purpose investmentProfit, zero opening balance and active local proposals. Remote legacy inactive roots are readable for deliberate CAS restoration; currency mismatch holds a conflict before ACK/write. Preserve exact Long/null/opaque metadata. POST excludes derived `current_balance_minor`; PATCH additionally excludes opening/currency/kind/purpose/created authority. Response currency and proposed version must match. Requests use captured session/caller/gate checks, bounded responses, safe errors and no redirects.

Typed Room source/ACK/failure/receipt methods atomically prove the current root row, dirty state, exact queue and linked dependency. Receipts change only private payload evidence in a newer coherent row+queue, preserving business values, received/dirty/base/device/date and retry fields. A captured-session predicate inside each new mutation transaction checks initial/final fences; same-owner token rotation causes rollback. No schema change. Financial ledger/posting/trade queues are never consumed as metadata ACKs.

The root-specific local journal records at most64 distinct actor/base/confirmed-version/fingerprint parents through the actual link planner. Strict owner/root/schema/Long/hash checks pin it to the local generation. Only a proven own predecessor overrides timestamp-first conflict resolution. Unproven own later differing server writes stay conflicted; other-device policy remains. Dedicated and generic remote ingress reject private root evidence; coordinator strips it before the closed wire port, which refuses residual private keys. Asset/photo provenance remains separate.

One composite wallet entry avoids engine entity dedup dropping the root. Its sequential phases are root → ordinary target dependency → root → deferred ordinary work. When root is pending, an opt-in ordinary-source guard admits only its exact owned eligible dirty current target, selected directly beyond the ordinary100due cap and rechecked before fetch/write. Other ordinary mutations wait without retry metadata changes until root is clean. This preserves target-before-link writes and releases old cloud links before ordinary-wallet retirement, including combined dirty-new-target+old-archive and failed-root retries. Investment gate off retains independent ordinary behavior. All seven summary counters and cancellation between phases are preserved.

Effective SQL requires linked target `system_purpose_raw_value IS NULL`; planner/view/picker now exclude all reserved purposes. Root readonly presentation ACKs no longer invalidate frozen linked-wallet confirmation. Identity/currency/link/created-at/cash and ordinary-target changes retain their checks. Six original focused screenshots (EN/VI/JA × light/dark, actualfont1.3/320dp) were pulled, hashed and individually inspected: all title/message/three actions complete, no overlaps. They belong to the focused19test run, not an OEM-device claim.

## Runtime RED → GREEN

- Canonical/snapshot14 and initial closed HTTPS14 tests were runtime RED→GREEN before root WIP preservation. Original7files were restored with SHA proof after152 commit; all were freshly reverified under153.
- Derived-money authority HTTPS regression: runtimeRED1, then normalized full input validation and restricted serializer; model/network GREEN.
- Reserved linked purpose:3modelRED plus actualpicker1RED; strict purposeNULL correction gives focusednativeGREEN1/2.564s.
- Typed Room source/ACK/failure foundation:9runtimeRED against unsupported methods, then9GREEN0.155s. Covers exact queue, changed link/dependency, owner revocation, failed insert rollback and final caller cancellation.
- Coordinator18cases/15runtimeRED against no-op stub. First implementation full431sync had1failure because readonly normalization masked an archived root. Preserving inactive state for restore gave full model992/network193/sync431GREEN.
- Real Room/authenticated local HTTPS integration6/3runtimeRED: old server00:30 write must not erase concurrent local00:15 choice on next cycle, lost reply and definite higher compared base7→8. Strict10parentmodel/9RED and18network/3RED drove bounded causal evidence and wire guards. New receiptRoom tests15/6RED drove actual success receipts; final focusedRoom15GREEN0.257s and integration6GREEN1.157s.
- Readonly presentation: model1runtimeRED; initial native test observed an unused wallet stream, corrected test-only to actual cash stream. NativeRED2 proves disabled confirmation after real typed metadata ACK. Root-only normalization yields fullmodel1003/network196/sync431GREEN and linked-wallet UI19/19GREEN58.521s. Added negative identity/money/ordinary-target coverage.
- Composite initial5unit/5RED. Ordinary-first with complete counter aggregation gives actualintegration10/1RED permanent HTTP400 when archiving the old linked wallet. Root-first initially passes10/10GREEN5.145s.
- Independent review found the combined dirty-new-target+old-archive case: actual1RED; root503 retention case makes integration12/2RED. Added exact-root dependency guard plus final ordinary pass: focused2GREEN2.027s. Extra due100target and root-dirty-during-fetch regressions retain the real clients and Room.
- Review also identified same-owner session replacement inside Room. ActualRoom18/3RED and actualHTTP+Room1RED prove old queue committed before coordinator cancellation. Captured-session predicate inside transaction yields18/18GREEN0.288s and integration13/13GREEN1.95s. Final focusedintegration15/15GREEN3.165s includes backlog/fetch-race tests.

Logs use `/tmp/mistia153-*`, copied/hashes archived at final acceptance. Test compile issues corrected: missing fake-store methods/import, trailing clock-lambda ambiguity after optional source callback. These compile errors and the initial wrong observed-stream timeout are not claimed as product regressions.

## Review, contracts and limits

Direct comparison: `Mistia/Shared/Sync/MistiaSyncLocalStore.swift:1974` normalizes canonical root presentation/active state; `SupabaseRemoteStore.swift` owner-scoped wallet create/CAS. Effective SQL canonical trigger `20260809090000_investment_domain.sql:683`, all-wallet servernow trigger in `20260417020000_release_baseline.sql`, derived balance migration `20260505090000_wallet_current_balance_snapshot.sql`, linked target/old wallet restrictions `20260826030000_fix_investment_linked_wallet_update_permission.sql`. Root PATCH returns the client-proposed version; asset RPC version rules are not reused. No Swift/SQL/RPC contract change. Historical151localSQL77migrations/251assertions retained, not rerun for unchanged SQL.

Independent scoped read-only review `review_wallet_publication153` reported two introducedP2s (combined dependency and final session fence), both runtime reproduced and corrected. Follow-up source review found both resolved and no additional introducedP1/P2; reviewer ran no builds/tests and makes no whole-branch claim. Author verified actual tests separately.

All11cloud flags remain false. Local authenticated HTTPS fixture is not live Supabase. API36ARM64 emulator only; no Samsung connected, no production write/deploy/migration/push, no repeat OAuth/account-switch setup. Room6/SwiftDataV11 unchanged.

## Final acceptance

Final host `testDebugUnitTest`, Room test compile/packages, Investment test package, app lint/build BUILD SUCCESSFUL1m2s. JVM2382/222suites,0failures/errors/skips. Swift627=4+151+472zero. All11contract/localization/store/icon/unit-fold scripts0; whitespace clean. Main152 min26/target36/20DEX, all11compiledflagsfalse, debug cert SHA256 `72064998df2a813facabae5e30fd1e7f7631c920e719d6bcb90008aa45d0235e`.

Frozen23Androidfiles172462patchbytes SHA256 `007d5b3c29f2e7982256c0bf86023ffc8edb922c141b47d6cb3c66c1180b7c33`. Main37115195bytes SHA256 `45fa4d4a37b7373a2f32e7f10342ad58b4568e925176454783ae1fc3a113f380`. Final3APK/source manifests in `android/build/outputs/apk2/2026-10-26/slice153-artifacts.json` and `slice153-source.patch/json`. Build/archive/installed SHA verified before full native run, install-r only; no uninstall/data clear.

First full-native harness accidentally read slice152 manifest: it reinstalled old accepted APKs and ran382RoomGREEN8.554s. Expected400count assertion stopped it before Investment. Preserved `/tmp/mistia153-old-manifest-room-native.log`, excluded from153acceptance. Corrected script reads slice153 and verifies all3installed hashes before running. Final Room400/400GREEN8.655s and Investment218/218GREEN949.795s,618native total, no ignored cases. All3build/archive/installed SHA match; final frozen source still matches the tested patch.


Main cold launch (observational, emulator):

```text
Starting: Intent { cmp=vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity }
Status: ok
LaunchState: COLD
Activity: vn.com.quyln.mistia.debug/vn.com.quyln.mistia.MainActivity
TotalTime: 1196
WaitTime: 1201
Complete
```

APK `android/build/outputs/apk2/2026-10-26/mistia-0.2.0-apk2-investment-wallet-v152.apk`; `slice153-source.patch/json`, `slice153-artifacts.json`, `slice153-logs/` and `slice153-linked-wallet-focused/manifest.json` retain immutable hashes and copied logs. Independent local slice commit follows this verification; full APK1–4/RC completion is not implied. Next: closed trade RPC publication and coherent derived-result reconciliation, then cash/family/RC workflows.
