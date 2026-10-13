# Atomic local default category bootstrap — 2026-10-13

Owner-scoped missing-default creation from shared catalog, stable cloud IDs,
real device metadata, complete vi/en/ja names and parent references. Existing
IDs, customized fields, favorites, versions, archive state and references are
not rewritten. Legacy system keys are reused; duplicate keys are reported for
separate repair. Known tombstones prevent resurrection and deleted parents
prevent new orphan descendants. This tightens preservation of known tombstones
under the user's explicit instruction to preserve existing data.

Complete owner/entity snapshot includes tombstones through a read-only Room DAO
query; schema unchanged. Valid foreign viewer-cache rows are ignored for self
seeding without decoding their other schema, but any occupied ID is protected.
Malformed self identity/collision aborts before writes. Short owner UUID notation
is rejected; owner UUID case canonicalizes. Batch records and outbox are atomic.

Review found an arriving remote row could be overwritten after planning from an
older snapshot. Runtime RED reproduced it, then conditional insert-only commit
was added: IDs AND owner/system keys are rechecked inside the same Room
transaction. A changed snapshot fails without writing any bootstrap rows; retry
can preserve remote customization. No automatic startup seed is wired yet,
pending protection for untouched seeds versus pre-existing cloud data.

TDD: missing API RED, foreign viewer/short owner regressions RED, arrival race
RED; twelve focused repository tests now GREEN. Tests cover idempotence, account
isolation, archived/custom metadata, tombstones, duplicate reporting, occupied
identities, storage failure/cancellation and same-repository concurrent calls.
Three instrumented Room tests compile: real 147-row catalog reopen/tombstone/
owner isolation, batch rollback and legacy-key arrival/retry. ADB empty: these
new tests have NOT executed, and no emulator/Samsung verification is claimed.
Direct local review against Swift bootstrap/identity and ownership contracts.

Full Android testDebugUnitTest, database Android-test APK assembly, lintDebug
and assembleDebug passed (733 tasks/3s final cached run; preceding full run50s).
527 JVM tests across69 suites, zero failures. Four Swift identity tests,
contract15, Android/strict Swift localization and diff checks pass.
VersionCode12; all eight financial write flags false. No production request/
write, migration or deployment. No independent final reviewer approval claimed.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-category-bootstrap-local-v12.apk
SHA-256: bcc020992f2b4e1f266bfc3ab540e0d74ddd1e2163bb609ddb46ebc8b2342ce2

Stage3 sync customization protection/startup integration remains next. Existing
record normalization/deduplication, native bill UI/payment and remaining APK2–4
and final physical/visual gates remain incomplete.
