# Android Automatic Exchange Rate Design

## Intent

Complete the existing Android transaction editor's `appRate` path so JPY/VND
internal transfers match iOS behavior. The editor must resolve exact minor-unit
destination amounts from a cached rate snapshot, preserve provider/date/rate
metadata in the transaction, survive network failure with the last good cache,
and retain the current manual-entry fallback.

## Scope

- Support the same currently enabled iOS pair: JPY/VND in both directions.
- Fetch `https://api.frankfurter.dev/v2/rate/JPY/VND` with the shared OkHttp
  client and decode `date`, `base`, `quote`, and decimal `rate`.
- Persist the last valid snapshot locally. Refresh at most once per local day
  after 07:00, matching `MistiaCurrencyRateMaintenance`.
- Expose cached snapshots immediately through a repository `StateFlow`; a
  failed refresh keeps the cached snapshot and returns a failure for diagnostics.
- Resolve direct and inverse rates with `BigDecimal`, `HALF_UP` integer rounding,
  and exact `Long` conversion. Invalid, zero, unsupported, or overflowing rates
  return no result.
- Let the cross-currency transaction editor select App rate or Manual. App rate
  computes and displays the destination amount and persists the rate, provider,
  and rate date; manual behavior remains unchanged.

## Boundaries

- No Supabase schema, RLS, RPC, Edge Function, production cloud write, or new
  write gate is involved.
- No broad currency-settings screen is added in this slice. The rate source and
  supported pair intentionally match the current iOS implementation.
- Same-currency transfers continue clearing all conversion metadata.
- If neither cache nor a successful refresh provides a usable rate, App rate is
  unavailable and the existing localized conversion error directs the user to
  refresh or enter the amount manually.

## Architecture and data flow

`core:model` owns `ExchangeRateSnapshot`, `ExchangeRateRepository`, and the pure
minor-unit resolver. `core:network` owns the Frankfurter/cache implementation.
Hilt provides the repository to `MainActivity`, which passes it to the existing
transaction screen. The screen collects cached snapshots and triggers stale
refresh; the editor delegates conversion to the pure resolver and passes the
resolved values through the existing `TransactionDraft` validation path.

Network responses are accepted only when the pair is JPY/VND and the decimal is
positive. Cache replacement occurs only after full validation, so malformed or
failed responses cannot destroy a previous valid snapshot.

## Verification

- Model tests: direct conversion, inverse conversion, half-up rounding, invalid
  rate, overflow, and metadata selection.
- Network tests: request path, valid response/cache, malformed response retaining
  cache, and daily refresh policy.
- Editor state tests: App rate creates the exact draft snapshot; missing rates
  fail without silently switching to manual; same-currency clearing remains.
- Full Android tests, Room compile, lint, APK assembly, contract/localization
  checks, APK checksum, and Samsung install/navigation verification.
