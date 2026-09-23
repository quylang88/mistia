# APK 1 receipt AI client foundation evidence — 2026-09-24

This slice establishes the native Android request/response and authenticated
transport boundary for Mistia's existing `analyze-bill-items` Supabase Edge
Function. CameraX, Photo Picker, review UI and transaction persistence remain
separate slices.

## Scope and parity boundary

- `core:model` now owns typed category/wallet candidates, request payload,
  itemized purchase/discount lines, quota, result, client and failure types.
- The request preserves the iOS/Edge Function snake_case contract, including
  locale, time zone, preferred currency and target app language.
- Literal `raw_line_text` remains audit evidence. The client does not translate,
  merge or reinterpret item rows: `3@` remains quantity `3`, and a standalone
  coupon can remain its own negative discount line.
- Response decoding accepts integer-valued decimals and numeric strings, ignores
  future unknown fields, normalizes confidence/ranges, rejects unknown line
  types, and removes category/wallet IDs outside the submitted candidate sets.
- The transport posts exactly to `/functions/v1/analyze-bill-items`, sends the
  configured publishable/anon client key only as `apikey`, and sends the caller's
  signed-in JWT as `Authorization: Bearer ...`. It never owns or reads auth
  storage and contains no service-role credential.
- OkHttp is configured for the existing two-stage Gemini path with a 170-second
  read timeout and 180-second total timeout. Coroutine cancellation cancels the
  in-flight call.
- HTTP 401/403, 400/405/422, 413, 415, 5xx/54x and transport failures map to
  stable typed categories. HTTP 429 becomes a daily-limit failure only when a
  valid denied quota object is present. Raw error bodies, base64 image data and
  access tokens are not included in exception messages.

No production Edge Function call, Gemini request, Supabase write, schema,
migration, RLS/RPC change, Edge Function deployment or write-gate change was
performed. Verification used MockWebServer only.

## TDD and review evidence

- Model RED: `ReceiptAnalysisTest` failed to compile before the item/result,
  quota and typed-failure contract existed. GREEN covers literal OCR retention,
  purchase/discount normalization, arithmetic totals, duplicate IDs, candidate
  validation and exception redaction.
- Network RED: `SupabaseReceiptAnalysisClientTest` failed to compile before the
  client existed. GREEN covers exact path/headers/body, flexible decoding, quota
  preservation, status mapping, malformed response, blank auth and cancellation.
- Self-review added RED regressions for an allowed purchase without an original
  amount, unknown `line_type`, long AI timeouts and malformed-body redaction.
  All pass after the parity, transport and redaction fixes.
- Hilt compilation proves the singleton `ReceiptAnalysisClient` binding without
  coupling the transport to `AuthRepository`, Compose or a ViewModel.

## Automated release gate

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed in 1m 56s (`709` tasks).
- Result XML: 209 tests across 39 suites, 0 failures, 0 errors, 0 skipped.
- Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- `swift Scripts/check-android-contracts.swift`: passed with 15 entities using
  Command Line Tools.
- `swift Scripts/generate-android-l10n.swift --check`: passed.
- Strict `generate-l10n.swift --strict-keys --check`: passed. No String Catalog
  or generated localization source changed. The broader localization audit
  reached its environment-only `xcstringstool` step, which is unavailable under
  Command Line Tools until the full Xcode toolchain/license is usable; that
  subcheck is not claimed.
- `git diff --check`: passed.

Final artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`697af35ad023bf87a957ec4f1117639acedf290d46924d562a2547c8adb62337`.
The APK contains 634 files. Generated debug `BuildConfig` confirms the global,
category, wallet, credit-card and transaction cloud-write flags are all
`false`.

## Device and next-slice boundary

Per the user's current direction, Samsung verification is deferred and does not
block local development. This foundation is not a claim that a real receipt was
captured, uploaded, analyzed by Gemini or applied on-device. The next slices are
CameraX/Photo Picker plus bounded image preparation, then the native itemized
review/apply flow and transaction persistence.

APK 1 and later APK 2–4/RC gates remain incomplete.
