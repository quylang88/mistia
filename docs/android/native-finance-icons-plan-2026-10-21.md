# Native Finance Icon Artwork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline. Original TXT explicitly authorizes autonomous slices, verification, commits and continuation without repeated design/plan permission. Fresh review at coherent-slice completion; whole-branch review remains final goal work.

**Goal:** Registered finance tokens render their actual shared iOS artwork on Android.
**Architecture:** Deterministic build-time SVG→transparentPNG resources plus static typed Kotlin catalog, one native Compose renderer, existing component fallback for unknown symbols. No product dependency or iOS runtime change.
**Tech Stack:** Kotlin/Compose/Android BitmapPainter; Node Sharp from configured workspace runtime for generation only; Node test runner/JUnit/native screenshot pixel checks.
**Spec:** docs/android/native-finance-icons-design-2026-10-21.md

## Global Constraints

Base d578bade89ffbe3642de46c7e09586a0f14412d9; existing codex branch/workspace. All10cloudflagsfalse, Room6/SwiftDataV11/iOS751unchanged, no production writes/deploy/migrations. Staticcopy only shared localization. Exact original SVG artwork; source196registeredtokens includinginactive,147activecategorypicker unchanged. Requested frame preserves layout; registeredimage0.86frame/no addedtile; template tintbaseHex, multicoloruntinted. Unknown symbols preserve old fallbacks. PNG256px; no runtime SVG/WebView/newnetworkdependency.

## Review Focus

- Old inactive/legacy tokens must use source group fallback and not vanish; generator actual-source completeness and literal legacy fixture.
- Later duplicate asset assignments override earlier mappings; literal controlled generator fixture.
- Template tint must come from descriptor color while fullcolor assets keep gradients; actual native literal-source pixel comparison.
- Custom runtime colors must not recolor registered fullcolor art; actual CategoryIcon comparisons with two different requested colors.
- Caller frame size and largefont must not crop/stretch/doublebackground icon; actual30/44dp/lightdark130% native cases and inspectedgallery.

### Task1: Source catalog and transparent resource generation

Files create Scripts/generate-android-finance-icons.cjs, Scripts/tests/android-finance-icons.test.cjs, android/core/designsystem/src/main/java/vn/com/quyln/mistia/core/designsystem/FinanceIconAsset.kt + FinanceIconAssets.generated.kt, resource drawables and docs/android/finance-icon-assets.generated.json; JUnit FinanceIconAssetTest.kt.
Interfaces consumes original Swift registry/categoryJSON/assets; produces FinanceIconAsset(assetName:String,drawableRes:Int,primaryHex:String,template:Boolean), financeIconAsset(token:String):FinanceIconAsset? and generatedFinanceIconAssets:Map<String,FinanceIconAsset>. Generator exports readFinanceIconRegistry(swift:String,categories:unknown):Map token→descriptor and command generate/check. `--check` validates SHA source/outputmanifest and generatedKotlin consistency, stale/missingfiles, no Sharp needed.

- [ ] Write literal controlled source-parser/orderedoverride/categoryprecedence/groupfallback/template/missingasset drift tests; absent adapter RED, no syntax/import error as business RED.
- [ ] Implement minimal safe parser/validator, run Node GREEN. Generate PNG with installed workspaceSharp retaining transparentalpha/gradient; same deterministic output on repeated generation/check.
- [ ] Write runtime lookup test: Internet→ic_fluent_wifi_24_color untinted, plan.loan→ic_fluent_vault_24_color, category babyfood→ic_fluent_bowl_salad_24_filled with baseHex, legacyhousing groupfallback; unknown→null. Watch null-adapter assertion RED, then generate lookup andGREEN.
- [ ] Inspect full originalPNG gallery; verify source/outputSHA and no opaquebackground/gradientloss; focusedNode/JVMGREEN. Commit together withTask2 coherentvertical125feature afterallchecks.

CI wiring: add generator `--check` to .github/workflows/android.yml with explicit Node22 setup and path triggers for Swift registry/categoryJSON/artwork/generator/manifest. Check itself uses no Sharp; no generation/dependency download in CI. Local workflow command is verified; a hosted GitHub run is not claimed.

### Task2: Actual native component consumers

Files create core/designsystem FinanceIcon.kt; modify CategoryIcon.kt, management WalletEditor.kt WalletIcon, planning InstallmentEditorSheet.kt InstallmentIcon and SavingsGoalIcon.kt, OverviewRecentTransactionRow.kt. Add native artwork comparisons to existingfeaturetestmodules with testassets independentliteral expectedartworks.
Interface consumes financeIconAsset(token); produces FinanceIcon(token:String,modifier:Modifier) native registeredart frame, no financialmutations. Existingcomponent wrappers detect registeredasset and use it; else currentfallback. No pickerwirechanges.

- [ ] ExistingCategoryIcon native tests compare correctliteral WiFi/calendar/vault/template sourceart at30/44dp, dark/light andcustomcolors; run oldrenderer actualbusinessRED beforewiring.
- [ ] Render originalPNG0.86frame with correcttemplateColorFilter/untintedcolor; wireCategoryIcon; focusedactualGREEN.
- [ ] Actualwallet/goal/installment wrappertests use literalexpectedasset andframe; runoldwrapperREDthenwireandGREEN. RemoveOverviewregisteredtransferbypass undernativeRED.
- [ ] Run affectednativeOverview/Planning/Management consumer regressions; inspect gallery/130%envi ja lightdark images, fullsource/testdiff+Swift andfreshisolatedreview; fixImportantwithruntimeRED→GREEN.
- [ ] Full testDebugUnitTest/Roomcompile/allrelevanttestpackages/lint/main, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6schemas/whitespace +generator--check, requireterminal0/JUnitfooters. Version125/archiveexecutedAPKs/manifestDEX/adbinstall-r/cold/installedhash. Evidence/progress/separatecommit, postcommitcheck/ledgercomplete, continuefullgoal.
