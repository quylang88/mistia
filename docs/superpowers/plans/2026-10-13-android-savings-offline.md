# APK 2 offline savings repository

Match PlanningGoalEditor.save/deleteGoal/nextSortOrder and wallet access.
Owner-scoped typed observe/create/edit/tombstone through atomic Room+outbox.
Keep existing currency, created date, remote version, explicit wallet clears;
no implicit wallet posting. Credit-card wallets are eligible like iOS.

- [x] RED repository tests: scope, create/order, edit/clear/version, deleted/stale
  edit, invalid amount/name/wallet, archived preferred wallet, atomic failure,
  cancellation and forged payload owner.
- [x] Implement and GREEN, add Room persistence/outbox recreation test.
- [x] Run full checks, direct Swift/local review, contract/generators, update
  evidence/progress and commit; continue gated savings push then native UI.

All cloud write flags stay false. No production calls/deployments.
