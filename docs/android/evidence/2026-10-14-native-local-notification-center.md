# Native local notification center — 2026-10-14

Overview now has a notification bell and live unread badge. The native route
shows Swift's known notification groups, newest group previews, unread counts,
and group detail sections by local day/newest rows. Opening a group marks the
presented keys read. The toolbar provides read-all and sync; pull-to-refresh and
back gesture are connected. Existing localized labels and dark/light Material
colors are used. This is the local center; family remote data, payment/top-up
row actions and Fluent visual matching still require additional slices.

Grouping mirrors NotificationCenterGrouping in Swift: bill/card/wallet/budget
and family/access/request categories, pending request routing, dueSoon exclusion,
owner filtering and local future-row visibility. Read updates capture exact
visible rows at invocation, then retry owner snapshot CAS up to3 times; new keys
or same-key replacement content arriving while reading remain unread. Owner keys
reset root navigation and center state/scopes to prevent prior-owner UI/actions
being reused during account changes.

Review found a real visibility bug: repayment after a future undo sync clock gave
the success notification a future creation date. RuntimeRED reproduced; local
notification now uses actual payment time while money keeps its monotonic sync
clock. The notification is immediately visible without weakening outbox ordering.

Verification:

- Grouping4 runtime REDs -> GREEN; read repository3 runtime REDs -> GREEN.
- Future-sync-clock success visibility runtimeRED -> GREEN. Existing exact money,
  scope/notification/batch/CAS tests pass.
- Full Android788 JVM/85 suites,0 failures/errors; Room/planning/notification
  AndroidTest compilation, lintDebug and assembleDebug pass (733 tasks).
- Two Compose tests compile only: group opening/presented keys/viewer protection;
  owner change clears selected group and prior-owner rows. No runtime UI results.
- Swift Notification13, contracts15, both l10n checks, actual SQLite notification3/
  outbox7 methods and diff check pass. ADB empty; no visual/device/live cloud QA.
- Independent review pending due reviewer usage limit; self/direct Swift review
  done. Nine cloud flagsfalse; Room schema5. Full APK1–4 parity remains incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-notification-center-v38.apk` (vn.com.quyln.mistia.debug, versionCode38).
SHA256: `3549d927146ee2055e410942dbfea5ccc2c0f97ab8d5c336c8c46183e0f339c7`.

Next: payment/top-up actions, atomic immediate manual-pay/skip resolution,
preferences and foreground/background maintenance with account cancellation;
family notification RPC/data/actions in APK3 and final visual/device verification.
