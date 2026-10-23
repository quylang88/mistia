# Installment investment payment implementation plan

> For agentic workers: use superpowers:executing-plans inline. User TXT overrides per-task commits/design confirmation pauses: commit once this functional slice is complete and then continue the full goal.

**Goal:** actual installment Pay/Undo with explicit fund consent, exact atomic derived cash effects and complete retry proof.

**Architecture:** typed installment public operations share the140 scheduled-expense planner and dedicated recomputed Room transaction. Real installment schedules/records/category remain explicit; no synthetic recurring bill or arbitrary derived-write admission.

**Stack:** Kotlin/JVM, Room, coroutines, Compose, existing exact-money investment model.

**Spec:** installment-investment-payment-design-2026-10-23.md.

**Constraints:** existing dedicated branch; same-currency installment wallet; fund accounting-currency restriction; all11cloud gatesfalse; Room6/SwiftDataV11; no remote write/deploy/migration/push. Inline TDD, one final scoped fresh review, local complete-slice commit only. Preserve140bill public/API/native behavior.

**Review focus:** initial/known-result admission must agree; sourcekind/real installment scheduling must survive engine sharing; no callback from a replaced repository/currency/owner; orphan canonical IDs and partial derived results must hold; newly edited exact amount/source must invalidate old visible consent. Tests below exercise each.

### Task 1: Pure typed installment preparation

Files: new core/model InstallmentInvestmentMoneyPlan.kt and tests; InstallmentPayments.kt; existing BillInvestmentPlanner.kt with a focused scheduled source adapter as needed.

Interfaces: append optional investment context to InstallmentPaymentRequest; add InstallmentInvestmentUndoRequest(expected plan,month,visible amount,visible link,context), sealed Pay/Undo, planInstallmentInvestmentMoney(snapshot,operation,catalog,deviceId,now,zone) returning typed payment+mutations. Keep bill APIs unchanged.

- [x] Add actual native regression first (task3 fixture below) and observe current INVESTMENT_USAGE_UNAVAILABLE instead of30 review. Add minimal unsupported model entry point and tests; observe runtime RED.
- [x] Implement real source-kind adapter: installmentDueRows, fixedloan_repayment, no card/investment wallet, exact samecurrency, typed source consent. Validate complete base via existing source contract, derive fund effects and explicit full-source proposal consent using140 engine. Never infer public consent from read-only proof.
- [x] Verify70-use30,30ordinary, foreignordinary/foreignreserve, Longexact, skipped/unknown/totalcycles/notdue, currentcanonicaldrift, fullknown Pay/Undo, partialholds, compoundundo/retry, ACK/raw/repay identity. Run focused RED→GREEN and full model suite.

### Task 2: Recomputed Room and repository boundary

Files: Contracts.kt, MistiaDatabase.kt, InstallmentPaymentRepository.kt, Repositories.kt, new database/androidTest InstallmentInvestmentMoneyRoomTest.kt.

Interfaces: consistent installment full snapshot and dedicated commit accepting typed operation/catalog/device/clock/zone; typed fund-aware Undo method on InstallmentPaymentRepository; normal repository investment request routes exclusively to this boundary.

- [x] Write actual Room tests and observe runtime unsupported RED: last-derived/outbox trigger rollback; currentowner/capturedcaller final fence rollback; fullsource+receipt CAS/orphan guard; no half-state observer; Pay/Undo/known completion/queues; repository no genericfallback.
- [x] Reuse the140 transaction shape with actual INSTALLMENT source selection and typed planner recomputation. Keep notifications domain-specific and no invented installment automatic success. Pass only validated base writes to InstallmentMoneyContract before derived effects.
- [x] Focused Room GREEN, full database JVM and current native Room suite; preserve140bill behavior.

### Task 3: Actual form and routes

Files: InstallmentPaymentSheet.kt, InstallmentPaymentState.kt if semantic consent helper needed, InstallmentDuePane.kt, UpcomingRecurringPaymentSheet.kt; new planning/androidTest InstallmentInvestmentPaymentScreenTest.kt.

- [x] Seed real Room100opening60reserved70installment; current form must show30review. Cancel must preserve all rows/outbox. Observe runtime RED before product changes.
- [x] Add public owner guard and scoped key(owner,source,month,mode,repository,currency); scoped saveable identity/time, no saved consent; typed fundreview/cancel/confirm and Undo. Compare visible payment source/amount independently of investment context, while pure planner checks full consent.
- [x] Wire actual DuePane and Upcoming to current currency/repository/typedUndo. Keep loading/targetCurrent/retry; active coroutine check before changing replacement UI; busy prevents duplicate/exits.
- [x] Test real Pay70/consumption30, typedUndo/restore, committed lostresponse no secondrows/queue rewrite, new hiddenbalance101→review29, visible source change, owner/DI/currency replacement, state restoration sameintent/no automatic consent/replay. Observe relevant RED→GREEN.
- [x] Add actual EN/VI/JA light/dark font130/320dp QA with LongMAX, full text/glyph/control bounds; capture/hash/inspect originals. Run old installment/bill/Overview and sharedfund transaction regressions.

### Task 4: Acceptance and complete slice commit

- [x] Compare final diff directly with cited Swift. One final scoped fresh review required by executing-plans; fix Important/Critical with observed regressions and rechecks. No repeated review loop.
- [x] Run testDebugUnitTest, database androidTest compile, app lint/assemble, native packages, relevant Swift tests, contracts, both strict localization checks, guards/schema/assets/icons/fold and git diff --check. Claim only actual outcomes; investigate failures.
- [x] Version140 main/test APK archives, contents/hash/install-r/installed hashes/cold start, adb devices and accurate emulator/Samsung/cloud boundaries. Update evidence/progress/handoff, complete plan, commit141 separately; immediately continue remaining full goal.
\nCompletion boundary: full2062JVM/lint/build/627Swift/required contracts+l10n+guards/assets and final scopedPlanning55/Transactions12 pass. Financial Room tests pass; wholeRoom291 has one unchanged notification preference publication failure, preserved in evidence and assigned immediate separate142fix. No wholeRoom/full158Planning/fullgoalGREEN claim. Both Important reviewer issues and changed-visible-wallet retry regression were observed RED then corrected. No repeated review; local functional141commit authorized, then continue142.\n