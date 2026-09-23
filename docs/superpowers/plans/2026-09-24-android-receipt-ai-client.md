# Android Receipt AI Client Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a typed, authenticated, locally testable Android client for Mistia's existing itemized receipt-analysis Edge Function.

**Architecture:** `core:model` defines the platform-neutral receipt contract and typed failures. `core:network` encodes/decodes the wire payload and invokes Supabase with the caller's refreshed user JWT. Hilt exposes the client for the next media/UI slice.

**Tech Stack:** Kotlin, kotlinx.serialization JSON, coroutines, OkHttp, Hilt, JUnit, MockWebServer.

**Spec:** `docs/superpowers/specs/2026-09-24-android-receipt-ai-client-design.md`

## Global Constraints

- JDK 17 and Android minSdk 26.
- Use `/functions/v1/analyze-bill-items`; do not call the legacy endpoint.
- Preserve raw OCR/item text and money values exactly as returned.
- Use `apikey` for the configured client key and Bearer user JWT for auth.
- Never log or expose access tokens, base64 image data, or private error bodies.
- No production deploy, cloud mutation, schema, RLS, RPC, UI, or media work.

## Review Focus

- A 429 without a valid quota must not masquerade as a decoded daily limit.
- Missing/invalid candidate IDs from the response must not reach later UI as
  trusted selections.
- Unknown response fields and flexible integer values must remain compatible
  with the existing Edge Function/iOS contract.
- Cancellation must propagate rather than becoming a generic network failure.
- No exception text may include the raw response body or credentials.

---

### Task 1: Pure receipt-analysis model contract

**Files:**
- Create: `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/ReceiptAnalysis.kt`
- Create: `android/core/model/src/test/java/vn/com/quyln/mistia/core/model/ReceiptAnalysisTest.kt`

**Interfaces:**
- Produces: request/candidate/result/item/quota types,
  `ReceiptAnalysisClient`, and typed failure categories.

- [x] Write failing tests for normalization, arithmetic/review invariants,
  candidate validation, and failure redaction.
- [x] Run the focused model test and confirm RED because the contract is absent.
- [x] Implement the smallest pure model contract that passes the tests.
- [x] Re-run focused model tests and confirm GREEN.

### Task 2: Authenticated Supabase Edge Function client

**Files:**
- Create: `android/core/network/src/main/java/vn/com/quyln/mistia/core/network/SupabaseReceiptAnalysisClient.kt`
- Create: `android/core/network/src/test/java/vn/com/quyln/mistia/core/network/SupabaseReceiptAnalysisClientTest.kt`

**Interfaces:**
- Consumes: Task 1 model contract, `SupabaseConfig`, shared OkHttp and JSON.
- Produces: authenticated request execution, tolerant decode, and typed errors.

- [x] Write failing MockWebServer tests for exact headers/body, tolerant decode,
  429 quota, status mapping, malformed success, redaction, and cancellation.
- [x] Run the focused network test and confirm RED because the client is absent.
- [x] Implement IO execution, wire mapping, validation, and error mapping.
- [x] Re-run focused model/network tests and confirm GREEN.

### Task 3: Hilt integration

**Files:**
- Modify: `android/app/src/main/java/vn/com/quyln/mistia/AppModule.kt`

**Interfaces:**
- Consumes: `SupabaseReceiptAnalysisClient`.
- Produces: singleton `ReceiptAnalysisClient` binding for the next UI slice.

- [x] Add the provider without coupling it to auth storage or a ViewModel.
- [x] Compile the app and verify the Hilt graph.

### Task 4: Evidence and slice commit

**Files:**
- Modify: `docs/android/android-parity-progress.md`
- Create: `docs/android/evidence/2026-09-24-apk1-receipt-ai-client.md`

**Interfaces:**
- Consumes: the completed client foundation.
- Produces: auditable local evidence and an independent feature commit.

- [x] Run full Android unit tests, Room Android-test compilation, lint, and
  debug assembly with one Gradle worker.
- [x] Run Android contract, Android localization, and strict iOS String Catalog
  checks, recording any environment-only limitation precisely.
- [x] Record test totals, APK SHA-256, security boundary, and deferred CameraX,
  Photo Picker, review UI, persistence, and Samsung checks.
- [x] Run `git diff --check`, self-review against Review Focus, and commit the
  slice independently.
