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

## APK 1 local receipt-image persistence foundation — 2026-09-24

- [x] Added a local receipt-image repository matching iOS's file-plus-metadata
  design, with private app-files storage for full JPEG and thumbnail data.
- [x] Added Room metadata schema v3 and an explicit 2→3 migration, unique
  transaction ownership, owner-scoped cleanup and generated schema evidence.
- [x] Protected replacement failure: new files are cleaned while the previous
  metadata/files remain readable; successful replacement removes superseded
  files, and delete removes both files and metadata.
- [x] Registered the repository in Hilt and verified 273 Android unit tests
  across 48 suites, Room Android-test compilation, lint, debug assembly, the
  15-entity contract check and Android/strict iOS localization code generation.
- [ ] Attach the selected bill image during the same expense-editor save,
  surface saved-receipt preview/removal in the editor, then implement debt/lend.

No receipt was attached to a transaction yet, no live AI/production request or
cloud write occurred, and no production database migration/deployment ran.
`adb` remains unavailable, so the Room migration and files were not exercised
on a device. All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-image-persistence-foundation.md`.

## APK 1 analyzed-receipt save flow — 2026-09-24

- [x] Routed the exact source bill image selected by the reviewed item group
  into the expense editor; another bill's image cannot be substituted.
- [x] Preassigned one transaction UUID and persisted the prepared JPEG and
  thumbnail before saving the transaction with that same UUID, matching iOS's
  receipt-before-context-save ordering without creating a duplicate on retry.
- [x] Prevented transaction persistence when receipt persistence fails and
  best-effort removed the newly persisted receipt when transaction saving
  fails, preserving the original transaction error and attaching cleanup
  failure as suppressed diagnostic context.
- [x] Wired the receipt repository through Hilt into the native transaction
  screen and cleared pending image state when the editor is dismissed or a
  normal new/edit flow starts.
- [x] Preserved the receipt-required marker across Activity recreation, so a
  restored editor whose in-memory image is unavailable refuses to save instead
  of silently creating a receipt-less transaction.
- [x] Propagated coroutine cancellation after compensating receipt cleanup in
  `NonCancellable`, including the ambiguous receipt-persistence boundary.
- [x] Verified 281 Android unit tests across 49 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Add saved-receipt preview/removal to the editor, then implement the
  receipt debt/lend path and remaining APK 1 closure checks.

No live AI/production request, cloud write, migration or deployment occurred.
`adb` remains unavailable, so the save flow and local files were not exercised
on an Android device. All five cloud-write flags remain `false`; APK 1 is not
complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-image-save-flow.md`.

## APK 1 receipt editor state contract — 2026-09-24

- [x] Added a typed editor state that distinguishes a new analyzed receipt
  from an already stored receipt and exposes one preview payload for either.
- [x] Removing a new pending receipt clears the create requirement without
  scheduling storage deletion; removing a stored receipt schedules an
  idempotent delete-on-save mutation.
- [x] Kept the saveable missing-image guard: restored pending state without
  its large in-memory bytes still refuses a silent receipt-less create.
- [x] Added transaction-first stored-receipt deletion, so a transaction-save
  failure leaves its existing receipt untouched and a deletion failure remains
  visible/retryable.
- [x] Isolated mutable image bytes between source, preview and save payload;
  preview equality/hash use byte content rather than array identity.
- [x] Verified 291 Android unit tests across 50 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind this contract to native thumbnail/full preview, saved-receipt load
  and remove controls in the transaction editor.

No UI claim, live AI/production request, cloud write, migration or deployment
occurred. `adb` remains unavailable. All five cloud-write flags remain `false`;
APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-editor-state-contract.md`.

## APK 1 native saved-receipt preview and removal — 2026-09-24

- [x] Loaded stored receipt metadata, full image and prepared thumbnail when an
  existing transaction editor opens, while skipping file reads when no receipt
  metadata exists.
- [x] Added a native Material 3 thumbnail, localized file size/error states and
  a tap-through full-image dialog; full-image bitmap decoding runs off the main
  dispatcher.
- [x] Bound explicit removal for both pending and stored receipts. Stored data
  is deleted only after the edited transaction saves successfully; saving
  without pressing Remove leaves the stored receipt untouched.
- [x] Preserved only semantic flags across Activity recreation, never image
  bytes. Pending missing bytes still block save, while stored/delete intent is
  restored and the stored preview can be reloaded.
- [x] Kept a corrupt or missing stored image removable by preserving metadata
  presence even when file loading fails; coroutine cancellation is propagated.
- [x] Verified 296 Android unit tests across 50 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Implement the receipt debt/lend path and remaining APK 1 closure checks.

No emulator/Samsung UI or dark-mode visual claim is made because `adb` is not
available. No live AI/production request, cloud write, migration or deployment
occurred. All five cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-receipt-preview-removal-ui.md`.

## APK 1 offline debt-lend foundation — 2026-09-24

- [x] Added typed offline `transfer/debt/lend` persistence with a required
  source wallet and counterparty, derived normalized counterparty key, explicit
  nulls for destination/category/FX fields and the existing atomic record+
  outbox commit boundary.
- [x] Matched the iOS counterparty fold across compatibility-width, case,
  diacritics and repeated punctuation/separators while preserving the trimmed
  display name, including dotless-I, sharp-S, final-sigma and Greek
  iota-subscript vectors checked against Foundation.
- [x] Limited this foundation to standalone posted lending: non-posted debt and
  settlement-owned records are rejected, while edits explicitly clear stale
  reporting, settlement, destination, category and FX fields.
- [x] Applied current wallet balance to cash lending and available credit to
  credit-card lending regardless of the entered transaction date.
- [x] Included credit-card lending in paid-statement protection, including a
  proposed new lend that would change an already covered statement.
- [x] Kept `borrow`, `collect`, `repay` and family transfer unsupported by this
  bounded create contract rather than silently persisting partial semantics.
- [x] Verified 304 Android unit tests across 50 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [ ] Bind the reviewed receipt Lend selection to the native debt editor with
  counterparty input and exact receipt attachment/save completion semantics.

No live cloud write, migration or deployment occurred. `adb` remains
unavailable, so no emulator/Samsung behavior claim is made. All five
cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-24-apk1-offline-debt-lend-foundation.md`.

## APK 1 receipt Lend editor routing — 2026-09-25

- [x] Added native Expense/Lend mode selection to receipt review and reused the
  existing mode-normalization contract so Lend accepts mixed categories while
  still enforcing one bill and one wallet.
- [x] Generalized the guarded review projection and editor bridge for
  `transfer/debt/lend`, resolving the exact selected bill image before the
  create action can open the editor.
- [x] Added debt intent and counterparty to saveable editor state. A receipt
  Lend opens as a locked Lend context, permits credit-card source wallets,
  requires a normalizable counterparty and emits no destination/category/FX.
- [x] Enabled native editing only for standalone posted Lend records without
  settlement ownership; family transfer and other debt intents remain outside
  this bounded editor contract.
- [x] Reused the receipt-first save coordinator and shared transaction UUID, so
  Lend has the same attachment failure, compensation and lifecycle guard as
  reviewed Expense creation.
- [x] Verified 307 Android unit tests across 50 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation.
- [x] Bind iOS-style locked allocation groups and created-allocation completion
  state to the Compose receipt review before closing APK 1.

No live AI/cloud write, migration or deployment occurred. `adb` remains
unavailable, so no emulator/Samsung UI or dark-mode claim is made. All five
cloud-write flags remain `false`; APK 1 is not complete.

Evidence:
`docs/android/evidence/2026-09-25-apk1-receipt-lend-editor-routing.md`.

## APK 1 receipt allocation groups and completion — 2026-09-25

- [x] Added native partial-quantity selection (`x1...xN`) and exact remaining
  quantity/minor-unit projection after locked or created allocations.
- [x] Replaced direct editor launch with iOS-parity confirmed allocation groups.
  Each group retains its Expense/Lend mode, exact item allocations and total.
- [x] Added locked-group rows with cancel and create actions. Cancel restores
  availability without creating anything; opening then canceling the editor
  keeps the group available for retry.
- [x] Kept the receipt review session underneath the transaction editor and
  mark a group created only after receipt plus transaction persistence returns
  success. Save failure and editor cancellation do not advance allocation
  state.
- [x] Disabled incompatible receipt revision actions after a group is locked or
  created, and exposed localized Locked/Created row state with exact remaining
  amounts.
- [x] Verified 311 Android unit tests across 50 suites, Room Android-test
  compilation, lint, debug assembly, the 15-entity contract check and Android/
  strict iOS localization code generation. Independent review reported no
  Critical, Important or Minor finding.
- [x] Audit the complete APK 1 checklist against the current iOS contracts and
  close any remaining local gap before moving to APK 2.

No live AI/cloud write, migration or deployment occurred. `adb` remains
unavailable, so the stacked receipt/editor sheets, quantity menu, allocation
states and dark-mode presentation are not claimed as device-verified. All five
cloud-write flags remain `false`; APK 1 closure still requires the explicit
parity audit.

Evidence:
`docs/android/evidence/2026-09-25-apk1-receipt-allocation-completion.md`.

## APK 1 local closure audit — 2026-09-25

- [x] Audited the gate against `contracts/feature-parity.yml`, the current iOS
  reference behavior, Android repositories/editors/push coordinators and the
  complete APK 1 evidence chain.
- [x] Confirmed local implementation for wallets, credit-card profiles,
  category hierarchy/translation, expense/income/internal transfer, gated
  standalone receipt Lend, affordability, paid-statement protection,
  multi-currency app/manual rates and receipt capture/analyze/review/persist.
- [x] Confirmed scope boundaries: statements/payments, due maintenance and
  notifications remain APK 2; family transfer, other debt intents and
  settlement remain APK 3; investment-backed transaction semantics remain APK
  4. These are not APK 1 closure gaps.
- [x] Promoted only the APK 1 contract status from `planned` to
  `build_verified_device_pending`. `writes_enabled` is explicitly `false` and
  every generated domain flag remains `false`; this is not a production-write
  or physical-device claim.
- [x] Reused the immediately preceding final gate: 311 JVM tests across 50
  suites, Room Android-test compilation, lint, debug APK assembly, 15-entity
  contract check and Android/strict iOS localization generation all passed.
- [ ] Begin APK 2 with the first dependency-bounded planning domain slice.

No Samsung/emulator is connected (`adb` is unavailable), which the user has
explicitly asked not to block continued implementation on. No live receipt AI
request, Supabase write, migration or deployment occurred. APK 1 is locally
build-verified and device verification remains pending rather than waived as
evidence.

Evidence:
`docs/android/evidence/2026-09-25-apk1-local-closure-audit.md`.

## APK 2 budget typed contract — 2026-09-25

- [x] Added the typed budget-plan cloud record for all shared schema fields,
  explicit JSON nulls, signed-64 minor units/versioning and strict UUID/UTC
  decoding.
- [x] Matched iOS required/optional decoding: malformed or missing required
  fields fail, the legacy family-spending flag alone defaults to `false`, and
  empty optional snapshot strings remain lossless.
- [x] Added frozen-category allocation snapshots and parent/child limit
  validation scoped by branch and local calendar month, with edit exclusion.
- [x] Used exact arithmetic for allocation sums so overflow cannot turn an
  invalid allocation into a valid one; only displayed error totals are clamped.
- [x] Verified 318 JVM tests across 51 suites, Room Android-test compilation,
  lint, debug assembly, the 15-entity contract check and Android/strict iOS
  localization code generation. Final independent review reported no finding.
- [ ] Add the offline Room/outbox budget repository on top of this contract.

No production cloud request/write, migration or deployment occurred. `adb`
remains unavailable, so no emulator/Samsung behavior is claimed. All five
cloud-write flags remain `false`; APK 2 remains incomplete.

Evidence:
`docs/android/evidence/2026-09-25-apk2-budget-typed-contract.md`.

## Shared localization baseline repair — 2026-10-13

- [x] Restored Android and strict Swift localization checks after starting
  HEAD 82a9313 added two invalid automatically extracted catalog keys.
- [x] Removed only the empty/untranslated entries; existing translations,
  generated output and iOS runtime source are unchanged.

Evidence: `docs/android/evidence/2026-10-13-localization-baseline-repair.md`.
APK 2–4 remain incomplete; all financial cloud-write gates remain disabled.

## APK 2 offline budget repository — 2026-10-13

- [x] Added owner-scoped typed budget observation and local create/edit/archive/
  tombstone delete through atomic Room record+outbox batches.
- [x] Matched iOS localized category snapshots, monthly duplicate/allocation
  validation, carried-forward new-record editing and automatic parent creation.
- [x] Preserved remote base versions and currency, explicit nullable clears,
  selected-month family-scope propagation and final-current-budget scope reset.
- [x] Added viewer-envelope/payload-owner isolation and exact-overflow regressions;
  reproduced and fixed all independent review findings using RED/GREEN tests.
- [x] Verified 332 JVM tests across 52 suites, Room Android-test compilation
  and APK assembly, lint, app APK assembly, contract/localization checks and
  52 focused Swift PlanningLogic tests.
- [ ] Add separately gated budget push, including conditional tombstone deletes,
  then native budget rows/editor before moving to savings.

Artifact versionCode 4; all financial cloud-write flags remain false. Emulator
installation failed as its connection disappeared; no instrumentation execution,
emulator UI or Samsung claim is made. No production request/write/deployment.

Evidence: `docs/android/evidence/2026-10-13-apk2-budget-offline.md`.

## APK 2 budget push foundation — 2026-10-13

- [x] Added separately disabled budget gate at coordinator and PostgREST boundaries,
  dependency ordering and selected-category outbox deferral.
- [x] Added iOS conditional tombstone delete semantics, remote missing/deleted
  ACK, conditional races, winners, stale response protection and durable conflicts.
- [x] Guarded remote identity, version overflow and semantic ACK deletion state;
  reproduced/fixed the independent review finding with RED/GREEN tests.
- [x] Verified 363 JVM tests across 54 suites, Room instrumentation compilation,
  lint/APK assembly, contract/localization checks and 14 focused Swift sync tests.
- [x] Ran BudgetRoomTest directly on API36 emulator: 2/2 passed, including atomic
  rollback and auto-parent/account-scope persistence from the preceding slice.
- [ ] Add native budget rows/month projection and editor, then continue savings.

APK versionCode 5; all six cloud-write flags remain false. No Samsung or budget
UI verification, live Supabase budget write, migration or deployment claim.

Evidence: `docs/android/evidence/2026-10-13-apk2-budget-push.md`.

## APK 2 native budget workflow — 2026-10-13

- [x] Monthly hierarchy/spending/FX/pace projection and native budget editor,
  shared category icons, frozen localization and legacy hierarchy fallback.
- [x] Exact input, owner-scoped restoration, category recent/favorites/search,
  save-failure retention, dismiss guard and archive/delete confirmations.
- [x] User-approved one currency per branch: repository rejects conflicts,
  including carried-forward and future budgets; form inherits branch currency.
- [x] 387 JVM tests/56 suites, 52 Swift planning tests, Room/test APK compilation,
  lint/app assembly and contract/localization checks passed.
- [ ] Execute compiled Compose workflow tests and visual QA when ADB returns;
  no device is currently connected. Final reviewer was usage-limited after
  reporting future-currency finding; its regression is fixed and green.
- [ ] Continue savings, then remaining APK 2–4 domains; full parity not complete.

VersionCode 6, all six write flags false; no production writes/deployment.
Evidence: `docs/android/evidence/2026-10-13-apk2-budget-ui.md`.

## APK 2 savings typed contract — 2026-10-13

- [x] Complete typed RemoteSavingsGoal wire record, explicit nullable fields,
  signed Long money/version and strict scalar/UUID/instant decoding.
- [x] Owner-scoped goal rows with inclusive target month, exact monthly ceiling
  and progress/date/name ordering, avoiding Double precision and overflow.
- [x] 392 JVM tests/57 suites, 52 Swift planning tests, Room compilation,
  lint/build and contract/localization checks passed.
- [ ] Add savings offline repository, gated push, summary and native workflow.

All six write gates false; no device/production verification claim.
Evidence: `docs/android/evidence/2026-10-13-apk2-savings-contract.md`.

## APK 2 savings offline repository — 2026-10-13

- [x] Scoped typed create/edit/delete with atomic record/outbox, original currency/
  timestamps/version, wallet clear/preferred archive access and stale edit guard.
- [x] Payload owner/identity validation, UUID normalization, exact sort overflow,
  cancellation propagation and storage failure regressions.
- [x] 401 JVM tests/58 suites, 52 Swift planning tests, Room test APK compilation,
  lint/build and contract/localization checks passed.
- [ ] Execute savings file-backed Room reopen test when ADB returns; no device.
- [ ] Continue separately gated savings push and native rows/editor/summary.

VersionCode 7, all six write gates false; no production writes/deployment.
Evidence: `docs/android/evidence/2026-10-13-apk2-savings-offline.md`.

## APK 2 savings push foundation — 2026-10-13

- [x] Separately disabled savings gate at coordinator/network, linked-wallet
  dependency barrier and priority60 ordering before pull.
- [x] Conditional upsert/tombstone races, ACK/conflict/retry/cancellation and
  replacement mutation protection using full typed savings payloads.
- [x] Fixed ISO8601 target-date semantic equality via comparison-only normalizer;
  wire/storage representations stay lossless, other domains unchanged.
- [x] 434 JVM tests/60 suites, 14 Swift sync tests, Room compilation, lint/build
  and contract/localization checks passed.
- [ ] Native savings rows/editor/summary next; APK2–4 and physical/UI gates pending.

VersionCode8; all seven write flags false. ADB empty; no production writes.
Evidence: `docs/android/evidence/2026-10-13-apk2-savings-push.md`.

## APK 2 native savings workflow — 2026-10-13

- [x] Planning tabs, savings summary/progress/monthly requirement and native
  name/amount/date/icon/wallet form with delete and unsaved-change confirmation.
- [x] Exact input, owner-scoped draft/edit-snapshot restoration, original target
  instant preservation, preferred archived wallet and save-failure retention.
- [x] Fixed reporting FX overflow in budget/savings: exact intermediate values
  and final display clamping, with runtime RED/GREEN regressions.
- [x] 442 JVM tests/61 suites, 52 Swift planning tests, Room/planning test APK
  compilation, lint/build and contract/localization checks passed.
- [ ] Four compiled Compose budget/savings workflow tests and file-backed Room
  reopen test await ADB; visual/font/keyboard/Samsung verification not claimed.
- [ ] Recurring bills next, followed by installments/statements/due maintenance
  and remaining APK3–4/RC settings. Full requested parity remains incomplete.

VersionCode9, all seven write gates false; no production writes/deployments.
Evidence: `docs/android/evidence/2026-10-13-apk2-savings-ui.md`.

## APK 2 recurring bill typed contract — 2026-10-13

- [x] Complete 28-field typed bill wire record with explicit nullable schedule/
  deadline/auto-pay/pause/resume clears and exact Long money/version.
- [x] Strict decoding, legacy pause default, lossless unknown raw schedules and
  Swift local-calendar explicit deadline resolution.
- [x] 448 JVM tests/62 suites, 52 Swift planning tests, Room compilation,
  lint/build and contract/localization checks passed.
- [ ] Due occurrences/scheduling next, then repository lifecycle guards, gated
  push, native bill forms/payment, installments/statements and APK3–4.

All seven write gates false; no ADB device or production writes/deployment.
Evidence: `docs/android/evidence/2026-10-13-apk2-bill-contract.md`.

## APK 2 bill scheduling foundation — 2026-10-13

- [x] Typed 15-field due occurrence wire contract with exact snapshots/version,
  nullable clears, strict decoding and lossless legacy raw enum values.
- [x] Owner-scoped bill due rows: local schedule/frequency/resume anchor, deadline/
  auto-pay window, month-end clamp, paused exclusion and archived paid history.
- [x] Unpaid-cycle archive calculation, skipped status and duplicate terminal
  precedence; no mutation of historical payments.
- [x] 458 JVM tests/64 suites, 52 Swift planning tests, Room compilation,
  lint/build and contract/localization checks passed.
- [ ] Offline bill lifecycle/outbox next, then gated push, native forms/payment
  and due maintenance. APK2–4 and physical/UI verification remain incomplete.

All seven write gates false; ADB empty; no production writes/deployments.
Evidence: `docs/android/evidence/2026-10-13-apk2-bill-scheduling.md`.

## APK 2 offline recurring bill lifecycle — 2026-10-13

- [x] Atomic typed save/pause/resume/archive and owner-scoped history/occurrences;
  original currency/version/created/first-month and recurring pause state kept.
- [x] Schedule/deadline/auto-pay normalization, linked category/wallet validation,
  preferred imported archives and stale/deleted/forged owner protections.
- [x] Archive unpaid/skipped-cycle guard preserves payment history; runtime
  RED/GREEN fix for irrelevant stale due-day when deadline disabled.
- [x] 470 JVM tests/65 suites, 52 Swift planning tests, Room test APK compilation,
  lint/build and contract/localization checks passed.
- [ ] Execute file-backed lifecycle Room test when ADB returns; no device now.
- [ ] Bill push/native form/payment and notification/automatic maintenance next;
  remaining APK2–4 and final physical/visual verification incomplete.

VersionCode10; all seven write gates false. No production writes/deployments.
Evidence: `docs/android/evidence/2026-10-13-apk2-bill-offline.md`.

## APK 2 recurring bill push foundation — 2026-10-13

- [x] Separately disabled bill coordinator/network gate, category+wallet barrier
  and priority70 ordering before pull, preserving tombstone/reset support.
- [x] Conditional races/winners/conflicts/retry/cancellation/stale protection;
  typed Swift semantic defaults, ISO instants and malformed record validation.
- [x] Seven runtime RED contract regressions fixed; 32 bill coordinator and nine
  HTTPS network tests pass with complete typed payloads.
- [x] 511 JVM tests/67 suites, 14 Swift sync tests, Room compilation, lint/build
  and contract/localization checks passed.
- [ ] Native bill form/lifecycle/payment and due maintenance next; remaining
  APK2–4 and final physical/visual verification incomplete.

VersionCode11; all eight write gates false. ADB empty; no production writes.
Evidence: `docs/android/evidence/2026-10-13-apk2-bill-push.md`.

## Follow-up category bootstrap dependency identified — 2026-10-13

- [x] Direct Swift/UI audit found Android lacks startup default system category
  seeding. The prior APK1 build closure does not prove fresh/offline-account
  default-category parity; this gap is reopened explicitly.
- [ ] Add shared catalog/stable owner-scoped identity, atomic local bootstrap
  and sync protection against overwriting pre-existing cloud customization.
- [ ] Then implement native bills with Swift quick-picker and correct planning
  mode order budget/due/goals plus due bills/cards/installments submodes.

No runtime/production change in this audit. All eight write gates stay false.
Plan: `docs/superpowers/plans/2026-10-13-android-system-category-bootstrap.md`.

## Shared system category catalog/identity contract — 2026-10-13

- [x] Same shared JSON: 161 definitions, 147 active parent/child rows, seed names/
  metadata/order, strict malformed/duplicate validation and picker metadata check.
- [x] Canonical/cloud/family SHA1 UUID golden vectors verified directly in Swift
  and Kotlin; owner isolation/case and strict UUID shape regression covered.
- [x] 515 JVM tests/68 suites, four Swift identity tests, Room compilation,
  lint/build, one packaged catalog asset and contract/localization checks pass.
- [ ] Atomic local bootstrap and cloud customization protection/startup wiring
  still required before the native bill quick-picker can work for fresh accounts.

All eight gates false; no startup mutation introduced, ADB empty. APK2–4 remain
incomplete. Evidence: `docs/android/evidence/2026-10-13-system-category-catalog-contract.md`.

## Atomic local system category bootstrap — 2026-10-13

- [x] Missing defaults with owner-scoped cloud IDs, shared catalog metadata,
  atomic record/outbox and existing ID/custom/archive/tombstone preservation.
- [x] Viewer-owner filtering, occupied identity protection, duplicate reporting,
  strict UUID scope and insert-only transaction arrival-race guard.
- [x] 527 JVM tests/69 suites, four Swift identity tests, Room test APK compilation,
  lint/build and contract/localization checks passed.
- [ ] Three full-catalog Room tests await device execution; ADB empty.
- [ ] Sync customization protection and startup wiring next, then bill UI/payment.
  Existing duplicate/legacy repair and remaining APK2–4/physical gates incomplete.

VersionCode12; all eight gates false. No startup seed or production writes yet.
Evidence: `docs/android/evidence/2026-10-13-system-category-bootstrap-local.md`.

## Untouched system category seed sync protection — 2026-10-13

- [x] Narrow exact-seed classifier and same-ID remote customization/tombstone
  preference, including create race; explicit edits retain normal conflict logic.
- [x] Stale preference ACK preserves newer user mutation/record and next push.
- [x] 538 JVM tests/70 suites, 13 focused Swift tests, Room compilation,
  lint/build and contract/localization checks passed.
- [ ] Legacy different-ID/system-key reconciliation and canonical category
  comparisons in budget remain prerequisites to startup integration.
- [ ] Then native bill UI/payment/maintenance and remaining APK2–4; physical/UI
  verification still pending. ADB empty, all eight gates false, no production.

Evidence: `docs/android/evidence/2026-10-13-system-category-seed-sync-guard.md`.
Next: `docs/superpowers/plans/2026-10-13-android-system-category-logical-identity.md`.

## Cross-platform system category identity in budgets — 2026-10-13

- [x] Owner-scoped canonical/cloud/legacy comparison index; wire FKs and frozen
  display metadata preserved. New system snapshots use Swift canonical IDs.
- [x] Continuity, branch spending/totals, allocation cap, duplicate/auto-parent,
  single-currency guard, family propagation/reset and native form inheritance
  handle imported iOS IDs. Custom IDs and foreign owners remain isolated.
- [x] Complete category metadata includes tombstones for historical comparisons;
  deleted categories stay out of pickers and cannot be saved as dependencies.
- [x] Runtime RED: six identity failures and one UUID casing failure; final
  550 JVM tests/70 suites, 56 Swift tests, Room/UI test compilation, lint/build,
  contract and localization checks pass. All eight write gates false.
- [ ] Legacy different-ID/system-key reconciliation still required before startup
  seeding. Next: owner-scoped remote system-key lookup, then atomic reference
  reconciliation. Native bills/payment/maintenance and APK2–4 remain incomplete.

VersionCode14; ADB empty; no physical/UI runtime or live Supabase verification.
Evidence: `docs/android/evidence/2026-10-13-budget-category-logical-identity.md`.

## Owner/system-key remote lookup — 2026-10-13

- [x] Read-only paginated system-category lookup with explicit owner/key/system
  filters, stable ID order, exact-count range cursor, legacy IDs and tombstones.
- [x] Reject foreign/wrong-key/custom rows, malformed/missing rows or count,
  overfull/inconsistent pages, invalid scope/range/key and invalid Long versions.
  No rows are silently dropped before later identity reconciliation.
- [x] Runtime RED4, GREEN10 HTTPS mock tests. Final 560 JVM tests/71 suites,
  21 focused Swift tests, Room/UI test compilation, lint/build, contract/l10n
  and diff checks passed. VersionCode15, all eight write gates false, ADB empty.
- [ ] Atomic reference/outbox reconciliation and coordinator integration next;
  lookup remains uncalled by startup. Then bootstrap integration and native
  bills/payment/maintenance, remaining APK2–4 and final physical verification.

Evidence: `docs/android/evidence/2026-10-13-system-category-key-lookup.md`.

## Recurring bill editor draft foundation — 2026-10-13

- [x] Exact optional/signed amount, recurring and one-time schedule inputs,
  Swift date/auto-pay normalization, edit currency/identity and account saver.
- [x] Six runtime RED tests, then imported-frequency parity RED; final568 JVM
  tests/72 suites and52 Swift tests pass. Room/UI compilation, lint/build,
  contracts/localization/diff checks pass. No device available.
- [ ] Native bill sheet/list, correct budget/due/goals navigation, quick picker
  and lifecycle controls next; payment/maintenance and APK2–4 still incomplete.
- [ ] Category legacy-ID reconciliation/startup remains an open parallel
  dependency; read lookup is already implemented but not called automatically.

Evidence: `docs/android/evidence/2026-10-13-bill-editor-draft.md`.

## Native bill editor/lifecycle and planning navigation — 2026-10-13

- [x] Budget/due/goals order and due bills/cards/installments submode structure.
  Bills projected by selected month, paused section and immutable archived history.
- [x] Native bill create/edit fields, Swift quick picker keys, dates/day/window/
  frequency/auto-pay options/wallet, exact optional amount, busy/error/discard and
  pause/resume/archive confirmations wired to existing offline repository.
- [x] Captured edit account scope plus archived/deleted rejection; independent
  review findings corrected. Native UI tests compile but await device execution.
- [ ] Credit cards/installments still placeholders; pay/skip/undo, due summaries/
  timing/maintenance/actual auto-pay/notifications, configured default currency,
  category legacy-ID reconciliation/startup seed and APK3–4 remain incomplete.

Evidence: `docs/android/evidence/2026-10-13-native-bill-editor.md`.

571 JVM tests/72 suites,52 Swift tests, full lint/build/Room/UI compilation and
contract/l10n/diff checks pass. VersionCode16, eight gates false, ADB empty.
Next: typed bill pay/skip/undo atomic transaction/occurrence workflow; preserve
category startup reconciliation as an explicit open dependency. Goal active.

## Bill skip / undo skip — 2026-10-13

- [x] Native captured-cycle confirmation, pending/skipped actions, busy/retry/error
  and owner-scoped repository. No ledger writes; skipped amount/payment/link null.
- [x] Conditional Room source/cycle snapshot guard, duplicate tombstone/outbox
  batch, exact Long version, paid/foreign protection and stale-schedule rejection.
- [x]579 JVM tests/72 suites,52 Swift tests, full lint/build/Room/UI compile,
  contracts/l10n/diff checks pass. Static review findings fixed and re-reviewed.
- [ ] Room reopen/UI workflow assertions compiled but not run; ADB empty.
- [ ] Payment + undo-payment atomic money workflow next; due sync/maintenance,
  cards/installments, category legacy-ID startup and APK3–4 remain incomplete.

VersionCode17, eight gates false, no production writes. Evidence:
`docs/android/evidence/2026-10-13-bill-skip-undo.md`.

## Gated due-occurrence push — 2026-10-13

- [x] Typed identity/version validation, semantic Date equality with losslessACK,
  source dependencies and linked ledger deferral forUPSERT/DELETE.
- [x] Separate occurrence write gatefalse in coordinator and network allowlist,
  global/dependency gates; occurrence pushes after bill/ledger before pull.
- [x]599 JVM tests/74 suites,11 coordinator+9HTTPS cases,53 shared Swift tests,
  full checks/contract/l10n/diff pass. Independent static review noP1/P2.
- [ ] Atomic payment/undo next. User-approved rule: bill payment wallet must have
  same currency, applying to both Android and Swift; cross-platform guards underway.
- [ ] APK2–4/default-category startup/maintenance/physical gates remain incomplete.

VersionCode18; nine write flagsfalse; ADB empty; no production writes.
Evidence: `docs/android/evidence/2026-10-13-due-occurrence-push.md`.

## Bill payment same-currency policy on Android and Swift — 2026-10-13

- [x] User explicitly requires wallet currency to equal bill currency on BOTH
  platforms. Shared predicates, wallet picker/default filtering and persistence
  guards implemented in existing flows; errors localizedvi/en/ja.
- [x] Swift manual payment and auto-pay blocked before money writes. Reviewer
  found auto-pay bypass; simulatorRED/real SwiftDataGREEN verifies correction.
- [x] Android bill save enforces retained currency, mismatched defaults rejected;
  actual Android pay repository still requires implementation using this helper.
- [x]601 Android JVM tests,53 shared Swift planning tests and2 iOS Simulator
  integration tests pass. iOS build +Android lint/build/Room/UI compile pass.
- [ ] Full SwiftPM601tests has1 reproducible V7 migration fixture failure:
  testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees, CoreData134504.
  Diagnose next; do not claim full Swift green or production migration proof.
- [ ] Android payment/undo +remaining APK2–4/default-category startup/physical
  gates remain incomplete. ADB empty; nine write flagsfalse; no productionwrites.

VersionCode19. Evidence:`docs/android/evidence/2026-10-13-bill-same-currency.md`.


## Swift V7 investment migration plan isolation — 2026-10-13

- [x] Resolved the full Swift gate failure documented in the bill currency slice.
  Root evidence: regenerated V7 ledger entity resolved to frozen V5 shape and lost
  five reporting/settlement fields. V7/V8 now use an isolated V7–V11 plan with
  unchanged investment stages; legacy V4 handling remains separate.
- [x] Enhanced real-store regression runtime RED with old plan, GREEN with isolated
  plan; independent ledger fields preserved. 20/20 final independent runs and
  16 migration tests on normal/fresh scratch builds pass.
- [x] Full SwiftPM601 tests zero failures; iOS build, Android full cached checks,
  contracts/l10n/diff pass. Independent review no actionable P1/P2.
- [ ] Android atomic bill payment/undo and remaining APK1–4 parity continue next.
  ADB empty; no physical or live cloud verification; all cloud write gates false.

Evidence: `docs/android/evidence/2026-10-13-swift-investment-migration-plan.md`.


## Android atomic bill payment / undo backend — 2026-10-13

- [x] Posted expense + paid occurrence/category fallback/outbox atomic batch;
  complete money/receipt snapshots rechecked in Room. Same-currency validation,
  exactLong amounts, owner/viewer isolation, balance/credit/statement guards.
- [x] Owned paid duplicates + linked ordinary ledger undo atomically tombstone
  with Long base versions and DELETE outbox. Archive/history, shared/investment,
  receipt/link dependencies guarded; unsupported cleanup remains explicit.
- [x]23 new JVM tests,624 total/75 suites green;3 real Room tests compile,
  full Android lint/build and Swift601 tests green. Independent review fixed
  archive undo P2 and confirmed no remaining backend P1/P2. Contracts/l10n pass.
- [ ] Native pay/undo sheet/actions next; investment confirmation/shared/receipt
  cleanup and the rest of APK1–4 remain incomplete. No ADB/physical/live cloud test.

VersionCode20; nine write flagsfalse. Evidence:
`docs/android/evidence/2026-10-13-atomic-bill-payments.md`.


## Native bill payment / undo UI — 2026-10-13

- [x] Pending Pay /paid Undo sheet actions, exact confirmed amount and captured
  month/wallet; nil amount input, owned same-currency selector, localized errors,
  busy/retry/discard and archived/skip suppression. Category icon/color/date window.
- [x] Owner/bill/month saved form/navigation and coroutine lifecycle guard;
  restore waits for source and occurrence loading. Stale source/status refuses.
- [x]6 new JVM tests,630 total/76 suites green;4 new Compose tests compile,
  full Android lint/build/Room/UI compile and Swift Planning53 pass. Review noP1/P2.
- [ ] Device UI/visual checks not run: ADB empty. Investment/shared/receipt cleanup,
  category reconciliation/startup, maintenance, cards/installments, settings,
  APK3–4 remain open; full goal continues.

VersionCode21, nine write gatesfalse. Evidence:
`docs/android/evidence/2026-10-13-native-bill-payments.md`.


## System category selection / lossless FK repair component — 2026-10-14

- [x] Swift-priority value selection separate from actual stored identity;
  all candidates retained, owner/key/version/deletion validation, no synthetic ACK.
- [x] Owned category-parent /ledger-budget-bill FK repair preserves money,
  unknown JSON, frozen snapshots, pending kind/base, tombstones and clock ordering.
- [x]12 runtime RED/GREEN tests; full642 JVM/77 suites and23 Swift category tests,
  lint/build/Room/UI compile, contracts/l10n/diff pass. Static review noP1/P2.
- [ ] Room/reference/outbox/translation reconciliation and coordinator wiring next.
  Before that, transaction DELETE push must support pending bill undo tombstones.
  Startup and full APK1–4 remain open; no ADB/live-cloud verification.

Evidence: `docs/android/evidence/2026-10-14-category-reconciliation-model.md`.

## Bill undo sync / exact outbox CAS — 2026-10-14

- [x] Gated ordinary transaction DELETE, sparse audit metadata, Long CAS, no-create ACK, investment RPC-role refusal.
- [x] Ledger-first occurrence undo; remote-winning live ledger restores matching paid occurrence or retains conflict. Review P1 reproduced and fixed.
- [x] Actual Room ACK/failure predicates match kind and nullable payload, protecting same-clock replacement edits. SQLite RED6/GREEN4 methods and Room test compile.
- [x]658 JVM/78 suites, full Android checks, Swift outbox5, contracts/l10n/diff pass; independent review no further P1/P2 in slice. APK22 / nine flagsfalse.
- [ ] Immediate undo→repay identity race next. No ADB/device/live cloud verification; complete APK1–4 remains active.

Evidence: `docs/android/evidence/2026-10-14-bill-undo-sync.md`.

## Stable bill repayment identity — 2026-10-14

- [x] Undo→repay reuses original ledger/paid-cycle IDs and exact versions; atomically replaces DELETE with UPSERT, preserves audit and advances clocks without moving occurredAt.
- [x] Live/missing/ambiguous/unsupported prior payment guards; both original/proposed statement locks; unknown raw ledger/occurrence JSON preserved through undo and repayment.
- [x]8 added JVM regressions (including late coordinator DELETE response);666 total/78 suites, full Android checks and Swift Planning53 pass. Review P1/P2 each runtime RED/fixed/rereview clean. APK23, nine write flagsfalse.
- [ ] Category atomic reconciliation/create409/startup next. No Android device/live cloud verification; full APK1–4 remains active.

Evidence: `docs/android/evidence/2026-10-14-bill-repayment.md`.

## Category translation snapshot protection — 2026-10-14

- [x] Full raw-record compare before atomic apply; exact task device/name/language/time/attempt checks protect replacement tasks from stale ACK/failure/discard.
- [x] Owner/deletion/source-name validation before HTTP, unknown-field preservation, future-clock protection and explicit complete-translation refresh.
- [x]6 new coordinator regressions;672 JVM/78 suites and full Android checks pass. SQLite actual predicates5 methods; two new Room tests compile only. Review P2 reproduced/fixed/rereview clean. Swift category/contracts/l10n pass. APK24; nine flagsfalse.
- [ ] Atomic identity/reference reconciliation and create409/startup next; Android device/live cloud verification and full APK1–4 remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-category-translation-snapshot.md`.

