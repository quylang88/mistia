# System category identity selection / lossless reference repair — 2026-10-14

Base: `f8f84ad`. Pure component prerequisite; Room/push/startup wiring is still pending.

Swift source compared: `MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories` and `remoteCategoryPriority`, plus category/ledger/budget/bill replacingCategoryReferences helpers. Selection filters active value candidates first, then applies whole timestamp seconds +1000 for actual owner-cloud ID. Identity is an existing owner-cloud row when present, otherwise the real value winner. Identity, values and every candidate remain separate: no fabricated remote row, false version, discarded duplicate or different-ID ACK is produced.

Owner/entity/key/system/version/deletion metadata is validated. Mixed viewer envelopes, duplicated remote IDs and malformed metadata fail closed. A live value row does not erase the truthful tombstone on the identity row; resurrection/merge must be handled by the upcoming conditioned transaction/outbox path.

The pure FK repair accepts only owned category parent or ledger/budget/bill category_id references. It preserves all other JSON, including >2^53 amounts, explicit nulls, nested future fields, frozen budget display/identity snapshots and current user audit fields. Current pending payload/owner/identity must match; pending kind/base version remain exact. A previously synced record gets a matching mutation. Deleted state remains unchanged, and clock metadata cannot regress. Contradictory envelope/payload clock, deletion or version metadata is rejected before repair.

Verification:

- Initial runtime RED10/10 at explicit unavailable functions, then GREEN.
- Remote and reference metadata regressions each runtime RED, then GREEN.
-12 new model tests; full Android642 JVM tests /77 suites zero failures; Room/planning test compilation, lint/assemble pass (724 tasks, final36s).
- Swift SystemCategory filter23 tests pass (17 data support +6 core).
- Contract15, Android/strict Swift localization and diff checks pass.
- Independent static component review: no actionable P1/P2. No Room or coordinator integration is claimed by that review.
- ADB empty; no emulator/Samsung/live cloud action. Existing nine write gates stayfalse. Native APK v21 artifact remains the preceding UI checkpoint; this pure component does not introduce a new install artifact.

Logs: `/tmp/mistia-category-reconcile-model-red.log`, `/tmp/mistia-category-reconcile-metadata-red.log`, `/tmp/mistia-category-reconcile-reference-red.log`, `/tmp/mistia-category-reconcile-model-final.log`, `/tmp/mistia-category-reconcile-swift.log`.

Next: fix transaction tombstone push needed by bill undo, then atomic category identity/reference/outbox/translation reconciliation and create/409 integration. Startup remains disabled until those are verified. Full APK1–4 remains incomplete.
