# Android parity execution record

## Binding requirements

Continue APK 1, 2, 3, 4 and RC in order using the existing Kotlin/Compose
architecture. Swift remains the business-rule reference and the shared
catalog remains the static-copy source. Each gate needs tests and physical
Samsung evidence; no blanket finance-write enablement and no production
schema deployment without the specified approval.

Latest user direction adds full Google/email entry, shared branding/icon
and the closest practical iOS hierarchy, spacing, purple palette and dark
mode. Samsung is connected and APK 0 is installed, but authenticated
baseline verification is still pending.

## Current task: baseline auth and presentation

- [ ] Add regression tests around Supabase auth payloads, session isolation,
  credential redaction and email validation before changing behavior.
- [x] Implement native Google Credential Manager with the existing web
  client ID, SHA-256 nonce binding and Supabase token exchange through
  AuthRepository. Cancellation must not sign out or expose credentials.
- [x] Implement email sign-in/sign-up, display-name metadata, confirmation
  resend and reset-email feedback. Match Swift password/email validation.
- [x] Replace the temporary launcher icon with the existing iOS artwork;
  use iOS auth hierarchy with grouped background and Google/email choices.
- [x] Fix amount/currency pairing in read-only lists with regression tests.
- [ ] Run Kotlin, contract, localization and Swift checks; build with an
  increased versionCode; install as an update on Samsung and record the
  authenticated/device results separately from mocked results.

## Subsequent gates

- APK 1: wallet/card/category/transaction/FX/receipt; domain repositories,
  atomic Room mutation+outbox, ordered push and conflict/retry testing.
- APK 2: planning, due maintenance and notifications with Swift vectors.
- APK 3: family roles/invites/transfers/settlements with cloud-first scope.
- APK 4: resale FIFO, unit-aware inventory, images and existing atomic RPCs.
- RC: remaining data/security/settings/accessibility/signing matrix.

No later gate is claimed complete by this execution record. Production
OAuth verification needs the Android package and this Mac's certificate
registered in the existing Google Cloud project; a client implementation
or a visible account picker alone is insufficient evidence.

## Handoff update — 2026-09-22

Google login is fixed and physically verified: Android OAuth registration was
missing, was created with user confirmation, and the Samsung received a Google
token and successfully exchanged it with Supabase. All 23 tables pulled, and
signed-in state survived force-stop/cold start. See the latest evidence's
resolution section; earlier pending statuses are historical.

User explicitly waives live account-switch testing. Do not ask for it again or
block APK 1–4 on that manual check. Keep account scoping correct in code/tests.
The user emphasizes that Android UI is still substantially different and many
features are missing: complete working screens and workflows, not merely
repository scaffolding or read-only counts.

APK 1–4/RC are NOT complete. Cloud financial writes remain disabled. The next
session should implement APK 1 domain-by-domain, with exact Swift rules,
atomic Room/outbox changes, contract serialization and device verification,
then proceed to APK 2, 3, 4 and RC in sequence.

## Swift gate correction — 2026-09-22

- [x] Reproduced the V7 investment migration failure in an isolated fresh
  scratch build instead of treating the earlier full-suite pass as sufficient.
- [x] Fixed the legacy-store fixture lifecycle with `autoreleasepool`, ensuring
  its CoreData coordinator is released before reopening the same URL with the
  current staged migration plan.
- [x] Re-ran the isolated fresh-scratch migration test and the full Swift suite:
  1/1 and 597/597 passed. No production migration or schema was changed.

Evidence: `docs/android/evidence/2026-09-22-swift-v7-migration-test-lifecycle.md`.

## APK 1 wallet slice — 2026-09-22

- [x] Added typed wallet contract mapping with exact signed `Long` minor units,
  iOS kind/icon/color defaults, explicit JSON nulls, canonical IDs/timestamps,
  and dedicated-flow guards for credit-card and investment wallets.
- [x] Added account-scoped offline create/edit/archive with one atomic Room
  transaction for the local wallet row and coalesced outbox row. Archive remains
  an `is_archived=true` upsert, matching iOS.
- [x] Replaced the wallet count with an interactive grouped list, empty state,
  editor sheet, bank validation, archive confirmation, 13 iOS wallet icon
  choices and the 10-color iOS palette.
- [x] Kept existing opening balance immutable in metadata editing; Android must
  add the separate balance-adjustment transaction flow before showing iOS's
  effective current balance.
- [x] Passed 51 Android unit tests, lint, debug assembly, Room instrumented-test
  compilation, contract/localization checks, and 597 Swift tests.
- [ ] Run `WalletRoomTest` and visual/create/edit/archive verification on the
  Samsung with `adb install -r`; no ADB device was connected for this slice.

This is one APK 1 vertical slice, not APK 1 completion. Wallet cloud push,
credit-card profiles/statements, categories, transactions, FX and receipts
remain pending, and `ALLOW_CLOUD_WRITES` remains `false`.

