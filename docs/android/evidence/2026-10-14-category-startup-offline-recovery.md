# Category startup and offline recovery — 2026-10-14

Signed-in sync now creates missing default categories locally after a complete
pull and category maintenance. AppModule supplies the existing insert-only
FinanceRepository bootstrap, shared registry, secure device ID and current UTC.
Retryable sync/auth-refresh failure uses the still-signed-in starting owner's
cache to create missing defaults while preserving the original network failure.
Permanent malformed input and cancellation do not trigger fallback. Successful
bootstrap executes once per sync call, including when later push summaries report
retry. Existing archived/deleted/favorite/custom metadata remains untouched by
the insert-only repository; cloud write gates remain false.

Completed raw pulls now also reconcile an unobserved owner-cloud base0 offline
seed using the existing exact atomic seed migration: untouched tombstones win,
explicit local edits merge against registry defaults, real target base/provenance
and ordered legacy cleanup persist. Other group pending edits/tasks defer. This
is local reconciliation without cloud writes even when all gates are disabled.

Owner is checked before and after each table fetch and before maintenance/default
creation. A changed/signed-out account cancels work. A runtime regression showed
late pull replies could restore rows after signout; the post-fetch guard now
rejects the reply before replacing local data.

Verification:

- Seed runtime2 REDs -> GREEN; edited/untouched/tombstone/future-alias coverage.
- Startup runtime2 REDs -> GREEN; complete pull then maintenance then defaults,
  retryable offline fallback, cancellation/permanent refusal.
- Auth refresh/account runtime2 REDs -> GREEN; cached signed-in owner only.
- Late pull runtime1 RED -> GREEN; no snapshot writes after signout.
- Full Android747 JVM/80 suites,0 failures/errors; Room/planning AndroidTest
  compilation, lintDebug and assembleDebug pass (724 tasks).
- Swift SystemCategory23 tests, contracts15, localization checks, actual SQLite7
  methods and git diff --check pass. ADB empty; no Android runtime or live cloud.
- Independent reviewer could not run due account usage limit. This slice has
  self-review and automated checks; independent review remains outstanding.
- Room schema4; nine cloud gatesfalse. Full APK1–4 parity remains incomplete.

Direct Swift comparison: MistiaBootstrap.seedDefaultCategoriesIfNeeded creates
missing roots before leaves and repairs duplicate references; Android mirrors
that ordering through maintenance+insert-only bootstrap, retaining authoritative
raw tombstones and user metadata rather than fabricating a remote ACK.

APK: `android/build/outputs/apk2/2026-10-14/mistia-0.2.0-apk2-category-startup-v31.apk` (vn.com.quyln.mistia.debug, versionCode31).
SHA256: `2f79066a6f90fa460e01534dfa6c9af402bc76c2c84f3079288480d2c8f92226`.

Next: complete independent review when available, then recurring bill due-cycle
maintenance/auto-pay/notifications and remaining native APK1–4 parity.
