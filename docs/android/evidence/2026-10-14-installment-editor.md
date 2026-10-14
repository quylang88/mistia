# Native installment create/edit/delete editor — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `9e21d3b`.

## Completed native metadata workflow

The Planning installment pane now opens an owned create/edit sheet and calls the actual installment save/delete repository. Creation allocates one client UUID when opening; retry and saved-instance restoration retain it. The form includes name, per-cycle amount, due day, frequency, nullable cycle count, payment-wallet selector and the four Swift registry icon tokens. Existing currency and creation anchor stay frozen. Day/frequency defaults and imported values follow PlanningInstallmentDraft; day/frequency pickers offer 1–31 /1–12. Blank cycle count clears the value, and invalid/overflowing count input raises a localized error instead of silently clearing it.

Wallet choices exclude foreign/deleted/unknown-kind/card records and newly linked archived wallets; the original archived link can remain. Wallet names include currency. This metadata link performs no payment or FX. It follows Swift's metadata selector; a different-currency link does not authorize a later money movement. Payment/undo/maintenance and settlement currency handling remain separate unfinished work.

Save failures retain fields and show generated vi/en/ja messages, including stale baseline guidance. Unsaved close/back/drag requires discard confirmation. Delete has its own confirmation explaining that posted transactions remain; it passes the original baseline rather than unsaved edits. Busy state disables duplicate save, close and destructive controls. Cancellation is checked before and after callbacks, including noncooperative delayed completion, so an old editor cannot dismiss a replacement.

The host keeps the editor composed across month/zone/loading changes. Owner-scoped navigation and form savers validate owner, editor UUID and encoded original identity. Repository identity is deliberately absent from the saved subtree keys, allowing restoration after repository reconstruction. Owner/target replacement cancels the previous editor scope; the latest callbacks are used after ordinary recomposition. A clock input supports deterministic host fixtures while production refreshes each resumed minute.

## Currency input comparison

Directly reviewed `PlanningEditors.swift` (PlanningInstallmentEditorSheet/PlanningInstallmentDraft), `CurrencyFormatting.swift` and `MistiaFinanceIcons.swift`. Actual Swift installment input comma-groups **raw minor integers for every currency**, without multiplying by fraction digits. Android follows this behavior using exact Long parsing: `1,375` stays 1375 minor for JPY/VND/USD. A formatted per-cycle preview makes the interpreted amount visible (USD 1375 minor displays 13.75). Values above Double's exact integer range remain exact.

Android retains invalid punctuation for explicit validation rather than Swift's permissive digit stripping. Decimal/scientific/letter/overflow input cannot silently become a different amount. New cycle count validation also avoids Swift's invalid-text-to-nil behavior. Other Android monetary forms still require a separate input-semantics audit; this slice makes no blanket claim about them.

## Verification

Runtime TDD:11 editor/navigation/cancellation cases first failed against stubs, then all11 passed. Initial dependency/compilation attempts were corrected before the accepted runtime RED; compilation failures are not counted as behavioral evidence. Cases cover stable creation identity, exact grouped minor values/overflow, nullable Int32 cycle count, imported schedules/currency/Long baseline, wallet filtering, malformed/foreign restoration and late canceled callbacks.

Final **1078 JVM tests /111 suites**, zero failures/errors. Full Android unit tests, Room/management/planning AndroidTest compilation, lintDebug and assembleDebug pass. Seven new Compose/Room workflow fixtures compile only: actual create/edit/delete/outbox with no ledger movement; saved-instance restoration with a new repository plus month change; owner replacement; failed save/dirty discard in dark large font; delete using original baseline; busy/frozen currency/exact Long behavior; archived/foreign/card wallet and icon selection. These fixtures have not run on an emulator or Samsung. StateRestorationTester source/compilation and saver JVM tests are not actual process-death device proof.

Full Swift603 (4contract+133data+466core), contract15, Android and strict Swift localization checks, actual SQLite outbox7/notification3 and `git diff --check` pass. Direct diff/Swift review completed. Independent review remains pending availability. Logs: `/tmp/mistia-installment-editor-{red,green,build,compose,full,package-info,final,swift}.log`. The first aggregate run was interrupted after unit/AndroidTest/lint completion because D8 remained unusually slow. A sequential packaging retry with detailed logs and the final aggregate run verify the actual artifact; no source or dependency-version change was made to bypass packaging.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-installment-editor-v55.apk`; debug package/versionCode55 verified. SHA256 `8418441b4be46bb06bb434761011429258d40cac145037129acdacc0dc508cb4`. The slice began on October14; final packaging completed after local midnight on October15.

## Remaining scope and gates

Default app currency/settings integration, Fluent/badged icon rendering and actual visual/accessibility/device inspection remain open. Current form uses Material icon equivalents with Swift registry default colors; no pixel-level parity is claimed. Installment payment/undo/skip/maintenance/push, card payment/currency decision, remaining APK1–4 and RC remain unfinished. All10 cloud flagsfalse; no live cloud write, deploy or migration. ADB empty; no Samsung/emulator/visual verification. Full goal stays active.
