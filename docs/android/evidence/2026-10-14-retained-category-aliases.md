# Retained system-category tombstone aliases — 2026-10-14

Basef40192c; versionCode27. Full owner-key lookup now reconciles an actual chosen identity plus deleted aliases, preserving every alias's raw metadata in Room. References from all aliases converge to the target in the same transaction; unknown JSON, Long money, frozen budget fields and viewer-owned payloads remain intact. Pending alias edits/translations defer adoption without changing retry state; newer stored alias metadata rejects stale lookup. An active competing identity still requires ordered cloud cleanup and remains an explicit conflict.

Child adoption resolves its system parent through real observed parent metadata instead of retaining a deleted alias parent. Review found the inverse hazard: a deleted owner-cloud parent with a live legacy parent could hide a live child. Runtime RED reproduced it. A live child now defers until parent reconciliation resolves this case; root role/kind validation applies to the selected parent. Existing live legacy FK and queued mutation remain unchanged. Deleted-history children may still retain deleted parent metadata.

New FK repair of a deleted category uses full UPSERT while preserving deleted_at; this transmits repaired parent fields through the supported category pipeline. Existing pending kinds remain unchanged. Model and actual coordinator regressions each failed at runtime with the prior unsupported DELETE, then passed after the fix.

Validation:11 new JVM regressions overall,718 total/80 suites green; full lint/assemble, Room/planning instrumentation compile, Swift SystemCategory23, contracts15, Android/strict Swift localization, actual SQLite/schema CAS7 methods and diff checks pass. Runtime initial adoption RED3/GREEN; inverse-parent review RED1/fixed/rereview clean. New Room retained-alias reopen test and expanded rollback-after-alias-import test compile only. Independent final review no actionable P1/P2.

APK android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-retained-category-aliases-v27.apk
SHA256 fd8b926c3f95e69646626bdc8437df9c735c64ac3e6204897af8d0ea1c4a8835
All nine write flagsfalse. No ADB/emulator/Samsung/live Supabase/production writes.

Next: a deleted cloud identity with an active legacy competitor needs cleanup-before-resurrection under the active owner/key unique index. Parent groups need this reconciliation before live children proceed. Startup/bootstrap and remaining APK1–4 stay incomplete.
