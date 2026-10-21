# Slice126 — consistent personal Overview financial reads

Baseline: `3cfd4e23`; branch `codex/android-apk2-4-parity`. Scope and acceptance: ../overview-financial-read-design-2026-10-21.md and ../overview-financial-read-plan-2026-10-21.md.

## Behavior and direct Swift comparison

Hero assets, monthly cashflow, weekly/category charts, category history and recent transactions now consume one owner-scoped raw six-entity Room SELECT (wallet, transaction, category, investment channel/asset/trade). The repository validates outer/body identity before emitting and retains tombstones/damaged fields for projections. Unsupported stores fail explicitly. No Room schema, financial mutation, outbox, wire payload, currency policy or cloud gate changes.

The lifecycle collector distinguishes loading, owned loaded and failed states, propagates cancellation, clears money before a new owner/repository/retry read, and rejects snapshots with the wrong owner. Unloaded/failed hero and chart money is unavailable, recent transactions do not claim loaded empty, and day actions are disabled. Retry resubscribes. Only a genuinely loaded empty readset yields zero/no recent transactions. Budget and upcoming dues keep their existing independent atomic readsets.

Compared directly with `Mistia/Features/Overview/OverviewView.swift` 608–685 (active channels/assets, latest per-asset persisted position, accounting wallet) and existing Overview report/recent logic. The inclusive raw source revealed previously omitted uncertain inventory archive/deletion/reference dependencies; current potentially active positions hold the total instead of inventing zero. Known excluded positions and no-trade positions remain neutral; closed positions do not require unused cost, and accounting currency does not parse wallet cash. Exact BigInteger reporting remains the established Android read-only policy, with Long mutation/wire contracts unchanged.

Independent review found an inclusive-input regression in recent transactions: permissive payload decoding could resurrect a row whose deletion field was an object/array, or supply currency from a wallet with uncertain deletion. Two new JVM tests reproduced it before the fix. Recent rows now require known deletion eligibility before sorting/limiting; explicit source currency stays independent of wallet fallback. An uncertainty hint accompanies known rows or replaces a false loaded-empty message. The reviewer confirmed this remediation statically.

## Runtime TDD and verification

- New repository tests: 2/2 runtime RED, unsupported snapshot / wrong-owner assertion, 14s; explicit producer then GREEN.
- New Room tests: 2/2 runtime RED at unsupported producer. Emulator was initially absent; same `mistia-api36-native` AVD reopened without wipe. Booting install and stale-package class lookup were harness diagnostics, not business RED. After implementation, atomic generation case passed; copied historical ID assertion was corrected from cycle ID to actual fixture ID. Final new + budget + due Room classes: **6/6 GREEN, 0.919s**. New case observes all six entities over 24 atomic batches; no mixed generation. Tombstone/damage/foreign scope and record/outbox immutability checked.
- Inventory tests: 15 executed, 2 RED (uncertain membership incorrectly zero; uncertain accounting-wallet deletion incorrectly primary fallback), 1s. After fix all 15 GREEN alongside repository tests.
- Actual full-screen withheld/error/retry/owner cases: **3/3 RED** (old known zero/old source); then **3/3 GREEN, 5.627s**. Initial test compile missing required theme parameter was corrected before runtime RED.
- Review regression: 7 recent JVM tests, 2 business RED, 12s (resurrected recent slot and wrong currency); fixed before final checks.
- First full host: **BUILD SUCCESSFUL, 115s**, 1741 JVM / 169 suites, zero failures/errors/skips; full required feature test compilation, Room test package, lint and main build. After review fix/extra native tests/version126, full JVM/Room/Overview package/lint/main: **BUILD SUCCESSFUL, 73s**. Final **1743 JVM / 169 suites**, zero failures/errors/skips, including snapshot2, inventory15 and recent7. The fixture-only host rerun passed in15s.
- Swift full test command terminal0: 610 tests across 4 app, 137 data/support and 469 core cases; zero failures. Contract 15 entities, Android localization check, strict Swift localization generation, SQLite outbox7/notification3/installment deletion11, six Room schema assets, and original icon freshness196/111 all terminal0. A log-print shell loop briefly shadowed zsh PATH; rerun via Python confirmed all already completed check logs. No check failure was hidden.