## Atomic category FK/outbox/task repair primitive — 2026-10-14

- [x] Complete Room snapshots of category/ledger/budget/bill records, future/failed outbox and all translation tasks; exact atomic compare before raw reference and task writes.
- [x] Valid owned same-key target hierarchy; lossless money/frozen/unknown metadata, pending kind/base versions, viewer isolation, strict category clocks and translation input/language preservation.
- [x]9 model regressions RED/GREEN;681 JVM/79 suites, full Android and Swift SystemCategory23 checks pass. Three Room tests compile only; independent component review noP1/P2.
- [ ] Identity merge/reassignment/deletion and seed edits are not yet combined with this primitive; create409/startup, device verification and full APK1–4 remain open. Nine write flagsfalse.

Evidence: `docs/android/evidence/2026-10-14-category-reference-room.md`.

## Lossless system category adoption preparation — 2026-10-14

- [x] Exact queued base0 seed validation and field deltas against registry defaults; real remote ID/version/audit retained, unknown JSON and unrelated remote edits preserved.
- [x] Untouched exact remote adoption; changed target gets pending UPSERT, duplicate candidates retained, active/tombstone distinction and explicit edited-source conflict, occupied target protection and translation input/language retargeting.
- [x]9 new tests RED/GREEN;690 JVM/80 suites plus full Android/Swift23/contracts/l10n checks pass; independent component review noP1/P2.
- [ ] Atomic target/source identity installation/removal with FK/outbox/tasks and create409/startup remain pending. No device/live cloud writes; full APK1–4 continues.

Evidence: `docs/android/evidence/2026-10-14-system-category-adoption-model.md`.

## Atomic single-remote system category identity migration — 2026-10-14

- [x] Complete snapshot CAS + exact source queue/task removal, real target install, safe unpersisted source identity removal and all FK/outbox/translation repairs in one Room transaction.
- [x] Same-ID adoption, explicit tombstone preservation, viewer-reference/remotely persisted-source guards; no different-ID normal ACK. Multiple remote duplicates remain explicitly rejected.
- [x]4 new combined model regressions RED/GREEN;694 JVM/80 suites and full checks pass. Four Room tests compile only; independent review noP1/P2.
- [ ] Owner-key lookup/create409/parent-dependency wiring and duplicate reconciliation before startup; physical/live cloud and complete APK1–4 remain pending. Nine flagsfalse.

Evidence: `docs/android/evidence/2026-10-14-category-identity-room.md`.

## Category precreate / create409 owner-key integration — 2026-10-14

- [x] Full owner-key pagination and exact snapshot-checked single-identity migration before create and after409. Separate reconciled count; edited seeds preserve remote values and queue correctly based target UPSERT.
- [x] Pending-parent deferral, deleted-parent create refusal/tombstone adoption, owner/pagination validation, same-clock edit protection, retry/cancellation/gate-off behavior.
- [x]10 new integration cases RED/GREEN;704 JVM/80 suites plus full checks pass. Independent review noP1/P2. APK25 / nine flagsfalse; no device/live cloud execution.
- [ ] Multiple remote identities remain explicit conflicts. Duplicate/tombstone cleanup must honor the SQL active-key unique index before startup. Full APK1–4 continues.

Evidence: `docs/android/evidence/2026-10-14-category-key-reconciliation.md`.

## Observed category identity provenance — 2026-10-14

- [x] Runtime reproduced version0 reconciliation loop; persisted local-only provenance prevents reseeding observed identities and preserves ordinary exact-version CAS/default-reset intent.
- [x] Room schema4/migration3→4, positive-base backfill, propagation across edits/repairs/retries, exact flag-aware ACK/failure; no wire payload change.
- [x]3 new JVM regressions;707 total/80 suites and full checks pass. Actual SQLite/schema7 methods; three new Room tests compile only. Independent review noP1/P2. APK26 / nine flagsfalse.
- [ ] Retained tombstone duplicates / active-key cleanup before startup; no device/live cloud verification; full APK1–4 continues.

Evidence: `docs/android/evidence/2026-10-14-observed-category-identity.md`.

## Retained category tombstone aliases — 2026-10-14

- [x] Atomic real target adoption plus raw deleted-alias metadata retention and reference convergence from every alias; pending alias edits/tasks defer, viewer references remain read only.
- [x] Child parent uses real observed parent identity; live children defer when preferred identity is deleted. Review P2 runtime RED/fixed/rereview clean. Deleted category FK repair uses full tombstoned UPSERT, preserving existing pending kinds.
- [x]11 new regressions;718 JVM/80 suites and full checks pass. Retained-alias Room reopen/rollback compile only. APK27; nine write flagsfalse.
- [ ] Active legacy competitor cleanup before cloud identity resurrection, parent maintenance/startup, physical verification and full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-retained-category-aliases.md`.


## Ordered active category alias cleanup — 2026-10-14

- [x] Atomically queue exact-base live legacy tombstone and canonical restoration,
  preserve raw metadata/history/references, send parent-first and cleanup-first.
- [x] Pending/future cleanup defers activation; complete owner-key lookup for
  observed active edits (including version0) blocks remote-winning live aliases.
  Occupied target edits/tasks defer adoption without dropping queued user work.
- [x]5 new JVM regressions RED/GREEN;723 total /80 suites and full Android,
  Swift23, contracts/l10n/SQLite checks pass. Independent review noP1/P2.
  Room cleanup reopen test compiles only; APK28; all nine flagsfalse.
- [ ] Generic clean-group maintenance, startup, device/live cloud verification
  and full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-category-active-alias-cleanup.md`.


## Observed category group maintenance API — 2026-10-14

- [x] Actual observed group repair without a seed or fabricated wire ID; common
  raw identity/value/reference path, tombstone preservation, pending group/task
  deferral, stale metadata and owner/kind/role validation.
- [x] Full snapshot CAS and shared Room install transaction; no source deletion.
  Reopen/stale/rollback tests compile only.
- [x]5 new runtime regressions RED/GREEN;728 JVM/80 suites and full Android,
  Swift23/contracts/l10n/SQLite checks pass; independent review noP1/P2. APK29.
- [ ] Maintenance coordinator/startup, physical/live cloud and full APK1–4 parity
  remain open; all nine write flags remain false.

Evidence: `docs/android/evidence/2026-10-14-observed-category-maintenance-api.md`.


## Post-pull category maintenance integration — 2026-10-14

- [x] Complete actual remote category input after all tables, roots first, fresh
  snapshots and atomic per-group repair; future edits/tasks and viewer rows kept.
  Local pending records are not substituted for authoritative cloud input.
- [x] AppModule wiring for syncNow/pullAll; incomplete/invalid paged pulls refuse
  maintenance. Review P2 cancellation was reproduced/fixed; re-review noP1/P2.
- [x]10 new regressions;738 JVM/80 suites and full Android/Swift23/contracts/l10n/
  SQLite checks pass. APK30; nine flagsfalse; no device/live cloud execution.
- [ ] Default bootstrap startup/offline recovery, remaining APK1–4 features and
  physical verification remain open.

Evidence: `docs/android/evidence/2026-10-14-postpull-category-maintenance.md`.


## Default category startup / offline recovery — 2026-10-14

- [x] Insert-only missing defaults after completed raw pull+maintenance; retryable
  offline/auth-refresh fallback for unchanged signed-in owner. Cancellation and
  permanent malformed input refuse fallback; no cloud writes.
- [x] Offline base0 seed reconciliation from full raw pull works with gatesfalse,
  preserves explicit edits and authoritative tombstones; alias pending edits defer.
- [x] Owner guards before/after pull and before maintenance/defaults. Runtime late
  signout response regression reproduced/fixed before local snapshot replacement.
- [x]9 new regressions;747 JVM/80 suites plus full Android/Swift23/contracts/l10n/
  SQLite checks pass. APK31; nine flagsfalse; no device/live cloud execution.
- [ ] Independent review unavailable due reviewer usage limit; remains outstanding.
  Full APK1–4 and physical verification remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-category-startup-offline-recovery.md`.


## Recurring bill maintenance event planner — 2026-10-14

- [x] Previous/current local pending cycles, exact snapshot amount, normalized
  auto-pay intent, start/deadline reminder and daily overdue keys, terminal/owner/
  paused/archive/deleted filtering matching direct Swift maintenance comparison.
- [x]5 new tests runtime RED/GREEN;752 JVM/81 suites plus full Android/SwiftPlanning53/
  contracts/l10n/SQLite checks pass; APK32, all nine flagsfalse.
- [ ] Auto-pay execution, persistent notifications/native hooks, independent review
  (usage limit) and device verification remain incomplete; full APK1–4 continues.

Evidence: `docs/android/evidence/2026-10-14-bill-maintenance-events.md`.


## Automatic bill payment repository guards — 2026-10-14

- [x] Automatic mode rechecks enabled/pause/resolved local date and disallows
  amount/wallet overrides, preserving current money/dependency validation.
- [x] Repeat attempt cannot create another expense; concurrent auto-pay disable
  invalidates complete transaction through full money snapshot CAS.
- [x]4 new tests (3 runtimeRED/GREEN);756 JVM/81 suites plus full Android/Swift53/
  contracts/l10n/SQLite checks pass. APK33; nine flagsfalse; no device/live cloud.
- [ ] Maintenance executor, localized auto-payment title, persistent notifications/
  native hooks, independent review and full APK1–4 remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-auto-payment-repository-guards.md`.


## Local recurring bill maintenance executor — 2026-10-14

- [x] Public FinanceRepository maintenance API executes automatic intents through
  atomic money repository; per-payment results, repeat suppression, owner scope,
  exact Long amounts and cancellation. Reminders re-read cycle state after money.
- [x]6 new regressions (5 runtimeRED/GREEN);762 JVM/81 suites plus full Android/
  Swift53/contracts/l10n/SQLite checks pass. APK34; nine flagsfalse.
- [ ] Durable notification batch/success recovery, localized auto title, native
  hooks, independent review (usage limit), device and full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-bill-maintenance-executor.md`.


## Owner-scoped local notification storage — 2026-10-14

- [x] Room schema5/migration4→5, separate local notification table, owner/key
  partition, exact snapshot CAS batch, flow/read APIs and account cleanup.
- [x] Swift upsert/read/resolve semantics, exact Long/null metadata, protected
  family/success/other-cycle/owner rows. No notification cloud outbox writes.
- [x]6 model runtimeRED/GREEN;768 JVM/82 suites and full Android/SwiftNotification13/
  contracts/l10n checks. Actual SQLite notification3 +outbox7 methods pass.
  Room/migration tests compile only; APK35; nine flagsfalse.
- [ ] Durable bill notification generation with money, localized copy/native
  notification center/hooks, independent review/device/full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-local-notification-store.md`.


## Atomic automatic-payment success notification — 2026-10-14

- [x] Production localized auto expense/success title+body provider; current
  structured bill/cycle/wallet metadata and stable Swift success key.
- [x] Success notification companion validates owner/bill/cycle/currency/configured
  wallet/enabled state and PAID writes, and commits inside money Room transaction.
  Existing read state is preserved; notification failure rolls money back.
- [x]Runtime RED/GREEN for presentation/companion and disabled boundary validation;
  769 JVM/82 suites plus full Android/Swift53/contracts/l10n/SQLite checks pass.
  New reopen/rollback Room tests compile only. APK36; nine flagsfalse.
- [ ] Reminder/failure batch, resolution/preferences/native center/hooks, independent
  review/device and full APK1–4 parity remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-atomic-auto-payment-notification.md`.


## Persistent recurring-bill reminder/failure batch — 2026-10-14

- [x] Production localized current reminder/failure generation, stable Swift keys,
  structured current action metadata and existing read/success history protection.
- [x] Full bill/occurrence/notification snapshot CAS with up to3 fresh retries;
  paid/read races cannot resurrect stale alerts. Paid/skipped/paused/archive/delete/
  missing/changed-unpayable cycles resolve actionable notifications.
- [x]11 new tests (model5 REDs +scheduleRED);780 JVM/83 suites plus full Android/
  SwiftNotification13/contracts/l10n/SQLite checks pass. Room race test compiles only.
  APK37; all nine flagsfalse; no device/live cloud.
- [ ] Native center/actions, immediate manual resolution/preferences/hooks,
  independent review and full APK1–4 remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-bill-notification-batch.md`.


## Native local notification center — 2026-10-14

- [x] Overview bell/live badge, grouped local center, newest preview/day details,
  presented-group read, read-all, sync/pull refresh and back gesture.
- [x] Owner-keyed route/state scopes; exact captured read targets preserve new and
  same-key replacement unread arrivals during CAS retry.
- [x]Future undo sync-clock notification visibility regression runtimeRED/fixed;
  money keeps monotonic audit clock and local notification uses real payment time.
- [x]8 new regressions;788 JVM/85 suites plus full Android/SwiftNotification13/
  contracts/l10n/SQLite checks pass. Compose2 tests compile only; APK38; flagsfalse.
- [ ] Payment/top-up actions, immediate resolution/preferences/maintenance hooks,
  family remote data/actions, Fluent visual/device QA, independent review and
  full APK1–4 parity remain open.

Evidence: `docs/android/evidence/2026-10-14-native-local-notification-center.md`.


## Notification bill payment/top-up actions — 2026-10-14

