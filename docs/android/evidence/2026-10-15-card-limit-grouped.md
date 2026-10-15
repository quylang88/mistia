# Native grouped credit-card limit — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `291bbc31`; APK83.

JPY/VND card limit groups thousands during typing and existing-card presentation via the shared exact text formatter. Direct Swift comparison: `ManagementEditors.swift` creditCardFormSection uses `MistiaCurrencyInputField`; `KeyboardModifiers.swift` delegates grouping to `MistiaCurrencyInputFormatting`. Android retains nonnegative exact Long parsing, blank→zero and malformed/overflow validation. Imported fractional ISO currencies retain existing Android semantics; broader cross-platform import parity remains open. No accounting/schema/network behavior change.

TDD:4 new JVM cases,2 intended runtime grouping failures;8 card-state cases now pass. Cases cover both supported currencies above2^53, Long.max, blank/zero/negative/malformed/overflow and importedUSD12.34→1234minor. Actual API36 Compose/Room2 new workflows first fail on ungrouped typed input, then pass: create exact9007199254740993, no record before explicit Save, reopen grouped, edit1375, preserve identities/opening balance and exact profile outbox. Initial native fixture had a wrong repository observer name (compile corrected), then expected local edits to increment remote sync_version; actual contract preserves cloud baseline0 and coalesces outbox. Corrected that assertion to0 and added exact queued limit/base assertions; no production version change. Final full management **17/17 pass in51.997seconds**.

Full **1409 JVM /134 suites**, zero failures/errors; Swift610 (4+137+469), app lint/build, database/management/planning AndroidTest compile, database/management test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room schemas1–6/bootstrap and whitespace pass. Reviewer `review_card_limit83` independently reviewed diff/new native fixture/shared formatter/parser/actual Swift sources: no Critical/Important/Minor findings. The subsequent fixture baseline correction is checked against `CreditCardDraft.toMutation` and actual Room/outbox.

Logs `/tmp/mistia-card-limit-{state-red,native-red,native-red-build,full,swift,final-test-build,management-full,management-final}.log`. `management-full` records the2 fixture-baseline failures; final green is `management-final`.

App `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-card-limit-grouped-v83.apk`, versionCode83, SHA256 `3c658981941c4a0c712bd5b0ecdc00ea2b071c374d114e0a05e8f8674fabd4bd`.
Executed management test APK `android/build/outputs/apk2/2026-10-15/mistia-management-card-limit-grouped-test-v83.apk`, SHA256 `50a5d40d19573d9fdfaa69657e2d63362d99b65e072bedb5642fa5b1d3066c07`. Metadata/manifest/version/DEX verified.

Only API36 emulator connected. No new full visual/Samsung/process-kill/live sync proof. All10 cloud-write flagsfalse; no production write/deploy/migration. Card calculator/owned editor, statement payment policy/workflow, remaining APK1–4 and RC gates remain open. Goal stays active; continue next slice.
