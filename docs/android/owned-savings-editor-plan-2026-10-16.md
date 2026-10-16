# Owned savings editor and primary defaults implementation plan — slice97

> Implement directly in this session, task-by-task, with independent review before the slice commit; user TXT already authorizes execution and local commits.

**Goal:** New savings goals use the current primary currency; restored drafts and asynchronous completions stay within their owner/record/currency scope.

**Architecture:** PlanningScreen passes normalized primary. Public SavingsGoalEditorSheet rejects foreign records and keys an owned subtree by owner, record ID and bound currency (existing record currency takes precedence). A scoped saver wraps the existing raw saver and validates the restored ID/currency. Post-callback cancellation checks prevent stale save/delete responses from dismissing the replacement editor.

**Tech:** Kotlin, Compose saveable state/coroutines, in-memory Room native tests.

**Spec:** user TXT and Swift PlanningEditors.swift772/825–826/920–948. Existing goals retain their stored currency; new goals use AppStorage primary. Exact Long money remains unchanged; a linked wallet is metadata, so do not apply the bill/installment payment currency restriction to goal linkage.

## Constraints and review focus

Keep all10 cloud gatesfalse, Room6/SwiftDataV11/iOS751; no production writes/deploy/migration. Preserve the old raw saver API for existing callers/tests. Reject malformed restored envelopes without crashing. Foreign supplied goal must not expose/edit its values. Live primary change while creating resets the scoped draft/calculator rather than relabeling money. Existing imported decimal currency edits preserve original minor-unit meaning. Cancellation guards UI completion only; repository opening-version/read-set guards remain separate work.

## Task1: owned draft and current primary

Files: SavingsGoalEditorState.kt/Sheet.kt, PlanningScreen.kt, SavingsGoalEditorStateTest.kt; new OwnedSavingsGoalEditorTest.kt. App version97; evidence/progress at completion.

- [x] Add focused native tests against current behavior: actual PlanningScreen VND new goal exact9007199254740993 target/signed current and exact outbox; existingJPY edit underVND primary retainsJPY; foreign record hidden; switching record resets calculator/picker; live creation primary changes reset draft/expression; late NonCancellable save/delete cannot dismiss the next owner's editor.
- [x] Build then run native tests; record intended runtime REDs separately from compilation/selector diagnostics.
- [x] Add scopedSaver(owner:String, recordId:String?, currency:String) with owner/ID/currency envelope and restored payload identity validation; JVM tests pin matching restore, wrongowner/record/currency and malformed/corrupt payload rejection. Verify actual runtime RED before guard implementation.
- [x] Add primaryCurrencyCode optionalJPY parameter; existing currency wins; normalized supported new currency defaultsJPY. Key owned subtree; initialize fresh using bound currency and scoped saver. Read focus manager inside ModalBottomSheet; clear before calculator/pickers. Check active coroutine before/after callbacks.
- [x] Run focused then full native planning and appropriate full Gradle/Swift/contracts/localization/SQLite/schema checks. Direct Swift comparison and independent read-only review; fix findings and rerun affected checks.
- [x] Inspect light/dark130% actual images; archive exact executed APKs/checksums; install-r/cold launch emulator; update evidence/progress and commit97 independently. Continue remaining primary planning consumers/APK1–4 immediately.
