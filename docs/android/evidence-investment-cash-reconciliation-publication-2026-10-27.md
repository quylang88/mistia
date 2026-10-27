# Slice159 evidence: manual investment cash reconciliation publication

Started2026-10-27; final acceptance continues2026-10-28 Asia/Ho_Chi_Minh. Baseline `1a1b44213272dbedd55c868c8578f04474269c36`, branch `codex/android-apk2-4-parity`. Full APK1–4/RC remains active. No fresh external-agent review is claimed; current instructions prohibit unsolicited delegation.

## Change and direct source review

Confirmed manual reconciliation publishes its real transfer ledger followed by a compared atomic posting pair, then performs one complete typed local financial ACK. Direct Swift review: `InvestmentPersistence.swift`1831–1906 and its linked transfer helpers; `SupabaseRemoteStore.swift`154–170/231–249/498. Actual role is `investmentReconciliation`, with derived `cash-reconciliation` ledger and `holder-cash-posting`/`linked-cash-posting` pair. Real80 can carry only booked profit50; no minor-unit/FX reinterpretation. Immutable different intent is held. Ledger preparation alone is never a financial ACK. Lost ledger/batch replies, clean ledger with orphan posting queues, exact per-row CAS and newer whole-source changes are covered.

Closed owner/session/caller/gated HTTPS, insert-only ledger preparation, terminal-empty bounded posting reads, force=false expected-version map, redacted SQL retry conditions, typed transactional Room ACK/failure, local IO propagation and all-seven-counter composite phase are implemented. Generic financial writers are not widened. Main versionCode156; Room6/SwiftDataV11 unchanged.

Local SQL reproduced confirmed destinations being stranded by later link changes. Migration80 applies only to the compared3arg API: complete canonical owned live same-currency historical ledger/pair proves its destination. Capacity checks, owner advisory lock, global row CAS, hardened single-row API, unchanged legacy2arg body and grants are preserved. Old noncanonical events retain the original current-link checks. The ledger and posting batch remain separate remote transactions, consistent with Swift; local durable queues recover the intermediate state.

## Runtime TDD and focused evidence

- Model5tests/3runtimefailures →5GREEN.
- Network8/7RED→8GREEN; added closed SQL version-race regression12/1RED→12GREEN.
- Actual API36ARM64 Room9/8RED→9GREEN0.198s; full rollback/session/newer-source and exact retry fences. Native adb exit0 on RED was correctly rejected by test statuses.
- Actual repository+Room+TLS14/12RED→14GREEN; version-race native1/1RED then full16GREEN3.162s. An earlier fixture lacked occurred_at and failed before publication; its log is retained separately and excluded from product RED.
- Composite phase5/1RED→5GREEN; all seven summary counters preserved.
- Inline clean-history scan regression: actual Room1/1RED observed2full-source reads instead of1 for a clean event; filter actual dirty posting/referenced-ledger keys before rereading. Full focused21GREEN4.319s also proves ledger-only recovery through clean postings.
- Inline root-currency regression19/2RED actually created2JPY postings under a VND accounting root. Canonical root owner/purpose/kind/active/currency checks fixed it:19GREEN.
- Local pgTAP17/6RED; stronger old-function characterization17/15RED→17GREEN. All synthetic fixtures roll back.

## Full local server acceptance

Guarded CLI2.122.0 --local reset applied80migrations. Before-create private Unix Docker adapter forced explicit127.0.0.1 host bindings; configured/effective bindings checked. Stored single-row/legacy2arg/new3arg bodies exactly matched source after reset. Full11SQLfiles376assertions PASS after the second fresh reset. Real two-caller foreign-owner absence race plus stale-update and absent-create batch races all PASS; fixtures/locks cleaned. No production connection/write/deploy was used. Own5containers and Docker backend stopped, volumes retained, docker info failure verified before launching host checks.

## Full host acceptance

2,646JVM/242suites:0failures/errors/skips. Full Swift627tests (4+151+472) passed. App lint/build, both native packages and Room compile passed; all11contract/localization/outbox/notification/installment/icon/fold/Room-asset scripts passed. Final host Gradle17s; the earlier27s and1m28s host runs are retained separately. git diff checks pass. Logs and exact commands are archived in the final manifest after native acceptance.

## Frozen candidate and native acceptance

Android14files/99614patchbytes SHA256 `e66dc2fad8f82e748e57e147ef1c4711b70a452f591dd8b5e6703b101952d713`. Candidate `/Users/quyln/Project/mistia/android/build/outputs/apk2/2026-10-27/slice159-candidate-e66dc2fad8f8`. Main156: min26/target36/20DEX/37003839bytes; SHA256 `6421f5c5a8adefb47116994bec272c648989f4bae726e03ef1f4cd9c1668a8be`. Same debug certificate SHA25672064998df2a813facabae5e30fd1e7f7631c920e719d6bcb90008aa45d0235e. All11writeflagsfalse.

All3build/archive/installed APK hashes matched before and after final suites; install-r preserves data. Emulator5554 API36ARM64 transport21. Final fullRoom476GREEN10.380s plus fullInvestment307GREEN1210.955s =783native, exact status0 counts, no ignored/negative statuses. Main156 COLD Status:ok is observational launch evidence. Samsung is absent.

Final manifest `android/build/outputs/apk2/2026-10-27/slice159-artifacts.json` binds source/APKs/backend reset/test proofs and133archived logs, and is bound to the actual source commit after creation. APK alias `android/build/outputs/apk2/2026-10-27/mistia-0.2.0-apk2-debug-v156.apk` has the main checksum above. All prior candidates and logs remain distinct.

An initial3e686 full run passed476Room and306/307Investment (1092.137s); one existing image-layout test asserted preview visibility immediately after scrolling to the separate Remove button. The same installed APK passed that exact test three focused times. A test-only correction now scrolls the preview itself inside the existing8s settling bound, preserving font130/width320/all6language-theme/no-write assertions; focused corrected run passed20.551s. Product APK/Room APK hashes remain unchanged. Initial failed native log and source/APKs remain under candidate3e686/native-attempt.json and initial-failed-native-logs; no production image bug is claimed.

The prior frozen9a36 candidate passed476Room+305Investment=781 (10.228s/1047.927s) before the two inline review regressions. Its original APKs, patch, backend snapshot and exact native logs are retained under its intermediate-native-acceptance.json/intermediate-logs. It is explicitly separate from the final e66dc source and is not bound to the eventual final commit.

## Limits and continuation

No Samsung/liveSupabase/productionwrite/deploy/push/OAuth replay. This completes only the manual reconciliation publication path when its prerequisites are publishable. Full linked-wallet-move and editable ordinary/bill/installment fund usage publication, wallet retirement coordination around queued financial events, remaining family/receipts/background/settings/security/signing and physical RC remain goal work. A new backend migration must be deployed through the separately authorized production workflow before enabling client writes; no approval is needed for the remaining local work. Commit this slice independently after final checks/docs; bind the resulting commit in the ignored manifest, then continue.
