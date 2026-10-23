# Resale sale implementation plan — slice144

Goal: complete actual native sale and zero-revenue liquidation over unit-aware FIFO with exact money and atomic Room/outbox.
Spec: investment-sale-design-2026-10-23.md. Execute inline TDD under user TXT; no permission pause/per-task agents. Current skill catalog has no Superpowers requirement. Existing codex branch retained; all11cloudflagsfalse/Room6/SwiftDataV11/noSamsung/prod/write/deploy/migration/push.

### Task 1: Exact shared trade creation and typed sale planning
- [x] Add typed sale request/unsupported entry and meaningful tests; observe runtimeRED before implementing.
- [x] Factor private real BUY/SELL creation core, retaining purchase APIs/admission. Exact capital-return/profit/cashAccrual, free-cost stock, liquidation, unit-aware fractional FIFO/oversell/backdated/rates/Long/ACK/partial proof and fund-history consent.
- [x] Full model/purchase/ordinary fund regressions GREEN; direct Swift review.

### Task 2: Actual atomic repository and native sale form
- [x] Runtime RED actual Room→typed repository/consistent read/recompute/whole-history/global publication proof/orphan/CAS/caller/owner/trigger rollback/known result.
- [x] Runtime RED actual Sell route→asset/wallet selection, exact quantity/unit/available stock/total amount/rates/date/note/loss mode, warnings, ephemeral review/saveable intent, stale balance/stock/owner/repository/process restoration/lost-response explicit retry.
- [x] Actual stored sale/stock/profit/cash effects visible. EN/VI/JA light/dark large-font320dp layout evidence; purchase remains working.

### Task 3: Verify, review and commit complete144
- [x] Appropriate focused/full JVM, native Room/Investment scopes, app lint/build/testAPKs, Swift/contracts/bothstrictl10n/guards/assets/icons/fold/whitespace and direct scoped diff review.
- [x] Version143 artifacts inspect/archive/hash/install-r/installed checksum/cold start. Evidence/progress/handoff/source patch; separate local144commit immediately, then trade lifecycle/privateimages/atomicRPC and fullremaininggoal.

Final evidence: evidence/2026-10-23-investment-sale.md. All3tasks complete; fullgoal remains active.
