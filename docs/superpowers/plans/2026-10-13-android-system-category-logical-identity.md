# System category logical identity and cross-platform budget parity

## Source evidence
Swift MistiaSyncLocalStore.scopedCategoryIDMap maps own isSystem rows to canonical
local IDs by systemKey; remoteCategoryIDMap maps cloud owner IDs back to local.
BudgetPlan.planningSnapshot prefers categoryIDSnapshot/parentIDSnapshot frozen
canonical IDs. Android stores category wire IDs, and current budget comparisons
use raw UUIDs. Thus iOS frozen canonical IDs can differ from Android live cloud
IDs for the same owned logical system category. Verify with runtime RED before
changing code; do not rely on translated name fallback to hide the mismatch.

## Next bounded slice: canonical comparisons, unchanged wire references
- [x] RED pure projection tests using actual factory system records: frozen
  canonical ID versus live cloud ID, renamed live category (so name fallback
  cannot mask failure), active continuity/carry-forward and parent totals.
- [x] RED repository tests: imported canonical parent/child snapshots enforce
  the approved single-currency branch rule and parent cap; final current-budget
  deletion disables the actual wire parent family flag. Metadata for tombstoned
  system categories and foreign-owner isolation must be covered.
- [x] Add owner-scoped logical identity index from typed system category metadata
  (canonical, owner cloud and actual legacy IDs). Custom IDs remain unchanged.
  Normalize comparison/grouping only; preserve live FK/wire IDs and frozen names,
  colors, amounts, versions. New system budget snapshot identity should match
  Swift canonical local identity. Check all allocation/currency/auto-parent/
  family propagation/delete call sites and editor branch currency inheritance.
- [x] Obtain complete category metadata including tombstones for projection and
  repository checks, while native pickers continue to exclude deleted records.
  Preserve existing observeBudgetCategories UI contract or add separate metadata
  API. Source user_id owner filtering remains strict despite viewer envelopes.
- [x] Review direct Swift budgetBranchRows/reportedExpense/category mapping for
  frozen hierarchy and any name fallback before claiming parity. Cover no double
  counting and immutable snapshots with regression tests.
- [x] Full Android/Swift/contract/localization/Room/lint/build checks, evidence,
  progress and commit. All eight write gates false, no production writes.

## After comparisons: legacy identity reconciliation before startup
A remote system row may exist under another ID for the same owner/system key.
Fetch-by-current-ID plus create can collide with system-key uniqueness. Do not
ACK a different ID through the ordinary same-ID ACK path or drop referenced
local category IDs. Compare Swift deduplication/reassignment directly, then add
atomic owner-scoped identity/reference reconciliation for categories, ledger
transactions, budgets and recurring bills, preserving user edits/outbox versions
and frozen display metadata. Test stale responses, create race, foreign viewer
rows, tombstones and referenced offline user records. Only after these paths are
verified should MainActivity startup pull/bootstrap be wired. Then return to
native bill form/lifecycle/payment and due maintenance; full APK1–4 goal remains.


## Owner-key lookup prerequisite completed
- [x] Typed owner/system-key page lookup includes legacy IDs/tombstones and exact
  range continuation; invalid/foreign/malformed pages fail closed.
- [x] Runtime RED4/GREEN10 HTTPS tests, 560 JVM/21 Swift, lint/build/Room/UI
  compilation and contract/l10n checks; committed as a separate read-only slice.

## Next atomic reconciliation acceptance
- [ ] Test an untouched queued owner-cloud seed against a different-ID owned
  remote row of the same system key. A normal same-ID ACK is prohibited.
- [ ] Decide canonical winner from complete pages using direct Swift priority
  review; preserve active versus tombstone semantics. Do not synthesize an
  unpersisted remote wire ID or silently discard duplicate remote candidates.
- [ ] Within one Room transaction, compare exact queued seed and current record
  before replacing it. Reject stale response or occupied target with newer local
  edits; preserve every newer mutation. Retry from fresh metadata instead.
- [ ] Repoint owned category parent_category_id and ledger/budget/bill category_id
  from old wire ID to selected actual remote ID. Preserve frozen budget display
  fields/identity and unknown payload fields, amounts, currency and versions.
  Preserve current dependent edits/base versions and tombstone mutation kinds;
  ensure every required dependent change has an atomic matching outbox mutation.
- [ ] Source user_id filtering must precede any payload rewrite despite viewer
  envelopes. Handle references in archived/deleted records and any foreign
  reference/occupied identity without destructive cross-owner writes.
- [ ] Audit pending category translation tasks and stale in-flight translations:
  reference/timestamp changes must not drop untranslated user edits or allow old
  responses to overwrite a replacement. Owner scope and retry remain intact.
- [ ] Tests for record/outbox rollback, reopen, stale queued seed, stale dependent
  edit, deleted remote, changed target, same-key duplicate, child parent rewrite,
  archived/deleted references, foreign viewer scope and exact monetary payloads.
- [ ] Integrate owner-key lookup/reconciliation before category create and again
  after create409; account cancellation and gate-off must produce zero requests.
  Explicitly edited offline seeds need preservation/reconciliation coverage too.
- [ ] Only enable startup pull/bootstrap once these paths are proven. Then resume
  native bill UI/payment/maintenance and remaining APK2–4 without waiting for ADB.

## 2026-10-14 implementation sequence

1. Pure remote selection and lossless reference rewrite. Compare Swift
   deduplicatingRemoteSystemCategories remote priority exactly: active value
   candidates first, timestamp seconds plus1000 for actual owner-cloud identity.
   Use an existing owner-cloud row as identity when present, otherwise the actual
   value winner ID; never fabricate an absent remote wire row. Keep identity and
   values separate, retain all duplicate candidates for atomic reconciliation.
   Rewrite only owned category parent /ledger-budget-bill category FK fields,
   preserve frozen display/identity snapshots, explicit nulls/unknown fields and
   Long versions. Preserve pending DELETE/base versions; reject stale inputs.
2. Atomic Room identity/reference/outbox/translation migration, with exact source
   queued-seed/target/dependent/task snapshots. Preserve edited seeds with an
   explicit merge, never ACK a different ID through same-ID ACK.
3. Integrate before category create and after409, including complete owner-key
   paging, cancellation/gate-off/retry and duplicate candidates. Then startup
   pull/bootstrap and remaining APK1–4. Each component gets RED/GREEN, full
   appropriate checks, review, evidence and independent commit; components alone
   do not establish full cloud reconciliation or startup readiness.
