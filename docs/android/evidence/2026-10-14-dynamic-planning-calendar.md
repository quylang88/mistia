# Dynamic planning calendar — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `a374217`.

## Behavior and direct Swift review

The default singleton finance repository previously froze ZoneId at construction. After a device time-zone change it could reject valid new budget/bill drafts and miss an automatic payment already due in the new local day. Four runtime tests reproduced these failures.

The default repository now resolves the current device ZoneId once per budget save/delete, recurring bill save/skip/undo/resume/archive and bill payment/undo operation. An explicitly supplied ZoneId remains fixed for fixtures/callers. Each bill maintenance pass captures one calendar and builds its payment executor with the same calendar; event generation, automatic date checks, credit-card statement locks and notification planning use that single captured value even if the system zone changes during a suspend/read.

Compared directly with `Mistia/Shared/CoreLogic/MistiaLocalization.swift` MistiaCalendar.current, which uses Gregorian/autoupdatingCurrent time zone, and Swift planning/bill maintenance entry points. Default Android repository now follows device calendar between operations instead of requiring process restart. No financial amount, owner, schema or cloud gate semantics changed.

## Verification

Four runtime TDD RED→GREEN cases cover default budget/bill save and direct/maintenance automatic payment after UTC→Tokyo device change. Two additional regressions cover mid-snapshot device-zone change (one coherent successful money pass) and resume at a UTC/local month boundary. Existing explicit-zone tests remain GREEN.

Full Android **846 JVM /91 suites**, zero failures/errors; Room/planning AndroidTests compile; lintDebug/assembleDebug pass. Swift Planning53, contracts15, both localization checks, SQLite outbox7 and notification DAO/schema3, whitespace checks pass. Logs: `/tmp/mistia-dynamic-planning-zone-{red,green,full,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-dynamic-planning-zone-v45.apk`; debug package/versionCode45 verified. SHA256 `85c916baa8e0249203064f18e4a9c495b3a12a519b9327b338270f530d0bc02f`.

## Limits and next slice

No ADB/emulator/Samsung. Device settings-change/UI refresh, WorkManager clock timing, Room rollback and visual QA unverified; AndroidTests compile only. Independent review pending availability; direct Swift/self-review completed. Nine cloud flagsfalse, no live Supabase write/deploy/migration.

Review of Swift OS scheduler confirms native OS alerts are low-cash-wallet reminders at next local 09:00; bill notices are inbox records. Next implement that wallet reminder model/local persistence and Android OS scheduling, rather than posting bill inbox entries as unsolicited OS alerts. Immediate preference triggers, other notification domains and full APK1–4 remain open. Goal active.