Evidence: `docs/android/evidence/2026-09-22-apk1-wallet-offline.md`.

## APK 1 wallet push foundation — 2026-09-22

- [x] Added iOS-equivalent PostgREST wallet fetch/create/update requests: owner
  and record filters on reads, array POST create, and owner/record/version
  filters on conditional PATCH with server representations returned.
- [x] Added account-scoped due-outbox reads, bounded retry metadata and an
  atomic compare-and-ACK transaction. A response for an older mutation cannot
  delete or overwrite a newer edit made while the request is in flight.
- [x] Added wallet create/update/semantic-ACK/conflict/retry coordination,
  including create-race refetch and deterministic iOS authority rules. Sync-now
  and WorkManager use the coordinator before pull.
- [x] Added a wallet-only build gate and kept it `false`; the PostgREST client
  independently rejects wallet writes while disabled. No production request,
  migration, RPC or deployment was performed.
- [x] Passed 65 Android unit tests, lint, debug assembly, Room instrumented-test
  compilation, contract/localization checks and the 5-test Swift outbox suite.
- [ ] Run Room tests plus offline-create/push/edit/conflict behavior on Samsung,
  then deliberately enable the wallet gate in a device-test build. ADB listed
  no device, so the current APK still performs pull-only behavior at runtime.

Unresolved Android conflicts are durably retained in the outbox with automatic
retry disabled, preventing data loss. The dedicated conflict record/review UI
and live Supabase verification remain a later wallet sync slice; therefore APK
1 is still not complete.

Evidence: `docs/android/evidence/2026-09-22-apk1-wallet-push-foundation.md`.

## APK 1 offline category hierarchy — 2026-09-23

- [x] Added the full typed `transaction_categories` contract with explicit
  nullable fields, 64-bit sync versions, localized names, hierarchy inference,
  system metadata preservation and iOS expense/income defaults.
- [x] Added owner-scoped create/edit/favorite/archive through the existing
  atomic Room record+outbox boundary. Duplicate names use the active editing
  locale; child parents must be active, same-kind roots; role is immutable
  after creation; structural edits receive the next branch sort order.
- [x] Matched iOS archive guards for active children and direct active
  transaction, budget and recurring-bill references.
- [x] Matched the iOS current-month budget branch guard: category name, kind
  and parent changes are blocked while that branch is used by an active budget;
  icon and favorite-only edits remain allowed.
- [x] Replaced the category count with expense/income hierarchy cards,
  expandable parent branches, child favorite controls, add/edit sheets,
  localized validation and archive confirmation. The editor packages the
  shared iOS system-category catalog and exposes all 147 active canonical
  `mistia.category.*` icon tokens; internal balance-adjustment children and
  empty uncategorized roots stay hidden like iOS.
- [x] Passed 89 Android unit tests, lint, debug assembly, Room instrumented-test
  compilation, contract/localization checks and 17 focused Swift system
  category tests.
- [ ] Install with `adb install -r` and verify the hierarchy/editor/archive
  states on Samsung. No ADB device was connected for this slice.

Category push, remote translation and live multi-device conflict verification
remain later domain-gated work. Category writes were not added to the wallet
allowlist, and no production write, migration, RPC or deployment occurred.

Evidence: `docs/android/evidence/2026-09-23-apk1-category-offline.md`.

## APK 1 category push foundation — 2026-09-23

- [x] Added a dedicated `ALLOW_CATEGORY_CLOUD_WRITES` build gate, defaulting
  to `false`. Category is independently allowlisted at the PostgREST boundary
  and was not folded into the wallet gate; the legacy global gate also remains
  `false`.
- [x] Added owner-scoped category fetch/create/conditional-update push with
  explicit nullable fields and signed 64-bit `sync_version` preservation.
  Category and wallet now share the same reviewed outbox state machine for
  semantic ACK, create race, conditional-update race, deterministic authority,
  unresolved conflict retention, bounded retry, cancellation and exact stale
  response protection.
- [x] Matched iOS dependency ordering: category parents push before children,
  and the sync engine orders the category domain before wallet regardless of
  dependency-injection list order. Pull still starts only after both gated
  push coordinators have run.
- [x] Passed 107 Android unit tests, lint, debug assembly, Room instrumented-test
  compilation, contract/localization checks and 22 focused Swift category/
  outbox tests.
- [ ] Install with `adb install -r` and verify category create/edit/conflict
  behavior on Samsung in an explicitly category-enabled test build. The SDK
  ADB reported no connected device for this slice.

