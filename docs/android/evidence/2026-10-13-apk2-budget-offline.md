# APK 2 budget offline repository — 2026-10-13

## Scope
Owner-scoped budget observation, create/edit, archive and tombstone delete via
FinanceRepository, with atomic Room cloud-record/outbox batches. No budget UI
or budget cloud-write path is claimed by this slice.

Direct Swift references: PlanningEditors.swift budget save, parent creation,
family scope propagation, carry-forward edit, archive/delete; PlanningSupport.swift
refreshCategorySnapshot; PlanningLogic.swift validateBudgetAllocation.

- Snapshots retain all localized names, paths, role, icon/color and parent metadata.
  Moving a budget from child to parent emits explicit nulls for removed metadata.
- Monthly duplicates, positive Long amounts, local-zone month anchors and parent/
  child allocation caps are validated before persistence. Exact parent totals
  reject overflow without committing any part of a batch.
- A carried-forward edit creates a new UUID/month record, retaining its source
  month. Normal editing preserves currency, createdAt and remote base version.
- The second child auto-creates a parent budget with summed limits and rollover
  disabled. Editing an old parent into the second child recreates the parent.
- Existing family scope is inherited from selected category, parent or budget;
  selected-month siblings refresh snapshots when scope is promoted. Deleting the
  final current-month branch budget resets the category scope in the same batch.
  New cloud-first family enablement and cross-subject aggregation are deferred.
- Decoded payload user_id is checked in addition to the viewer envelope, so
  RLS-visible foreign rows cannot become personal budgets or dependencies.
  Explicit editingExisting intent rejects missing edit IDs while create supports
  caller-chosen UUIDs. Coroutine cancellation propagates.

## TDD and review
Initial RED: missing BudgetDraft/repository/batch interfaces. GREEN: persistence,
snapshots, base versions, duplicates, caps, carry-forward and auto-parent tests.
Runtime RED exposed mismatched JVM/Tokyo month handling in delete; unified
repository calendar zone fixed it. Independent review reported payload-owner
projection, edited-parent exclusion and promoted-sibling snapshot mismatches;
all three were reproduced as failing tests, fixed and passed. A second review
found enabled-child/disabled-parent scope inheritance; its regression was
observed failing, fixed, and passed. No reported finding remains unresolved.

## Local validation
- Full Android command: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  ./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :core:database:assembleDebugAndroidTest :app:lintDebug :app:assembleDebug
  --console=plain --max-workers=1`: BUILD SUCCESSFUL, 727 tasks, 1m32s.
- 332 JVM tests across 52 suites, zero failures; 14 are budget repository tests.
- Room instrumented tests compile and their APK assembles; schema remains v3.
- Lint passes with 0 errors (existing warnings remain).
- 15-entity contract check, Android localization and strict Swift localization
  checks pass; `git diff --check` passes.
- Focused Swift PlanningLogicTests: 52/52 passed using full Xcode DEVELOPER_DIR.
- APK versionCode 4, versionName 0.2.0-apk2-debug; 653 packaged files.
  Global/category/wallet/card/transaction cloud-write flags all remain false.

Artifact: `android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-budget-offline-v4.apk`.
SHA-256: `30f062a2f8f0c6222f384fcfa9d45b2dcacf48081d619a322b55cfda927975cd`.

## Device and cloud boundary
ADB initially saw emulator-5582 offline, later API36 sdk_gphone64_arm64 in device
state. Direct `adb install -r` of the database test APK failed with connection
closed/device offline before instrumentation could execute. The emulator then
disappeared; this SDK has no emulator executable. No Room runtime or emulator UI
claim is made. No Samsung was connected. No live Supabase request/write, migration,
RPC, Edge Function change or production deployment occurred.

Next slice: independently gated budget push including iOS conditional tombstone
delete semantics; then native budget projection/editor. APK 2–4 remain incomplete.
