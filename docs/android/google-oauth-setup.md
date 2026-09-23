# Google OAuth Android setup — Mac debug certificate

## Observed failure (Samsung, 2026-09-21)

After the user selected an account, app diagnostics recorded
`GOOGLE_PICKER_STARTED` followed by `GOOGLE_PICKER_CANCELLED`. There was no
`GOOGLE_TOKEN_RECEIVED` or Supabase exchange. Google Play services explicitly
reported that this Android application is not registered for OAuth 2.0 and
instructed matching the package name and SHA-1 certificate fingerprint.
This establishes an OAuth registration blocker; it is not evidence of a Kotlin
compiler or Supabase token-exchange failure.

## Registration values

Use the SAME Google Cloud project as the existing iOS/web client, project
number `741455632256`. Inspect existing Android clients first; retain clients
for existing devices and release keys.

- Application type: **Android**
- Suggested name: **Mistia Android debug — Mac 2026-09**
- Package name: `vn.com.quyln.mistia.debug`
- SHA-1: `35:4E:93:46:C5:35:CA:D6:9E:6C:08:6C:20:33:00:78:1F:5C:42:23`
- SHA-256 (if another console requests it): `72:06:49:98:DF:2A:81:3F:AC:AB:AE:5E:30:FD:1E:7F:76:31:C9:20:E7:19:D6:BC:B9:00:08:AA:45:D0:23:5E`
- Existing web/server client ID used by the Android request:
  `741455632256-bi55tot7hie9rtdpru0de2f4hts3m6l4.apps.googleusercontent.com`

The Android OAuth client does not replace the web client ID in the token
request. Do not change or delete the working iOS/web client. Production
`vn.com.quyln.mistia` and its release certificate require their own registration.
Do not regenerate this Mac's debug keystore to work around this error.

[Open Google Cloud credentials](https://console.cloud.google.com/apis/credentials?project=741455632256).
The user signed into Google Cloud. Project `mistia-492216` contains the
expected iOS and web clients and no Android client. The Android creation form
is fully populated with the values above and awaits the user's action-time
confirmation required by the browser tool for a new OAuth registration.
No client has been created or modified yet.

## Verification after registration

1. Retry Google on the installed version 3 APK and select the test account on
   Samsung. No automatic consent retries.
2. Verify fixed diagnostic events `GOOGLE_TOKEN_RECEIVED`,
   `GOOGLE_EXCHANGE_STARTED`, `GOOGLE_EXCHANGE_SUCCEEDED`, and signed-in UI.
3. Independently verify email sign-in, authenticated pull and account isolation.
4. Only then proceed through the financial write release gates.

Public configuration values above are not passwords or client secrets.

## Completed registration and successful device verification

The previously pending form was approved by the user and successfully saved in
project `mistia-492216`. Android client ID:
`741455632256-12uieac1sm1v17am9ro25gkrjrii9vgr.apps.googleusercontent.com`.
Google token retrieval and Supabase exchange succeeded on Samsung version 3,
and the user confirmed signed-in navigation. See the resolution section in
`docs/android/evidence/2026-09-21-google-login.md`. Do not duplicate this
client for the same certificate; a different signing certificate needs its own
Android client as recorded below.

## Current Mac debug certificate — 2026-09-23

Reinstalling from the current Mac used a different debug keystore from the
2026-09-21 APK. Google Play services therefore rejected the first post-install
attempt before returning an ID token. The user retained the older Android
client and created an additional Android client in the same Google Cloud
project with:

- Name: `Mistia Android debug - Mac 2026-09 SHA84`
- Package: `vn.com.quyln.mistia.debug`
- SHA-1: `84:EE:48:1E:2A:17:C4:5E:0E:52:27:71:2F:5F:58:7F:7B:19:0B:4E`
- SHA-256: `33:42:69:BE:54:79:82:B5:5C:EF:95:0F:81:8B:E7:5F:79:12:50:A0:79:34:4F:BA:02:09:51:B4:F5:EA:25:00`

No iOS client, web/server client or Supabase provider setting was changed. On
the same installed APK, Samsung logs then recorded
`GOOGLE_TOKEN_RECEIVED`, `GOOGLE_EXCHANGE_STARTED` and
`GOOGLE_EXCHANGE_SUCCEEDED`; the authenticated transaction list displayed
pulled cloud data. This supersedes the current-Mac registration blocker.
