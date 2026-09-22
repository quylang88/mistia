# APK 1 offline category hierarchy evidence — 2026-09-23

Starting point for the ongoing APK 1 work was `afce6aa`; this slice follows
the separately committed wallet and wallet-push slices. It completes offline
category hierarchy management only and does not claim APK 1 completion.

## Implemented behavior

- Typed every `transaction_categories` field used by the shared contract:
  localized names, kind, icon/color, favorite and family flags, parent/role,
  system metadata, sort/archive timestamps, deletion, sync version and device.
  Optional fields remain explicit JSON nulls and unknown wire values survive
  storage without being silently converted.
- Added account-scoped create/edit/favorite/archive. Each successful operation
  writes the category record and coalesced outbox row through the existing
  atomic Room transaction. Pulled `sync_version` remains the mutation base.
- Matched iOS validation: normalized duplicate names in the current app
  language, active same-kind root parent requirement, child-only favorite,
  immutable role after creation, and next sort order after moving kind/parent.
- Matched the current-month budget branch guard for name/kind/parent changes;
  icon and favorite-only edits remain available, matching the Swift editor.
- Matched iOS archive blockers for active children and direct non-deleted
  references from transactions, budgets and recurring bills. Archive remains
  an `is_archived=true` upsert.
- Replaced the category count placeholder with expense/income filters,
  expandable parent cards, sorted children, child favorite controls and
  parent/child add/edit paths. The editor provides name, kind, hierarchy,
  parent, favorite, icon/color, error states and archive confirmation.
- The Android build packages the shared iOS
  `MistiaSystemCategories.json` catalog. The editor exposes all 147 active
  parent/child canonical `mistia.category.*` tokens; inactive entries are
  excluded and Material icons remain only a deterministic rendering adapter.
  This prevents Android-created categories from becoming unknown icons on iOS
  after cloud push is enabled.
- Internal balance-adjustment children are excluded from management, and an
  uncategorized root is hidden while empty, matching the iOS hierarchy.

## Parity review and corrections

Review used `ManagementView.categoriesSection`,
`ManagementCategoryEditorSheet`, `CategoryDraft`,
`CategoryHierarchySupport`, `MistiaFinanceIconRegistry`,
`CategoryNameTranslationService` and the category sync model.

The review found and corrected six material mismatches before commit:

1. Editing a category into a different kind/parent initially retained its old
   sort order; it now receives the next order in the destination branch.
2. Duplicate checking initially compared all translation columns; it now
   compares the localized display name for the active editing language, as iOS
   does.
3. Favorite update failures were initially silent; the hierarchy now exposes
   the localized interaction error.
4. The first icon picker draft stored Android Material names. It now stores
   only the shared canonical Mistia tokens and maps them locally for display.
5. Internal balance-adjustment categories were initially visible. They now use
   the same stable system keys/derived UUID identities as iOS and stay hidden;
   empty uncategorized roots also collapse out of the hierarchy.
6. The first canonical picker exposed only a hand-written subset. Gradle now
   copies the shared iOS catalog into app assets and test resources, and tests
   require the complete 147-active-token set with representative fallbacks.

Remote category-name translation is intentionally not claimed. The local
fallback preserves other translations exactly like iOS; the remote translation
and stale-response guard belong with the later category cloud-write slice.

## Automated verification

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug`: passed; 89 unit tests, 0 failures, 0
  errors, 0 lint errors, and Room Android test sources compiled.
- Focused model/repository/editor suites cover full field round-trip, explicit
  nulls, hierarchy rules, owner isolation, locale-aware duplicates, sort
  reassignment, base-version retention, favorite behavior and every archive
  blocker.
- `swift Scripts/check-android-contracts.swift`: passed, 15 entities.
- Android localization generation and strict Swift localization generation
  checks passed with no generated changes.
- `swift test --filter MistiaSystemCategoryRemoteApplyTests`: passed 17/17.
- `git diff --check`: passed.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`0db0dc1d31a3c0f884e6a887776453d264afa493baffae1da99f780d95c5013b`.

## Device and cloud gates

`adb devices -l` returned no connected device, so no `adb install -r`, Room
instrumented execution or visual/create/edit/favorite/archive Samsung result is
claimed. The APK is ready to install as an update when the device reconnects.

Category is absent from the wallet-only remote mutation allowlist and both the
legacy global and wallet build gates remain `false`. No Supabase write,
production migration, RPC, RLS, OAuth or deployment action was performed.
