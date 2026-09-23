# Android Receipt AI Client Foundation Design

## Intent

Create the authenticated Android client contract for Mistia's existing
`analyze-bill-items` Supabase Edge Function. This is the stable boundary that
the later CameraX, Photo Picker, review UI, and transaction-persistence slices
will consume. The client must preserve the iOS request/response semantics,
literal OCR evidence, quota metadata, and actionable error categories without
exposing credentials or private upstream response bodies.

## Scope

- Add typed request candidates, itemized analysis results, line types, quota,
  and client/error contracts to `core:model`.
- Preserve the Edge Function's snake_case wire fields, including
  `raw_line_text`, quantity, original/discount/final minor amounts,
  `multiple_bills_detected`, and `target_language_code`.
- POST to `/functions/v1/analyze-bill-items` with the configured client key in
  `apikey` and the signed-in user's JWT as `Authorization: Bearer ...`.
- Decode optional, missing, numeric-string, and integer-valued decimal fields
  defensively, matching the existing iOS client tolerance.
- Map authentication, invalid request, oversized image, unsupported media,
  daily quota, upstream unavailability, and malformed success responses into
  typed failures. Preserve a decoded quota object on HTTP 429.
- Perform blocking OkHttp work on `Dispatchers.IO` and preserve coroutine
  cancellation.
- Provide the client through Hilt for the later UI/media slice.

## Boundaries

- No CameraX, Photo Picker, Compose review UI, image transcoding, transaction
  creation, or receipt persistence is added here.
- No Supabase schema, migration, RLS, RPC, Edge Function deployment, or
  production write is performed. Local tests use MockWebServer only.
- The Android client targets `analyze-bill-items`, not the legacy
  `analyze-receipt` endpoint.
- Literal OCR text remains audit evidence. The client must not translate,
  normalize, merge, or otherwise reinterpret item text or money arithmetic.
- The app uses only its configured publishable/anon client key. No service-role
  or secret key belongs in Android code.

## Architecture and data flow

`core:model` owns immutable receipt-analysis types, `ReceiptAnalysisClient`,
and a typed `ReceiptAnalysisException`. `core:network` owns
`SupabaseReceiptAnalysisClient`, which validates local preconditions, encodes
the request with the shared explicit-null wire format, invokes the authenticated
Edge Function, and converts the response into model types.

The client accepts an access token rather than reaching into auth storage. The
later presentation layer must obtain a current session through the existing
`AuthRepository.refreshIfNeeded()` flow, which keeps authentication lifetime
and HTTP transport separately testable.

Error bodies are parsed only for the documented quota payload. They are not
surfaced in exception messages because Edge Function or upstream details may be
private. Supabase's `sb-error-code` can be retained as diagnostic metadata, but
never replaces the app-level failure category.

## Verification

- Model tests cover normalization, item review invariants, arithmetic totals,
  candidate-ID validation, and typed failure redaction.
- MockWebServer tests cover the exact URL, method, headers, complete snake_case
  request body, tolerant success decoding, 429 quota decoding, status mapping,
  malformed success data, and cancellation.
- Run focused model/network tests, compile the app Hilt graph, then run the full
  Android unit/Room/lint/APK gate plus contract and localization checks.
- Record APK checksum and explicitly mark Samsung verification deferred per the
  user's current direction.

