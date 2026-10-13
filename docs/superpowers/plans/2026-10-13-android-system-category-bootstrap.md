# Android default system category bootstrap parity follow-up

## Verified gap
Swift MistiaApp.runDeferredStartupWork invokes seedDefaultCategoriesForLaunchIfNeeded.
MistiaBootstrap ensures active parents/children from the shared JSON. Android has
catalog assets/rendering and custom category management, but no default-category
startup seed path (searched core/database, model, sync and MainActivity). Swift
bill picker uses recurringBillQuickPickDefaults keyed by system categories, so
native bill creation would be empty for a fresh/offline Android account without
this dependency. Close it before implementing the bill picker; do not replace
Swift picker behavior just to bypass missing defaults.

## Sources already inspected
- Mistia/Shared/CoreLogic/MistiaSystemCategories.json
- Mistia/Shared/CoreLogic/MistiaSystemCategoryIdentity.swift
- Mistia/Shared/Persistence/MistiaBootstrap.swift ensureDefaultParentCategories,
  ensureDefaultLeafCategories and normalizeParentCategory/normalizeLeafCategory.
- Mistia/Shared/Sync/MistiaSystemCategorySyncSupport.swift cloudScopedID/dedupe.
- Mistia/Core/UI/MistiaCategoryPicker.swift billQuickPickCategories.
- FinanceEnums.swift recurringBillQuickPickDefaults (26 keys, in defined order).

## Bounded slices
1. Pure catalog/identity contract, TDD with real shared JSON as test resource.
   Match active registry hierarchy/vi/en/ja/icons/colors/per-parent ordering;
   SHA1 stable UUID (version5/variant bits) namespace canonicalID and owner-scoped
   cloudScopedID. Golden vectors against Swift, same-owner determinism and
   different-owner isolation. Do not create new independent category assets.
2. Atomic local bootstrap and reconciliation, TDD/Room tests. Preserve existing
   IDs, custom names, versions, favorites, archive state and linked references;
   create missing defaults using owner-scoped cloud identity to avoid global PK
   collision. Respect known tombstones/user state; compare direct Swift behavior
   before choosing normalization rules. Detect/record duplicate/legacy repairs
   separately; no broad destructive rewrite or production migration.
3. Startup wiring and sync protection, before exposing automatic seed behavior.
   Pull first when available. Offline bootstrap must remain usable, but an
   untouched local seed must not overwrite a pre-existing cloud customization
   on later sync. Add a verified unmodified-seed predicate (owner-scoped ID,
   version0, created==updated, exact catalog payload) and conditional remote-winner
   handling; explicit user edits must keep normal winner semantics. Tests must
   cover race, tombstone, changed name/favorite, owner isolation and stale ACK.
   Avoid unsafe heuristic that classifies all system rows as untouched defaults.
   No new Room metadata migration unless evidence shows it necessary.

After each completed slice: full relevant Android/Swift/contract/localization
checks, evidence/progress, ADB status and independent commit. All eight write
gates remain false; no production requests/writes/deployment. Then return to
native bill form/lifecycle/payment and due maintenance.

## Native UI findings to retain
PlanningMode order is budget/due/goals. Due submodes bills/creditCards/installments.
Current Android provisional four-tab order is different and must be corrected
with owner-scoped saveable navigation, safe restoration of older Int tab state,
and updated Compose tests (savings moves from tab1 to tab2).
Bill quick-picker includes selected original category if absent from defaults.
Do not drop custom original category identity or archived preferred wallet.
