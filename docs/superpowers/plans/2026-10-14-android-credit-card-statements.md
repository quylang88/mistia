# Android credit-card statement parity

Goal remains full APK1–4. Current completed slice ports the shared statement model
and fixes existing transaction/bill paid guards, verified by27 common Swift/Kotlin
vectors and full checks. No production card payment feature is complete yet.

Next slices:

1. Completed native Management card statement/history read slice (v50);
   see evidence/2026-10-14-credit-card-statement-history.md. Generated-title localization completed in v51; payment action remains unfinished.
   No device/visual proof yet.
2. Owned raw snapshot/CAS transaction+occurrence money pipeline for manual payment,
   undo, duplicate-link checks, current affordability, receipt/investment protections,
   captured calendar/clock and lossless unknown fields/Long base versions.
3. Card currency decision is pending: user was asked same-currency-only (matching
   accepted bill rule) versus manual FX with automatic same-currency-only. Swift
   currently copies raw minor values across linked wallet currencies. Do not execute
   dependent payment behavior until answered; continue independent read/model/UI work.
4. Closed statement occurrence maintenance, daily attempt throttling and due+5-day
   retry range; previous payment adoption, canonical/legacy migration and no duplicate
   ledger creation. Localized notifications/history/actions and atomic money companion.
5. Card occurrence push/dependencies, gate safety, background/foreground/preferences
   ordering (cards before bills) and full focused/Android/Swift/contracts/l10n/SQLite
   validation, evidence and separate commits per slice.

All nine write flags stay false. No production writes, deployment or schema migration.
ADB currently empty; Room/Compose compile checks are not runtime/device proof.
Independent review remains pending availability. Complete APK1–4 and visual/device
parity are still open; do not stop after the model or claim the overall goal achieved.
