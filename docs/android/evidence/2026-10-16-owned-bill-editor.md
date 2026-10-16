# Owned bill editor and current primary — 2026-10-16

Branch `codex/android-apk2-4-parity`; baseline `19612b02`; app98. Plan `../owned-bill-editor-plan-2026-10-16.md`.

PlanningScreen forwards normalized primary for new bills. Existing record currency wins; same-currency payment wallet filtering remains unchanged. Foreign supplied bill is hidden. Owner/record/currency keys scope all draft/dialog/busy/error state; scoped saver wraps existing18slot format, checks outer/inner identity/code and safely validates date/day ranges/frequency>=1 while preserving legacy24. Pre/post active-job checks cover save and shared pause/resume/archive completion. No financial repository/schema/network/Swift runtime change; these are UI guards, not repository opening-baseline/read-set guarantees.

Direct Swift PlanningEditors.swift1080–1118 filters eligible wallet currency and chooses stored plan/due-item currency before AppStorage primary. Existing Android ISO presentation/minor parsing for importedUSD is preserved; full imported currency normalization/formatting parity remains an explicit separate audit gap.

TDD: all4 new scoped-saver cases produced actual runtime REDs before guards. Focused **20 JVM cases pass** (4new+16existing), covering exact money, owner/record/currency envelopes, corrupted inner payload, malformed dates/day/frequency and legacy24. Native8 **6 actual intended REDs**, then **8/8 pass30.718sec**. ExistingJPY/importedUSD cases already passed; no compile/selector error counted as RED.

Real PlanningScreen fixture stores a real owner-scoped rent system-key category (raw record and matching queued payload) and JPY/VND/USD wallets in in-memory Room. NewVND bill saves exact9007199254740993 with identical outbox payload and only VND wallet offered. ExistingJPY exact identity/amount/wallet survives primary change; importedUSD13.75→14.25 stores1425minor with itsUSDwallet. Foreign owned bill remains unchanged with no editor exposed. Record switch closes old wallet picker; create primary switch removes calculator/private amount/name. Save and pause tests commit only captured old owner before holding NonCancellable response; replacement owner's editor remains enabled and cannot be dismissed by old completion. Finally releases fixture work even on RED assertions.

Supplemental visual **1/1 passes8.841sec**, with settled compositor capture (no fixed sleep/animation override), all4 light/dark130% PNGs inspected. Full exact amount andVND suffix readable; dark form shows selectedCashVND, both calculators show the full number without transition ghosting. Light image intentionally shows numeric IME, lower controls scroll. No full authenticated/system-chrome/Samsung UI claim. Independent read-only review reports no findings.

Full **1465 JVM/138suites**, Swift610(4contract+137data+469core), lint/build16sec, Room/management/planning/transaction/settings AndroidTest compile, Room/planning package, contract15, both localization checks, SQLite7/3/11, packaged Room6schemas/bootstrap, whitespace pass. Final **73/73 native planning passes377.191sec** on the checksum-matched executed artifact.

Logs `/tmp/mistia-owned-bill-{state-red,native-red-build,native-red,focused-build,native-focused,visual-build,visual,full,swift,native-final}.log`.

Metadata/manifest/DEX-verified archives `android/build/outputs/apk2/2026-10-16/`:

- `mistia-0.2.0-apk2-owned-bill-v98.apk`, versionCode98, SHA256 `f4097b2b502979c0298adde426a870055d74bdd0f23277967b7d8fa51418e649`.
- `mistia-owned-bill-test-v98.apk`, target36, SHA256 `dc879b97558c6bbad2b19918ca01fe90ec4ede7cca3e5be9af167f72265b4031`.

API36 only; app98 installed with install-r preserving data; cold MainActivity start Statusok1605ms, installed versionCode98 confirmed. No Samsung/live Supabase/production write/deploy/migration. All10 flagsfalse; Room6/SwiftDataV11/iOS751 unchanged. Generic bill/savings opening-baseline/read-set guards, remaining installment/budget primary consumers, due/overview/family/investment, imported/no-wallet cases, prior native startup/open/save concerns and full APK1–4/RC remain open. Goal active; continue installment primary/scoped creation next.
