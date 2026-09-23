# Android Automatic Exchange Rate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cached automatic JPY/VND rate resolution to the native Android transaction editor with iOS-equivalent metadata and fallback behavior.

**Architecture:** A pure model-layer resolver consumes immutable rate snapshots. A network-layer repository validates Frankfurter responses and atomically persists the last good snapshot; Compose observes that repository and resolves the existing transaction draft without changing Room or cloud schemas.

**Tech Stack:** Kotlin, BigDecimal, coroutines/StateFlow, OkHttp, kotlinx.serialization, SharedPreferences, Jetpack Compose, Hilt, JUnit, MockWebServer.

**Spec:** `docs/superpowers/specs/2026-09-23-android-automatic-exchange-rate-design.md`

## Global Constraints

- JDK 17 and Android minSdk 26.
- Only JPY/VND is supported in this slice.
- Use `HALF_UP` integer minor-unit rounding and reject overflow.
- Preserve a last good cache on every refresh failure.
- No Supabase mutation, schema, RLS, RPC, Edge Function, or production deployment.
- Manual FX behavior and same-currency metadata clearing must remain intact.

## Review Focus

- Inverse VND-to-JPY conversion must divide and round `HALF_UP`, never multiply.
- A zero, negative, malformed, or overflowing rate must not create a draft.
- A failed refresh must not erase a cached rate the editor can still use.
- Switching wallets must recompute from the selected pair without retaining stale metadata.
- Recomposition must not issue unbounded refresh requests.

---

### Task 1: Pure exchange-rate contract and resolver

**Files:**
- Create: `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/ExchangeRates.kt`
- Create: `android/core/model/src/test/java/vn/com/quyln/mistia/core/model/ExchangeRatesTest.kt`

**Interfaces:**
- Produces: `ExchangeRateSnapshot`, `ExchangeRateRepository`, and `resolveExchangeRate(amountMinor, sourceCurrencyCode, destinationCurrencyCode, rates)`.

- [x] Write failing tests for direct/inverse conversion, half-up rounding, invalid rates, unsupported pairs, and overflow.
- [x] Run `./gradlew :core:model:testDebugUnitTest --tests '*ExchangeRatesTest'` and confirm failure because the API is absent.
- [x] Implement the immutable types and pure resolver with `BigDecimal` and exact `Long` conversion.
- [x] Re-run the focused model tests and confirm they pass.

### Task 2: Cached Frankfurter repository

**Files:**
- Create: `android/core/network/src/main/java/vn/com/quyln/mistia/core/network/FrankfurterExchangeRateRepository.kt`
- Create: `android/core/network/src/test/java/vn/com/quyln/mistia/core/network/FrankfurterExchangeRateRepositoryTest.kt`
- Modify: `android/app/src/main/java/vn/com/quyln/mistia/AppModule.kt`

**Interfaces:**
- Consumes: `ExchangeRateRepository` and `ExchangeRateSnapshot` from Task 1.
- Produces: a singleton Hilt binding backed by SharedPreferences and OkHttp.

- [x] Write failing MockWebServer tests for the exact path, validated cache replacement, cache retention on malformed data, and once-daily refresh after 07:00.
- [x] Run the focused network test and confirm failure because the repository is absent.
- [x] Implement response validation, atomic cache persistence, `StateFlow`, and stale-refresh policy.
- [x] Bind the implementation in `AppModule` and re-run focused network and app compilation checks.

### Task 3: Transaction editor App-rate flow

**Files:**
- Modify: `android/app/src/main/java/vn/com/quyln/mistia/MainActivity.kt`
- Modify: `android/feature/transactions/src/main/java/vn/com/quyln/mistia/feature/transactions/TransactionsScreen.kt`
- Modify: `android/feature/transactions/src/main/java/vn/com/quyln/mistia/feature/transactions/TransactionEditorSheet.kt`
- Modify: `android/feature/transactions/src/main/java/vn/com/quyln/mistia/feature/transactions/TransactionEditorState.kt`
- Modify: `android/feature/transactions/src/test/java/vn/com/quyln/mistia/feature/transactions/TransactionEditorStateTest.kt`

**Interfaces:**
- Consumes: repository snapshots and `resolveExchangeRate` from Tasks 1-2.
- Produces: an App-rate `TransactionDraft` with resolved destination amount and rate/provider/date metadata.

- [x] Write failing editor-state tests for exact App-rate draft metadata, missing-rate validation, and wallet-pair recomputation.
- [x] Run the focused transaction-feature tests and confirm the new expectations fail.
- [x] Inject/collect the repository, trigger bounded stale refresh, enable both mode chips, and make App-rate fields derived/read-only.
- [x] Re-run focused tests and compile the app.

### Task 4: Evidence and release gate

**Files:**
- Modify: `docs/android/android-parity-progress.md`
- Create: `docs/android/evidence/2026-09-23-apk1-automatic-exchange-rate.md`

**Interfaces:**
- Consumes: the completed automatic-rate flow.
- Produces: auditable local and Samsung evidence plus one independent feature commit.

- [x] Run full Android unit tests, Room Android-test compilation, lint, and debug assembly with one Gradle worker.
- [x] Run Android contract, Android localization, and strict iOS String Catalog checks.
- [x] Record test totals, APK SHA-256, cache/network boundary, and all remaining APK 1 work.
- [x] Skip final-artifact Samsung verification per the user's current direction; distinguish the earlier pre-final diagnostic from the release gate.
- [x] Run `git diff --check`, review the staged diff, and commit `feat(android): resolve transaction app exchange rates`.
