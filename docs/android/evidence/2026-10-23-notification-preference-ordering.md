# Slice142 — ordered device notification preferences

Baseline adbb3525. Fixes the concrete full-Room failure recorded by slice141: after master-off, the existing store could publish enabled=true while a recreated store correctly read false. Version141; complete local slice, APK1–4/RC remains incomplete.

A private shared monitor orders reads, mutations, listener publication and the registration refresh across all stores for the device preference file. Each publication reads one preferences.all snapshot. After apply(), publication reads current storage again because synchronous main-thread listeners and StateFlow observers can perform a newer nested mutation. Publishing the outer precomputed value would overwrite that mutation. Initialization registers then refreshes under the same monitor. Default/absent-detail behavior and public APIs are unchanged; no schema, financial or copy changes.

## Observed RED → GREEN

Three real-Android regressions use real SharedPreferences through delegating ContextWrapper coordination, actual mutations, StateFlow emissions and persisted/recreated state assertions. No test-only product hooks:

- An old main listener read is held while a background master-off mutation runs. Old implementation emitted [true,false,true,false], runtime RED0.019s (/tmp/mistia142-red-native.log). Coordination releases the held reader even when the corrected writer waits for the monitor; its bounded opportunity is not a performance assertion.
- A synchronous main listener/observer turns master back off during outer master-on. The outer publication must not republish true.
- A real write immediately before listener registration must appear in the initial state.

Expanded tests all3 runtime RED0.030s (/tmp/mistia142-expanded-red-native.log), then new3+existing2 GREEN0.549s (/tmp/mistia142-first-green-native.log); database JVM331/build GREEN. Final full database native294/294 GREEN6.819s (/tmp/mistia142-full-database-native.log), including the unchanged recreation test that failed in141. Actual notification settings UI2/2 GREEN3.767s (/tmp/mistia142-settings-native.log).

## Final verification and review

Full JVM2062/197 suites with zero failures/errors/skips, Room native compile and database/settings testAPK assembly, app lint/assemble BUILD SUCCESSFUL1m35s (/tmp/mistia142-full-host.log). Swift627=4+151+472 zero failures (/tmp/mistia142-swift.log). Contracts15, both strict localization checks, outbox/notification/installment guards7/3/11, Node9/icon assets196tokens111originals and fold4/1553 checks all exit0 (/tmp/mistia142-checks.json). Database testAPK contains all6 Room schemas and MistiaSystemCategories.json. Whitespace check passes.

Direct Swift comparison: NotificationsSettingsView.swift retains device @AppStorage keys, master-off preserving detail choices and first-enable detail initialization/family-off. Android semantics remain aligned; this fix orders Android publication. No new UI presentation, no new screenshot acceptance claim.

One fresh scoped final review found no Critical/Important/Minor issue. It checked reentrant mutation, multiple store ordering, initialization registration gap, atomic field snapshots and default semantics against actual RED/GREEN evidence. Preliminary constructor read is refreshed before construction returns. Multiprocess preference synchronization is outside this in-process app; manifests contain no android:process. Root independently verified the exact expected source/doc changes. No repeated review.

## Artifact and verification boundary

API36 ARM64 emulator transport16 only, no Samsung. Main version141:20DEX/35828724bytes, SHA256 e949e8cddc166ec8ab4f8c5179748f8e18c8792f0054c46d51e3a02edfb54c76. Main/database/settings APKs archived with slice142-artifacts.json under android/build/outputs/apk2/2026-10-23, installed with install-r, all installed/archive checksums match. Main COLD Statusok1099ms is observational. Source3Androidfiles/11616bytes SHA25675b63e72f8a6f10db02fabc485dc1fd424fade0a2ff4c80224776437a2bea72f, slice142-source.patch/json against adbb3525; docs excluded.

All11cloud gatesfalse, Room6/SwiftDataV11. No live Supabase/production write/deploy/migration/push. Separate local142commit, then actual resale purchase/sale/FIFO/privateimages/atomicRPC and remaining APK1–4/RC. This does not claim full-goal completion.
