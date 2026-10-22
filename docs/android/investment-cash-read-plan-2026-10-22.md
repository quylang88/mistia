# Investment cash read implementation plan

Spec: investment-cash-read-design-2026-10-22.md. Baseline00f497a1, current feature branch. Inline runtime TDD and per-slice delivery; no implementation delegation or new checkout.

## Task1 — cash allocation and fund-usage primitives

Files: core/model/InvestmentCashAllocation.kt and tests; related source-derived goldens if useful.

- [x] Runtime RED for booked/unreconciled separation, signed totals, original/accounting currency separation, stable order, source scope, tombstones, unreadable cash and exact overflow/cancellation.
- [x] Implement exact immutable projection with no accounting/local unit mixing; preserve source ordinary/booked/unreconciled usage ordering and historical-vs-current affordability.
- [x] Test normal actual Swift examples, boundary values and invalid currency/dependency admission; keep mutation/RPC unexposed.

## Task2 — consistent financial reads and shared exact balances

Files: Contracts.kt, database repositories/DAO wrappers and model/feature read helpers plus JVM/Room tests.

- [x] Add unsupported four-entity read API and runtime RED, then one owner-scoped Room query; verify four-entity generations, cancellation and wrong-owner/body boundaries. Keep131 mutation readset3 unchanged.
- [x] Reuse/extract persisted profit and exact raw wallet cash reader/kernel with unchanged Overview delegates and meaningful equivalence tests. Never double count allocated investment cash in actual cash.
- [x] Share one four-entity presentation snapshot for linked-wallet controls and financial reads; retain131 consent and all failure/restoration/owner behavior.

## Task3 — actual native read components and delivery

Files: feature/investment cash summary/location/linked balance components, read lifecycle, existing screens/tests; app version/evidence/progress.

- [x] Actual missing summary/location/linked balance native RED before implementation, then real Room-backed readable/empty/unknown/error/retry/owner and exact money cases.
- [x] Adapt existing linked-wallet observation test seams as needed without weakening business assertions; maintain selector/only-default/move/cancel/restore/late callback behavior.
- [x] EN/VI/JA light/dark actual font130/narrow width, largest meaningful amounts, glyph and non-overlap bounds; inspect original captures. Avoid claims of completed fonts/root/insets/hit targets.
- [x] Appropriate full host/native regressions/Swift/contracts/l10n/SQLite/assets/contents/hash checks; direct source/diff review and reproduce/fix findings.
- [x] Version132 install-r/COLD/archive evidence, progress and separate local commit; continue reserved-cash usage protection and complete transaction/payment/trade/cash/private-image/RPC plus remaining APK1–4/RC requirements.

Task1 checkpoint:15/15 runtime RED1s against explicit unsupported operations, then allocation/usage/balance primitives plus existing link14 all GREEN1s. Known deleted damaged cash and valid noncash transferOut history exposed two further failures; a same-currency row amount disagreement expands that to3 business failures in31tests/1s. Shared exact projection now skips authoritative tombstones before field parsing, recognizes all five source noncash roles, and preserves131 per-row same-unit equality and Long mutation boundaries. Model allocation16/link15 + repository6 GREEN2s after sharing the booked reader. Wallet read currency with surrounding spaces could reach the formatter without canonical ISO code; new1/17 runtime RED1s, canonical DTO/read-consent comparison fix yields allocation16/link17/repo6 GREEN2s (verify exact final log). Raw stored fields remain untouched. Four-entity read/API, exact linked cash reader, native financial components and full132 delivery still required. Main/installed archives remain committed131; no132 APK or UI completion claim.

Four-entity read checkpoint: model subset1 + repo2 runtime RED from unsupported API (both tasks via --continue,5s), actual Room3/3 unsupported runtime RED. New single-query/read fences/scoped observation implement the contract; focused42 JVM tests (allocation16/link17/subset1/cashRepo2/linkRepo6) zero failures/errors/skips with build8s, actual Room3/3GREEN1.644s. New DB test APK installed only on API36transport14; main/Investment packages remain delivered131. All commands terminal. Native presenter still observes131 wallet3; next switch the presentation to shared cash4, preserve mutation3/CAS, then exact wallet/profit readers and real summary/location/linked balances. Full132 verification/version/artifacts/UI/evidence/commit still required; do not commit the partial slice.

Final completion evidence:1869JVM/182 suites, Swift611,11checks, scoped95emulator tests and36actual captures; source patch100e7e48311ad5b30e4acef936675d1d23f2c89c3c71166b315887ebbcfe2547. Version132 installed/archived six hashes, COLD1248ms observation. See final evidence; local per-slice commit follows. Full goal and final fresh whole-branch review remain open.
