# Slice133 — native investment cash deposit and withdrawal (2026-10-22)

Baseline `4c8109de`, branch `codex/android-apk2-4-parity`. Implements actual creation of deposits/refills and withdrawals, including the linked-wallet-first route. History editing/deletion/reconciliation, ordinary-outflow reserved-fund protection, trades/private images/atomic RPC and the rest of APK1–4/RC remain open. This slice does not complete an APK gate.

## Behavior and source review

- Deposit maximum = min(nonnegative realized-profit shortfall, nonnegative source actual minus nonnegative source allocated cash). Withdrawal maximum = positive booked linked cash, matching Swift without adding an actual/ordinary-cash withdrawal cap. Exact read values use BigInteger; one wire transfer caps at Long.MAX_VALUE.
- Eligible selected/linked/system wallets are owned, live, unarchived and use the same normalized ISO currency. Selected wallets exclude credit-card/investment kinds. JPY/VND/USD minor units remain exact, including USD4.75→475. Same-wallet deposits/withdrawals reclassify allocated cash with actual balance unchanged; other-wallet transfers move actual amounts once.
- Save creates exactly one posted internal-transfer ledger row plus one deterministic signed manual booked cash-transfer posting, with two matching outbox entries. No wallet opening/trade mutation. Explicit null references, report/source/destination amounts, note whitespace and exact versions are preserved.
- One owner-scoped four-entity presentation read serves the summary, linked controls and form. The mutation planner validates raw source membership and frozen visible wallet/capacity consent; Room compares the entire four-entity snapshot inside one transaction, protects orphan pending IDs and checks the active owner before/after writes. Three repository attempts never silently accept changed visible consent. A matching complete event replay returns without another write even when the first successful transfer exhausted capacity; partial/tampered/reused events fail.
- Native controls include exact amount/max/limit, eligible-wallet selection, same-wallet explanation, actual date/time pickers and optional note. Save/cancel/title stay pinned while the body scrolls, matching the Swift modal scaffold. Read/save errors and retries retain immutable event identity and reviewed values. Changed currency cannot relabel old input. Saved state and same-owner repository rebinding retain the draft; owner replacement cancels old operations and clears private UI.
- A linked preference committed before a lost success receipt can be retried through the original frozen request; strict planner replay remains authoritative. The root resumes cash creation only after the actual linked-picker save, and cancel writes no cash rows.

Direct author review used `InvestmentLogic.swift:541–582`, `InvestmentModels.swift:680–741`, `InvestmentPersistence.swift:1927–2008,2126–2225,3792–3890,4070–4175`, `InvestmentHubView.swift:3416–3460,4149–4389` and `MistiaModalScaffold.swift`. Default wallet, limits, signed roles, dates, note trimming and toolbar placement were compared directly. Source snapshot (19 Kotlin/build files, including tests) `/tmp/mistia133-source.patch`, SHA256 `1ed5928177d5ff1f74d4968aa14dff14b138745e519dbde2187c0b7e004c74ab`. Author scoped review only; no completed independent whole-branch review claim.

## Runtime TDD and corrections

| Evidence | Actual result |
| --- | --- |
| Scalar preview | 7 unsupported runtime RED → 7+19 prior allocation GREEN1s. |
| Raw planner | 8 unsupported runtime RED → 15 focused GREEN1s; expanded invalid/overlimit input RED recorded. |
| Same-event noncanonical posting | New regression1/10 runtime RED1s → explicit event-reuse rejection, model706/73suites GREEN1s. |
| Repository / real Room | New repository5 unsupported runtime RED6s and Room8 unsupported runtime RED → repository13 GREEN6s, actual Room8 GREEN0.219s. |
| Foundation Unicode note trimming | New regression1/11 runtime RED1s → existing exact whitespace set reused; model707+repo13 GREEN2s. |
| Shared form read | 4/15 unsupported runtime RED1s → exact shared capacity kernel, full model711/73suites+repo13 GREEN3s. |
| Actual native flow | Initial5 missing-action runtime RED32.831s → real controls/form/link-first; initial6 run5pass/1failure, recorded below. |
| Lost linked-success receipt | Actual native1 RED3.057s → visible same-target acknowledgment with strict underlying replay. |
| Pinned modal controls | First weak visibility fixture passed; strengthened30line note plus actual post-expansion scroll RED3.52s → pinned header, full7 GREEN26.691s. |
| Recovery/owner/rebinding | Seven added cases5pass/2fail28.9s: actual same-owner repo recreation lost draft; separate test fixture mixed-owner seed rejected correctly. Root keyed by owner, operation scopes by repo; seeds partitioned by owner. Full cash13 GREEN50.506s. |
| Paired paths/currency/real pickers | Other deposit, same withdrawal and changed-currency hold passed. Calendar/clock selector failures were fixture mismatches (full date Text, hour/minute ContentDescription), not product mutation fixes. Real day20+changed hour/minute and equal stored ledger/posting instant then GREEN38.588s. |
| Actual font/narrow visual case | Passed in combined2 run192.743s; other case's numeric clock selector failed and was corrected from its actual semantics. 36 captures, no financial writes. |

