# Resale purchase implementation plan — slice143

> Use superpowers:executing-plans inline with test-driven-development; user TXT authorizes complete-slice local commits and autonomous implementation. Spec: investment-purchase-design-2026-10-23.md.

Goal: actual Investment new purchase → exact trade/FIFO/funding/fund effects → atomic owner Room/outbox → visible resulting activity/stock. Complete form and repository in one slice.
Tech: Kotlin/Compose/Room/BigDecimal; existing Swift rules and shared localization.
Constraints: all11cloud flagsfalse; Room6/SwiftDataV11; no prod/deploy/migration/push/Samsung claim.
Review focus: zero-cost stock without wallet; backdated buys changing later sell FIFO/profit; stale fund consent after hidden balance changes; complete no-write retry after lost response; card funding and foreign accounting/funding rates; raw/ACK/collision/owner/caller/outbox rollback; recreation/repository replacement without replay.

### Task 1: Exact purchase planning and canonical fund replay

Files: core/model InvestmentPurchase.kt + tests; InvestmentAssetRebuild.kt minimal fresh-zero behavior; InvestmentFundUsagePlan.kt shared private effect builder; InvestmentFundUsageTimeline.kt validated funding event replay.
Interfaces: InvestmentPurchaseSnapshot (complete transaction+investment+asset/channel raw readset); InvestmentPurchaseDraft (stable id/createdAt, asset, unit, quantity, total source/accounting amounts/rates, wallet, note/occurredAt); request expected visible asset/wallet/system and optional exact fund consent; plan result trade + complete mutations.
- [x] Write meaningful first purchase tests; unsupported entry point runtime RED before implementation.
- [x] Paid/free purchase, LongMAX, decimal quantities/units, FX metadata and scales, invalid quantities/rates, wallet/currency/card limits, source/owner validation.
- [x] Canonical baseline proof, backdated unit-aware rebuild, global derived fund preview/consent; prior immutable history/raw preserved. Exact known-result returns no mutations; partial/colliding/manual/orphan results hold.
- [x] Full model focused GREEN and existing ordinary fund/FIFO regressions.

### Task 2: Atomic repository and actual native form

Files: core Contracts.kt, database purchase repository/RoomLocalStore, InvestmentScreen + new purchase sheet; app ExchangeRateRepository wiring; actual Room/Compose tests.
- [x] Runtime RED actual repository → implement consistent snapshot/transactional recompute/orphan outbox/owner and caller fences; prove late trigger rollback and no half-state observer, retry/cancel/race/foreign owner behavior.
- [x] Runtime RED actual form → select asset/wallet, quantity/unit, total amount, promotional zero, occurred date/note/rate summary; fund use/change dialogs; stable saveable identity but ephemeral consent, source revalidation, stale response/repository replacement and explicit no-write retry; actual result shown in Investment.
- [x] Direct Swift/diff parity and EN/VI/JA light/dark large-font narrow-screen layout verification. Use shared existing catalog copy and money formatting.

### Task 3: Verify and commit complete143

- [x] Full JVM, Room native compile/test packages, app lint/build, Swift/contracts/bothstrictl10n/guards/schema assets/icons/fold/whitespace.
- [x] Full Room and relevant Investment native regressions; one final direct scoped diff/Swift review (current available skill catalog removed Superpowers before final review), observed TDD corrections, no repeated external review.
- [x] Version142 APK inspect/archive/hash/install-r/installed checksum/cold start; source patch/evidence/progress/handoff. Commit143 separately then immediately actual sale/FIFO/lifecycle and remaining full scope.