- [x] Native payment-required/overdue action opens current bill payment sheet;
  auto failure opens existing internal transfer editor with destination-only preset.
  Current owner/cycle/bill/wallet validation, stale amount/currency refusal,
  malformed cycle protection and one-time pause parity.
- [x] Payment/skip resolve cycle notifications in the Room mutation transaction;
  pause/archive/delete resolve the bill. Undo/pending/foreign writes preserve alerts.
- [x]10 new tests with runtimeRED/GREEN;798 JVM/86 suites plus full Android/Swift53/
  contracts/l10n/SQLite checks pass. Room pay/skip/pause rollback and Compose callback
  tests compile only. APK39; all nine flagsfalse.
- [ ] Reminder preferences/guarded maintenance hooks, family/card/investment actions,
  Fluent visual/device QA, independent review and full APK1–4 remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-notification-bill-actions.md`.


## Native notification preferences — 2026-10-14

- [x] Persistent device-level master/detail/family choices and native settings route;
  explicit-enable Android permission flow; legacy initialization preserves family.
- [x] Commit-time bill preference gates suppress notifications without suppressing
  payment; disabled reminder history still resolves; late family fetch cannot replace cache.
- [x] Runtime RED/GREEN;808 JVM/87 suites plus Android/SwiftNotification13/contracts/
  localization/SQLite checks pass. Room/SharedPreferences/Compose tests compile only.
  APK40; all nine cloud flagsfalse; no device/live cloud.
- [ ] Guarded maintenance/background hooks, OS delivery, independent review,
  Fluent visual/device QA and full APK1–4 parity remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-notification-preferences.md`.


## Bill maintenance current-account guard — 2026-10-14

- [x] Serial injectable coordinator captures current owner at execution, cancels on
  account switch/sign-out, preserves same-owner refresh and cancellation semantics.
- [x] Production Room money/reminder commits check active owner before/after writes;
  stale owner cancellation rolls back the transaction.
- [x] Runtime RED/GREEN;816 JVM/88 suites; full Android/SwiftPlanning53/contracts/
  l10n/SQLite pass. New financial/reminder rollback Room tests compile only.
  APK41; nine cloud flagsfalse; no device/live cloud.
- [ ] Foreground/background hooks/cold-process restore, OS delivery, independent
  review/device verification and full APK1–4 parity remain unfinished.

Evidence: `docs/android/evidence/2026-10-14-bill-maintenance-account-guard.md`.


## Foreground recurring-bill maintenance — 2026-10-14

- [x] Owner-keyed resumed lifecycle runs sync once then actual guarded local bill
  maintenance immediately/every minute; backgrounding cancels. Offline sync permits
  cached payment; no reminder preference gate on money. Storage retries next tick.
- [x]5 runtime RED/GREEN regressions;821 JVM/89 suites; full Android/SwiftPlanning53/
  contracts/l10n/SQLite checks pass. App/Room AndroidTests compile only; APK42.
- [ ] Background/cold-process restore, OS delivery, immediate preference triggers,
  dynamic device time-zone, independent review/device QA and full APK1–4 remain open.
  Nine cloud flagsfalse; no device/live cloud writes.

Evidence: `docs/android/evidence/2026-10-14-bill-foreground-maintenance.md`.


## Background-safe session restoration — 2026-10-14

- [x] Shared initial restoration gate for Activity/worker callers; serialized restore,
  resolved-state guard, retry/cancellation behavior. Activity uses gate.
- [x] Five reproduced late auth-response races fixed with session generation guards,
  immediate local sign-out and serial owner-checked refresh; signed-out cache cannot resurrect.
- [x]13 added tests;834 JVM/90 suites; full Android +Swift601/contracts/l10n/SQLite pass.
  Room/app AndroidTests compile only; APK43; nine cloud flagsfalse; no device/live cloud.
- [ ] Background worker/cold-process device run, OS delivery, preference/time-zone
  hooks, independent review/device QA and full APK1–4 remain unfinished.

Evidence: `docs/android/evidence/2026-10-14-background-session-restoration.md`.


## Background recurring-bill maintenance — 2026-10-14

- [x] Unique hourly local WorkManager job, no network/permission constraint, retry
  backoff; Hilt entry point resolves cold-process dependencies without UI/static state.
- [x] Shared restore then actual account-guarded bill pipeline; signed-out no-op,
  repository error retry and cancellation propagation; reminder flags do not gate money.
- [x]6 runtime pipeline tests (5 REDs);840 JVM/91 suites; full Android/SwiftPlanning53/
  contracts/l10n/SQLite pass. App/Room AndroidTests compile only; APK44; cloud flagsfalse.
- [ ] Actual OS scheduling/cold-process/boot/device verification, OS delivery,
  preference/time-zone hooks, independent review and full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-background-bill-maintenance.md`.


## Dynamic planning calendar — 2026-10-14

- [x] Default singleton repository follows current device zone per planning/money
  operation; explicit fixtures stay fixed. Each automatic pass shares one captured
  zone across events, payment/statement checks and notification generation.
- [x] Four reproduced REDs +two calendar regressions;846 JVM/91 suites; full Android/
  SwiftPlanning53/contracts/l10n/SQLite pass. Room/planning AndroidTests compile only.
  APK45; cloud flagsfalse; no device/live cloud.
- [ ] Device zone-change/UI QA, OS low-wallet scheduling, immediate preference hooks,
  remaining notification domains, independent review and full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-dynamic-planning-calendar.md`.


## Persistent next-morning wallet reminders — 2026-10-14

- [x] Local low-cash-wallet inbox and intended next-09:00 targets, exact Long balance,
  current zone/DST, owner/activity filters, archived shared-debt exclusion, preserved
  read history and stale/obsolete cleanup; hooked after bill foreground/background passes.
- [x] Full raw wallet/transaction/group/inbox snapshot CAS with3 fresh retries and
  commit-time owner/preferences checks; no financial/outbox mutation.
- [x]15 new runtime cases;861 JVM/93 suites; full Android/SwiftNotification13/contracts/
  l10n/SQLite pass. Room race/preferences/rollback tests compile only; APK46; flagsfalse.
- [ ] Actual Android OS schedule/posting/cleanup, immediate preference triggers,
  independent review/device/visual QA and full APK1–4 remain incomplete.

Evidence: `docs/android/evidence/2026-10-14-wallet-reminder-inbox.md`.


## Native Android low-wallet reminders — 2026-10-14

- [x] Actual idle-aware local09:00 AlarmManager scheduling, private receiver/unique
  delivery worker, Hilt cold restore, clock/boot recovery and wallet channel/posting.
- [x] Fresh owner/balance/policy/permission/channel checks, durable pending intent and
  handled/delivered nonces, normal retry protection and stale display cleanup.
  Suppressed requests cannot replay after later funding/permission changes.
- [x] Immediate owner/master/wallet preference and financial-change observation;
  no inbox feedback loop, token-refresh restart or unchanged-data rescheduling.
- [x]30 added runtime cases;891 JVM/96 suites; full Android/Swift601/contracts/l10n/
  SQLite checks pass;3 new Android platform tests compile only. APK47; flagsfalse.
- [ ] Actual OS/device timing/sound/reboot/permission/tap verification, independent
  review, bill/family immediate preference flow, remaining maintenance/UI/APK3–4
  domains and complete APK1–4 parity remain unfinished. No live cloud writes.

Evidence: `docs/android/evidence/2026-10-14-native-wallet-reminders.md`.


## Immediate bill notification preference maintenance — 2026-10-14

- [x] User master/reminder/detail changes invoke actual guarded bill maintenance
  immediately. Master disable skips new work; money remains independent of bill
  notification detail. Owner transitions take a fresh baseline without replaying gestures.
- [x] Expected-owner guard after coordinator mutex prevents queued old-owner action
  from running money for replacement account; token/family/history changes stay quiet.
- [x]7 runtime RED/GREEN cases;898 JVM/97 suites; full Android/SwiftNotification13/
  contracts/l10n/SQLite pass. AndroidTests compile only; APK48; nine flagsfalse.
- [ ] Card/budget due maintenance, targeted family inbox preference refresh/actions,
  independent review/device/visual QA and full APK1–4 remain unfinished.

Evidence: `docs/android/evidence/2026-10-14-immediate-bill-preferences.md`.


## Shared credit-card statement model and paid guards — 2026-10-14

- [x] Next-month local close/due calculation, exact Long charge/current credit,
  linked/covering paired-FX payment resolution, canonical/legacy occurrence precedence,
  statement states, due-month projection and due-through+5-day automatic decision.
- [x]27 common JSON vectors run against actual Swift and Kotlin, including Japan/
  Vietnam boundaries; guard/repository fixes prevent false freezes and reopening an
  already-paid statement by adding a larger charge. Operation clock/calendar captured.
- [x]36 added cases;934 JVM/99 suites; full Android/Swift602/contracts/l10n/SQLite pass.
  Room/planning AndroidTests compile only; APK49; nine write flagsfalse; no device/cloud.
- [ ] Native statement/payment/history UI, actual card payment/maintenance/undo and
  outbox dependencies, installments, pending cross-currency card product decision,
  independent review/device/visual QA and full APK1–4 remain unfinished.

Evidence: `docs/android/evidence/2026-10-14-credit-card-statement-model.md`.


## Native credit-card statement/history view — 2026-10-14

- [x] Management card navigation plus separate existing editor; owned statement summary,
  states/dates/linked wallet, raw charge history and static paid-history locks.
- [x] Bounded local month navigation, Save/Cancel month/year dialog, owner/card-scoped
  saved state, lifecycle observation/loading/error/retry and resumed calendar refresh.
- [x]7 runtime RED/GREEN cases;941 JVM/100 suites; full Android/Swift602/contracts/
  l10n/SQLite pass.3 new Compose tests compile only. APK50; nine write flagsfalse.
- [ ] Actual card payment/undo/maintenance, pending card currency policy, generated
  transaction-title localization, installment/UI/device/independent review and complete
  APK1–4 parity remain unfinished. No device/visual/live cloud verification.

Evidence: `docs/android/evidence/2026-10-14-credit-card-statement-history.md`.


## Generated transaction-title localization — 2026-10-14

- [x] Shared Swift-matching title recognition with semantic restrictions and preserved
  custom titles; current-language display in Overview, Transactions and card history.
  Uses generated vi/en/ja resources and owned category metadata; no persisted mutation.
- [x]24 runtime RED/GREEN cases against shared xcstrings;965 JVM/101 suites; full
  Android/Swift602 +focusedTransaction37/contracts/l10n/SQLite pass.2 resource/Compose
  tests compile only. APK51; nine write flagsfalse; no device/live cloud verification.
- [ ] General Finance read-scope audit, card payment/maintenance/pending currency
  choice, installments, independent/device/visual QA and full APK1–4 remain open.

Evidence: `docs/android/evidence/2026-10-14-generated-transaction-titles.md`.


## Personal Finance repository read scoping — 2026-10-14

- [x] All15 raw financial collections plus wallet/category/profile/transaction and
  delegated budget/goal/bill/due streams validate entity, row/payload owner+UUID ID and
  both tombstones before exposing live data. Historical category metadata retains
  owned tombstones while excluding aliases; family viewer/subject repositories stay separate.
- [x] Personal financial counts derive from the same validated streams and respond
  to payload changes with unchanged storage count; no storage/outbox repair/write.
- [x]21 initial REDs;23 new cases;988 JVM/104 suites; full Android/Swift602/contracts/
  l10n/SQLite pass.2 new DAO+repository Room tests compile only. APK52; flagsfalse.
- [ ] Device/independent review, card payment/maintenance/currency choice, installments,
  remaining APK1–4 and RC are unfinished. No device/live cloud verification.

Evidence: `docs/android/evidence/2026-10-14-finance-read-scope.md`.


## Owned installment due read view — 2026-10-14

- [x] Strict16-field installment codec, exact Long/nullable metadata, envelope identity;
  typed owned live read and selected-month scheduling/frozen occurrence projection.
- [x] Replaced installment count placeholder with native amount/status/due-day rows,
  loading/error/retry/empty states, owner/month/zone state isolation and resumed clock.
- [x]35 common JSON vectors run against actual Swift/Kotlin; duplicate settled/pending,
  finite/month/legacy schedules, DST/Japan/Vietnam, exact amounts and frozen history.
- [x]44 new runtime cases;1032 JVM/107 suites; full Android/Swift603/contracts/l10n/
  SQLite pass.2 Compose +1 Room checks compile only. APK53; nine write flagsfalse.
- [ ] Installment CRUD/payment/undo/skip/maintenance/push, pending card currency
  decision, independent/device/visual QA and full APK1–4/RC remain unfinished.

Evidence: `docs/android/evidence/2026-10-14-installment-due-read.md`.


## Owned installment mutation repository — 2026-10-14

- [x] Stable-ID save/delete APIs, semantic baseline/ACK/replay behavior, imported raw
  currency/creation/unknown metadata and exact Long versions, nullable total-cycle clears.
- [x] Complete raw plan/wallet/occurrence snapshot CAS, three attempts, atomic Room
  record/outbox writes and current-owner cancellation/rollback. Delete preserves expense
  ledger and frozen occurrence data while tombstoning owned live plan/cycles.
- [x] Installment flagfalse (10 flagsfalse total); shared due client/coordinator source
  gate isolates bill readiness from card/installment children and pins PATCH source kind.
- [x]35 new cases;1067 JVM/110 suites; full Android/Swift603/contracts/l10n/SQLite pass.
  Four new Room fixtures compile only. APK54; no device/live cloud verification.
- [ ] Native installment CRUD forms, payment/skip/undo, proper source-delete push
  preflight, pending card currency decision, independent/device/visual QA and APK1–4/RC.

Evidence: `docs/android/evidence/2026-10-14-installment-mutations.md`.


## Native installment metadata editor — 2026-10-14

- [x] Planning create/edit/delete sheet wired to actual repository; stable create UUID,
  exact Swift grouped-minor input with formatted preview, immutable currency/anchor,
  nullable cycles, owned wallet/four icon selectors and localized failures.
- [x] Discard/delete confirmations, original delete baseline, busy/late-cancellation
  guards and owner-scoped form/navigation savers. Editor survives month/loading changes;
  repository identity removed from saved subtree keys for reconstruction.
- [x]11 runtime RED/GREEN cases;1078 JVM/111 suites; full Android/Swift603/contracts/
  l10n/SQLite pass. Seven new Compose/Room workflows compile only. APK55;10 flagsfalse.
- [ ] Actual installment payment/skip/undo/maintenance/push, card currency decision,
  app currency/settings and monetary-form audit, Fluent/device/independent/visual QA,
  remaining APK1–4 and RC. No device/process-death/live cloud verification.

Evidence: `docs/android/evidence/2026-10-14-installment-editor.md`.


## Native installment skip/undo — 2026-10-15

- [x] Pending/skip row actions and native confirmations wired to real repository;
  owner/month/zone scope, busy/late-callback guards and generated vi/en/ja failures.
- [x] Full raw snapshot CAS and atomic Room occurrence/outbox writes; active semantic
  source baseline, finite/frequency schedule, paid/linked duplicate guards, nullable
  skip snapshots, preserved frozen undo tombstones and no ledger/balance movement.
- [x]19 repository +5 policy runtime cases (initial16 produced15 intended REDs),
 1102 JVM/113 suites; full Android/Swift603/contracts/l10n/SQLite pass. Four Room and
  three Compose additions compile only. APK56; all10 flagsfalse; no device/cloud write.
- [ ] Installment payment/undo/currency, dedicated push/delete dependency preflight,
  actual maintenance/notification audit, pending card policy, currency/settings/forms,
  independent/Samsung/visual checks and remaining APK1–4/RC remain unfinished.

Evidence: `docs/android/evidence/2026-10-15-installment-skip.md`.


## Gated installment plan push foundation — 2026-10-15

- [x] Typed owner/version/clock validated plan coordinator, Swift semantic comparison,
  exact nullable/Long payloads, standard create/update/independent tombstone conflict,
  ACK/retry/cancellation and stale-response behavior. Canonical UUID wallet dependency.
- [x] Native DI/client allowlist behind installment+wallet flags; engine order80 before
  due90. Source deletion with pending owned cycles is held before remote IO; existing
  bill-only child gate stays closed. This is not complete installment synchronization.
- [x]25 coordinator +10 HTTPS cases; initial20 produced19 REDs, plus dependent-delete
  and UUID regressions.1137 JVM/115 suites; full Android/Swift603/contracts/l10n/SQLite
  pass. APK57; all10 flagsfalse; no device/production write or schema change.
- [ ] Causal source-delete/child conflict reconciliation and dedicated occurrence push,
  installment payment/undo/currency, actual maintenance audit, card settlement policy,
  settings/monetary forms, independent/device/visual QA and full APK1–4/RC remain open.

Evidence: `docs/android/evidence/2026-10-15-installment-plan-push.md`.


## Durable installment source-delete provenance — 2026-10-15

- [x] Explicit causal batch with source/cycle before-images, exact prior queues/Long
  metadata and child manifest; strict codec/actor/owner/frozen-field validation.
- [x] Native Room capture in the same snapshot CAS/outbox transaction, owner read/clear,
  non-replacing unresolved batches and local migration5→6. Bounded64KiB BLOB chunks,
  integrity/UTF-8 checks and scoped cascade cleanup; legacy deletes stay unproven.
- [x] Fixed missing schema assets in the actual database AndroidTest APK; six schemas
  and bootstrap catalog verified. Ten disk-Room and one migration fixtures package only.
- [x]16 model cases (9 initial REDs +actor/chunk regressions),7 actual SQLite cases and
  artifact RED/GREEN;1153 JVM/116 suites. Full Android/Swift603/contracts/l10n/SQLite pass. APK58;
  all10 flagsfalse. No AndroidTest/device execution or production schema/write change.
- [ ] Source ACK/child restoration and causal batch cleanup, legacy recovery, occurrence
  push and actual payment/undo/currency remain unfinished. Current guards remain closed;
  card policy/settings/forms/full APK1–4/RC and independent/device/visual QA remain open.

Evidence: `docs/android/evidence/2026-10-15-installment-delete-batch.md`.

## 2026-10-15 — installment source ACK/history restoration (APK59)

Completed the gated source-delete reconciliation path with immutable per-request causal batch identity, active remote winner restoration of only matching child deletes, preservation of newer child intent/prior retry metadata and paid financial history, and atomic Room source/child/queue/exact batch cleanup. Successful source deletion retains children/batch/expense for dedicated cleanup. Stale failures are batch-fenced too; cancellation and persistence failures cannot bypass the guard. Legacy unproven dependencies remain held. Shared conflict policy preserves existing sync API behavior.

Runtime23 model +14 sync cases pass; full1190 JVM/118 suites, Swift603, lint/build, AndroidTest compilation/package, contract15, localization and existing SQLite checks pass. Ten new disk-Room fixtures are compile/package only; ADB empty. VersionCode59 APK/test APK and checksums are in `evidence/2026-10-15-installment-source-ack.md`. All10 flagsfalse; no cloud writes/deploy/migration or device proof.

Next: dedicated installment child deletion/push/completion, resurrection and legacy recovery; actual payment/undo/currency handling and maintenance; remaining full APK1–4/RC and independent/Samsung/visual checks. Full goal remains active.

## 2026-10-15 — protect unfinished installment deletion during pull (APK60)

Fixed the post-source-ACK pull interval: clean source rows with an exact owned causal batch are preserved both from snapshot deletion and incoming UPSERT until dedicated reconciliation clears the batch. Current-owner guards cover source pull and cursor transaction rollback. Other plans/owners/entities remain unaffected; corrupt intent stays held for explicit recovery.

Two actual-SQL behavioral RED cases now pass; installment SQLite helper11 (four additions), outbox7/notification3, full1190 JVM/118 suites, Swift603, lint/build, AndroidTest compile/package, contract15/localization and packaged six schemas pass. Six added disk-Room fixtures compile/package only; no ADB device. Evidence/APK60/test APK/checksums: `evidence/2026-10-15-installment-pull-pin.md`. All10 flagsfalse; no production writes/deploy/migration. Child completion/resurrection/legacy recovery and full APK1–4/RC remain active.

## 2026-10-15 — proven installment deletion completion (APK61)

Completed the dedicated causal source-delete child worker inside the existing due-domain coordinator. It uses owned authoritative reads, sparse exact Long conditional deletes, bounded races, whole-batch atomic Room ACK/queue/header/chunk cleanup, stale snapshot/batch fencing and idempotent lost-response/cancellation retry. It retains recorded expenses and newer child intent. Active source resurrection remains a scoped conflict with the source pull pin retained; explicit recovery remains unfinished. Ordinary installment upsert/undo and legacy unproven delete writes stay held. Network capability is separate, sparse-delete-only and default false; all10 generated flagsfalse.

Runtime16 model +23 worker +8 HTTPS cases pass; full1237 JVM/121 suites, Swift603, lint/build, AndroidTest compile/package, contract15/localization and existing SQLite checks pass. Seven added disk-Room fixtures compile/package only; ADB empty. APK61/test APK/checksums and limits: `evidence/2026-10-15-installment-delete-completion.md`. No production writes/deploy/migration. User now requests installment payment by same-currency wallet only on BOTH Swift/iOS and Android; implement selector and persistence guards next. Full APK1–4/RC remains active.

## 2026-10-15 — same-currency installment wallets on both platforms (APK62)

Implemented the user's explicit rule on Swift/iOS selection/default/save/early-payment and current SwiftData persistence preflight, plus Android default-wallet picker/form/repository/raw-snapshot validation. Currency changes during Android commit are revalidated. Early iOS payment uses the actually selected wallet. No amounts/currencies are rewritten. Actual Android installment payment/undo remains next; its existing metadata surfaces now enforce the selected rule.

Runtime financial rule RED/GREEN on both platforms; final1244 JVM/122 suites, Swift609, complete unsigned generic-iPhone app build, Android lint/build/AndroidTest compile/package, contract15/localization and existing SQLite checks pass. Found/fixed shared installment amount-preview placeholder that blocked actual iOS string-symbol generation. Two new Room +one Compose fixtures compile only; ADB empty. Evidence/APK62/test APK/checksums: `evidence/2026-10-15-installment-same-currency.md`. All10 flagsfalse; no live production writes/deploy/migration. Full goal remains active.

## 2026-10-15 — installment payment/undo repository (APK63)

Implemented the real FinanceRepository installment payment/undo API with visible-source baseline, native installment schedule/loan-repayment category, exact Long same-currency spending, current affordability and shared receipt/statement/investment/settlement guards. Full raw financial dependencies/receipts are rechecked for atomic expense/category/paid-marker writes. Undo/repay keep one expense/occurrence identity and exact bases; bill-only automatic notifications remain isolated. Native payment sheet/actions and ordinary occurrence cloud push are still next, so the user flow is not yet complete.

Runtime22 new repository cases +49 existing bill cases pass; full1266 JVM/123 suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization and SQLite checks pass. Four new Room fixtures compile/package only; ADB empty. Evidence/APK63/test APK/checksums: `evidence/2026-10-15-installment-payment-repository.md`. All10 flagsfalse; no production writes/deploy/migration. Full goal remains active.

## 2026-10-15 — native installment payment/undo flow (APK64)

Wired actual payment/undo repository calls to pending/paid installment row actions and owned saveable native sheets. Same-currency picker/default/current-wallet revalidation, fixed exact amount, frozen confirmation, failure retention, dirty-wallet discard and busy/late-result/month/owner guards are implemented. Direct Swift review corrected an initial editable-amount draft: fixed installment payments display the amount read-only, matching DuePaymentSheet. Changed current-cycle status/amount/link/date holds the old confirmation; metadata-only ACK does not invalidate it.

Runtime10 new state cases pass after feature and review-regression RED/GREEN; full1276 JVM/124 suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization and SQLite checks pass. Nine new Compose/Room fixtures compile/package only; ADB empty. Evidence/APK64/database and planning test APK/checksums: `evidence/2026-10-15-installment-payment-ui.md`. All10 flagsfalse; no production writes/deploy/migration. Next: ordinary installment occurrence/undo push and recovery/maintenance, then remaining full APK1–4/RC. Full goal remains active.

## 2026-10-15 — gated installment skip/undo sync (APK65)

Implemented a dedicated nonfinancial skip/undo worker composed into the single due coordinator, with complete owned raw snapshot/queue/batch fences, atomic Room ACK/retry, exact Long/null payloads, source scheduling/read checks, bounded create/update races and cancellation/lost-response retry. Paid/link state and causal source-delete batches remain separate. Client capability defaults false and cannot be bypassed by a broad source list. Added a complete owner/source/month paged read after schema review found no source/month uniqueness constraint; observed other-ID financial siblings hold, live unlinked duplicates defer. Multi-record remote atomicity/duplicate recovery is still required before production readiness.

Runtime13 model +21 worker +10 HTTPS +one generic bypass regression pass; full1321 JVM/127 suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization and SQLite helpers pass. Six new Room fixtures compile/package only; ADB empty. Evidence/APK65/test APK/checksums: `evidence/2026-10-15-installment-skip-sync.md`. All10 flagsfalse; no production writes/deploy/migration. Next: coupled paid occurrence/payment undo sync and recovery/maintenance, then remaining full APK1–4/RC. Full goal remains active.

## 2026-10-15 — installment financial mutation coherence (APK66)

Strengthened the actual Room money-boundary validator: exact paid amount/link/time must match the single posted expense, all pending/paid duplicate markers and live linked expense undo writes must be covered, and tombstones preserve the prior financial record. Inner/outer/outbox clocks, actor/version/kind must agree. Legacy nil-link/nil-amount history and already-deleted expense undo remain supported; existing bill behavior is unchanged. This is a prerequisite guard, not completion of paid occurrence cloud synchronization.

