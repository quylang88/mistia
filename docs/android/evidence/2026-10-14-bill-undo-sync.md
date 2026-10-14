# Bill undo DELETE sync and exact outbox acknowledgement — 2026-10-14

Base cf73773; versionCode22. Ordinary ledger tombstones now use the existing gated conditional DELETE pipeline. Sparse metadata patch includes the owner audit actor, exact Long version and explicit tombstone; missing/deleted remote rows ACK without create. Investment cash deposit/withdrawal roles refuse ordinary writes, matching Swift's dedicated RPC routing (RPC implementation remains open).

A real transaction/occurrence coordinator integration test verifies ledger-before-occurrence deletion. Independent review found a P1: a later remote ledger edit could win DELETE while occurrence deletion still proceeded, leaving an expense without paid history. Runtime RED reproduced it. Occurrence DELETE now checks linked ledger state and restores the matching authoritative paid occurrence when the ledger remains live. Missing/deleted/incompatible paid history retains an explicit conflict without PATCH. Late restore responses cannot clear replacement mutations.

Actual Room SQL also lacked kind/payload predicates: same-clock replacement edits could be erased by an old ACK or marked permanently failed by an old response. Scripts/check-android-outbox-cas.py extracts and executes the production DAO queries in SQLite. Six stale-payload/kind/null assertions failed before the fix; all four test methods now pass. Nullable payload uses SQLite IS equality. ACK and failure bind complete kind/payload snapshots. A real Room same-clock edit test compiles; it has not run on a device.

Validation: 658 Android JVM tests /78 suites pass; database and planning instrumentation compile, lint and debug assemble pass. Three new HTTPS mock PostgREST tests cover sparse exact PATCH, race/foreign responses and disabled writes. Five Swift outbox tests pass with Xcode developer directory (an earlier CLT run selected zero and is not counted). Contracts15, Android localization, strict Swift localization and diff checks pass. Independent rereview found no additional P1/P2 for this slice.

APK: android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-undo-sync-v22.apk
SHA256: be411294dbf67273ab7613ab825ee6a4879eceb033da83ae8439f11bf5e16fc7
Package vn.com.quyln.mistia.debug, min26/target36, all nine write flags false.

No ADB devices; Room/UI runtime and physical verification unperformed. No live Supabase or production writes. Next identified race: undo followed immediately by repayment must coalesce stable payment identity so an older remotely winning expense cannot coexist with a new payment ID. Full category reconciliation/startup, fund usage/receipt/shared cleanup, maintenance/cards/installments/settings and APK3–4 remain open. This slice does not claim the complete bill lifecycle or APK1–4 finished.
