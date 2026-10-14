# Stable bill payment identity after undo — 2026-10-14

Base6df39d2; versionCode23. Repayment of an owned tombstoned paid cycle revives the same ordinary expense and all matching occurrence IDs. It preserves creation audit and exact Long base versions, clears tombstones, and replaces DELETE with UPSERT atomically. An old in-flight deletion can now compete with one payment ID, rather than leave two expenses. Same/backwards clock operations advance updatedAt past the previous payment/undo clock; occurredAt remains the real supplied payment time.

A live previous ledger refuses repayment until paid-history reconciliation resolves it. Missing/ambiguous prior links, archived/shared/investment/receipt dependencies, prior reporting overrides or changed original currency refuse before any writes. These guards are explicit pending unsupported lifecycle work; no silent new ID fallback. Paid statement lock checks both original reused and proposed transactions, consistent with the ordinary transaction edit guard. Raw unknown ledger/occurrence JSON survives both undo and repayment, with known typed changes and exact pending payload installed together.

TDD: three initial repayment regressions failed at runtime; implementation made them green. Expanded duplicate/future-clock/receipt/missing cases pass. Independent review found P1 original statement-lock bypass and P2 unknown payload loss. Both reproduced with two runtime failures and fixed; reviewer found no remaining actionable P1/P2. Late DELETE response followed by repayment UPSERT is tested through the real transaction coordinator, preserving one ID without create.

Validation:666 Android JVM tests /78 suites green; full lint/debug build, database/planning instrumentation compile pass. Existing Room reopen/pay/undo test now includes repayment and stale ACK/failure rejection (compiled only). Swift Planning53 pass; contracts15, Android/strict Swift localization, actual SQLite outbox CAS4 methods and diff checks pass. All nine write gates remainfalse. No ADB devices, no Android runtime UI/Room/device claim, no live cloud or production writes.

APK android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-bill-repayment-v23.apk
SHA256 4ef6c1dabe43d0ae24a3a64317dc34432a705bb9ce2793decaccba2655b8919b

Next: atomic category identity/reference/outbox/translation reconciliation and create/409 wiring before startup. Full APK1–4, fund usage/shared/receipt cleanup and physical verification remain incomplete.