Full Overview first run: **155 executed, 154 passed / 1 fixture failure, 493.964s**. The owner key correctly resets chart mode; the fixture mistakenly asked for a category-only node after replacement. Corrected to verify unavailable money and absence of the private category row. Final product build full Overview: **158/158 GREEN, 728.222s**. This includes all six new financial read tests, the inclusive-deletion repair and explicit lifecycle cancellation/restart cases.

Visual inspection then found that the new test fixture omitted the app Scaffold: a dark card sat on a light default background with default text colors. Corrected only the fixture to use the actual Scaffold/padding. Product code unchanged. Final complete financial-read class **6/6 GREEN,15.013s** with the corrected Scaffold fixture. All six original EN/VI/JA light/dark font130 PNGs refreshed and visually inspected, with measured1.3font scale/full text/no ellipsis checks. Images: `images/2026-10-21-overview-financial-read/overview-financial-error-{en,vi,ja}-{light,dark}-font130.png`. The full158 package is archived separately; after that run only this test wrapper changed. No product theme or global inset fix is claimed. Final Planning crossfeature route class **8/8 GREEN,41.881s**, freshly assembled in1s. No unrelated Planning full-suite rerun or Samsung claim.

## Review and limits

Initial isolated product patch SHA256 `478afa8b08711a03c15216ce3ee2557a076f491243a6802ee13d4a7dc475a271`: one Important P2 recent deletion finding, no Critical. Remediated product patch `e6baea09ce94b1520cc8cbf6d09cbdfc5f188c43e41b1951056a429b3d59c9d1`: reviewer found P2 resolved and no remaining Important issue in remediation. Review was read-only/static; reviewer ran no Gradle/device/network commands. This is not whole-branch approval.

All ten cloud write gates remain false. No live Supabase, Samsung, production write, deployment or migration verification. Room6, SwiftDataV11 and iOS build751 remain unchanged. API36 ARM64 emulator transport14 provides local native evidence only. Investment card itself is the following slice; full APK1–4/RC goal, family/receipts/investment CRUD/remaining UI/settings/background/device/release work remain active.

## Final artifacts and installed verification

Main version126/minSDK26/target36, install-r preserving data, COLD launch Statusok **1206ms**. Final main/Overview/database/Planning installed APK SHA256 values each match their archived files. Archives live under ignored `android/build/outputs/apk2/2026-10-21/`; no binaries are committed.

- main: `mistia-0.2.0-apk2-overview-financial-read-v126.apk`, 35085004 bytes, 20 DEX, SHA256 `19f6dcc34956ff681d4600e8cafaf002730161abb0a8c2ac79309ddd398fe3ec`.
- overview: `mistia-overview-financial-read-test-v126.apk`, 24058344 bytes, 9 DEX, SHA256 `feebe8da9e5681f2f93834a2b401ace8db9ed6bf5a4c77c76b1b7a24f08809f7`.
- database: `mistia-overview-financial-read-database-test-v126.apk`, 4504927 bytes, 5 DEX, SHA256 `268b52658fb0a2422610e5710f822b20fca0383e590b1a734e47ea06d89c4eed`.
- overview-full-run: `mistia-overview-financial-read-full-run-test-v126.apk`, 24058344 bytes, 9 DEX, SHA256 `994f25def90bef6301794f260d1647d3c84f8ee24cf8ffc29d9a380ca62392a0`.
- planning: `mistia-overview-financial-read-planning-test-v126.apk`, 24438927 bytes, 10 DEX, SHA256 `2b6c74eacb5de5a3eab3d60746248a2181bf6f9dd3f4a0b19c2cc44ddbc2d352`.

All final commands completed; no live Gradle/instrumentation runner remains. APK full-run archive994f25de retains the158case run; final Overview feebe8da retains the corrected visual fixture/sixcase run. Main/source unchanged by that fixture correction. Branch and full APK1–4 goal remain active; continue actual Investment Overview card with this consistent source, then remaining APK4 inventory functionality and outstanding domains.

Final source/test/version patch SHA256 `ad78d1f8db6a36f97bcea8b8f8c871952f178379c22d8f69938c28222401a8e3`.
