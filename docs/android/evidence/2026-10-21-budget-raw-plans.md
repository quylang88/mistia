# Raw budget-plan availability and stored editor identity — slice120

Started2026-10-20, final validation2026-10-21. Branch `codex/android-apk2-4-parity`, base `bc8ce5fa`. Full APK1–4/RC goal remains active.

## Behavior

Unreadable owned current/past plan money, month or eligibility can no longer disappear into a zero/partial budget or revive an older healthy continuity plan. While the raw template stream has not emitted, or a potentially active template cannot be read, the whole budget summary is unavailable and the branch list is withheld. The existing generic amount hint remains, with no false “no budgets” message. Repair restores the exact projection without a read writing records/outbox. Proved archived/deleted/foreign/future templates remain neutral. Nonpositive saved limits and plans with no resolvable branch cannot publish a healthy/empty budget; Swift PlanningEditors325 and Android BudgetMutations58 already require a positive saved limit.

`observeBudgetReadRows` supplies an owner/identity-scoped unparsed stream in the production repository, retaining unreadable body deletion instead of filtering it out before the consumer can assess availability. Existing strict persistence/editor parsers remain unchanged. The interface default derives rows from typed plans for existing implementations; the production override and real Room tests prove that the actual app retains malformed raw templates. There is no unfiltered UI-to-DAO access or mutation API.

Editing reloads the exact strict raw record behind the displayed id. A delayed independent typed editor stream cannot turn an existing-row tap into Create or inject a default amount. Owner/body-id checks, actual stored currency/amount/metadata and positive/readable eligibility are retained. The editor still saves through the normal repository path. Foreign rows are excluded before duplicate-id reduction, so they cannot hide an owned template.

This is a conservative whole-plan availability guard. It does not certify independent usable fields of otherwise unreadable templates, raw ledger/wallet/category completeness, all continuity/import/name normalization, read-set atomicity, family budgets, or Savings/Due availability. These remain required work; this slice is not a financial-domain or APK gate completion claim.

## TDD and review evidence

- Initial eight adapter tests: six actual business failures in1s; valid exact/exclusion controls passed. Old intake produced0 or resurrected500 instead of unavailable.
- Raw production repository case: one runtime failure (expected original malformed row, actual empty), command9s including native packaging. No compiler failure counted as RED.
- Actual Room PlanningScreen: three intended money/availability failures in19.583s before wiring the new read path. Initial minimal guard: JVM8 +repository28 GREEN, native3 GREEN5.318s.
- Parent review reproduced missing branch, nonpositive limits and foreign-duplicate hiding: three of11 JVM cases failed in2s. The delayed typed-stream editor route also reproduced a blank create form instead of the stored1,000 amount. Native6 had three intended failures in20.164s while original three passed.
- Guard/identity/editor fixes: focused build GREEN3s. Final new native **6/6 GREEN9.826s**; new unit suite12 cases passes, including strict original reload and wrong owner/id rejection. Final focused budget exact/raw, currency, workflow, owned editor and calculator **42/42 GREEN166.223s**, with read-only record/outbox comparisons.

Parent direct review covered the complete immutable Android source/test patch SHA256 `6f494e173666eca6c4020882be6c8cc7a6489c86cd0e078e7a397984137e71f5`, Swift PlanningEditors300–340/PlanningLogic1044–1080 and119's branch/pace behavior. Invalid JSON templates cannot exist as typed SwiftData snapshots; the conservative Android availability state protects financial accuracy rather than imitating a silent parser omission. Swift currency normalization174 also only supportsJPY/VND; no full-ISO continuity parity is claimed. No iOS runtime change or independent whole-branch approval claimed.

Superpowers became available again during continuation: current using-superpowers/executing-plans/TDD/systematic-debugging/verification guidance read, plan ledger/task brief adopted without repeating already-proven RED steps. Work remains on the user's established feature branch/current repository; no additional worktree/branch or permission pause introduced. Whole-branch fresh review remains at the end of the full scope, with per-slice direct review retained.

## Final verification and artifacts

Full Android command exited0/BUILD SUCCESSFUL144s: **1673 JVM tests /160 suites, zero failures/errors/skips**, Room and relevant feature AndroidTest compile/package, lint and main assembly. Swift **610** (4contracts/137data/469core) passed; contract15entities, both strict localization generators, SQLite7/3/11, Room6schema assets and whitespace passed. No production/test code changes followed these checks.

Existing exact/unavailable money/font fixtures ran through the new pipeline; all12 final en/vi/ja light/dark actual130% PNGs were refreshed and inspected, with complete glyph assertions. These verify financial content in real Room PlanningScreen fixtures, not full MainActivity/system-inset/header positioning. The six new raw-plan business tests are distinct from those existing localized image fixtures; no new all-scenario visual claim is made.

Main120 install-r preserves data; cold `Status: ok`,1017ms; version120/min26/target36 confirmed. Main20DEX/planning-test9DEX, manifests/output metadata checked. Both installed base.apk SHA256 values match archives under ignored `android/build/outputs/apk2/2026-10-21/`.

|Artifact|SHA256|
|---|---|
|mistia-0.2.0-apk2-budget-raw-plans-v120.apk|1d13f03ec9d04df92f0382fc523a224b2758b455d4895a71f02df8bddfac62dc|
|mistia-budget-raw-plans-test-v120.apk|a3862322a16e2c678953aa9b029d86c877f3c5c73c3270282a6c101793dcb4f3|

All10writeflagsfalse; Room6/SwiftDataV11/iOS751 unchanged. API36ARM64 emulatortransport13 only. After the overnight interruption ADB had no device and no qemu process existed; the existing AVD was restarted without wiping data, boot/API verified before testing. The earlier transport12 no-device invocation did not run tests. No Samsung/live Supabase/production write/deploy/migration verification. Logs `/tmp/mistia-budget-raw-plans-*` preserve baseline/review RED, all GREEN commands, interruption/boot, installed/cold/checksum evidence.

Next: retain truthful budget spending from raw ledger/source-wallet/category dependencies and reduce unnecessary template holds; complete actual Overview budget/due/config sections and the remaining family/investment/receipt/device/visual/RC work. User same-currency budget/bill/installment rules remain binding. Full goal stays active.
