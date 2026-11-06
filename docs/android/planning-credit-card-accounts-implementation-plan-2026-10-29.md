# Planning credit-card accounts Implementation Plan —169

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline. The human already chose continuous work and one immediate commit per complete slice. Steps use checkbox (`- [x]`) syntax.

**Goal:** Replace Planning's credit-card count with real owned account cards and working statement/add/edit navigation matching Swift.

**Architecture:** Consistent three-domain Room read→pure owned card projection→lifecycle/error-aware Planning pane. Existing Management card editor reused through a scoped controller and actual app destinations.

**Tech Stack:** Kotlin/JVM17, Room6/Flow, Compose/Navigation, API36ARM64, Swift/Xcode parity; no new dependencies/schema/backend.

**Spec:** `docs/android/planning-credit-card-accounts-design-2026-10-29.md`.

## Global Constraints

- Workspace `/Users/quyln/Project/mistia`, branch `codex/android-apk2-4-parity`, accepted168 base `a429fa4bdc273f103c6b48b963c23271f05132fe`. Preserve WIP/archives, no reset/pull/push/PR/production.
- All11 cloud write flagsfalse. Same-currency card payment rule unchanged. No floating point money/primary conversion; actual wallet units only.
- No Planning→Management production dependency. Reuse current form/save authority, no new undo/autopay behavior.
- Tests/runtime evidence/scripts go in persistent plan workspace from the start; never rely on /tmp for final acceptance. Never overlap Docker, compilers and emulator.
- Runtime TDD, focused and appropriate full checks, direct Swift/visual inspection, one fresh final review and immediate complete169 local commit/main166 before next slice.

## Review Focus

- Owner rotation during slow load/deviceID/save must not display old account or persist a stale form; Task1/2/3 tests pin this.
- A disappeared edit target never silently becomes a new card; Task2 route tests pin this.
- Statement button inside editable card must navigate once without also opening editor; Task2/3 UI/NavHost tests pin this.
- Unknown/foreign linked source and duplicate/malformed profile rows must not expose another account or a partial successful balance; Task1/2 tests pin this.
- ExactLong and long localized money at font1.3/dark must remain readable without changing rows/outboxes; Task1/2 native screenshots/assertions pin this.

### Task 1: Real RED and consistent account projection

**Files:** New `CreditCardAccountRead.kt` in core/model and JVM tests; Contracts.kt, core/database/MistiaDatabase.kt, Repositories.kt; new Room tests. First UI regression `feature/planning/.../PlanningCreditCardAccountsTest.kt`.

**Interfaces:** `CreditCardAccountReadSnapshot(owner:UserId,rows:List<CloudRecord>)`, companion entities wallet/profile/ledger; `observeCreditCardAccountReadSnapshot(owner):Flow<...>`; `planningCreditCardAccounts(snapshot):List<PlanningCreditCardAccount>` with wallet/profile IDs/name/issuer/network/last4/currency/debt/available/sourceLabel/closing/due/order facts.

- [x] Write first real Room/repository Planning regression using existing PlanningScreen API, owner cash1000JPY/cardlimit1000/charge70; select planning.tab.1 then planning.due.1; assert visible card name/debt70/available930. Build and run API36; Expected actual missing card assertionRED on current count placeholder, not compile/seed failure. Preserve source/APK/installed hashes.
- [x] Write pure projection/snapshot tests: exact9007199254740993, source/debt/overpayment, current selected month/primary independence, posted/archive/deletion/foreign exclusion, profile ambiguity/malformed envelope, source privacy/order/Long boundaries. Missing API compile is not runtimeRED; closed stub then actual assertionsRED. Implement minimal projection/read contract; Expected focusedGREEN.
- [x] Room tests require one complete reactive owned snapshot including history/tombstones, source/profile/ledger update coherence, foreign exclusion, no queue writes, cancellation/reopen. RuntimeRED before implementation; implement DAO/repository using existing consistent-row pattern. Expected nativeGREEN and full affected JVM/Roomcompile.

### Task 2: Planning card pane and shared editor controller

**Files:** New PlanningCreditCardPane.kt/load/presentation helpers, PlanningScreen.kt; Management CreditCardEditorRoute.kt and reuse existing form; corresponding JVM/native tests and localization only via established generators if missing.

**Interfaces:** Pane consumes owner/repository and callbacks `(walletId:String)->Unit` for statement/edit, `()->Unit` add. Route consumes owner/nullablewalletID/repository/deviceID/enabled currencies and dismiss. Existing saveCreditCard remains only mutation authority.

- [x] Add meaningful missing UI/route/load/error/privacy/owner/targetdisappearance/largeLong/font1.3 tests before product code. Expected actual assertionsRED. Extend first regression rather than substituting a synthetic-only account view.
- [x] Implement focused pane/projection load state and Swift one-column brand card/empty/add state with exact localized wallet units; statement nested button separate from edit. Implement owner-scoped editor controller using existing sheet, history currency lock, live choices and cancellation before/after deviceID. Expected focusedJVM/nativeGREEN; inspect saved light/dark/font1.3 screenshot images.
- [x] Run old Planning budget/savings/bill/installment and Management card/editor native regressions plus full affected JVM. Expected no changed money/outbox on read and existing form behavior preserved.

### Task 3: Actual navigation and complete slice acceptance

**Files:** MainActivity.kt and new app PlanningCreditCardDestinations.kt, app Android NavHost integration tests;169 evidence/progress/handoff and mainversion166.

**Interfaces:** Shared app graph destinations render existing statements/new scoped editor. Planning callbacks invoke same graph; Management statement entry preserved.

- [x] Write actual NavHost+Room tests for statement→back, nested statement does not edit, edit→save actualprofile without duplicatewallet, add→save card, invalid/rotated owner target; Expected runtimeRED before wiring. Implement minimal graph and callbacks; ExpectedGREEN.
- [x] Full testDebugUnitTest/Roomcompile/lint/main+affectedtestAPKs, contracts/bothl10n/Swift/universal iOScompile and affected complete native scopes with exact source/build/installed fences; inspect new UI screenshots. Expected0failures and all11flagsfalse. Backend inherited only if final tracked source exactly unchanged168 and immutable619/23/3 proofs verified.
- [ ] Direct Swift full diff review plus one fresh whole-slice reviewer; one material TDD fix pass/full affected suites, ledger all rulings/minors. Expected no unresolved material findings. Archive main166/test/evidence/sourcepatch, update docs, immediate separate169 commit and actualcommit/tree binding. Continue full APK1–4/RC scope.
