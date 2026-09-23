# APK 1 receipt analysis coordinator evidence — 2026-09-24

This bounded slice builds the authenticated request and batch-coordination
layer between prepared Android receipt images and the existing typed
`ReceiptAnalysisClient`. It does not expose UI, persist transactions or invoke
the live Edge Function.

## Scope and parity

- `buildReceiptAnalysisRequest` mirrors the iOS itemized-bill payload: prepared
  JPEG bytes are Base64 encoded off the main dispatcher and accompanied by MIME
  type, locale, current time-zone identifier and target language.
- Category candidates are owner-scoped, active expense children only, exclude
  the balance-adjustment system category, preserve configured order and include
  localized category and parent names.
- Wallet candidates are owner-scoped and active, preserve configured order and
  exclude the deterministic investment-profit system wallet. The first
  eligible wallet supplies the request currency, falling back to JPY.
- `analyzePreparedReceipts` obtains one refreshed signed-in access token for the
  batch, submits images sequentially in picker/capture order and returns an
  ordered success/failure attempt for each bill.
- A typed per-bill analysis failure does not discard successful sibling bills.
  Missing authentication fails before the first client request, while coroutine
  cancellation stops the batch and propagates to its owner.
- Result rows are passed through the typed receipt model unchanged by this
  coordinator. Literal OCR text, quantity notation and standalone discount rows
  therefore remain available to the later native review screen.

## TDD and review evidence

- RED: the focused target failed to compile because
  `ReceiptAnalysisRequestContext`, `buildReceiptAnalysisRequest` and
  `analyzePreparedReceipts` did not exist.
- GREEN: four focused JVM tests cover localized owner-scoped candidate
  filtering/order, Base64 and locale metadata, one-token sequential partial
  success, missing authentication before transport, and cancellation stopping
  the remaining batch.
- Mutation review: admitting parent/income/archived/foreign-owner/system
  categories, admitting archived/deleted/foreign-owner/investment-system
  wallets, refreshing a token per image, continuing after cancellation or
  reordering results breaks a focused assertion.
- `git diff --check`: passed.

## Automated release gate

- Focused command:
  `./gradlew :feature:transactions:testDebugUnitTest --tests
  'vn.com.quyln.mistia.feature.transactions.ReceiptAnalysisCoordinatorTest'
  --no-build-cache --no-daemon --max-workers=1 --console=plain`: passed, 4/4.
- Full command:
  `./gradlew testDebugUnitTest
  :core:database:compileDebugAndroidTestKotlin :app:lintDebug
  :app:assembleDebug --no-build-cache --no-daemon --max-workers=1
  --console=plain`: passed in 55 seconds (`709` tasks).
- Result XML: 236 tests across 44 suites, 0 failures, 0 errors, 0 skipped.
  Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- With `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, the 15-entity
  Android contract check, Android localization generation check and strict iOS
  localization codegen check passed.
- The full localization skill audit remains unavailable on this machine: the
  full Xcode path is blocked until its license is accepted, while Command Line
  Tools does not contain `xcstringstool`. No localization source changed in
  this slice, and this limitation is not claimed as a passing audit.

Artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`d65e3dea0e8303fda8764efff4334bff77dd55bf509bba8bac65d7cce1f8c4e4`.
The APK contains 653 files. Generated debug `BuildConfig` confirms all five
cloud-write flags remain `false`.

## Remaining boundary

No live Edge Function/Gemini request, transaction or receipt-image persistence,
production write, migration or deployment occurred. The coordinator is not yet
routed to UI. Samsung verification remains deferred per the user's direction.
The native analysis/review state and screen, then review-to-transaction apply
and persistence, remain the next APK 1 work; APK 1 and APK 2–4 remain incomplete.
