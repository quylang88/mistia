# Slice134 implementation plan

Spec: investment-cash-history-design-2026-10-22.md; baselinee3316c5a, inline execution in current branch.

1. [x] Runtime history RED then exact pure/raw history GREEN. Cover every kind/filter/precedence, shared event dedup, dates/ties/limit, huge/min amounts, FIFO pack/box/Unicode funding source, deleted/foreign/malformed rows and original gross currency. Reuse133 owned four-entity read; no duplicate inconsistent money stream.
2. [x] Runtime lifecycle planner/repo/Room RED then GREEN. Exclude event for capacity, lock direction, preserve metadata/versions, edit/delete exactly owned pair/all event postings, dependency limits, semantic ACK/replay, tamper/partial/source change/orphan queue, rollback and owner replacement at each boundary.
3. [x] Actual native history/edit/delete RED then GREEN: preview/see all/filter/pagination, original values on reopen, real save/delete confirmation/cancel and changed capacities, errors/retries/draft restore/lost responses/duplicates/owner/DI replacement. Real persisted rows/queues/actual+allocated balances asserted, no synthetic callbacks replacing routes.
4. [x] Full EN/VI/JA lightdark actualfont130/320dp money/glyph/bounds/hit target visual QA and original captures. Direct Swift/diff review and all corrections via meaningful runtime regressions. Full appropriate JVM/Room/native/lint/build/Swift/contracts/l10n checks; version134 archive/install-r/COLD/hashes, evidence/progress and separate complete slice commit. Continue full goal afterward.
