# Post-pull category maintenance integration — 2026-10-14

`CategoryMaintenanceCoordinator` receives the actual complete remote category
rows, filters valid viewer-owned categories, retains unknown registry keys and
processes known roots before children. Each group captures a fresh full snapshot
and invokes atomic observed maintenance. Pending group edits/tasks or a parent
requiring reconciliation defer; stale CAS is counted separately. This creates
local queued repairs and performs no HTTP writes.

`PullOnlySyncEngine` invokes it after every required and optional table finishes,
for both syncNow and pullAll. It captures category input before the pending-local
merge, so unsent edits cannot masquerade as authoritative remote data. An
incomplete pull never invokes maintenance. Pagination must advance exactly by the
nonempty page size; repeated/empty/gapped continuation fails immediately.
AppModule provides the coordinator using the secure device ID store. Cloud write
gates remain unchanged; default missing-seed startup creation is still pending.

Verification:

- Five coordinator runtime REDs -> GREEN: actual raw input, clean duplicate repair,
  roots-first/dependent child deferral, future edits/viewers, stale CAS/cancellation
  and invalid owned metadata. Fake store uses actual model plans.
- Engine hook/pagination runtime REDs -> GREEN. Both entry points use actual raw
  data after all tables, interrupted pull skips maintenance, invalid paging fails.
- Independent review P2: CancellationException was converted to Result.failure by
  existing engine runCatching. Runtime RED reproduced; both entry points now
  rethrow before failed status. Direct pull and actual maintenance-hook cancellation
  tests pass for both entry points. Re-review: no remaining actionable P1/P2.
- Full Android738 JVM/80 suites,0 failures/errors; Room/planning AndroidTest
  compilation, lintDebug and assembleDebug exit0.
- Swift SystemCategory23 (17 data +6 core), contracts15, both localization checks,
  actual SQLite/schema7 methods and git diff --check pass.
- ADB empty. No Android runtime/emulator/Samsung/live Supabase/production write
  verification. All nine flagsfalse; schema4. Full APK1–4 remains incomplete.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-postpull-category-maintenance-v30.apk` (vn.com.quyln.mistia.debug, versionCode30).
SHA256: `a9f646ef593fa0601bec28d98ce845bf3fa49af5235d6ec9c9e5ce380a3773a2`.

Next: safe missing-default bootstrap on signed-in startup/offline recovery, then
remaining bill maintenance/native APK1–4 slices and final device verification.
