# Category owner-key reconciliation before create and after409 — 2026-10-14

Basefd12d04; versionCode25. Category push with the bundled registry now captures an exact complete local reference/outbox/task snapshot, consumes every owner/system-key page, validates scope/metadata/progress, and atomically reconciles a single existing actual remote identity before creating a seed. A create409 repeats the guarded lookup before same-ID fallback. Changed seeds preserve unrelated remote fields and leave a correctly based merged UPSERT for the next push; untouched seeds adopt the exact remote row without writes. Reconciliation has its own summary count, avoiding a fabricated different-ID ACK or cloud-write claim.

Any pending parent, including failed/future retry, defers a child without changing its mutation or issuing requests. A missing cloud child under a deleted parent retains an explicit conflict; an existing child tombstone may still be adopted. Same-clock edits during lookup reject migration. HTTP errors retain the exact seed for retry, cancellation propagates, foreign/malformed pages fail closed, and a disabled category gate performs no key lookup, fetch or write.

Multiple remote identities remain explicit retained conflicts at this stage. The SQL contract (20260514093000_system_category_cloud_identity_dedupe.sql, read only) has an active owner/system-key unique index and retains old tombstones; duplicate cleanup must account for that constraint before startup. No SQL was changed or executed.

TDD: three new integration regressions runtime RED then GREEN (different-ID precreate, different-ID409, lookup cancellation). Seven additional key paging/retry/stale edit/owner/parent cases pass. Existing seed tests now assert local reconciliation followed by correctly based conditional push; unknown/monetary reference preservation covered. Full704 Android JVM tests /80 suites pass; Room/planning instrumentation compile, lint/assemble, Swift SystemCategory23, contracts15, Android/strict Swift localization, actual SQLite CAS5 methods and diff checks pass. Independent integration review no actionable P1/P2.

APK android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-category-key-reconciliation-v25.apk
SHA256 d2ebac1ab8b3c7deca275cadfe31b4d0a9feb8a77b9153051b5d2b9fecbf1d20
Package vn.com.quyln.mistia.debug / min26 / target36. All nine write flagsfalse. ADB empty; no Room/UI runtime, emulator/Samsung/live Supabase or production writes.

Next: duplicates/tombstone cleanup under the active-key uniqueness constraint, then startup pull/bootstrap. Full APK1–4 remains incomplete.
