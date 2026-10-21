# Overview recurring due items and original-cycle payment — slice 124

Base: `99d826b2f8faec663d1e282e38d13b26c8ae6b34`. Branch: `codex/android-apk2-4-parity`.
Status: slice-local implementation, regression and artifact checks completed; full APK1–4/RC goal remains active.

## Delivered behavior

Overview shows actual pending recurring bills from the previous/current cycle and installments from the current cycle. The local calendar window is today through seven days, with the existing payment-opening/deadline rule, urgency at three days, date/name ordering and maximum three rows. A composite source-kind/id/month identity preserves different unpaid cycles of the same source. Each row keeps its own exact minor amount and currency; intentional variable bills show the shared “No amount yet” copy. Unreadable required source/cycle fields hold the section unavailable instead of producing a zero or ordinary pending item.

A new owner-scoped, five-entity raw snapshot is produced by one Room query, retaining tombstones and damaged financial fields for admission. Loading, read failure, retry, wrong owner and late old-owner emissions are covered. Reads do not write rows or outbox. This remains conservative source admission, not a complete independent-field read audit.

Tapping a row saves only owner/kind/source/month and opens the existing Bill/Installment payment sheet through a shared Planning presenter. MainActivity composes the features and coordinates overlays; there is no production feature-to-feature dependency. A test-only dependency verifies the actual Overview-to-presenter composition. The presenter reloads the original source cycle, retains an open draft through read failure, disables payment/confirmation when unavailable or stale, and never turns an old Pay target into Undo or Create. Current same-currency wallet rules remain unchanged.

Direct executor review found an installment pending-cycle amount could change before repository read while its plan remained unchanged. Installment requests now carry the visible effective-cycle amount separately from plan default, and the shared manual executor verifies it before money writes. Unknown current cycle kind/status or an unreadable related month cannot default to pending or disappear. Existing atomic money/outbox CAS remains authoritative. Installment UI source consent now uses the existing repository semantic comparison, including its timestamp tolerance and ACK metadata exclusions, so changed currency/schedule/wallet disables confirmation while metadata-only ACK remains valid.

## Actual TDD and focused execution

- Raw snapshot: two JVM failures and two Room failures under the legacy combined streams; the Room run observed 13 mixed `(6000,5000)` / `(5000,6000)` source/cycle pairs and omitted damaged deletion. One-query implementation: focused JVM GREEN and actual Room **2/2 GREEN, 0.209s**.
- Selector: **12 cases / 11 business failures** with the absent adapter, then **12/12 GREEN** plus existing scheduling vectors. Covers DST, previous/current cycle identities, 0/3/4/7-day boundaries, excluded paid/skipped/archived/foreign sources, exact values above 2^53/Long.MAX, variable null versus unreadable money, unknown enums and max-three sorting.
- Missing native section: **7 cases / 6 business failures, 40.536s**, then **7/7 GREEN, 11.811s**. Identifier-only navigation adds two JVM cases.
- Missing shared payment route: **3/3 business failures, 20.242s**, then **3/3 GREEN, 12.406s**. Actual Room payments persist exact **1375 USD**, one expense/occurrence/outbox each, unchanged wallet opening balance, and effective balance **8625**. Variable bill amount and identifier route survive saved-state restoration.
- Extended route suite: **8/8 GREEN, 26.318s**. External payment disables the old confirmation and cannot become undo; read failure retains the variable draft and retry pays it; initially paid/missing sources show an explicit unavailable dialog; unreadable wallet currency cannot invent eligibility.
- Required executor bugs: installment effective-cycle **1/1 business RED**, target cycle authority **3/3 business RED**. Focused Bill/Installment repository, PaymentState and Upcoming tests passed in **5s** after guards.
- UI source-consent test: corrected fixture genuinely changes **JPY to USD**, then **1/1 business RED, 1s** with the old helper. The earlier fixture accidentally left currency unchanged and is not counted as business RED. Shared semantic comparison: PaymentState/repository tests and native packaging **GREEN, 7s**.
- Actual section content/geometry/visual suite: **9/9 GREEN, 17.954s**. All 12 original PNGs in `images/2026-10-21-overview-recurring-due/` were inspected: en/vi/ja, light/dark, exact/variable and unavailable states, measured **1.3** font scale, complete text and no ellipsis. Header/card gap, 13sp title and 30dp icon geometry are asserted. These are component cases; full icon assets, rounded-font identity, root/system insets and complete physical hit testing remain open.

