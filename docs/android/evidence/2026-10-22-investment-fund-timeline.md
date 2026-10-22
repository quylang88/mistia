# Slice135 — historical investment fund usage read foundation (2026-10-22)

Baseline56db56d8, branch codex/android-apk2-4-parity. Adds an exact owner-scoped historical replay/comparison boundary for later ordinary transaction/payment confirmation and atomic derived posting integration. This is a complete read foundation, not a delivered transaction/payment protection flow. No UI action or write route is connected in135; APK1–4/RC remains incomplete.

## Direct source and behavior

Compared InvestmentPersistence.swift487–551,2399–2516,2727–3151; InvestmentLogic.swift645–685; InvestmentModels.swift637–674; InvestmentPersistenceTests.swift1900–2115, and FamilyWalletSpendingTests. Replays base cash allocations and actual ledger cash in occurrence/creation/posting-priority/unsignedUUID order. Excludes old derived usage and investmentReserveUse adjustments; retains manual imported allocation transfers. Uses ordinary cash, then booked, then unreconciled; internal same-owner non-card transfers carry investment allocation while card payments/debt/family outflows consume it. Virtual unreconciled adjustments apply once. Date/income/source changes and removal recompute downstream usage. All changed wallets are retained, largest absolute change/stable UUID is the source primary presentation choice.

Exact BigInteger arithmetic handles Long.MIN income outflows, aggregate usage beyond Long and negative ledger balances. Original wallet-local and accounting currencies never silently relabel. Read holds explicitly when an allocation or reserved internal transfer would need an unsupported conversion; ordinary FX with no reserved consumption retains both exact legs. Historical timeline outcomes describe attribution only, not current spendability or permission to save; empty usages do not certify affordability. Snapshot rows/versions/unknown metadata/outbox never change. The next mutation slice must re-read and prove consent atomically rather than treating this read result as authorization.

Repository performs one existing owned atomic four-entity Room read for both comparisons, rejects declared-owner/body/duplicate/tombstone/replacement contradictions, propagates disk/cancellation errors and checks coroutine cancellation before/after reading and before return. Existing Room before/after owner fences are reused; no schema/version/gate changes. Strict consumed cash/identity/date/currency parsing prevents malformed money defaulting to zero. Retired/noncash/unused fields are skipped only where not consumed.

## Runtime TDD and corrections

Initial12 shared runtime tests:12 unsupported failures2s, `/tmp/mistia135-timeline-red.log`. Implementation9pass/3fail1s `/tmp/mistia135-timeline-green.log`: fixture tried ordinary WalletDraft to create a card (correctly refused by existing dedicated-flow guard); one expected a zero-use record though source only records positive use; another accidentally assigned the deleted income the same event identity as the manual cash allocation, so source replacement correctly excluded that allocation. Corrected fixtures to construct imported card payload, assert absence of zero-use expectation and use distinct owned event identity.12GREEN1s `/tmp/mistia135-timeline-fixture-green.log`; no product fix or disabled assertion for those fixture issues.

Repository5 initial4fail/1negative pass4s `/tmp/mistia135-repository-red.log`. Real Room3/3 runtime RED `/tmp/mistia135-room-red.log`. Implementation added one owned read plus cancellation boundaries; missing ensureActive import compile failure corrected before runtime. Repository5GREEN3s; Room3GREEN0.107s. Real Room tests prove exact30→10 use/20 restore, original high9007199254740993 version/unknown metadata/rows/all queues unchanged, same-ID foreign partition isolation, and actual active-owner change at the second read fence with no write.

Moved timeline vectors into sharedTest so the exact same assertions run on JVM and Android. Six additional source/negative tests found one real bug: explicit source_currency_code could disagree with the used wallet or be numeric.18 ran17pass/1failure1s `/tmp/mistia135-timeline-source-review-red.log`; strict used-source currency check fixed it. Full model and focused repositories/native packages GREEN2s `/tmp/mistia135-focused-green.log`.18 shared cases cover original Swift1019→76 use/943 restore/3323 remaining, expense/income deletion, transfer/card/self/debt/resale/family, unreconciled virtual balances, import versus derived, creation/priority/unsigned ties, exact extremes, all-wallet changes, FX hold and original FX legs, malformed owner/currency/identity/date/role/bucket/origin, drafts/archive/tombstones and retired records.

## Final scoped verification

Full host `/tmp/mistia135-full-host.log` BUILD SUCCESSFUL44s: **1944 JVM/190suites, zero failures/errors/skips**, required Room native compile, model/DB native APK assembly, lint and main debug assembly pass. Swift `swift test` `/tmp/mistia135-swift.log`: **611=4+137+470, zero failures**. Contracts15, Android l10n, strict Swift l10n, outbox7, notification3, installment11 guards, Room6 schema assets,196icon tokens/111 original artworks, fold4tests/1553 entries and git diff whitespace pass. An extra icon-generator fixture run initially failed2/9 because this shell lacked bundled sharp resolution; rerun with bundled NODE_PATH9/9GREEN and actual generated-source check passes. No icon source changes or dependency install. Log `/tmp/mistia135-icons-fixture-green.log`, `/tmp/mistia135-check-*.log`.

**76 actual emulator scoped native cases pass**: Room41 (prior investment38+new3), model35 (accounting17+same shared timeline18). Logs `/tmp/mistia135-final-{database,model}-native.log`; no UI/full-feature/native-global claim. No UI changes or new screenshots required in this read foundation. Existing134 UI evidence stays historical; ordinary fund confirmation/mutation/payment routes remain open.

Source snapshot7 files/44399bytes SHA256`f1d7497cdcc3587b06b32297831c97b4aed1b4df575b7d029c50ff3c37d153d0`, `/tmp/mistia135-source.patch`; author scoped Swift/diff review only. Fresh whole-branch independent review remains a final-goal gate.

## Update artifacts and remaining goal

Three APKs archived to ignored android/build/outputs/apk2/2026-10-22/, install-r preserving data, installed/archive SHA rechecked. Main version135/0.2.0-apk2-debug/min26/target36; COLD Statusok1098ms is a single emulator observation, not performance acceptance. Actual font1.0/no wm override restored; emulator transport15 API36ARM64 only.

| APK | Bytes | DEX | SHA256 |
| --- | ---: | ---: | --- |
| main | 35560140 | 20 | `0949e14a2ad81ea9ad501eafdb18bc783ed605b6813de1f4146ac742ad060ce2` |
| model | 3307365 | 4 | `f6a1bc32c8883345dd1944ddbd0c3c765de247a9053cb10f481b1d2641293d26` |
| database | 5510253 | 5 | `806bf8f5008ff50bf799531d5e79b321581ca2dfac5bfcdd0231fdc1262901aa` |

No Samsung, live Supabase, production write, deployment, migration or push. All11cloud flagsfalse/Room6/SwiftDataV11 unchanged; no iOS product edits135. User has now explicitly chosen **same-currency reconciliation only, on iOS and Android**; implement that next without reasking. Earlier card-currency question remains separate/unanswered. Budget branch/bill/installment choices remain, including both-platform installment corrections62–64. Complete next reconciliation flow, ordinary fund consent/atomic persistence/payment edits/restores, trades/private images/RPC and remaining family/receipt/background/settings/release gates. Do not mark goal complete from135.
