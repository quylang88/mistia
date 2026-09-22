# Android auth and branding increment — 2026-09-20

Base commit: `2ffe485d1ff271c2f61ee623cc0fe9b93106b88b`; implementation is currently uncommitted.
APK: `0.1.1-apk0-debug`, versionCode `2`, package `vn.com.quyln.mistia.debug`.
This is an APK 0 increment, not completion of APK 1–4.

## Implemented

- Native Google Credential Manager entry with existing iOS server/web client ID,
  random nonce, SHA-256 nonce for Google and original nonce for Supabase.
- Email sign-in, registration with display-name metadata, confirmation resend,
  recovery request and localized errors. Existing-password sign-in does not
  impose new signup strength rules. Password fields are never saved in Android
  instance state; responses and session diagnostics do not expose credentials.
- Shared iOS launcher artwork and Google/email auth hierarchy; copy continues
  to come from the shared generated localization resources.
- Overview and transactions use source amount with source currency, falling
  back through source/destination wallet currency as Swift does. They no longer
  pair source amount with reporting currency.
- Google ID dependency pinned to 1.2.0: 1.2.1 requires Kotlin 2.4 metadata, which
  the repository's Kotlin 2.2.21 compiler cannot read.

## Checks

- Android `testDebugUnitTest :app:lintDebug :app:assembleDebug`: passed.
  32 Kotlin tests, zero failures/errors. Includes TLS MockWebServer auth
  payload/credential-redaction tests and ViewModel/validation/currency tests.
- Contract drift: passed, 15 entities.
- Android and strict Swift localization generation checks: passed.
- Independent scoped code review: no actionable introduced issue found.
  Device Google integration, saved-state behavior and account isolation remain
  outside the completed mocked/unit verification.
- Fresh Swift regression: 596/597 passed. The unchanged iOS test
  `MistiaMigrationPlanTests.testV7InvestmentStoreMigratesWithoutOpeningPositionOrFees`
  fails with SwiftData `unknownDataStoreSchema` / CoreData 134504 after an
  investment `insufficientPosition` migration error. Isolated rerun also fails.
  Earlier preflight passed; this later failure supersedes it for this increment.
  No iOS runtime changes were made to bypass the failure.

Logs are in ignored `android/build/reports/preflight/2026-09-20/`.

## Physical device status

Earlier baseline: Samsung SM-F776Q, Android 17/API 37, serial R5GL72ERETZ.
The initial auth UI instrumented attempt could not run because transitive old
Espresso called removed `InputManager.getInstance`. Added explicit Espresso
3.7.0, whose release notes document using the system service instead.
Before retesting, the device disconnected. Subsequent attempts reported
`No connected devices`.

After reconnecting and enabling debugging, ADB returned `device` and the
instrumented auth-entry test passed on SM-F776Q/API 37 with Espresso 3.7.0
(`auth-device-connected.log`). This covers visibility/navigation of Google,
email, registration and recovery controls only; it does not authenticate.
Gradle's connected-test lifecycle removed the test target afterward, so the
version 2 artifact was explicitly installed again successfully and opened.
This run is not evidence of authenticated data retention through an update.
Use explicit `adb install -r` and direct instrumentation for later tests where
preserving user session/data matters.

On 2026-09-21 the user reports selecting a Google account returns to unchanged
login UI. Google authentication is therefore still failing/unverified.
Follow-up diagnosis is recorded separately. Authenticated pull/account switching
and full UI/icon visual verification remain incomplete.

Google OAuth also needs registration of this debug package and this Mac's
certificate; a successful build is not OAuth verification.
SHA-1: `35:4E:93:46:C5:35:CA:D6:9E:6C:08:6C:20:33:00:78:1F:5C:42:23`.
SHA-256: `72:06:49:98:DF:2A:81:3F:AC:AB:AE:5E:30:FD:1E:7F:76:31:C9:20:E7:19:D6:BC:B9:00:08:AA:45:D0:23:5E`.

## Artifact and gates

APK: `android/build/outputs/apk0/2026-09-20/mistia-0.1.1-apk0-debug-v2.apk`.
SHA-256: `0457931fb3013d66bac5cd22ffc1cd8f351289eeb194bc048f5122dd4a399c7f`.

Finance writes remain disabled. No production migration, RLS change, deployment
or cloud finance mutation was performed. APK 0 authenticated device gate must
finish before claiming APK 1, and APK 1–4/RC remain incomplete. Feature-parity
release statuses intentionally remain unchanged.
