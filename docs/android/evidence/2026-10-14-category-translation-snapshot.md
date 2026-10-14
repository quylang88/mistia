# Category translation full snapshot safety — 2026-10-14

Basecd16e33; versionCode24. Prerequisite for lossless category identity/reference reconciliation; that migration is not yet wired.

Translation apply now requires the exact raw category snapshot captured before HTTP, and Room compares it inside the same transaction as task removal/category/outbox updates. Same-clock FK, name, metadata or sync-version changes therefore reject stale responses. Task discard/apply/failure SQL also matches device ID, preserving a replacement task even if names and timestamps match. The existing exact name/language/time/attempt predicates remain.

Before HTTP, coordinator verifies owner/entity/ID and payload identity/version/clock/deletion against the owner envelope, skips tombstones, and compares the queued source-language input with the current selected name. Explicit user edits can refresh already populated translations. The raw payload merge retains unknown fields and exact numeric metadata; updatedAt cannot regress behind a future local clock. Swift CategoryNameTranslationService resolver/fallback and maintenance application were compared directly; Android adds full raw-snapshot protection needed for pending FK repair.

TDD: initial actual coordinator RED3 (foreign viewer text, deleted category, unknown/future clock) then GREEN. Actual DAO SQLite device replacement predicates RED2 then GREEN. Review found source-name staleness before snapshot capture: runtime RED1, fixed and rereview clean. Six new coordinator tests total;672 Android JVM tests /78 suites pass. Two new Room tests cover same-clock parent change and task-device replacement; compilation passes, device runtime not performed. Full Android lint/assemble/Room/planning compile, contracts15, Android/strict Swift localization, SQLite CAS5 methods and diff checks pass. Focused Swift Category suites pass (counts in log /tmp/mistia-translation-snapshot-swift.log). Independent final review no actionable P1/P2.

APK android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-category-translation-snapshot-v24.apk
SHA256 21dded8059a12408be1bc638188eae9c8fdf5c42eacb74c0d5621897c83f62d0
All nine write flagsfalse. ADB empty; no emulator/Samsung/live Supabase/production writes.

Next: atomic category identity/reference/outbox/translation migration and owner-key create/409 integration, then startup and remaining APK1–4. Goal remains incomplete.
