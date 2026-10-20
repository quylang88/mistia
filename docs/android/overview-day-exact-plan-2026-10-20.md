# Exact and available Overview day chart/details implementation plan — slice110

> For agentic workers: use superpowers:executing-plans inline, actual runtime TDD, one fresh read-only review and an independent local commit; continue full goal.

**Goal:** Day chart bars/callouts and opened day totals remain exact beyond Long, with explicit missing-conversion states and truthful original row amounts.
**Architecture:** NullableBigInteger perday sums and week availability reuse109OverviewMoney; one unconvertible day holds the displayed week rather than show a partial/falsezero chart. Day details retain every owned eligible dated row, nullable originalMoney when explicit currency is malformed, and nullableBigInteger exact total. Existing selection/pager/haptic/longpress/editor flow preserved for availablepositive days.
**Tech stack:** Kotlin/BigInteger/BigDecimal/Compose Canvas; min26/target36, Room6.
**Spec:** originaluserTXT/fullAPK1–4 financialprecision;108–109 mandatory weekly/daytotal audit. SwiftOverviewLogic weekly chart/snapshot and OverviewView1790–2265 Daychart/details; classifiers remain deliberately separate as existing. BASE87449ee49e81bf10d6bf19c98d04324d9b707df7.

## Global constraints

All10writeflagsfalse; no push/deploy/migration/productionwrite. Room6/SwiftDataV11/iOS751 unchanged; Androidversion110. Read-only owner scoped activeposted/dateguards, existing monthly/week reportedexpense classifier and day originalspending classifier preserved. UserTXT explicitly authorizes autonomous slices/review/fix/commit in this checkout, overriding generic approval/relocation gates.

**Financial rulings:** Zero needsnoFX. Explicitnonblank source→ownednondeletedwalletcode→legacyJPY consistently with109reporting. SameISOimports exactrawminor; malformed/unsupportedcrossholds. Weekly currency=null now resolveslegacyJPY rather than rawmixedcurrency summation (allUI callers supply validatedprimary). Perday unknown is sticky; week anyunknown shows existing localizedspending-unavailable hint and no misleading bars/axis/callout/hold. Keep pager/history/dateheader. Daytotal sumsoriginalsourceamounts perrecordexactFX, notreportingoverride, preservingSwiftdaysemantics. Day rows with malformed originalcurrency remain visible/countable with money=null/emdash; originalamounts never relabeled asJPY/primary. Unknown originalzero does notpoison total. Dayoriginalsource fallback alignslegacyJPY reporting (formerprimaryfallback intentionallycorrected); globalRecentmissingcurrencyprimaryfallback remains required importedaudit. Rawmalformedamount/date globalprojection audit remains open, not claimedfixed.

## Review focus

- Positive/negative >Long totals, converted overflow and cancellation remain exact through chartscale/callout/accessibility/daytotal formatting; floatingpoint onlydimensionless ratios/intensity.
- MissingFX or malformed/unsupportedcurrency cannot produce partialweek/falsezero or stale selectedmoney; rate/primary/wallet changes repair withoutwrites.
- Original rows retain exactsourcecurrency or explicitunknown, includinglegacyJPY fallback andmalformedcurrency count; daytotal differsfromreportingoverride intentionally.
- Owner replacement/lifecycle/overlay/mode/historyprepend/shrink preserveprivacy and valid periodidentity, clearingstale selections before callbacks.
- Normal/actual130% light/dark axis/weekdays/callout/daydate/daytotal/unknownhints staycomplete/reachable, and positivebarhold→row→storededitor remains exact/read-only untilauthorizedsave.

### Task 1: Exact available day chart and details

