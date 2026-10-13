# Owner/system-key remote category lookup — 2026-10-13

RemoteMutationStore now exposes a typed SystemCategoryPage read contract. The
fallback explicitly throws unsupported, preventing implementations without this
capability from silently reporting that no remote category exists.
PostgREST implementation performs GET on transaction_categories with explicit
user_id, system_key and is_system filters, ID ordering, bounded item range and
Prefer count=exact. Exact Content-Range produces an explicit nextOffset even if
the server returns fewer rows than the requested limit. Callers must consume
all cursors before reconciliation. Unknown/missing/inconsistent count fails.

Rows retain original payloads, legacy wire IDs, tombstones, nullable fields and
64-bit versions. Scope, key, system flag, typed identity, numeric nonnegative
Long versions, response shape and requested page bound are checked. Invalid
rows are rejected rather than silently dropped. HTTP errors preserve the
existing safe retry classification. Existing mutation behavior is unchanged;
strict response parsing is opt-in for this read.

TDD API compile RED then runtime RED4 with unsupported fallback, followed by
GREEN10 HTTPS mock-server tests for read filters/headers, nulls/Long versions,
legacy IDs/tombstones, empty result, foreign/key/system rejection, malformed
pages, invalid range/key/owner/token with zero requests, invalid versions,
HTTP503 and exact-cursor/server-cap behavior. No production request issued.

Direct source review: Swift MistiaSystemCategorySyncSupport groups by user/key,
retains active/tombstone distinction and repoints categories, transactions,
budgets and recurring bills. Its repointCategoryReferences preserves frozen
budget display snapshots while updating the live relationship. This slice adds
lookup only; it does not ACK different IDs or rewrite local/cloud references.

Final Android 560 JVM tests/71 suites, zero failures/errors; Room and planning
instrumented Kotlin compilation, lintDebug and assembleDebug passed (724 tasks,
final run42s). Swift identity4 and RemoteApply17 pass. Contract15, Android l10n,
strict Swift generation and git diff --check pass. Local direct diff review;
no independent reviewer approval claimed. ADB empty, no emulator/Samsung runtime
verification. Eight generated write gates false; no cloud writes/deployments.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-system-category-key-lookup-v15.apk
Package vn.com.quyln.mistia.debug, versionCode15/versionName0.2.0-apk2-debug.
One packaged shared system catalog asset.
SHA-256: 805546fbdb3f4bbaaed0a591e887dfc7f8158260fd15563e559e12e99a2ec10f

Remaining: atomic owner-scoped identity/reference/outbox/translation handling,
stale-response guards, coordinator create-race integration and startup bootstrap.
Lookup is not yet called automatically. Native bill UI/payment, due maintenance,
remaining APK2–4 and physical gates remain incomplete; full goal stays active.
