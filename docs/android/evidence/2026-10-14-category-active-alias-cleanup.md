# Ordered category active-alias cleanup — 2026-10-14

Scope: queued Android bootstrap reconciliation where the real owner-cloud row is
already deleted and one real legacy row remains active. General maintenance of
already-pulled clean groups and startup wiring remain pending.

## Behavior and parity evidence

Swift `MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories`
selects active values and the existing cloud-scoped identity independently, and
repoints references. The local SQL migration
`20260514093000_system_category_cloud_identity_dedupe.sql` retains deleted legacy
rows and enforces a partial unique active `(user_id, system_key)` index. Android
therefore commits both queued writes locally, sends the legacy tombstone before
canonical activation, and checks the complete current owner-key group before
activating an observed category. No SQL or production data was changed.

The atomic identity plan preserves raw alias JSON, references/frozen values,
exact server versions and unknown Long values. Cleanup uses full tombstoned
UPSERT because category DELETE is unsupported. Pending alias/target edits or tasks
are protected. Parent-first ordering is retained. Future/retrying sibling cleanup
defers activation. A newer remote live alias wins its normal conflict resolution
and the fresh activation guard then preserves the canonical queue as conflict.
Observed server version0 follows the same guard without reseeding.

## Verification

- TDD model:21 tests,1 expected runtime failure before implementation; GREEN.
- TDD coordinator:29 tests,4 expected runtime failures before implementation;
  GREEN. In-memory remote additionally enforces the active-key uniqueness rule.
  Coverage includes exact write order/bases, retry/recovery, remote-winning alias
  and observed version0. Existing stale/cancellation/owner/gate regressions pass.
- Full Android:723 JVM tests /80 suites,0 failures/errors; database and planning
  AndroidTest compilation, lintDebug and assembleDebug exit0.
- New Room reopen test compiles only: both version0 pending writes/provenance and
  raw unknown alias metadata survive reopening. Not executed on Android runtime.
- Xcode Swift SystemCategory filter:23 tests (17 data +6 core),0 failures.
- Contract check15 entities, Android l10n and strict Swift l10n checks pass.
- Actual SQLite/schema outbox checks:7 methods pass; git diff --check passes.
- Independent read-only review: no actionable P1/P2 in this bounded slice.
- ADB empty; no emulator/Samsung/live Supabase/production write verification.
- All nine cloud write flags remain false; Room schema remains4.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-category-cleanup-v28.apk`
(package vn.com.quyln.mistia.debug, versionCode28, 0.2.0-apk2-debug).
SHA256: `75f4c8c5fe1c4cf17b332199aa521fffcc4c290c5f07e0004d531f2bbf81916c`.

Full APK1–4 parity is still incomplete. Next is generic observed owner-key group
maintenance, then startup pull/bootstrap and remaining native feature slices.
