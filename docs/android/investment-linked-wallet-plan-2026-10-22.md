# Investment linked-wallet implementation plan

Spec: investment-linked-wallet-design-2026-10-22.md. Baseline3d9839cc; inline execution with runtime TDD and the user's autonomous per-slice workflow. No new worktree or agent; current feature branch is isolated and clean after130.

## Task1 — strict cash read and mutation planner

Files: core/model/InvestmentLinkedWallet.kt and matching tests. Interfaces: InvestmentWalletSnapshot(owner,rows), InvestmentWalletLinkRequest(expectedSystem,expectedTarget,eventId,moveAllBookedCash,expectedBookedMinor,ledgerTitle), InvestmentWalletLinkPlan(linkedWalletId,mutations), planInvestmentWalletLink(snapshot,request,deviceId,now).

- [x] Runtime RED for choose-first/only-default/move-booked, exact wire/unknown metadata/Long versions and unchanged ordinary wallets.
- [x] RED for archived/credit/investment/foreign/mismatched/unreadable wallets, stale visible link/target/amount, malformed cash/overflow and event collision/replay.
- [x] Implement minimum strict model; verify expected positive/negative booked legs, skip known unreconciled/tombstoned cash and preserve metadata; direct compare Swift.

## Task2 — repository and atomic Room

Files: Contracts.kt, InvestmentLinkedWalletRepository.kt, Repositories.kt, MistiaDatabase.kt and JVM/real Room tests. Repository observeWalletSnapshot/changeLinkedWallet; store observe/read/conditional commit of three entities.

- [x] Unsupported repository/store runtime RED, then bounded CAS retries with account/cancellation/source-consent fences.
- [x] Real Room complete four-row batch/outbox, exact versions, no opening balance changes, stale cash/link/target races, late posting trigger rollback and owner replacement.
- [x] Confirm existing reserved wallet/ledger gates cover the resulting rows and all flags remain false.

## Task3 — native selector/choices and delivery

Files: feature/investment linked-wallet state/sheet/section and InvestmentScreen.kt, native tests, app version/evidence/progress.

- [x] Absent-flow native RED before wiring actual selection, change-only and change+move actions with source labels/icons.
- [x] Verify actual Room effects, eligible options, duplicate/retry/source change/restoration/late-owner cases and all cancellation choices.
- [x] EN/VI/JA light/dark/font130/320dp glyph/bounds assertions and visually inspect originals; no root/font/hit-target completion claim.
- [x] Focused model/repository/Room/native plus channel/asset/Overview/payment regressions, complete appropriate host/lint/packages/Swift/contracts/l10n/SQLite/assets checks.
- [x] Review source/diff, reproduce and fix findings, rerun affected checks; keep incomplete domains explicit.
- [x] Version131 install-r/COLD/contents/checksums, evidence/progress and separate local commit; continue remaining APK1–4/RC.

Initial eight model tests runtime RED8/8 in1s against the explicit unsupported planner, then8/8GREEN1s. First implementation compile required parentheses around a conditional wallet-ID comparison; this compiler diagnostic is not counted as a business RED. More admission/collision/ACK cases and repository/Room/native delivery remain in progress.

Current progress: model11/11GREEN1s, including partial/colliding event refusal, owner/raw damage and ACK-only Long versions. Focused model11 + repository6 GREEN7s (including Room package), then9s after store implementation. Repository6/6 runtime RED2s against unsupported API before implementation; a test fixture first referenced top-level BudgetMemoryStore as nested and the façade first missed an explicit DTO import, corrected compiler diagnostics only. Real Room6/6 runtime RED on unsupported read/commit, then6/6GREEN0.291s after three-entity snapshot/conditional transaction. Case coverage: first link/version9007199254740993/owned outbox, four-row movement without opening-balance writes, last posting trigger rollback, owner replacement cancellation, cash-at-CAS stale confirmation, and16 three-entity generations. New DB test APK installed only on API36ARM64transport14; main remains delivered130. At the backend checkpoint all processes were terminal. A subsequent native linked-wallet5-case class has been added, compiled and installed; its initial absent-flow RED runner is now active in /tmp/mistia131-linked-wallet-native-red.log. Native UI Task3 and full131 checks/delivery remain open; do not commit this partial slice yet.

Initial native class:4/5 absent-entry business RED,1/5 fixture failure because different owners were seeded in one batch. Fix the fixture to seed each owner in its own transaction and rerun before claiming all five business RED. Current next action is Task3 native read projection/selector/choices implementation, then the same five tests GREEN and expanded lifecycle/visual coverage. Main still130; installed Room/Investment test packages are131 development builds. No active tool handle remains at this checkpoint.

Eligibility fixture corrected and rerun alone on the rebuilt installed APK:1/1 business RED6.722s at the absent choose() entry (/tmp/mistia131-linked-wallet-eligibility-red.log). Together with the initial four missing-entry failures this establishes runtime RED for all five planned native behaviors; do not describe the first complete class as five business failures. All tool handles are terminal. Next implement Task3 projection/read lifecycle + native selector/choices, then run the entire five-case class GREEN and add failure/restoration/late-owner/visual coverage before complete131 checks/commit.

Native implementation checkpoint: initial five actual flows GREEN12.686s, extended nine GREEN25.502s. Shared wallet decoder/booked cash projection and lifecycle states preserve frozen/saveable source/target/amount/event, retry/owner/late-result guards and busy action exclusion. Read projection two-test RED1s fixes invalid/missing previous wallet advertising movable cash; model13 + repo6 GREEN2s. Replay-provenance regression1/14RED2s before strict event metadata/date/archive/coherence validation, then14+repo6 GREEN5s. Initial actual320dp/font130 visual1GREEN11.546s caught complete text but missed button overlap; image review found it, new inter-button bounds assertion1RED3.698s, one vertical action column fixes it and visual1GREEN11.637s. All18 final originals inspected (final12 unchanged card/picker, six corrected choices). First full host84s and final64s pass; final JVM1837/177suites zero failures/errors/skips, Swift611 and all standard scripts pass. Source/test/version patch80b5dd77ef639f6c3e83ead175959a6f2ad4bd7ef83c5bffc9e6fdc0a5f1628a. Final install-r/COLD/hash and sequential native20/17/33/8/8 regression orchestration running; read its terminal results before updating delivery/commit. No complete whole-branch/independent131 review claim.

Final delivery checks terminal: Room20/17model/33Investment/8Overview/8Planning all GREEN (86 total), full1837JVM/177suites, Swift611 and standard scripts. Final18 captures match inspected originals; six hashes/font1.0/no wm override verified after native completion. All tools terminal. Commit this complete vertical slice, then continue132 exact cash allocation/read balances and subsequent usage protection/trade/cash/private-image/RPC work; whole APK1–4/RC remains open.
