# Background-safe session restoration — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `8ece218`.

## Behavior and reason

Before enabling a cold-process bill worker, direct review found actual auth races: late refresh could resurrect a logged-out account; late logout/401 restore could clear a newly signed-in owner; retained cache could restore an explicitly signed-out session; late login could overwrite sign-out. Five HTTPS MockWebServer runtime regressions reproduced all five.

Auth now versions session transitions under one local lock. Login/signup/Google responses persist only for their initiating generation. Logout invalidates old operations and clears local state before awaiting remote logout. Refresh requests serialize, read only the current active session, require unchanged owner/generation, and never fall back to a signed-out secure cache. Failed old restore can clear only its still-current saved session. Same-owner ordinary refresh still works. Existing email/password, Google nonce/provider, signup and logout-failure tests pass; no OAuth configuration or live account testing changed.

Added singleton SessionRestorationCoordinator shared by future workers and Activity. It serializes initial restore, waits for completion, skips already-resolved states, retries an unresolved failed attempt, and preserves cancellation. Activity now uses this gate. Compared with Swift SessionStore bootstrap's existing-session guard, active profile scope and auth transition boundaries. Android requires explicit generation checks because HTTP completions resume independently.

## Verification

TDD runtime RED: five HTTPS stale-response races and four restore gate failures; GREEN: seven added auth tests (including foreign refresh-owner rejection and concurrent rotating-token refresh) and six gate tests. Full Android **834 JVM / 90 suites**, zero failures/errors; Room and app AndroidTests compile, lint and assemble pass. Full Swift package run passes **601 tests** (4 contract +133 data +464 core); these do not include iOS-only SessionStoreOfflineTests. Contracts15, Android localization, strict Swift localization, actual SQLite outbox7/notification3 and whitespace checks pass.

Logs: `/tmp/mistia-auth-background-race-red.log`, `/tmp/mistia-session-restoration-red.log`, `/tmp/mistia-background-auth-{green,full,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-background-auth-guard-v43.apk`; debug package/versionCode43 verified. SHA256 `80817b53d19b0dc2f572ca09cd02e37361eefc62d117d3465ca839aad4a1e623`.

## Limits

No connected ADB/emulator/Samsung. No device session restoration, Room/Compose runtime or visual verification. Independent review pending availability; direct Swift/self-review completed. Nine cloud-write flagsfalse; no live Supabase writes/deploy/migration. Background worker itself, OS delivery, immediate preference triggers, dynamic ZoneId and full APK1–4 remain open. Goal remains active.
