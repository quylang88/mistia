# APK 2 native savings workflow

Match Swift GoalsTabContent/PlanningGoalRowView/PlanningGoalEditorSheet and
FinanceIconRegistry six goal options. Native form name/target/current/date/icon/
linked-wallet selector, exact input, immutable existing currency, owner-scoped
saved drafts/edit snapshots, unsaved-dismiss and delete confirmation, retained
failed-save draft. Preferred archived linked wallet remains visible.

- [x] RED state and summary tests: exact input/overflow, signed current, local
  date preservation, owner restoration, stale edit identity, FX/nearest summary.
- [x] Implement GREEN and native list/editor/summary with shared catalog copy.
- [x] Compile Compose workflow tests; run available device tests and visual QA
  only if ADB connected. No false emulator/Samsung claim.
- [x] Full checks/Swift comparison, evidence/progress, APK checksum and commit.

All seven cloud gates false. Family subject roles later APK3; reporting currency
currently JPY until app settings RC. Continue bills/installments after this slice.

Review fix: reporting conversion overflow previously became zero via transaction-oriented Long FX conversion. Added exact BigInteger planning conversion, final display clamping and budget/savings regressions (both observed RED). No ledger mutation FX behavior changes.

Boundary: four Compose workflow tests compile but have not executed, ADB empty. Visual/font/keyboard/Samsung verification remains pending; no independent final reviewer approval is claimed while review service is usage-limited.
