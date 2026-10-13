# Gated due-occurrence push — 2026-10-13

New coordinator reuses verified generic outbox conflict/retry/cancellation and
conditional tombstone paths. Typed due record identity/owner/version checked.
Scheduled/paid dates normalize by instant only for semantic comparison; actual
server payload is retained on ACK. Exact nullable15field contract and Long
versions/amounts retained. Live source dependencies defer by source kind, and
linked transaction pending defers both UPSERT and DELETE. This keeps ledger
push before payment occurrence, including undo deletion. Missing remote tombstone
can ACK after linked transaction dependency settles.

App introduces ALLOW_DUE_OCCURRENCE_CLOUD_WRITES=false. Coordinator/network
allowlist additionally require global, transaction, bill, wallet and category
gates; push list includes occurrence after upstream sources. All nine flags
false. Credit-card/installment full workflows remain incomplete, despite typed
source dependency mapping. No production calls/migration/deployment.

TDD missing API compileRED then10 runtime failures, GREEN11 coordinator cases;
9 HTTPS PostgREST tests confirm owner-filtered fetch/create/conditional update,
exact nullable/Long payloads, sparse tombstone patch, foreign rejection and
disabled/independent allowlist. Engine ordering verifies occurrence before pull
and after bill/ledger. Source gates preserve queue/retry metadata when deferred.
Static reviewer found no actionable P1/P2 in this bounded slice.

Android full unit/lint/build/Room/UI compilation passed724tasks/19s:599 JVM tests
in74 suites, zero failures. Shared Swift PlanningLogic53 pass, including pending
separate cross-platform currency rule test. Contract15, Android l10n, strict
Swift generation and diff checks pass. ADB empty; no device/cloud runtime claim.
Concurrent currency-rule source edits are a separate uncommitted slice.

Reviewed current Supabase changelog (Postgres minor extension notices unrelated
to this client-only patch) and primary REST/security docs:
https://supabase.com/docs/guides/api
https://supabase.com/docs/guides/api/securing-your-api
Scope remains client gate/RLS-aware owner filters, no grants/schema/auth changes.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-due-occurrence-push-v18.apk
Package vn.com.quyln.mistia.debug, versionCode18/versionName0.2.0-apk2-debug.
SHA-256:672b46b64abfbd1b745a638c0f697147cf27022f4b63f824714fefcb5b5e2666

User clarified bill payment wallet must match currency on Android AND Swift.
Next: enforce this rule in UI and persistence, then actual atomic payment/undo.
Other open dependencies: currency settings, maintenance/cards/installments,
category legacy-ID/startup bootstrap, APK3–4 and final physical verification.