Runtime logs: `/tmp/mistia133-cash-{preview-red,preview-green,plan-red,plan-expanded-red,plan-green,event-reuse-red,model-suite-green,repository-red,room-red,room-green,note-red,note-green,form-read-red,form-read-green,native-red,recovery-red,recovery-green,complete-paths-native}.log`; linked/header/picker diagnostics `/tmp/mistia133-{link-lost-receipt-red,cash-pinned-header-expanded-red,cash-date-bounds,picker-visual,clock-final}.log`.

Historical failures retained: a test-only pending-owner field typo, explicit repository import and missing darkTheme fixture argument were corrected before treating runtime RED as meaningful. Initial native6 had a same-wallet date/note Save await timeout; identical isolated case passed7.487s. A subsequent7 run had a date-button await timeout; bounded click geometry/tree diagnostics retained, no guessed data/business fix or retapping. Later full acceptance below passed without weakening storage, queue or owner assertions. Saved-state/DI tests are feature restoration evidence, not full-app process-kill acceptance.

## Final verification

Full host `/tmp/mistia133-full-host.log`: BUILD SUCCESSFUL1m40s; **1896 JVM tests /185suites, zero failures/errors/skips**. Includes required full unit tasks, core model/Room native APKs, affected feature native compiles/builds, app lint and main APK. Unchanged tasks may be Gradle UP-TO-DATE; focused model711 and repository13 runtime greens are above. The final clock test selector changed afterward, then the test APK rebuilt successfully1s; product source unchanged.

Full Swift `swift test`: **611=4+137+470, zero failures** (`/tmp/mistia133-swift.log`); ignore the separate Swift Testing 0-test summaries. Eleven checks passed: contract15, Android l10n freshness, strict Swift l10n freshness, outbox7, notification3, installment11, Room test assets6schemas, finance icons196tokens/111source artworks, unit-fold1553, fold freshness4tests, and `git diff --check`. Logs `/tmp/mistia133-check-*.log`.

Actual API36 ARM64 emulator scoped final acceptance: **122 tests**, zero failures:

- investment: 58 tests, 260.452s.
- database: 31 tests, 0.98s.
- model: 17 tests, 0.211s.
- overview: 8 tests, 22.628s.
- planning: 8 tests, 42.228s.

Investment runs all channel10/asset13/linked17/cash18 tests. Room covers asset8/channel6/linked6/cash-read3/cash-transfer8. Model covers accounting17; Overview8 is investment-card only, Planning8 due-route only. No full Overview/Planning/Management native suite claim. Logs `/tmp/mistia133-final-*-native.log`, runner `/tmp/mistia133-native-all.py`.

Visual proof: [36 PNG captures and SHA manifest](images/2026-10-22-investment-cash-transfer/manifest.json), actual system font1.3 and width320dp, EN/VI/JA × light/dark. Deposit/withdraw top+bottom plus calendar/clock captures inspected in6contact sheets and original VI amount/withdrawal, EN clock and JA calendar. Editable19digit amounts and full exact limits fit, glyph/layout/overflow/header/nonoverlap checks pass. Final system font1.0 and wm override cleared. Original files are native captures; contact sheets only assist review.

## Update artifact evidence

Six APKs archived under ignored `android/build/outputs/apk2/2026-10-22/`, installed with `adb install -r`; each installed APK SHA matched its archive. Main `mistia-0.2.0-apk2-investment-cash-transfer-v133.apk`, versionCode133/versionName0.2.0-apk2-debug, min26/target36. COLD Statusok **6693ms**, a single emulator observation under local load, not performance acceptance. Metadata `/tmp/mistia133-installed.json` and `/tmp/mistia133-artifacts-install.log`.

| APK | Bytes | DEX | SHA256 |
| --- | ---: | ---: | --- |
| main | 35461836 | 20 | `f651c005a1be6d029a819414fafbd7b77ecc151f62fd96e0fe895812a09d8a68` |
| model | 3261391 | 4 | `dfdc46fa26c89689093de1b4aa9f7f546fd8bedc0605851f1d81642745782b1b` |
| database | 5426289 | 5 | `c11823eced943bdad43fa56b983766a5d27f5c538f2660722e00facccc879a5d` |
| investment | 23672087 | 9 | `8af7a1af27e9a00e56b1a89eb9eae1f511cf0363c7946933e301def1905f41c0` |
| overview | 25133324 | 9 | `8e15e3317aa97609dd04b86acdc88a32c11bc0f0a2e23d94942f8e1d3f725f04` |
| planning | 25070256 | 10 | `5e50db788571876141aca92309fa40fe58a8fd773b655682ff5cd6f028ba4510` |

All11 cloud-write flags remain false; Room6 and SwiftDataV11 unchanged, no iOS product source changes in133. Emulator transport15 only; Samsung not connected. No live Supabase/prod writes/deploy/migrations/push. User's budget branch and bill/installment currency decisions remain in force; installment same-currency correction on both platforms was delivered in62–64. Credit-card currency decision stays pending without blocking independent local work. Fresh final whole-branch review, Samsung/cloud-boundary E2E, broader UI/font/insets/hit-target and all remaining APK1–4/RC requirements remain open. Local slice commit followed by next coherent slice; overall goal stays active.
