# APK 2 recurring bill gated push — 2026-10-13

Independent ALLOW_RECURRING_BILL_CLOUD_WRITES=false at coordinator and network
allowlist, additionally requiring wallet/category gates. Priority70 follows
savings before pull. Pending category OR payment wallet outbox defers UPSERT
without retry poisoning; DELETE bypasses both dependencies. All eight gates
false. No due-occurrence or installment write gate enabled by this domain.

Shared conditional upsert/tombstone engine supplies create/update races,
semantic ACK, version/winner/conflict/retry/cancellation behavior and protection
against a newer mutation being erased by a stale response. Long version overflow
fails before writes; sparse tombstone patch retains semantic server fields.

Swift RemoteRecurringBillPlan typed decoding/fingerprint comparison found
additional required parity: missing nullable fields and legacy is_paused=false,
all six optional schedule timestamp instants, nil/empty optional raw schedule,
and ignored unknown server extensions. Comparison rebuilds known typed fields
and normalizes dates; wire/request/ACK payloads remain lossless. Raw currency
case is retained in semantic comparison like Swift. Added opt-in record validator
hook (default no-op for other domains) to reject malformed bill fields and local
owner/id/version envelope disagreement before remote IO/ACK/conflict.

TDD missing coordinator RED, then seven runtime contract failures reproduced
before typed normalization/validation fix. All 32 bill coordinator tests pass.
Nine HTTPS MockWebServer tests verify owner/id/version filters, Long amount/
version, explicit nullable wallet/category/device/schedule fields, sparse DELETE,
independent default-disabled allowlists and foreign payload/response rejection.
Sync order test now includes bill before pull. Direct local/Swift review done;
no independent final reviewer approval or production request is claimed.

Full Android testDebugUnitTest, Room Android-test compilation, lintDebug and
assembleDebug passed (713 tasks/12s). 511 JVM tests across 67 suites, zero failures.
Swift outbox5 + transaction conflict9 tests passed (14 total). Contract15,
Android/strict Swift localization generation and diff checks pass.
VersionCode11; all eight write flags false. ADB empty: no emulator/Samsung bill
or UI execution, live Supabase write, migration or deployment.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-bill-push-v11.apk
SHA-256: 75122dd944460ea6b5ddee45ec810a025596c98e675e03af44b52ddd2b9c1580

Next native bill form/lifecycle, then actual payment and due maintenance with its
own gate/contract. Remaining APK2–4 and final visual/physical gates incomplete.
