# APK 1 offline debt-lend foundation evidence — 2026-09-24

This bounded slice opens the local transaction/repository path needed by the
receipt review's Lend mode. It implements standalone posted `debt/lend` only;
the native receipt/editor binding and other debt intents remain separate work.

## Scope and parity

- `TransactionDraft` accepts a counterparty display name for
  `transfer/debt/lend`. Posted lending requires an active owner-scoped source
  wallet, positive exact minor units, the Lend intent and a normalizable
  counterparty. It has no destination wallet, category or FX fields.
- The counterparty key follows Swift's compatibility, width, diacritic and case
  folding plus alphanumeric/separator collapse. For example,
  `Ngọc Đặng！Ａ` persists as the trimmed display value and `ngoc đang a` as the
  normalized key. Live Foundation checks also lock `Işık → isık`,
  `ışık → ısık`, `ẞ → ss`, `ᾲ → α` and final sigma behavior.
- Bank/cash lending is an outflow checked against current wallet balance,
  independent of the entered date. Credit-card lending is the only supported
  debt intent allowed on a card and is checked against current available
  credit.
- Credit-card debt lending contributes to statement charges and is locked when
  a post-closing payment covers the statement. Repository validation also
  rejects a proposed new lend that would alter such a paid statement.
- The repository keeps dependency lookup and observation account-scoped and
  commits the ledger record with its coalesced outbox mutation atomically.
  Payload fields include the `lend` wire intent and normalized counterparty.
- `borrow`, `collect`, `repay` and `familyTransfer` remain explicitly rejected
  by this create contract. Non-posted debt and edits of settlement-owned debt
  are also rejected. Standalone Lend edits explicitly null any stale reporting,
  settlement, destination, category and FX values. Other intents require their
  own wallet/settlement semantics.

## TDD and review trail

- RED 1: model tests failed at compilation because `TransactionDraft` lacked
  counterparty input and the required validation errors. Balance and paid-card
  assertions described lending as an outflow and statement charge.
- GREEN 1: typed debt-lend mutation, Swift-equivalent counterparty folding,
  current-balance/available-credit checks and direct paid-statement lock passed
  the focused core-model suite.
- RED 2: the first repository paid-statement setup reused the expense ID and
  exercised edit protection instead of a proposed new lend; assigning a
  distinct transaction ID exposed the real failure.
- GREEN 2: repository proposed-statement validation now includes only expense
  and `debt/lend` charges. Owner-scoped record/outbox, insufficient-balance and
  paid-statement repository tests pass together with the focused model tests.
- RED 3: review vectors exposed that uppercasing before lowercasing changed
  Turkish dotless-I and Greek iota-subscript semantics. Review also identified
  missing posted-only and settlement-ownership boundaries.
- GREEN 3: compatibility decomposition now removes combining marks before the
  lowercase/special case fold; the Foundation vectors pass. Non-posted debt and
  settlement-owned edits are rejected, and regression tests assert explicit
  nulls in both the local record and pending outbox payload.
- Final review: no Critical or Important findings remained; production code was
  judged ready after refreshing the release evidence.
- `git diff --check`: passed.

## Automated release gate

- Full Android command: `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 1 minute 44 seconds (`709` tasks).
- Result XML: 304 JVM tests across 50 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test source compilation, Android lint and debug APK assembly
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android cloud-contract check, Android localization generation check and
  strict iOS localization codegen check passed.
- No localization source changed. The known full localization-audit limitation
  remains: the Xcode license is not accepted and Command Line Tools do not
  provide `xcstringstool`; the full audit is not claimed as passing.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`d43a3768c1f13e6a2492d4540b9009d561117f9b7e69b00975d1b53d8277f345`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Verification boundary

`adb` is unavailable, so local debt save, balance errors and card-statement
errors were not exercised on an emulator or Samsung device. No production
Supabase request, migration, RLS/RPC/Edge Function change or deployment
occurred. Receipt Lend UI/editor binding and other debt/settlement intents are
still pending; APK 1 and APK 2–4 remain incomplete.
