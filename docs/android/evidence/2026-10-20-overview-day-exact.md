# Exact and available Overview day chart/details — slice110

Date2026-10-20; branch`codex/android-apk2-4-parity`; base`87449ee4`. Full APK1–4/RC remains active. All slice checks and artifacts below are verified; the broader goal remains active.

## Behavior and direct Swift review

Weekly perday values, totals, chartscale/axis/accessibility/callout and original daytotal retain nullableBigInteger without finalLong clamping. Missing/invalid/unsupported nonzeroFX holds the entire affected week with localized conversionhint; no partialbars, falsezero, axes, stalecallout or hold. Pager/date/mode/history remain. Live rates/primary/ownedwallet changes repair; owner replacement retains no previous money. Dimensionless ratios/intensity alone use floatingpoint.

Explicitnonblanksource→ownednondeletedwalletcurrency→legacyJPY, consistently with109reporting. Default nullreportingcurrency resolvesJPY instead of rawmixedunits. Exact sameISOimports remain available in puremodels; unsupportedcrossheld. Original dayrows retain sourceamount/currency, includinglegacyJPY fallback and malformedcurrency rowcount/selectability as unknownmoney/emdash. Unknownzero needsnoFX; nonzero unknown neverpartiallytotalled. Daytotal sumsoriginalamounts, notreportingoverride, intentionally preserving separateSwiftdayclassifier contract. Positive reportedbar can therefore open negative originaltotal, tested exactly at twiceLongMIN. Parentlanguage/resources/density and sourcecashflowprefix/LongMINmagnitude fix retained.

Direct Swift`OverviewLogic.swift`455–550 weekly Mondayhistory/calendar and `OverviewView.swift`2059–2270 details/date/count/rowdismiss/order compared; existing `TransactionLogic` reporting/spending classifiers remain separate. Nullableexactmoney intentionally corrects Swift Int64 overflow and source-minors mislabeledprimary under user'sfinancialcorrectness requirement. No persistence/schema/syncchange.

## Actual TDD and diagnostics

New10businessmodelcases on109API: **9/10actualruntimeRED1sec**, guards case alreadypassed. Valuegoldens avoid type-onlyRED. >Long positive/negative, perrecordFXoverflow/rounding/cancellation, stickyunknown/recovery, ownedwallet/sourcepriority/legacyJPY/nulltargetmixedunits, USDsameISO/unsupportedcross, malformedcountableunknown/zero, calendar/history/future/ineligible covered. Migrated oldweekly10/day8 goldens to exact/null/retainedunknown contract. **58focusedmodel/6suitesGREEN**, last combinedbuild/nativepackageGREEN6sec.

Initial native8baseline **8fail52.491sec** contained6intendedbusinessREDs and2invalidholdhelpertimeouts: substringzero matcher incorrectlymatched200/250VND. CorrectedhelperrequiresactualOnLongClick; rebuilt109two-model baselinefixtureGREEN1sec, restored in-progress110sources byte-identically viaSHA256, reran2cases **2/2actualheader-valueRED14.337sec**. These diagnose different outcomes; no invalidtimeout/compilefailure claimedfinancialproof. Currentnative8 **8/8GREEN25.106sec**: actualRoom/read-onlyrows/outbox, physicaltap/callout/350mshold, exactdayheader/originalrows, unknownweek/rates/metadata/primary/owner, malformedsource/count/selection, actualdensity1.0/1.3fullglyph andlight/dark.

Tenfinalsettled130%images (refreshedfromfinalproductionfocusedrunafterreviewfix) in`overview-day-exact-2026-10-20/` inspected: chartselection, positiveexpandedday, negativeexpandedday, unknownsheet andunknownweek, eachlight/dark. ActualfontScale/fullglyph/physicaldisplay assertions executed; originalrows are scrolled into view, unknownhint screenshot captures hint while lowercontent remains scrollable. Axisglyph andphysicalocclusion checks are separate; Final captures show both readable after the review fix.

## Independent review

Fresh read-only review by`review_overview_monthly109`, immutablepatchSHA256`b5521c8e29131e61d92d72e2f550075618ea6ee77d2aedff3a71157fcf238de2`: noCritical/Important; ready subjectparentchecks. Minor selectedwidecallout obscured upperaxis at130% (individualglyphbounds donotproveocclusion). Parent chose tofixwithin110: dedicatedphysicalbounds native **1/1actualRED2.418sec**, selectionRect(180,1251,902,1325) overlappedaxisRect(121,1232,433,1290). Reserve measuredcalloutrowaboveaxes, retainfullmoneywidth/transparentphysicalhitbehavior andexactfinancialratio. Onefixpass, no rereview. Firstpostfixfocused20: **19pass/1fail52.993sec**; actualoldphysicalcallouttap no longer cleared selection because it now sits above dayhitareas. Parentchartbackground now clears taps outside children; callout remains noninteractive anddaytap/hold consume their own events. Renamedoldtest to describe physicalclear+dayreselection and strengthened it with reselect/assert. Final **20/20focusednativeGREEN54.199sec** aftertapfix, including physicalaxisocclusion anddayreselection/hold. FullpostfixJVM/lint/build **GREEN4sec**,1561JVM/150unchanged. All10PNGs refreshed andinspectedafterthisfinalproductionrun: topaxis/callout bothreadable, originalsourcepositive/negative/unknownhintscomplete. No failedtesthidden. ExistingCashflowcountlabel/Eventbadge/chartvisuals/olderactualfontaudit remainopen. Reviewerinspected3images, parentalall10inspectionseparate.

