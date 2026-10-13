# APK 2 offline recurring bill lifecycle — 2026-10-13

Typed owner-scoped bills (including archived paid history) and due occurrence
observation. Atomic Room record+outbox save/pause/resume/archive; immutable
currency/created/version and original recurring first-month anchor. Category
icon uses selected live expense child; owner/payload/parent identity and payment
wallet validated. Preferred imported archived category/wallet can remain linked;
new archived/foreign/deleted dependencies fail. Existing category archive rules
still block active bill references. Credit cards are not excluded.

Matches PlanningBillEditor normalizedBillSchedule and PlanningBillPauseActions:
new current/next first month; optional amount; normalized deadline; recurring
auto-pay day window/fallback; one-time local dates and clamped auto-pay date;
one-time edits clear recurrence/pause/resume fields. Recurring edits retain
pause metadata. Pause clears resume anchor, resume starts current local month
without deleting occurrences. One-time pause/resume is a no-op like Swift.
Archive requires every relevant cycle through current month paid; skipped and
foreign/forged paid occurrences cannot bypass guard. Archived bill/occurrences
remain stored for history, with an UPSERT rather than destructive DELETE.
Stale/archived/deleted edit and lifecycle actions cannot resurrect records.

TDD missing API RED followed by GREEN. Twelve repository tests cover lifecycle,
normalization, Long/version preservation, dependencies/scope, historical records,
invalid schedule, failure/cancellation and imported tombstone protection.
Review found a disabled deadline could reject an irrelevant stale due-day value;
its runtime regression failed before conditional validation fix. Initial fixture
errors (duplicate category seeding, native category archive blocked by bill)
were corrected to cache fixture and explicitly simulate imported archived data.
No weakening of existing management validation was needed.

File-backed Room test compiles pause/database reopen/resume/archive, coalesced
outbox and two preserved paid occurrences. ADB empty, so this test has NOT run.
Bill notification resolution/automatic maintenance is still pending its later
slice; no absent notification implementation is claimed as complete.

Full Android testDebugUnitTest, database Android-test APK assembly, lintDebug
and assembleDebug passed (731 tasks/35s on final run). 470 JVM tests across 65
suites, zero failures; 52 Swift PlanningLogic tests, contract15, Android/strict
Swift localization and diff checks pass. Direct Swift/local review completed;
no independent final reviewer approval or emulator/Samsung runtime claim.

VersionCode10, all seven cloud-write flags false. No production request/write,
migration or deployment. Generic Room schema unchanged.
Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-bill-offline-v10.apk
SHA-256: 54fe528cfa5e30b1110b977bef88efc75152228bea37c93ebef12611067ad1e8

Continue bill push, native form/payment and due maintenance; remaining APK2–4
and final visual/physical gates are incomplete.
