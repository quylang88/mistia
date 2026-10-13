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
