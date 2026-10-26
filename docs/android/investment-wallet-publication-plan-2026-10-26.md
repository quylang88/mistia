# Slice153 implementation plan — accepted verification

Baseline `0e7253964c05215fce08e47331ad73073a60cfa2`; design `investment-wallet-publication-design-2026-10-26.md`. Inline runtime TDD in the user's dedicated branch. Preserve accepted152/main151 artifacts. No routine approval, push or production writes.

- [x] Canonical root validator and exact source/link snapshot: UUID/type/purpose/zero opening/Long/date/null/opaque values, active writes versus readable legacy inactive roots.
- [x] Closed owner-scoped HTTPS metadata port behind global&&investment gate: create/CAS/read, explicit nullable link, bounded responses, session/caller/gate checks, cancellation and safe errors. Ordinary wallets/financial rows excluded.
- [x] Money authority: runtime RED→GREEN for derived balance exclusion on POST/PATCH and immutable opening/currency/kind/purpose/created exclusion on PATCH; validate the complete proposal before serialization.
- [x] Typed Room root/current-link source/dirty/exact queue proofs and scoped ACK/failure/receipt with rollback on insert failure, owner replacement, caller cancellation or same-owner captured-session replacement at final transaction fence.
- [x] Root coordinator direct selection beyond ordinary100due cap, exact conflict/race/retry/late-ACK guards, currency mismatch holds, readonly server metadata normalization and deliberate inactive root CAS restoration.
- [x] Root-specific bounded64 causal parent journal, actual link producer, strict wire stripping/ingress rejection and definite superseded-write receipts. Runtime server00:30/newlocal00:15, lost reply and comparedbase7→8 tests preserve newer choices.
- [x] One engine wallet entry: root → ordinary target dependency → root → deferred ordinary work. Exact opt-in current target selection and preflight/before-write source checks preserve old-wallet retry metadata while root is pending/fails. Keep all7summary counters/cancellation and independent domain gates.
- [x] Linked picker/planner target purposeNULL requirement; root readonly ACK preserves frozen consent while ordinary target/money/link/identity changes invalidate it. Real native UI/Room/HTTPS coverage including combined dependencies, due100backlog and root-dirty-during-fetch.
- [x] Direct Swift/effective SQL/diff review and independent scoped reviewer. Both reportedP2s reproduced before correction; follow-up finds no remaining introducedP1/P2.
- [x] Full2382JVM/222suites,627Swift,400Room+218Investment=618native, lint/main/native build,11scripts and whitespace. No failures/errors/skips/ignored. Initial wrong-manifest Room run retained and excluded from slice acceptance.
- [x] Main152/source/APKs archived, build/archive/installed SHA verified, cold launch1196ms observational; six EN/VI/JA light/dark font1.3/320dp focused images individually inspected. Evidence/progress/handoff updated from accepted manifests.

Commit the verified slice independently, then continue trade/cash RPC publication with coherent financial-result reconciliation and remaining APK1–4/RC. Root metadata ACK is not a financial-move ACK. All11flags remain false; no Samsung/liveSupabase/productionwrite/deploy/migration/push claim. See `evidence/2026-10-26-investment-wallet-publication.md` for runtime RED/GREEN, review corrections, exact hashes and limits.
