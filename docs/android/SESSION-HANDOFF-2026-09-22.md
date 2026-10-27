# Mistia Android session handoff — 2026-09-22

> Latest accepted local checkpoint (2026-10-27): **slice155, investment metadata retirement coordination, main154** on `codex/android-apk2-4-parity`. Final2566JVM/627Swift/451Room/262Investment (713native), lint/build/11checks pass. Actual close→archive, move→old-branch archive, staged name/unit/photo and captured-session protections are covered. Continue separate cash RPC and remaining APK1–4/RC. All11cloud flags stay false. API36ARM64 emulator only; Samsung/production gates remain pending. Google login is already validated; no OAuth/account-switch replay.


Read the original requirements at
`/Users/quyln/.codex/attachments/1b6bfcfe-49b2-4465-bafe-41003c98d45a/pasted-text.txt`.
Latest user override: **do not require manual account switching**. Prioritize
completing APK 1–4 and UI/functionality parity; current signed-in UI remains
read-only and incomplete. Do not claim those gates complete.

## Workspace

Repository `/Users/quyln/Project/mistia`, work based on develop commit
`2ffe485d1ff271c2f61ee623cc0fe9b93106b88b`. The user requested committing the
current Android code, tests and handoff as a checkpoint before the next session.
Inspect git log/status/diff for that checkpoint and preserve any later changes.
Do not reset, blindly pull over changes or repeat environment bootstrap.

Java17: `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`.
SDK: `/Users/quyln/Library/Android/sdk`, platform36/build-tools35.0.0.
Use `JAVA_HOME=... ./gradlew` from android/.
Swift: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
Kotlin2.2.21, KSP2.3.12, GoogleID1.2.0. User permits upgrading Kotlin2.4 when
actually needed. GoogleID1.2.1 requires newer metadata but upgrading is not the
fix for the reproduced OAuth failure.

## Completed increment

- Google native Credential Manager, hashed nonce to Google/raw nonce to
  Supabase; email sign-in/signup/name metadata/resend/recovery forms.
- Auth ViewModel/validation, no passwords in saved instance state, redacted
  diagnostics/errors. Debug event logging accepts fixed enum events only.
- iOS artwork reused for launcher and auth UI; purple/grouped auth hierarchy.
- Source amount/currency pairing fixed in overview/transactions with wallet
  fallbacks matching Swift.
- 35 Kotlin tests + debug lint/build pass, contract15entities and localization
  checks pass. Scoped independent review found no introduced P1/P2 issue.
- Auth-entry Compose instrumented test passed on Samsung with Espresso3.7.0.
  Gradle connected tests removed the target app after testing: use explicit
  install -r and direct instrumentation going forward to preserve live data.

## Google fixed on real Samsung

SM-F776Q, Android17/API37, serial R5GL72ERETZ. Connection sometimes disappears;
check adb status before device actions and do not claim evidence while offline.
Version3 (`0.1.2-apk0-debug`) installed with `adb install -r`.
Google returned unregistered Android package/SHA1 and disguised it as
Credential Manager cancellation. Registered Android OAuth in existing Cloud
project mistia-492216/741455632256 with explicit user confirmation.
Client ID: 741455632256-12uieac1sm1v17am9ro25gkrjrii9vgr.apps.googleusercontent.com.
Package vn.com.quyln.mistia.debug; SHA1
35:4E:93:46:C5:35:CA:D6:9E:6C:08:6C:20:33:00:78:1F:5C:42:23.
Do not replace the existing web client ID used for token requests.
User selected account; GOOGLE_TOKEN_RECEIVED and GOOGLE_EXCHANGE_SUCCEEDED
observed; user confirmed entering app. All23 pull tables completed, one viewer
partition, zero outbox records. Force-stop/cold-start retained signed-in UI.
No need to repeat Cloud setup or Google debugging without a new failure.
Email code is tested, but real email login is not independently verified.
User has explicitly waived manual account-switch tests.

APK: `android/build/outputs/apk0/2026-09-21/mistia-0.1.2-apk0-debug-v3.apk`.
SHA256: 3276f8283c59ab29b3b044e46346673439c09b6b66a965417c3a84da89f7a0fb.

## Remaining failure

Swift regression initially597/597 passed, later596/597. Unchanged
MistiaMigrationPlanTests.testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees
fails CoreData134504/unknown coordinator model version; same failure with clean
scratch build android/build/swift-clean-check. No Swift runtime edits made.
The insufficientPosition log nearby is from another expected oversell test,
NOT this failure's root cause. Diagnose; do not disable test or claim passing.

## Next work

Latest user workflow requirement: split implementation into small, coherent
vertical slices. For every slice: define scope and acceptance criteria against
iOS, implement, run relevant checks, review the diff and behavior, fix review
findings, then commit that slice before starting the next one. Record validation
and remaining gaps in the progress document. Do not accumulate all APK1–4 work
in one large commit. A slice commit does not imply that its entire APK gate is
complete. Commit locally; pushing or deploying is not part of this request.

APK1 wallet/card/category, income/expense/internal transfer/FX, receipt
CameraX/Photo Picker/AI, offline mutation/outbox and push/pull.
APK2 budgets/goals/bills/installments/card statement-payment/due/notifications.
APK3 family permissions/invites/transfers/shared expenses/settlements/inbox.
APK4 resale unit-aware FIFO, buy/sell/capital/profit postings, private product
images and existing atomic RPC. Then original RC scope.

