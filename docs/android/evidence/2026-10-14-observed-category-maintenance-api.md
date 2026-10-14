# Observed category group maintenance API — 2026-10-14

Scope: model/Room API for real already-pulled groups without any queued seed.
The coordinator/startup path remains a separate unfinished integration.

`planObservedSystemCategoryMaintenance` keeps actual remote identity/version,
chooses active values using the same Swift remote selection rule, preserves all
deleted metadata and financial references, and queues ordered active legacy
cleanup/canonical restoration when needed. It never invents a bootstrap outbox
or absent remote wire ID. All-deleted groups remain deleted. Entire known group
pending edits/tasks, including future retries, defer repair. Newer local clean
metadata rejects a stale remote lookup. Kind/role/owner/key checks fail closed.

Common raw merging and reference/alias repair paths were extracted from the
existing seed implementation and verified with its tests before adding behavior.
`RoomLocalStore.commitObservedSystemCategoryMaintenance` compares the entire
four-table/outbox/task snapshot and installs all changes in one transaction;
there is no source deletion. Existing bootstrap uses the same installation path.

Verification:

- Five new model runtime REDs then GREEN,26 adoption/maintenance cases.
- Full Android728 JVM tests /80 suites,0 failures/errors. Database and planning
  AndroidTest compilation, app lintDebug and assembleDebug pass (724 tasks).
- Room reopen, stale snapshot and injected outbox rollback tests compile only.
  They check version0 provenance, exact Long/frozen ledger values, both pending
  category writes and all-or-nothing rollback. No Android runtime assertions made.
- Swift SystemCategory23 tests pass (17 data +6 core).
- Contracts15 entities, both localization checks, actual SQLite/schema7 methods,
  git diff --check pass. Independent read-only review found no P1/P2 in this API.
- ADB empty; no emulator/Samsung/live Supabase/production writes were run.
- Nine flagsfalse, Room schema4. Full APK1–4 parity remains incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-observed-category-maintenance-v29.apk`, versionCode29, package vn.com.quyln.mistia.debug.
SHA256: `21df5f87ce78e0f8d4ebe46fce6b67f1adc4cfa01927c2edb466103ada8e8c30`.

Next: parent-first maintenance coordinator using full authoritative remote
snapshots, then safe startup pull/bootstrap and remaining APK1–4 features.
