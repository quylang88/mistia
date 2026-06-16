# Event and Settlement UI Refinements Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Fix the UI layout of ongoing events in Overview, refine the event cost calculator to default to empty amounts and enforce complete inputs before calculation/saving, prevent the event editor from auto-adding blank participant rows during edits, and prevent empty expense drafts from showing as ghost rows.

---

### Task 1: Overview Layout Alignment & Participant Count
Adjust the layout of ongoing events in the Overview section to center the icon and the amount + chevron vertically, move the bill count to the bottom under the name/participants, and include the participant count format (`N người: A, B, C`).

**Files:**
- Modify: `Mistia/Features/Overview/OverviewView.swift:2057-2133`

### Task 2: Default Event Split Input to Null/Placeholder & Require Complete Inputs
Update the split calculator sheet so participant paid amounts default to empty (`""` rather than `"0"`), showing the placeholder. Disable calculations and the checkmark save button until all participants have non-empty amounts entered.

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:1887-1965` (add `allInputsProvided`, guard `suggestionsForSelf`)
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:2018-2065` (disabled state and UI check for `allInputsProvided`)
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:2123-2134` (update defaults to `""`)

### Task 3: Prevent Auto-Appending Participant Row on Edit
In `SettlementEditorSheet` for event editing, remove the logic that automatically appends an empty row to the list of participants upon loading the draft.

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:994-1015`

### Task 4: Remove Abnormal Ghost Expense Rows
Filter out incomplete expense drafts (`hasContent == false`) from the `draftBillsContent` view in `SettlementEditorSheet` so they do not show up as ghost rows before/during sheet presentation.

**Files:**
- Modify: `Mistia/Features/Transactions/SettlementSheets.swift:766-855`

---

## Verification Plan

### Automated Tests
- Run settlement logic tests:
  `swift test --filter SettlementLogicTests`

### Manual Verification
1. Verify the layout of ongoing events in the overview section. Check alignment of icons, name, participants, bill count, amount, and the chevron.
2. Open the event cost split modal, ensure the input fields show the placeholder and start empty. Verify that calculations do not show, and saving is disabled until all inputs are entered.
3. Open the edit event modal, check that no empty participant row is appended to existing participants.
4. Try adding an expense to the event, ensure no ghost row pops up on the underlying screen before the expense modal shows.
