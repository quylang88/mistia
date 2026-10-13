# Bill skip / undo skip — 2026-10-13

Native Planning bill rows expose skip or undo-skip for pending/skipped active
cycles, with captured source/month confirmation, busy/repeat guard and failure
feedback. Paid and archived rows have no skip action. Repository derives the
current schedule, creates or updates pending occurrences to skipped with explicit
null amount/paidAt/linkedTransaction, and performs no ledger mutation. Repeated
skip is idempotent. Undo tombstones every owned skipped duplicate with a DELETE
outbox entry per record; paid, foreign and other-cycle rows remain intact.

New LocalStore conditional bill-cycle batch compares the source bill and complete
cycle snapshot including tombstones/viewer envelopes inside the same Room
transaction as record/outbox writes. Source/cycle arrivals abort stale operations.
Occupied foreign viewer identity cannot be overwritten. Owned wire/payload IDs
must match before mutation; payload owner is filtered before decoding foreign
rows. Sync versions/base versions remain Long, including9007199254740993.
No schema migration. Unsupported stores fail explicitly rather than write without
snapshot checks. No due-occurrence cloud push gate added or enabled in this slice.

Direct Swift review: DuePaymentSheet guards pending skip and nonnil due-item undo;
PlanningSupport.saveDueSkip/upsertOccurrence clears amount/paid/link; undoDueSkip
marks every matching skipped occurrence deleted. Android queues all duplicate
changes atomically rather than dropping any required matching outbox mutation.
Independent static reviewer found a stale-undo schedule gap; regression RED
proved it, then current projection guard fixed pause/resume schedule changes.
Reviewer verified no remaining actionable P1/P2 in this bounded slice.

TDD: repository API runtimeRED2 thenGREEN, wire identity retarget regressionRED,
and stale undo after pause/resume regressionRED thenGREEN. Eight added repository
tests cover exact cross-month scheduled date, null snapshots/no ledger writes,
idempotence/re-skip after tombstone, paid/foreign/unscheduled protection, duplicate
undo/version preservation, failed batch rollback, arriving paid cycle and viewer
scope. Existing real Room reopen test extended for skipped state and DELETE
outbox; new native confirmation test verifies skip/undo keeps ledger empty. Both
instrumented assertions are compiled, not executed (ADB empty).

Final Android full checks:579 JVM tests/72 suites, zero failures/errors;
Room/UI instrumented Kotlin compilation, lintDebug and assembleDebug pass
(724tasks/final49s). Swift PlanningLogic52 pass. Contract15, Android l10n,
strict Swift generation and git diff --check pass. Local direct/static reviewer
verification; no emulator/Samsung or production runtime claim.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-bill-skip-undo-v17.apk
Package vn.com.quyln.mistia.debug, versionCode17/versionName0.2.0-apk2-debug.
SHA-256: f7001878d29daaf8cb2ce393e82e44de4c951ebaaa1b5f9f17d75dc834ed12c7
Eight write gates false. No production requests/writes/deployments/migrations.

Remaining: actual payment + undo payment with atomic money/occurrence/outbox,
separately gated due sync, due maintenance/notifications/auto-pay, credit-card
and installment workflows, currency preference, category identity reconciliation/
startup bootstrap, APK3–4 and final physical verification. Full goal stays active.
