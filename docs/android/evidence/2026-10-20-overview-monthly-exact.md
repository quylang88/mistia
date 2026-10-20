# Exact and available Overview monthly cashflow — slice109

Date2026-10-20; branch`codex/android-apk2-4-parity`; base`e8c5096c`. Full APK1–4/RC remains active.

## Behavior and direct Swift review

Monthly income and expense remain nullableBigInteger through aggregation and formatting. No finalLong clamp. Missing/invalid/unsupported nonzeroFX makes only the affected direction unavailable for that month; its partial total never appears. The other direction stays visible. Zero/excluded records do not poison availability; rates/currency/ownedwallet metadata repair live. Exact originalsource perrecord HALF_UP ignores reporting snapshot pair, with explicitsource→owned nondeletedwalletcurrency→legacyJPY fallback. SameISO importedminor retained, unsupportedcrossneverinterpretedasJPY. Public OverviewScreen normalizes its reporting/display target once to supportedJPY/VND, preventing pureUSD imports from being mislabeled asJPY.

Hero shows exact auto-sized income/expense or emdash+localized vi/en/ja conversionhint with stateDescription peraffected direction. Existing historicalCategory selectedsummary and Daycurrent behavior retained, owner replacement clears state before new flows emit. Shared OverviewMoney helper extracted fromcategory; category grouping/classifier unchanged. Long convenienceconstructor only builds explicitzero snapshots, no legacy clamping getter.

Swift references`OverviewLogic.swift`665–724, `TransactionLogic.swift`1415–1498, `OverviewSupport.swift`115–145. Existing debt/resale/adjustment/card-payment/reporting/calendar classifiers retained, including their deliberate category/monthly difference. Exact >Long/nullavailability intentionally correct Swift Int64 overflow/missingratezero under financial correctness requirement. Other asset/weekly/daytotal and globalplanning/imported audits stay open.

## Actual TDD and review

New9modelcases actual8/9runtimeRED1sec on oldLongAPI, using decimal value goldens rather than a type-only failure. Precision, bothdirections, twiceMIN, perrecordFXoverflow/cancellation/rounding, missingdirection, invalidrates/imports, sourcewalletfallback, ineligible/zero andhistory tested. New+existing10monthly/11category/8day/10weekly **48focused tests GREEN2sec** after migration. Existing oldclamp/missingFX0 golden expectations deliberately replaced with exact/null contract.

Initial6nativecases **6/6runtimeRED39.164sec** before model/UI migration→**6/6GREEN12.978sec**. RealRoom read-only snapshots, exacttwiceMAX, independentmissingFX/recovery/primary/wallet, historicalmode/owner, actual1.3fullglyph light/dark numbers/hints. FourinitialPNGs inspectedcomplete.

Freshread-only review`review_overview_monthly109` immutablepatchSHA256`55c2ad0b1a1c21ba35939caba8293bfbf7adc54f8c46c0da813bb7098757f9a3`: noCritical,1Important. RawprimaryUSD reachedpureUSDmodel, HeroformattedJPY: false¥1375. Newnativeactual1/1RED6.766sec→singlepublicboundarynormalizationfix. Recommendation added twiceLongMIN income/expense fullglyph at1.0/1.3 light/dark. Onefixpass, no rereview.

Firstfull60native149.07sec:54pass/6fail. Oneoldermonthly expectedmissingFX0; now expects emdash+hint. FiveolderRecentScreen tests queried uncomposed offscreen rows after new hint increasedHeroheight; fixtures now scroll required section before querying, preserving all money/filter/order/owner/no-write assertions. Ownercase explicitly observes count and row sections before/after and verifies replacementemptyplaceholder. A test-only missingcontext compileerror1sec was corrected with ApplicationProvider, no compile-errorREDclaim or installfromfailedbuild. Bothpackages thenbuildGREEN2sec. **20/20focusednativeGREEN36.428sec** (newmoney8+existingmonthly6+recent6) afterfixes. Finalwhole **62/62Overviewnative GREEN125.301sec**, actualrecent/day→storededitor→exactRoom/outbox **2/2GREEN6.963sec** on checksum-verified final packages.