No production category request, migration, RPC, Edge Function or deployment
was performed. Remote category-name translation remains a separate slice so
its iOS-equivalent fallback and stale-response guard can be implemented and
tested together; APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-category-push-foundation.md`.

## APK 1 category-name translation parity — 2026-09-23

- [x] Matched the iOS save-first flow: the locale-specific fallback category,
  category cloud mutation and account-scoped translation request are committed
  atomically before the editor dismisses. Translation runs asynchronously and
  creates a second coalesced category mutation only after a usable result.
- [x] Added the existing `translate-category-name` Edge Function client with
  the same `name`/`source_language` request and Vietnamese/English/Japanese
  response contract. Android uses the remote branch because Apple's installed
  Translation framework is not available on Android.
- [x] Added an exact `updated_at` compare-and-apply guard. A response for an
  older name cannot overwrite a later edit or delete its replacement request.
  Failures and unchanged fallbacks remain queued with bounded backoff; auth
  failures can recover after session refresh; cancellation still propagates.
- [x] Added Room schema v2 and migration 1→2 for the category translation
  outbox. Maintenance is owner-scoped, coalesces concurrent runs, infers the
  same Vietnamese/English/Japanese retry source as iOS for older or pulled
  categories with missing names, and never replaces a newer local request.
- [x] Passed 120 Android unit tests across 24 suites, Room migration/
  instrumentation source compilation, lint, debug assembly, contract check
  and both localization checks. The focused Swift package test could not be
  rerun after Xcode began requiring license acceptance; the same 22 Swift
  category/outbox tests passed in the immediately preceding slice.
- [ ] Run migration/Room tests and category create/edit/stale-response UI
  verification on Samsung. ADB reported no connected device.

No live Edge Function call, Supabase write, production migration or deployment
was performed. All cloud-write flags remain `false`; APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-category-translation.md`.

## APK 1 offline credit-card profiles — 2026-09-23

- [x] Added typed `credit_card_profiles` mapping with exact payload fields,
  explicit nulls, signed 64-bit values and all iOS card-network wire values.
- [x] Added owner-scoped offline create/edit of a linked credit-card wallet and
  profile. Room commits both local records and both independent-version outbox
  rows atomically; payment sources must be active, same-owner and non-card.
- [x] Added a dedicated native Compose card editor and management routing for
  issuer/network/last-four, limit/currency, closing/payment days, payment
  source, notes and color. New cards use iOS defaults 10/26.
- [x] Passed 131 Android unit tests across 27 suites, Room instrumentation
  source compilation, lint, debug assembly, contract check and strict iOS/
  Android localization checks.
- [ ] Run the Room test and native create/edit/rotation/dark-mode verification
  on Samsung. ADB reported no connected device.

Card archive remains unavailable until transaction debt and statement data can
enforce the iOS blockers. Credit-limit/debt and payment-source-change debt
guards are deferred for the same reason. Credit-card push is the next separate
domain-gated slice; all cloud-write flags remain `false`, no production write
or deployment occurred, and APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-credit-card-offline.md`.

## APK 1 credit-card push foundation — 2026-09-23

- [x] Added an independent `ALLOW_CREDIT_CARD_CLOUD_WRITES` gate, defaulting to
  `false`, plus a PostgREST allowlist entry and dedicated coordinator. Runtime
  injection additionally requires the wallet gate so profiles cannot be pushed
  before their linked wallet domain is enabled.
- [x] Added owner-scoped profile fetch/create/conditional-update with explicit
  nulls, signed 64-bit values and the shared semantic-ACK/conflict/retry/stale-
  response state machine.
- [x] Verified sync priority as category → wallet → credit-card profile → pull,
  regardless of dependency-injection list order.
- [x] Passed 139 Android unit tests across 29 suites, Room instrumentation
  source compilation, lint, debug assembly, contract check and both localization
  generation checks.
- [ ] Enable wallet + credit-card gates only in a deliberate device-test build,
  then verify create/edit/semantic-ACK/conflict behavior on Samsung. ADB
  reported no connected device.

No live Supabase write, migration, RLS/RPC change or deployment occurred. All
cloud-write flags remain `false`; transaction/FX and receipt parity remain in
APK 1, so APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-23-apk1-credit-card-push-foundation.md`.

## APK 1 transaction and FX typed contract — 2026-09-23

- [x] Added a complete typed `ledger_transactions` cloud record with explicit
  nulls, signed 64-bit money/version fields and exact iOS enum wire values.
- [x] Added ordinary expense/income/internal-transfer mutation rules for owner-
  scoped active dependencies, posted versus draft completeness, category-kind
  matching and credit-card direction restrictions.
- [x] Added exact-decimal cross-currency validation and same-currency stale-FX
  clearing. Family/debt transfers remain rejected until their APK 3 cloud-first
  workflows exist.
- [x] Passed 145 Android unit tests across 30 suites, Room instrumentation
  source compilation, lint, debug assembly, contract check and both localization
  generation checks.
- [ ] Add atomic offline repository/editor flows, then a dependency-ordered and
  separately gated transaction push pipeline. Run all UI/device behavior on
  Samsung when ADB is available.

