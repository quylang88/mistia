# Mistia cross-platform contracts

This directory is the compatibility boundary between the independent Swift and Android runtimes.

- `schema/cloud-entities.json` defines the 15 synchronized finance entities, wire field names, pull order and write dependency order.
- `schema/services.json` records RPC, Edge Function, Storage and deep-link contracts.
- `schema/enums.json` records stable wire enums shared by both clients.
- `golden/` contains platform-neutral serialization and business-logic vectors.
- `feature-parity.yml` is the release gate ledger.

Contract changes are append-only where possible. A backend migration must remain compatible with the last shipped iOS and Android versions and deploy before a client that consumes it. Clients must never infer permission by bypassing or relaxing RLS.
