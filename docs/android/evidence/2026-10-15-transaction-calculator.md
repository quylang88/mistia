# Owned transaction amount calculators — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `8e4fc62d`; APK90.

Source JPY/VND amounts and manual cross-currency destination JPY/VND amounts now open the shared native calculator. Keyboard focus clears on opening; busy saves disable both entry buttons. OK commits grouped exact integer text only to its selected draft field and clears old validation errors. Source commits share the typing path and recompute APP_RATE using current snapshots; derived destination remains read-only without a calculator. Cancel/error preserves original blank/signed draft text. No arithmetic or persistence algorithm changed.

Active field restoration carries a scope envelope; both field and expression scope include owner, record, primary kind/subtype, source/destination IDs and currencies, and conversion mode. Foreign/restored stale tool state cannot be committed to a different scope. The editor's existing owned draft/callback guards remain intact.

Direct Swift references: `Mistia/Features/Transactions/TransactionEditorSheet.swift`1271,1290–1299 use `MistiaCurrencyInputField`; `Mistia/Shared/Modifiers/KeyboardModifiers.swift`11–85 opens the sheet, clears first responder and writes returned text; `Mistia/Core/UI/MistiaAmountCalculatorSheet.swift` validates before commit and dismisses. Shared Android math remains covered by86 golden vectors derived from actual Darwin Foundation Decimal. Other/imported currencies and unselected-wallet calculator availability are an explicit remaining parity audit, not claimed complete by this bounded JPY/VND slice.

TDD: six new actual Compose/Room cases first fail for missing calculator actions. Initial green attempt passes5/6; remaining fixture selected a read-only APP_RATE destination using hasSetTextAction, so could not find it. Selector now uses the actual destination field tag, retaining exact derived amount165666 and persisted snapshot assertions. Final **17/17 full transaction native tests pass in65.166seconds**, including exact source9007199254740993/destination18014398509481986 and literal outbox values, unchanged wallet records, no transaction/outbox before Save, APP_RATE recalculation, invalid zero/divide-zero/cancel, selected-field expression restoration, currency-change closure, owner isolation and saving disable.

Full **1425 JVM/134suites**, zero failures/errors; Swift610 (4+137+469), app lint/build, database/management/planning/transaction AndroidTest compile, database/transaction test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room schemas1–6/bootstrap and whitespace pass. Actual Room164 was last run green in89; no database/model change in90. Independent read-only `review_transaction_calculator90` reports no Critical/Important/Minor code finding. Logs `/tmp/mistia-transaction-calculator-{red-build,native-red,focused-build,native-focused,full,swift,native-final}.log`; native-focused contains the obsolete fixture selector failure, native-final is green.

Archived metadata/manifest/DEX-verified artifacts under `android/build/outputs/apk2/2026-10-15/`:

- `mistia-0.2.0-apk2-transaction-calculator-v90.apk`, versionCode90, SHA256 `4bb608f1c6531cada3eae5c8257de3674c153b440c330480728478fef7375570`.
- Executed `mistia-transactions-calculator-test-v90.apk`, SHA256 `f5d6101880e526689646b081d3af883031c990a37f1258f5f13e16579ca24031`.

API36 emulator update used install-r preserving data; installed version90 confirmed and cold MainActivity launch Status ok (TotalTime1789ms). These automated fixtures and launch are not Samsung/authenticated manual financial or complete visual/receipt/background/process-kill QA. No Samsung connected. All10 cloud flagsfalse; no production writes/live Supabase/deploy/migration; Room6/SwiftDataV11/iOS751 unchanged. Prior management initial row timeout84 remains unproven. Ordinary transaction preflight-to-commit races, reporting FX, remaining APK1–4 and RC remain open; goal stays active and continues.
