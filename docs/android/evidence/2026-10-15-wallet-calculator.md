# Native owned wallet opening-balance calculator — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `935eea8c`.

New-wallet JPY/VND opening balance now opens the shared native calculator, matching the actual Swift new-wallet currency input action. OK updates only the draft and resets validation; explicit Save persists the wallet. Cancel preserves signed initial text. Existing opening balance remains metadata-read-only and has no calculator; imported fractional currencies retain existing semantics without this integer-only tool.

WalletEditorSheet now takes explicit ownerId from ManagementScreen, rejects foreign supplied wallets, keys its full subtree by owner/record, and saves an owner envelope around the existing draft saver. Malformed/foreign saved payloads safely fall back to a fresh draft. Calculator expression scope includes owner/record/currency. MainActivity already keys the signed-in root by owner; these changes add component-level ownership and direct fixture coverage, not a claim of an observed production account leak.

Runtime TDD:2 new state cases fail for foreign/malformed restore, then all14 state cases pass. Four native cases initially fail for missing calculator/foreign-wallet visibility; after wiring, a fifth actual runtime case proves that a late NonCancellable save can close a new owner's editor without a post-callback cancellation check. Added current-job checks before save/archive response handling. Final full management **11/11 actual API36 cases pass in31.407seconds**, including exact >2^53 VND create/outbox/no ledger, signed Cancel/divide-zero rejection, exact saved expression restore/owner reset, immutable existing opening balance/foreign-wallet hiding, and late response leaving the new owner's unsaved draft visible. Original authorized save belongs only to its captured old owner; no new-owner wallet is written.

Full **1396 JVM /133 suites**, zero failures/errors; Swift610 including86 shared calculator vectors, app lint/build, database/management/planning AndroidTest compile, database/management test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged schemas1–6/bootstrap and whitespace pass. Direct self review compared Swift new-wallet input, shared calculator semantics, Android owner routing/saver and cancellation lifecycle. Shared light/dark-font130 calculator screenshots were inspected in APK75; no separate wallet screenshot/full visual/Samsung/process-kill/live-sync proof. Independent review remains pending.

Logs `/tmp/mistia-wallet-calculator-{owner-red,red-build,native-red,focused,late-red-build,late-red,full,swift,native-green}.log`.

APK `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-wallet-calculator-v80.apk`, debug versionCode80: SHA256 `3a7a44a3212f55966173961e45980f62b7451e2bb43a23497541c3a3f81494ad`.

Executed management test APK `android/build/outputs/apk2/2026-10-15/mistia-management-wallet-calculator-test-v80.apk`: SHA256 `27f08f9f5304b2c23faa97bf72617a83a4bbf45ebfcdd682c8c2dbd8b9b4ee2e`. Manifest/version/DEX verified.

Only API36 emulator connected; all10 flagsfalse; no Samsung/live Supabase writes/deploy/migration. Existing-wallet current-balance/adjustment, card/transaction monetary forms/settings/imported-currency audit, coupled payment cloud writes/recovery/fund usage/maintenance, pending card policy, APK3/4/RC and device gates remain open. Goal stays active.
