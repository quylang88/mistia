# Investment asset management implementation plan

> For agentic workers: use superpowers:executing-plans inline, preserving the user's autonomous per-slice workflow. Checkboxes track the current vertical slice; the user requires its independent commit after complete verification.

**Goal:** Actual native asset create/edit/archive/restore, including atomic financial rebuilding when legacy units are first resolved.
**Architecture:** Strict model planner over an owner-scoped six-entity snapshot; repository retries conditional Room writes; a separate native asset editor observes the complete readset while existing channel APIs retain their four-entity contract.
**Tech Stack:** Kotlin/Compose, Room6, Long money/129 Foundation-compatible decimal FIFO, coroutines, shared xcstrings, JVM/real SQLite/native tests.
**Spec:** docs/android/investment-assets-design-2026-10-21.md

## Global constraints

- Baseline38d6b2aa, branch codex/android-apk2-4-parity; preserve changes and existing Google auth. No pull/reset/history rewrite.
- Keep all11 cloud flagsfalse; no production write/deploy/migration. Future investment RPC remains separate.
- Preserve exact Long versions, explicit nulls, source currency, owner identity, tombstones, unknown fields and creation metadata.
- Runtime RED→GREEN for new behavior; local per-slice commit after direct Swift/diff review and complete relevant checks. No new approval prompts except real blockers or product ambiguity.
- Private image actions follow separately; retain existing image path throughout this slice.

## Review focus

- History appearing during CAS must lock older channel/currency edits; missing required trade membership must not invent no-history.
- Retry/ACK metadata and queue-only changes must preserve latest Long version and mutation identity; no loss of a newer local edit.
- Archive prefers actual FIFO over stale persisted positions, retaining the Swift readable fallback on failed projections. Imported FX currencies scale exact minor units by their fraction digits.
- Legacy free buys follow Swift's preliminary funding dependency; malformed/missing stored rates never reuse old snapshots or guess currency.
- Obsolete deterministic ledger legs must be tombstoned even when previous link/posting rows are missing; late posting failure rolls back the whole batch.
- Owner/source replacement and late noncancellable callbacks must clear private forms and never dismiss another owner's draft.

## Task1 — asset model and repository

**Files:** core/model InvestmentAssets.kt, InvestmentAssetRebuild.kt, Contracts.kt; core/database InvestmentAssetRepository.kt, Repositories.kt; matching model/repository tests.
**Interfaces:** InvestmentAssetRecord/Draft/Request, InvestmentAssetSnapshot(owner,rows), planInvestmentAssetMutation(snapshot,request,deviceId,now) -> InvestmentAssetMutationPlan; InvestmentRepository observeAssetSnapshot/saveAsset/archiveAsset/restoreAsset.
**Produces:** strict complete wire asset, visible expected proof, deterministic batch including legacy unit/FIFO/ledger/posting changes and bounded snapshot retries.

- [x] Runtime eight model tests fail against unsupported planner, then implement create/edit/archive/restore and financial rebuild.
- [x] Runtime six repository tests fail against unsupported API, then implement scoped reads/replay/CAS/cancellation.
- [x] Corrupt unit and tombstone regression RED→GREEN; canonical obsolete ledger/preliminary funding dependency regression RED→GREEN.
- [x] Add/verify required membership, stored FX, invalid rate, history lock, complete unknown-field/version/explicit-null and source consent cases.
- [x] Verify focused model/repository tests and direct Swift parity before task completion.

## Task2 — Room transaction and cloud boundaries

**Files:** MistiaDatabase.kt, InvestmentAssetRoomTest.kt; InvestmentLedgerDomain.kt; TransactionPushCoordinator.kt and tests; SupabaseGateway.kt and TransactionDeletePostgrestTest.kt.
**Consumes:** Task1 planner/request; current owner fence and existing record/outbox commit helper.
**Produces:** observeInvestmentAssetSnapshot, investmentAssetSnapshot, commitInvestmentAssetMutation(expected,request,deviceId,now):Boolean; reserved investment ledger domain checks.

- [x] Real Room four tests RED unsupported reads/commit, then implement one six-entity owner read plus conditional transaction/fences/outbox collision check.
- [x] Verify seven real SQLite cases including full10-row rebuild, exact9007199254740993/995 versions,14 queues, late cash posting trigger rollback and history-at-CAS.
- [x] Runtime sync27/3 failures and HTTPS4/1 failure demonstrate missing reserved-ledger gates; implement queued/local/fresh role deferral and client refusal, focused31GREEN.
- [x] Add any uncovered stock/source/outbox races revealed by direct review, preserving ordinary transaction behavior.
- [x] Run complete affected Room/model/sync/network suites and confirm no production operation.

## Task3 — actual native asset flow and delivery

**Files:** InvestmentScreen.kt, InvestmentAssetEditorSheet.kt, InvestmentAssetReadLoad.kt, MainActivity.kt; InvestmentAssetScreenTest.kt and existing channel tests; app version/evidence/progress.
**Consumes:** Task1 repository APIs, Task2 consistent reads; actual primary/enabled currencies/device identity.
**Produces:** working personal asset form/list actions, saved draft and source consent, history locks, recoverable errors/retry and owner lifecycle handling.

- [x] Actual missing flow five native tests RED32.709s, then implement owner-keyed form/list/read states; first fiveGREEN16.13s.
- [x] Verify six-read membership damage cannot hide behind known history.
- [x] Add real legacy-resolution/history-lock/stock alert/menus, failed-save restoration and late callback native cases; all preserve exact rows/outbox/owner boundaries.
- [x] Verify EN/VI/JA light/dark at actual system font130 and narrow width; retain complete glyph/bounds assertions and inspect originals.
- [x] Run complete channel regressions and appropriate model/Room/other feature regressions.
- [x] Full testDebugUnitTest, model/Room/required feature native compiles/packages, lint/main, Swift611+, contracts15, both l10n checks, SQLite7/3/11, schema6 assets, finance196/111 and unit-fold1553/freshness checks; read terminal outputs.
- [x] Direct source/diff review, reproduce/fix findings with TDD, repeat affected checks. Record precise limits; final whole-branch review remains an overall-goal gate.
- [x] Version130 install-r/COLD/hash/archive verification, evidence/progress and separate local commit. Continue buy/sell/cash/private images/RPC and all remaining APK1–4/RC work.
