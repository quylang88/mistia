# Slice140 — recurring-bill investment payment and undo

Baseline dfdc8cc2. Implementation, scoped review corrections and scoped acceptance complete. Full Planning package has intermittent legacy UI-test failures described below; no whole-package green claim. Separate141 installment integration is designed, with no141product changes yet. APK1–4/RC remains incomplete.

## Delivered behavior

Actual Planning, Overview/Upcoming and notification bill-payment entry points now supply the current accounting currency and stable repository scope. A wallet with100cash/60reserved pays30 directly;70 needs explicit30fund consent. Cancel writes nothing. Pay/Undo/repaid cycles use frozen operation identity/time, full source/receipt consent, exact current affordability and whole-timeline derived effects. Undo can restore downstream allocations beyond the selected expense. Repayment reuses original expense/cycle identities, preserves raw extension/creator/LongACK fields and requires a new intent after a distinct Undo. Complete known results are no-write retries; partial financial results hold instead of being repaired silently.

The dedicated Room writer independently reconstructs the complete plan inside one transaction over15entity tables plus receipt identities. Primary expense, all matching cycle markers, canonical investment postings/adjustments and queues commit together. Source/receipt CAS, orphan generated queues, current owner and captured caller fences prevent stale/partial/cancelled commits. Generic bill mutation whitelist is unchanged. Existing manual investment rows, settlement/receipt links and paid-card locks remain protected. Source envelope/body deletion metadata must agree.

Automatic bill payment now allows ordinary cash even when investment postings exist. Fund-requiring automatic payment holds before success presentation/notification or financial writes. Successful automatic presentation and local notification are validated and written atomically. Manual callers cannot inject automatic notification/presentation.

The shared actual fund dialog moved into coredesignsystem; the transaction wrapper preserves its tags/behavior. Actual BillPaymentSheet has scoped saveable identity/time, no saved fund consent, typed Pay/Undo review, explicit retry, busy and source guards, owner privacy, and cancellation checks before old callbacks update replacement UI. Accounting-currency mismatch uses localized policy copy. Approved same-currency bill wallet selection remains enforced. Installment reserved funds keep their existing hold until141.

## Direct Swift comparison and review

Read PlanningSupport.swift230–285 (wallet/currency/current balance and exact confirmed preview),330–373 (expense/occurrence/fund usage),492–575 (compound undo), MistiaRecurringBillMaintenance.swift80–145 (ordinary automatic success/fund pause), and InvestmentPersistence.swift2437 onward (accounting-currency rule). Android deliberately retains stronger atomic whole-timeline undo recomputation to avoid stale downstream money.

One final fresh scoped read-only review found an Important initial-Undo/completed-result mismatch for distinct compound marker amounts, a linked expense deleted before this intent and a live pending duplicate. Three actual focused model regressions failed (/tmp/mistia140-review-red.log,30tests3fail). The correction binds the visible amount/link to its original marker, independently validates each other marker against its own expense, preserves prior tombstones at/before intent, rejects future tombstones and rejects mixed live pending cycles before first write. Complete canonical derived proof and tampered-marker/partial-result negative controls remain. Review's other concrete concerns were declined; no repeated review loop. Whole-branch final review remains future scope.

## Observed TDD and automated checks

| Boundary | Observed RED | Recheck evidence |
| --- | --- | --- |
| Actual real Room/repository/form70-use30 | Existing INVESTMENT_USAGE_UNAVAILABLE, native1failure2.891s | First actual flow1GREEN3.823s; expanded UI11GREEN50.176s |
| Pure full operation |6unsupported runtime failures; later status/bootstrap/foreignfund/raw tombstone/source/currentcanonical/ACK/Undo regressions | Final30bill model tests within full2046JVM/196suites, zero failures/errors/skips |
| Room transaction |6run5unsupported failures; repository unsupported fallback; manual automatic-notification injection | New12GREEN0.640s; final full Room282GREEN6.543s |
| Owner privacy | Expanded8UIrun2fail: old title after owner replacement; other owner's wallet name in review | Both corrected; native combined19GREEN53.725s |
| Ordinary automatic payment | Ordinary wallet with reserved postings incorrectly held; automatic title/manual presentation regressions | Actual Room12GREEN; provider invoked only after ordinary/fund preflight |
| Legacy completed Undo |30run3fail for compound amount/prior deletion/pending duplicate | Full2046JVM zero after correction |

