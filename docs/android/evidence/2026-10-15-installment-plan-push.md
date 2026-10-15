# Gated installment plan push foundation — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `a171e445`.

## Completed plan coordinator

InstallmentPushCoordinator delegates standard owner-scoped outbox create/conditional update/independent tombstone handling to the existing tested pipeline. It validates the complete typed plan against envelope ID/owner/Long version/deletion/clock metadata. Semantic comparison uses Swift's typed UUID/optional values and preserves the raw currency string's case; unknown server extension fields do not create false conflicts. It preserves exact amounts/versions and explicit nullable fields, and uses sparse deletion patches so an independently deleted source retains server business/history fields.

Active plans wait for the owned payment-wallet mutation to finish. UUID comparison canonicalizes valid uppercase/lowercase wallet references without accepting shortened aliases as equivalent. Native DI registers the coordinator and client allowlist under ALLOW_INSTALLMENT_CLOUD_WRITES && ALLOW_WALLET_CLOUD_WRITES. Actual SyncEngine order includes installment priority80 after wallet and before due priority90, matching Swift entity ordering. No payment, ledger or occurrence write permission is added by enabling plan capability in a test.

Create races, conditional update races, semantic ACKs, later local/remote winners, unresolved conflicts, retry/backoff, overflow rejection, cancellation and stale responses follow the generic pipeline. Its CAS ACK/failure path cannot replace a newer mutation or recreate account data removed while a response was in flight. Malformed local/remote identity/type/version data fails closed.

## Dependent deletion remains held

This is a plan metadata foundation, **not complete installment synchronization**. Independent source tombstones can sync, but a source DELETE with a pending owned installment occurrence is held before remote IO. Missing pending-cycle storage also holds it. Unrelated source kinds and foreign payloads do not block an independent deletion. This prevents acknowledging a source deletion while its paid/linked cycle cleanup still has no installment-specific preflight. Child records/outbox and the existing ledger remain intact.

The shared due coordinator/client still permit recurringBill only. Installment occurrence queue entries remain held with zero remote requests; no source-list expansion or bill linked-ledger-delete preflight reuse was made. Do not remove the new source-delete guard or enable installment children until source-delete conflict reconciliation and ledger-preserving dependency handling are implemented. A remote winner for a source deletion must also reconcile the exact dependent child-delete intents; it must not restore an active plan over locally hidden paid history. Merely recognizing a matching timestamp/device is not sufficient proof of a causal deletion batch.

## Direct Swift comparison

Reviewed RemoteInstallmentPlan fields/coding, MistiaSyncRecord installment semantic fingerprint, source summary/differences, mutation ordering (80/90), generic create/version/conflict/tombstone paths and native delete behavior. Swift fingerprints name/icon/exact amount/day/count/frequency/wallet/raw currency/archive/deletion; Android's typed normalization preserves those distinctions and treats absent nullable count like nil. Plan delete preserves the posted expense; dependent occurrence deletion requires its dedicated path rather than bill undo semantics.

## Verification

Runtime TDD:20 initial coordinator cases produced19 intended failures against the inert stub (gate-off already passed). Implementation passed the initial set. Review added a failing dependent-delete regression before the hold was implemented, plus a failing uppercase-wallet UUID dependency case before canonical matching was added. Final25 coordinator cases and10 HTTPS localhost client cases pass; the actual SyncEngine ordering test now includes installment between bill and due.

Final **1137 JVM tests /115 suites**, zero failures/errors. Full Android unit tests, Room/management/planning AndroidTest compilation, lintDebug and assembleDebug pass. Full Swift603 (4contract+133data+466core), contract15, both localization checks, actual SQLite outbox7/notification3 and whitespace checks pass. No new AndroidTest execution or new Room schema is claimed. Direct diff/source self-review completed; independent review remains pending availability.

HTTPS cases verify table/ID/owner filters, exact Long version/amount, nullable fields, conditional race, sparse tombstone PATCH, foreign payload/response rejection, default-disabled gate and isolation from wallet/ledger/due writes. No production credentials or requests are used. Logs `/tmp/mistia-installment-push-{red,green,focused,dependent-delete-red,focused-final,uuid-red,final-green,full,final,swift}.log`.

APK: `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-installment-plan-push-v57.apk`; debug package/versionCode57 and coordinator DEX presence verified. SHA256 `92806e5f4291a4999f4c565820433a40da4e33208f8eb1a7259913f829f9c46b`.

## Remaining goal

All10 build flags remain false. Dedicated installment occurrence/source-delete reconciliation, actual payment/undo/currency handling, maintenance/notification audit, pending card settlement policy, app currency/settings and monetary-form audit, full APK1–4/RC and independent/device/visual QA remain unfinished. ADB empty; no emulator/Samsung/live cloud verification, production write, deploy or migration. The full goal remains active.
