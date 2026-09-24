# APK 1 local closure audit — 2026-09-25

APK 1 is locally implemented and build-verified. Its release-contract status is
`build_verified_device_pending`, not device-verified. This audit changes no
runtime behavior, cloud-write flag, schema or production service.

## Scope matrix

| Domain | Local implementation evidence | Boundary |
| --- | --- | --- |
| Wallets | Native create/edit/archive, owner-scoped atomic Room plus outbox, ordered gated push | Live writes and current-device UI verification remain disabled/pending |
| Credit cards | Linked profile create/edit, limit/closing-day rules, paid-cycle protection, ordered gated push | Statement/payment workflows belong to APK 2 |
| Categories | Native hierarchy editor, translation parity, parent-before-child offline/push ordering | Live writes and current-device UI verification remain disabled/pending |
| Transactions/transfers | Expense, income, internal transfer, receipt Lend, current-balance/card-credit guards, paid-statement locks, atomic Room/outbox and gated push | Family transfer, collect/repay/borrow and settlement belong to APK 3 |
| Multi-currency | Exact decimal manual/app rates, JPY/VND snapshot cache, inverse conversion and minor-unit rounding | No production dependency was changed |
| Receipt AI | Photo Picker, CameraX, bounded preprocessing, typed authenticated client, review corrections, quantity/groups, Expense/Lend editor routing, local image persistence/preview/removal | No live Gemini run or current Android-device verification is claimed |

The mapping was checked against `contracts/feature-parity.yml`, current Android
source/tests, the iOS transaction and AI-bill reference paths, and the APK 1
evidence sequence in `docs/android/evidence/`. The deferred capabilities map to
the published later-gate boundaries rather than missing APK 1 work:

- APK 2: budgets, savings, recurring bills, installments, card statements,
  due maintenance and local notifications.
- APK 3: family roles/invites, family transfers, shared expense, settlement and
  inbox.
- APK 4: resale inventory, unit-aware FIFO, cash posting, product images and
  atomic investment RPCs.

## Verification reused from the final APK 1 code slice

- Full Android gate passed in 1 minute 1 second: 311 JVM tests across 50 suites,
  Room Android-test source compilation, Android lint and debug APK assembly.
- The 15-entity Android contract check, Android localization generation check,
  strict iOS localization codegen check and `git diff --check` passed.
- Debug APK SHA-256:
  `597dcd90901017b82c218981188250622f4eea6a2300f70cbd07a10a3e73ddf6`;
  653 files.
- Generated debug `BuildConfig` had category, wallet, credit-card, transaction
  and global cloud-write flags all set to `false`.
- Independent review of the final receipt allocation/completion path reported
  no Critical, Important or Minor finding.

## Accurate boundary

`adb` is unavailable and no Samsung/emulator run was performed for the final
artifact. The user explicitly directed continued work without Samsung, so this
does not block starting APK 2, but physical UI, dark-mode, camera/picker, live
receipt analysis and gated cloud-write behavior are not claimed as verified.
The known full localization-audit limitation also remains: Xcode licensing is
not accepted and Command Line Tools do not include `xcstringstool`; the three
direct contract/codegen checks above are the checks that passed.
