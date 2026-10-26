# Investment asset causal publication, slice152

Baseline: `53556917` (slice151), branch `codex/android-apk2-4-parity`.

The TXT requires that late responses never erase newer local work. Real Room/files/HTTPS tests reproduced three failures: an older asset RPC commits at server00:30 while a rename or new photo is saved at local00:15. Its late ACK leaves the new queue intact, but the next timestamp-first conflict decision imports the old server row. A lost RPC reply has the same problem.

Store bounded local causal evidence in the same asset/outbox payload produced by the existing mutation planner. Each of up to64 distinct parents records exact Long base, source device, deleted state, and business SHA256 with and without image. Normalize archived instants and exclude metadata and both owned private keys. This is evidence for conflict ordering only; it grants no image upload, read, ACK or deletion authority. Existing Room/cache reference proof remains authoritative for photos. Unchanged business probes do not append evidence. Malformed/unknown/foreign evidence is held.

The asset coordinator recognizes an exact same-device parent at base+1 despite the server timestamp. CAS still compares the fetched server version; no forced writes. Other-device conflicts keep the shared policy. An unproven same-device server winner with different semantics is retained as an explicit conflict, preventing silent loss. The shared resolver remains unchanged; the optional coordinator hook defaults to its old behavior for every other domain.

When a definite superseded RPC succeeded against a higher compared server base, typed Room receipt recording atomically appends its exact returned fingerprint/version to the newer coherent row and queue. It requires the original local parent, same owner/id/device/local base/created identity, exact sent/result semantics and expected+1 server version. It preserves business values, dirty state, received-at and every queue stamp, with captured-caller/current-owner checks before and after both writes. A lost reply cannot establish a definite version-gap receipt; ambiguous gaps remain pending/conflicted rather than guessing.

Both private keys are stripped by assetPayloadForCloud and refused at dedicated/generic remote ingress. No schema, SQL, auth, currency rule, gate or financial domain is widened. All11cloud flags remain false. Direct Swift/SQL review confirms server clock and expected-version behavior; this Android correction does not claim an iOS runtime fix.

Root-wallet prerequisite work is preserved separately with hashes in `/tmp/mistia-root-publication-wip-preserved/manifest.json`. Restore only after this slice's independent commit, then continue canonical root/trade/cash and the full APK1–4/RC objective.
