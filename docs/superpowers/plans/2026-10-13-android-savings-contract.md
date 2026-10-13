# APK 2 savings goal typed contract

Inline implementation authorized by original TXT. Next bounded slice after budget.

Match RemoteSavingsGoal fields and Swift goalRows/monthsRemaining sorting.
Use exact Long wire values, explicit nullable wallet/device/deletion fields,
strict UUID/UTC decoding and BigInteger monthly ceiling/progress comparisons.
Owner/archive/deletion filters belong to projection; no cloud mutation in this slice.

- [x] RED typed payload tests: round trip, explicit nulls, signed Long boundaries,
  required/type/identity/time rejection, preservation of optional strings.
- [x] RED projection tests: inclusive month count, Tokyo boundary, exact ceiling,
  completed/negative balance, ratio/date/name ordering, scope/archive/tombstones.
- [x] Implement minimal model/projection and GREEN.
- [x] Full Android checks, Swift planning comparison/tests, contract/generators,
  local review, evidence/progress and commit; then offline repository.

Later slices: Room/outbox save/delete and linked-wallet owner access; separately
disabled savings push; native editor/icons/date/wallet selector and rows.
