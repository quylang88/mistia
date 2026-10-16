# Overview day details implementation plan — slice107

> For agentic workers: use superpowers:executing-plans inline, with actual runtime TDD and one fresh read-only review before this slice commit.

**Goal:** Long-press a positive daily bar to inspect all owned spending transactions on that local day, then open the existing stored transaction editor.
**Architecture:** Pure owned day projection supplies exact original row money and per-record converted total; real Overview derives it from validated financial inputs/live current rates. A dedicated native sheet owns presentation only and routes selected IDs through existing app-root editor callback.
**Tech Stack:** Kotlin/Compose Material3/JavaTime/BigInteger; min26/target36; Room6.
**Spec:** original APK1–4/TXT attachments and Swift OverviewView413–422/838–852/942–980/1795–2008/2059–2270; TransactionLogic1423–1433/1536–1541. Autonomous local slices/commits explicitly authorized; no new approval or worktree relocation. Existing branch codex/android-apk2-4-parity, BASE cd43c911.

## Global constraints

All10 cloud-write flags false; no push/deploy/production writes/migration. Preserve rows/outbox, owner-scoped private UI, exact Long/BigInteger money, vi/en/ja catalog reuse, Room6/SwiftDataV11/iOS751. Full category charts/remainingOverview/family/investment/RC remain subsequent required work.

Swift day sheet currently sums original minor amounts and labels every row with primary currency even across source currencies. Accuracy requirement in TXT takes precedence: show each original source currency; convert originals per-record for primary total. Unknown/missing FX makes total unavailable (em dash) while preserving exact rows, never relabeling imported USD as JPY. This intentionally corrects that narrow presentation mismatch on Android; existing broader reporting/imported audit remains open. Reported-expense chart overrides remain chart logic; day list uses Swift isExpenseSpending (including zero/signed ordinary amounts), not every nonzero reporting override.

## Review focus

- Owner switches while sheet open/next flow empty clear prior day/rows immediately (native replacement case).
- Day query must include more than five records, filter before sorting, use local day boundaries/occurred-created ordering (model+native7rows).
- Mixed source currencies/missing or inverse FX must preserve original row meaning and avoid partial totals (model+native live-rate case).
- Positive chart with no actual spending rows (reporting override only) must not open empty unrelated detail (native no-open case).
- Large exact values/font130 must preserve entire row/summary, scrolling/close/row-to-editor behavior (native fullglyph visuals + real editor save).

### Task 1: Owned day projection, native sheet and editor navigation

**Files:** create core/model OverviewExpenseDay.kt/test, feature/overview OverviewDayTransactionsSheet.kt/native test; modify shared OverviewMonthlyCashflow classifier, OverviewWeeklyChart, OverviewHeroMetrics, OverviewScreen; add stored-editor native integration case; app version107.
**Interfaces:** public OverviewExpenseDayRow(transaction:LedgerTransactionRecord,money:Money); OverviewExpenseDay(day:LocalDate,currencyCode:String,rows:List<OverviewExpenseDayRow>,totalMinor:Long?). overviewExpenseDay(owner,records,wallets,day,currency,rates=emptyList(),knownTitles=emptyMap(),zone):OverviewExpenseDay. Public isOverviewExpenseSpending(record,walletKind,titles=emptyMap()):Boolean shared by chart classifier. Chart/hero optional onOpenExpenseDay:(LocalDate)->Unit, realScreen owns ephemeral selectedDay. Sheet consumes day projection/owned wallet/category maps and (id)->Unit callback; dismissal before root navigation.

- [x] Write8 core cases against empty implementation: owned/status/archive/tombstone/unknown/calendars; 7+ rows local-day/recency; zero/signed/paid-for and excluded adjustment/card/installment/reporting-only; source fallback/invalid code/foreign wallet; JPY3+JPY3 at2.5=>VND16 ignoring snapshot999; inverseVND3=>JPY1; missing/imported FX=>null while originals remain; signed overflow cancellation=>LongMAX or converted6. Execute testDebugUnitTest --tests '*OverviewExpenseDayTest', require intended runtime assertion failures.
- [x] Extract shared boolean classifier without changing reported override behavior; implement exact day projection/per-record supported FX/no partial totals. Run day+weekly+monthly focused tests, require all green.
- [x] Add native cases against current no-longpress UI: realRoom7rows/exactmoney/count/zero-no-open/read-only, physical350ms longpress+haptic/selection-clear, liveprimary/rates/removal, owneremptyflow, reporting-only no-open, localizedlabels/close and light/dark130% fullglyph captures. Add real dayrow→storededitor→save exact Room/outbox case. Require runtime missing-sheet REDs before wiring.
- [x] Implement combined click/350ms longpress with accessible label/haptic and positive/overlay guards; owned Screen day selection and live projection; medium/large native sheet with localized date/header/summary/sourcecurrency rows/time-wallet-category/subtitle and exact money. Close before invoking existing editor callback; liveempty detail shows existing localized empty message.
- [x] Run focused native class/core plus actual editor integration; inspect all4 light/dark130% PNGs, fix real issues via runtime RED→GREEN.
- [x] One fresh review against Swift/spec/BASE diff, resolve Important/Critical findings using runtime RED→GREEN and green suites.
- [x] Full testDebugUnitTest/relevant AndroidTest compile/package/lint/build; Swift610/contracts15/both localization/SQLite7-3-11/packagedRoom6schemas/diff. FullOverview native, day editor integration, checksummed manifest/DEX APK107/test archives; install-r/cold/version smoke, evidence/progress, independent commit. Continue remaining full APK1–4/RC.

Self-review: projection/row/summary signatures align; every review-focus input has an explicit test; no placeholder category action; unavailable FX is a defined display state. Native inline execution persists under user's autonomous instructions; no permission pause.

Final validation: core8 + magnitude1 newtests;1530JVM/147suites/Swift610/scripts/lint/build39sec. Actual native42/42Overview79.66sec including8daycases; recent/dayeditor2/2GREEN7.446sec. Actual130%/datebaseline/fullglyph/physicallyexpandedvisible4PNGs inspected. OneImportant reviewfix and parentlayoutfix RED→GREEN; Minor Eventbadge deferred torequiredfamilyparity and priorSheet130%audit explicitlyopen. Evidence: evidence/2026-10-16-overview-day-details.md.
