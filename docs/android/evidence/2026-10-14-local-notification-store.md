# Owner-scoped local notification storage — 2026-10-14

Room schema5 adds `local_app_notifications(owner_user_id,notification_key,
payload_json)` with composite primary key and migration4→5 registered after prior
migrations. Local notifications never enter the cloud outbox. Observation/read
APIs validate persisted owner/key/source and support full owner snapshot CAS
batch replacement inside one Room transaction. Account clearing includes this
table and preserves other owners.

The model mirrors MistiaRecurringBillNotificationBatch's repeated upsert behavior:
read state, first read time, original creation and resolved action survive repeat
updates; forceUnread resets unread/creation/read timestamp while preserving action.
Structured bill/cycle resolution marks only local actionable payment/failure/
overdue records read+resolved, preserving success/family/other-owner/other-cycle
rows. Exact metadata JSON including >2^53 Long and explicit null stays intact.
This is storage/model only; bill event-to-notification generation, atomic success
notification with money, localized copy, native center/delivery and hooks remain.

Verification:

- Six model runtime REDs -> GREEN for repeat/force-unread/read/resolve/scope/error.
  Timestamp exception assertion was corrected to actual DateTimeParseException.
- Actual production migration/DAO SQL executed in SQLite:3 runtime REDs for missing
  migration -> GREEN; compares exported schema5 table shape, exact outbox retention,
  same-key owner partitioning and owner-only account clearing/no cloud mutations.
- Existing production outbox CAS script now reads schema5:7 methods pass.
- Two Room reopen/rollback/stale/owner tests and migration4→5 test compile only;
  no Android runtime assertions claimed.
- Full Android768 JVM/82 suites,0 failures/errors; database/planning AndroidTest
  compilation, lintDebug and assembleDebug pass (724 tasks).
- Swift Notification13 tests (8 data+5 core), contracts15, both l10n checks,
  git diff --check pass. ADB empty; no live Supabase/production writes.
- Independent review remains pending due reviewer usage limit. Direct Swift/self
  review completed. All nine cloud gatesfalse. Full APK1–4 parity is incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-local-notifications-v35.apk` (vn.com.quyln.mistia.debug, versionCode35).
SHA256: `2b41c1fd18fe1a20efda1ef04c7b24efd5730e17882963b07c41fea8c2c2904c`.
