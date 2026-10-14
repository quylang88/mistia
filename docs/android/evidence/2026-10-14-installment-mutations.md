# Owned installment mutation repository — 2026-10-14

Branch `codex/android-apk2-4-parity`; baseline `e36f849`.

## Completed repository slice

Added InstallmentRepository save/delete APIs and a stable-ID draft, delegated through FinanceRepository. The existing owned read API keeps its behavior. Saves trim names, validate positive exact Long amount, owned live known non-card payment wallet and picker ranges, preserve imported currency/creation anchor/raw unknown fields and Long base versions, and emit explicit nullable total-cycle clears. Existing archived linked wallets can be retained; newly linked archived/deleted/foreign/card wallets are rejected. Unchanged imported legacy day/frequency values remain representable, while new invalid values are rejected. Total cycles remain nullable Int values as in Swift/SQL; the repository does not silently coerce a nonpositive legacy count.

Edits compare business fields against the user's baseline, excluding ACK-only version/timestamp/device changes. A semantic remote edit fails stale; metadata-only ACKs use the fresh base version. Already-committed desired fields acknowledge without rewriting timestamps. Stable creation IDs and conditional retry let interrupted/repeated/concurrent creation converge on one plan. Currency changes on an existing plan are rejected to prevent interpreting a proposed minor amount in different units.

Deletion marks the plan and every owned live installment occurrence deleted in one operation, preserving each occurrence's amount/status/paidAt/link/version/unknown fields. Existing tombstones, foreign/aliased/unrelated sources and all ledger transactions remain untouched. This follows Swift PlanningInstallmentEditorSheet.deletePlan/deleteOccurrences, which preserves the posted expense ledger. Malformed owned related history fails the whole operation instead of partially cleaning it up. Repeated deletion is an ACK.

## Atomic/account boundary

InstallmentMutationSnapshot captures complete raw plan/wallet/occurrence tables. Room captures and compares the snapshot inside transactions, validates the exact permitted plan/occurrence mutations and commits records/outbox atomically. It checks the existing injected current finance owner before/after snapshot and writes; cancellation rolls back a stale-owner write. The private guard name/message now reflects its shared Finance use; the existing constructor/auth callback remains compatible.

Pure validation rejects ledger writes, missing related occurrence deletions, frozen/unknown metadata changes, foreign identity, incorrect Long base versions, mismatched devices/clocks and unsupported structure. Three fresh CAS attempts handle intervening wallet/source/occurrence changes; persistent conflicts retain data without an unsafe fallback. LocalStore implementations without conditional snapshot support fail closed.

This is metadata CRUD. Linking a wallet performs no payment or exchange and does not decide the remaining settlement currency policy. Native create/edit/delete forms are **not wired yet**; APK54 retains the previous native read pane.

## Domain gate review finding

Added ALLOW_INSTALLMENT_CLOUD_WRITES=false; **all10 flags remain false**. Installment plan writes are absent from the production network allowlist and no installment push coordinator is registered.

Review found the existing shared due coordinator/client could otherwise process installment/card children when bill occurrence writes were enabled. Both now default to a recurringBill-only source allowlist. Unsupported/card/installment/source-less writes are held/rejected before remote requests; queued records remain intact. Sparse due tombstones include the immutable source discriminator, and conditional PATCH adds source_kind_raw_value alongside ID/owner/version filters so a permitted bill request cannot modify a stored row of another source kind. Existing bill behavior remains covered and green.

The current bill preflight assumes occurrence deletion accompanies linked-ledger undo. A future installment push slice must explicitly support plan deletion while retaining the linked expense; it must not simply enable installment children through that preflight. Card/installation source gates remain closed pending their dedicated foundation and product policy.

## Verification

Runtime TDD: initial18 repository cases had17 intended failures against stubs; direct policy/replay/race cases were then expanded. Two due-source coordinator regressions failed against the old unrestricted path. Correct HTTPS client fixtures produced3 unsupported/source-less gate failures plus1 missing source-PATCH-filter failure. Initial HTTP fixtures were rejected by HTTPS configuration and were not accepted as domain-gate proof; they were corrected before implementation/verification. A legacy schedule edit produced1 intended validation failure before preservation was added.

Final **1067 JVM tests /110 suites**, zero failures/errors:35 new cases (24 repository+5 snapshot policy+4 HTTPS client gate+2 existing-coordinator regressions). Full Android tests, Room/management/planning AndroidTest compilation, lintDebug and assembleDebug pass. Four new actual Room tests compile only: coalesced Long edit/delete preserving ledger, outbox-trigger rollback, owner change before snapshot and owner flip during actual SQL/outbox insertion with rollback. They were not executed on a device/emulator.

Full Swift **603 tests** (4contract+133data+466core), contracts15, both localization checks, actual SQLite outbox7/notification3 and whitespace checks pass. The SQLite helper checks do not substitute for runtime execution of the new Room fixtures. Direct review compared Swift editor validation, immutable currency/creation behavior, delete/tombstone persistence, SQL field types and current generic due push/preflight behavior. Independent review remains pending availability.

Logs `/tmp/mistia-installment-crud-{red,green,full,source-gate-red,client-gate-red,source-gate-green,legacy-red,final,swift}.log`. The intermediate source-gate-green attempt exposed the missing URL predicate; the final full run includes the correction.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-installment-mutations-v54.apk`; debug package/versionCode54 verified. SHA256 `83b557f6c8e39501b2d800596a9f71a5d4b4a37a4ca581f6cde0de167f2de23a`.

## Remaining gates

Native installment editor/navigation/confirmations/process restoration, skip/undo, actual payment/undo/currency handling, source-specific push/maintenance and complete UI remain unfinished. Card currency question remains pending. ADB empty; no Samsung/emulator/live cloud/visual verification, no production write/deploy/migration. Full APK1–4/RC goal stays active.
