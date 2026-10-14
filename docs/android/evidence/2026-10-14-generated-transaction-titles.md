# Stored generated transaction-title localization — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `27e675f`.

## Behavior and Swift comparison

Overview, Transactions and native card statement history now share a display-only generated-title resolver. It recognizes stored Vietnamese/English/Japanese internal-transfer, sent/received family-transfer, balance-adjustment and four debt-intent titles, then renders the current resource language. Matching trims whitespace and ignores case; unrelated/custom/blank titles are preserved. No record, amount, fingerprint, outbox or generated copy changes.

Compared actual `TransactionGeneratedTitle.swift` and `FinanceEnums.TransactionDebtIntent.title`. Transfer subtype constrains candidates; known debt intent restricts matching, while a legacy nil intent considers all four debt names. Expense/income adjustment titles require the canonical adjustment category UUID or its system key. UI metadata is owner-scoped, including archived/deleted system category metadata, and a mismatched category owner/id cannot supply the system key. Static known titles come from generated Android resources for all three languages; cached values contain only strings, never Context/Activity/account records. Display text uses stringResource so language changes recompose. No second translation catalog was introduced.

Overview retains its existing raw-record/money query and malformed-record fallback; title localization does not alter its selection/money rules. A separate read-scope audit is needed for general Finance repository streams: they currently rely on the local-store partition, and typed decoders can accept a payload owner differing from the row owner. This existing gap is not claimed fixed here. Native statement view already checks its own owned card/profile/charge metadata.

## Verification

TDD: initial stub produced39 failures across96 preliminary assertions; cases were consolidated to remove empty/no-op test methods. Final runtime RED `/tmp/mistia-generated-title-red-focused.log`: **24 tests,24 intended failures**. GREEN24 parameterized cases (8 title kinds ×3 shared catalog languages) verify actual xcstrings titles, case/Unicode whitespace, custom/blank values, wrong subtype/intent/category, nil-intent fallback and canonical/system-key adjustment aliases. xcstrings is copied only into test resources, not packaged as a runtime asset.

Full Android **965 JVM tests /101 suites**, zero failures/errors; Room/management/planning AndroidTests compile, lintDebug/assembleDebug pass. Two new resource/Compose bridge tests compile only: live en/ja/vi changes preserve stored/custom strings; foreign category system key cannot rename an owned expense. A test fixture initially passed an already-typed CategoryMutation record into fromCloudRecord; the compile error was fixed and all checks rerun successfully. No runtime/device proof is claimed for these AndroidTests.

Focused Swift TransactionLogic **37 tests**, full Swift **602 tests** (4contract+133data+465core), contracts15, both localization checks, actual SQLite outbox7/notification3 and whitespace checks pass. Logs: `/tmp/mistia-generated-title-{red,red-focused,green,full,swift,swift-full}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-localized-transaction-titles-v51.apk`; aapt confirms debug package/versionCode51. SHA256 `f38bf9c106bdd3f7a018d8469a0cccf70139229d02f028a68a5a4acab61f02bd`.

## Remaining gates

ADB empty; no emulator/Samsung/language-change/visual device verification. Independent review pending availability; direct Swift/self-review completed. Nine cloud flagsfalse, no live Supabase write/deploy/migration. General read scoping, card money/maintenance/pending currency decision, installments, remaining APK1–4 and RC work stay open. No overall gate is marked complete.
