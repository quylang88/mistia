# Native original finance artwork — slice125

Base `d578bade89ffbe3642de46c7e09586a0f14412d9`; branch `codex/android-apk2-4-parity`.
Status: slice-local implementation, verification, visual review and installed-artifact checks complete. Full APK1–4/RC goal remains active.

## Behavior and source authority

Registered finance icons use their actual iOS source artwork on Android through a shared native BitmapPainter renderer. This corrects concrete124 screenshots where Internet displayed a house and planning tokens displayed an ellipsis. Wallet/card, category, savings-goal, installment and Overview recent-transfer consumers now share the artwork path. Picker membership, stored token/color fields, mutation/currency rules, cloud gates and iOS runtime are unchanged. Unknown/unregistered system symbols retain their existing Android fallback.

Source authority: `Mistia/Core/UI/MistiaFinanceIcons.swift`, `Mistia/Shared/CoreLogic/MistiaSystemCategories.json`, original `Mistia/Assets.xcassets/*.imageset/*.svg`. The registry has **196 distinct registered tokens**: all161 categories (including14 inactive/historical entries) plus37 explicit descriptors with two overlaps. The147 active category picker entries are a different count. Ordered source assignments, category precedence, group fallback and template semantics are preserved.

`Scripts/generate-android-finance-icons.cjs` generates **111 original artworks**, transparent256px RGBA PNGs and a static typed Kotlin resource lookup; no product dependency, runtime SVG parser, WebView or network fetch. Generation uses existing local Sharp/libvips, while `--check` needs only Node and verifies source/output hashes, descriptors, Kotlin lookup and missing/stale resources. The generated manifest `docs/android/finance-icon-assets.generated.json` pins each source SVG and packaged PNG SHA-256; manifest SHA `53e7d220ad70ab777e4632092b50d2d5e3cd288ac10909f13280d1a12e3df889`.

Swift's registered-image behavior is retained: original artwork at **0.86 of the caller's frame**, no surrounding tile, original multicolor/gradients, and `_filled`/`_regular` art tinted with the registered descriptor primary color. Requested custom colors affect only unregistered fallbacks. Caller frame sizes remain30/34/40/44dp as supplied.256px exceeds the largest current44dp frame atxxxhdpi (`44×0.86×4=151.36px`).

An SDK Svg2Vector probe accepted135SVGs without warnings, but inspection showed the Wi-Fi elliptical radial-gradient transform reduced to a circular radius. It was not used for final assets. Raster generation preserves the original gradient without a runtime dependency. All111 original PNGs were inspected in a contact sheet; this is original repo artwork, not generated AI imagery.

## Actual TDD and focused native results

- Generator source parser: **6/6 business assertion RED**, then **6/6 GREEN**. Literal controlled fixtures cover category descriptor precedence, later assignment override, inactive fallback, explicit planning token, template tint and unsupported source/policy rejection.
- Artifact behavior: **3 new failures** before generation/check implementation, then combined **9/9 Node GREEN** (final0.846s). Actual generated PNG is256×256 RGBA, outside shape transparent and center exact red; missing original asset fails before replacing outputs; source drift/missing PNG fails read-only check.
- Runtime catalog: **5 cases / 4 assertion RED**, unknown-symbol control passed; then **5/5 GREEN**. Exact literal assets/colors: Wi-Fi, vault, amber baby-food template, historical housing fallback. Initial `requireNotNull` diagnostic was replaced by `assertNotNull` and the proper assertion RED rerun.
- Existing CategoryIcon actual emulator image comparisons: **6/6 RED, 8.133s**, mean RGB errors40.76–58.04 against independently chosen original source artwork. New renderer: **6/6 GREEN, 7.972s**.
- Actual old component/bypass failures: wallet **1/1 RED, 1.589s**; savings-goal/installment **2/2 RED, 2.773s**; Overview recent-transfer bypass **1/1 RED, 1.571s**.
- After wiring: wallet **1/1 GREEN, 1.600s**; savings-goal/installment **2/2 GREEN, 2.784s**; complete image/reference/actual-transfer class **7/7 GREEN, 9.363s**. References are literal Wi-Fi/calendar/vault/baby-food/cash/transfer artwork; native Canvas comparison checks source pixels, template color and0.86frame rather than only semantics tags.

## Full verification and regression findings