No transaction cloud-write gate or live production request was added. Existing
cloud-write flags remain `false`; APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-transaction-fx-contract.md`.

## APK 1 offline transaction repository — 2026-09-23

- [x] Added owner-scoped typed transaction observation and offline save through
  the atomic Room record+outbox boundary.
- [x] Added dependency lookup isolation, edit base-version retention and
  explicit null propagation for removed FX fields.
- [x] Replaced raw JSON parsing in the existing transaction list with typed
  transaction/wallet streams and the source-leg amount/currency projection.
- [x] Passed 148 Android unit tests across 31 suites, Room instrumentation
  source compilation, lint, debug assembly, contract and localization checks.
- [x] Added the native create/edit transaction sheet in the next independently
  verified slice.
- [ ] Add current-balance affordability and paid-card-statement validation,
  automatic app-rate lookup, and visual verification on Samsung; ADB reported
  no connected device.

Transaction cloud push and receipt capture/analysis remain later APK 1 slices.
No production write or deployment occurred, and APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-transaction-offline-repository.md`.

## APK 1 native transaction editor — 2026-09-23

- [x] Added a Material 3 create/edit sheet for ordinary expense, income and
  internal transfer records, including native date/time pickers, wallet and
  child-category selection, notes, and exact-decimal cross-currency input.
- [x] Enforced iOS category hierarchy and wallet direction rules at both the UI
  and model boundaries. Family/debt, settlement-owned and archived records stay
  read-only instead of entering an incomplete local flow.
- [x] Connected saves to the owner-scoped atomic Room record+outbox repository;
  all user-facing copy comes from generated String Catalog resources.
- [x] Passed 156 Android unit tests across 32 suites, Room instrumentation
  source compilation, lint, debug assembly, contract and localization checks.
- [x] Added the current-wallet-balance affordability engine in the next
  independently verified slice.
- [x] Added paid credit-card statement guards in a later independently verified
  slice, including a Samsung check against an actual locked transaction.
- [ ] Add automatic app-rate resolution before claiming full iOS transaction
  parity.

No transaction cloud push, live Supabase write or deployment occurred. All
cloud-write flags remain `false`; receipt work and the remaining transaction
rules keep APK 1 incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-transaction-editor.md`.

## APK 1 transaction affordability — 2026-09-23

- [x] Ported the iOS wallet-balance index: non-card wallets seed from opening
  balance, cards seed at zero debt, and all posted/non-archived transactions
  contribute regardless of entered date.
- [x] Enforced current-balance affordability for expense and internal-transfer
  outflows. Editing excludes the replaced record, so it validates the proposed
  amount against the wallet state before that record.
- [x] Enforced credit-card available credit from the linked profile limit minus
  current debt; transfer payments into cards reduce debt using the destination
  amount for cross-currency transfers.
- [x] Passed 164 Android unit tests across 33 suites, Room instrumentation
  source compilation, lint, debug assembly, contract and localization checks.
- [x] Passed the focused Room transaction instrumentation test directly on
  Samsung `SM-F776Q` and opened the authenticated native transaction editor.
- [x] Added paid statement-period locks in a later independently verified slice.
  Preserve iOS investment-fund confirmation semantics when APK 4 adds the
  corresponding Android investment write flows.

A Samsung `SM-F776Q` connected during verification. After the user explicitly
allowed replacing the old debug install, that package was uninstalled and this
slice's APK installed successfully. After registering this Mac's debug SHA-1,
device logs proved Google token retrieval and Supabase exchange success. The
signed-in transaction list showed pulled cloud records, and the localized native
editor rendered without crash or overflow at 1080×2520. No transaction was
submitted during the visual check.

The focused `TransactionRoomTest` passed on the Samsung. The unfiltered 12-test
database instrumentation run also exposed one separate known test-fixture gap:
`MistiaDatabaseMigrationTest` lacks the packaged `MistiaDatabase/1.json` Room
schema asset. That unrelated failure remains visible and is not claimed fixed by
this slice.

All cloud-write flags remain `false`; no production write or deployment
occurred, and APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-transaction-affordability.md`.

## APK 1 transaction push foundation — 2026-09-23

- [x] Added a transaction-domain coordinator on the shared outbox push engine,
  preserving create/update versioning, semantic acknowledgement, conflicts,
  retries and stale-response protection.
- [x] Enforced dependency ordering: category, wallet and credit-card profile
  mutations run before `ledger_transactions`; pull starts only afterward.
- [x] Added a separately gated PostgREST transaction write allowlist. The
  transaction path also requires category and wallet write gates, and every
  gate remains `false` in the generated debug build.
- [x] Verified 168 unit tests across 34 suites, Room Android-test compilation,
  lint, debug assembly, contract and localization checks.
