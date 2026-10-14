# Atomic single-remote system category identity migration — 2026-10-14

Baseb8de757. Room now recomputes adoption and dependent FK/outbox/translation repairs inside one transaction after exact complete snapshot comparison. It removes the exact source queue/task, removes a different unpersisted owner-cloud seed identity, installs the real remote identity (clean raw row or merged pending UPSERT), then installs all dependent changes/tasks. Any failure rolls back source, target, outbox and tasks together. No different-ID ordinary ACK is used.

Different-ID removal requires the genuine owner-cloud seed with base/version0, absent from the complete remote selection. Viewer references to the disappearing ID refuse migration. Occupied/newer local targets are protected by the preparation and snapshot checks. Same-ID adoption retains identity and skips FK changes. Authoritative tombstones remain deleted; a separately explicit reference-repair path allows their adoption without resurrecting them. Edited-source/tombstone conflicts retain local data.

This bounded API accepts exactly one fully enumerated remote row. Multiple remote duplicates require explicit reconciliation and are rejected without writes. The coordinator must consume every owner-key page before calling it. Push/create409/startup integration and duplicate cleanup are not yet claimed.

Four new combined model regressions runtime RED then GREEN. Full694 Android JVM/80 suites green; full lint/build/Room/planning compile, Swift SystemCategory23, contracts15, Android/strict Swift localization, SQLite CAS5 methods and diff checks pass. Four new Room tests compile only: persistent adoption/reopen with edited names/large versions/FKs/tasks, rollback after identity removal, stale source/late ACK/failure protection, same-ID and tombstone adoption without fabricated mutations. Independent static review no actionable P1/P2. No Android device, emulator or live cloud execution; all nine write flagsfalse. Latest UI artifact remains v24.

Next: owner-key precreate and post409 coordinator integration, parent dependency handling, duplicate cleanup, then startup and remaining APK1–4. Full goal stays incomplete.
