# Overview daily spending chart — slice106

After105commit71e7c1c7. Direct Swift OverviewLogic455–555/798–846/1474–1523 groups reported expense by local day, Monday–Sunday pages through currentweek, currentweek future days included, futureweeks omitted with fallbackcurrentzero, emptyweek gaps and nonzero preconversion earliestweek preserved. Signed exact daily sums and intensity before rendering; source FX perrecord without reporting snapshot pair. OverviewWeekSpendingChart1795–2005 has positivebar tap/toggle callout, exact money and teal→pink intensity. This slice delivers weekly model and visible daychart/paging/selection. Daydetail longpress/drilldown, category mode and remaininghero sections follow as separate required slices; no placeholder interaction promised.

- [x] Model runtime RED→GREEN for calendars/week gaps/future/day zones, owned/status, shared reported-expense classification, exact signed/overflow/FXperrecord and finite intensity.
- [x] Native runtime RED→GREEN for Room→chart exactamount/selection/toggle/zero holds, historicalpaging/clear, liveprimary/rates, owner/overlay/lifecycle privacy, vi/en/ja labels, no writes and settledlight/dark130% visual.
- [x] DirectSwift/diffreview, focused/fullchecks, checksummedAPK/test/smoke/evidence/progress and independent106commit, then daydetail/category/remainingAPK1–4/RC.

All10flagsfalse; no productionwrites/deploy/migration; Room6/SwiftDataV11/iOS751. Existingimported reporting normalization/familyarchived-event/fullinvestment/editoratomicity/receiptdeviceQA gaps remain. Pure chart ratios may use floating point only after exact monetary values are finalized.

## Execution detail

**Goal:** Deliver native weekly history and exact daily-bar selection in real Overview.
**Architecture:** Pure owned weekly projection consumes the same reported-expense classifier as monthly cashflow. OverviewScreen supplies validated financial inputs/current rates; a dedicated chart owns ephemeral week/day selection. Existing hero embeds chart and clears selection when its overlay/lifecycle becomes inactive.
**Tech stack:** Kotlin/Compose Foundation pager, Material3, JavaTime/BigInteger, Room test host; minSDK26/target36.
**Spec:** `/Users/quyln/.codex/attachments/14a5e42d-74ef-4419-b511-5b60da3154aa/pasted-text-1.txt`, original requirements attachment and direct Swift references above.
**Review focus:** selected-day removal during live updates; owner/overlay/background selection privacy; extreme exact values with bounded visual ratios; stable historical selection on prepended weeks; complete localized weekday/callout text at130% font. Each maps to a native case below.

### Task 1: Weekly projection and day chart

Files: core model OverviewWeeklySpending.kt/test (new), OverviewMonthlyCashflow.kt (shared classifier visibility); feature OverviewWeeklyChart.kt/test (new); OverviewHeroMetrics.kt/OverviewScreen.kt/MainActivity.kt (wiring/overlay); app version106.
Interfaces: `overviewWeeklySpending(owner, records, wallets, currency?, rates, knownTitles, reference, zone): List<OverviewWeekSpending>` yields Monday start/current flag/seven `OverviewDailySpending(date, amountMinor:Long, intensity:Double)`; `OverviewWeeklyChart(pages, currency, overlayPresented=false)` renders owned supplied data only, ephemeral selection keyed by week, no financial writes.

- [x] Write ten model tests and execute actual runtime RED:8 intended failures/10cases against zero projection; /tmp/mistia-overview-weekly-model-red.log.
- [x] Implement exact signed daily aggregation, per-record source FX, continuous Monday pages/current fallback and finite BigInteger-range intensity; shared monthly expense classifier. Focused20tests pass /tmp/mistia-overview-weekly-model-green.log.
- [x] Write/run native missing-chart REDs: realRoom exactbar+toggle/zero, swipehistory+selectionclear/prependedhistory, liveprimary/rates+selecteddayremoval, owneremptyflows, overlay/background clear, vi/en/ja labels, settled130% snapshots; assert unchanged financial rows/outbox.
- [x] Add dedicated pager/bar selection component with exact accessible amounts, localized weekday/range and bounded chart-only ratios; root supplies overlay flag and validated weekly records. No category placeholder/longpress action until those slices exist.
- [x] Run native focused class and model20; inspect artifacts; fix actual findings using runtime RED→GREEN.
- [x] Run full testDebugUnitTest, relevant AndroidTest compile/package, lint/build, Swift610, contract15/localization/SQLite/schema/diff checks; run full Overview suite plus actual Overviewtap→storededitor integration. Record exact counts and executedAPK SHA256; install-r/coldversion smoke.
- [x] Fresh read-only review against Swift/spec/diff, fix Critical/Important with actual RED→GREEN and green suite; update evidence/progress, commit106 independently. Continue remaining fullgoal.

Ruling: Continue inline in requested checkout/branch and do not introduce new approval pauses — TXT explicitly authorizes autonomous implementation/commits and permits stopping only for real blockers/product decisions. Existing Swift fixes the design; approvals/worktree relocation from generic skills are superseded. Cost if wrong: user may request a different local workflow; no external publication occurs.

Verification: final34/34 Overview native60.672sec (11weekly), transaction navigation1/1green3.953sec;1521JVM/146suites/Swift610/lint-build/scripts. Independent2P2 review regressions, history-reset and visual weekday/fullglyph issues reproduced and fixed; all4finalPNGs inspected. APK106/evidence/progress committed independently; remainingfullgoal continues.
