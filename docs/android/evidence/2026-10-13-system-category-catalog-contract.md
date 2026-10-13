# System category catalog/identity contract — 2026-10-13

Pure core-model parser reads the same shared MistiaSystemCategories.json used by
existing native icons. Retains 161 legacy/current definitions; 147 active rows
(20 parents, 127 children), inherited kind/hierarchy, vi/en/ja seed names, icons/
colors/fallbacks/aliases and Swift per-parent/sibling bootstrap sort ordering.
Rejects malformed registry kinds/types/colors and duplicate keys rather than
silently creating a partial hierarchy. No independent production catalog asset
introduced: APK inspection shows one assets/MistiaSystemCategories.json.
Model JVM tests consume a generated test resource copied from the shared source.
Existing management picker test now compares all 147 icon/color/fallback entries
to the bootstrap contract, preserving its existing icon-only parser API.

Exact SHA1 namespace/version5/variant UUID contract for canonical source keys,
owner-scoped cloud identity and family-scoped remote identity. Golden vectors
were added to and executed by Swift MistiaSystemCategoryIdentityTests, then
asserted by Kotlin. Loan canonical ID matches the existing planning exclusion.
Owner/remote UUID shape is strict: a regression reproduced Java accepting short
UUID notation before explicit validation fixed it. Different owner IDs produce
distinct cloud IDs; UUID letter case canonicalizes consistently with Swift.

TDD missing catalog/identity APIs RED and short-owner runtime RED observed;
four new Kotlin tests now GREEN. Four focused Swift identity tests pass, including
the cross-platform golden vectors; iOS runtime source unchanged.
Full Android testDebugUnitTest, Room test compilation, lintDebug and assembleDebug
passed (714 tasks/39s), 515 JVM tests across 68 suites, zero failures.
Contract15, Android/strict Swift localization and git diff --check pass.
All eight write gates remain false. ADB empty; no device/production requests,
writes, migrations or deployment. This slice adds no startup seed or mutation.

Next atomic local missing-default bootstrap and protection against overwriting
existing cloud customizations; only then integrate startup and return to native
bill picker/form/lifecycle/payment. The fresh-account bootstrap gap remains open
until those runtime slices are implemented and verified. APK2–4 still incomplete.
