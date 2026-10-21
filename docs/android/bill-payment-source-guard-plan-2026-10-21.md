# Bill Payment Source Guard Implementation Plan

> **For agentic workers:** use superpowers:executing-plans inline and runtime TDD; fresh whole-branch review remains at completion of the full APK1–4 goal.

**Goal:** A changed recurring bill cannot be paid with a stale visible/confirmed source amount.
**Spec:** `docs/android/bill-payment-source-guard-design-2026-10-21.md` and binding original TXT/same-currency decisions.
**Architecture:** typed source consent in the existing local request, shared semantic comparison, repository source guard plus current atomic CAS, and a guarded native frozen confirmation. No new dependency/schema/wire entity/network/currency policy.

## Constraints

Keep all10flagsfalse, Room6/SwiftDataV11/iOS751, current branch and authorized local per-slice commits. No production write/deploy/migration. Retain explicit variable amount overrides, exact Long/minor parsing, same-currency eligibility, source owner/cycle guards, auto-pay's fresh source/no override rules, and installment expected-source semantics. Metadata ACK alone must not invalidate consent; createdAt normalization preserves exact instant/calendar meaning. Other source fields conservatively define source consent. No redundant design/execution/worktree permission handoff; genuine product choices still require the user. Do not infer the pending credit-card currency answer.

### Task 1: Carry and validate recurring manual source consent

Files: core/model BillPayments.kt; database BillPaymentRepository.kt and ScheduledExpenseSource.kt; existing BillPaymentRepositoryTest.kt and BillPaymentRoomTest.kt as needed; new database androidTest BillPaymentSourceRoomTest.kt. All packages retain vn/com/quyln/mistia/core/{model,database}.

Interfaces: append `expectedBill:RecurringBillPlanRecord?=null` and `expectedDueAmountMinor:Long?=expectedBill?.amountMinor` to BillPaymentRequest; recurring manual pays require it, auto/Installment adapter preserve their separate proof rules. Core `RecurringBillPlanRecord.matchesBillPaymentSource(expected):Boolean` compares owner/id/all source fields after canonicalizing exact createdAt and stripping only updatedAt/syncVersion/device metadata; malformed required time is false. Core `BillPaymentRequest.matchesBillPaymentConsent(other:BillPaymentRequest?):Boolean` compares nonbaseline request fields and the semantic baseline; null/nonnull cannot match. Repository validates expected source against its fresh owned raw source before any money/outbox work, retaining existing final CAS.

- Add request field without enforcing it solely to compile actual runtime baseline tests. Write real repository/Room literal tests before guards: visible5000→stored6000 at same syncVersion0 must reject SOURCE_CHANGED/no writes; controls same source/metadata ACK/intentional variable override/autopay. Missing expected manual source also must not write. Initial behavior should pay the stale amount and fail the assertion; compile errors are not RED.
- Read actual baseline logs. Implement shared comparison/mandatory manual guard. Update legitimate existing manual test constructors to supply their visible bill; preserve original failure reasons and money assertions. Inventory all runtime constructors; only the actual BillPaymentState producer is changed in Task2, auto/Installment paths stay semantically unchanged.
- Focused core source-consent/repository and actual Room GREEN. Task1+Task2 one coherent123 slice; no partial completion/commit before full vertical verification.

### Task 2: Guard the actual frozen confirmation and current source producer

Files: planning BillPaymentState.kt/BillPaymentSheet.kt and their unit/native tests; app version123; evidence/progress docs. No static copy outside shared catalog.

- Before UI fix add native tests opening5000 confirmation then changing same-id source to6000/currency/schedule while open; old5000 cannot invoke callback, cancel/reconfirm current6000 can. Metadata-only ACK keeps same intent valid. A delayed actual repository invocation proves backend source proof covers a source change before its read even when visible flow is withheld.
- Add pay/undo noncancellable late-result native regressions before fixing UI delivery after a cancelled sheet; reuse coroutine activity guard before callbacks, like installments. Make BillPaymentState emit current expectedBill; confirm button and execute both use shared current consent check; use current callbacks, preserve drafts/busy/cancellation/undo behavior. No speculative financial policy or blanket error swallowing. Add the effective due amount baseline to detect pending-occurrence snapshot changes independently of bill defaults; BillPaymentState supplies row.amountMinor, preserving intentional variable null. The existing SOURCE_CHANGED error map/copy suffices unless actual UX evidence requires a catalog change.
- Run focused unit/native GREEN and direct Swift DuePaymentSheet/current immutable diff review. Important findings require their own runtime RED→GREEN before fixes.
- Run full testDebugUnitTest/Room+required feature AndroidTest compile/package/lint/main, complete relevant Planning native suite, scoped Overview regressions only if a changed path requires them, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/diff whitespace. Inspect actual terminal0/JUnit footers and actual130% UI where changed.
- Archive final executed main/test123 packages; manifest/DEX/version/min/target/install-r/cold/installed hashes; evidence/progress/independent123commit/task-done. Then continue actual upcoming bill/installment Overview section/shared payment route and remaining APK1–4/RC; no full domain/gate completion claim.