- [x] Installed the new APK with `adb install -r` on Samsung `SM-F776Q`; app
  data/session remained intact and authenticated cold launch rendered without
  crash.

No live Supabase write, migration, RLS/RPC change or deployment occurred.
Automatic app-rate resolution and receipt capture/analysis remain APK 1 work;
APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-23-apk1-transaction-push-foundation.md`.

## APK 1 paid credit-card statement guards — 2026-09-23

- [x] Ported the iOS paid-statement lock for credit-card expenses using the
  statement month, card closing day, posted charges and covering payment.
- [x] Preserved direct paid-occurrence links and the legacy localized card
  payment-title fallback used by iOS.
- [x] Enforced the lock in the owner-scoped repository before any Room/outbox
  mutation, for both edits and new expenses inserted into a closed cycle.
- [x] Marked locked rows with the existing localized explanation and disabled
  entry into the native editor.
- [x] Verified 177 unit tests across 35 suites, Room Android-test compilation,
  lint, debug assembly, contract and localization checks.
- [x] Installed the APK on Samsung `SM-F776Q`; an actual paid-statement row
  rendered the lock explanation and ignored a tap without opening the editor.

No live Supabase write, migration, RLS/RPC change or deployment occurred. All
cloud-write gates remain disabled, and APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-paid-statement-guards.md`.

## APK 1 automatic transaction exchange rate — 2026-09-23

- [x] Added the iOS-equivalent JPY/VND Frankfurter snapshot contract, direct
  and inverse exact-decimal conversion, `HALF_UP` minor-unit rounding and
  overflow/invalid-rate rejection.
- [x] Added a SharedPreferences-backed repository that exposes the last good
  rate immediately, validates responses before atomic replacement and refreshes
  at most once per local day after 07:00. Cache commits run off the caller
  thread and coroutine cancellation is preserved.
- [x] Enabled App rate in the native transaction editor. Destination amount,
  decimal rate, provider and rate date are derived from the current snapshot;
  refreshed snapshots cannot leave display and saved draft out of sync.
  Manual conversion and same-currency metadata clearing remain intact.
- [x] Verified 194 Android unit tests across 37 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check, Android
  localization generation and strict iOS localization code generation.
- [x] Final-artifact Samsung verification was skipped under the user's current
  direction because no Samsung is connected. An earlier pre-final diagnostic
  build fetched and persisted a real `JPY/VND=164.77` Frankfurter snapshot,
  but that observation is not claimed as the final APK device gate.

No Supabase schema, RLS/RPC, Edge Function, production write or deployment was
changed. All cloud-write flags remain `false`. Receipt capture/analysis and
other unfinished APK 1 workflows remain, so APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-23-apk1-automatic-exchange-rate.md`.

## APK 1 receipt AI client foundation — 2026-09-24

- [x] Added the typed Android contract for the existing itemized receipt Edge
  Function, including literal OCR rows, purchase/discount arithmetic, candidate
  IDs, multiple-bill state and daily quota metadata.
- [x] Added an authenticated `analyze-bill-items` client using the configured
  client key in `apikey` and the signed-in user JWT in `Authorization`. The
  transport has AI-appropriate 170/180-second timeouts and cancellable OkHttp
  execution.
- [x] Added tolerant numeric decoding and candidate validation while preserving
  raw OCR text. Typed failures distinguish auth, request, media, size, quota,
  upstream, malformed-response and network cases without exposing raw error
  bodies or credentials.
- [x] Verified 209 Android unit tests across 39 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check, Android
  localization generation and strict iOS localization code generation.
- [ ] Connect CameraX/Photo Picker image acquisition and preprocessing, then
  add the native itemized review/apply flow and transaction persistence.
- [ ] Run the final receipt flow and its artifact on Samsung when device
  verification resumes. Per the user's current direction, absence of a Samsung
  does not block local slice development.

No live Gemini/Supabase function invocation, production write, schema, RLS/RPC,
Edge Function deployment or cloud-write gate change occurred. All cloud-write
flags remain `false`; APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-ai-client.md`.

## APK 1 receipt image preparation policy — 2026-09-24

- [x] Ported the iOS itemized-bill image budget into a platform-neutral,
  cancellable Android contract: 3,000 px analysis image, JPEG quality descent,
  0.86 dimension retries down to the 900 px OCR floor and a 3.8 MB ceiling.
- [x] Added deterministic thumbnail generation policy at 240 px/0.68 quality
  and typed decode/dimension/scale/encode/too-large failures.
- [x] Kept bitmap decoding, orientation correction and opaque white rendering
  behind a codec boundary so the next Android framework slice can be tested
  independently from the sizing algorithm.
- [x] Verified 217 Android unit tests across 40 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Implement the Android bitmap/URI codec, then connect Photo Picker and
  CameraX before exposing receipt analysis in the native UI.

