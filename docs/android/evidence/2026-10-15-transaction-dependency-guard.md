# Defer transaction push while wallet/category intent remains pending — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `6af36e68`.

Dependency audit before installment paid-occurrence synchronization found a prerequisite APK1 gap: TransactionPushCoordinator relied on category/wallet domain ordering. If an earlier parent write remained blocked/retrying, the transaction still reached the server and could produce an avoidable FK/RLS failure. Domain order alone does not prove dependency acknowledgement.

UPSERT now checks both source/destination wallet IDs and category ID against the current owner's complete pending-ID sets, including blocked and future retries. UUID references are normalized for lookup; explicit null/cleared references and unrelated/other-owner queues do not block it. Deferred children preserve the exact queue, attempts, error and retry time. When the parent leaves the outbox, the next push proceeds normally. Transaction DELETE remains independent of pending wallet/category metadata so expense undo cannot deadlock behind a parent rename/archive/delete. Investment cash event restrictions remain intact.

Added a default-no-op beforeRemoteWrite hook to the shared outbox executor at all five create/base-update/forced-update/base-delete/forced-delete sites. Transaction push repeats its dependency check immediately before POST/PATCH, catching a parent intent queued during the preceding fetch or conflict resolution. Preflight boundaries check cancellation before and after callbacks. Other coordinators retain their existing policy; the new callback defaults to Continue. Semantic ACKs do not require another server write and retain their existing behavior.

Runtime TDD: eight initial cases produced four intended REDs for source/destination/category/UUID-reference dependencies; negative/control cases already passed. Initial guard passed all24 transaction cases. Added a dependency-arriving-during-fetch regression, observed RED, then implemented the before-write hook; final25 transaction cases pass, including create, matching-base PATCH and local-winner forced PATCH variants. The complete sync module passes. Fake pending-ID lookup was corrected to implement its documented owner/entity scope; it previously returned transaction IDs for every entity. This fixture correction is not a production change.

Final **1340 JVM tests /128 suites**, zero failures/errors. Full Android unit tests, database/management/planning AndroidTest compilation, database test APK assembly and app lintDebug/assembleDebug pass. Swift609, contract15, both localization checks, whitespace and existing SQLite outbox7/notification3/installment-deletion11 helpers pass. Existing packaged database test schemas1–6/bootstrap catalog match source. No database/Room schema or Swift runtime change, and no new instrumentation execution is claimed. Database test APK is unchanged from APK66.

Direct Swift self review compared sortedMutationsForPush, ensureRemoteWalletDependenciesExistIfNeeded, ensureRemoteCategoryDependenciesExistIfNeeded and their transaction upload call sites. Android's owned outbox guard prevents bypassing the domain coordinators/readiness flags. This slice does not implement Swift's separate missing-remote-parent repair/create flow; that audit remains open. It also does not turn remote reads and a subsequent write into a cross-record transaction. Independent review remains pending availability.

Logs `/tmp/mistia-transaction-dependency-{red,green,race-red,race-green,full,swift}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-transaction-dependency-v67.apk`: SHA256 `95b70327d7934224577c9c448fb9e6105fcf669a89dd21b40a382616b26092c7`. Debug versionCode67 and actual dependency helper/before-write DEX presence verified.

All10 flagsfalse; ADB empty; no emulator/Samsung/visual/background/live Supabase evidence, production write, deployment or migration. Continue installment paid occurrence/payment-undo financial ACK and source/duplicate/legacy recovery, missing-parent repair, maintenance/notifications/fund usage, pending card policy and remaining APK1–4/RC. Full goal remains active.
