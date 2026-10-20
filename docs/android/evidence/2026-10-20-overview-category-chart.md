# Overview monthly category chart — slice108

Date:2026-10-20. Branch`codex/android-apk2-4-parity`; base`48255cff`. This slice is one local read-only Overview flow; full APK1–4/RC remains active.

## Behavior and Swift comparison

Day/Category segmented control below the chart heading, monthly history pages, category pie and positive first5+Other legend; parent and rootOther open one-level drilldown with back. Selected category month drives income/expense summary, Day returns current monthly cashflow; week/month identities retained between modes and history prepend/removal. Owner replacement clears private state before new flows emit. Owned historical category metadata supplies labels, explicit en/ja then immutable system catalog fallback; names merge by displayed Unicode whitespace/case/canonical NFC equivalence across IDs. Classifier preserves reporting overrides/signed entries/zeroordinary history and adjustment identity (category Swift snapshot rules).

Direct references: Swift`OverviewLogic.swift`606–661/847–1088, `OverviewSupport.swift`115–145, `OverviewView.swift`1545–1790, entire`MistiaCategorySpendingChartView.swift`, and SwiftOverviewLogicTests. Stored transactions @Query180 has no sort; visibleTransactions maps existing input order, so representative metadata follows first input as pureSwift. No invented occurrence ordering.

Financial improvements: BigInteger amounts through grouped/child/Other/percentage/legend formatter; only dimensionless drawing ratios useFloat. Missing or unsupported nonzero FX holds the complete affected month with localized cannot-convert hint, never partial pie/falsezero. Exact perrecord HALF_UP source conversion ignores historical reporting pair; owned wallet currency fallback, sameISO imports retain exactminor. Broader preexisting monthly Long display/clamp/missingFX/global imported-currency audit remains required, not resolved here.

## Actual TDD and corrections

Core11/11 runtimeRED against empty projection→39 focused(category11/day8/weekly10/monthly10)GREEN. BigInteger formatter truncating stub actual1/7RED→7GREEN; 2*LongMAX exactJPY/VND andUSD minor formatting. Initial8 native missing-modeRED52.334sec. JVM Unicode regex passed but Android ICU rejected`(?U)`; dedicated imported Unicode native1/1runtimeRED, NFD JVM1/11RED→portable Unicode whitespace pass+NFC,39coreGREEN and dedicatedAndroid1/1GREEN1.838sec.

First9class69.084sec had3failures: two month-list mutation IndexOutOfBounds crashes and130% legend reachability. Keying chart subtree by month identities replaces lazy count/keys/content together; subsequent9class17.911sec8pass/onlyfontfailure. Diagnostics distinguish nested-horizontal-pager performScrollTo limitation from production clipping: bounded slow outer-list gestures prove last amount has zero height at all scroll offsets. Explicit label/percent styles and measured actual text row heights replace fixed58dp estimate→9/9GREEN20.43sec. Image inspection then found child100 drill amount clipped; added actual fullglyph assertion failed1/1RED2.549sec(glyph25px vs layout16px). Measure back text/icon/padding plus10dp interitem spacing→9/9GREEN24.514sec. Test retains physical scrolling, exact beyondLong values, actual1.3font density/fullglyph root and child checks, read-only financial/outbox snapshots.

Recent/day editor integration initial2cases: recentpassed; day fixtureOct16 no longer in current week onOct20, actual1failure14.405sec. Test now navigates from current to fixture week before physical400ms hold; fixed dates and exact Room/outbox assertions retained. Final actual2/2GREEN11.561sec on checksum-verified final transaction test package.

## Review and final verification

Fresh independent review dispatched on immutable code patchSHA256`24354724fa7425862461370f220c6e8d7905e46e9e8d9f163fcfd055ffece7c4`. Review: noCritical,2Important accepted. Normal-font horizontal layout could clip >Long money, and inactive-mode removed/reappearing month/week resurrected old selections. Three newnative tests actual3/3RED13.227sec; corrected olderrecent scrolling control passed in the same4case run. Fixpass uses measured full-font money width to choose stacking and unconditional Hero observers for both period identities. MinorNEL-only importedtranslation fallback accepted as correctness issue; unit1/11RED1sec→sharedUnicode whitespace trimming/grouping. Focused39core +13native(category12/recent1)GREEN31.188sec after one fixpass; no rereview.