No cloud call, production write, localization change or device claim occurred.
Samsung verification remains deferred per the user's current direction, and
APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-image-preparation.md`.

## APK 1 Android receipt bitmap and URI codec — 2026-09-24

- [x] Added a concrete Android receipt-image loader for `content://`/URI input,
  with a 24 MiB streaming source cap before decode.
- [x] Added bounds-first power-of-two bitmap sampling, EXIF orientation
  normalization, opaque white-background rendering, scaling and JPEG encoding
  behind the existing preparation policy.
- [x] Added deterministic recycling of every decoded/rendered native bitmap on
  success, failure and cancellation paths.
- [x] Verified 222 Android unit tests across 41 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Connect this loader to Photo Picker and CameraX, then implement the native
  review/apply flow. Device visual verification remains deferred.

No cloud call, production write, localization change or Samsung claim occurred.
All cloud-write gates remain `false`; APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-android-codec.md`.

## APK 1 receipt Photo Picker foundation — 2026-09-24

- [x] Added an Android system Photo Picker control that chooses the single- or
  multi-image contract from the remaining five-image capacity and requests
  image media without broad storage permission.
- [x] Connected selected content URIs directly to the bounded bitmap/preparation
  pipeline while the temporary grants are valid. Processing is lifecycle-bound
  and preserves coroutine cancellation.
- [x] Preserved picker order and partial success: one unreadable/oversized image
  does not discard other valid selections, while excess selections are
  reported instead of decoded.
- [x] Verified 227 Android unit tests across 42 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Add CameraX capture, then expose both sources only through the complete
  native itemized review/apply flow. Device Photo Picker verification remains
  deferred.

The reusable picker is not shown in the ordinary transaction editor because
receipt attachment persistence is not implemented there. No picker was opened
on-device, no cloud call/write/deployment occurred, and all cloud-write gates
remain `false`; APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-photo-picker.md`.

## APK 1 receipt CameraX foundation — 2026-09-24

- [x] Added stable CameraX 1.6.2 preview/capture dependencies and a native
  lifecycle-bound back-camera sheet using `PreviewView`, `ImageCapture` and
  `ProcessCameraProvider`.
- [x] Added hardware-first camera entry, runtime permission handling and typed
  permission/unavailable/bind/capture failure outcomes for the future receipt
  analysis screen.
- [x] Captured quality-oriented JPEGs into isolated app cache, routed them
  through the shared EXIF/bitmap preparation pipeline and deleted every
  temporary file on success, failure, cancellation or sheet disposal.
- [x] Verified 232 Android unit tests across 43 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Build and route the native itemized analysis/review/apply flow that owns
  both Photo Picker and CameraX controls. Physical capture verification remains
  deferred.

No camera was opened on-device, no receipt was analyzed or persisted, and no
cloud call/write/deployment occurred. All cloud-write gates remain `false`;
APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-camerax.md`.

## APK 1 receipt analysis coordinator — 2026-09-24

- [x] Added the iOS-parity request builder for prepared receipt images,
  including Base64/MIME data, locale/time zone/target language, active
  owner-scoped child expense categories with localized hierarchy names, active
  owner-scoped wallets and the JPY fallback currency.
- [x] Excluded balance-adjustment categories and the deterministic
  investment-profit wallet from AI candidates while preserving configured
  category/wallet order.
- [x] Added one-refresh-token sequential batch analysis with ordered per-bill
  partial success, typed authentication failure before transport and strict
  coroutine cancellation propagation.
- [x] Verified 236 Android unit tests across 44 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Route the coordinator through a native analysis/review state and screen,
  then implement reviewed item persistence as transactions.
- [ ] Run the completed receipt flow on Samsung when device verification
  resumes. Per the user's current direction, its absence does not block local
  slice development.

No live Edge Function/Gemini call, receipt/transaction persistence, production
write, migration, deployment or cloud-write gate change occurred. All five
cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-analysis-coordinator.md`.

## APK 1 receipt review state — 2026-09-24

- [x] Added a stable-ID review session for up to five prepared receipt images,
  ordered pending-only analysis batches and transient-work dismiss protection.
- [x] Added ordered partial-result application with live category/wallet ID
  validation, per-bill typed failure/quota state and multiple-receipt blocking.
- [x] Preserved literal OCR review evidence, including `3@` quantity notation
  and a standalone coupon discount row, without merging or reordering rows.
- [x] Added isolated retry and remove transitions that preserve prepared image
  identity and do not disturb sibling bills.
- [x] Verified 240 Android unit tests across 45 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Build and route the Compose analysis/review screen using this state,
  Photo Picker, CameraX and the analysis coordinator; reviewed transaction
  apply/persistence remains separate follow-up work.

