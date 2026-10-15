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
