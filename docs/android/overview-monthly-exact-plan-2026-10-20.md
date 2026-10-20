# Exact and available Overview monthly cashflow implementation plan — slice109

> For agentic workers: use superpowers:executing-plans inline with runtime TDD, one fresh read-only review, independent local commit and immediate continuation.

**Goal:** Monthly Overview income/expense remain exact beyond Long and show unavailable conversion explicitly instead of a false numeric total.
**Architecture:** Migrate the local monthly read model's two monetary fields to nullable BigInteger (null means that direction cannot be completely converted). Share category's validated exact source conversion through a small internal OverviewMoney helper; retain separate existing income/expense classification rules. Hero formats exact values and provides localized availability feedback. No persistence or outbox contracts change.
**Tech stack:** Kotlin/BigInteger/BigDecimal/Compose; min26/target36, Room6.
**Spec:** user original APK1–4/TXT, required financial correctness, slice108 independent-review Important carry-forward monthly clamp/missingFX/unsupported-code findings. Direct SwiftOverviewLogic665–724 and OverviewSupport115–145/TransactionLogic reportedIncome/Expense classifiers; intentional financial correction of Swift Int64 overflow/missing-rate zero. BASEe8c5096cf698a676d5d19c46962fa85edfe5994b.

## Global constraints

All10 write gatesfalse; no cloud write/deploy/migration/push. Account-owned active posted/calendar filtering and existing debt/resale/adjustment/card-payment classification retained. Room6/SwiftDataV11/iOS751; Androidversion109. UserTXT authorizes autonomous small slices/TDD/review/commit in this checkout, superseding generic approval pauses/relocation. No new product decision needed to preserve monetary precision and expose missing conversion.

**Design ruling:** Affected income and expense are held independently: a missing expense conversion must not hide a fully available income total. Each direction is sticky-unavailable within its month, regardless of order/cancellation. Zero needs no FX. Source explicitnonblank→owned nondeleted source-wallet code→legacyJPY; never reinterpret unsupported or malformed explicit code asJPY. SameISO imports retain rawminor, supported crossJPY/VND uses current validated rate and exact perrecord HALF_UP. Stored reporting pair ignored as currentSwift monthly behavior. Continuous history/currentfutureday/futuremonth rules unchanged. Model API used only Screen/Hero/tests; replace local fields rather than leave an unused clamping compatibility API. Ordinary amount storage remainsLong.

## Review focus

- >Long positive/negative sums and perrecord conversion/cancellation retain exact minor units through formatted income and expense, at normal/actual130% font.
- One unconvertible nonzero row holds the entire affected direction, never partial total or zero; independent other direction stays visible and rates repair live.
- Imported/malformed source codes and absent source-wallet currency cannot become mislabeled JPY; owned wallet fallback never reads foreign/deleted metadata.
- Current/historical summary selection and Day/Category transitions preserve108 period identity behavior; owner replacement clears unavailable/private state.
- Existing reporting/debt/resale/adjustment/title/calendar/status rules and read-only Room/outbox invariants survive migration; missing FX on excluded/zero rows does not poison totals.

### Task 1: Exact monthly projection and native available summary

**Files:** modify core/model/OverviewMonthlyCashflow.kt/test; new OverviewMonthlyMoneyTest.kt; extract internal helpers to OverviewMoney.kt and update OverviewCategorySpending.kt calls without behavior change; modify OverviewHeroMetrics.kt; new OverviewMonthlyMoneyScreenTest.kt; canonical xcstrings onegeneric cashflow-conversion-unavailablekey and generatedoutputs; appversion109.
**Interfaces:** OverviewMonthlyCashflow(month:YearMonth,incomeMinor:BigInteger?,expenseMinor:BigInteger?) plus a Long-argument convenience constructor for explicit zero snapshots, no clamping getter. Existing overviewMonthlyCashflow function signature unchanged; values exact nullable. internal String.overviewCurrencyCode():String? validates ISO3; internal overviewMoneyMinorExact(amount:Long,source:String,target:String,rates:List<ExchangeRateSnapshot>):BigInteger? validates source/target, identity and supported crossFX. Category uses same helper; grouping/classifier unchanged. Hero monetary rows use BasicText exactformatter/auto-size, emdash onnull, localized hint/testtag per affected direction; existing monthly amount tags unchanged.

- [x] Add9 new pure money cases against current API, compare decimalminor text to avoid a type-only RED: beyondLong sums bothdirections/negativeMIN; perrecordFX>Long/cancellation/rounding/reportingpair ignored; missingexpense withvalidincome; missingincome withvalidexpense; invalid/unsupported rates hold; importedUSDsameISO/malformed/crosshold; ownedwallet sourcefallback vsforeign/deleted/legacy; excluded/zero/owner/status rows do not poison; historical unavailablemonth/gaps/currentfutureday/futuremonth. Run :core:model:testDebugUnitTest --tests '*OverviewMonthlyMoneyTest', require intended actual runtimeREDs.
- [x] Migrate fields/aggregate state, extract validated exact conversion helper reused bycategory, preserve currentclassifier/calendar. Update existing10 test goldens to BigInteger/null financial contract, including former clamp/missingFX expectations. Run new+existing monthly/category/day/weekly suites GREEN; ordinary classification unchanged.
- [x] Native actualRED: current2*MAX income/expense exact; missingFX per-direction emdash+hint vsotheravailable; live sourcewallet/primary/rates repair; historicalCategory selectedsummary and Daycurrent; owneremptyflow; readonlyrows/outboxes; actual130% light/dark complete money (bothdirections) and unavailable hints. Newcanonical generic l10nkey vi/en/ja generated strictly.
- [x] Implement adaptive exact monetary metrics and localized availability. Focused native GREEN; inspect settled light/dark actual130% PNGs with complete amount glyphs/hints. User source money never usesDouble orLongclamp.
- [x] Fresh independent review vsplan/sourceSwift/immutablepatch, one accepted Important/Critical fixpass with runtimeRED→GREEN and finalwholeGREEN; record all minor/declined rulings. No rereview.
- [x] Full testDebugUnitTest/relevantAndroidTestcompile/package/lint/build, Swift610/contracts15/bothl10n/SQLite7-3-11/Room6assets/diff. FullOverviewnative andactual2editorintegrations; finalAPKmetadata/manifest/DEX/checksums/executedpackage/install-r/coldsmoke. Evidence/progress/independent109commit/taskdone. ContinuefullAPK1–4.

Self-review: one complete monetary read/display flow; nine corecase business values prove precision/availability; no duplicate legacy clamping API. Assets/weekly/day-total legacyLong boundaries, broaderplanning/imported audits, family/event/investmentvisibility,108visualminors,107eventbadge/olderactualfontscaleaudit, remainingOverview/RPC/receipts/RC stay required and are not claimed fixed.

Completion2026-10-20:1551JVM/149suites;62Overviewnative/2actualeditorintegrations;Swift610/scripts/lint/build/APKchecks/install-r/coldsmoke;6actual130%PNGs. Evidence`evidence/2026-10-20-overview-monthly-exact.md`. Onefreshreview/onefixpass, remainingfinancial/fullAPK1–4audit notwaived.