No live AI call, receipt/transaction persistence, production write, migration,
deployment or cloud-write gate change occurred. Samsung verification remains
deferred and all five cloud-write flags remain `false`; APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-review-state.md`.

## APK 1 native receipt review UI — 2026-09-24

- [x] Composed Photo Picker, CameraX, image preparation, authenticated analysis
  and review state into one native Material 3 receipt-analysis sheet.
- [x] Added per-bill thumbnail/result/error rendering, literal OCR/quantity/
  discount rows, typed failure messages, multiple-receipt blocking and targeted
  reanalysis/removal.
- [x] Added active-analysis dismissal protection and confirmation before
  discarding any acquired/reviewed image state.
- [x] Reused generated String Catalog resources throughout and verified 241
  Android unit tests across 45 suites, Room Android-test compilation, lint,
  debug assembly, the 15-entity contract check and Android/strict iOS
  localization code generation.
- [ ] Add editable item review and reviewed transaction apply/persistence, then
  route the complete sheet from Transactions. Keeping the current read-only
  sheet internal avoids exposing a dead-end workflow.

No live AI request, receipt/transaction persistence, production write,
migration, deployment, emulator/device visual check or cloud-write gate change
occurred. Samsung verification remains deferred and all five cloud-write flags
remain `false`; APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-review-ui.md`.

## APK 1 receipt item selection contract — 2026-09-24

- [x] Ported iOS item selection rules for expense and lend modes: one wallet,
  same purchase category for expense, standalone discount compatibility and
  exclusion of created/locked/unavailable/zero rows.
- [x] Added exact minor-unit quantity allocation, normalized mode changes and
  locked groups that reject nonpositive totals.
- [x] Added expense/debt-lend transaction-prefill semantics for amount,
  category, merchant, occurred date and single-bill receipt attachment.
- [x] Verified 247 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind item editing/selection/group confirmation into the review sheet and
  persist supported reviewed drafts before routing the flow.

No transaction was persisted, no live AI/production request was sent and no
migration, deployment, device claim or cloud-write gate change occurred.
Samsung verification remains deferred and all five flags remain `false`; APK 1
is not complete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-item-selection.md`.

## APK 1 receipt review arithmetic — 2026-09-24

- [x] Ported purchase/discount review validation and exact final-amount
  recomputation, including targeted missing-field cleanup.
- [x] Ported proportional standalone-discount allocation with exact minor-unit
  quotient/remainder handling, deterministic row-order tie-break and preserved
  discount-row identity/literal OCR.
- [x] Verified 250 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind these correction operations and item selection to Compose editors,
  then persist supported reviewed transaction drafts and route the full flow.

No UI edit, receipt/transaction persistence, live AI/production call,
migration, deployment, device claim or cloud-write gate change occurred.
Samsung verification remains deferred and all five flags remain `false`; APK 1
is not complete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-review-arithmetic.md`.

## APK 1 receipt review mutations — 2026-09-24

- [x] Added immutable bill-scoped transitions for wallet, payable total,
  category, reviewed item replacement, proportional discount allocation and
  explicit item removal.
- [x] Preserved sibling bills, result metadata, full raw OCR and literal row text
  through a concrete `3@` purchase plus standalone Japanese coupon edit chain.
- [x] Verified 251 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind these transitions to native editors and item selection, then open the
  existing transaction editor with the reviewed prefill and route the flow.

No transaction/image persistence, live AI/production call, migration,
deployment, device claim or cloud-write gate change occurred. Samsung remains
deferred and all five flags remain `false`; APK 1 is not complete.

Evidence: `docs/android/evidence/2026-09-24-apk1-receipt-review-mutations.md`.

## APK 1 receipt selection projection — 2026-09-24

- [x] Projected ordered review bills/items into stable selection candidates with
  wallet/category/merchant/date metadata and exact partial-quantity amounts.
- [x] Added whole-line toggle semantics with same-bill enforcement and shared
  wallet/category/discount normalization.
- [x] Verified 253 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Render selection controls, open the native transaction editor with the
  reviewed prefill, mark saved allocations and route the complete flow.

No transaction/image persistence, live AI/production call, migration,
deployment, device claim or cloud-write gate change occurred. Samsung remains
deferred and all five flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-selection-projection.md`.

## APK 1 receipt transaction prefill bridge — 2026-09-24

- [x] Added a currency-aware bridge from a supported receipt expense draft to
  the existing native transaction editor, preserving merchant, exact amount,
  date, wallet and child expense category.
- [x] Added optional initial editor state without changing ordinary new/edit
  behavior or restored-state precedence.
- [x] Kept debt-lend drafts outside persistence because the current Android
  repository does not support debt-transfer semantics.
- [x] Verified 255 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind reviewed selection to the sheet and route supported expense prefills
  from Transactions; debt/lend and receipt image persistence remain later work.

No transaction/image was persisted, no live AI/production request was sent and
no migration, deployment, device claim or cloud-write gate change occurred.
Samsung remains deferred and all five flags remain `false`; APK 1 is not
complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-transaction-prefill.md`.