Test compilation, a non-void JUnit setup, and a Compose non-local-return D8 error were corrected as harness/compiler diagnostics; they are not counted as business RED.

## Full verification

- Full host command **BUILD SUCCESSFUL, terminal exit 0, 1m58s**: all JVM tests, required Room/feature instrumentation compilation and packages, app lint and debug APK.
- **1731 JVM tests / 167 suites**, zero failures, errors or skips (fresh final XML totals).
- Swift **610 tests**: 4 app, 137 data-support and 469 core-logic tests, all passed; the separate Testing Library zero-test footer is not the XCTest count.
- Contracts **15 entities**, Android and strict Swift localization checks, SQLite outbox **7**, notifications **3**, installment deletion **11**, Room assets **6 schemas**, whitespace: passed.
- Complete Planning run: **134 executed / 133 passed / 1 failure, 538.582s**. The failure reproduced a frozen-confirmation rendering regression: a still-readable changed source hid the user’s original confirmed amount. Preserve that frozen amount while keeping confirm disabled; externally paid/unavailable targets still show a dash. Final full host after correction: **GREEN, 41s**, all **1731 JVM / 167 suites** clean.
- Final complete changed payment classes: BillPaymentSheet **10** + real Room UI **1** + InstallmentPaymentWorkflow **9** + Overview route **8** = **28/28 GREEN, 101.107s**. Other Planning paths were unchanged after the full run; this is not a claim that an entire final 134-case run passed.
- Final complete Overview **144/144 GREEN, 314.796s**; affected actual Room source/snapshot/payment/ACK suites **28/28 GREEN, 1.154s**. All runners reached their explicit JUnit `OK` footer.

## Direct review and limits

Reviewed directly against Swift `OverviewLogic.upcomingDueAlerts`, `OverviewView.recurringBillDueItems`, `routeDueAlertTap`, `UpcomingBillsSection`/`DueRow`, `MistiaFinanceIconView`, and existing DuePaymentSheet/source-consent/currency rules. The source/test patch is `/tmp/mistia-overview-recurring-due-final-source-test.patch`, SHA-256 `0ddaae57db55eccb0f5d5fc45ff9b13a2192392149e88f8f11ae9b986a0df810`. Fresh isolated reviewer `review_due124` inspected the pinned final patch and reported no concrete Critical/Important finding. The reviewer did not execute tests. Declined areas (credit-card integration, independent-field admission, complete icon/font assets, and whole APK/domain/branch completion) remain required backlog and are not certified by this slice. No independent whole-branch approval is claimed.

All ten cloud-write gates remain false; Room 6, SwiftData V11 and iOS version 751 are unchanged. API36 ARM64 emulator transport 13 only. No Samsung verification, live Supabase test, production write, deployment or migration occurred.

Credit-card alert/payment integration remains open with the existing currency product question. Investment/preparing/configuration/family/receipts, complete financial read semantics, full icon/font/root UI parity, background/device/release checks and a fresh whole-branch review remain required. This personal recurring-due feature does not complete the Due domain, Overview or an APK gate. Full APK1–4/RC goal remains active; commit this coherent slice after final verification, then continue local work.


## Final archived artifacts and installation

- `mistia-0.2.0-apk2-overview-recurring-due-v124.apk` — SHA-256 `88509acfc0bdd31ad4b478bccc3002317b05914d23ea7a49a7b5df7dc63b8776`, 20 DEX files.
- `mistia-overview-recurring-due-test-v124.apk` — SHA-256 `952902a684e57ae416c62cded9cfb5853a7ca14390c45840b8e60f8e35e56d5d`, 9 DEX files.
- `mistia-overview-due-payment-test-v124.apk` — SHA-256 `ffe25bcf5b55b8b4f2f1e9070f0bedfa6b7d27766ab64f17bd92f76e54ea3299`, 10 DEX files.
- `mistia-overview-due-room-test-v124.apk` — SHA-256 `c2820bdee3b573c305b36eb7bc8307710a96bd4c6bb17e4bd17c2cb88a0d652a`, 5 DEX files.

Main manifest: versionCode124, versionName0.2.0-apk2-debug, min26/target36. Overview/planning test targets36; Room test target26 executes on API36. Archives are ignored under android/build/outputs/apk2/2026-10-21/. Main124 installed with `adb install -r` preserving app data, cold launch `Status: ok`, `COLD`, **1150ms**, and installed manifest version124/min26/target36. All four installed package SHA-256 values match the archived APKs above. Emulator font_scale restored to1.0; Samsung remains absent.
