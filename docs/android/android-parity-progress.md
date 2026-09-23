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
- [ ] Add the native create/edit transaction sheet, affordability validation
  and visual verification on Samsung; ADB reported no connected device.

Transaction cloud push and receipt capture/analysis remain later APK 1 slices.
No production write or deployment occurred, and APK 1 remains incomplete.

Evidence: `docs/android/evidence/2026-09-23-apk1-transaction-offline-repository.md`.