- Host **BUILD SUCCESSFUL, exit0, 58s**: full JVM, required Room/feature test compilation/packages, app lint and debug APK.
- **1736 JVM tests / 168 suites**, zero failures/errors/skips.
- A stale cached JDK17.0.20.1 class-root diagnostic appeared after Homebrew moved to17.0.21, though the host command succeeded. Gradle daemon was stopped; a fresh in-process `:app:compileDebugKotlin --rerun-tasks --no-daemon` rebuilt205tasks, **BUILD SUCCESSFUL, exit0, 193s**, without that diagnostic. Existing unrelated deprecation/always-true warnings remain outside this slice.
- Final full host after measured gallery-label assertions: **BUILD SUCCESSFUL, exit0, 161s**, all1736JVM/168suites clean. Subsequent native-fixture packages + full JVM/Roomcompile/lint/main checks passed **5s / 20s / 6s**; a final package-only fixture correction passed1s. No product source changed after the reviewed renderer/catalog/consumer implementation.
- Swift **610 XCTest cases** (4app/137data-support/469core-logic), all passed. Separate Testing Library zero-test footer is not the XCTest count.
- Contracts15entities, both localization checks, SQLite outbox7/notifications3/installment deletion11, Room6schema assets, whitespace, Node9 and generator `--check`: passed.
- Complete Management **31/31 GREEN, 136.734s**.
- Complete Planning: **136 executed / 134 passed / 2 failures, 622.137s**. `importedUsdBudgetRetainsDecimalMinorMeaningUnderVndPrimary` queried the merged edit action before Room readiness (diagnostic found it in the later unmerged tree); `realPlanningCreatesExactVndBudgetAndMatchingOutbox` timed out waiting for persistence after a physical Save click. Both unchanged cases passed isolated **2/2, 9.318s**. Fixture now waits for the actual merged edit action and uses the enabled semantic Save action for financial-persistence cases, with exact input/amount/currency/outbox assertions retained. **No physical-hit-target fix or proven cause of the transient physical-click timeout is claimed**; that remains full-goal device/root/IME coverage. Final entire OwnedBudgetEditor11 + icon-consumer2 classes: **13/13 GREEN, 42.886s**. This is not a claim of a final whole136-case GREEN run.
- Complete Overview: **152 executed / 151 passed / 1 failure, 375.782s**. An old test required legacy `fork.knife` and canonical Groceries to be pixel-identical, which contradicts Swift's registered source artwork. Replaced it with separate literal references: legacy Material food fallback, canonical original **carrot template** from Swift's final ordered assignment. The first replacement reference incorrectly chose generic Food and failed in the33-case run; this was a test-reference error, not a production regression or business RED. Final complete modified visual class **7/7 GREEN, 16.403s**, preserving strict independent pixel checks. The other32 focused artwork/gallery/watchlist/due cases ran before this last reference correction (33 executed / 32 passed / 1 wrong-reference failure,78.099s); product source and their tests were unchanged. No final whole152-case GREEN claim.
- Final current Management APK consumer case **1/1 GREEN, 1.457s**, after the clean JDK rebuild changed package bytes; its earlier full31-case run covered the same product source. All final installed test APKs match the archived hashes below.
- All111 packaged artworks render in a real native gallery, all196 source tokens resolve, light/dark gallery labels are measured at1.3fontScale with complete text. **38 original PNGs** were inspected:14gallery +12budgetwatchlist +12recurringdues (section screenshots en/vi/ja light/dark exact/variable/unavailable). No result is passed based on ADB exit code alone.

## Review and limits

Directly reviewed source Swift registry, palette, template policy and FinanceIconView behavior. Fresh isolated reviewer `review_icons125` inspected pinned source/test patch `67fe085d8da59e764400c154df5470a38528704ad730b79aa41d524c85581120`, independently ran read-only generator check196tokens/111artworks, and found no Important/Critical regression. No Gradle/device test was run by reviewer. Afterwards gallery font/full-label assertions, native readiness/reference fixtures and CI freshness wiring were updated; no renderer/catalog/consumer product source changed. Final source/test patch `/tmp/mistia-native-finance-icons-final-source-test.patch` SHA `8ec07daf7868bb3e7c3efa15728efd07d5ef24bb1d95c6bf74d2291fd8784636`.

This does not certify rounded-font identity, root/system insets, motion, every physical hit target, full financial read semantics, family/investment/receipts/settings/background/release, or a whole APK/branch gate. Those remain required full-goal work. All10cloudflagsfalse, Room6/SwiftDataV11/iOS751 unchanged; no production write/deployment/migration/live Supabase test. Emulator API36 ARM64 transport13 only; no Samsung verification claimed. Unregistered legacy/system names keep the old broad Android fallbacks; universal SF-symbol identity is not certified. The original full goal still requires remaining actual Overview sections, independent financial-read semantics, family/receipts/investment/settings, physical device/root/IME/background/release checks and a fresh whole-branch review. Separate125commit follows the checks below, then local work continues.


## Reproduction and CI freshness

Generation/tests used local Node22 + Sharp0.35.5/libvips8.18.7/librsvg2.63.2. Commands on this workspace:

```sh
NODE_PATH=/Users/quyln/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules node Scripts/generate-android-finance-icons.cjs
NODE_PATH=/Users/quyln/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules node --test Scripts/tests/android-finance-icons.test.cjs
node Scripts/generate-android-finance-icons.cjs --check
```

Android CI now explicitly sets up Node22 and runs the last read-only check, triggered by shared Swift registry/category/artwork and generator/manifest changes. No Sharp install/generation is required by CI or app builds. The workflow command passed locally; no hosted GitHub CI run is claimed.

## Archived and installed artifacts

- `mistia-0.2.0-apk2-native-finance-icons-v125.apk` — SHA-256 `0807aad1900df40c245bee0b497f29f71cd35135ad43d2eac6d531537785a7c6`, 20DEX, 35068620bytes.
- `mistia-native-finance-icons-overview-test-v125.apk` — SHA-256 `ca22852fbaa0c0d10ff0c9989bf8a9c6bf4d82f1ac9d02832bf4b331300f2bca`, 9DEX, 23933730bytes.
- `mistia-native-finance-icons-planning-test-v125.apk` — SHA-256 `f94d9271a6811bf2c8c895d9bd72d43bce8d1ae116187fde17287daefc424a23`, 10DEX, 24438927bytes.
- `mistia-native-finance-icons-management-test-v125.apk` — SHA-256 `b6f8c33cd291901dc8c1ad1602499590178dcb383ffceccc224e0cc52726d31b`, 9DEX, 23589816bytes.

Archives are ignored under android/build/outputs/apk2/2026-10-21/. Main125 installed with `adb install -r`, preserving app data. Cold launch `Status: ok`, `COLD`, **1081ms**; installed manifest version125/min26/target36. All four installed package hashes match these archives. All3native test targets36 executed on API36ARM64transport13. Emulator font_scale restored1.0; Samsung absent.
