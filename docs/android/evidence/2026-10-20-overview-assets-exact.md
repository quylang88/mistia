# Exact and available Overview assets - slice111

2026-10-20; branch `codex/android-apk2-4-parity`, base `022988f3436bc167bd97a6f73bfec2ea96fec9ca`. Full APK1-4/RC remains active. All slice checks and installed artifacts below are verified; broader APK1-4/RC remains open.

## Behavior and Swift comparison

Available assets retains nullable BigInteger from exact wallet balances and remaining inventory through current FX, combined total and Hero formatting. Missing/invalid/unsupported nonzero conversion makes the complete total unavailable; an omitted component never appears as zero or a partial result. Zero needs no FX/currency. The strict OverviewMoney helper now accepts BigInteger balances; its Long entry point delegates without changing monthly/category/day semantics. Same-ISO imports retain exact minor units, unsupported cross conversions remain held. Wire/storage amounts remain signed Long.

Cash classification is unchanged: active owned noncredit wallets, exact original source/destination legs, future posted entries, family/debt/shared/resale treatment. Conversion rounds each final wallet balance once, preserving Swift behavior: two 3JPY postings in one wallet convert to15VND at2.5; separate 3JPY wallet balances convert to16VND. Signed cancellation remains exact beyond Long.

Inventory retains active owned channel/assets and latest owned snapshot ordering by occurred/created/UUID. An asset with no position snapshots contributes zero. An unorderable calendar or malformed latest positive-position quantity/cost holds the portfolio, never an older snapshot or partial known assets. Quantity must be a decimal string; cost an integer JSON number. Nonpositive quantity contributes zero without cost; negative numeric cost remains normalized to zero. Accounting metadata remains independent of wallet cash parsing. Invalid existing currency with nonzero inventory is held; Screen no longer drops cost on null metadata. Unknown inventory stays unknown.

Hero shows an exact adaptive value or emdash and localized asset-availability explanation/stateDescription. Rates/primary/wallet/position/archive changes recompute live; owner-keyed composition clears old values before next-owner flows emit. No display operation changes financial records or outbox. One catalog key added with vi/en/ja and both generated outputs.

Direct references: `OverviewLogic.swift`407-455, `OverviewView.swift`655-688, `InvestmentLogic.swift`397-420, `InvestmentModels.swift`367, `InvestmentSyncModels.swift`304-305. Strict wire shapes match Swift String/Int64 decoding; negative cost normalization and nonpositive positions preserved. Nullable exact reporting intentionally corrects Swift overflow and missing-rate-zero under the user's financial correctness requirement.

## Actual TDD and local checks

New12 business model cases against110 API: 8 actual runtime RED in1sec; four existing safeguards passed. Goldens compare decimal monetary values, not only types. Cash2MAX/2MIN, final-wallet conversion overflow/cancellation/rounding, partial missing FX/recovery, supported/imported/malformed currency, zero/ownership, combined inventory overflow, malformed latest position/strict wire/calendar/no resurrection covered. After implementation and prior15 assets-golden migration, 85 focused tests in8suites GREEN2sec. Original date/order/UUID/cash classification coverage retained.

Eight native baseline cases on110: 7 intended money/availability RED in47.148sec; owner-before-flow safeguard passed. After implementation, 8/8 GREEN19.1sec. Actual Room snapshots/outbox for six entities, live rate/primary/wallet/accounting/position repair, sold/archive, unsupported source/primary, owner replacement, exact cash+inventory and positive/negative beyond Long. Actual1.0/1.3 density and full-glyph bounds, physical display and settled captures tested. Six final-production PNGs in `overview-assets-exact-2026-10-20/` inspected: positive2MAX, negative2MIN and unavailable, light/dark at130%; numeric bounds additionally verified at100%.