Runtime10 new model cases pass after7 initial feature REDs and one clock-regression RED; full1331 JVM/128 suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization and SQLite checks pass. Three new Room fixtures compile/package only; ADB empty. Evidence/APK66/test APK/checksums: `evidence/2026-10-15-installment-money-contract.md`. All10 flagsfalse; no production writes/deploy/migration. Next prerequisite: defer generic transaction writes while referenced wallet/category outbox remains pending after domain retry/failure, then continue paid occurrence ACK/recovery and remaining full APK1–4/RC. Goal stays active.

## 2026-10-15 — transaction wallet/category dependency guard (APK67)

Closed an APK1 prerequisite found during installment payment-sync audit: transaction UPSERT waits for owned source/destination wallet/category queues, including blocked/future retries, and rechecks immediately before each remote write. Explicit nulls/unrelated/foreign queues do not block it; DELETE remains independent. Added a default-no-op before-write hook to the shared executor and cancellation checks around preflight callbacks. Existing coordinator policies retain their behavior. Missing-remote-parent repair and remote cross-record atomicity remain separate open work.

Runtime9 new transaction cases pass (four initial dependency REDs +one mid-fetch race RED); final25 transaction cases and full1340 JVM/128 suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization and SQLite checks pass. Existing database test APK is unchanged from66; no instrumentation execution; ADB empty. Evidence/APK67/checksum: `evidence/2026-10-15-transaction-dependency-guard.md`. All10 flagsfalse; no production writes/deploy/migration. Continue coupled installment paid occurrence/payment-undo ACK/recovery and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — installment paid-history ACK without remote writes (APK68)

Added a dedicated ACK-only coordinator, pure owned financial policy and atomic Room occurrence ACK/scoped retry using complete plan/due/ledger/wallet/queue/batch snapshots. It validates existing server paid history against the exact expense, wallet and currency, supports completed undo and restoration after a lost ledger-delete conflict, preserves raw unknown/null/Long payloads and holds observed sibling/financial drift. Composed inside the single due coordinator with no new remote write capability; new paid upload/live paid deletion remain unfinished. Corrected a compile-only skip ACK owner fixture to trigger after actual queue removal.

Runtime14 policy +11 worker cases pass after feature and review RED/GREEN; full1365 JVM/130 suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization and SQLite helpers pass. Five new Room fixtures compile/package only; ADB empty. Evidence/APK68/test APK/checksums: `evidence/2026-10-15-installment-paid-ack.md`. All10 flagsfalse; no production writes/deploy/migration. Next: native fixture execution feasibility, then paid write/undo/duplicate recovery and remaining full APK1–4/RC. Full goal stays active.

## 2026-10-15 — actual Room emulator execution (APK69)

Provisioned an official checksum-verified ARM64 CLI/emulator/default Android16 API36 image and isolated `mistia-api36-native` AVD. Executed the whole standalone database test APK: initial122 cases exposed6 setup failures from a missing required wallet in the skip ACK fixture. Corrected setup to use a same-currency USD wallet and reran: **122/122 actual Android Room instrumentation tests pass** across22 classes, including migrations, installment causal deletion/ACK/payment/undo and owner/CAS/rollback/disk assertions. Existing evidence's compile-only status is superseded only for these exact database fixtures; Compose and Samsung are still unverified. App69 installs/cold-launches on the emulator (startup smoke only).

Full1365 JVM/130suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization/SQLite/schema checks pass. Evidence/APK69/executed database test APK/checksums: `evidence/2026-10-15-native-room-emulator.md`. All10 flagsfalse; no production write/deploy/migration. Continue actual Compose workflows and remaining full APK1–4/RC; goal remains active.

## 2026-10-15 — actual payment Compose restoration fix (APK70)

Actual emulator execution of all9 installment payment workflows exposed a caller-wiring product crash: form saver received localized month text rather than canonical YYYY-MM. Fixed the saver key, preserved localized presentation and retained assertions. Also fixed fixture/reconstructed repository to load the required shared category catalog. After runtime RED, **9/9 Compose/Room workflows pass on API36**, including actual payment/undo/repay, restored wallet/discard/owner/month and late noncooperative response. This supersedes compile-only status only for those exact9 cases, not all planning/device gates.

Full1365 JVM/130suites, Swift609, lint/build, AndroidTest compile/package, contract15/localization/SQLite/schema checks pass. Evidence/APK70/executed planning test APK/checksums: `evidence/2026-10-15-native-payment-restoration.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue full planning workflows and remaining full APK1–4/RC; goal remains active.

## 2026-10-15 — full planning Compose emulator evidence

Executed the entire APK70 planning test package on API36 emulator: **33/33 Compose cases pass** across bill payment4, budget/savings/bill workflow7, installment read2/editor11/payment9. Saved seven synthetic fixture screenshots and inspected representative light/dark/font-large views. Full visual/iOS/accessibility/Samsung/process-kill/live-sync parity remains unproven. Screenshot review found a concrete JPY fractional-digit formatting mismatch (`¥600.00` under English locale); fix next with runtime regression. Evidence-only checkpoint uses unchanged APK70/build checks.

Evidence: `evidence/2026-10-15-native-planning-suite.md`; screenshots under `evidence/2026-10-15-planning-emulator/`. All10 flagsfalse; full APK1–4/RC goal remains active.

## 2026-10-15 — exact currency presentation (APK71)

Fixed shared formatter's locale-inherited fraction digits observed on actual budget screenshot: JPY/VND render without fractions; existing imported USD2/KWD3 precision and exact BigDecimal/Long amounts remain intact. Currency presentation locale follows the Swift map independently of app/device language. Five runtime formatter cases pass after4 intended REDs. A native budget CRUD regression verifies rendered JPY600 while storage stays600 minor; updated screenshot inspected. Imported non-JPY/VND Swift parity remains an explicit monetary-audit gap.

Full1370 JVM/131suites, Swift609, lint/build, contract/localization/schema/SQLite checks pass. Full planning rerun exposed one Room fixture teardown race; corrected RuleChain ordering to dispose Compose before database close, then **33/33 actual API36 Compose cases pass**. Evidence/APK71/final executed test APK/checksums: `evidence/2026-10-15-currency-presentation.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue native management and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — actual management Compose evidence

Executed full unchanged APK71 management test package on API36 emulator: **5/5 cases pass** (statement read/navigation3, title localization2). Exact paid total/charge locks, bounded/cancelable month navigation, card-row/edit routing and language/foreign-category scoping assertions now execute natively. This is evidence for those fixtures only; card payment/undo/currency choice and Samsung/visual/live-sync/background gates remain open. No new app version/code change for this checkpoint.

Evidence/executed test APK/checksum: `evidence/2026-10-15-native-management-suite.md`. All10 flagsfalse; full APK1–4/RC goal remains active.

## 2026-10-15 — bill grouped amount input (APK72)

Matched Swift's JPY/VND bill editor grouping during typing and existing-record presentation while preserving exact minor/null and invalid-input validation. Imported fractional currencies keep existing Android decimal semantics; full cross-platform import audit remains open. Extracted the existing installment grouping implementation into a reusable planning helper without changing its behavior. Five new runtime cases pass after4 intended REDs; actual API36 bill workflow verifies grouped input and exact >2^53 stored amount; screenshot inspected.

Full1375 JVM/131suites, Swift609, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK72/executed focused test APK/checksums: `evidence/2026-10-15-bill-grouped-input.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue budget/savings monetary forms and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — budget grouped minor input (APK73)

Matched Swift JPY/VND grouping while typing/opening budgets without changing positive/exact minor parsing, branch currency/clear rules or owned month/identity. Common supported-currency selector is shared with bills; imported fractional input remains unchanged. Four new state cases pass after3 intended REDs; actual API36 budget CRUD creates/reopens exact >2^53 grouped amount, edits and deletes with correct outbox.

Full1379 JVM/131suites, Swift609, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK73/executed focused test APK/checksums: `evidence/2026-10-15-budget-grouped-input.md`. Direct Swift review identified amount calculator action still missing on Android; separate slice follows savings grouping. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Full APK1–4/RC goal remains active.

## 2026-10-15 — savings target/current grouping (APK74)

Matched Swift JPY/VND grouping for both savings fields during input/opening, retaining exact positive target/signed-or-empty current, owned restoration, original date/identity and fractional-import semantics. Four new runtime state cases pass after3 intended REDs; actual API36 savings CRUD verifies grouped target/current before save and after reopen plus exact persistence/edit/delete/outbox.

Full1383 JVM/131suites, Swift609, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK74/executed focused test APK/checksums: `evidence/2026-10-15-goal-grouped-input.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue native amount calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — native budget calculator (APK75)

Added native calculator entry to JPY/VND budget fields: exact BigDecimal/Long arithmetic, Swift operator/keypad semantics, positive integer validation, draft-only OK/cancel, owned expression restore. Shared36 vectors execute against actual Swift and Kotlin, plus6 input-state tests. Runtime RED/GREEN includes3 native workflows; final **36/36 planning cases pass** on API36 emulator. Inspected light/dark-font130 screenshots. Other forms and imported fractional currencies remain separate work.

Full1390 JVM/133suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK75/executed test APK/checksums: `evidence/2026-10-15-budget-calculator.md`. Two accessibility labels added to sole catalog and outputs regenerated. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue bill calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — native bill calculator (APK76)

Wired JPY/VND optional bill amount to shared native calculator, retaining blank/null, exact minor and draft-only OK/cancel semantics. Owner/bill/currency expression restore and busy/focus handling are scoped. All3 native API36 workflow cases pass after3 missing-entry REDs; real Room/outbox verifies no write before Save, exact >2^53 result, optional-null save and owner isolation.

Full1390 JVM/133suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK76/executed test APK/checksums: `evidence/2026-10-15-bill-calculator.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue savings calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — savings calculator and Decimal review fixes (APK77)

Wired separate JPY/VND savings target/current calculator actions, owned selected-field/expression restore, draft-only OK and signed-current Cancel. Three native RED/GREEN workflows verify exact persistence/outbox, field isolation and owner reset. Complete planning42 passes before final math corrections; all9 budget/bill/savings calculator workflows pass on the final artifact. App update/cold-launch smoke passes on isolated emulator.

Review expanded actual Swift/Kotlin calculator goldens36→86 and fixed later divide-zero priority, coefficient-based division, whole-limb exponent normalization for division/addition, and pre-compaction product exponent checks. Runtime RED/GREEN recorded for observed errors; no Swift runtime change. Full1390 JVM/133suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK77/executed package checksums and distinct earlier42-case artifact: `evidence/2026-10-15-savings-calculator.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue installment calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — native installment cycle calculator (APK78)

Wired raw-minor amount-per-cycle to shared calculator with draft-only OK/cancel, busy/focus and owner/id/currency expression restore. Four native RED/GREEN cases prove exact >2^53 metadata save, USD raw-minor preservation/preview, unchanged queue before Save and unchanged ledger/wallet, invalid/cancel and id/owner isolation. Calculator4 plus existing editor11: **15/15 API36 cases pass**. Imported non-JPY/VND full Swift formatting parity remains open.

Full1390 JVM/133suites, Swift610/86calculatorvectors, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK78/executed test APK/checksums: `evidence/2026-10-15-installment-calculator.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue monetary management/transaction forms/settings audit and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — wallet opening-balance grouping (APK79)

Matched supported JPY/VND wallet opening-balance grouping without changing signed/exact Long, blank/invalid/overflow, imported decimal or immutable existing opening balance. Existing planning helper moved unchanged to core model for shared form presentation. Four new state cases pass after3 intended REDs; actual API36 management6/6 includes exact >2^53 wallet save/outbox with no ledger entry.

Full1394 JVM/133suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK79/executed test APK/checksums: `evidence/2026-10-15-wallet-grouped-input.md`. Wallet calculator/current-balance adjustment and imported-currency full parity remain open. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue next monetary form slice and full APK1–4/RC; goal stays active.

## 2026-10-15 — owned wallet opening-balance calculator (APK80)

Wired new-wallet JPY/VND calculator with exact draft-only OK, signed Cancel and explicit Save. Added owner-enveloped safe draft restoration, owner/record subtree keys, foreign-wallet rejection and expression scope. Actual native TDD also exposed a late NonCancellable save dismissing the next owner's draft; post-callback cancellation checks fix save/archive handling. State2 RED/GREEN; final **11/11 management API36 cases pass**, including5 new calculator/ownership/late-response workflows.

Full1396 JVM/133suites, Swift610/86calculatorvectors, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Evidence/APK80/executed test APK/checksums: `evidence/2026-10-15-wallet-calculator.md`. Existing-balance adjustment and other monetary forms/full imported-currency parity remain open. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue credit-limit/transaction monetary forms and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — guarded regular-wallet currency edits (APK81)

Direct Swift audit found Android could retag a wallet currency despite active linked ledger history. Added current-owner/source/destination policy, conservative malformed-dependency holds and exact wallet-baseline/current-ledger checks inside atomic Room wallet/outbox commits. Raw opening money and sync-version coherence prevent silent corrupt-data rewrites. Owned loaded UI disables currency appropriately; stale forms get localized rejection. Source/destination Room REDs, policy9 RED/GREEN, corrupt-money RED and UI lock RED recorded. Native reruns also exposed initial wallet loading stuck after ledger recomposition; stable owner/repository Flow instances and lifecycle-aware owned ledger collection fix it with original assertions/timeouts intact.

Final1405 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass; actual **Room130/130 and management13/13** pass. Evidence/APK81/executed packages/checksums: `evidence/2026-10-15-wallet-currency-guard.md`. One catalog key regenerated on both platforms. Card currency edits, investment-cash protection and older-wallet-snapshot transaction/remote races remain open; no blanket atomicity claim. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue card currency guard, then credit-limit/transaction monetary forms and full APK1–4/RC; goal stays active.

## 2026-10-15 — guarded credit-card currency edits (APK82)

Existing-card saves now compare exact wallet/profile baselines and current ledger dependencies inside one Room transaction with both outboxes/owner fences. Enforces Swift active/unarchived source-or-destination currency lock, linkage/duplicate/malformed/deleted aggregate holds and exact independent Long versions. Canonical ID lookup/canonical write-owner checks close runtime-reproduced create-route bypasses in both regular-wallet and card saves. UI applies owned loaded-history lock and localized stale rejection. Card currency payment policy remains pending separately.

Final1405 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Actual **Room145/145, management15/15** pass. Fresh read-only review found no Critical/Important/Minor issue in the slice. Scope rulings preserve creation/payment-source concurrency, editor-opening version tokens and corrupt-identity recovery as separate required follow-ups. Evidence/APK82/executed packages/checksums: `evidence/2026-10-15-card-currency-guard.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue credit-limit input/calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — credit-card limit grouping (APK83)

Matched supported JPY/VND limit grouping during typing/opening while preserving exact nonnegative Long, blank/invalid/overflow and imported decimal behavior. Four new JVM cases with2 intended runtime REDs;2 actual Compose→Room workflows with2 intended ungrouped-input REDs. Final **17/17 management cases pass**: exact >2^53 create/reopen/edit, identity/opening balance and coalesced exact profile outbox. Native fixture baseline assumption corrected to cloud-version preservation0; production version behavior unchanged.

Full1409 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema checks pass. Independent review found no issues in bounded slice. Evidence/APK83/executed test APK/checksums: `evidence/2026-10-15-card-limit-grouped.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue owned card calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — owned credit-card limit calculator (APK84)

Added JPY/VND card calculator with draft-only OK/cancel, focus/busy handling, owned expression restoration and explicit owner/card/profile scope. Foreign/incomplete supplied aggregates are hidden; malformed/foreign/id-mismatched restored drafts rejected; late NonCancellable save cannot dismiss a new owner's draft. Six native intended REDs then focused6green;2 JVM saver REDs with envelope removed then green. Full management **23/23 pass** on final diagnostic artifact.

Full1411 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace checks pass. Independent review found no Critical/Important issue; whitespace fixed. One earlier full23 run had an existing initial card-row wait timeout before editor entry; unchanged diagnostic rerun passed. Failure-only lifecycle/Room/tree diagnostics retained; cause and remediation remain unproven, explicitly tracked. Evidence/APK84/executed test APK/checksums: `evidence/2026-10-15-card-calculator.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue card creation atomic fences and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — atomic credit-card creation guards (APK85)

Create-only capability now checks canonical/raw identity and zero version, absent both records/outboxes and no preexisting profile link in the same Room transaction as dual writes, with current-owner fences before/after. Default LocalStore fails before writes when capability unsupported. Ten native cases with8 intended REDs then **155/155 full Room pass**; JVM default-capability RED then4card casesgreen. Full JVM exposed9 old fixture dependencies on unsafe fallback;2test stores now explicitly batch validated pairs without weakening production/default or domain assertions.

Full1412 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace checks pass. Full management **23/23 pass**; emulator update preserving data and cold MainActivity launch pass, installed version85 confirmed. Independent review found no Critical/Important issues. Evidence/APK85/executed packages/checksums: `evidence/2026-10-15-card-create-guard.md`. APK84 intermittent initial row-delivery concern remains unproven; no remediation claim. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue payment-source live validation and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — live source-wallet validation on card save (APK86)

Both create/edit transactions now re-read selected source eligibility immediately before dual aggregate/outbox writes: canonical non-self ID, matching owner/raw live record, literal false archive flag and known non-card kind. Clearing remains allowed; valid source metadata/version changes and its queue remain untouched. No source/card currency rule added. Nine native cases with7 intended create REDs, then7 separate edit=true REDs, then **164/164 full Room pass**. Full management **23/23 pass**.

Full1412 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace checks pass. Independent review found no issues. Evidence/APK86/executed packages/checksums: `evidence/2026-10-15-card-source-guard.md`. Latest installed app smoke85; no Samsung/live production writes/deploy/migration. All10 flagsfalse. Prior intermittent startup delivery concern remains unproven. Continue remaining transaction monetary forms and full APK1–4/RC; goal stays active.

## 2026-10-15 — transaction source/destination grouping (APK87)

Added supported JPY/VND grouping during source/manual-destination typing, reopen/receipt prefill and app FX display; exact parsing and existing imported decimal/FX algorithms retained. Four initial JVM cases with3 intended REDs,2 native intended REDs; independent review caught source-switch/amount-first regression. Added2 actual native REDs and2 JVM cases, fixed currency-aware source selection without changing imported major-unit meaning. Reviewer confirmed resolution. Final **4/4 transaction native cases pass** for >2^53 manual pair/create/reopen/edit/outbox, read-only app FX exact pair/provider/date, USD switch save and amount-before-wallet.

Full1418 JVM/134suites, Swift610, lint/build, database/management/planning/transaction AndroidTest compile, database/transaction test APK assembly, contract/localization/SQLite/schema/whitespace checks pass. Evidence/APK87/executed test APK/checksums: `evidence/2026-10-15-transaction-grouped-input.md`. All10 flagsfalse; latest installed smoke85; no Samsung/live production writes/deploy/migration. Continue owned transaction calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — owned transaction editor and completion callbacks (APK88)

Explicit owner now scopes transaction editor/receipt/prefill subtree, saved draft envelope and wallet/category candidates; foreign supplied records hidden. Both screen and notification-top-up callers use the guarded editor. Post-save active-job check blocks late noncancellable response from dismissing/advancing a new owner's draft. Five new native cases with4 intended REDs;2 JVM saver runtime REDs then green; intermediate native still reproduces late callback before postcheck. Existing monetary fixture random-UUID ordering assumption corrected to complete unchanged records byID. Final **9/9 transaction native cases pass**.

Full1420 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace checks pass. Independent review found no blocking issue; additional receipt/foreign-category native QA remains scoped future coverage. Evidence/APK88/executed test APK/checksums: `evidence/2026-10-15-transaction-owner.md`. All10 flagsfalse; latest installed smoke85; no Samsung/live production writes/deploy/migration. Continue source/manual-destination calculator and remaining full APK1–4/RC; goal stays active.

## 2026-10-15 — amount-only manual FX parity (APK89)

Direct Swift audit found the manual editor should accept exact source/destination amounts without entering a rate. Removed extra manual rate field/requirement and clears stale editor rate/date metadata, provider manual; raw legacy drafts retain valid supplied metadata. APP_RATE still requires a positive real rate and stores its snapshot. Four intended JVM REDs and2 actual native REDs then green. Final **1425 JVM/134suites,164/164 Room and11/11 transaction native** pass; Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace checks pass. Read-only independent review found no issues. Local nullable-column/investment-only trigger audit confirms contract compatibility; no live Supabase query/schema change.

Evidence/APK89/executed packages/checksums: `evidence/2026-10-15-manual-fx-parity.md`. All10 flagsfalse; latest installed smoke85; no Samsung/live production writes/deploy/migration. Prior management startup concern remains unproven. Continue transaction calculator and full APK1–4/RC; goal stays active.

## 2026-10-15 — owned source/manual-destination transaction calculator (APK90)

JPY/VND source and manual cross-currency destination fields now use the shared calculator, exact grouped draft-only OK, cancel/error preservation, APP_RATE source recalculation, focus/busy handling and scope envelopes for owner/record/kind/subtype/wallet pair/currencies/mode. Six native intended REDs; one intermediate read-only destination fixture selector corrected without changing financial assertions. Final **17/17 transaction native** pass. Full1425 JVM/134suites, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass; independent review finds no code issues.

Evidence/APK90/executed test APK/checksums: `evidence/2026-10-15-transaction-calculator.md`. API36 install-r/cold launch/installed version90 verified; no Samsung/live production writes/deploy/migration. All10 flagsfalse. Unselected/imported-currency calculator parity and prior management startup concern remain open. Continue ordinary transaction atomic save guards, reporting FX and full APK1–4/RC; goal stays active.

## 2026-10-16 — atomic ordinary transaction validation/read set (APK91)

saveTransaction now validates from one complete raw owner snapshot of ledger/wallet/category/card-profile/due-occurrence data, then compares that read set in the same Room transaction as record/outbox writes. Owner fences before/after, target envelope/version/tombstone and orphan-queue holds; unsupported capabilities fail before writes. Eleven actual runtime REDs, then corrected paid-period fixture and fresh-policy lock assertion; supplemental removed-guard3native/unsafe-fallback1JVM REDs prove rollback/version/create/default fences. Final **1426 JVM/134suites,179/179 Room and17/17 transaction native** pass. Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace checks pass. Independent review plus supplemental re-review reports no findings.

Evidence/APK91/executed packages/checksums: `evidence/2026-10-16-transaction-save-guard.md`. App build91, latest installed smoke90; API36 only, no Samsung/live production writes/deploy/migration; all10 flagsfalse. Editor-opening version tokens, malformed-numeric/imported data recovery, investment allocation, reporting FX, prior management startup concern and full APK1–4/RC remain open. Continue remaining currency/reporting functionality; goal stays active.

## 2026-10-16 — exact income/expense reporting conversion persistence (APK92)

TransactionDraft now supports explicit reporting currency/Long amount with manual nil-rate or app-rate metadata, exact source/report pairing, same-source clearing and transfer clearing/rejection. Absent explicit reporting input can preserve complete legacy conversion for metadata-only edits; monetary edits require refreshed conversion. Nine model intended runtime REDs and3 actual Room REDs then green. Reviewer Minor persisted-readback gap fixed and re-reviewed; no remaining findings.

Final **1435 JVM/134suites,182/182 Room and17/17 transaction native** pass; Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. Evidence/APK92/executed packages/checksums: `evidence/2026-10-16-reporting-fx-model.md`. App92 build, latest installed smoke90; API36 only, all10 flagsfalse, no Samsung/live production writes/deploy/migration. Real API persistence is verified; native reporting form and device currency settings remain next required slices. Existing imported/investment/editor-baseline/startup/RC gaps remain; goal stays active.

## 2026-10-16 — owned native reporting conversion form (APK93)

Income/expense now expose exact manual reporting input/calculator or automatic pair calculation from the supplied primary currency. APP_RATE extra amount/rate fields hidden to match Swift. Reporting text binds its original currency; reviewed USD→JPY relabeling bug and normalization issue reproduced with2 JVM/2 native REDs and fixed. Initial8 state/8 native REDs; eleven new native workflows cover exact create/edit/persistence/outbox, scope isolation, missing-rate recovery, busy state and visual font130%. Independent re-review finds no remaining issues.

Full **1445 JVM/134suites,28/28 transaction native** pass; Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. Visual QA exposed test manifest target26 warning overlay; transaction test target36 verified, stale own-fixture warning dismissed and clean4PNG light/dark130% inspected. Earlier covered images are not physical UI proof; other module targets/management startup concern remain open. Evidence/APK93/executed package/checksums: `evidence/2026-10-16-reporting-form.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Primary defaultsJPY until device settings connection next; full APK1–4/RC remains active.

## 2026-10-16 — device currency preferences/settings and configured rates (APK94)

Added Swift-default JPY/manual165 device preferences, enabled/primary constraints, direct/inverse8-place manual editing, localized settings/navigation, configured manual/automatic rate wrapper and forced-refresh path. Current primary reaches real TransactionsScreen/editor; delayed automatic result cannot replace manual selection. Initial7 model/4network/4native REDs plus current-primary native and blank-reopen JVM/native regressions, then green. Reviewer Minor disk-reload evidence gap fixed with separate write/force-stop/read invocations and distinct-PID assertion; no remaining findings.

Final **1457 JVM/136suites,29/29 transaction native,10/10 settings native**,2 explicit process phases pass; Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. Four light/dark130% screenshots inspected. App94 install-r/cold launch/version smoke passes. Evidence/APKs/executed packages/checksums: `evidence/2026-10-16-currency-settings.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Enabled-currency picker integration and aggregate primary totals remain next; full APK1–4/RC goal stays active.

## 2026-10-16 — enabled currency choices in wallet/card forms (APK95)

Real application settings now filter choices through ManagementScreen into both owned editors. Retains visible current stored/draft code when disabled, exact money, history locks and calculator expression across live settings changes; Swift new-formJPY default retained explicitly. Five actual native REDs then5focusedgreen; full **30/30 management native** pass with two supplemental exact calculator/visual cases. Final visual capture strengthened to show both currentJPY and VND choice; separate final artifact1/1pass and four light/dark130% replacements inspected. Independent review plus supplemental review finds no issues.