Declinedrulings: wholeweekholdswithheldbyexplicitdesign; positiveonlychartselectionmatchesSwift; originalvsreportedtotalintentional; legacyJPYnotRecent/importresolution; rawinputfiltering auditremains; pager/lifecycle/ownerguards inspectedbutnoindependentrace/deviceverification; hugeexponents/extremehistory/unboundeddigits/resourceboundsnotordinaryinputproof; TalkBack/alllocales/Samsungnotverified; remainingfinancial/family/event/investment/RPC/receipts/editoratomicity/UI/RC/wholebranchreviewnotwaived; finalartifact/native/cloudnotindependentlyexecuted.

## Verification

Host full **1561JVM/150suites**, zero failures/errors/skips; full lint/build **70secGREEN** and relevant Room/management/planning/overview/transactions/settings AndroidTestcompile/package. Swift610(4contract+137data+469core), contracts15, bothstrictlocalization, SQLite7/3/11, Room6schema/bootstrapassets pass. FirstfullOverviewnative **68pass/2fail154.253sec**: botholdDayScreen fixtures still awaitedLong.MAXclampedaggregates. Helpers nowacceptBigInteger; expectedMAX+100 andMAX+96 exactvalues, preserving sign/date/font/row/read-only checks. **2/2focusedGREEN7sec**. No productionchange. Finaltestfixturepackage+lint/buildGREEN8sec. Pre-reviewvisualfixwholeOverview **70/70GREEN159.28sec**. This result ispreservedaspre-axis-fix, notfinalnewUIproof. Reviewminorphysicalocclusiontest added; final **71/71OverviewnativeGREEN176.905sec**, afterallfixes, onchecksum-matchingfinalpackage. Postreviewfullhost1561JVM/150 +lint/buildGREEN4sec. Actual recent/day-row editor integrations passed 2/2 in 10.459sec, retaining exact Room/outbox assertions. App110 installed with adb install -r preserving data; cold MainActivity Status:ok, 1181ms. Installed version110/min26/target36 confirmed; all three installed base.apk checksums match archives below. API36 ARM64 Pixel5 emulator transport11 only; no Samsung connected.

## Remaining full goal

Assets/globalplanning exact/availability, Recentlegacyoriginalcurrency/rawmalformed/importedclassifier, family/event/investmentvisibility/RPC/receipts/editoratomicity/remainingOverviewbudget-due-config-walletcards, olderchartvisualminors/dayEventbadge/oldsheetactualfontscaleaudit/devicebackground/processkill/RC andwholebranchfreshreview remain required. No broadercompletion claim. All10cloudwriteflagsfalse, Room6/SwiftDataV11/iOS751 unchanged; emulatoronly/noSamsung/liveSupabase/productionwrite/deploy/migration.

## Final artifact integrity

Ignoredarchives `android/build/outputs/apk2/2026-10-20/`, metadata/aaptbadging and `mistia-overview-day-exact-v110-SHA256SUMS.txt`. Mainmanifest+20DEX, Overviewtest9DEX, transactiontest11DEX inspected; version110/min26/target36. All three executed/installed base.apk SHAs match archives below.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-day-exact-v110.apk|878a8698d2dfb339b4471d217ddf14756395bc37bbb89e856eb68abf7850dc07|
|mistia-overview-day-exact-test-v110.apk|34d44fc07ec9a89061554b16b0ba085b3ded81060e800ffe5bf5a4eb69f14834|
|mistia-overview-day-exact-transaction-test-v110.apk|c3857bd90387f52d75c3adbbb0429feab5015bac5ca69cc5c73adf47fea083a2|

Logs `/tmp/mistia-overview-day-exact-{model-red,model-green,native-red,baseline-fixture-build,corrected-native-red,native-green,host-final,swift,native-first-full,fixture-focused,native-70-pre-review,axis-red,axis-focused,axis-tap-focused,host-post-tap,native-final}.log`; diagnostic/pre-fix outcomes retain theiractualstatuses; Final footer checks passed: 71 Overview and 2 editor tests. ADB exit0 alone was not treated as JUnit success. Finalimagesfromchecksum-matchingfinalOverviewAPK focusedrun, notdiagnosticbaseline captures.
