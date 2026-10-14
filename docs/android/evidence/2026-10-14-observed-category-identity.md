# Observed remote identity provenance, including version zero — 2026-10-14

Basee084985; versionCode26; local Room schema4, migration3→4 registered alongside1→2→3. A valid remote sync_version0 adopted with a merged edit previously re-entered seed reconciliation every push, never sending its update. Runtime RED reproduced this loop. QueuedMutation now has a local-only observed-identity flag; adoption marks it explicitly even at version0. Seed lookup and untouched-default preference skip observed rows, which use ordinary same-ID conflict/CAS without inventing a positive version.

Room persists the flag in sync_outbox, preserves it across edits/reference repairs and retries, and derives it from clean pulled records or positive base/record versions. Existing positive-base outbox entries are backfilled by the local migration; unknown zero-base entries remain unobserved until lookup confirms them. The flag participates in exact ACK/failure predicates and complete reconciliation snapshots. It never enters PendingMutation payloads or cloud JSON.

Three added JVM regressions pass: zero-version merged edit pushes after one reconciliation, observed edit returning to defaults cannot use untouched-seed preference, pure seed preparation rejects observed queues. Full707 Android JVM/80 suites pass; full lint/assemble and Room/planning instrumentation compile. Actual production SQL/schema SQLite7 methods pass, including stale flag ACK/failure rejection and migration payload/Long version/retry preservation. Three new Room instrumentation tests compile:3→4 preservation, observed-zero reopen/edit/CAS, clean pulled-zero subsequent edit. No device runtime claim. Swift SystemCategory23, contracts15, Android/strict Swift localization and diff checks pass; independent review no actionable P1/P2.

APK android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-observed-category-identity-v26.apk
SHA256 00bafa5176c3161812012b5ab5d68c5f48d14bba8fab8ca6449ef9d1dabe203c
All nine cloud flagsfalse. No ADB device/Android emulator installed, no live Supabase or production changes. Room schema migration is local only.

Next: retained tombstone duplicates, active-key unique constraint cleanup and startup integration. Full APK1–4 remains active and incomplete.
