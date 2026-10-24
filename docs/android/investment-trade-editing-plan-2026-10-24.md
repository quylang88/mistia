# Investment financial trade editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan inline. Steps use checkbox syntax for tracking. User TXT supplies autonomous execution and independent slice commits.

**Goal:** Edit existing resale BUY/SELL through actual native routes with exact atomic FIFO/fund publication and stable identity.
**Architecture:** Typed edit intent extends the private creation engine through explicit edit mode. Rebuild original and target histories and global fund effects in one trusted Room transaction. Reuse owned147 form with immutable kind and stored-rate hydration.
**Tech Stack:** Existing Kotlin/Compose, Room6, BigDecimal/Long, Swift reference.
**Spec:** docs/android/investment-trade-editing-design-2026-10-24.md

## Global Constraints

- All11cloudflagsfalse/Room6/SwiftDataV11; no production writes/deploy/migration/push.
- All five settledcurrency decisions retained; no OAuth/manual account-switch replay.
- Runtime RED→GREEN before behavior changes, complete relevant suites, direct Swift/diff review, evidence/progress/handoff, independent local slicecommit.
- Work in current user-requested branch codex/android-apk2-4-parity at /Users/quyln/Project/mistia. No checkout/reset/discard/rebootstrap; preserve completed147 archives.

## Review Focus

- Asset move cannot leave original dependent sales understocked or skip original history's outbox proof after committed retry.
- Existing purchase funding is excluded from current capacity, including card liability; new wallet still uses current complete balance.
- Switching free/loss must clear nullable fields and retire old legs without restoring unrelated tombstones.
- Restored edit draft cannot silently bind newer unseen primary; ACK-only change stays usable.
- Native queued actions must use current fields and revoked grants remain revoked across close/readgap/rebind.

### Task 1: Complete typed financial editing

**Files:** new core/model InvestmentTradeEditing.kt and InvestmentTradeEditingTest.kt; modify InvestmentTradeCreation.kt, Contracts.kt; database InvestmentTradeRepository.kt, Repositories.kt, MistiaDatabase.kt and new InvestmentTradeEditingRoomTest.kt; shared InvestmentTradeCreationSheet.kt, InvestmentTradeDetailSheet.kt, InvestmentScreen.kt and new native InvestmentTradeEditingScreenTest.kt; canonical Localizable.xcstrings only if existing Edit copy cannot cover title, regenerate outputs.
**Interfaces:** produce InvestmentTradeEditDraft (id,assetId,kind,quantity,unit,grossMinor,accountingMinor,accountingCurrency,sourceRate,rateProvider,rateDate,walletId,walletMinor,walletRate,note,occurredAt,createdAt); InvestmentTradeEditRequest(expectedTrade,draft,expectedAsset,expectedWallet,consent,adjustmentTitle); planInvestmentTradeEdit(snapshot,request,deviceId,now):InvestmentTradeEditPlan; typed InvestmentRepository.editTrade and LocalStore.commitInvestmentTradeEdit; internal engine explicit Create/Edit expected; private Room protected asset ID set. Public edit plan/review/consent may typealias shared exact structures without accepting a generic writer.

- [x] Write first literal pure test: buy2cost100 then sale1gross80; edit buycost120 => laterbasis60/profit20, remaining1cost60, wallet960. Initially public typed boundary may throw UnsupportedOperationException to permit actual feature-runtime RED, not compiler failure. Run :core:model:testDebugUnitTest --tests '*InvestmentTradeEditingTest'. Expected actual assertion/unsupported-feature failure.
- [x] Implement minimal typed edit planner/explicit private mode with no relaxed create semantics. Expand meaningful RED→GREEN for edit sale1→0.5 changes basis25/profit55/stock1.5, original funding excluded, assetmovebothhistories and dependent sale rejection, immutablekind/createdAt, paid/free and loss/receipt identity tombstones, exact no-write/partial/stale/metadata/Long/FX, fundsource equality. Whole model suite GREEN.
- [x] Write real Room unsupported-edit runtime RED. Implement typed repository/store and protected original+target asset sets, complete publication and final owner/caller fences. Add finalqueue rollback, stalefullsource, owner/caller, malformed/missing old+newhistory outbox and exact retry. Run focused then fullRoom native with zero failures.
- [x] Write actual native missing Edit route RED. Implement stable owned edit hydration, prefill, current storedrate/current pair, excludesoldstock, typed Save, return refreshed detail/Cancel, normal baseline restoration and147 callbackauthority. Prove actual financial records/outboxes and no-writeCancel.
- [x] Expand native tests: purchase/sale edit, assetmove+dependentstock error, free/loss transitions, fundCancel/currentconfirm, lostresponse/no-writeRetry, restore/unseenprimary, rebind/readgap/late callbacks/currentinput, ENVIJA both themes actualfont130/320 and exactLongmoney. Watch each meaningful feature/bug RED before correction; run complete changed form/detail/Room scopes.
- [x] Run full testDebugUnitTest, Room AndroidTestcompile, lintDebug, assembleDebug; Swift627 and11contract/localization/guard/icon/fold/Roomasset checks; direct Swift/diff and fresh scoped review. Fix actionable findings with runtimeTDD then appropriate complete suite.
- [x] Bump main147, archive source patch against147commit and relevant APKs/sha/install-r/installedhash; actual emulator evidence only unlessSamsungconnected. Update dedicated148evidence, progress/handoff, design/plan completion and local commit immediately. Continue privateimages/atomicRPC/family/receipts/background/settings/RC/fullgoal.
