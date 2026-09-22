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
