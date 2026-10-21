# Slice129 — shared unit-aware FIFO accounting

Baseline9dfb8cc0; branch codex/android-apk2-4-parity. Design/plan: ../investment-fifo-design-2026-10-21.md and ../investment-fifo-plan-2026-10-21.md. This is the accounting prerequisite for asset/default-unit edits with history and buy/sell/postings, not complete APK4 or an exposed trade editor.

## Behavior and source review

Typed immutable trade input/projection uses UUID/Instant, Long accounting money and BigDecimal quantities. Sort by occurred, created, canonical UUID text (unsigned ordering, unlike Java UUID.compareTo); FIFO queues remain independent per normalized unit. Purchase amount is total order cost. Partial sales retain residual lot quantity/basis; full lot releases all remaining cost. Global remaining cost/quantity/open-lot count and positive unit balances accompany each calculation. Explicit invalid quantity/amount, oversell and arithmetic overflow stop the evaluation without returning partial projections; all working state belongs to the call. Exact checked Long sums; no Double wire/accounting.

Direct authority: Mistia/Shared/CoreLogic/InvestmentLogic.swift39–384 and existing InvestmentLogicTests. Unit labels collapse the exact Foundation whitespace set, retain first display label, use POSIX full case-fold keys and canonical equivalence. Pack/box remain distinct; missing/empty label retains legacy behavior. Real Foundation folding stops at NUL; generation/apply preserves this behavior. Pure unit positions have deterministic key ordering; future UI must apply source localized ordering, no complete UI-collation claim.

Generated1553 scalar mappings derive by executing the actual existing Swift InvestmentUnitLabel helper over Unicode scalars. Small Kotlin table works identically on JVM/Android; no new production ICU dependency. NFC comparison preserves Swift canonical String equality while display spelling remains unchanged. Generator check pins helper-snippet/generator/output SHA; four isolated temporary-root tests reject stale generator, helper and output while accepting original corpus. Android CI now runs freshness checks, actual Swift parity test and model native-test compilation, with relevant path triggers; local checks only, no hosted CI execution claim.

The real Swift engine supplies147 accounting vectors and32 Unicode/display/key vectors (including64 interleaved generated histories and48 high-precision histories). A single Kotlin assertion helper runs the same corpus on JVM and native Android. Swift test also evaluates the actual engine against the checked-in corpus, so Android cannot pass merely by updating expected outputs independently. All money in golden JSON is a decimal string to preserve Long values beyond2^53; this test format does not change production wire schemas.

## Decimal intermediate parity

An exact rational implementation failed one minor on the long-quantity many-digits vector. Real Foundation first fits multiplication to an unsigned128-bit significand, then uses its scaled/truncated division before final half-up minor rounding. Kotlin models these intermediate operations with BigInteger/BigDecimal rather than replacing them with an exact final ratio. The source model and on-machine Swift probes were reviewed alongside the goldens; maximum/minimum quantity, valid values above exponent127, parser significand truncation and unrepresentable ratio cases are included. The finite significand/exponent boundary is checked before expensive scaling.