## APK 1 receipt selection and editor routing — 2026-09-24

- [x] Exposed the native AI Bill sheet from Transactions with the injected
  receipt client and refreshed signed-in access token.
- [x] Added native checkbox selection constrained to one reviewed bill, wallet
  and purchase category while preserving compatible standalone discounts.
- [x] Added a guarded expense-draft action that rejects flagged/cross-bill
  selections and opens the native transaction editor with reviewed data
  prefilled for the existing offline save path.
- [x] Verified 257 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Add editable total/wallet/category/item review controls and receipt-image
  persistence. Debt/lend remains blocked until its repository contract exists.

No live AI/production request, production write, migration or deployment
occurred. `adb` is not installed on this host, so no emulator/Samsung UI claim
is made. All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-selection-routing.md`.

## APK 1 receipt wallet/category review — 2026-09-24

- [x] Added native wallet and purchase-category menus using the same ordered,
  active, owner-scoped, localized candidates supplied to receipt analysis.
- [x] Excluded archived/deleted/system-only records consistently and kept
  discount rows uncategorized.
- [x] Invalidated only target-bill selection after a wallet/category correction
  so stale grouping cannot be applied while sibling selection survives.
- [x] Verified 259 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Add receipt-total and item-fact editors plus discount allocation, then
  persist receipt images and implement the debt/lend path.

No live AI/production request, production write, migration or deployment
occurred. `adb` remains unavailable, so no emulator/Samsung UI claim is made.
All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-wallet-category-review.md`.

## APK 1 receipt total editor — 2026-09-24

- [x] Added a native printed-total editor with generated localized copy and
  currency-aware initial formatting.
- [x] Reused the transaction editor's exact minor-unit parser: valid currency
  precision maps without rounding, while zero/negative/excess precision is
  rejected.
- [x] Updated only the target bill and invalidated only its stale selection.
- [x] Verified 261 Android unit tests across 46 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Add item-fact editing and discount allocation controls, then receipt-image
  persistence and the debt/lend path.

No live AI/production request, production write, migration or deployment
occurred. `adb` remains unavailable, so no emulator/Samsung UI claim is made.
All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-total-editor.md`.

## APK 1 receipt item editor contract — 2026-09-24

- [x] Added an immutable item-editor draft seeded from analyzed receipt facts,
  with exact currency-aware amount formatting/parsing and explicit purchase or
  standalone-discount normalization through the shared reviewed-item model.
- [x] Preserved literal OCR evidence while allowing reviewed names, translation,
  quantity and amounts to change; invalid names, quantities, precision,
  over-discounting and zero discounts cannot enter review state.
- [x] Added target-bill item replacement that invalidates only that bill's
  stale row selection while preserving sibling bill identity and selection.
- [x] Verified 266 Android unit tests across 47 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind this contract to the native item editor and add discount-allocation
  controls, then receipt-image persistence and the debt/lend path.

No live AI/production request, production write, migration or deployment
occurred. `adb` remains unavailable, so no emulator/Samsung UI claim is made.
All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-item-editor-contract.md`.

## APK 1 native receipt item editor — 2026-09-24

- [x] Bound every analyzed row to a scrollable native Material 3 editor for
  original/translated names, purchase/discount type, quantity and exact row
  amounts, using generated String Catalog resources throughout.
- [x] Kept literal printed OCR visible and immutable, showed the recomputed
  final amount, and disabled Save until the tested item-review contract accepts
  the complete draft.
- [x] Added reviewed row replacement and deletion paths that invalidate only
  the edited bill's selection while leaving sibling bills untouched.
- [x] Verified 267 Android unit tests across 47 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Add proportional discount-allocation controls, then receipt-image
  persistence and the debt/lend path.

No live AI/production request, production write, migration or deployment
occurred. `adb` remains unavailable, so no emulator/Samsung UI or dark-mode
visual claim is made. All five cloud-write flags remain `false`; APK 1 is not
complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-item-editor-ui.md`.

## APK 1 receipt discount allocation control — 2026-09-24

- [x] Added the native proportional-allocation action only when a standalone
  discount can be distributed across positive purchase rows.
- [x] Reused the exact minor-unit allocator with deterministic remainder order;
  allocated discount rows become zero and render a localized allocated state.
- [x] Rejected ineligible allocation without changing state or selection, and
  invalidated only the target bill's selection after a valid allocation.
- [x] Verified 269 Android unit tests across 47 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Persist receipt images for reviewed expense transactions, then implement
  the debt/lend path and remaining APK 1 closure checks.

No live AI/production request, production write, migration or deployment
occurred. `adb` remains unavailable, so no emulator/Samsung UI claim is made.
All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-discount-allocation-control.md`.
