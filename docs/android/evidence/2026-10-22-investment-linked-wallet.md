# Slice131 — native investment linked wallet and booked cash moves

Baseline3d9839cc on codex/android-apk2-4-parity. Design/plan: ../investment-linked-wallet-design-2026-10-22.md and ../investment-linked-wallet-plan-2026-10-22.md. This slice delivers choose/change-linked-wallet and both source choices in the actual Investment destination. Full wallet detail, cash/trade/private images/RPC and APK1–4/RC remain open.

## Behavior and direct Swift comparison

Compared configuration/setLinkedWallet/changeLinkedWallet in InvestmentPersistence690–868 and selector/choices in InvestmentHubView3255–3335,3460–3535,3647–3687, plus existing wallet/posting wire models. The canonical system wallet retains its existing investment_linked_wallet_id field; no separate table or schema. Only owned live unarchived ordinary non-credit wallets in the canonical accounting currency are eligible targets. Stable visible system/target/amount consent, event identity, exact Long version, explicit nulls, creation metadata and unknown fields survive the mutation. Synchronization ACK metadata can advance without invalidating visible consent; a changed link/target/confirmed cash cannot be overwritten.

Changing only default mutates one canonical wallet/outbox row. Change-and-move also creates the deterministic linked-wallet-move investmentReconciliation internal ledger transfer and old-linked-cash-posting/new-linked-cash-posting, role cashTransfer, bucket booked, origin manual, null trade/asset IDs, exact opposite local/accounting amounts. Amount is max(old linked booked cash,0); known unreconciled/tombstoned cash stays untouched. BigInteger accumulation rejects an out-of-Long result, never rounds or relabels currencies. Ordinary opening balances and existing postings are preserved. Complete replay returns no additional movement; unrelated/partial/archived/damaged provenance, invalid versions/dates and mixed occurrence dates are refused.

One owner-scoped wallet/ledger/posting read feeds planning; Room re-plans inside its conditional transaction, guards orphan outbox identities and checks active owner before/after. Last-posting failure rolls back canonical wallet, ledger, earlier posting and all queues. Repository retries bounded snapshot races while preserving visible consent and propagating cancellation. Canonical wallet and investmentReconciliation role remain reserved by existing ordinary-domain guards. All11 flags remain false. These repository/Room tests use local stores; no live Supabase verification or production write/deploy/migration is claimed.

## Native flow and read states

The actual destination includes source-copy linked-wallet selector with original wallet artwork. Previous different links show only-default/change-and-transfer-all/Cancel; first selection saves directly. Target/system/amount/event are saveable, failed reads disable money actions while retaining confirmation, retry reloads the same draft, failed saves/restoration retain the event, source changes retain the historical visible amount and disable stale money confirmation. Owner/repository keys and coroutine activity checks fence late results. Busy state disables duplicate actions/cancellation.

The shared strict read projection never advertises movable cash from a missing/deleted/credit/incompatible previous wallet. A valid replacement can still be selected without moving uncertain money. Components are checked at actual system font1.3/320dp in EN/VI/JA light/dark; all18 final card/picker/choice PNGs in images/2026-10-22-investment-linked-wallet were inspected. Card/picker12 are byte-identical to inspected originals; final six corrected choice captures were inspected separately. No complete font identity/root inset/physical hit-target/full wallet-detail parity claim.

## Runtime RED→GREEN

- Model8/8 runtime RED1s against unsupported planner, then8GREEN1s; collision/owner/damage/ACK cases yield11GREEN. Two read-source regressions fail1s (missing/incompatible old wallet advertised movable cash) before strict view admission;13 plus repo6 GREEN2s. Replay provenance regression1/14 RED2s before validating versions/dates/archive/occurrence coherence; final focused14+repo6 GREEN5s with native package.
- Repository6/6 runtime RED2s against unsupported API, then6GREEN. A mistaken nested BudgetMemoryStore qualification and missing façade DTO import were compiler diagnostics corrected before runtime claims.
- Actual Room6/6 runtime RED from unsupported reads/commit, then6/6GREEN0.291s. Tests cover exact9007199254740993 and owned queues, four-row financial batch, unchanged opening balances, last destination-posting trigger rollback, owner cancellation, cash-at-CAS and16 consistent three-entity generations.
- Initial native5 executed27.473s:4 absent-entry business failures and1 fixture failure from seeding different owners in one batch. Per-owner seeding fixes that fixture; eligibility alone1/1 business RED6.722s at absent choose entry. First working complete5/5GREEN12.686s. Extended read retry, failed-save/restoration, frozen cash/target changes and late noncancellable old-owner callback cases make9/9GREEN25.502s.
- First visual test1/1GREEN11.546s checked glyph/layout text completeness, but image review exposed Cancel overlapping the move action. Added inter-button geometry reproduces1/1 RED3.698s. All three actions now share one vertical action column; complete visual test including no-overlap assertions1/1GREEN11.637s. No relaxed glyph, currency, snapshot or queue assertions.
- Native theme argument/resource-class reference/compiler corrections are harness diagnostics, not business RED. Final host/native regression results follow after terminal outputs.

