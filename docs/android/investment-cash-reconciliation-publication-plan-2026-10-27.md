# Slice159: manual cash reconciliation publication

Baseline `1a1b44213272dbedd55c868c8578f04474269c36`; branch `codex/android-apk2-4-parity`. Full APK1–4/RC goal remains active.

Publish the existing confirmed, immutable manual reconciliation: one real ledger transfer and its two canonical booked-profit postings. Real cash80 may move only booked profit50. Same currency is mandatory. Compare actual Swift persistence and effective SQL directly.

1. Runtime model RED→GREEN: strict canonical group, complete owner/result proof, exact business and version preservation, orphan queue recovery, malformed/foreign/private rejection. No ledger-only financial ACK.
2. Closed HTTPS ledger insert/read and compared batch publication. Exact owner/session/caller/gate fencing including HTTP errors, bounded terminal-empty keyset reads, force=false and complete Int64 expected map. Lost replies recover through owned reads; different immutable intent stays conflicted.
3. Typed Room atomic whole-generation ACK/failure and coordinator; preserve newer edits, unrelated queues and future backoff. Compose one investment engine entry after cash publication. Check linked-wallet changes against effective SQL before claiming completion.
4. Actual repository+Room+TLS native integration, inline Swift/SQL/diff review, appropriate full host/Swift/contracts/native checks, APK checksum/certificate inspection, precise evidence, independent commit immediately.

No production write/deploy/push; all eleven flags remain false. Existing account/OAuth/currency decisions remain binding. Ordinary editable transaction/bill/installment investment-fund consumption follows as a separate complete domain; this slice does not claim all allocation publication.

Completed2026-10-28: runtime RED→GREEN/model/network/Room/integration and both inline review regressions; full2646JVM/627Swift/783native,376SQL+3races/80freshreset, all host scripts/lint/build pass. Exact source/APK/native history and limits are in the evidence document. No client writes or production changes. Full goal continues after independent159commit.