Full host: 1573 JVM tests/151 suites, no failures; required Room/management/planning/overview/transactions/settings AndroidTest compile/package, lint/build GREEN75sec. Old assets native missing-FX-zero golden migrated to emdash+hint, preserving subsequent rate assertions; fixture/package/lint/build GREEN4sec. Swift610 (4 contract,137 data,469 core), contracts15, both strict localization checks, SQLite7/3/11, Room6 schema/bootstrap assets and whitespace passed. Whole Overview native passed 79/79 in182.339sec. Actual recent/day editor integrations passed2/2 in9.943sec, retaining exact Room/outbox assertions. App111 installed with adb install -r preserving data; cold MainActivity Status:ok1116ms, version111/min26/target36 confirmed. All three executed/installed base.apk checksums match archives below.

## Independent review and final artifacts

Fresh independent read-only review by `review_overview_monthly109` against immutable patch SHA256 `700fa1196cdf2a4896fd66df1af24efcbb2d0535fe6569b118d17e5faaf80bcc`. No Critical, Important or new Minor findings; ready subject remaining parent checks. No production fix pass or rereview needed. Reviewer independently inspected three PNGs; parent refreshed and inspected all six from the final whole-suite package.

Declined rulings: upstream malformed wallet/ledger filtering remains mandatory next; invalid ownership/envelopes/deleted/inactive exclusions and moved-asset history intentional; absent/deleted accounting system-wallet primary fallback retained; zero/nonpositive quantity/negative numeric cost normalization explicit; unorderable candidate conservatively holds inventory. Same-ISO import and public reporting normalization remain consistent. Cross-domain flow loading/multi-entity atomicity, resource bounds, investment CRUD/rebuild/permissions/persisted correctness, all locales/TalkBack/Samsung and broader remaining goal are unverified or separate mandatory work. Parent corrects the review carry-forward of prior chart callout/axis overlap: it was already physically fixed/verified in110, not reopened here. Other category visuals/day Event badge/older actual-font audit remain open. Final executed APK identity is parent-owned verification.

## Scope still required

Global raw financial input filtering can drop malformed ledger/wallet amounts/dates or currency metadata before projections; this slice does not resolve or waive that audit. Recent legacy original currency, imported/classifier/global planning audits remain. Full family/event/investment CRUD/rebuild/RPC/permissions/visibility, receipts/editor atomicity, Overview budget/due/config/walletcards, category visual minors/day Event badge/older sheet actual-font audit, device background/process-kill/RC and final whole-branch review remain required.

All10 cloud-write flags false; Room6/SwiftDataV11/iOS751 unchanged. No production write, deploy or migration. API36 ARM64 Pixel5 emulator only; no Samsung or live Supabase verification. Main111 is installed and smoke-verified as above. No whole-goal completion claim.


## Final artifact identity and logs

Ignored archives: `android/build/outputs/apk2/2026-10-20/`, metadata/aapt badging and `mistia-overview-assets-exact-v111-SHA256SUMS.txt` plus installed hash record. Main manifest and20DEX entries, Overviewtest9DEX and transactiontest11DEX inspected. All10 generated BuildConfig write flags remain false. Final executed JUnit footers79/2 verified; ADB exit0 alone was not considered success.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-overview-assets-exact-v111.apk|d4f3d72ae7c501a7aef091c4d86a5970882ebabdf19f340ddf7b8337722be669|
|mistia-overview-assets-exact-test-v111.apk|091852699544a20aefd2e39f409233a0e99c537c16ec50249cfbc05a5336b55f|
|mistia-overview-assets-exact-transaction-test-v111.apk|344c904cdb88d86a8c819c84556b1628d4d975fb7e8a752b39b34d91cfb32518|

Logs `/tmp/mistia-overview-assets-exact-{model-red,model-green,native-red-build,native-red,native-green-build,native-green,host-final,final-fixture-build,swift,native-final,editor-final,cold-smoke}.log`. Initial8native result and final79 whole-run evidence are separate; all six final settled PNGs refreshed from the final whole-suite package and inspected. No Samsung/live-production claim.
