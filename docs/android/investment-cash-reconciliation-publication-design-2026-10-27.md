# Manual investment cash reconciliation publication

Baseline `1a1b44213272dbedd55c868c8578f04474269c36`, slice159. This is the existing explicit real-transfer confirmation from the Android reconciliation sheet. The event is immutable; a different business event requires a new identity. Ordinary editable fund consumption and linked-wallet-move events remain separate publication work.

## Financial identity and amount

Swift `InvestmentPersistence.swift` creates role `investmentReconciliation`, ledger `investmentLedgerIdentity(event,"cash-reconciliation")`, holder posting `holder-cash-posting` and destination posting `linked-cash-posting`. Both postings are manual booked `cashReconciliation`, with no trade/asset refs. A real80 transfer may carry only booked profit50: ledger source/destination/reporting amounts stay80 while the postings are−50/+50. All local/accounting/ledger/wallet currency codes must match. Android uses the same identities and quantities; no FX or minor-unit reinterpretation.

## Staged remote publication and atomic local result

Swift creates the reconciliation ledger through its ordinary create-row path and writes allocation postings separately. Android prepares that same immutable real ledger through a closed insert-only HTTPS method, then calls the compared three-argument `mutate_investment_cash_postings` overload with a complete exact per-posting version map and force=false. It never merge-upserts the real transfer or converts a missing previously observed ledger into a new transfer.

A prepared ledger is not a financial ACK. The publisher reads the complete owner-scoped event, including a terminal empty keyset posting page. Only a canonical, same-business, non-regressed full ledger/pair proof can import all three records and clear their exact relevant queues in one Room transaction. Clean-ledger/partial-posting legacy recovery remains possible. Different immutable intent, unknown IDs, foreign/private/tombstone results and missing observed identities are held. Whole four-entity generation equality plus exact original queues, owner, caller and captured-session fences protect newer work and unrelated queues. Final session revocation rolls back ACK/failure bookkeeping; local database IO propagates.

## Historical destination and compatibility

Runtime pgTAP reproduced a current-link constraint in the compared batch: changing or clearing the link after real-transfer confirmation stranded the allocation. Migration80 recognizes only an owned canonical historical ledger, locks it for share, validates its posted/live internal-transfer shape and active same-currency ordinary wallets and the immutable accounting currency of the canonical root, verifies both canonical postings bind that exact ledger/destination and have matching signed amounts/dates/manual origin without trade or asset refs. The existing capacity checks and owner advisory lock remain. Noncanonical legacy events retain current-link behavior. Hardened single-posting and old two-argument bulk bodies are unchanged.

The real ledger and posting batch are two remote transactions, as in the Swift flow; durable local queues recover an intermediate prepared ledger after a lost response. No claim of a single three-row server transaction is made. The local financial result acknowledgement is atomic.

## Engine and authorization

One engine entry runs channel→asset→trade→cash→reconciliation→asset→channel, retaining all seven counters and avoiding entity de-duplication. All due event queues are selected from the whole source, including after more than100 ordinary transactions. Clean historical groups are scanned once with that source; only actual dirty posting or referenced ledger keys trigger another generation read, preserving ledger-only recovery. Future backoff and dirty wallet/trade prerequisites defer before HTTP. Reads and writes fence owner/session/caller; writes additionally fence the existing global and investment gates, including failed HTTP responses. Closed SQL comparison/capacity messages become redacted retry codes; arbitrary diagnostics are discarded. No new write flag is enabled. All eleven write flags stay false; the new migration must be deployed through the separately authorized production process before enabling the client.

## Validation limits

Runtime model/network/Room/actual repository+Room+TLS tests and local pgTAP/race tests are recorded separately from final full checks in the slice evidence. MockWebServer fixtures exercise protocol, lifecycle and local state; effective local SQL remains the financial server oracle. No Samsung, live Supabase or production write/deploy/push is claimed. APK1–4/RC remains active.