Final post-correction host command ran testDebugUnitTest, database androidTest Kotlin compile, database/planning/transactions native package assemblies, app lint and main assembly. BUILD SUCCESSFUL58s in /tmp/mistia140-review-full-green.log. All196JUnit XML suites counted2046tests, zero failed/error/skipped. Full Swift627tests zero in /tmp/mistia140-swift.log, with explicit Xcode DEVELOPER_DIR; no Swift business logic changed in140, only generated localization.

Contracts15, both strict localization checks, outbox/notification/installment store guards7/3/11, Room test assets6schemas+catalog, Node icon tests9, art registry196tokens/111originals, unit-fold tests4/1553mappingcheck and whitespace checks pass. Relevant logs: /tmp/mistia140-{contracts,android-l10n-check,swift-l10n-check,outbox-check,notification-check,installment-check,room-assets-check,icons-tests,icons-check,fold-tests,fold-check}.log.

First full Planning147run had2failures: BillPaymentSheetTest.nilAmountCannotSubmitUntilPositiveAndPickerOmitsDifferentCurrency (picker node absent) and BudgetWorkflowTest.billFormPersistsExactAmountWithNativeControls (save observation timeout), /tmp/mistia140-planning-all-native.log691.045s. Without any product/test change, both focused tests passed8.796s and the full preceding newBillUI+BillPaymentSheet+BudgetWorkflow sequence29passed112.907s. Root cause is not proven; no product fix is claimed. The second full147run755.666s runner/757.09s driver passed both earlier failures and every new bill flow but failed one unrelated existing InstallmentEditorWorkflowTest.deleteConfirmationUsesOriginalBaselineAndDoesNotSaveUnsavedChanges (confirmDelete absent). That test passed focused1/1 in4.517s without product/test changes. No simultaneous full Planning green or resolved root-cause claim. Logs: /tmp/mistia140-planning-final-all-native.log, /tmp/mistia140-native-failures-focused.log, /tmp/mistia140-native-sequence-diagnostic.log and /tmp/mistia140-installment-delete-diagnostic.log. Carry the existing installment form touch/IME/window-timing investigation into141. Final full Transactions97/97GREEN406.048s (not the previously estimated96) in /tmp/mistia140-transactions-final-all-native.log, covering shared dialog and real receipt/lifecycle regressions.

## Native visual evidence

Eighteen actual BillPaymentSheet confirmation/use/restore views cover EN/VI/JA light/dark at system font1.3 and320dp width on API36ARM64. The real Room/repository test includes fullLongMAXmoney, complete TextLayoutResult ends/no ellipsis, glyph presence, separated>=48dp actions and no-write observation/Cancel checks. All18originals are hashed in [the manifest](images/2026-10-23-bill-investment-payment/manifest.json); all3six-image contacts inspected. Initial UI11/11GREEN50.176s is /tmp/mistia140-qa-native.log. Full UI regression repeats these cases. System font/width restore is verified at1.0/1080x2340 after the run.

These views accept the new dialogs only. Pre-existing underlying bottomsheet global dark-body/content palette and TestActivity system-bar contrast remain whole-app follow-up; no whole-app accessibility/insets/palette or physical-device completion claim.

## Artifacts and execution boundary

VersionCode139 main archived at android/build/outputs/apk2/2026-10-23/mistia-0.2.0-apk2-bill-investment-payment-v139.apk:20DEX,36550829bytes, SHA256 e116776e9f82ca28432cf95cd529bf1f3b0c68d42fc89c9cedc61b9a59a80d78. Main/Room/Planning/Transactions installed with install-r, all four archive/installed hashes matched; slice140-artifacts.json records each. Cold launch Statusok/COLD1184ms is a single observation, not performance acceptance. Install/hash/cold log /tmp/mistia140-final-artifacts.log.

Source patch26files/156760bytes SHA25675454a4296b00a239c053b2347fcf5964d6de5ff5194a9c649faa6d6458505ad, archived as slice140-source.patch/json against dfdc8cc2. Docs/images are outside this source patch.

Only API36ARM64 emulator transport16 is connected. No Samsung verification, live Supabase, production write, deploy, migration or push. All11cloud gatesfalse, Room6 and SwiftDataV11 unchanged. Existing Google/email auth authorization and all five approved currency decisions persist. Do not repeat OAuth/account-switch setup. Complete140 local commit is authorized by TXT; immediately continue141 and the full remaining APK1–4/RC scope.