Minor omitted back/empty-state icons and pie gradient/rounding/shadow remain explicitly required visual parity work. Parent declined-ruling ledger: monthlyLong clamp and missingFXzero/unsupported normalization remain Important mandatory financial audits; JPY/VND primary selection follows current contract, imported-code audit stays open; fullfamily/event/investmentvisibility required; weekly count/key race unconfirmed, targeted shrink coverage retained; decomposed imported card-payment classifier remains audit work; Samsung/TalkBack/rotation/processrestore/broaderfonts finalRC pending; finalfullnative/artifacts/install/smoke owned by parent; wholeAPK1–4/cloud/schema readiness never waived.

Full host **1542JVM/148suites**, final lint/build **140sec GREEN** after review fixes (all required AndroidTest compilation/package tasks included). Earlier68sec/26sec runs predated later fixes. Swift610(4contract+137data+469core), contract15, both strictlocalization checks, SQLite7/3/11, packaged6Roomschemas/bootstrap passed after portableUnicode change. Firstfull51native134.236sec had50pass/one earlier recent-font test missing its lazy offscreen row; repaired test scrolling setup passed focused, fullglyph checks preserved. Final **54/54Overview native GREEN182.302sec** after review fixes; actual recent/day editor regressions **2/2GREEN11.561sec**. These are final artifact outcomes, distinct from earlier diagnostic failures.

## Visual and device scope

API36ARM64 Pixel5 emulator`mistia-api36-native`, restartedexistingAVD withoutwipe onOct20 afterADB/qemuabsence confirmed; transport11. Four settled PNGs in`overview-category-2026-10-20/`: root light/dark all6amounts complete; final drill light/dark bothLongMAX andchild100complete, actual1.3 density/fullglyph assertions. Parent inspected all4; provisional/clipped diagnostic captures excluded. App108 installed with`adb install -r` preserving data; cold launch`Status:ok`,1008ms, versionCode108/min26/target36 confirmed. Manifest+20DEX entries and output-metadata reviewed; generated BuildConfig all10write flagsfalse. Actual installed overview/transaction/app base.apk SHA256 matched archived final files.

No Samsung verification, liveSupabase or production write. All10 write flagsfalse; Room6, SwiftDataV11, iOS751 unchanged. No financial/outbox writes from charts.

## Remaining full-goal work

Event association badge in day rows; older sheet130% actualfontScale audit; Overviewwallets/cards/budget/duealerts/sectionconfiguration; family andinvestment APK3/4, RPC/permissions/atomicity, imported/globalfinancial audits, receipts/device/background/RC and wholebranch finalreview remain required. Full scope is not declared complete.

## Final artifact integrity

Archives ignored under`android/build/outputs/apk2/2026-10-20/`; checksum manifest`mistia-overview-category-v108-SHA256SUMS.txt` and app outputmetadata retained there.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-category-v108.apk|928db435b052789a2188fb883ba60c44857022fb7242e28add8ffa7d698fb453|
|mistia-overview-category-test-v108.apk|496b72c1f8160fed8d19521d0663494f603b6bb477035e21a9f4e74ef94aaf8f|
|mistia-overview-category-transaction-test-v108.apk|edb27a5294b2c5ae3de4a4f233e726a223ae03eb63995ff504d46a278d9bcef6|

Final logs`/tmp/mistia-overview-category-{review-green-build,review-focused,host-review-final,native-review-final,editor-final,swift-final}.log`; actualRED/diagnostic logs remain separately named`model-red`,`format-red`,`native-red`,`unicode-red`,`unicode-model-red`,`font-layout`,`step`,`child-red`,`review-red`,`nel-red`,`editor-initial`. Whitespace check passed. Review sourcepatch and all declined-ruling decisions are retained in ignored plan execution ledger. Wholebranch final review remains required at full-goal end.
