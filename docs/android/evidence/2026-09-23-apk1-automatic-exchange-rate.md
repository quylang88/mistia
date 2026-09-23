# APK 1 automatic transaction exchange rate evidence — 2026-09-23

This slice completes the native Android `appRate` path for ordinary
cross-currency internal transfers. It follows the current iOS JPY/VND source,
refresh window, conversion direction and metadata contract without changing
any cloud-write boundary.

## Scope and parity boundary

- `ExchangeRateSnapshot` preserves the decimal as a string together with base,
  quote, provider, fetch timestamp and provider rate date.
- Direct JPY→VND conversion multiplies; inverse VND→JPY conversion divides.
  Both use `BigDecimal`, integer `HALF_UP` rounding and exact `Long` conversion.
  Zero, negative, malformed, unsupported and overflowing values do not resolve.
- `FrankfurterExchangeRateRepository` requests exactly
  `GET /v2/rate/JPY/VND`, accepts only the expected positive pair and an ISO
  date, and atomically commits a validated snapshot to SharedPreferences.
- The last good snapshot is exposed immediately and is retained on HTTP,
  decoding, validation or cache-write failure. Refresh occurs at most once per
  local day and only at/after 07:00. The network/cache work runs on IO and
  coroutine cancellation is rethrown.
- The transaction screen triggers one lifecycle-bounded stale refresh. For a
  supported wallet pair, App rate derives read-only destination/rate fields and
  the saved draft's amount, rate, provider and date from the same current
  snapshot. A refreshed snapshot recomputes displayed values before save.
- Manual conversion keeps its existing entered amount/rate metadata behavior.
  Unsupported pairs fall back to manual, and same-currency transfers clear all
  stale conversion fields.

No Supabase schema, migration, RLS, RPC, Edge Function, production request or
new write gate belongs to this slice.

## TDD and review evidence

- Resolver RED: focused model tests failed to compile before
  `ExchangeRateSnapshot` and `resolveExchangeRate` existed. GREEN covers direct,
  inverse, half-up, malformed/zero/unsupported values and overflow.
- Repository RED: focused network tests failed to compile before the
  Frankfurter repository/cache existed. GREEN covers the exact route, validated
  atomic replacement, malformed-response retention, the 07:00 daily boundary,
  next-day refresh and cache-write failure.
- Editor RED: focused feature tests failed before rates were accepted by
  `toDraft` and before wallet-pair recomputation existed. GREEN covers exact App
  rate metadata, missing-rate validation, unsupported-pair fallback and
  same-currency clearing.
- Final self-review added three RED regressions: cache commit on the caller
  thread, swallowed `CancellationException`, and stale App-rate display state.
  All three passed after the IO/cancellation/display fixes. The review also
  restored exact manual provider/date preservation.

## Automated release gate

- `./gradlew testDebugUnitTest :core:database:compileDebugAndroidTestKotlin
  :app:lintDebug :app:assembleDebug --no-build-cache --no-daemon
  --max-workers=1 --console=plain`: passed in 58s.
- Result XML: 194 tests across 37 suites, 0 failures, 0 errors, 0 skipped.
- Room Android-test Kotlin compilation, Android lint and debug APK assembly all
  completed successfully.
- `swift Scripts/check-android-contracts.swift`: passed with 15 entities using
  Command Line Tools.
- `swift Scripts/generate-android-l10n.swift --check`: passed.
- Strict `generate-l10n.swift --strict-keys --check`: passed. No String Catalog
  or generated localization source changed. The additional
  `xcstringstool compile --dry-run` subcheck cannot run until this Mac's full
  Xcode license is accepted; it is not claimed.
- `git diff --check`: passed.

Final artifact before commit:
`android/app/build/outputs/apk/debug/app-debug.apk`, SHA-256
`7172c32f137f175012f874649d8e2d671e53ee9f7854553739019d45c4ffb6cf`.
The APK contains 634 files. Generated debug `BuildConfig` confirms the global,
category, wallet, credit-card and transaction cloud-write flags are all
`false`.

## Device boundary

Per the user's current direction, final-artifact Samsung verification is
skipped because no Samsung is connected. Earlier in the slice, a pre-final
diagnostic build installed successfully on `SM-F776Q`, retained the authenticated
session and persisted a live Frankfurter snapshot with rate `164.77`, provider
`frankfurter` and rate date `2026-09-23`. Subsequent review fixes changed the APK,
so that observation is supporting network/cache evidence only, not a device
claim for the final artifact or the full JPY/VND editor branch.

Receipt capture/analysis and other APK 1 parity work remain outstanding. APK 1
and later APK 2–4/RC gates are not claimed complete.
