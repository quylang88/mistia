# Live source-wallet validation during card save — 2026-10-15

Branch `codex/android-apk2-4-parity`; baseline `527bca4e`; APK86.

Both Room credit-card create/edit transactions now re-read the selected payment-source wallet before any wallet/profile/outbox writes. A selected source must have a canonical non-self UUID, matching owner/raw identity, live row, explicit literal false archive flag and known non-card kind. Missing/deleted/archived/foreign/malformed/unsupported sources abort the whole save. Clearing selection is allowed. Valid source metadata/version changes remain allowed and its record/queue are never rewritten.

This closes the gap between earlier `CreditCardDraft.toMutation` validation and the actual commit, without a source snapshot CAS or currency-policy change. Actual Swift comparison: `ManagementEditors.swift`379 passes owner/preferred/excluded-self/excludesCreditCards through wallet picker access; the existing Android draft checks equivalent source eligibility before Room. Missing/malformed archive flag deliberately holds safely; no legacy auto-repair claim. This is metadata-link validation, not payment or funds reservation. Pending card-statement payment currency policy remains unresolved.

Runtime TDD:9 new actual Room cases first produce7 intended failures for create. After wiring the helper to create only, those same7 fail explicitly at `edit=true`; helper then added to edit transaction. Modes: archived/deleted/missing/foreign payload owner/card kind/unknown kind/stringfalse archive. Both paths assert complete before/after wallet/profile rows and queues. Happy cases preserve >2^53 source version/queue through valid metadata changes and permit clearing a previously selected source after archive. Final full Room **164/164 pass in2.892seconds**.

Full **1412 JVM/134suites**, zero failures/errors; Swift610 (4+137+469), app lint/build, database/management/planning AndroidTest compile, database/management test APK assembly, contract15, both localization checks, SQLite7/3/11, packaged Room schemas1–6/bootstrap and whitespace pass. Full native management **23/23 pass in82.516seconds** on the final guard artifact.

Independent reviewer `review_card_source86` checked helper placement in both transactions, raw scope/liveness, eligibility semantics, no source rewriting, both runtime RED phases and before/after assertions: no Critical/Important/Minor finding.

Logs `/tmp/mistia-card-source-{red-build,native-red,create-green-build,edit-native-red,full,swift,database-final,management-final}.log`.

App `android/build/outputs/apk2/2026-10-15/mistia-0.2.0-apk2-card-source-guard-v86.apk`, versionCode86, SHA256 `39d10dd00d62f6cc639c45e2ad06b14b350e6956049e8b1f7be3ae1b6f30fede`.
Executed Room test APK `android/build/outputs/apk2/2026-10-15/mistia-room-card-source-guard-test-v86.apk`, SHA256 `41c2203f8f27757d03a9ed9e2544c7f5c680b0f4ec3fe3ccda1ab4b70cef5e4e`.
Executed management test APK `android/build/outputs/apk2/2026-10-15/mistia-management-card-source-guard-test-v86.apk`, SHA256 `f660befc9618580f97942ca602224cf7a578853f25555e6088b1c501020c7cc4`. Metadata/manifest/version/DEX verified.

Only API36 emulator connected. App build86 not manually installed; latest update/cold-launch smoke85. No Samsung/full visual/process-kill/live sync verification. APK84 intermittent startup row-delivery concern remains unproven. All10 cloud flagsfalse; no production writes/deploy/migration. Editor-open baseline tokens, statement payment/currency choice, imported currency audit, other monetary forms, remaining APK1–4 and RC gates stay open. Goal stays active; continue next slice.
