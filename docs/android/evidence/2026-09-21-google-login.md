# Google login diagnosis — 2026-09-21

Base commit `2ffe485d1ff271c2f61ee623cc0fe9b93106b88b`, uncommitted work.
Physical Samsung SM-F776Q, Android 17/API 37, ADB serial R5GL72ERETZ.
Installed with `adb install -r`: `0.1.2-apk0-debug`, versionCode 3.
Package manager confirmed version 3 and update time 2026-09-21 21:05:58.
No uninstall or clear-data was performed in this diagnosis.

## Reproduced failure

User confirmed Google account selection succeeded, but app remained on login.
Version 2 swallowed Credential Manager cancellation silently. A failing unit
regression reproduced missing UI feedback; version 3 now shows generic
localized failure feedback without automatically retrying consent.

The user retried on version 3. Safe app events:

```
09-21 21:06:56 GOOGLE_PICKER_STARTED
09-21 21:07:11 GOOGLE_PICKER_CANCELLED
```

Google Play services `GetTokenResponseHandler` reported that the Android
application is not registered to use OAuth 2.0 and that package name and SHA-1
certificate fingerprint must match Google Developer Console registration.
No Google ID token was returned, and no Supabase exchange event occurred.
Root blocker: Android OAuth registration for this debug package/certificate.

Read-only Supabase `/auth/v1/settings` confirms both Google and email providers
are enabled; no settings or database records were changed.

## Changes and checks

- Injectable Google provider enables tests of cancellation, token/nonce handoff,
  rejected exchange and successful session publication.
- Debug diagnostics accept only fixed enum events. No token, nonce, email,
  exception message or server response is logged by these diagnostics.
- Missing, cancelled, unexpected and parsing-failed credentials have distinct
  diagnostic events; UI remains localized and does not expose implementation
  details.
- KSP upgraded from 2.2.21-2.0.5 to 2.3.12: old KSP could not resolve the new
  provider interface even though Kotlin compilation independently succeeded.
  Updated KSP passed compilation and Hilt/Room generation.
- Kotlin remains 2.2.21, Google ID remains 1.2.0. The observed OAuth registration
  rejection is not fixed by changing compilers. User permits Kotlin 2.4 if a
  dependency requires it; latest Google ID 1.2.1 is not required for this fix.
- Final Android unit/lint/assemble command passed: **35 tests, zero failures**.
- Contract check passed (15 entities); Android/strict Swift localization checks
  and `git diff --check` passed.
- Independent review found no introduced P1/P2 issue. Suggested fixed parsing
  diagnostic was added and included in the final build.
- Swift runtime unchanged since previous evidence; the recorded V7 migration
  test failure remains unresolved. Do not claim the Swift gate is passing.

## Artifact and next action

APK: `android/build/outputs/apk0/2026-09-21/mistia-0.1.2-apk0-debug-v3.apk`
SHA-256: `3276f8283c59ab29b3b044e46346673439c09b6b66a965417c3a84da89f7a0fb`.
Build/test logs: ignored `android/build/reports/preflight/2026-09-21/`.

Registration details are in `docs/android/google-oauth-setup.md`. Google Cloud
is open in the Codex browser, awaiting user login to the project. No OAuth
client has yet been created/modified. After registration, verify an actual
successful token exchange and signed-in navigation on Samsung.

APK 1–4 and RC remain incomplete. Cloud financial writes stay disabled pending
baseline authentication/device verification and each individual domain gate.

## Resolution — supersedes the pending-registration status above

The user signed into Google Cloud project `mistia-492216` (741455632256).
Only the existing iOS and web OAuth clients were present. After the user
explicitly confirmed the completed form, an Android OAuth client was created:

- Name: `Mistia Android debug - Mac 2026-09`
- Package: `vn.com.quyln.mistia.debug`
- SHA-1: `35:4E:93:46:C5:35:CA:D6:9E:6C:08:6C:20:33:00:78:1F:5C:42:23`
- Client ID: `741455632256-12uieac1sm1v17am9ro25gkrjrii9vgr.apps.googleusercontent.com`

The existing iOS/web clients were not modified. On the subsequent Samsung
attempt, fixed diagnostic events confirmed:

```
09-21 21:11:58 GOOGLE_PICKER_STARTED
09-21 21:12:07 GOOGLE_TOKEN_RECEIVED
09-21 21:12:07 GOOGLE_EXCHANGE_STARTED
09-21 21:12:08 GOOGLE_EXCHANGE_SUCCEEDED
```

The user independently confirmed entering the app. All 23 pull tables completed;
Room contained one viewer partition and zero outbox mutations. After force-stop
and cold launch, the signed-in root remained visible with no login button.
Temporary local copies used to inspect aggregate Room counts were removed;
only aggregate counts remain in ignored evidence.

The unchanged Swift V7 migration test also fails with a clean scratch build
(`android/build/swift-clean-check`), so it is not resolved by clearing build
cache. The failure is CoreData 134504 / unknown coordinator model version;
the nearby insufficientPosition log in the full suite belongs to a separate
expected oversell test and must not be presented as this test's root cause.

Latest user direction, 2026-09-22: do NOT require live account-switch testing.
Continue APK 1–4 and substantially complete Android UI/functionality to match
iOS; the current signed-in screens are only a read-only baseline, not parity.

## Current-Mac debug-key follow-up — 2026-09-23

The APK reinstalled from the current Mac was signed with SHA-1
`84:EE:48:1E:2A:17:C4:5E:0E:52:27:71:2F:5F:58:7F:7B:19:0B:4E`, so the
older `35:4E:93:...` Android OAuth client could not authorize it. After the user
registered the current package/SHA-1 as a second Android client, a new Samsung
attempt produced:

```
GOOGLE_PICKER_STARTED
GOOGLE_TOKEN_RECEIVED
GOOGLE_EXCHANGE_STARTED
GOOGLE_EXCHANGE_SUCCEEDED
```

The resumed activity was Mistia `MainActivity`; the authenticated transaction
screen showed pulled cloud records and the native transaction editor opened.
No iOS/web client, Supabase provider setting, RLS policy or cloud-write gate was
changed to obtain this result.