**Files:** modify OverviewWeeklySpending.kt/test, OverviewExpenseDay.kt/test; new OverviewDayMoneyTest.kt; modify featureOverviewWeeklyChart.kt/OverviewDayTransactionsSheet.kt and related nativefixtures; new OverviewDayMoneyScreenTest.kt; appversion110. Reuse OverviewMoney helper and existingconversionUnavailable localization; no persistence/schema/APIcloudchange.
**Interfaces:** OverviewDailySpending(date:LocalDate,amountMinor:BigInteger?,intensity:Double) with Long convenienceconstructor for fixtures; OverviewWeekSpending keepsstart/isCurrent/points/end and adds hasUnavailableConversion:Boolean +totalMinor:BigInteger?. Existing overviewWeeklySpending signature unchanged but nullcurrency resolvesJPY. OverviewExpenseDayRow(transaction:LedgerTransactionRecord,money:Money?); OverviewExpenseDay totalMinor:BigInteger? (otherfields unchanged). Existing overviewExpenseDay signature unchanged. UI skips financialdrawing when weekunavailable; all knownmoneyusesBigDecimal(BigInteger)/formatterBigInteger overload. Source-row nullmoney shows emdash with localizedstateDescription; daytotalnullshows emdash+existingconversionhint.

- [x] Add purebusinessvalue goldens againstoldAPI before implementation: week/day2MAX/2MIN; FXoverflow/cancellation/rounding; weekdayunknown withotherwisevalidday andwholeweekavailability; recovery; ownedwallet/sourcepriority/legacyJPY; sameISOUSDimport andunsupportedcross; malformedoriginalcurrency rowretainedunknown/countandnonpartialtotal; zeros/ineligible/calendar/futureweek/history. RequireactualruntimeREDs, no type-only RED claims. Add interfaceproperties only as smallest failing stubs if compilationneeds; recordthem.
- [x] Native actualRED on109: exact2MAXbar+callout+350mshold/daytotal+sourceRows/back/no-write; missingFXweekhint/nofalsebar/stale-callout-clearing+recovery; liveprimary/wallet/owner/overlay/history; malformedsource/daytotal/sourcefallback; actual1.0/1.3 light/darkfullglyph and physicalsheetexpansion. Keep installedbaseline artifact immutable while testing.
- [x] Implement nullableBigInteger projections/sharedsourceFX, update previous10weekly/8day goldens to exact/null/retainedunknownrow contract. Preserve existing classifier/calendar tests. Focused coreweekly/day/category/monthly GREEN before broaderchecks.
- [x] Implement chartunknownpage/selectionguards/exactaxis/ratio/callout semantics, nullable originalmoney/exactdaytotal/hints. FocusednativeGREEN; inspectfinalsettledPNGsactualdensity/fullglyph/physicalrowdisplay. No guessed layoutfixes; actualRED→GREEN when needed.
- [x] Fresh independentread-onlyreview againstimmutablepatch/Swift/spec; oneImportant/Criticalfixpass runtimeRED→GREEN/finalwholeGREEN, recordminor/declinedrulings. No rereview.
- [x] Full testDebugUnitTest/relevantAndroidTestcompile/package/lint/build, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/diff; fullOverviewnative andactual2editorintegrations. APKmetadata/manifest/DEX/checksums/executedpackage/install-r/coldsmoke, evidence/progress, independent110commit/taskdone. ContinuefullAPK1–4/RC.

Self-review: complete Daychart→details flow, all5reviewfocusinputs pinned. Category/monthly109helpers and no-write invariants retained. Assets/globalplanning/Recentlegacy-originalcurrency/rawmalformed/importedclassifier audits; family/event/investment/RPC/receipts/editoratomicity/remainingOverview/visualminors/Eventbadge/oldsheetfontscale/deviceRC/wholebranchreview remain required.

Completion: 58focused models/6suites; final20focused native54.199sec; 71Overview176.905sec and2editor10.459sec; full1561JVM/150/Swift610/scripts/lint/build pass. All10finalactual130%PNGs inspected. Three executed APK checksums match archives; app110 install-r/cold1181ms/version confirmed. One review/fix pass, no rereview. Old superpowers plugin disappeared from catalog/filesystem mid-turn; task-done helper unavailable, equivalent full checks executed without claiming helper execution. Continue assets/global inputs/remaining APK1-4/RC.
