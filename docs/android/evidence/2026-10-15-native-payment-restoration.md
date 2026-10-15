# Actual Compose installment payment and restoration — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `85c1bab1`.

Ran all9 InstallmentPaymentWorkflowTest cases on dedicated `mistia-api36-native`, Android16/API36 ARM64 emulator `emulator-5554`. Initial actual execution produced3 failures: the fixture constructed a real payment repository without its required category catalog, causing one direct failure and the real-payment workflow timeout; actual StateRestorationTester execution exposed a product crash because the sheet passed the localized month title (for example October2026) to a saver that expects canonical `2026-10`. Pure saver tests had not covered that caller wiring.

Fixed the product to key the saver with row.month.toString(), keeping only the visible cycle title localized. Fixed the synthetic payment and reconstructed repository to load the shared MistiaSystemCategories catalog from packaged assets. Neither payment/category validation nor test assertions were weakened. Existing restoration workflow was the runtime RED: it selects an alternate same-currency wallet, restores saved state/reconstructs the repository, asserts the selected wallet survives, checks keep/discard, then proves month/owner changes close the old sheet. Direct Swift review confirms its dueMonthKey is a canonical model key distinct from its formatted month title and its unsaved-selection baseline.

After rebuilding/reinstalling: **9/9 actual Compose/Room workflows pass**. Includes current-currency invalidation during confirmation; changed paid-cycle undo hold; loading/invalid frozen amount; late NonCancellable undo after month change; real payment/undo/repay stable IDs and derived balance/outbox; busy/failure retention; skipped/paid row actions; restoration/discard/owner/month; excluded wallet picker in dark mode. This is real Compose activity/runtime with synthetic Room data, not live account use or Samsung verification. StateRestorationTester covers Android save/restore integration; no full OS kill/restart or signed-in process-death claim.

Logs `/tmp/mistia-native-installment-payment-ui-red.log` (9run/3fail), `/tmp/mistia-native-installment-payment-ui-assemble.log`, `/tmp/mistia-native-installment-payment-ui-green.log` (9pass in23.686seconds). Full planning suite is next and is not claimed here. Existing database suite122pass is documented separately in native-room-emulator evidence.

Full JVM1365/130suites, Swift609, app lint/build, database/management/planning AndroidTest compile/package, contract15, both localization checks, SQLite7/3/11 helpers and packaged database schemas1–6/bootstrap pass. No Swift/runtime schema/catalog or cloud capability changes. Direct self review complete; independent review remains pending. Final full logs `/tmp/mistia-native-payment-restore-{full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-payment-restore-v70.apk`, debug versionCode70: SHA256 `d51eb341296f6fcf49f5d7fa8a6b8190039e007f9e018af5275f912fa2db44b8`.

Actually executed planning test APK `android/build/outputs/apk2/2026-10-15/mistia-planning-native-payment-test-v70.apk`: SHA256 `6a9a746949eef5442c95b738f8e8a27ea80ad6b6383e8d8b4bb2122114c132cf`.

All10 flagsfalse; only emulator connected, no Samsung/live cloud writes/deploy/migration. Full planning/management/UI/background/accessibility/visual checks, missing-parent repair, paid remote writes/undo orchestration, duplicate/source/legacy recovery, fund usage/maintenance, pending card choice, currency/settings/forms and remaining full APK1–4/RC remain active.
