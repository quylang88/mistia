# Recurring bill payment source consent — slice123

Branch codex/android-apk2-4-parity, base40677923. Full APK1–4/RC goal remains active.

## Behavior

Manual recurring-bill payments carry the visible source and effective cycle amount. Before preparing money writes the repository compares these to its fresh owned source/cycle. Missing/stale manual consent fails with existing SOURCE_CHANGED; no transaction, occurrence or outbox write commits. The existing atomic snapshot/CAS still guards changes after the repository read. Automatic payments retain fresh-source/no-manual-override behavior; the installment adapter retains its separate expected-plan guard. Same-currency eligibility and deliberate positive variable/repayment overrides remain intact.

Source comparison canonicalizes the exact created instant and ignores only ACK metadata (updatedAt/syncVersion/last device). Other source fields conservatively invalidate consent, including owner/id/amount/currency/wallet/schedule/name/category/archive/pause. Local edits with the same syncVersion0 are detectable. Pending occurrence amount changes are checked independently of default bill amount, preserving intentional null for variable dues. The local request adds expectedBill/expectedDueAmountMinor; no persisted/wire entity, schema, network payload or cloud gate changes.

Both the native confirmation button and callback compare frozen consent to the current request. An open5000 confirmation cannot submit after visible source/cycle becomes6000, schedule changes or currency changes; cancel and reconfirm uses current6000. Metadata-only ACK does not require reconfirmation. Current callbacks and existing busy/cancel/undo paths remain. A real Room UI case changes stored source after confirmation but before repository invocation, with the visible row withheld: the backend refuses stale money and records/outbox remain unchanged apart from the independent source edit.

## TDD and direct review

- Five initial JVM vectors: two actual business failures3s, paid5000 instead of SOURCE_CHANGED after stored6000/missing proof. Same source/ACK/variable/autopay controls passed.
- Actual Room baseline2/1 businessRED0.182s, stale paid5000; persistence/reopen control passed. Native confirmation2/2RED4.632s: old payment remained enabled after amount/schedule changed.
- Source guard/current producer/frozen consent focused database76+PlanningBillPayment GREEN7s; Room11GREEN0.509s and native sheet6GREEN16.354s. Legitimate existing manual fixtures now supply their visible source. Paused/custom-category/maintenance manual-race fixtures use the actual source they intend to test, retaining original error/money assertions.
- Review found pending cycle amount can change while bill remains equal. New unit1/1RED2s reproduced stale paid5000. Added effective-cycle baseline and fresh6000/variable-null controls. Focused core4/database77/Planning7 GREEN/package9s. Final Room12/12GREEN0.525s includes3 new source/cycle/reopen vectors and9 existing atomic-payment tests.
- Pure consent vectors cover exact time/ACK equivalence, relevant source changes, wallet/month/amount/mode/cycle amount and malformed required time. UI and actual Room integration retain record/outbox assertions.
- The first dialog font fixture measured1.0 instead of1.3: outer composition density did not configure its separate Android window. The fixture now sets actual emulator font scale before Activity launch and restores it in finally. Image inspection found all labels still English; explicit locale title/cancel assertions reproduced missing Vietnamese text after scoping a duplicate-title matcher to the confirmation. Test-only window resources/configuration are configured/restored per locale. No production locale code changed. WindowInspector font fixture runsAPI29+, actualAPI36; no skipped test in this run. JUnit initially rejected the integration expression's non-void return; explicit Unit fixed this harness error, not a business RED. Final localized-font +real Room UI integration2/2GREEN7.712s.

Direct reference: Swift DuePaymentSheet406–445 rebuilds a draft from its current due item; Android installment request/sheet already carry/check expected source. Existing finalCAS is unchanged. Complete source/test patch SHA256cfebda171bd658c82fa22a8cc4592738a848b3307205621e52cc2d42e6e7bd53 reviewed. No independent whole-branch approval claimed.

## Verification and artifacts

Full Android terminal0/BUILD SUCCESSFUL92s, then14s/5s/6s after native fixture changes:1708JVM/164suites zero failures/errors/skips, required AndroidTest compile/package, Room compilation, lint/main assembly. Swift610(4/137/469), contracts15entities, both strict localization generators, SQLite7/3/11, Room6schema assets and whitespace passed. Six final actual130% en/vi/ja light/dark confirmation PNGs inspected: full9007199254740993 amount, correct title/cancel and disabled old Pay now. No full-root/system-inset/all-dialog/hit-target parity claim.

Complete Planning124/124GREEN796.344s before the narrow late-result callback fix below. After that fix full JVM/compile/lint/main GREEN16s and complete modified BillPaymentSheet10 +real Room UI integration1 =11/11GREEN30.529s; the unchanged remaining Planning paths were covered by the124 run. Do not describe this as a whole126-test final run. Main123install-r preserved data; cold Status:ok/LaunchState:COLD1188ms, installed version123/min26/target36 and all3 installed/archive SHA256 matches verified. No native Overview rerun required for unchanged reader/watchlist paths; full compile/JVM retained. Archives in ignored android/build/outputs/apk2/2026-10-21/. Manifests checked: version123/min26/target36, main20DEX/planning9/database5.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-bill-source-guard-v123.apk|86eb5f12f60fdeec9f2a8897dce02a1b1ec42b3c2529d0093b2abcd498e45cd3|
|mistia-bill-source-guard-test-v123.apk|3b1e0fe8310ec32d8aa99e77cf740548fbefe861045b57948eda50827785dcf6|
|mistia-bill-source-room-test-v123.apk|0bb869d302fa0ce65af4ab4893d7f81fe0b7cafee2d2b3e4635abc38a52b2715|

All10writeflagsfalse; Room6/SwiftDataV11/iOS751unchanged; API36ARM64emulatortransport13 only. No Samsung/liveSupabase/productionwrite/deploy/migration. Logs /tmp/mistia-bill-payment-source-guard-*. Next actual upcoming bill/installment Overview section/shared payment route, then card/investment/preparing/config/family/receipts/settings/device/background/release/full-branch review. This is one recurring-payment correctness slice, not a complete Due domain/APK gate.


## Late-result review correction

Direct review of the changed callback path and existing guarded installment implementation found that a noncancellable old bill operation could still dismiss a new cycle's confirmation after the old sheet's coroutine was cancelled. Two actual synthetic native cases first failed2/2in5.408s for pay and undo: the new confirmation disappeared after the old success returned. The sheet now checks coroutine activity immediately after the repository callback, before delivering success/error to UI. Both paths retain busy/cancel cleanup; a completed financial commit is not undone by this UI delivery guard. Focused complete bill sheet +real Room UI suite11/11GREEN30.529s, full Android checks GREEN16s after this narrow runtime change. Final six localized130% images refreshed/inspected from that executed package; system font scale restored1.0. No other runtime path changed after the124 Planning run.