Full **1457 JVM/136suites**, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. Evidence/app95/full30/final-visual1 packages/checksums: `evidence/2026-10-16-enabled-currencies.md`. Management test target36; older startup concern remains unproven. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue primary planning summary/new-form consumers and remaining full APK1–4/RC; goal stays active.


## 2026-10-16 — primary currency in planning summaries and sheet focus QA (APK96)

Current app primary now reaches budget/goal exact aggregation and all summary formatting; separate branches/individual goals keep original money/currency. Four native intended REDs then focusedgreen; missing rates, inverse/live rate updates, foreign owner exclusion and exact >2^53 totals verified with complete raw rows/outboxes unchanged. Actual visual QA found a monthly amount splitting midnumber; runtime layout RED then FlowRow fix. Four light/dark130% corrected images inspected; test host matches production parent Scaffold.

Full regression uncovered legacy sheet focus bugs; actual bill category/name and wallet/amount, installment wallet/amount and goal/budget calculator/amount focus REDs now pass after sheet-local focus/clear fixes. Physical assertions retained with failure-only diagnostics. Earlier installment failed-save missing-error and savings save-wait symptoms remain causally unproven; separate isolated/class reruns passed. Final **55/55 native planning passes293.211sec**; prior interrupted/failing runs retained separately. Independent review and supplemental re-reviews report no remaining findings. Full **1457 JVM/136suites**, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass.

Evidence/app96/executed packages/preserved failing artifacts/checksums: `evidence/2026-10-16-planning-reporting-currency.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. New planning defaults and owned savings editor remain next, plus broader imported/investment/startup/full APK1–4/RC gaps. Goal stays active.


## 2026-10-16 — owned savings editor and current primary defaults (APK97)

New goals now consume actual PlanningScreen primary; existingJPY/importedUSD retain their stored minor-unit meaning. Whole editor keyed by owner/record/currency, foreign supplied goals hidden, scoped saved-state envelope validates outer/inner identity/code/dates, and cancelled old save/delete completion cannot close a replacement draft. UI guards do not provide repository atomic/read-set/opening-baseline protection. Initial3 saver runtime REDs plus malformed-date RED, then focused13green. Corrected native9 has7 intended REDs, then **9/9green33.021sec**; exactVND >2^53 persistence/outbox, signed current, ownership/record/primary/callback workflows covered.

Full **1461 JVM/137suites**, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. Captures strengthened to wait for stable compositor frames; visual1/1green7.05sec and all4 replacement light/dark130% PNGs inspected. Independent review finds no issues. Final **64/64 native planning passes302.993sec**. App97 install-r/cold start Statusok1228ms and installed version97 confirmed. Evidence/app97/executed test package/checksums: `evidence/2026-10-16-owned-savings-editor.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue owned bill editor/primary, then remaining planning consumers and full APK1–4/RC; goal active.


## 2026-10-16 — owned bill editor and current primary defaults (APK98)

Current app primary now reaches new bills, existingJPY/importedUSD keep currency/minor meaning/payment wallet. Foreign supplied records hidden; whole editor keyed owner/record/currency, scoped18slot envelope validates identity/code/calendar/day/frequency while preserving legacy24. Shared save/pause/resume/archive callbacks check cancellation before/after; repository atomic/opening-baseline guards remain separate. Four saver actualREDs then **20 focused JVMgreen**; native8 had6 intended REDs then **8/8green30.718sec**, supplemental settled visual1/1green8.841sec. RealScreen→Room/outbox exactVND >2^53, onlysamecurrencywallet, imported/currentrecord/scope/late-save-pause covered. Independent review finds no issues.