## Verification and scope

Fullhost **1551JVM/149suites**, final lint/build **15secGREEN**, requiredRoom/management/planning/overview/transactions/settings AndroidTestcompile/package; Swift610(4contract+137data+469core), contracts15, bothstrictlocalization, SQLite7/3/11, packaged6Roomschemas/bootstrap and whitespace passed. Finalwhole62Overview and2editor regressions passed as above. Manifest+20DEX entries/outputmetadata reviewed. App109installedwith`adb install -r` preservingdata; coldlaunch`Status:ok`,1162ms, version109/min26/target36 confirmed. Actualinstalledapp/overviewtest/transactiontest base.apk hashes matcharchives.

Images in`overview-monthly-exact-2026-10-20/`, actual130% light/dark exacttwiceMAX andunavailable hints; negative fullglyph verification1.0/1.3 nowincluded. All6finalsettledPNGs refreshedfromfinalartifact andinspected: positive/negative twiceLong bounds andunavailablehints, light/dark, actual1.3density/fullglyph. Native negativecase additionally verifies1.0font.

API36ARM64Pixel5 emulator transport11; main109installed/smokeverified. Emulatoronly in`adb devices -l`. NoSamsung/liveSupabase/productionwrite. All10writeflagsfalse; Room6/SwiftDataV11/iOS751 unchanged; no financial/outbox mutations fromdisplay.

## Review declined-ruling ledger and remaining goal

Asset/weekly/daytotalLong/missingFX remain mandatory nextfinancialaudit; fullAPK1–4/family/event/investmentvisibility/receipts/RPC/editoratomicity/remainingOverviewUI notcomplete. Swift overflow/missingFXzero intentionallycorrected; separatecategory/monthlyclassifier and deliberateignoredreportingpair retained. Imported/decomposedtitle/debtambiguity/unknownedum audit staysopen. Calendar/currentfutureday/futuremonth/history andowned/deletedwallet behavior retained andcovered; malformedownedwalletcode holdsconversion, missingmetadata uses explicitlegacyJPY. SameISOimports/unsupportedcross hold intentional; pathologicalrateexponents/history/resourcebounds remainbroaderaudit. NativeTalkBack/alllocalizedlayout/Samsung/cloud not independentlyverified. Olderchartvisualminors/dayEventbadge/sheetactualfontScaleaudit stillrequired. Finalparent artifact/runtime checks completed above; no whole-goal completion claim. Wholebranchfreshreview required at fullgoalend.

## Final artifact integrity and logs

Ignored archives`android/build/outputs/apk2/2026-10-20/` with outputmetadata and`mistia-overview-monthly-exact-v109-SHA256SUMS.txt`.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-monthly-exact-v109.apk|87644a7a0d17320c5209df1b0124128c8225b6aaba13b3bd2ee73f1ac1170b44|
|mistia-overview-monthly-exact-test-v109.apk|13f64e0a737362b3671be38563ef628dbe8bee09ddce038b686362937fbbbe8e|
|mistia-overview-monthly-exact-transaction-test-v109.apk|e9ec0926b82ad961836f096b8230fb92984511c90523f47682b8d872610202dc|

Final logs`/tmp/mistia-overview-monthly-exact-{model-green,review-fixture-build,review-focused,host-final,native-final,editor-final,swift}.log`. EarlieractualRED/diagnostics`model-red`,`native-red`,`native-full`,`primary-red`,`review-green-build` retain their own outcomes, not substituted for finalsuccess. One review/fixpass/declined-ruling ledger in ignored plan workspace. Category/weekly/day/monthly guards/previousoutbox and UI financial state verified without financialwrites.
