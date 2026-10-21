# Overview Budget Watchlist Implementation Plan

> **For agentic workers:** use superpowers:executing-plans inline with TDD; fresh whole-branch review remains at completion of the full goal.

**Goal:** Show actual exact budget alerts on Overview using the same scoped read snapshot as Planning.
**Spec:** `docs/android/overview-budget-focus-design-2026-10-21.md` (copy accepted working design from /tmp after121 commit).
**Architecture:** shared core projection, core alert selector, actual lifecycle-aware native Overview section. No feature-to-feature dependency/new dependency/schema/cloud changes.
**Constraints:** same branch/autonomous separate local122 commit; all10writeflagsfalse; no production write/deploy/migration; shared catalog copy; owner and strict editor identities retained. Other actual missing Overview sections remain open.

### Task 1: Share budget reader and implement exact alert selection with business RED

Files: core:model BudgetReadProjection.kt/BudgetReadCategoryMetadata.kt/OverviewBudgetAlerts.kt and test OverviewBudgetAlertsTest.kt; existing planning BudgetRawPlans.kt/BudgetRawSpending.kt/BudgetCategoryReadMetadata.kt become thin compatibility wrappers or delegate to core. Keep stored edit strict and test signatures intact. No Compose in core:model.

Interfaces: public core projectRawBudgetReadSnapshot preserves121 signature; shared projectRawBudgetPlans/storedBudgetReadPlan preserve contracts as needed, planning wrappers use qualified delegates. overviewBudgetAlerts(projection:BudgetProjection,maximumCount:Int?=3,includesStable:Boolean=false,locale:Locale=Locale.getDefault()):List<BudgetBranchRow>?; null only if complete projection unavailable, known empty yields empty. Unknown branch health remains visible (priority ahead of known alarms), known exceeded before caution, exact signed ratio then locale name, limit nonnegative count. No Long narrowing/Double sort/child double count.

- Write literal pure tests before function implementation; minimal baseline equivalent to current absent section returns empty. Runtime assertion RED required, not unresolved-symbol compile failure.
- Vectors: stable excluded/explicit includesStable; exceeded before caution; max3; BigInteger ratios that collide as Double; parent one alert; unknown vs loaded-empty; locale tie and nonpositive maximum; unsupported FX does not erase an independently readable branch currency amount.
- Move existing raw adapter to core without changing policy; expose only APIs consumed by feature wrappers and selector. Focused121 raw/exact/ownership/classifier tests GREEN.

### Task 2: Render real native Overview section and verify the vertical slice

Files: overview OverviewBudgetFocus.kt/OverviewBudgetReadLoad.kt, OverviewScreen.kt, native OverviewBudgetFocusScreenTest.kt/OverviewRecentScreenTest.kt, app version122; existing catalog resources only. Shared CategoryIcon gets optional shape/glyph/alpha styling with unchanged defaults for the actual30dp Swift fallback tile.

- Before UI fix write real Room test: seed category/plan1,000/spend1,200 then wait/scroll to exact watchlist1,200/1,000/120%; current UI missing section must fail. Stable-only control hidden. Add delayed/error/retry/owner-switch/late-owner vectors, live repaired amount/category archive and record/outbox byte checks; genuine unknown is dash, not0/stable. Existing snapshot producer is the source.
- Replace APK0 count placeholder with budget focus. Known empty/stable-only hides; unavailable shows existing amount hint and error Retry. One scoped snapshot drives projection; no transient typed empty/mixed read sets. No click route for alert row, consistent with Swift noninteractive BudgetRow.
- Match Swift OverviewSection header13sp bold uppercase/tracking0.6sp outside card/gap8dp; flat22dp grouped card/row insets14dp/icon30dp. Add actual geometry RED before correcting the initial generic card. Use shared symbol/rounded section, dynamic full percentage, exact spent/limit wrapping, bounded known progress, day count/tints. Capture en/vi/ja light/dark actual130% and inspect all final images. Do not claim root/system-inset certification from component fixtures.
- Focused unit/native GREEN, direct immutable diff/Swift review; reproducible important findings get RED→GREEN. Full testDebugUnitTest/Room+featureAndroidTest compile/package/lint/main; full relevant Overview and budget regressions; Swift610/contracts15/strictlocalizations/SQLite7-3-11/Room6schemas/diff whitespace. Inspect actual footers and terminal0.
- Archive final main+executed test APK122, manifest/DEX/version/min/target, install-r/cold/installed checksum. Evidence/progress and independent local122 commit, task-done contract; continue actual upcoming due/investment/preparing/config and remaining APK1–4/RC. No extra permission handoff within existing authorization.