Full **1465 JVM/138suites**, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. All4 light/dark130% PNGs inspected. Final **73/73 native planning passes377.191sec**; app98 install-r/cold start Statusok1605ms/version confirmed. Evidence/app98/executed test package/checksums: `evidence/2026-10-16-owned-bill-editor.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue installment primary/scoped creation and remaining budget/due/overview/family/investment/imported/full APK1–4/RC; goal active.


## 2026-10-16 — current-primary installment creation and scoped editor (APK99)

PlanningScreen primary now reaches new installment navigation; changing primary resets only active creation to a freshID, preserving any legitimately committed oldcurrency plan. Existing edit keeps stored currency/frozenbaseline, and foreign/archived/deleted/route-mismatched originals are hidden. Whole editor/saved envelope bind owner/route/currency/create-vs-edit. Swift rawinteger installment contract retained including importedUSD1375÷5=275; broader imported presentation remains open. Initial3 saver actualREDs then17focusedJVMgreen; native8 had6 intendedREDs then8/8green31.91sec, visual1/1green8.595sec. ExactVND >2^53 Room/outbox, onlysamecurrencywallet, liveprimary/ownedbaseline/late-save workflows covered. Independent read-only review finds no issues.

Full **1469 JVM/139suites**, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. All4 settled light/dark130% PNGs inspected. Final **82/82 native planning passes351.55sec**; app99 install-r/coldstart Statusok1036ms/version confirmed. Evidence/app99/executed test package/checksums: `evidence/2026-10-16-primary-installment-editor.md`. All10 flagsfalse; no Samsung/live production writes/deploy/migration. Continue owned budget/primary defaults and remaining due/overview/family/investment/imported/full APK1–4/RC; goal active.


## 2026-10-16 — owned budget editor and current-primary defaults (APK100)

New budget now consumes real current primary; existingJPY/importedUSD retain money/currency/identity and unsaved draft across primarychange. Branch inheritance/onecurrency rule preserved and old input clears when branchcurrency changes. Whole editor/saved envelope scopes owner/record/month/initialcurrency, permits legitimate freshchip/branch overrides, rejects malformed calendars/mismatchedinnercontext and hides foreign supplied plan. Save/sharedarchive-delete check cancellation before/after; repository atomic/opening-baseline guards remain separate. Four actual saverREDs then14focusedJVMgreen; correctednative10 had7 intendedREDs then10/10green35.833sec, settledvisual1/1green8.376sec/all4 light/dark130% inspected. Independent review and supplemental reviews find no issues.

Full **1473 JVM/140suites**, Swift610, lint/build, AndroidTest compile/package, contract/localization/SQLite/schema/whitespace pass. Firstfull93 had1 oldinitial-Add lookup failure; sameartifactisolatedgreen, added strictloaded-node wait, class12/12green. Secondfullaborted afterknownoldpaymentdiscard failure; unchangedclass4/4green, originalClose now scrolls/assertsvisible then physicalclick/waitsactualdiscard withfailure-onlydiagnostics; focused4/4green. No productionchange, timingcauseunproven. Final **93/93 planningnative passes405.908sec**; app100 install-r/coldstart Statusok1178ms/versionconfirmed. Failing/intermediate packages and logs preserved separately. Evidence/APKs/checksums: `evidence/2026-10-16-owned-budget-editor.md`. All10 flagsfalse; no Samsung/liveproductionwrite/deploy/migration. Continue actual Overview recent projection, remaining due/family/investment/imported/full APK1–4/RC; goal active.


## 2026-10-16 — owned recent Overview projection (APK101)

Recent Overview now filters owner/envelope/payload identity, posted ordinary status, tombstone/archive/unknownkind/malformedamount/calendar before sorting parsedoccurred/created and taking5. Source exact Long/currency preserved; ownedsourcewallet then actualprimaryfallback, never reporting/destination relabeling. Ownerkey removes priorrows/counts before replacementflow emits. Initial5JVM4actualREDs then5green; native5 had4intendedREDs then5/5green7.326sec. RealRoom/outbox readonly assertions and mixedscope/emptyflow tests pass. Independent review finds no issues.

Font130 broadComposeoverflowflag was a testdiagnostic, not productRED: fullglyph line583.75854 in585box whileparagraphwidth871. Corrected exacttext/one-line/noellipsis/fullend/perglyphbounds checks and inspected2finalPNGs. Final **6/6Overviewnative passes9.255sec**. Full **1478JVM/141suites**, Swift610, lint/build12sec, AndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass. App101 install-r/coldStatusok1058ms/versionconfirmed. Evidence/APKs/checksums `evidence/2026-10-16-overview-recent.md`. All10flagsfalse, noSamsung/liveproductionwrite/deploy/migration. Relativetime/cashflow/icons/navigation/hero/fullOverview and broaderAPK1–4/RC remain required; continue recentrowpresentation. Goalactive.


## 2026-10-16 — recent Overview row presentation (APK102)

Recent rows now have exact signed originalmoney, cashflowtints, ownedcategory/kindicons and localizedrelative labels. Swift family/debt/paid-for category specialcases preserved; Japan/Vietnam calendar/min/hour/future thresholds covered. Flexible groupedrow retains complete amounts atfont130. Parent clock refreshesonresume/minute whileRESUMED, cancelsbelowRESUMED. Native lifecycle verifiespaused1min/resumed1hr fromadvancedclock; actual60sectick unmeasured. Initial5JVM/3native intendedruntimeREDs thenfocused10JVM/9nativegreen; staticclockstub additionalactualRED then final **10/10Overviewnative passes14.871sec**. Two settled light/dark130% images inspected, exactsignedamount/fullglyph assertions pass. Independentreview/supplement report nofindings.

Full **1483JVM/142suites**, Swift610, lint/build11sec, AndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass; app102install-r/coldStatusok1229ms/versionconfirmed. Evidence/APKs/checksums `evidence/2026-10-16-overview-recent-presentation.md`. All10flagsfalse, noSamsung/liveproductionwrite/deploy/migration. Continue actual recenttransactioneditornavigation then Overviewhero/remainingAPK1–4/RC; goalactive.


## 2026-10-16 — stored transaction editor from Overview (APK103)

Actual recent-row tap now opens owned stored form at app root while retaining Overview/tab. Owner/UUID-only savednavigation, owner-scoped dependency loading/retry, strict amount/calendar and identity guards hold invalid/missing/foreign/unsupported/paid targets before editing. Route/receipt work keyedowner/id; receipt envelope checked beforebytes, latecancelled save/receipt cannot affectreplacement, saved-state ownedunsaveddraft restored. Existing importedUSD and explicitVND reporting pair retained. Shared transaction sheet now openslarge perSwift. Generic editor-opening baselines/atomicreceipt-financial updates/fullAPK3 semantics remain separate.

Navigation3actualREDs then3green; correctednative5actualREDs then5green, supplemented10green. Excluded categoryfixture/field-position criterion diagnostics; correctedinitial-heading actualRED and malformeddate actualRED then final **15/15focusednative passes39.389sec**. All4finalsettledlight/dark130% imagesinspected; halfheightimages diagnostic only. Independentreview/finalsupplement nofindings. Final **44/44transactionnative passes169.08sec**, Overview10/10green14.857sec. Full **1486JVM/143suites**, Swift610, lint/build51sec, AndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass. App103install-r/coldStatusok2663ms/versionconfirmed. Evidence/APKs/executedchecksum: `evidence/2026-10-16-overview-transaction-editor.md`.

All10flagsfalse; noSamsung/liveproductionwrite/deploy/migration; Room6/SwiftDataV11/iOS751 unchanged. Continue Overviewmonthlyfinancialsummary/hero/charts/alerts plusfamily/investment/imported/editoratomicity/receiptdeviceQA/fullAPK1–4/RC. Goalactive.


## 2026-10-16 — Overview monthly cashflow (APK104)

Owner-scoped continuous monthly income/expense projection and current realOverviewmetrics now use live appprimary/rates. Swift signed/zero overrides, debt/resale/legacy income, paid-for, adjustment/card/installment exclusions preserved; source-rate direct/inverse conversion ignores snapshotpair in thisaggregate perSwift. Exact BigInteger conversion/sum clamps only at finalboundary, aftercancellation. Strict rawamount/optionalreporting/calendar/envelope guards beforelegacydecoder; originalRoom/outbox untouched. Current JPY/VND reporting normalization/imported audit and family archived-event visibility remain separate.

Initial9model8actualREDs then9green, conversionoverflow/invalidrate supplement totals10newcases. Excluded unstablefakeflow fixture, R-import compile and staleAPKdiagnostics; correctednative5intendedREDs7.226sec then **6/6focusedgreen9.734sec**. Two settledlight/dark130% imagesinspected withfullLongMIN/MAX andperglyphbounds. Independentreview nofindings. Final **16/16Overviewnative passes24.861sec**, actualOverviewtap→storededit integration1/1green3.767sec. Full **1496JVM/144suites**, Swift610, lint/build72sec, AndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass. App104install-r/coldStatusok1090ms/versionconfirmed. Evidence/APKs/executedchecksums `evidence/2026-10-16-overview-monthly-cashflow.md`.

All10flagsfalse; noSamsung/liveproductionwrite/deploy/migration; Room6/SwiftDataV11/iOS751 unchanged. Continueassetbalance/hero/charts/alerts and remainingfamily/investment/imported/editoratomicity/receiptdeviceQA/fullAPK1–4/RC. Goalactive.


## 2026-10-16 — Overview available assets and remaining inventory (APK105)

Real hero now shows active owned noncredit-wallet cash plus latest remaining investment cost, with current primary/rates. Original source/destination legs, postedfuture, family/debt/shared/resale cash semantics matchSwift. Activeownedasset/channel/position orderingoccurred-created-UUID, positivefractionalquantity/nonnegativecost, sold/malformedlatest holds and independentcrossplatform systemwalletSHA256 golden covered. Exact intermediatebalances/conversion/sums clamp only atfinaldisplayboundary. Sharedfinancialrawguards now validate destinationleg/walletopening; originalrows/outbox untouched. FullInvestmentCRUD/RPC/permissions/APK4 remains separate.

Model10actualREDs then46focusedgreen; final15newmodelcases coveroverflow/inventory/scoping/currency. Native6actualREDs8.766sec then6/6green9.88sec. AdditionalactualRED1.85sec exposed malformedcashopening droppingvalidinventorycurrency (¥7vs¥3); independentownedmetadatacurrencyfix plusmodel/native regression added. Independentreview/supplement nofindings. Firstfull23had22pass/1oldclipped-orderassertion35.321sec; unchangedproduction, testnow measuresunclippedorder and physicallyscrolls/allrowsdisplayed, focused1green2.248sec. Final **23/23Overviewnative passes35.491sec**, Overviewtap→storededit integration1green3.472sec. Bothfinal light/dark130% PNGsinspected withfullLongMAXasset. Full **1511JVM/145suites**, Swift610(newUUIDgolden), lint/build65sec+testlint3sec, AndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass. App105install-r/coldStatusok1320ms/versionconfirmed.

Evidence/APKs/preservedfirstfailingtest/executedchecksums `evidence/2026-10-16-overview-assets.md`. All10flagsfalse; noSamsung/liveproductionwrite/deploy/migration; Room6/SwiftDataV11/iOS751 unchanged. Continue daily/categorycharts/drilldowns/budget-due-configsections plusfamily/investment/imported/editoratomicity/receiptdeviceQA/fullAPK1–4/RC. Goalactive.


## 2026-10-16 — Overview weekly daily spending chart (APK106)

Real hero now shows exact owned Monday–Sunday daily bars and continuous weekly history through currentweek, emptygaps/futuredays/currentfallback, liveprimary/perrecordFX, signedexpenseclassification and finite intensity. Positivebartap/toggle/exactcallout, zero/swipe/heading/overlay/background clears, ownerreplacement, stableprependedweek and removedhistoryreset covered. BigInteger exact aggregation/clamp only atdailyboundary; floatingpoint is visual only. Daydetail/categorydrilldowns remain requirednextslices.

Initial10modelcases8intendedruntimeREDs→20focusedgreen;7/7native missingchartREDs10.276sec. Compile/semantics/fixture equality diagnostics separated in evidence. Independent review2P2s (axis clipping/physicalcallout hitinterception) actual2/2RED→green, historyremoval actualRED→green; visualreview found weekdayclipping actualRED and inheritedlineheight failure, corrected standaloneadaptivefont→focusedgreen2.133sec. Firstfull33green58.289sec predatesweekdayfix; final **34/34Overviewnative passes60.672sec**, actualOverviewtap→storededitor integration1green3.953sec. Fourfinal settled light/dark130% PNGsinspected withallaxisdigits/weekdays/LongMAXcaption; earlierimages diagnostic only.

Full **1521JVM/146suites**, Swift610, lint/build73sec plus finalcorrected11sec, relevantAndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass. Evidence/APKs/preservedfailures/executedchecksums `evidence/2026-10-16-overview-weekly-chart.md`. All10flagsfalse; noSamsung/liveproductionwrite/deploy/migration; Room6/SwiftDataV11/iOS751 unchanged. Continue daydetail/categorycharts/budget-due-config and remainingfamily/investment/imported/editoratomicity/receiptdeviceQA/fullAPK1–4/RC. Goalactive.

App106 install-r preserving data, coldMainActivity Statusok1033ms and installedversion106 confirmed on API36 emulator.


## 2026-10-16 — owned Overview day details and stored editor navigation (APK107)

Physical350ms positivebarhold now opens native medium/large day sheet; exact originalsource rows, full localizeddate/time/wallet/category, count/unlimitedrecency and liveprimary/perrecordFXtotal. Missing/unsupported FX is unavailable rather than a partial/relabelledtotal, intentionally correcting Swift's source-minors/primary-label mismatch. Ownerreplacement and externaloverlayclear private sheet; rowdismisses before existingeditor. Zero/reporting-onlybar cannot open unrelatedemptydetail; signed/zerospending classification distinctfromreportingoverride chart. Sharedclassifierextraction retainsmonthly/weekly behavior.

Model8cases7actualREDs→28focusedGREEN; native7cases6missing-sheetREDs41.274sec andactualeditorRED6.728sec→GREEN. Locale diagnostic proved sheetwindowEnglishlabels vsVietnamesedate, fixed scopedparentresources. New actualfontScale assertion RED1.0vs1.3 thenparentDensityfix→7/7GREEN19.28sec. Firstfull41GREEN76.41sec predatesreviewfixes. IndependentreviewImportantdoubleminus plusparentdatebaseline68px<font79.2px reproduced2nativeREDs4.964sec, magnitudeformatterunitRED→6GREEN; oneprefixcashflowdirection/BigDecimalmagnitude/standalonedatestyle fix. Final8focusedGREEN23.812sec; fourcorrectedsettled actual130% light/darkPNGs inspectedafterphysicalexpandandrowIsDisplayed. Partial-sheetcaptures excluded.

Final **42/42Overviewnative GREEN79.66sec**, actualrecent/dayrow→storededitor→exactRoom/outbox **2/2GREEN7.446sec**. Full **1530JVM/147suites**, Swift610, final lint/build39sec, relevantAndroidTestcompile/package, contract/localization/SQLite/schema/whitespace pass. Evidence/APKs/executedchecksums: `evidence/2026-10-16-overview-day-details.md`.

ReviewMinor Eventbadge in dayrows remains requiredfamilyOverviewwork. New open verification audit: earlier simulated130% sheet captures lack actualfontScale assertion; remeasure/recapture before claiming130% proof. FullscreenOverview104–106 unaffected. All10flagsfalse; noSamsung/liveproductionwrite/deploy/migration; Room6/SwiftDataV11/iOS751 unchanged. Continue categorycharts/drilldown/budget-due-config/remainingOverview, family/investment/imported/editoratomicity/receiptdeviceQA/priornative-timing/fontscaleaudit/fullAPK1–4/RC. Goalactive.

App107 install-r preserving data, coldMainActivity Statusok1050ms and installedversion107 confirmed on API36 emulator.


## 2026-10-20 — Overview monthly category chart and drilldown (APK108)

Day/Category mode switch, continuous monthly pages, exact name-normalized parent/child rollups, positive5+Other pie/legend, one-level drill/back, physical hits/haptic and selected-month cashflow summaries. BigInteger grouping/Other/formatter/percentage denominator; missing nonzeroFX holds wholemonth with localized hint. Owned historicalmetadata/systemcatalog fallback, portable Unicode whitespace/NFC and owner-keyed state. Month-list mutation replaces pager count/keys/content together; unconditional Hero month/week observers prevent removed periods resurrecting while inactive; measured row/back/text width retains all amounts at normal/130% font.

Core11runtimeRED→39focusedGREEN; BigIntegerformatter1/7RED→7GREEN. Native8missing-modeRED52.334sec; actualAndroidICU regex/NFD failures fixed with portable Unicode/NFC. Actualhistorycrashes/font zero-height/back-childglyphREDs fixed. Fresh independentreview2Important(normalwidth clippedmoney/inactive staleperiod) produced3nativeREDs13.227sec→13focusedGREEN31.188sec; NEL-onlytranslation fallback unitRED→GREEN in same onefixpass. No rereview. Older recentfont test lazy scrolling setup corrected after actualfull51failure; fixedOct16 editorfixture now navigates historicalweek onOct20, exact Room/outbox assertions retained.

Final **1542JVM/148suites**, **54/54Overviewnative GREEN182.302sec**, actualrecent/day→storededitor→exactRoom/outbox **2/2GREEN11.561sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets, relevantAndroidTestcompile/package and lint/build140secGREEN. Fourfinal settled actual130% light/dark root/drillPNGs inspected withall6rootamounts andchild100fullglyph. App108install-r/coldStatusok1008ms/versionconfirmed; archived/executed3APKchecksums match. Evidence`evidence/2026-10-20-overview-category-chart.md`.

Reviewminors back/emptyicons and piegradient/rounding/shadow remain required visualparity. Parent declined-rulings preserve mandatory monthlyLongclamp/missingFXzero/unsupportedcode, importedclassifier/currency, family/event/investmentvisibility audits; unconfirmed weeklypager race retains shrink coverage. Older sheetactualfontScaleaudit, dayEventbadge, Overviewbudget/due/config/walletcards, editoratomicity/receipts/device/background, fullAPK1–4/RC and wholebranchfinalreview remain open. All10flagsfalse; Room6/SwiftDataV11/iOS751 unchanged. NoSamsung/liveproductionwrite/deploy/migration. Goalactive; nextslice exact/available monthlysummarymoney.


## 2026-10-20 — exact and available Overview monthly income/expense (APK109)

Closed monthlysummaryLongclamp/missingFXzero/unsupportedsourcecode audit from108. NullableBigInteger income/expense, perrecordexactcurrentFX/rounding andsignedcancellation; onlyaffected direction unavailable/emdash+vi-en-ja hint/stateDescription, neverpartialtotal. Explicitsource→ownnondeletedwalletcurrency→legacyJPY; sameISOimports exactminor, unsupportedcrossheld. SharedOverviewMoney helper extractedfromcategory withoutclassifier/groupingchange. PublicScreen validatesone supportedprimary for bothprojection/display, preventingUSD1375→false¥1375. Exactadaptivepositive/negative values retainfullglyph at1.0/1.3font. HistoricalCategory/Day/owner/reset/read-only behavior retained.

New9model8actualREDs1sec→48focusedGREEN2sec;6nativeactualREDs39.164sec→6GREEN12.978sec. Freshreview1Important primary/displaymismatch actual1/1RED6.766sec→oneScreenboundaryfix; recommendationtwiceMINnegativefourfont/themevariants added. Firstfull60had6fail149.07sec: oldmissingFX0golden +5lazyrecentqueryfixtures; repaired scrolling preservesowner/filter/money/no-write assertions, includingvisiblecount/rowsections before/afterownerchange. Separatetestcompilemissingcontextdiagnostic corrected, neverruntimeREDclaim. Final **20focusednativeGREEN36.428sec**, **62/62OverviewnativeGREEN125.301sec**, actualrecent/day→storededitor→exactRoom/outbox **2/2GREEN6.963sec**.

Full **1551JVM/149suites**, Swift610, final lint/build15sec, relevantAndroidTestcompile/package, contract15/bothstrictlocalization/SQLite7-3-11/Room6assets/whitespace pass. Sixfinalsettledactual130% light/dark positive/negative/unavailablePNGs inspectedcomplete; negative additionallyfullglyph1.0. App109install-r/coldStatusok1162ms/versionconfirmed, archived3APK/executedchecksums match. Evidence`evidence/2026-10-20-overview-monthly-exact.md`.

Nextmandatoryfinancialslice: weeklybar/callout/daytotalLongclamp/missingFX; assets/globalplanning/importedLegacyOriginalCurrency/classifier audits remain. Reviewdeclined-rulings preserved: family/event/investmentvisibility/RPC/receipts/editoratomicity/remainingOverviewUI; unknown/decomposedtitle inputs/resourcebounds/deviceTalkBack/RC notcompleted. Olderchartvisualminors/dayEventbadge/sheetactualfontScaleaudit andwholebranchfreshreview remainrequired. All10flagsfalse; Room6/SwiftDataV11/iOS751unchanged; emulatoronly, noSamsung/liveproductionwrite/deploy/migration. Goalactive.


## 2026-10-20 - Exact and available Overview day chart/details (APK110)

Weekly bars/callouts/axis and original day totals now retain nullable BigInteger without Long clamping. Missing nonzero conversion holds the whole week with a localized hint; no partial bars, false zero, stale callout or hold. Live primary/rates/owned wallet changes repair. Original day amounts remain distinct from reported chart semantics. Source explicit -> owned nondeleted wallet -> legacy JPY; null reporting target resolves JPY. Same-ISO imports retain minor units; unsupported cross conversion stays unavailable. Malformed original currency rows remain countable/selectable with unknown money; zero needs no FX. Financial rows/outbox unchanged.

New10core cases9actual runtimeRED1sec ->58focused/6suitesGREEN. Initial8native baseline52.491sec had6intendedREDs and2invalid hold helpers (zeroVNDsubstring matched200/250); corrected OnLongClick helper and reran2actual header-valueRED14.337sec on109 fixture, restoring110 model sources byte-identically. Then8/8GREEN25.106sec. First full70 had2old-clamp golden failures154.253sec; helpers now accept MAX+100/MAX+96 exactly, retaining row/font/read-only checks ->2focusedGREEN7sec, pre-review-fix70GREEN159.28sec.

Fresh review noCritical/Important; Minor callout occluded top axis. Fixed within110: physical bounds actualRED2.418sec -> measured reserved callout row. Initial20focused19pass/1physical-tap failure52.993sec -> chart-background tap clear plus day-reselection assertion. Final **20focusedGREEN54.199sec**, **71/71OverviewnativeGREEN176.905sec**, actual recent/day-row editor exact Room/outbox integrations **2/2GREEN10.459sec**. Ten final settled actual130% light/dark chart, positive/negative day and unavailable PNGs refreshed/inspected; axis/callout readable together, full glyph/density/physical display assertions. One fix pass, no rereview.

Full **1561JVM/150suites**, Swift610, final full checks/lint/buildGREEN4sec (initial70sec), relevant AndroidTest compile/package, contracts15/both strict localization/SQLite7-3-11/Room6assets/whitespace pass. App110 install-r preserving data/coldStatusok1181ms/version110 confirmed; all3 archive/executed APK hashes match. Evidence: `evidence/2026-10-20-overview-day-exact.md`. Old superpowers plugin helpers disappeared mid-turn; task-done helper not claimed, equivalent checks completed.

All10flagsfalse; Room6/SwiftDataV11/iOS751 unchanged; emulator only, no Samsung/live Supabase/production write/deploy/migration. Next: exact/available asset cash+inventory. Global planning/Recent legacy original currency/raw malformed/classifier audits remain. Full family/event/investment visibility/RPC/receipts/editor atomicity/Overview budget-due-config-walletcards, category visual minors/day Event badge/older sheet actual font audit/device RC/whole-branch fresh review remain required. Goal active.


## 2026-10-20 - Exact and available Overview cash plus inventory (APK111)

Available assets now retains nullable BigInteger cash balances, per-final-wallet FX, inventory and Hero total. No final Long clamp, missing-FX-zero, unsupported-code relabel or dropped inventory on invalid accounting metadata. Zero needs no FX/currency. Latest malformed positive-position quantity/cost or unorderable calendar holds the portfolio; strict decimal-string quantity/integer numeric cost follows Swift wire decoding. Nonpositive positions/negative numeric cost normalization, ownership/active/moved-asset/order/UUID and cash/debt/family/resale classifiers preserved. Localized vi/en/ja explanation and stateDescription with live repair/owner clearing; financial rows/outbox unchanged.

New12model8actual runtimeRED1sec ->85focused/8suitesGREEN2sec. Eight native baseline7intendedRED47.148sec/owner safeguard pass ->8/8GREEN19.1sec. Prior assets missing-FX0 fixture migrated to emdash+hint; later rate assertions retained. Fresh independent immutable review noCritical/Important/newMinor, no fix pass/rereview. Final **1573JVM/151suites**, **79/79OverviewnativeGREEN182.339sec**, recent/day editor exact Room/outbox integrations **2/2GREEN9.943sec**, Swift610/contracts15/both strict localization/SQLite7-3-11/Room6assets/whitespace, required AndroidTest compile/package and lint/buildGREEN75sec plus fixture4sec.

Six final settled actual130% light/dark positive2MAX/negative2MIN/unavailable PNGs refreshed from final whole-suite package and inspected; numbers additionally full-glyph at100%. App111 install-r preserving data/coldStatusok1116ms/version111/min26/target36 confirmed; all3 archived/executed base.apk SHAs match. Evidence: `evidence/2026-10-20-overview-assets-exact.md`. All10flagsfalse; Room6/SwiftDataV11/iOS751 unchanged; emulator only/no Samsung/live Supabase/production write/deploy/migration.

Next mandatory raw-input audit: OverviewFinancialInputs can omit malformed wallet/ledger amounts/dates/metadata before valid aggregates; no end-to-end malformed-input completeness claim. Cross-domain flow/loading atomicity, Recent legacy original currency/import/classifiers/global planning, full family/event/investment CRUD/rebuild/RPC/permissions/visibility, receipts/editor atomicity/remaining Overview, category visual minors/day Event badge/older font audit/device RC/whole-branch fresh review remain required. Parent corrects stale review carry-forward: chart callout/axis overlap was already fixed/physically verified in110. Goal active.


## 2026-10-20 - truthful raw cash admission and paired transfers in Overview (APK112)

Assets now uses cash-specific raw admission: unreadable eligible opening/required posted leg or uncertain eligibility holds the whole exact total; known irrelevant/foreign/deleted/archived/draft/credit/unselected components stay neutral. Strict JSON numeric Long money, trusted envelope/canonical identity and required reference checks. Valid cash survives unused bad clocks/reporting/destination fields; resale cost/shared/family/debt semantics preserve Swift. Credit metadata survives an unreadable unused credit opening. Missing nonzero destination pairing only reuses source minors for established same-ISO; pure assets entry point guarded too. Malformed explicit currency JSON cannot masquerade as absent legacy code. No reporting intake/persistence/schema/cloud changes.

Feature baseline11 cases10runtimeRED1sec, pure3/1RED1sec, native7/7intendedRED45.312sec -> GREEN. Parent credit metadata regression1/12JVMRED +1nativeRED6.853sec ->110focusedJVM/15nativeGREEN. Fresh independent112review requested but reviewer failed before findings due to usage limit; no independent approval claimed. Parent full diff/Swift review found explicitcurrency fallback,13th featurecase actualRED(expectednull/20) and nativeRED6.676sec -> minimalguard -> final15focusednativeGREEN29.352sec.

Final **1589JVM/153suites**, **87/87Overviewnative GREEN165.682sec**, actualrecent/day storededitor exactRoom/outbox **2/2GREEN8.149sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package and lint/build42secGREEN. Six final settled actual130% en/vi/ja lightdark PNGs inspected; repaired2MAX fullglyph asserted. Main112 install-r/coldStatusok1014ms/versionconfirmed; all3executedinstalled/archiveSHAs match. Evidence `evidence/2026-10-20-overview-raw-cash.md`. Emulator restarted only after verified absence of old qemu/ADB; currentAPI36ARM64transport12. No Samsung/liveSupabase/productionwrite/deploy/migration. All10flagsfalse; Room6/SwiftDataV11/iOS751 unchanged.

Next reporting currency metadata must survive unreadable unused wallet opening (current financial filter drops it and can falsely use legacyJPY). Broader malformed reporting money/calendar/eligibility, Recent legacy/source import/classifier/globalplanning, cross-flow atomicity/loading, family/event/investment/receipt/device/visual/fullAPK1-4/RC remain mandatory. Independent whole-branch finalreview still outstanding;112independentattempt did not execute. Goal active; continue immediately after independent commit.


## 2026-10-20 - reporting wallet currency/kind independent of cash opening (APK113)

Monthly/week/category/day no longer drop currency/kind metadata when unused cash opening is unreadable. VND165 legacy-source expense reports1JPY at165 instead of false165JPY; day row stays originalVND165. Invalid existing currency holds reports instead of falling through; credit-kind card-title classification retained. Ephemeral reporting-only wallet opening0 never read/persisted/used for assets;112 rawcash still unavailable until actual opening repair. Owner/deleted/kind/archive rules unchanged, historical archived metadata retained.

New7featureJVM6actualruntimeRED1sec and4/4native intendedmoneyRED26.193sec -> feature30/4suitesGREEN5sec and4nativeGREEN9.91sec. Separate missingthemecompile diagnostic not counted asRED. Direct SwiftOverviewSupport113-153, TransactionLogic1407-1430 and OverviewLogic665-708 reviewed; parent completepatch795ea85292c3363ac94a47581d2651291c1bc232b32288bc2142e56412c10add noadditionalfinding. No independent agent review executed (prior usagefailure); finalwholebranch independent audit remains outstanding.

Final **1596JVM/154suites**, **91/91OverviewnativeGREEN184.438sec**, actualrecent/day storededitor exactRoom/outbox **2/2GREEN8.111sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package and lint/build27secGREEN. Main113install-r/coldStatusok1121ms/version113/min26/target36 confirmed;3installed/archiveSHAs match. Evidence `evidence/2026-10-20-overview-reporting-wallet-metadata.md`. Existingfont/theme/localized tests rerun in whole suite, no new113 screenshot claim. API36ARM64emulatortransport12 only; no Samsung/liveSupabase/productionwrite/deploy/migration. All10flagsfalse, Room6/SwiftDataV11/iOS751 unchanged.

Next mandatory monthly raw admission: unreadable required posted money/status/calendar must not disappear into partial/zero reports, while irrelevant fields must not drop valid totals. Week/category/day raw issues remain subsequent consumer-specific work; Recent fallback directly matches Swift boundary but wider legacy/import/source-wallet/globalplanning/classifier/loading audit remains. Full family/event/investment/receipts/device/visual/APK1-4/RC stays active. Continue immediately after independent113commit.


## 2026-10-20 - truthful raw monthly cashflow effects and availability (APK114)

Monthly/selectedcategory-month summaries now consume strict raw per-direction effects. Required unreadable money/status/archive/classification or source metadata holds affected whole direction; oppositeknownamount remains. Reporting overrides remove unused original dependency, badcreated/destination fields no longer drop knownmoney. Datedunknown createsmonthlyhistory; unplaceableoccurred holds affected directions acrosscurrent/knownhistory without inventingdate. Knownfuture/ineligible/foreign/bodyidentity/deleted/draft rows neutral; zero noFX. ExactBigInteger perrecordFX/overflow/cancellation/importidentity retained. Sharedcore monetary-field selectors preserve debt/resale/shared/paidfor/installment/adjustment/card/legacy rules; finite uncertainty paths never defaultbadfinancialfields0. Shared112rawtrusthelpers extracted unchanged; cashassets independent. No persistence/schema/cloud changes.

Actual9featurecases8runtimeRED2sec +native5/5moneyRED32.65sec on113; extended12feature10runtimeRED3sec ->focused120GREEN7sec and32nativeGREEN59.132sec. Parent4acceptancecontrols ->final124JVM/13suitesGREEN3sec; oldfalsepartialnativegoldenmigrated bothunknown ->107knownunusedcreated ->7, originalno-writeassertionsretained. Parentcopyfinding: monthlyhintalreadyusesamountsbutonlyFX (initialweekly-stringconfusioncorrected); actual1native semanticRED1.848sec ->generic reportingAmountUnavailablevi/en/ja+generated+monthlytext/stateDescription ->11nativeGREEN25.637sec. Finalparentpatch7a6b8cdd28ae757407b20cea00473948f6dc4d0bb209657dd78ae1b6b9757d07 reviewed/directSwiftTransaction1407-1479/OverviewSupport113-153/Overview665-708; noindependentagentreviewexecuted, finalwholebranch independentauditoutstanding.

Final **1612JVM/155suites**, **96/96OverviewnativeGREEN214.168sec**, actualrecent/day storededitor exactRoom/outbox **2/2GREEN7.524sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package and lint/build60secGREEN. Six final settled actual130% en/vi/ja lightdark PNGs pulled/inspected. Main114install-r/coldStatusok1174ms/version114/min26/target36; all3installed/archiveSHAs match. Initialpre-hint96/2passed222.119/7.554 notusedasfinalproof. Evidence `evidence/2026-10-20-overview-monthly-raw-inputs.md`. All10flagsfalse; Room6/SwiftDataV11/iOS751 unchanged; emulatorAPI36ARM64transport12 only, noSamsung/liveSupabase/productionwrite/deploy/migration.

Next rawweekly/category/day admission: weeklyfalse0 stillvisiblewhenbadrequiredmoney dropped; categoryraw can omit an unknown-only past month even though monthlymodel createsit. Existing-period monthlysummary is fixed; wholehistoricalUI/graphmoney not certified. Keep imported/source-wallet/globalplanning/classifier/financialdomain/loading-atomicity, fullfamily/event/investment/receipts/Overviewwalletcards/budget/due/config/visual/dayEventbadge/older-sheetfont/device/background/RC and finalwholebranchreview required. Goalactive; separate114commit then immediately next consumer slice.


## 2026-10-20 - truthful raw weekly spending and unplaced expense availability (APK115)

Weekly now shares114 strict raw reporting effects, independent currentSunday cutoff includes future-withinweek acrossmonth/year and ignoresfutureweeks. Unknown required expense/status/classifier/currency holds wholeweek; unused income/destination/created fields do not discard knownspending, override can removeoriginaldependency. Known datedunknown createshistory; unplacedexpense flag holds known/currentweeks withoutinventeddate/nullpoint. Generic114hint replacesaxes/bars/callout/dayactions; pager/range retained. Selectionclears whenavailabilitychanges withunchangedpoints and neverresurrectsonrepair. OverviewReportingEffect renamed/shared; monthlycutoff/classification/perrecordFXexact retained. No persistence/schema/cloudchanges.

JVM9cases8actualRED1sec/native6of6moneyRED39.014sec on114 ->133focusedGREEN8sec/native6GREEN14.96sec. Separate getOrNull import compilediagnostic notREDclaim. Parentzero-directionfinding newJVM1of10RED1sec +native1RED6.78sec ->per-directionknownzero retained despiteuncertainincome/primary/calendar ->134focusedGREEN2sec/native16GREEN34.45sec. Year/Tokyo-localMonday controls feature57GREEN1sec (135focusedwithcore78/14suites). DirectSwiftOverview457-554/808-824/Transaction1423-1469 and immutableparentpatch b6ab27e3d78cdde2cef50977963debfb4d481a98e24eeb0d3c247b467a87510a reviewed; nofurtherproductionfinding. No independentagentreviewexecuted/approvalclaimed; finalwholebranch independentauditoutstanding.

Final **1623JVM/156suites0fail/error/skip**, **103/103OverviewnativeGREEN270.1sec**, actualrecent/day storededitor exactRoom/outbox **2/2GREEN7.81sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package and lint/build140secGREEN. Six final settled actual130% en/vi/ja lightdark PNGs pulled/allinspected. Main115install-r/coldStatusok1160ms/version115/min26/target36; all3installed/archiveSHAs match. Evidence `evidence/2026-10-20-overview-weekly-raw-inputs.md`. All10flagsfalse; Room6/SwiftDataV11/iOS751 unchanged; API36ARM64emulatortransport12 only, noSamsung/liveSupabase/productionwrite/deploy/migration.

Next original-day raw rows/money/count/calendar/createdsorting/liveopensheetcorruption and actualstorededitorrepair; categoryraw grouping/availability/unknown-onlypastmonthnavigation also mandatory. The retainednonempty-dayguard does not certify unreadableoriginal-daydata. Keep imported/source-wallet/legacy/classifier/financialdomain/globalplanning/loading-atomicity, family/event/investment/receipts/Overviewwalletcards/budget/due/config/visual/dayEventbadge/older-sheetfont/device/background/RC and finalwholebranchreview required. FullAPK1-4goalactive; separate115commit thenimmediate nextslice.


## 2026-10-20 - original-day raw expenses and truthful live details (APK116)

Original-day now has consumer-specific raw admission, independent of reporting overrides. Confirmed expense with unreadable original amount retains trusted row/count1 and nullable originalMinor/Money; whole total unavailable, no placeholder0 arithmetic/storage/editor payload. Unknown required status/archive/classifier/occurred date exposes uncertain count and holds potential nonzero total; known zero needs no FX but cannot establish count. Known irrelevant rows neutral. Unreadable created is sorting metadata, retained money/count with occurred desc then readable-created desc/nullsLast/stableties. Unused reporting/destination fields cannot discard original money. Walletcurrency/name independent of unused opening/kind, owner-safe historical labels. Shared finite classification candidates preserve monthly/weekly behavior; shared core exact day-total helper avoids duplicate FX.

Screen recomputes live sheet from raw, allows meaningful uncertain original details while refusing reporting-only income empty day; row tap dismisses then reloads stored id. New actual integration proves unreadable original cannot open form/save or write0; existing editor guard sufficient, no editor production change. New localized entries-unavailable body/count semantics and generic amount hint; retained actual resources/density. Swift original rules/sort/sheet/rows reviewed; Event badge/count-label wording and olderfont audit remain visual/family work.

Baseline9JVM7actualbusinessRED1sec, native5/5RED34.598sec and actualeditor1/1RED6.947sec -> initial5nativeGREEN12.465sec ->12featureJVM/7nativeGREEN24.969sec. InternalFXhelper access compile diagnostic fixed by shared core operation, not claimed as runtime RED. Parent immutablepatch3fc31d150814a98ffc5570324b9b29f2ccf26a65c58562a4de8d0556805bc2b4/directSwift reviewed; no independent agent review executed/approval claimed, wholebranch independent audit remains.

Final **1635JVM/157suites0fail/error/skip**, **110/110OverviewnativeGREEN255.895sec**, actual recent/day exact Room/outbox + unavailable original storededitor **3/3GREEN12.031sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package/lint/build85secGREEN.12finalsettled actual130%en/vi/ja lightdark money/countPNGs pulled/allinspected. Main116install-r/coldStatusok1403ms/version116/min26/target36;3installed/archiveSHAs match. Evidence `evidence/2026-10-20-overview-original-day-raw-inputs.md`. All10flagsfalse, Room6/SwiftDataV11/iOS751unchanged; emulatorAPI36ARM64transport12 only, noSamsung/liveSupabase/productionwrite/deploy/migration.

Next categoryraw grouping/money/availability/unknown-onlyhistoricalmonthpager mandatory. Keep imported/source-wallet/legacy/classifier/financialdomain/globalplanning/loadingatomicity, family/event/investment/receipts/Overviewwalletcards/budget/due/config/visualEventbadge/countlabel/olderfont/device/background/RC/finalindependentwholebranchreview required. FullAPK1-4goalactive; separate116commit then immediate nextslice.


## 2026-10-20 - raw category spending and historical month navigation (APK117)

Category now uses consumer-specific raw effects independent of unused cash/income/destination/created fields. Required unreadable money/eligibility/sourcecurrency/grouping holds whole pie; unknown-only dated expense retains historical/contiguous month pages, unplacedpotentialnonzero holds known/current pages withoutinventedhistory. Explicitexpenseoverride removes unusedoriginal/primary dependencies; originalzero retains history/noFX, explicitoverride0 excludes. Shared pure categoryeffects aggregation preserves exactBigInteger/perrecordFX/translation/NFC/Unicodewhitespace/parentchild/firstrepresentative/amount-name-ID/5+Other. Ownedhistoricalwallet metadata independentofunusedopening/kind, trustedrawidentity/JSONLong/reference checks. Screen no longer uses commonfinancialfilter in production. Monthly selectedsummary retains114semantics.

Baseline8JVM7actualRED1sec +native5/5RED32.904sec ->initial5nativeGREEN9.971sec. Parentrelationship/rolefinding2/10JVMRED1sec and2nativeRED8.45sec (generic hint also actualRED) ->candidatecategoryavailability/roleuncertainty/generic114hint fix ->23focusednativeGREEN47.151sec. Added3acceptancecontrols ->13featureJVM, added8thnative live drill-corrupt-repair inwholefinal. DirectSwiftcategorylogic/snapshot/tests/immutablepatch2c0264fd2104485eca2530661b704b117f06a9622afaa500a1465bd98c373887 parentreviewed; noindependentagentreviewexecuted/approvalclaimed, wholebranchauditoutstanding.

Final **1648JVM/158suites0fail/error/skip**, **118/118OverviewnativeGREEN308.893sec**, actualrecent/day exactRoom/outbox +unavailableoriginal storededitor **3/3GREEN15.524sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package/lint/build76secGREEN.6finalsettled actual130%en/vi/ja lightdarkPNGs pulled/allinspected. Main117install-r/coldStatusok1192ms/version117/min26/target36;3installed/archiveSHAsmatch. Evidence `evidence/2026-10-20-overview-category-raw-inputs.md`. All10flagsfalse, Room6/SwiftDataV11/iOS751unchanged; API36ARM64emulatortransport12 only, noSamsung/liveSupabase/productionwrite/deploy/migration.

Next Overviewvisual/categoryempty-backicons/piegradient-rounding-shadow/daycountlabel, Eventbadge/familypermissions/olderfontaudit. Keep broader source-wallet/import/legacy/classifier/financialdomain/globalplanning/loadingatomicity, fullfamily/event/investment/receipts/Overviewwalletcards/budget/due/config/device/background/RC/finalindependentwholebranchreview required. FullAPK1-4goalactive; separate117commit then immediate118baseline.


## 2026-10-20 - category visual details and truthful transaction-count caption (APK118)

Categoryback nowchevron+categoryicon+name/capsule; emptychartpieicon/centeredcopy; sectorgradient/rounded7-4corners/backgroundborder/2dpinset/dominantshadow12-y5/dark-lightalpha, existingratio/5+Other/hittest/haptic/drill/availability exactfinancialbehavior retained. Sharedcountcaption onlySwift/AndroidDaySheet changed Cashflow/ThuChi/収支 ->Transactions/Giao dịch/取引件数 withbothgenerators. ParentactualPNGfinding legacyfork.knife=>ellipsis reproducednativebitmap1382pixelRED1.648sec ->sharedCategoryIconrawsymbolfallback throughnativefamilyresolver;7nativeGREEN16.2sec. Whole147assetfidelity notcertified; nativeMaterialapproximation explicit.

Initial4nativevisual/captionRED5.988sec ->4GREEN6.843sec;extended18focused40.08sec. Firstwhole125 FAILED atweeklyhistorytest118: surfaceNodeDetachcrash wasprecededbycapturedComposeInternalwrong-threadSnapshotStateObserver/TestMonotonicFrameClock onRoomarch_disk_io_0. Isolated1passed2.449sec;new12-cycleprepend/remove/mountstresscontrolpassed11.47sec, notclaimedasRED. Local1.11.4v2APIconfirmedviajavap;all17Overviewtestimports migratedtoqueuedStandardTestDispatcher perofficialAndroidguidance, no dependency orspeculativeweeklyproductionchange.19v2focusedGREEN50.276sec. ParentdirectSwift/immutablefinalpatch5e4fcbf065616ea18d3c326a355ab0ada3b451c3b9c28cca945339a66e92a9a8reviewed;noindependentagentreviewexecuted/approvalclaimed,wholebranchauditoutstanding.

Final **1648JVM/158suites0fail/error/skip**, **126/126OverviewnativeGREEN332.987sec**, actualrecent/day exactRoom/outbox +unavailableoriginal storededitor **3/3GREEN13.368sec**, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace, requiredAndroidTestcompile/package/lint/build46secGREEN +finalv2incrementalcommand6secGREEN.24finalsettledactual130%en/vi/ja lightdarkroot/drill/empty/daycaptionPNGs pulled/allinspected;thesearecomponentfixtures,realRoomapplicationflowsseparatelycovered. Main118install-r/coldStatusok1108ms/version118/min26/target36;3installed/archiveSHAsmatch. Evidence `evidence/2026-10-20-overview-category-visual.md`. All10flagsfalse,Room6/SwiftDataV11/iOS751unchanged;emulatorAPI36ARM64transport12only,noSamsung/liveSupabase/productionwrite/deploy/migration.

Next119budgetread exact/availability/sourcecurrency: currentBudgetPlanning clampsaggregatesLong/PlanningMoney missingFX=>0/unsupportedornullcode=>JPY/lacksownedwalletsourcefallback. AddactualJVM/nativeREDthenfixbeforeOverviewbudgetwatchlist. Correctstalebacklogwording: SwiftOverview716-808 hasconfigurableinvestment/preparingSettlements/budgetFocus/upcomingBills/recent;Androidwallet/categorycountersareAPK0placeholder,notanewwallet/cardlistrequirement. Keeprawbudget/planning/globalfinancialdomain/import/atomicity/family/event/investment/receipts/Overviewactualsections/config/assetpack/Eventbadge/olderfont/device/background/RC/finalindependentwholebranchreview required. FullAPK1-4goalactive;separate118committhenimmediate119TDD.


## 2026-10-20 — exact budget read totals and unavailable conversion (APK119)

Budget branches, allocations, summary and pace now retain nullable BigInteger read amounts. Two maximum Long expenses/child limits remain exact; required missing FX or uncertain classifiers produce an em dash and generic unavailable hint without false zero/stable health/progress. Known independent parent allocations remain. Explicit source currency, owned historical wallet metadata and legitimate legacy JPY fallback are preserved; archived wallet currency/kind no longer disappear from historical spending. App locale supplies frozen labels and month order. Stored money, editor identity/payloads, schemas and cloud gates are unchanged.

TDD: core8/7 business RED and native4/4 RED25.979s; classifier finding core9th RED/native1RED12.951s; localization product finding plus stale partial-total oracle corrected; archived metadata2/2RED13.256s. All12new core cases /38budget core tests pass, new8native GREEN16.452s and34focused GREEN124.779s. First whole Planning101 had two failures519.252s; unchanged isolated2GREEN18.157s. Explicit loaded-target/pre-submit readiness assertions retained all original money/persistence/account-isolation checks; affected18GREEN67.598s. All14existing Planning Compose fixtures migrated to v2 after118's actual test-clock diagnosis. No production fix is claimed for the intermittent bill submission timing.

Final **1660JVM/159suites zero failures/errors/skips**, **101/101 Planning native GREEN583.418s**, **126/126 Overview native GREEN348.826s**, actual stored-editor3GREEN16.575s. Host full66s/post-font-fixture5s/post-readiness4s, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace passed. All12final actual130% en/vi/ja light/dark financial PNGs refreshed and inspected with complete glyph assertions; viewport alignment/systeminsets/MainActivity navigation remain separate visual coverage. Main119install-r/coldStatusok1978ms/version119/min26/target36 and all4installed/archive SHA256 matches. Evidence: `evidence/2026-10-20-budget-exact-read.md`. Parent direct Swift/diff/image review and final source patchb15be798e00a4a19080dde5c14df0a81e864a043794e84da594d6b5b327d7eeb; no independent agent approval claimed.

All10writeflagsfalse, Room6/SwiftDataV11/iOS751 unchanged. API36ARM64 emulatortransport12 only; no Samsung/liveSupabase/productionwrite/deploy/migration. Full APK1–4/RC goal remains active. Next raw budget-plan admission: strict repository parsing can silently omit unreadable required plan fields, leaving false empty/partial/zero summaries. Generic financial observe also filters malformed body deletion before downstream raw readers; preserve owner/identity scope when correcting that boundary. This119 slice uses existing typed inputs and does not certify raw plan/ledger/category completeness, continuity/import normalization, read-set loading/atomicity, family coverage or Savings/Due availability. Actual Overview sections/configuration, family/event/investment/receipts, full asset/font/root UI, device/background/release and final whole-branch review remain mandatory. Commit119 separately, then continue local work immediately.


## 2026-10-21 — raw budget-plan availability and exact stored edit routes (APK120)

Current/past unreadable plan money/month/eligibility no longer disappears into zero/partial totals or resurrects an older healthy plan. Owner/id-scoped raw repository stream retains malformed body deletion; projection holds the summary/list with the existing unavailable hint and suppresses false empty copy until repair. Known future/archived/deleted/foreign rows remain neutral. Missing branch/nonpositive limits hold rather than publish stable money. Stored row taps reload the strict exact raw original, preserving Edit when the independent typed stream is delayed. No persistence parser/schema/cloud mutation change.

TDD: initial8JVM/6businessRED1s; rawrepository1RED/command9s; actualRoomnative3RED19.583s -> initialJVM8+repo28/native3GREEN5.318s. Parent missing-allocation/nonpositive/foreign-duplicate findings3of11JVMRED2s plus actual delayed-editor blank-create regression: native6/3RED20.164s -> reviewed fixes. Final new unit12, **1673JVM/160suites zero failures/errors/skips**, **6newnativeGREEN9.826s**, focused budget/editor/calculator/currency **42/42GREEN166.223s**. Fullhost144s/Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace passed. Parent directSwift/immutablepatch6f494e173666eca6c4020882be6c8cc7a6489c86cd0e078e7a397984137e71f5 reviewed; no independent wholebranch approval claimed.

All12 existing exact/unavailable actual130% en/vi/ja light/dark final PNGs refreshed and inspected through the new pipeline; no full-root/system-inset/new-all-raw-scenario visual claim. Main120install-r/coldStatusok1017ms/version120/min26/target36; main20/planning9DEX and both installed/archive SHAs match. Evidence `evidence/2026-10-21-budget-raw-plans.md`. Current Superpowers execution/TDD/verification guidance adopted with a ledger once available again. Overnight emulator disappearance was verified (no ADB/qemu) before restarting the same AVD without wiping data; finalAPI36ARM64transport13. All10flagsfalse, Room6/SwiftDataV11/iOS751unchanged; noSamsung/liveSupabase/productionwrite/deploy/migration.

This remains a conservative template guard; raw budget ledger/wallet/category effects, independent usable fields of otherwise unreadable templates, continuity/import/name normalization, loading/atomic read sets and family/Savings/Due availability remain mandatory. Do not certify a financial domain/APK gate from this slice. Continue raw spending/actual Overview sections/config, full family/investment/receipts/root visual/font/device/background/release and whole-branch review. Full APK1–4/RC goal active; separate120commit then continue local work.


## Slice121 — consistent raw budget spending and read failure recovery — 2026-10-21

One owner-scoped Room query now supplies plan/ledger/wallet/category rows including historical tombstones, preventing mixed atomic wallet/ledger currency generations. Raw expense intake retains unavailable required money/eligibility/calendar/currency/classification instead of false0/partial sums. Fixed overrides and proved neutral/unrelated/unneeded fields retain known amounts. Parent uncertainty can hold parent spending while preserving a directly identified child. Canonical-equivalent titles and Unicode label grouping match reviewed Swift behavior without rewriting stored bytes. Loading/error/wrong-owner/late emissions clear totals; Retry reads current rows. Strict stored edit identity remains. Recent picker ignores unreadable recency instead of crashing. Budget deletion timestamps are validated; legacy Overview default remains unchanged.

Actual TDD: repository2RED/Room2RED(mixed pairs+omission)→GREEN; raw13unit/9RED, baseline10native/9RED, title1RED(expected0 actual7), loaded-then-failed1RED(stale7), recency DateTimeParseExceptionRED, broken-deletion-string1RED(false0) before fixes. Final **1689JVM/162suites zero failures/errors/skips**, Room **2/2GREEN0.259s**, budget focused **54/54GREEN177.166s**, Overview **126/126GREEN303.165s**. Full host121s/110s/7s, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace passed. First54run53pass/1calculator coordinate-movement failure154.4s captured old/newbounds during IME relayout; arithmetic/save fixture now uses real semantics action and does not certify physical hit testing. Superseded old Overview cancellation is not counted as a pass. Direct source/test patch5cb605d025faee8cf05b6d05cc8e80b1adfeb84e7ad3f136c67e18df619e95f8 reviewed against Swift; no independent wholebranch approval claimed.

All12final actual130% en/vi/ja light/dark financial PNGs refreshed/inspected. Full header/systeminsets/MainActivity/hit-target parity remains separate. Main121install-r/coldStatusokCOLD1646ms/version121/min26/target36; main20/planning9/Overview9/DB5DEX, all4installed/archive SHA256 matches. Evidence `evidence/2026-10-21-budget-raw-spending.md`. All10flagsfalse, Room6/SwiftDataV11/iOS751unchanged; API36ARM64transport13 only, noSamsung/liveSupabase/productionwrite/deploy/migration.

Conservative template/alias holds, full family budget semantics and generic Savings/Due availability remain open; no financial-domain/APK gate completion. Continue actual Overview watchlist/due/investment/preparing/config, family/investment/receipts/root visual/font/device/background/release and final fresh whole-branch review. Full APK1–4/RC goal active.


## Slice122 — actual Overview budget watchlist — 2026-10-21

Replaced the APK0 wallet/category count placeholder with the actual personal budget watchlist. Both Overview/Planning use the same raw scoped snapshot/projection; the3 reader bodies moved unchanged to core with compatibility delegates. Selection hides known stable/empty, keeps unknown visible, ranks exceeded/caution then exact signed ratio/locale name, maximum3, preserving branch currency and parent identity without child double counting. Missing summaryFX cannot erase a readable branch alert. Loading/error/retry/late-owner guards prevent stale private totals.

Native section follows reviewed Swift header13sp bold uppercase/tracking.6 outside body/gap8dp, flat grouped22dp card/insets14dp/tile30dp, exact spent/limit/percentage/day count and bounded progress without Material stop/gap. Unknown is neutral/dash/no progress. CategoryIcon optional shape/glyph/alpha keeps defaults unchanged for other consumers. Full147asset/rounded-font identity/root/system-inset/hit-target parity remains open; these are tested native component geometry/content cases.

TDD: absent-selector8/8actualRED2s; absent-section native7/6RED40.519s with stable-hidden control passing; focused reader/selection4s→native7GREEN12.14s→new8GREEN17.146s. Old recent-owner fixture still expected removed count12345: initial existing126 had125pass/1obsoleteassert failure293.598s; remove only count stream/asserts, retain private owner-switch row checks, isolated1GREEN2.074s and previsualfull134GREEN342.03s. Further Swift component review reproduced header16sp instead13sp: native1/1RED1.946s before actual geometry correction; new9/9GREEN20.465s. Final **1697JVM/163suites zero failures/errors/skips**, **135/135OverviewGREEN349.122s**, **54/54PlanningGREEN205.979s**. Initial finalstylePlanning53pass/1SavingsCRUD edit-save timeout225.807s; unchangedisolated1GREEN8.36s did not identify a production cause. CRUD fixture now asserts200/save-enabled and uses actual save semantics, preserving stored/delete/outbox assertions; no Savings runtime or physical hit-target fix claimed.

Fullhost73s/13s/52s/finaltest-only5s, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/whitespace passed. All12final exact/unavailable en/vi/ja light/dark actual130% component PNGs inspected after correction. Immutable source/test patchfe674423bf1a8c95c94622e2afe847ffc6198bc8e5657df8613f0f38a8ace174 directly reviewed against Swift, including the source of flat grouped card/header/icon geometry; no independent wholebranch approval claimed. Main122install-r/coldStatusokCOLD1346ms/version122/min26/target36/main20DEX/Overview9/planning9, all3installed/archive SHAs match. Evidence `evidence/2026-10-21-overview-budget-focus.md`.

All10flagsfalse, Room6/SwiftDataV11/iOS751unchanged; API36ARM64transport13 only, noSamsung/liveSupabase/productionwrite/deploy/migration. FullAPK1–4/RC goal active. Actual upcoming dues/investment/preparing/config/family/receipts/globalwalletbalance/settings/device/background/release and wholebranchreview remain. Next prerequisite: reproduce frozen bill confirmation/source change consent before wiring upcoming-dues payments; this adjacent risk is not fixed in122. Continue per-slice local commits.


## Slice123 — recurring payment source/cycle consent and late UI results — 2026-10-21

Manual recurring payments require the visible typed source and effective cycle amount; fresh repository state must match before money/outbox work, and existing atomicCAS still guards later changes. Missing/stale proof returnsSOURCE_CHANGED. Canonical exact created instant/other source fields are conservatively compared; only ACKupdatedAt/version/device metadata is ignored. Pending occurrence amount is checked independently of bill default, including intentional variable null. BillPaymentState supplies both baselines; frozen confirmation enablement and execute compare current consent. Automatic payments keep fresh source/no overrides and installments keep their separate expected-plan proof. All runtime constructors inventoried; strict manual fixtures now pass their actual visible source. No persisted/wire entity/schema/currency policy changed.

Actual TDD:5newJVM/2businessRED3s paid5000 afterstored6000/missingproof; Room2/1RED0.182s; confirmation2/2RED4.632s enabledoldamount/schedule; pendingcycle-only amount1/1RED2s beforeeffectivecyclebaseline. Core4consent/DB77/Planning7focusedGREEN9s; actualRoom12/12GREEN0.525s. RealRoomUI withholds the visible row, changes storedsource afterconfirmation before repositoryread, and proves no stale money/occurrence/outbox write. Font fixture initiallymeasured1.0 and then imagesrevealedallEnglish; actualwindowfont/resources/config are now configured/restored with explicitlocale title/cancel and fullglyph assertions. Native localizedfont+realRoomUI2/2GREEN7.712s. No productionlocale change or harnessdiagnostic counted as businessRED.

Full **1708JVM/164suites zero failures/errors/skips**, full Planning **124/124GREEN796.344s**. Further directcallbackreview reproduced oldnoncancellable pay/undo success dismissing a newcycleconfirmation: native2/2RED5.408s. Added coroutineactivity check aftercallback beforeUIdelivery, likeinstallments; no financialcommitundo. Final complete modified BillPaymentSheet10 +realRoomUI1 **11/11GREEN30.529s**, fullhostafterguardGREEN16s. OtherPlanningpathsunchanged after124run; do not claim a whole126 final run. Fullhost92s/14s/5s/6s/16s, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6schemas/whitespace passed. No nativeOverview rerun for unchangedreader/watchlist; fullcompile/JVMretained. All6final actual130% en/vi/ja light/dark confirmationPNGs refreshed/inspected; no fullroot/systeminset/allmodal/hittargetparityclaim. Fontscale restored1.0.

Immutable source/test patchcfebda171bd658c82fa22a8cc4592738a848b3307205621e52cc2d42e6e7bd53 reviewed against SwiftDuePaymentSheet406–445 and existinginstallmentexpected-source/cancellationguards; no independentwholebranchapproval. Main123install-r/coldStatusokCOLD1188ms/version123/min26/target36/main20DEX/planning9/DB5; all3installed/archiveSHAsmatch. Evidence evidence/2026-10-21-bill-payment-source-guard.md. All10flagsfalse/Room6/SwiftDataV11/iOS751unchanged; API36ARM64transport13 only/noSamsung/liveSupabase/productionwrite/deploy/migration.

FullAPK1–4/RCgoalactive. Next actual upcoming bill/installment Overview section/sharedpaymentroute with one scopedreadset and truthful amount/loading/ownerstates; creditcard/investment/preparing/config/family/receipts/globalwalletbalance/settings/device/background/release and freshwholebranchreview remain. This is one recurring-payment correctness slice, not Due/APK gate completion.


## Slice124 — Overview recurring dues and original-cycle payment — 2026-10-21

Actual personal bill/installment alerts replace the missing Overview due section: one scoped raw five-entity Room query, strict source/cycle admission, previous+current bill/current installment cycles, local calendar0..7days/DST, payment-opening/deadline, red0..3/blue4..7, date/name sort max3, exact per-source currency and intentional variable-null label. Composite kind/id/month identity prevents same-source cycle collisions. Loading/failure/retry/owner replacement/late snapshots remain distinct from loadedempty and reads do not write outbox.

Core identity-only saved target (owner/kind/id/month) routes through MainActivity to shared Planning original-source presenter. Current strict data reloads; draft survives failure/retry and savedstate restoration, unavailable/stale/paid targets disable pay without becoming Create/Undo. Test-only Planning→Overview dependency verifies actual crossfeature composition; runtime features remain independent. Installment effective-cycle consent now accompanies expectedplan, and shared manual executor rejects changed pending amount/future cycle status/kind/unreadable related month before money writes. Existing atomicCAS and samecurrency rules retained. UI installment source consent shares existing repository semantic comparison/ACK exclusions/timestamp tolerance.

TDD: rawsnapshot2JVMRED/Room2RED13mixedpairs→Room2GREEN0.209s; selector12/11businessRED→12GREEN; absentsection7/6RED40.536s→7GREEN11.811s; identifiercodec2unit. Missingpaymentroute3/3RED20.242s→3GREEN12.406s, thenextended8GREEN26.318s proves1375USD/samecurrency/openingbalance/outbox/restore/externalpaid/retry/missingsource/walletunknown. Installmentpendingamount1RED andunknowncycle3RED→focusedGREEN5s. Source-consentfixture corrected toactualJPY→USD, then1businessRED1s→sharedhelper/focusedGREEN7s; initialunchangedcurrencyfixture not counted. Finalactual130% section9GREEN17.954s/all12envi ja lightdarkPNGs inspected; exact fullmoney/noellipsis/header13sp/gap8/tile30 geometry. Full147asset/roundedfont/root/inset/hittarget parity remains explicit nextwork.

Full1731JVM167suites zeroerrors/failures/skips; host118s/final41s; Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6schemas/whitespacepassed. Planningfull134executed538.582s:133pass/1frozenconfirmedamount renderingfailure; fixedto retainhistoricalconsentamountwhilestillreadable andkeepconfirmdisabled. Finalcompletechangedpaymentclasses28/28GREEN101.107s, otherPlanningpathsunchangedafterfullrun; no whole134finalGREENclaim. FinalOverview144/144GREEN314.796s; affectedRoom28/28GREEN1.154s. DirectSwift/immutablepatch0ddaae57db55eccb0f5d5fc45ff9b13a2192392149e88f8f11ae9b986a0df810 plusfreshisolatedreview_due124 noCritical/Importantfindings; no wholebranchapproval. Main124install-r/coldStatusokCOLD1150ms/version124/min26/target36, main20/Overview9/Planning10/DB5DEX; all4installed/archiveSHAsmatch. Evidence evidence/2026-10-21-overview-recurring-due.md withallSHAs and12images.

All10cloudflagsfalse/Room6/SwiftDataV11/iOS751unchanged; API36ARM64transport13 only/noSamsung/liveSupabase/productionwrite/deploy/migration. FullAPK1–4/RCgoalactive. Creditcardintegrationpendingexistingcurrencydecision, independentfinancialreadsemantics/investment/preparing/config/family/receipts/globalwalletbalance/settings/background/release/freshwholebranchreviewremain. NextlocalUIwork: actualsourcefinanceiconassets (currentcoarsegroups do notrenderidentity), thenremainingactualsections. No Due/Overview/APKgatecompletionfromthisslice. Separate124committhencontinue.


## Slice125 — original native finance artwork and source freshness — 2026-10-21

Shared nativeBitmapPainter replaces broad Material/ellipsis art for registeredfinance tokens. SourceSwiftregistry/categoryJSON/SVGs remainauthority;196distincttokens (all161categories incl14inactive +37explicit/twooverlaps),111originaltransparent256PNGartworks. Preserveorderedoverrides/categoryprecedence/groupfallback; registeredart0.86callerframe/noaddedtile, originalmulticolor/gradients, filled/regulartemplateusesdescriptorbaseHex. Category/wallet/card/installment/savings/Overviewtransferconsumerswired; unknownsystemsymbolsretainoldfallbacks, picker/wire/currency/mutationsunchanged. Generatorchecksource/outputSHA/staticKotlin/missingstaleresources needsNodebuiltinonly, generation usesexistinglocalSharp0.35.5/vips8.18.7/rsvg2.63.2; no productdependency/runtimeSVG/WebView/network. CIexplicitNode22/check/pathtriggersadded; localcommandpassed, no hostedCIclaim. SDK135SVGconversion0warnings was rejected becauseWiFielipticalradialtransformlost; source-rasterpreservesart. ManifestSHA53e7d220ad70ab777e4632092b50d2d5e3cd288ac10909f13280d1a12e3df889 pinsall111source/outputhashes.

TDDgenerator6/6RED→6GREEN +artifact3RED→Node9GREEN; catalog5/4assertRED→5GREEN. ExistingnativeCategory6/6RED8.133s(errors40.76..58.04RGB)→6GREEN7.972s. Actualconsumerwallet1RED1.589s/goal+installment2RED2.773s/Overviewtransfer1RED1.571s→1GREEN1.600s/2GREEN2.784s/7GREEN9.363s. Nativegalleryloads196tokens/renders111artworks+measures1.3fontsize/fullglyphs,14lightdarkPNGs; final12watchlist+12dueenvi ja lightdarkimagesrefreshed/inspected (38originalscreens), plus111sourcePNGgalleryinspected. No roundedfont/rootinset/physicalhit/allSFsymbolcompletionclaim.

Full1736JVM168suiteszeroerrors/failures/skips; host58s/final161s/later5-20-6s, Swift610/contracts15/bothl10n/SQLite7-3-11/Room6assets/whitespace/Node9/artcheckpassed. StaleJDK17.0.20.1diagnostic afterHomebrew17.0.21update resolvedbydaemonstop/freshinprocess205taskcompile193s/noe:; laterfullhostclean. FullManagement31GREEN136.734s; finalrebuiltAPKconsumer1GREEN1.457s. Planning136executed622.137s,134pass/2fixturefail(editbeforeRoomready/savephysicaltimeout); unchangedisolated2GREEN9.318s, waitmergedaction/enabledsemanticSavefixture retains exactmoney/outbox checks, finalwholeOwnedBudget11+icon2 classes13/13GREEN42.886s. No physicalhittargetfix orprovenIMErootcause claimed. Overview152executed375.782s,151pass/1obsoletelegacy=canonicalpixelassumption; independentlegacyMaterialfood/canonicalSwiftfinalcarrottemplatereferencesreplaceit. FirstnewreferencewronggenericFoodwascorrectedagainstSwiftfinalassignment, notbusinessRED. 33focusedran78.099s/32pass1wrongreference; finalcompletechangedVisual7/7GREEN16.403s. No finalwhole136/152GREENclaim; otherpathsunchangedafterfullruns. Fullgoalphysical/root/IMEverification remains.

Freshisolatedreview_icons125 pinned67fe085d... noImportant/Criticalfindings, independent196/111check; no reviewerGradle/deviceclaims. Lateronlytestfixtures/fontassertions/CIwiringchanged, productrenderer/catalog/consumersunchanged; finalsource/test/CIpatch8ec07daf7868bb3e7c3efa15728efd07d5ef24bb1d95c6bf74d2291fd8784636. No wholebranchapproval. Main125install-r/coldStatusokCOLD1081ms/version125/min26/target36/main20DEX; Overview9/Planning10/Management9DEX; all4installed/archiveSHAsmatch, evidence/2026-10-21-native-finance-icons.md hasexactSHAs/38images/commands/limits. All10flagsfalse/Room6/SwiftDataV11/iOS751unchanged/API36ARM64transport13only/noSamsung/liveSupabase/productionwrite/deploy/migration.

FullAPK1–4/RCgoalactive. NextactualOverviewinvestmentcard+originalsourcenavigation/readavailability, thenpreparing/config/family/receipts/settings/background/release andwholebranchreview; creditcardcurrencydecisionstillpending. Independentfinancialreadsemantics/globalwalletbalance/unregisteredlegacyglyph/font/root/hittarget/fullUIremainrequired. Separate125committhencontinue.


## Slice126 — consistent Overview financial reads — 2026-10-21

Personal hero, cashflow/weekly/category charts, category history and recent list now use one owner-scoped raw six-entity Room query. Tombstones/damaged financial fields remain available to projections; outer/body identity is checked before emission. Explicit loading/failed/owned-loaded lifecycle states prevent invented zero and stale private money during owner/repository/retry changes, propagate cancellation and reject wrong-owner snapshots. Unavailable recent reads do not claim loaded empty; day actions are disabled until loaded. Budget/Due keep their own atomic readsets. No schema, wire/mutation/outbox/currency-policy changes.

Inclusive inventory admission now holds potentially active uncertain archive/deletion/reference dependencies instead of silently dropping cost; known exclusions/no positions/closed quantity stay neutral and accounting currency remains independent of cash parsing. Fresh isolated review found recent rows could be resurrected by malformed body deletion and wrong wallet currency supplied; actual two-test JVM RED reproduced it before fixing known-deletion eligibility, independent explicit source currency and an uncertainty hint. Reviewer confirmed P2 resolved in product patch e6baea09...; no remaining Important finding in remediation, static only/no wholebranchapproval.

TDD repository2RED14s→GREEN; Room2unsupportedRED→six new/budget/due classes6GREEN0.919s (copied fixture historical ID corrected); inventory15/2RED1s→15GREEN; actualscreen3RED→3GREEN5.627s; recent7/2RED12s→7GREEN. Final1743JVM169suites zero errors/failures/skips; host115s/73s/fixture15s, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6assets/icon196-111/whitespace green. Firstnative155/154pass1fixturefail493.964s (owner key resets chartmode; old fixture asked wrong node); corrected expectation. Final product fullOverview158/158GREEN728.222s. Visual review found newfixture missing appScaffold; corrected onlyfixture, finalcompleteclass6/6GREEN15.013s, all6ENVIJA lightdark actual130PNGs refreshed/inspected. Final Planning crossfeaturepaymentroute8/8GREEN41.881s. No repeated wholePlanning/Management suite claim.

Main126install-r/COLDStatusok1206ms/min26/target36/main20DEX35085004bytes; final Overview9/DB5/Planning10DEX, all4installed/archiveSHAsmatch. Evidence evidence/2026-10-21-overview-financial-read.md records exact hashes, separate full158 vs finalvisualfixtureAPK and six original images. All10cloudflagsfalse/Room6/SwiftDataV11/iOS751 unchanged. Same preserved AVD reopened after earlier emulator had exited, API36ARM64 transport14 only; no wipe/Samsung/liveSupabase/productionwrite/deploy/migration.

FullAPK1–4/RC goal active. Next actual Investment Overview card and original-source navigation, then inventory CRUD/FIFO/private images and outstanding preparing/config/family/receipts/globalwallet/settings/background/release/wholebranchreview. Existing creditcardcurrency decision remains pending; it does not block this independent local work. Separate126commit then continue.


## Slice127 — actual Overview investment capital and profit — 2026-10-21

Actual native personalOverview Investment card now precedes budget/dues/recent and opens existinginvestmentroute. Reuses126single6entitysnapshot; capital=latestpositiveposition/nonnegativepersistedbasis foractiveasset/channel, profit=allownerlivepersistedrealizedamounts includingclosed/archived/orphanhistory, nodate/kindfilter/FIFOsubstitution. Independent nullableamounts, exactBigInteger sum/cancellation beyondLong, accountingISOcurrency fromcanonicalsystemwallet evenarchived orprimary onlygenuinelyabsent/deleted. Requirednonzerotradeaccountingcode mustmatch; no relabelledUSDcents. Hero uses samecheckedcapital. Wire/mutationLong unchanged, oldminimalnativefixturesgainrequiredaccountingcode, unknownfields/read/outboxchecksretained.

Originalregisteredicons/header13/group22/padding14x12/icon30/chevrons/+zero/tealgain/redloss. Unread/error/ownerwrongmoneydash, sharedretry, overlaydisabled; loadedempty0/+0. ActualMainActivitycallback opens existingowner-scoped investmentlist; that destination remainsknownAPK0read-only pendingnextAPK4CRUD, no hub/FIFO/privateimages/familycompletionclaim.

TDDsummary8/8RED1s→8GREEN2s; nativeabsentcard4/4RED26.7s→card4+assets15=19/19GREEN38.055s. Readonlyisolatedreview19884c55 noConfirmedCriticalImportant, askednarrow320check: new8caseclass7pass1realoverflowRED→fullwidthamountrowwhenneeded/manualfontfit/wrapfallback→8/8GREEN20.933s. All13originalnativePNGs inspected (ENVIJA lightdark/VNDpositive/USDnegative+320dark), actual1.3font/fullglyphbounds/signcolor/header/gap/icons/insetsasserted. No roundedfont/root/globalinset/allSF/hittargetcompletionclaim.

Full1751JVM170suites zeroerrors/failures/skips; fullhost60s/final23s/fixture25s/final10s, Swift610/contracts15/bothstrictl10n/SQLite7-3-11/Room6schemas/art196-111/whitespacegreen. FullOverview166executed/160pass6fixturefail504.830s (Budget3offscreenwait/FinancialRead2offscreenchild/Weekly1initialmergedweekday); no prodchangeafterrun. FixtureactualsectionScrollToNode/stableRecenttitle/readmoneyready/unmergedglyph fixes retainassertions. Finalcompleteaffectedclasses42/42GREEN134.764s (unchangedWeekly12alsopassed), finalcompleteCard8+Weekly12=20/20GREEN80.240s; Planningactualroute8/8GREEN41.910s. No whole166 finalGREEN orwholePlanning/Management rerun claim.

Main127install-r/COLDStatusok1345ms/min26/target36/main20DEX35325059bytes; Overview9/Planning10DEX all3installed/archiveSHA match. Evidence evidence/2026-10-21-overview-investment-card.md records13images, exacthashes andseparatefull166/affected42/final20APKarchives. Source/test/versionpatch1fc8ab15...; independentreviewwasbeforefinalnarrowlayout, rootreview+nativeTDDresolvedconcern, no independentpostlayout/wholebranchapprovalclaim. All10cloudflagsfalse/Room6/SwiftDataV11/iOS751 unchanged, systemfont1.0, API36ARM64transport14only/noSamsung/liveSupabase/productionwrite/deploy/migration.

FullAPK1–4/RCgoalactive. Nextactualnativeinvestmentchannelcreate/rename/archive/restore+canonicalsystemwallet/atomicCAS, thenassetCRUD/unitFIFO/cash/privateimages/RPC andremainingpreparing/config/family/receipts/globalwallet/settings/background/release/freshwholebranchreview. Creditcardcurrencydecisionstillpending; independentlocalworkcontinues. Separate127committhencontinue.


## Slice128 — native investment channel management — 2026-10-21

Actual investment destination now creates, renames, archives and restores owned channels using one wallet/channel/asset/trade snapshot. Create/canonicalize deterministic systemwallet and channel plus both outbox rows in one conditional Room transaction; preserve existing accounting currency, created metadata, exact Long versions (including absent JSON version), unknown fields and explicit nulls. Visible-source rename/archive proof tolerates semantic ACK, refuses newer edits, and CAS reload checks stock becoming positive. Loading/failed/retry/loadedempty, owner/source replacement, saveable stable draft, duplicate-save and late noncancellable callback guards. Name-only form/default symbol/color/sort/archive flags and error OK alert compared directly with Swift; creation ordering uses Instant and trim uses the exact Foundation26-scalar set. Existing asset/activity readers retained; complete hub/asset/FIFO/privateimage/RPC work remains.

Dedicated ALLOW_INVESTMENT_CLOUD_WRITES=false added; all11flagsfalse. Ordinary wallet sync defers canonical/kind/purpose investment wallets without consuming queues/HTTP/failure bookkeeping; client rejects them and investment tables even if generic allowlisted. Future dedicated investment atomic RPC/coordinator is required; this slice enables local writes only. No schema change, production write/deploy/migration/liveSupabase.

Runtime TDD repository8unsupportedRED→GREEN, malformedchannel/walletversion and missingJSONversionRED→GREEN, FoundationNEL/completeBMPwhitespacesetRED→final16GREEN. RealRoom5unsupportedRED→GREEN, final6/6GREEN1.521s including actual trigger rollback/owner cancellation/atomic4entitygenerations/canonicalcurrencyrace/stock0→positiveCAS. Native missingUI5RED→GREEN, error-not-dialogRED→AlertDialog; finalwhole10GREEN205.178s after offset-dateorderingRED8.628s. Native visual actualwindowfont1.3 ENVIJA lightdark12 original images inspected; intrinsic subpixel rounding fixture corrected using linebounds±1px/fullcharacters/noellipsis/noheightoverflow, no disabled assertion. After final name-only correction exactsource actualcreate1GREEN20.561s; no whole10 finalrerun claimed. Overviewinvestmentcard8GREEN69.101s and Planningactualroute8GREEN167.946s on retained regression APKs before final whitespace-set-only change; no wholeOverview/Planning/Management rerun claim.

Full1770JVM171suites zeroerrors/failures/skips; finalhost68s with required Room/allfeature native compilation/packages/lint/main; Swift610/contracts15/bothl10n/SQLite7-3-11/Room6assets/art196-111/whitespacegreen. Direct root Swift/diff review corrected version preservation, dialog, date ordering and trimming; no independent128/wholebranchapproval claim. Finalsource/test/versionpatch ce9d7ff18aab0592f75a5ce04ab6a8ba0ee1fd3fdadaefb0db5042ad80aa3a58. Main128install-r/COLDStatusok8082ms (emulator observation, not performance acceptance),20DEX35711134bytes/min26/target36; main/Investment/DB finalsource plus Overview/Planning testedregressionpackages all5installed/archiveSHA match. Evidence evidence/2026-10-21-investment-channels.md records exact hashes, runtime stages and12images.

Room6/SwiftDataV11/iOS751 unchanged; systemfont1.0 restored, API36ARM64transport14 only/noSamsung/livecloud/production operations. FullAPK1–4/RC goal active. Next dependency: unit-aware FIFO/rebuild foundation needed by asset/default-unit edits with history, then complete asset UI/privateimages/cash/atomicRPC and remaining preparing/config/family/receipts/globalwallet/settings/background/release/wholebranchreview. Existing card-currency decision remains pending; independent work continues. Separate128commit then continue.


## Slice129 — unit-aware FIFO accounting foundation — 2026-10-21

Pure typed accounting prerequisite now matches actualSwift InvestmentAccountingEngine for independent pack/box/legacy unit FIFO, total-order purchase cost, partial/full residual basis release, signed sale profit/loss, remaining position/cost/open-lot count and per-unit balances. Occurred/created/unsignedUUID ordering; reject nonpositive quantity/negative money/oversell/Long overflow without returning partial output. BigDecimal/BigInteger quantities/intermediates, exact checkedLong money, noDouble. ActualSwift fullfold generated1553scalar table, NFC canonical equivalence, original display spelling/firstlabel, exact26scalar whitespace shared withchannelhelper. NUL-prefix semantics preserved; pure unitpositions use deterministic keys, futureUIstillneedslocalizedordering. No new productionICU dependency.

TDD16/16unsupported runtimeRED1s→16GREEN +oldrepo16GREEN4s. ActualSwift89goldens exposed NULprefix thenlongquantity1minor roundingRED; Foundation128bit intermediate fit/normalize/scaleddivide correction→17GREEN/native17GREEN0.204s. Expanded143 exposedzero-costlargequantity overflow→zero-fit correction→native17GREEN0.157s;147 addsvalidabove127exponent/max/min/unrepresentableratio:RED→noncompactsig handling→GREEN. Final17nativeGREEN0.171s includes147accounting+32unitvectors, with64interleaved/48highprecision histories. No relaxedmoney assertions. Generator4freshnesstests/sourcehelper/outputSHAchecks/CIpath+actualSwiftgoldenstep/modelnativecompile added; localpassed,nohostedCIclaim.

Full1787JVM173suites0fail/errors/skips, host81s/final63s withmodelnative/Room/allrequiredfeaturecompilepackages/lint/main; Swift611=4+137+470 (newactualenginegoldentest)/contracts15/bothl10n/SQLite7-3-11/Room6assets/art196-111/whitespacegreen. ExactfinalRoomchannel6GREEN0.281s +actualchannelcreate1GREEN3.715s afterunchangedsemanticswhitespacehelperextraction; no fullOverview/Planning/Management rerun claim. Rootdirectsource/diffreview, no independent129/wholebranchapproval. Finalsource/test/CI/version/golden/manifestpatch027fa55becd7bed8d86cbd6073899a34186e6f42f6e83f62db65fae5a47ed56a.

Main129install-r/COLDStatusok1307ms/min26/target36/main20DEX35776214bytes, model4/DB5/Investment9DEX, all4installed/archiveSHA match. Evidence evidence/2026-10-21-investment-fifo.md records exacthashes/stage-specificREDGREEN andprimaryreferences. All11flagsfalse/Room6/SwiftDataV11/iOS751 unchanged, systemfont1.0/API36ARM64transport14only/noSamsung/liveSupabase/productionoperations. No financial mutation/editor/postings/privateimage/RPC integrated by thispurecomponent; fullAPK1–4/RCgoalactive. Nextasset/default-unit management/rebuild integration thenbuy/sell/cash/privateimages/RPC andremainingpreparing/config/family/receipts/globalwallet/settings/background/release/freshwholebranchreview. Separate129committhencontinue.


## Slice130 — actual investment assets and atomic legacy-unit rebuilding — 2026-10-22

Native Investment now supports asset create/edit/archive/restore with stable saved draft identity, exact versions/explicit nulls/unknown fields/image path/creation metadata, owned active channels and actual enabled currencies. All history including tombstones locks channel/currency; complete required membership admission prevents damaged rows from inventing no-history. Source consent, loading/error/retry, save failure/restoration and owner/noncancellable callback guards preserve private drafts and newer edits. Existing four-entity channel API remains intact; asset mutations use one six-entity read/CAS/Room transaction with account fences and complete outbox rollback.

First nil default-unit resolution labels nil history and rebuilds129 FIFO calculations, funding/capital/profit ledger legs, signed postings and booked/derived cash accrual with stored FX/currency, deterministic identities and frozen metadata. Tombstones preserve authoritative deletion; obsolete canonical ledger legs are deleted even when old link/posting rows are missing. Preliminary funding dependency on a free legacy buy follows Swift. Investment-role queued/local/fresh-before-wire deferral and network refusal reserve all derived financial rows for the future dedicated atomic pipeline; no ordinary-domain partial cloud write.

Runtime TDD: initial model8/repository6/Room4/native5 unsupported-flow failures before implementation; corrupt unit/tombstone/metadata/membership/dependency/canonical deletion regressions fail before fixes. Sync27 initially3 failures and HTTPS4 initially1 failure then31GREEN3s. Independent reviewer on immutable30cb3009 identified stale persisted archive quantity and missing ISO minor scaling, then its turn failed at a usage limit before final report; no completed independent approval is claimed. Root verified/fixed both: archive two-test RED1s→FIFO-first18GREEN2s; USD funding/capital two failures1s→major-rate/minor-scale19+repo6GREEN3s. Additional missing raw quantity1RED1s→strict typed admission21GREEN1s; readable typed engine-failure fallback retains Swift behavior. Direct root final source/diff review covers all scoped mutation/read/UI/cloud paths; whole-branch review remains a final-goal gate.

Initial native12GREEN40.516s; real320dp/systemfont1.3 visual test exposed partially expanded sheet clipping, RED3.527s→full expansion1GREEN17.955s. Pre-review complete Asset13+Channel10=23GREEN96.927s. Final full host68s,1817JVM/175suites zero failures/errors/skips, model/Room/required feature native compiles/packages, lint and main; Swift611/contracts15/both strict l10n/SQLite7-3-11/Room6assets/art196-111/fold1553+freshness4 pass. Final complete Asset13+Channel10=23/23GREEN99.721s, RoomAsset8+Channel6=14/14GREEN0.507s, model17/17GREEN0.229s, OverviewCard8/8GREEN21.226s and PlanningDueRoute8/8GREEN38.280s. No full Overview/Planning/Management native suite rerun claimed.

Main130/min26/target36 installed with install-r; COLD Statusok1201ms, main20/model4/DB5/Investment9/Overview9/Planning10DEX. All six installed/archive SHA values match. All18 actual EN/VI/JA light/dark font130/width320 PNGs inspected, final captures byte-identical. Evidence: evidence/2026-10-21-investment-assets.md includes TDD/check logs, limitations and exact artifact hashes. All11 cloud flagsfalse; Room6/SwiftDataV11/iOS751 unchanged. API36 ARM64 transport14 only, no Samsung/live Supabase/production write/deploy/migration. No full font/root/inset/hit-target/grid/hub/private-image parity claim.

Full APK1–4/RC remains active. Next complete the investment linked-wallet/configuration and booked cash move flow needed by cash/trade handling, then buy/sell/cash/private images/atomic RPC and remaining Overview/family/receipts/settings/background/release work. Existing credit-card currency decision stays pending without blocking this independent work. Separate130 local commit, then continue.


## Slice131 — actual investment linked-wallet choices and booked cash moves — 2026-10-22

The native Investment destination now supports first linked-wallet selection, changing only the default, and changing with a full booked-cash move. Wallet/ledger/posting data comes from one owner-scoped three-entity read. Stable visible system/target/amount/event consent, exact Long versions, unknown fields/nulls/creation metadata, bounded CAS retries and current-owner fences preserve newer edits. Targets must be owned, live, unarchived ordinary non-credit wallets in the canonical accounting currency. Missing/incompatible old wallets do not advertise movable cash; choosing a valid replacement without moving uncertain cash remains possible.

Change-only mutates one canonical wallet field/outbox row. Move-all atomically also creates the deterministic investmentReconciliation internal transfer and two opposite cashTransfer/booked/manual postings with null trade/asset IDs. It moves only max(old booked cash,0), excludes known unreconciled/deleted cash, uses checked BigInteger totals and never changes ordinary opening balances or existing postings. Complete event replay is idempotent; partial/unrelated/archived/damaged provenance, invalid versions/dates or inconsistent event dates fail. Existing reserved wallet/ledger client/coordinator guards and all11 false cloud flags remain intact; no dedicated investment RPC enabled.

Native selector/confirmation uses source copy and original wallet art, saved target/system/amount/event, loading/failure/retry/source-conflict states, failed-save restoration and late-owner/noncancellable callback fences. Busy actions prevent duplicate changes. Initial model8/8 runtime RED1s→GREEN; expanded11 then two read-source regressions RED1s→13+repo6 GREEN2s, replay provenance1/14 RED2s→14+repo6 GREEN5s. Repository6/6 RED2s→GREEN; actual Room6/6 unsupported RED→6GREEN0.291s verifies four-row financial atomicity, exact9007199254740993, last-posting trigger rollback, owner/cash-at-CAS races and16 consistent generations.

Initial native5 ran27.473s:4 missing-entry failures,1 mixed-owner fixture failure; fixed per-owner seeding then eligibility1/1 business RED6.722s. Actual5GREEN12.686s, expanded9GREEN25.502s. Initial glyph-only visual1GREEN11.546s missed a Cancel/move action collision revealed by image review; new inter-button bounds1RED3.698s→one vertical action column→1GREEN11.637s. All18 final EN/VI/JA light/dark actual font1.3/320dp card/picker/choice PNGs inspected; full final33 captures are byte-identical. No full font/root/inset/hit-target/wallet-detail parity claim.

Final full host64s,1837JVM/177suites zero errors/failures/skips; model/Room/required feature native compiles/packages, lint/main, Swift611/contracts15/both strict l10n/SQLite7-3-11/Room6assets/art196-111/fold1553+freshness4 all pass. Final installed Room20GREEN6.309s, model17GREEN1.439s, complete Asset13+Channel10+LinkedWallet10=33GREEN615.771s, OverviewCard8GREEN65.692s. PlanningDueRoute8GREEN166.134s: all86 final native cases pass. All18 final captures remain byte-identical, post-run font1.0/no wm override and six installed/archive hashes rechecked. No full Overview/Planning/Management native rerun claim.

Main131/min26/target36 install-r preserves data, COLD Statusok6961ms under emulator load (observation only); main20/model4/DB5/Investment9/Overview9/Planning10DEX, all six installed/archive SHA values match. Final Android source/test/version patch80b5dd77ef639f6c3e83ead175959a6f2ad4bd7ef83c5bffc9e6fdc0a5f1628a. Direct scoped root Swift/diff review and reproduced corrections; no independent131/whole-branch approval claim. Evidence evidence/2026-10-22-investment-linked-wallet.md contains exact hashes and limits. All11 flagsfalse/Room6/SwiftDataV11/iOS751 unchanged/API36ARM64transport14 only; no Samsung/live Supabase/production write/deploy/migration.

Full APK1–4/RC remains active. Next complete exact investment cash allocation and actual wallet/cash-location balances, then reserved-cash usage consent and transaction/payment protection, buy/sell/cash/private images/atomic RPC and remaining family/receipts/settings/background/release work. Existing credit-card currency decision stays pending without blocking independent local work. Separate131 commit after final results, then continue.


## Slice132 — exact investment cash reads and native wallet financial presentation (2026-10-22)

Added actual earned-profit/available-cash/shortfall summary, linked actual/allocated cash and cash-location/original-currency rows with exact BigInteger values. One owned four-entity Room presentation read now serves both linked controls and financial sections;131 three-entity mutation/CAS remains unchanged. Extracted shared raw cash admission/exact wallet engine and persisted-profit reader; Overview delegates retain zero-neutral, FX-pair and existing cash policies. Unreadable profit/cash remain independent, source contradictions cannot relabel another account, unrelated wallet damage cannot erase readable linked cash. No cash is counted twice or relabelled through live FX.

Runtime TDD and direct source/diff review documented in [cash read evidence](evidence/2026-10-22-investment-cash-read.md). Final1869JVM/182suites zero fail/error/skip, full host/lint/APK/test builds, Swift611 and11 contract/l10n/store/schema/assets/diff checks pass. Actual emulator95scopedtests pass:39 Investment/23 Room/17 accounting/8 Overview card/8 Planning route. Initial9 virtual-row fixture failures fixed by actual LazyColumn scrolling; money-wrapping visual failure fixed by adaptive exact sizes.36 EN/VI/JA lightdark font130 width320 images inspected. No whole Overview/Planning/Management native suite claim.

Version132 update installed on API36ARM64 transport15, preserving data; six archive/installed hashes match. Main SHA9ce8c443c9c88860e32589f986a1c7e825c08543ddec6d05ce6374ad338dfbcb; COLD1248ms single observation, not performance acceptance. Source patch100e7e48311ad5b30e4acef936675d1d23f2c89c3c71166b315887ebbcfe2547. All11flagsfalse/Room6/SwiftDataV11/iOS sources unchanged. No Samsung/live Supabase/production/deploy/migration/push. Author direct scoped review only; fresh whole-branch review remains pending.

APK1–4/RC remains incomplete. Continue actual cash refill/withdraw/reconciliation and reserved-fund protection in transaction/payment edits/restores, then trades/private images/dedicated RPC and remaining APK3/RC flows. No placeholder actions were added. Keep user's budget branch currency and bill/installment same-currency wallet decisions; installment correction applies to both platforms.


## Slice133 — actual investment cash deposit/refill and withdrawal (2026-10-22)

Native Investment now creates deposits and withdrawals through a complete owned same-currency form: exact amount/max/limit, wallet choice, same-wallet explanation, note and actual date/time pickers. Missing linked preference routes through the real selector and resumes only after save. Same-wallet flows reclassify allocation with actual balance unchanged; other-wallet flows move actual cash once. Deposit uses profit shortfall/source ordinary limit; withdrawal uses source booked linked cash. Exact BigInteger reads retain values beyond Long while a single wire amount caps at Long.MAX_VALUE.

One shared owner four-entity presentation read and frozen wallet/capacity consent feed strict raw planning, whole-four Room CAS, two financial rows/two outbox entries and before/after owner fences. Complete exact replay returns without another write even after exhausted capacity; partial/tampered/reused events and orphan queues hold. Pinned save/cancel match Swift scaffold. Feature saved-state/same-owner DI rebinding retain drafts; late old-owner callbacks cannot dismiss or leak private data. Source-derived Foundation whitespace and lost linked-success receipt bugs fixed with runtime regressions.

[Cash transfer evidence](evidence/2026-10-22-investment-cash-transfer.md) records runtime RED→GREEN and initial fixture/timing failures without erasing them. Final full1896JVM/185suites zero fail/error/skip; lint/build/required native compiles pass, Swift611 and11contract/l10n/guard/schema/assets checks pass. Actual emulator122scopedtests pass:Investment58/Room31/accounting17/Overviewcard8/Planningroute8.36native EN/VI/JA lightdark actualfont130/width320 captures refreshed/hashed/inspected. No whole Overview/Planning/Management native claim.

Version133 install-r/COLD succeeded, six installed/archive hashes match; main SHA f651c005a1be6d029a819414fafbd7b77ecc151f62fd96e0fe895812a09d8a68. COLD6693ms single emulator observation, not performance acceptance. Source patch SHA1ed5928177d5ff1f74d4968aa14dff14b138745e519dbde2187c0b7e004c74ab. All11flagsfalse/Room6/SwiftDataV11/iOS sources unchanged; API36ARM64 only, no Samsung/livecloud/production/deploy/migration/push. Author scoped review; fresh final whole-branch review remains open.

APK1–4/RC remains incomplete. Continue complete cash history/edit/delete/reconciliation and reserved-fund protections for ordinary transaction/payment edits/restores, then trades/private images/dedicated RPC and remaining family/receipts/background/settings/release work. No placeholder actions. User's budget and bill/installment same-currency decisions remain in force, including both-platform installment correction delivered62–64. Separate133 local commit, then continue.


## Slice134 — investment cash history and manual transfer edit/delete (2026-10-22)

Completed native preview/full timeline, exact signed money/original gross currency, source grouping/filter and real scrolling pagination. Manual deposits/withdrawals reopen original values and support confirmed atomic edit/delete with dependency checks, strict replay after lost receipts, metadata/imported-posting preservation, whole-four Room CAS and before/after owner fences. Back, read/save/delete failure/retry, draft restore, same-owner rebinding and noncancellable old-owner completion are covered by real native/Room assertions. Ordinary/trade rows remain readable; their editor routes remain open.

[Cash history evidence](evidence/2026-10-22-investment-cash-history.md) records runtime RED→GREEN, direct Swift/diff review and corrections. Final full1921 JVM/188suites zero failures/errors/skips; host lint/build/native compiles pass; Swift611 and11 required checks pass.148 unique scoped native cases accepted: Investment77, Room38, accounting17, Overviewcard8, Planningroute8. Investment aggregation explicitly retains the first77 run's old channel readiness failure and corrected complete Channel10 run; it is not a clean single77-run claim.30 native EN/VI/JA lightdark actualfont130/width320 images inspected/hashed.

Version134 install-r/COLD succeeded, all six installed/archive hashes match. Main SHA9664f1f95f20973a6462af720b75c010effb5c3c30f6cae200e166ab0ee7b203; COLD6477ms single emulator observation, not performance acceptance. Source18-file patch SHAd194983e4648ca3180d03b4e66a6bb56a6adc4264d45af2ba616533fdd8eeaa8. All11flagsfalse/Room6/SwiftDataV11/iOS unchanged. No Samsung/live Supabase/production writes/deploy/migration/push. Author scoped review only; fresh whole-branch review remains open.

APK1–4/RC remains incomplete. Reconciliation cross-currency product choice is pending; continue independent reserved investment fund protections for ordinary transaction/payment edits/restores, then remaining trades/privateimages/atomic RPC/family/receipts/background/settings/release flows. Existing user currency choices remain in force, including both-platform installment correction delivered62–64. Complete134 local commit independently, then continue.


## Slice135 — historical investment fund usage read foundation (2026-10-22)

Added strict exact chronological read/comparison of owned ordinary cash and investment allocation; source occurrence/creation/posting/unsignedUUID order, excludes derived consumption/automatic adjustments, handles ordinary→booked→unreconciled and owned internal transfer allocation. Income/date/source edits/removal recalculate downstream usage; retains all changed wallets and exact values beyond Long. One existing owned four-entity Room snapshot feeds both timelines, no rows/versions/queues changed. This read proof is not current affordability or save consent. Unsupported needed reserved FX conversion holds explicitly; ordinary paired FX remains readable.

[Timeline evidence](evidence/2026-10-22-investment-fund-timeline.md) records runtime RED→GREEN and actual source-currency regression fix. Final1944JVM/190suites zero fail/error/skip; full lint/build/Room native compile, Swift611 and required contract/l10n/store/schema/assets/fold/diff checks pass.76 actual emulator tests pass:Room41/model35 (same18 timeline vectors on both runtimes). No UI or full-feature native claim. Main135 installed with three archive/installed hashes verified, SHA0949e14a2ad81ea9ad501eafdb18bc783ed605b6813de1f4146ac742ad060ce2; COLD1098ms observation only. Source SHAf1d7497cdcc3587b06b32297831c97b4aed1b4df575b7d029c50ff3c37d153d0. All11false/Room6/iOS unchanged; no Samsung/cloud/prod/deploy/migration/push. Author scoped review, final whole-branch independent review pending.

APK1–4/RC incomplete. User now chose same-currency reconciliation only on both iOS and Android; implement next. Ordinary fund usage confirmations, derived atomic writes, payment/edit/restore integration remain to finish after this read foundation; no protection-flow completion claim. Remaining trades/family/receipts/background/settings/RC unchanged. Independent local135 commit then continue.


## Slice136 — iOS same-currency reconciliation correction (2026-10-22)

Applied user's same-currency reconciliation decision to existing iOS service and selection UI. Entire positive batch currency/active-wallet/original-unit preflight runs before any row; holder/linked/accounting must share supportedJPY/VND. Foreign locations readable but not actionable, stale selected ID cannot become reconcile-all, source change clears real-transfer consent. Original80actual/50booked behavior retained.

[Currency evidence](evidence/2026-10-22-investment-reconciliation-currency.md): runtime policy2RED and SwiftData4RED (including actual partial/pending rows)→GREEN, final original-unit/archived-linked characterization. FullSwift618zero failures, actual iOSSimulator arm64+x86_64 application build succeeds including changed view; compilation only, no native iOS UI/touch claim. Build script's sole automatic plist751→898 delta was verified/restored; no plist/version change committed. FullAndroid1944JVM/190/lint/build/Room compile pass, all required contracts/l10n/guard/assets/fold checks pass. Android source/APK unchanged136. Source5Swift-file SHA5413dd8d8748a088411835ccd72b7889357e83f133240f84d2925b85f4485301. Author scoped review; final whole-branch independent review remains open.

APK1–4/RC incomplete. This completes iOS correction; next137 must deliver missing Android same-currency real reconciliation UI/atomic writes/native proof. All11gatesfalse/Room6/SwiftDataV11; no Samsung/livecloud/production/deploy/migration/push. Keep full remaining goal, continue immediately after local136commit.
