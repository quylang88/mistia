# Mistia Android session handoff — 2026-09-22

> Latest accepted checkpoint (2026-10-24): **slice149, product photos, main148** on `codex/android-apk2-4-parity`. Full2206JVM/627Swift/343Room/189Investment and lint/build/11checks pass; see the final Slice149 section and its evidence. Continue150 atomic investment RPC/image publication and the remaining APK1–4/RC scope. Earlier baseline/auth sections below are historical: Google login is already validated; do not repeat OAuth/account-switch setup. All11cloud flags remain false. Current device is an API36ARM64 emulator, not Samsung.


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
