# Mistia Android session handoff — 2026-09-22

Read the original requirements at
`/Users/quyln/.codex/attachments/1b6bfcfe-49b2-4465-bafe-41003c98d45a/pasted-text.txt`.
Latest user override: **do not require manual account switching**. Prioritize
completing APK 1–4 and UI/functionality parity; current signed-in UI remains
read-only and incomplete. Do not claim those gates complete.

## Workspace

Repository `/Users/quyln/Project/mistia`, work based on develop commit
`2ffe485d1ff271c2f61ee623cc0fe9b93106b88b`. The user requested committing the
current Android code, tests and handoff as a checkpoint before the next session.
Inspect git log/status/diff for that checkpoint and preserve any later changes.
Do not reset, blindly pull over changes or repeat environment bootstrap.

Java17: `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`.
SDK: `/Users/quyln/Library/Android/sdk`, platform36/build-tools35.0.0.
Use `JAVA_HOME=... ./gradlew` from android/.
Swift: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
Kotlin2.2.21, KSP2.3.12, GoogleID1.2.0. User permits upgrading Kotlin2.4 when
actually needed. GoogleID1.2.1 requires newer metadata but upgrading is not the
fix for the reproduced OAuth failure.

## Completed increment

- Google native Credential Manager, hashed nonce to Google/raw nonce to
  Supabase; email sign-in/signup/name metadata/resend/recovery forms.
- Auth ViewModel/validation, no passwords in saved instance state, redacted
  diagnostics/errors. Debug event logging accepts fixed enum events only.
- iOS artwork reused for launcher and auth UI; purple/grouped auth hierarchy.
- Source amount/currency pairing fixed in overview/transactions with wallet
  fallbacks matching Swift.
- 35 Kotlin tests + debug lint/build pass, contract15entities and localization
  checks pass. Scoped independent review found no introduced P1/P2 issue.
- Auth-entry Compose instrumented test passed on Samsung with Espresso3.7.0.
  Gradle connected tests removed the target app after testing: use explicit
  install -r and direct instrumentation going forward to preserve live data.

## Google fixed on real Samsung

SM-F776Q, Android17/API37, serial R5GL72ERETZ. Connection sometimes disappears;
check adb status before device actions and do not claim evidence while offline.
Version3 (`0.1.2-apk0-debug`) installed with `adb install -r`.
Google returned unregistered Android package/SHA1 and disguised it as
Credential Manager cancellation. Registered Android OAuth in existing Cloud
project mistia-492216/741455632256 with explicit user confirmation.
Client ID: 741455632256-12uieac1sm1v17am9ro25gkrjrii9vgr.apps.googleusercontent.com.
Package vn.com.quyln.mistia.debug; SHA1
35:4E:93:46:C5:35:CA:D6:9E:6C:08:6C:20:33:00:78:1F:5C:42:23.
Do not replace the existing web client ID used for token requests.
User selected account; GOOGLE_TOKEN_RECEIVED and GOOGLE_EXCHANGE_SUCCEEDED
observed; user confirmed entering app. All23 pull tables completed, one viewer
partition, zero outbox records. Force-stop/cold-start retained signed-in UI.
No need to repeat Cloud setup or Google debugging without a new failure.
Email code is tested, but real email login is not independently verified.
User has explicitly waived manual account-switch tests.

APK: `android/build/outputs/apk0/2026-09-21/mistia-0.1.2-apk0-debug-v3.apk`.
SHA256: 3276f8283c59ab29b3b044e46346673439c09b6b66a965417c3a84da89f7a0fb.

## Remaining failure

Swift regression initially597/597 passed, later596/597. Unchanged
MistiaMigrationPlanTests.testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees
fails CoreData134504/unknown coordinator model version; same failure with clean
scratch build android/build/swift-clean-check. No Swift runtime edits made.
The insufficientPosition log nearby is from another expected oversell test,
NOT this failure's root cause. Diagnose; do not disable test or claim passing.

## Next work

Latest user workflow requirement: split implementation into small, coherent
vertical slices. For every slice: define scope and acceptance criteria against
iOS, implement, run relevant checks, review the diff and behavior, fix review
findings, then commit that slice before starting the next one. Record validation
and remaining gaps in the progress document. Do not accumulate all APK1–4 work
in one large commit. A slice commit does not imply that its entire APK gate is
complete. Commit locally; pushing or deploying is not part of this request.

APK1 wallet/card/category, income/expense/internal transfer/FX, receipt
CameraX/Photo Picker/AI, offline mutation/outbox and push/pull.
APK2 budgets/goals/bills/installments/card statement-payment/due/notifications.
APK3 family permissions/invites/transfers/shared expenses/settlements/inbox.
APK4 resale unit-aware FIFO, buy/sell/capital/profit postings, private product
images and existing atomic RPC. Then original RC scope.

Implement complete screens and actions with hierarchy/spacing/icons/color/dark
mode as close to iOS as practical. Preserve native Kotlin/Compose architecture;
UI/ViewModels through repositories. Use Long minor units, BigDecimal/decimal
strings, explicit nulls, fingerprints, version/tombstone/owner scoping,
dependency ordering, atomic Room mutation+outbox, retry/conflict tests.
Do not enable global ALLOW_CLOUD_WRITES. Gate each write domain separately.
Shared xcstrings is sole static copy source; regenerate rather than edit
outputs. No production migrations/deployments without explicit approval.

Evidence/docs: android/README.md; contracts/*;
docs/android/android-parity-progress.md;
docs/android/evidence/2026-09-21-google-login.md (resolution supersedes earlier
pending status); docs/android/google-oauth-setup.md.
