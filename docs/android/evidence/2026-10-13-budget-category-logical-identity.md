# Budget system category logical identity — 2026-10-13

Binding product decision: one currency per budget branch, rejecting mixed saves.
The guard includes effective carried plans and future anchors; imported existing
records are preserved without automatic money conversion.

Swift source review: MistiaSyncLocalStore.scopedCategoryIDMap/remoteCategoryIDMap
maps owned system rows to canonical IDs; PlanningSupport.planningSnapshot prefers
frozen IDs. PlanningEditors uses live relationships for duplicate/auto-parent
checks and refreshes snapshots on explicit save. PlanningBudgetSpendingIndex
matches category/branch UUID or normalized name and deduplicates transactions.
Android now normalizes owned system UUID comparisons via typed metadata while
preserving live cloud FKs and frozen display values. Custom UUIDs stay unchanged.

TDD runtime RED: BudgetPlanningTest 2 failures and BudgetRepositoryTest 4 failures
under renamed live categories, imported canonical snapshots and actual legacy
FKs. Observed separate casing regression RED before normalizing payload owner
UUID. GREEN adds coverage for parent totals including unbudgeted deleted child,
no double counting, immutable projection snapshots, custom/foreign identity,
tombstone metadata/picker exclusion, malformed foreign viewer row isolation,
canonical auto-parent/family propagation and actual wire parent flag reset.

Native form uses the same identity index for branch currency inheritance, frozen
path selection and picker selection. Full category metadata observer includes
owned tombstones; active picker observer remains unchanged. Room reopen test now
asserts 147 metadata rows versus 146 selectable rows after one tombstone; this
instrumented assertion is compiled but not run in this slice.

Final Android testDebugUnitTest: 550 tests/70 suites, zero failures/errors.
Room and planning instrumented-test Kotlin compilation, lintDebug, assembleDebug
passed (724 tasks, final run29s). Swift PlanningLogic52 and identity4 pass.
15-entity contract, Android l10n and strict Swift generation checks pass;
git diff --check passes. Direct local source/diff review; no independent reviewer
approval claimed. ADB empty: no emulator/Samsung runtime claims for this slice.
All eight generated write gates false. No production requests/writes/deployments.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-budget-category-identity-v14.apk
Package vn.com.quyln.mistia.debug, versionCode14/versionName0.2.0-apk2-debug.
One packaged shared system catalog asset.
SHA-256: 680f924915a970234e5ff92c78c9d7a19ef41b28279a40c5a650e36fb3d2960e

Boundary: no startup seed enabled yet. Different-ID remote system-key collisions
need owner-key lookup plus atomic reference/outbox reconciliation. Native bill
UI/payment, due maintenance, remaining APK2–4 and final physical verification
remain incomplete. Full goal remains active.
