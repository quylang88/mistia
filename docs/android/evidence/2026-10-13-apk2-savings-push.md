# APK 2 savings goal push — 2026-10-13

Independent ALLOW_SAVINGS_GOAL_CLOUD_WRITES=false at DI coordinator and network
allowlist, additionally requiring wallet gate. All seven write flags false.
Savings priority60 follows budget and wallet before pull. Pending linked-wallet
outbox defers UPSERT without altering retry metadata; DELETE bypasses dependency.
Reuses shared conditional upsert/tombstone engine: explicit nulls, Long versions,
semantic ACK, create/update races, winners, durable conflicts, bounded retries,
cancellation and atomic stale-response protection. Missing/deleted remote
savings tombstones acknowledge without recreating the remote record; live
remote deletion uses sparse owner/id/version-conditional PATCH.

Direct local review against Swift RemoteSavingsGoal payloadFingerprint,
preparedForMutation, processDeleteMutation and shared schema dependencies.
Review found equivalent targetDate instants with distinct ISO8601 representations
could produce a false conflict. Regression at equal version/time failed before
fix. Savings opts into a comparison-only target_date instant normalizer used in
both early semantic ACK and conflict decisions. Stored/request/ACK payloads stay
lossless; other domains retain the existing identity normalizer. Different
target dates still produce a genuine conflict after a conditional race.

TDD observed missing coordinator RED and timestamp regression RED, then GREEN.
24 savings coordinator tests and nine HTTPS MockWebServer network tests use full
typed goal payloads. Cover gate, owner identity, signed precision, explicit
nullable wallet/device/deletion fields, conditional filters, tombstones,
dependencies, conflicts, retries, cancellation and newer mutation protection.
No production request was used. Local final diff/Swift review completed; no
independent reviewer approval is claimed while service is usage-limited.

Validation: full Android testDebugUnitTest, Room Android-test compilation,
lintDebug and assembleDebug passed, 713 tasks/9s on final run.
434 JVM tests across 60 suites, zero failures. Swift MistiaSyncOutboxTests5 and
MistiaSyncTransactionConflictTests9 passed (14 total). Contract15, Android and
strict Swift localization generators and git diff --check passed.
VersionCode8. No ADB device, emulator/Samsung savings/UI execution, live
Supabase write, migration or deployment.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-savings-push-v8.apk
SHA-256: a59e4c4954129ca15aeedb90164f5eefa9c02c03dca14aa634d458583062101d

Next native savings editor/rows/summary; remaining APK2–4/device gates incomplete.
