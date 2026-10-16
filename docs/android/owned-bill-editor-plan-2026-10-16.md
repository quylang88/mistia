# Owned bill editor and current primary implementation plan — slice98

Implement directly in the current authorized session; user TXT authorizes local commits after each verified slice.

Goal: new bills use current primary; foreign/restored/stale editor state never crosses owner/record/currency scope. Swift PlanningEditors.swift1080–1118 filters payment wallets by active currency and selects stored plan/due-item currency before AppStorage primary.

Files: RecurringBillEditorSheet.kt, RecurringBillEditorState.kt, PlanningScreen.kt; new OwnedBillEditorStateTest.kt and OwnedBillEditorTest.kt. App98, dedicated evidence/PNGs and progress entry.

- [x] Runtime native REDs: real PlanningScreen VND new bill with actual owned system-key rent category and same-currency wallet persists exact9007199254740993 and outbox; existingJPY/USD underVND primary retains exact minor meaning; foreign supplied bill hidden; switchingrecord closes picker/action; primarychange resets create draft/calculator/wallet; late NonCancellable save/pause cannot dismiss nextowner's editor. Release callbacks in finally. Do not weaken same-currency wallet filtering or existing physical assertions.
- [x] Runtime JVM REDs: scoped saver rejects outer owner/ID/currency mismatch, inner identity/code mismatch, malformed envelope/date/schedule, preserves exact money and legitimate legacyfrequency24. Preserve existing raw18slot saver API.
- [x] Minimal fix: optional primaryJPY argument passed from PlanningScreen; existingrecordcurrency precedence, supportednewcode normalized. Reject foreignrecord and key owned subtree by owner/record/currency. Scoped envelope wraps raw saver and validates target dates/day ranges; existing legacyfrequency>=1 preserved. Active-job checks before/after save and shared pause/resume/archive callback. Already-correct sheet-local focus96 retained.
- [ ] Focused native/model green; direct Swift audit and independent review; full Gradle/unit/lint/build, Swift610/contracts/localization/SQLite/schema checks. Full native planning suite on final APK with settled screenshots, light/dark130% inspection and install-r/coldlaunch smoke.
- [x] Record exact executed APK checksum/evidence/progress; independent commit98 then immediately continue installment/budget primary consumers and remaining APK1–4/RC.

All10 flagsfalse, no production writes/deploy/migration; Room6/SwiftDataV11/iOS751. This slice protects UI draft/completion; repository editor-opening baselines and atomic read-set guards remain required separate work. Pending card-payment product decision does not block independent bill work.