Implement complete screens and actions with hierarchy/spacing/icons/color/dark
mode as close to iOS as practical. Preserve native Kotlin/Compose architecture;
UI/ViewModels through repositories. Use Long minor units, BigDecimal/decimal
strings, explicit nulls, fingerprints, version/tombstone/owner scoping,
dependency ordering, atomic Room mutation+outbox, retry/conflict tests.
Do not enable global ALLOW_CLOUD_WRITES. Gate each write domain separately.
Shared xcstrings is sole static copy source; regenerate rather than edit
outputs. No production migrations/deployments without explicit approval.

Evidence/docs: android/README.md; contracts/*;
docs/android/android-parity-progress.md;
docs/android/evidence/2026-09-21-google-login.md (resolution supersedes earlier
pending status); docs/android/google-oauth-setup.md.


## Slice138 checkpoint — 2026-10-23

Latest ordinary editor investment-fund consent/atomic seven-entity save/receipt CAS flow is complete; see android-parity-progress.md slice138 and evidence/2026-10-22-transaction-investment-funds.md for final checks, review rulings, artifacts and scope. VersionCode137/main SHA2795fdb2311b98ed9aa4c3148aba4021552b497b073cafd07d4ca109837f6693 installed on API36 ARM64 emulator only, no Samsung. Final1996JVM/627Swift/70Transactions+261Room native accepted; separate18font130/320dp views. All11gatesfalse/Room6/SwiftDataV11, no production write/deploy/migration/push. APK1–4/RC remains active. Continue ordinary transaction lifecycle archive/restore/delete with derived fund effects and actual routes, then payment protections and remaining full goal. Do not repeat Google OAuth/account-switch setup.


## Slice139 checkpoint — 2026-10-23

Ordinary transaction archive/restore/delete with atomic derived fund effects and actual editor/Management/receipt flows complete; see android-parity-progress.md slice139 and evidence/2026-10-23-transaction-lifecycle.md. Final2016JVM/627Swift/96Transactions+270Room native; Management31 before finalcopy-onlyrefresh;30nativefont130/320views accepted. Main138 SHA7b24cf5463590283f07caa0546067135614c339c1dfb9f4e9c6eb1982f557a5c installed/hashmatched on API36ARM64 only, noSamsung. All11gatesfalse/Room6/SwiftDataV11/no production/deploy/migration/push. APK1–4/RC remains active. Continue140 recurring-bill reserved-fund payment/undo (shared executor currently blocks any investment posting), then installment integration and full remaining scope. Preserve all five currency decisions; do not repeat OAuth/account-switch setup. Read-only next-slice research is preserved at /tmp/mistia140-research.md. Preserve completed139 source/APK evidence while proceeding with140.

## Slice140 checkpoint — 2026-10-23

Recurring-bill reserved-fund payment/typedUndo/repay/explicitretry with atomic canonical effects and actual Planning/Overview/notification routes complete; ordinary automatic succeeds/fund-required holds. See progress slice140/evidence/2026-10-23-bill-investment-payment.md. Final2046JVM/627Swift/282Room/97Transactions pass; changed billUI11 and29combined pass,18views inspected. Full147Planning runs had intermittent legacy picker/save/delete test failures; secondrun passes earlier2 butfails existing installment delete, then thatfocused1GREEN4.517s unchanged. No fullPlanning green/rootcausefix claim; investigate in141. Main139 SHAe116776e9f82ca28432cf95cd529bf1f3b0c68d42fc89c9cedc61b9a59a80d78 installed/hashmatched, COLD1184ms observation. All11false/Room6/SwiftDataV11/noSamsung/cloud/prod/deploy/migration/push.

Immediately continue141 actual installment Pay/Undo/fundconsent/atomicwriter/nativeUI. Design/plan installment-investment-payment-{design,plan}-2026-10-23.md prepared separately; do not mix into140commit. /tmp/mistia141-research.md records real sourcekind/scheduling/category/noncard constraints and actual DuePane/Upcoming routes. No141product edits yet. Keep full original APK1–4/RC scope and all5currency decisions. No new product question needed, no OAuth/account-switch replay. Reuse current dedicated branch/checkout and inline TDD; local complete-slice commits remain authorized.

## Slice141 checkpoint — 2026-10-23

Installment fund-aware Pay/Undo/repay and actual DuePane/Overview routes complete; shared real-source exact engine/atomic Room and explicit failed-intent retry after observer changes. Both Important scoped review findings corrected with native/model RED→GREEN; visible-wallet retry regression fixed. Full2062JVM/627Swift/lint/build/requiredchecks pass; final scopedPlanning55GREEN419.827s and Transactions12GREEN,18views accepted. FullRoom291 financial tests pass but unchanged NotificationPreferencesStoreTest current/recreated master-state mismatch failed; preserve evidence/no wholeRoomGREEN claim. Main140 SHAdf4891daf9ab18830668c34d2047e3e7584ea133ca2996e8632dec1bacf9078e installed/hashmatched, COLD1164ms observation. All11false/Room6/SwiftDataV11/noSamsung/cloud/prod/deploy/migration/push.

Immediately142 separate notification preference publication ordering bugfix: /tmp/mistia142-research.md, /tmp/mistia142-publication-test.kt and notification-preference-ordering-{design,plan}-2026-10-23.md prepared. New142test exists onlyin/tmp, no142product source change. Current listener reads/publishes without update lock; force an older main listener read and a newer off mutation using actualAndroid prefs wrapped in ContextWrapper, inspect actual StateFlow emissions, observeRED beforefix. Consider private per-file serialization +one snapshot read; no test-only productAPI needed. Commit142 separately afterfullchecks and scopedreview, then continue actual resale purchase/sale and fullremaininggoal. No new userproductdecision needed; no OAuth/account-switch replay.

## Slice142 — 2026-10-23: notification preference publication ordering

Fixed the concrete141 full-Room preferences failure with shared-file read/write/publication ordering, atomic field snapshots, post-apply current-state reads for reentrant callbacks, and registration refresh. Three actual Android regressions observed RED then GREEN. Final full native database294/294 and notification UI2/2 pass; JVM2062/197 suites, Swift627, lint/build/contracts/l10n/guards/icons/fold/schema assets pass. One fresh scoped review clean. Version141 main/database/settings install-r and archived/installed SHA256 match on API36 ARM64 emulator; no Samsung/cloud/prod/deploy/migration/push. All11flagsfalse/Room6/SwiftDataV11. Evidence: evidence/2026-10-23-notification-preference-ordering.md. Full APK1–4/RC remains incomplete; continue actual resale purchase/sale, then lifecycle/privateimages/atomicRPC and remaining scope. Do not redo142 or reask settled currency policies.

## Slice143 — 2026-10-23: actual native resale purchase

New Investment/asset purchase form writes exact quantity/unit/total order, promotional stock, funding/FIFO/derived fund effects and outbox atomically. Backdated buys rebuild later sales; card/FX/LongMAX and same-accounting-currency fund consent enforced. Stable explicit no-write retry proves complete same-asset FIFO/global fund publication; no hidden repair or partial/orphan writes. Owner/caller/read-failure/restore/dependency boundaries covered. Final2085JVM/200zero, Swift627zero, fullRoom304GREEN, newpurchase12GREEN plus finalguard3nativeGREEN, history19+visual1GREEN20 after evidence-backed IME fixture correction. Initial fullInvestment100 had1legacytimeout; no final whole-package GREEN claim. Allchecks/lint/build/18nativeviews pass. Version142 main/DB/Investment installed and hashes match on API36 emulator only. All11flagsfalse/Room6/SwiftDataV11/noSamsung/cloud/prod/deploy/migration/push. Evidence: evidence/2026-10-23-investment-purchase.md. FullAPK1–4/RC incomplete; next actual sale/FIFO/lifecycle/privateimages/atomicRPC and full remaining scope. Do not redo143 or reask settled currency decisions.


## Slice144 — 2026-10-23: actual native resale sale and liquidation

Actual Investment/asset Sell form now records real SELL, unit-aware FIFO capital/profit/cash accrual and outbox atomically. Shared typed buy/sale creation preserves complete source/canonical history/publication/owner/caller/CAS proofs and no-write known-result retry, including sold-out stock. Exact Foundation quantity/Long/FX, card rejection, gift basis, zero-revenue loss/default note, linked setup, unknown stock and malformed historical units are covered. Downstream reserved consumption requires exact consent even when total use stays equal but moves between transactions. Trade-specific neutral review copy and stale empty-review conflicts apply to both forms; no automatic replay after source changes.

Final2103JVM/201zero,627Swiftzero, fullRoom311GREEN7.262s, actualSale14+Buy13GREEN27/135.052s, lint/build/all11script checks pass.24 refreshed/hashed/inspected native ENVIJA lightdark actualfont130/320 views; final paid/loss header pixel checks GREEN26.712s disproved a suspected overlap, no clipping change. Main143 SHA4ecd54bdbfaaca0b7f49484f3255153eab7c18a445ad93a74754c865bb40ecf2 installed/hashmatched alongside DB/Investment; COLD1429ms observational. Source23files167187bytes SHA180aa7aede1f47acacabd9b6d01f3a0962b51daa6f99842e28b4017a979df650. All11flagsfalse/Room6/SwiftDataV11/noSamsung/livecloud/prod/deploy/migration/push. Evidence: evidence/2026-10-23-investment-sale.md. Author scoped Swift/diff review only, no whole-branch or fullInvestment/native-app acceptance claim.

Separate144localcommit then immediately145 global fund-allocation comparison/confirmation correctness (verify ordinary-income equal-total A→B reallocation with runtimeRED). Then trade lifecycle/privateimages/atomicRPC/family/receipts/background/settings/RC and remaining fullAPK1–4 goal. Preserve settled currency policies; do not redo OAuth/account-switch setup or completed143/144.


## Slice145 — 2026-10-23: global reserved-cash reallocation consent

Ordinary/payment/lifecycle and actual trade planners now share an exact per-transaction wallet/booked/unreconciled comparison. Equal wallet totals moving consumption between transactions/buckets require explicit source-bound consent; ordinary-only availability/map-order changes do not invent allocation changes. Canonical ENVIJA allocation review copy distinguishes genuine equal-total reallocation from an unchanged primary's existing Use fallback. Pure/Room/editor runtime RED→GREEN cover no writes before consent, Cancel, exact moved derived DELETE/UPSERT and complete no-write retry. A scoped review's fallback-copy regression was reproduced/fixed. No Swift runtime/schema change; direct Swift aggregate-preview limitation documented.

Final2107JVM/202zero,627Swiftzero, lint/build/all11checks pass. Accepted native501 acrossfullTransactions100GREEN276.335s/fullRoom312GREEN7.663s/model35GREEN0.227s/payment27GREEN158.528s/buy-sale27GREEN189.633s. Initial100run had1oldOverview Recent-node timeout; compact400dp screenshot/semantics proved lazy row outside composition after correct financial load. Test now actually scrolls the vertical list, preserves real tap/exact money/outbox checks; focused1GREEN and full100GREEN. No product Overview change. Six new native LongMAX ENVIJA lightdarkfont130/320 views hashed/inspected. Main144 SHA82cd39b600ffcd8b6889f7974a918d129602c21ebe742991131e33fc840785de andall6 APKinstalled/archivehashes match; COLD1497ms observational. Source15files50268bytes SHA77efd7010331e928ce72695266e39606669c6c4e3ca483016819c2a4873ae6f7. Evidence: evidence/2026-10-23-investment-fund-reallocation.md. All11false/Room6/SwiftDataV11/noSamsung/livecloud/prod/deploy/migration/push. No whole-app/fullPlanning/fullInvestment/finalbranch acceptance claim.

Separate145localcommit then immediately146 actual trade detail/Delete, including source/canonical/FIFO/global fund consent/atomic Room/native routes and exact tombstone retries. Detailed read-only research /tmp/mistia146-research.md; no146product edits in145. Then trade editing/privateimages/atomicRPC/family/receipts/background/settings/RC and the full remaining APK1–4 goal. Preserve all settled currency policies; do not redo OAuth/account-switch setup or completed143–145.


## Slice146 — 2026-10-24: native trade detail and exact deletion

Actual Investment activity/cash-history trade rows open owned detail with full quantity/money/FIFO/wallet/rate/date/note values and explicit Delete. All active history is reachable through chronological virtualized rows. Typed deletion atomically tombstones canonical legs/postings, rebuilds remaining unit-aware FIFO/global fund effects, rejects dependent-stock deletion and requires exact fund consent. Complete source/publication/owner/caller/CAS/orphan proofs and no-write deleted-result Retry preserve unknown/Long metadata. Read failures, dependency replacement, restore and queued canceled callbacks revoke ephemeral authority. Existing automatic-adjustment labels survive language changes. Direct author Swift/diff review; no Swift runtime/schema change.

Final2119JVM/203zero, Swift627zero, lint/build/all11checks pass. Accepted525native: fullRoom321/model35/payment27/trade-detail-and-forms42/fullTransactions100. Initial fullInvestment131126/5 contained one uncomposed lazy Add assertion and four calendar-rollover fixtures: fixed expense24T00 was earlier than a current-day24 sale. Existing wait/scroll plus relative-future expense and actual submitted-order assertion now pass in final42; no final wholeInvestmentGREEN claim. InitialTransactions99/100 secondArchive-confirm timeout remains causally unproven; unchanged focused1 passed and final full100GREEN353.654s with failure-only diagnostics. No product lifecycle fix claim.24 native ENVIJA light/dark/font130/320 originals hashed/inspected, exact money/header/action checks pass. Main145 SHA4122f7c4a1e700ea15837fdfd235d6a5584e90a799d8940516ea7cb90f501062, all6APKinstalled/archive hashesmatch; COLD1918ms observational. Source25entries166440bytes SHA1b088b73e57a3e57d2323a7f7fefe34e2a97de9519b98cec106e9a334d99163f. Evidence: evidence/2026-10-24-investment-trade-deletion.md.

All11flagsfalse/Room6/SwiftDataV11/noSamsung/livecloud/prod/write/deploy/migration/push. FullAPK1–4/RC active. Separate146localcommit then immediately147 trade-form ephemeral prompt/retry revocation (ten actual native tests and design/plan prepared onlyin/tmp/mistia147-*; no147product edits in146). Full financial trade editing research in/tmp/mistia148-trade-edit-research.md includes immutable kind, asset moves, both histories, old-leg-excluded affordability, two-asset Room publication and exact retry. Then privateimages/RPC/family/receipts/background/settings/RC and full remaining scope. Preserve all five currency policies; no new product question or OAuth replay needed.

## Slice147 — 2026-10-24: trade-form callback revocation and live input

Actual shared BUY/SELL form now revokes queued Save after Close, old financial-review callbacks after Cancel/reopen and old Retry after edits/reverts or a read failure/recovery. Private read epochs prevent late preflight from reopening a stale review; keyed button presentations keep captured native actions from redirecting to a later grant. Current explicit committed-result Retry tolerates metadata-only asset/wallet ACKs while typed core/Room proves the exact complete no-write result. Primary Save reconstructs live fields/resources/rates and validates current snapshot stock, so same-turn input then Save persists current money. Stable draft restore/linked setup/default gift/loss/stock/FX and all five currency policies retained. No UIcopy/schema/wire/Swift runtime changes.

Runtime TDD: initial10RED→10GREEN; readrecovery2RED→12GREEN; ACK2RED; expanded18first14pass/4fail, intermediate9pass/9fail exposed reused-native-handler and capturedstock regressions. Diagnostic3RED→3GREEN11.196s; final18GREEN101.893s and completeBuy22+Sale23+Detail14=59GREEN362.305s. Full2119JVM/203zero/Swift627zero/lintbuild39s/all11checks/whitespace pass. One fresh independent scoped review found no actionable introduced defect; declined considerations explicitly ruled in evidence. Main146 20DEX36002164bytes SHA49a365c1d553e01ab137067a347d134a333182ec58030ba0ef88bd0101aab122 andInvestmenttest archive/installed hashesmatch; COLD1235ms observational. Source4entries49478bytes SHAf7f594cdfbf5ee82a15dcc4ac93dac71214e52546ccb41b38b79347ba91c2299 against892bf255. Detailed evidence: evidence/2026-10-24-investment-trade-form-revocation.md. No wholeInvestment149/wholeapp/finalbranch acceptance claim; completed146 native originals/archives remain intact.

All11flagsfalse/Room6/SwiftDataV11; API36ARM64transport16 only/noSamsung/liveSupabase/prod/write/deploy/migration/push. FullAPK1–4/RC active. Separate147localcommit then immediately148 typed full financial trade editing: immutable kind/stableid/createdAt, original+target asset histories, excludesoldfunding affordability, global exactfundconsent, twohistorypublication/rollback/no-writeRetry, owned native routes/hydration/restore147authority. Research/tmp/mistia148-trade-edit-research.md; design/plan prepared/tmp before147commit, no148product changes in147. Then privateimages/atomicRPC/family/receipts/background/settings/RC and full remaining goal. User explicitly authorizes autonomous slices and commits; no repeated approval or OAuth/account-switch replay.


## Slice148 — 2026-10-24: actual financial trade editing

Owned activity/history detail now opens real Edit with stableID/immutablekind/createdAt, exact quantity/unit/total/date/note/wallet/free-loss and stored sourceFX. Typed Edit/privateCreate-Edit engine rebuilds original+target asset histories, rejects dependent-stock moves, excludesold3legs from current cash/card capacity and atomically publishes canonical legs/globalfund effects. Exact sourceconsent, fullnineentityCAS, bothhistorypublication, capturedcaller/currentowner/finaltransactionfences and no-write committed-result Retry retained. Restore keepsoriginalbaseline, cannot overwrite unseenprimary;147 callbackauthority andcurrentinput apply. No schema/wire/newcopy/Swift runtime change.

Meaningful pure8runtimeRED→GREEN, missingoldfundingtombstoneRED→GREEN, actualRoom unsupportedRED→4GREEN and actualmissingEditrouteRED→native3/7/8/13GREEN. One fresh scoped review found2P2: foreignzero→paid missingrate actual2RED8.574s→2GREEN9.661s; malformedretiredmoney/link pureRED→newfinancialretiredproof, foreignprofit and coherentRoompublication tests. Deliberate Android improvement over Swift's samezero-rate limitation: originallyzero usesavailablecurrentrate, existingpositivekeepsstoredrate. No claim Swift runtime fixed or independentfinal-cleanreview after the TDD correction pass.

Final2139JVM/204zero (model926/database333), Swift627zero, reviewedhostlintbuild1m17s/all11checks/whitespace pass. FullRoom328GREEN13.477s andcompleteBuy22+Sale23+Detail14+Edit18=77GREEN486.512s; acceptednative405.18hashed/inspected nativeENVIJA lightdark actualfont130/320 sheet/review originals retain exactLongdigits/text/actions. Read-only currency symbol maywrap; no missing-valueclippingfix fromcontact-sheet presentation artifacts. Main14720DEX36830810bytes SHA304740c1dc789264463e6d00a4d2396e3771d56792629fbf6b23495cdb3530a3; all3APKinstalled/archivehashesmatch, COLD1174ms observational. Source14entries120215bytes SHA64edfbc3b92218bf520b6c96ff71459d57035081e3041e1cec3e326b613983c9 against0137d408. Evidence: evidence/2026-10-24-investment-trade-editing.md. No wholeInvestment167/fullPlanning/Transactions/wholeapp/finalbranch acceptance claim.

All11cloudflagsfalse/Room6/SwiftDataV11; API36ARM64transport16 only/noSamsung/liveSupabase/productionwrite/deploy/migration/push. FullAPK1–4/RC active. Separate148localcommit then immediately149 owned private productimages/cache/staging/actualcamera-PhotoPicker/thumbnail/gatedStorage foundation, then150existingatomicRPC/orderedpublication/cleanup and fullremainingfamily/receipts/background/settings/security/signing/physicalRC. Read-only149research/design in/tmp/mistia149-image-research.md and/tmp/mistia149-design.md; no149productsource in148. Supabase skill/currentofficialdocs/changelog consulted for nextscope only, no projectmutation. Preserve allfivecurrencydecisions, no repeatedapproval/OAuth/account-switch replay.


## Slice149 — 2026-10-24: private owned product photos

Completed actual native Photo Picker/camera/preview/replace/remove/Cancel and thumbnails in inventory, activity, trade picker/detail and cash history. Frozen staged identities and submitted proposals survive saved-state restoration; stale form/picker/retry callbacks cannot attach or publish another proposal. JPEG1600px/<=4,000,000bytes,240px thumbnails, dark/light transparency and thumbnail sizes/rounded placeholders match the directly read Swift implementation. Typed Room save binds real immutable staged bytes and a reserved revision, full-source CAS, protected outbox coherence, final current-owner/captured-caller checks and atomic metadata/outbox/legacy-unit financial effects. Exact uncertain-result retry never rewrites a known committed result. Private Storage reads/cache and gated immutable upload/delete primitives are present; all11flagsfalse.

Final2206JVM/209suites zero,627Swift zero, app lint/build/native packages, all11checks and whitespace pass. Complete Room343/343GREEN8.381s and complete Investment189/189GREEN1078.039s, no failures/ignored cases; accepted native532 across those two full suites. The earlier interrupted Investment attempts are historical and not counted. Author Swift/diff review fixed an uncertain-result UI retry gap and dark transparent-PNG mismatch through actual runtime RED→GREEN. Final review is by the author, not an independent whole-branch review. No full Planning/Transactions/whole-app/final APK1–4 acceptance is inferred.

Main148,20DEX,38334907bytes SHA946334856e0944f8c788b33acf41cef29a855e353718550fd2fb4c4322d2e75d. Main+Investment+database archives and installed SHA all match (slice149-artifacts.json); install-r preserved data, main COLD Statusok1229ms is observational. APK: android/build/outputs/apk2/2026-10-24/mistia-0.2.0-apk2-investment-product-images-v148.apk. Frozen38-file Android patch237399bytes SHA97a9fd0f91927913f1bc1392add1ec343c37c0f99b849c0e58bade79d07bb92e against5f2a2c0d; slice149-source.patch/json. Six native scrolled photo preview originals EN/VI/JA/light/dark/font130/320dp are hashed and visually inspected. Evidence: evidence/2026-10-24-investment-product-images.md.

API36 ARM64 emulator transport16 only; no Samsung, live Supabase, production write/deploy/migration/push or OAuth/account-switch replay. External OEM camera/gallery apps were not automated; native tests use controlled ActivityResultRegistry results through real contracts/provider/JPEG/cache/Room. Room6/SwiftDataV11 unchanged. Next150: existing atomic investment RPC publication, upload-before-metadata, version/path/revision-specific ACK/conflicts and conservative startup reservation/cleanup reconciliation. Unknown reserved/orphan bytes remain held until that coordinator can prove their state; no unsafe deletion. Commit149 now, then continue150 and the full APK1–4/RC goal.


## Slice150 — 2026-10-24: closed investment channel publication

Dedicated owned channel client/coordinator now registered at priority100. Explicit Long/null/opaque JSON, exact owner/id/version filters, strict session/caller/gate fences, status-safe errors, bounded/cancelable HTTP and closed-entity policy preserve the ordinary investment-writer denials. Atomic row/dirty/queue publication snapshot plus typed Room ACK/failure protect newer mutations, owner/caller changes and every queue stamp; reserved wallet remains pending. Author Swift review fixed valid local-winner version jumps, equivalent archived timestamp comparison and a missing device-stamp coherence check through observed runtime RED→GREEN. No independent clean/whole-branch review claim.

Final2245JVM/212zero,627Swiftzero,lint/build/native packages/all11checks/whitespace pass. FullRoom354GREEN8.242s and fullChannelUI10GREEN38.098s (accepted native364), including EN/VI/JA/lightdark/font130 regressions. FullInvestment189 is149 evidence, not150; no broader native/fullgoal claim. Main149,20DEX,36996311bytes SHA9c91e7f55be53f23b5aa7ca39e36678dc46fff42a8acb0163020e230070c555c. Main+Room+Investment archive/build/installedSHA match (slice150-artifacts.json), install-r/COLDStatusok1161ms observed. Source13files71856bytes SHAdcf154a01e56d8dca89ca44ba86a25e56955a1031289eb37bb5ecb1378630c31 against6d844c19 (slice150-source.patch/json). Evidence: evidence/2026-10-24-investment-channel-push.md.

All11flagsfalse/Room6/SwiftDataV11, emulatorAPI36ARM64transport16 only; noSamsung/livecloud/production write/deploy/migration/push/OAuth replay. Channel publication is the prerequisite discovered before asset RPC; canonical reserved wallet stays in its dedicated domain, not the ordinary writer. Next151 atomic asset RPC and private image upload-before-metadata/recovery/ACK/cleanup, then trade/cash RPC and remaining full APK1–4/RC. Commit150 now and continue; full goal remains active.

## APK4 asset publication slice151 — 2026-10-26

- Added a closed owned asset fetch/mutate/delete RPC client and asset110 coordinator after channel100. Expected-version0 creates and exact Long CAS updates use forcefalse; server versions remain authoritative. Source/session/caller/dependency gates, conflict/race/retry behavior, safe HTTP status and no ordinary investment writer fallback are covered.
- Bound explicit photo revision/previous path/hash intent to the actual Room asset+exact outbox transaction without a schema bump. Keep preserves latest remote photo; same-photo ACK may cross a later rename without consuming that queue. New photo revisions reject old ACK. Trusted Room/cache recovery handles committed-but-unpromoted candidates, legacy hold/explicit empty-photo repair, confirmed old retries and lost superseded bytes. Upload precedes metadata; cleanup requires matched confirmation and fresh references including restorable tombstones. Dirty trade/cash/posting queues remain intact.
- Runtime TDD, direct author Swift/SQL/diff review and final host2298JVM/215suites zero, lint/main/both native-package build, Swift627zero and11scripts0. Full Room376GREEN10.894s plus full Investment197GREEN1013.412s =573native, no ignored cases. An interrupted initial197run is excluded; the full rerun used the same immutable APKs after cold-boot recovery. Existing gallery/camera contracts and multilingual/font/dark-mode flows remain covered; no OEM automation or Samsung claim.
- Local PostgreSQL: all77repository migrations verified, all251pgTAP assertions across6files PASS, including investment_domain.sql. The CLI's post-reset full-stack health stage failed on a network mismatch, so only direct fresh-DB pgTAP is accepted. Its default port bindings were repaired to127.0.0.1 and inspected before/after tests; all our containers/Desktop stopped afterward, volumes retained. No SQL/source migration, production deployment/link/write or OAuth replay.
- Main150 min26/target36/20DEX/signing verifies; all11flagsfalse, Room6/SwiftDataV11 unchanged. Main APK36217292bytes SHA25686b9b8257c248a9d8bbc268741bcb751fc3e80b699dd38a0949adbe40f3de698. Source28files/152497bytes SHA2562d5ba1c76b3c851cccad2e429eb861cdc3e5c8e5f77e73df0420b035daad5075 against032d8593. All3build/archive/installed hashes match; install-r preserves data; COLD Statusok1583ms observational. Archives: android/build/outputs/apk2/2026-10-26/slice151-artifacts.json and mistia-0.2.0-apk2-investment-asset-publication-v150.apk. Previous149/148 artifacts are retained.
- Evidence: docs/android/evidence/2026-10-26-investment-asset-publication.md. Next closed canonical investment-wallet metadata prerequisite (trade SQL requires the cloud root wallet), then trade/cash RPC and derived results. Engine de-duplicates push coordinators by entity, so a root-wallet publisher must compose with ordinary wallet publication without widening its gate or dropping either path. APK1–4/RC is **not complete**; continue autonomously.

## Slice152 — 2026-10-26: causal asset publication

Real Room/files/HTTPS tests reproduced three failures when an older asset RPC commits at server00:30 while the user saves a name/photo at local00:15. The old queue remained protected, but the next timestamp-first sync could consume the new proposal. A bounded strict local-only parent fingerprint journal now accompanies the actual row/outbox mutation, recognizes a proven own prior server write and retains ambiguous own winners as conflicts. Only the asset coordinator uses the hook; other-device/shared policies stay intact. Both private keys are stripped on wire and refused at dedicated/generic ingress. Existing photo authority remains in Room/cache proof.

A further actual7→8 compared-base regression was RED then GREEN after definite superseded-RPC receipts atomically append actual server fingerprint/version to the newer coherent row+queue. All business, dirty, received-at, base/device/date/attempt/retry/error stamps remain. Final owner/caller fences and rollback cover both writes. Lost-reply unknown version gaps remain held, never guessed. Typed receipt cannot consume trade/cash/posting queues. No UIcopy/schema/Swift/SQL/migration/currency-policy change.

Final2312JVM/216suites zero, Swift627zero, lint/main/both native-package build1m4s plus final test-fixture refresh5s,11scripts0 and whitespace pass. FullRoom382GREEN8.724s and fullInvestment201GREEN1204.728s =583native,0ignored. Fresh independent scoped static review found no actionable introduced P1/P2; no whole-branch clean claim. Original3nativeRED→GREEN and higher-base1RED→GREEN,2modelRED→GREEN plus strict/bounded/opaque and6new Room receipt/rollback tests are recorded in evidence/2026-10-26-investment-asset-causal-publication.md.

Main151 min26/target36/20DEX, 36217292bytes SHA256 `24d5b38fd102286889b0bd6401ef6254da6406f9dc9636fd1d73a284c3bf4694`; same debug certificate,11compiledflagsfalse. Source18Androidfiles/55018patchbytes SHA256 `c3f156b2d3e17829c7d8bbe628b1084e387b57e9a2e7d42fbb4250dd8f918f15` against53556917. All3build/archive/installed SHA match; install-r preserves data; cold launch Statusok is observational. Immutable APK/source/log manifests: android/build/outputs/apk2/2026-10-26/slice152-artifacts.json and mistia-0.2.0-apk2-investment-asset-causal-v151.apk. Existing151 SQL77migrations/251assertions evidence is retained, not rerun for unchanged SQL.

API36ARM64transport17 only/noSamsung/liveSupabase/productionwrite/deploy/migration/push/OAuth replay; Room6/SwiftDataV11 unchanged. FullAPK1–4/RC remains active. Commit152 independently, restore the7hashed root-wallet WIP files from /tmp/mistia-root-publication-wip-preserved/manifest.json and continue153 canonical root metadata/composite wallet publication, then trade/cash RPC and remaining family/receipts/background/settings/security/signing/physicalRC. Read-only next research /tmp/mistia153-root-next-observations.md corrects a server-clock assumption: ledger_wallets set_updated_at also uses servernow, and current_balance_minor is server-derived; omit derived money fields and test causal link protection. No new product question needed.

## Slice153 — 2026-10-26, canonical investment-wallet publication

Closed deterministic root metadata HTTPS/coordinator, typed exact Room source/ACK/failure/definite superseded receipts and local64parent evidence protect newer link choices across serverclock late/lost replies. Derived money/immutable currency authority excluded, ordinary reserved-wallet writer remains closed. One four-phase wallet entry resolves dirtytarget/oldwalletretirement dependency with exact opt-in guard/directselection and retry preservation. Root Room transactions fence captured session at commit; readonly root presentation ACK keeps frozen picker confirmation valid. Reserved target purpose must be NULL.

Runtime RED→GREEN and independent scoped static review caught/fixed combined dependency and final session-fence P2s; follow-up reports no remaining introducedP1/P2. Full2382JVM/222suites,627Swift,400Room+218Investment=618native,lint/build/11checks0; all3APK build/archive/installed SHA verified, sourcefrozen23files172462bytes SHA007d5b3c29f2e7982256c0bf86023ffc8edb922c141b47d6cb3c66c1180b7c33. Main152 SHA45fa4d4a37b7373a2f32e7f10342ad58b4568e925176454783ae1fc3a113f380. See `evidence/2026-10-26-investment-wallet-publication.md` and archive `android/build/outputs/apk2/2026-10-26/slice153-artifacts.json`. Initial wrong-manifest native run excluded; final installed hashes verified before suite. All11flagsfalse; no Samsung/liveSupabase/productionwrite/deploy/migration/push. Historical151SQL77migrations/251assertions retained unchanged. Full goal remains active.

Next concrete work: trade RPC is atomic and returns a rebuilt multi-trade result, not a generic table row. Publish current owned trade intent only after channel/asset/root/realwallet prerequisites, reconcile exact derived financial queues without consuming newer work, validate units/zero-amount/crossasset/FIFO/version semantics against effective SQL. `investment_rebuild_asset` advances trade versions after INSERT/CAS, so do not reuse root exact-proposed or asset expected+1 reply rule. Actual serverclock/session/owner/rollback tests required. Read-only research `/tmp/mistia154-trade-publication-research.md`; no implementation yet. Keep Docker/emulator sequential, no Gradle/build/install/instrumentation overlap. Continue cash/family/RC after dependencies, not just metadata ports.


## Slice154 — 2026-10-27, closed investment trade publication

Closed captured-session/gated trade RPC client, complete owned keyset result reads, bounded causal parents/definite delete-rebuild receipts, intermediate FIFO scheduling and atomic full financial ACK are implemented with ready metadata. Exact whole-generation/queue/session/owner/caller proofs preserve newer work. No generic financial writer or unrelated cash-operation ACK. Discarded edit→delete imports actual server tombstones; alive opaque intent and full parent fingerprints remain exact.

Actual runtime TDD and independent scoped review resolved three P2s: captured sibling ancestry, four oldest-first deletions and dependent BUY/SELL edits. Additional final source-fence/HTTP/ingress/deletion regressions were reproduced and fixed. Follow-up reports no remaining introducedP1/P2 within this disabled foundation, not whole-branch/production readiness. Metadata retirement integration and cash RPC remain explicit next work.

Final2525JVM/231suites zero,627Swift zero, lint/build/native packages57s/all11scripts0; local77existing migrations/7pgTAPfiles278assertions PASS (27new, no migration change). FullRoom436 GREEN 10.997 s plus fullInvestment237 GREEN 991.384 s =673native, no ignored cases. All3build/archive/installed SHA match before and after suites, install-r only; COLD Statusok observational. Source31Androidfiles305464bytes SHAe8f8ed8929d9840215be8165bf5e36a6d442e8fc0bd922441485d56e2d74b8eb against9b164739. Main153 min26/target36/20DEX/37268929bytes SHA359985b2cf9d175da4ebe2dfd41194e7eea7723710616f81ff666219f679380e. Evidence: `evidence/2026-10-27-investment-trade-publication.md`; archive `android/build/outputs/apk2/2026-10-27/slice154-artifacts.json`. Initial aapt parser failure stopped before manifest/install/native and is excluded.

All11flagsfalse/Room6/SwiftDataV11 unchanged; API36ARM64transport18 only/noSamsung/liveSupabase/productionwrite/deploy/migration/push/OAuth replay. Docker/own5containers stopped with volumes retained before native. Full APK1–4/RC remains active. Commit154 independently and continue asset/channel retirement coordination: offline close→archive or move→archive currently encounters cloud position guards plus metadata-first/trade-clean prerequisite cycle. Include combined rename/unit/photo/archive and stale/session/result fencing, not a universal dirty-metadata bypass. Then separate cash RPC, family and full RC.


## Slice155 — 2026-10-27, investment metadata retirement coordination

Baseline479d72fa, main154. One engine entry runs channel→asset→trade→asset→channel. Exact owned active metadata proves archived prerequisites without consuming archive queues; prepared active stages survive lost/late replies and rebase only metadata versions after matching causal proof. Newer business/photo intent and retry/session/owner/caller authority remain protected. Actual root-wallet publication precedes new target channel/asset creation. No generic financial writer or unrelated cash-operation ACK.

Complete owned history reads, per-unit FIFO closure and original-cloud move dependencies guard final retirement. Fractured cross-read histories defer; final-archive400 retries narrowly,403 remains permanent. All due metadata gets one turn so100 held archives cannot starve later targets; future backoff is preserved. Real JPEG/cache/Storage cases cover upload order, Keep/newer replacement and delayed cleanup. NULL legacy history follows the actual label/rebuild version increments without synthetic trade resurrection.

One fresh static reviewer reported a P2 cross-read race; actual native/model RED→GREEN fixed it. Full initial Investment262 had261passes and one metadata-retry pointer timeout. The exact APK passed three focused repeats; its Sale test now uses the same actual accessibility OnClick as the previously corrected Purchase counterpart, preserving2successful saves, unchanged rows/queues and the5second deadline. No product UI behavior was changed or declared fixed.

Final2566JVM/236suites zero,627Swift zero, app lint/build/native packages and11scripts0. FullRoom451 GREEN20.041s plus fullInvestment262 GREEN1546.98s =713native, exact statuses/no ignored. Build/archive/installed SHA match before and after; install-r only, main154 COLD Statusok2280ms (observational). Android40files/227709bytes SHA8d79023fd09c65a73f04c7916a01acee70b6720627bcd5ec7d1d6f2c13eb691c. Main154 min26/target36/20DEX/36479432bytes SHAe80a0a53ffe67ae85fa04441c8771047a9734296f56cf826d2c3e3f355f87348. Same debug certificate. Room6/SwiftDataV11 and SQL77migrations unchanged; localSQL278 remains historical154 evidence, not rerun155.

Evidence: `evidence/2026-10-27-investment-retirement-coordination.md`; source/APK/log manifest: `android/build/outputs/apk2/2026-10-27/slice155-artifacts.json`. Accepted154 and failed initial155 artifacts remain immutable. API36ARM64transport18 only, no Samsung/liveSupabase/productionwrite/deploy/migration/push; all11flagsfalse. Full APK1–4/RC stays active. Next: separate cash-event/allocation RPC, remaining family/receipts/background/settings/security/signing and final Samsung RC. Preliminary source notes `/tmp/mistia156-cash-publication-research.md` are not implementation.