## Verification and boundaries

First full host BUILD SUCCESSFUL84s before the replay/action fixes. Fresh Swift611=4+137+470 passes; contracts15, Android localization generation check, strict Swift localization generation check, SQLite outbox7/notification3/deletion11, Room6 schema assets, finance196 tokens/111 artworks, unit-fold1553 mappings and4 freshness tests pass. No hosted CI execution claim. Final full host BUILD SUCCESSFUL64s,1837JVM/177suites zero failures/errors/skips; model/Room/required feature native compiles/packages, app lint/debug all pass. Final native regressions are terminal and GREEN; see exact results below.

Room6/SwiftDataV11/iOS751 unchanged, all11 cloud flagsfalse. API36 ARM64 emulator transport14 only; no Samsung/live Supabase/production write/deploy/migration. Direct scoped root source/diff review and reproduced corrections only; no independent131 or whole-branch approval claim. Final whole-branch review remains an overall-goal gate. Continue cash allocation/funding previews and actual cash/trade/private-image/RPC flows plus the remaining domains after this slice's separate local commit.

## Final installed artifacts

Main131/minSDK26/targetSDK36 installed with install-r preserving data; COLD Statusok6961ms, an observation under local emulator load rather than performance acceptance. Main20/model4/DB5/Investment9/Overview9/Planning10DEX. All six installed package SHA256 values match the ignored local archives under android/build/outputs/apk2/2026-10-22/. Final Android source/test/version patch SHA25680b5dd77ef639f6c3e83ead175959a6f2ad4bd7ef83c5bffc9e6fdc0a5f1628a.

- main: `mistia-0.2.0-apk2-investment-linked-wallet-v131.apk`, 35946781bytes; SHA256 `9faea1d405c8c71129a740150b2ce17a779303c84af28a2828e0240cf763add1`.
- model: `mistia-investment-linked-wallet-model-test-v131.apk`, 3229695bytes; SHA256 `efded4317777c697929af617a29b3c81caba8e09ee95532073b7a8433ce7dc74`.
- database: `mistia-investment-linked-wallet-database-test-v131.apk`, 5602812bytes; SHA256 `7f0396b5716a4b82db136a31ad2586bb40aee0b358d69ca966937bb7e41e1967`.
- investment: `mistia-investment-linked-wallet-investment-test-v131.apk`, 23640391bytes; SHA256 `89824229c2847d5af1c5a13c828410f51db32b26f2acf95fb523c42ab3628249`.
- overview: `mistia-investment-linked-wallet-overview-test-v131.apk`, 25101628bytes; SHA256 `35e1650742912cd08d5f6abd1a91267ba21fa0aa9ff51b3e62b35fec19c9c6b7`.
- planning: `mistia-investment-linked-wallet-planning-test-v131.apk`, 25038560bytes; SHA256 `76efadd2fd2eaf9a37874bc776f6d83265b309ca3e7f47da5895eca870385bdc`.

## Exact final native verification

All installed suites are terminal: Room Asset8+Channel6+LinkedWallet6=20/20GREEN6.309s, shared model16 + Swift golden corpus=17/17GREEN1.439s, complete Asset13+Channel10+LinkedWallet10=33/33GREEN615.771s, OverviewInvestmentCard8/8GREEN65.692s and OverviewDuePaymentRoute8/8GREEN166.134s:86/86 in total. No full Overview/Planning/Management native suite rerun claim. All18 final linked-wallet images from the full33 run are byte-identical to the inspected final originals. Post-run font1.0/no wm override and all six installed/archive hashes were checked again. API36ARM64transport14 only; no Samsung/live Supabase/production write/deploy/migration.

Direct final scoped review checked three-entity observation/read/conditional transaction, before/after owner fences, source/target/amount consent, Long/null/unknown/frozen metadata, booked/unreconciled/deletion admission, deterministic event/replay provenance and collision refusal, source-copy/eligibility/native saved state/retry/duplicate/late-owner handling, current reserved cloud boundaries and corrected action geometry. Root reproduced/fixed the read/replay/layout findings before final checks. No independent131 or whole-branch approval is claimed; the complete APK1–4/RC gate remains open.

Separate local commit after final whitespace validation, then continue exact cash allocation and actual wallet/cash-location balances, reserved-cash usage consent/protection, buy/sell/cash/private images/RPC and remaining domains. No overall completion claim.