Primary implementation reference: [Swift Foundation6.2 Decimal math](https://github.com/swiftlang/swift-foundation/blob/swift-6.2-RELEASE/Sources/FoundationEssentials/Decimal/Decimal%2BMath.swift). Unit-fold distinction from simple lowercase: [ICU case-fold documentation](https://unicode-org.github.io/icu/userguide/transforms/casemappings.html). Actual current Mistia Swift runtime outputs remain the acceptance authority. No iOS runtime changes; only a new Swift test/corpus.

## Runtime RED→GREEN and checks

- New accounting test16/16 runtime RED1s against unsupported operations; minimal FIFO implementation and generated fold →16GREEN, plus existing channel repository16GREEN in4s focused build.
- Initial89 goldens: one business RED (a-NUL-b key expected prefix a, actual ab). Prefix folding correction exposed the high-precision one-minor RED (922337203685477 vs922337203685478). Foundation-compatible decimal intermediates →17 tests GREEN; native initial17/17GREEN0.204s.
- Expanded143 goldens exposed zero-cost very-large-quantity overflow; diagnostic named the case, zero fit correction →17GREEN3s; native17/17GREEN0.157s.
- Expanded147 includes exponent-above127 and maximum-supported quantity: business RED1s→noncompact significand handling →17GREEN3s. Range/invalid-result handling remains explicit; no relaxed money assertions.
- Final native after all147 vectors initially17/17GREEN0.183s; subsequent bounded fitting change retains all17 JVM tests GREEN3s. Exact final native/full host verification recorded below.
- Unit-fold check1553mappings and its4 freshness tests GREEN; actual Swift golden check GREEN. Full Swift611=4+137+470 zero failures (new golden test increments prior610); contracts15/both localization generation checks/SQLite outbox7,notification3,deletion11/Room6 schema assets/original finance artwork196tokens111images/whitespace all GREEN.
- Full Android host BUILD SUCCESSFUL81s:1787JVM tests in173 suites, zero failures/errors/skips; new model native APK, Room compilation/package, required feature test compilation/packages, app lint/debug build. Final host after bounded fitting change follows below.

## Boundaries

All11 cloud flagsfalse, Room6/SwiftDataV11/iOS751 unchanged; no production write, liveSupabase, deploy or migration. API36 ARM64 emulator transport14 only, no Samsung. No financial mutation/UI integrated by this pure component yet, no existing persisted trade rewritten, and no claim that asset/default-unit editor, private images, ledger postings or atomic RPC are done. Direct root source/diff review only, no independent slice129 or wholebranch approval. Full APK1–4/RC goal stays active; next integrate asset/default-unit changes and rebuilding, then buy/sell/cash/private images/RPC and remaining domains.

## Exact final verification and artifacts

Final full host BUILD SUCCESSFUL63s,1787JVM/173suites zeroerrors/failures/skips; all required packages/compiles/lint/main. Complete final native model17/17GREEN0.171s covers16 business test methods and the shared147accounting/32unit vectors. Final Room channel class6/6GREEN0.281s and actual channel create1/1GREEN3.715s preserve the exact Foundation whitespace admission/two owned queues after sharing the helper. No full Overview/Planning/Management rerun claimed; this slice adds a pure component and unchanged-semantics whitespace extraction.

Direct root review checked typed input/error ordering, local working state, Long overflow, unsigned UUID order, independent queues, residual basis, real Swift intermediate decimal fit/normalization/division, canonical unit/display and generated/CI freshness. Final source/test/CI/version/golden/manifest patch SHA256027fa55becd7bed8d86cbd6073899a34186e6f42f6e83f62db65fae5a47ed56a. No isolated reviewer or wholebranch approval claimed.

Main129/minSDK26/target36 install-r preserving data, COLD Statusok1307ms. Main20/model4/DB5/Investment9DEX; all4 installed SHA256 values match ignored local archives under android/build/outputs/apk2/2026-10-21/. Systemfont1.0, API36ARM64transport14 only; all host/native commands terminal.


- main: `mistia-0.2.0-apk2-investment-fifo-v129.apk`, 35776214 bytes, SHA256 `bfe8a6d9490a5591525cac6e218520c05b25717fd2aecfbb5659d3938de71d67`.
- model: `mistia-investment-fifo-model-test-v129.apk`, 3190200 bytes, SHA256 `cdd4cb716fbf8285e47f63785df6022f56cd7d8516fb24bd51c51cd5fb2b3377`.
- database: `mistia-investment-fifo-database-test-v129.apk`, 4569801 bytes, SHA256 `4c20b6e96c0a0cea762099dcab7cfa3c866096c9d87e0c12e3177fcdfb992c41`.
- investment: `mistia-investment-fifo-channel-test-v129.apk`, 23600896 bytes, SHA256 `5e39514b4cbd9ab1c25c93bcbc305e530b36a2a451965707b61f4e7a13b10f65`.

Separate local commit then continue asset/default-unit management/rebuilding and remaining APK1–4/RC work; no overall completion claim.
