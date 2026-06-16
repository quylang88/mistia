# Settlement Debt Row Edit Design

## Goal

Remove manual participant-share editing from the `Chia chi phí` section and
allow users to edit the automatically generated borrow/lend amount directly on
each debt row.

## Chosen Approach

Keep the automatic split result as the source of reporting and calculation
truth. Store manual overrides only for the debt suggestions shown to the
current user.

Alternatives considered:

- Save each edited debt transaction immediately. This can leave the event
  partially saved when the user edits several rows and dismisses the modal.
- Recalculate participant shares from edited debt amounts. This would change
  expense reporting and contradict the requirement that debt editing must not
  change reported expenses.

Debt-row overrides preserve the existing calculation while keeping edits
explicit and local to the final settlement records.

## Removed Share Editing

- Remove participant share edit rows from the `Chia chi phí` section.
- Remove the participant-share pencil/checkmark controls.
- Remove committed share overrides, share draft state, share adjustment badges,
  and the total-share difference row.
- Remove the independent manual-share overlay from the modal's participant
  inputs.
- Keep automatic equal-share calculation unchanged for reporting and for
  generating the initial debt suggestions.
- Remove localization keys that exist only for participant-share editing and
  total-share differences.

## Debt Row Layout

- Continue generating borrow/lend rows automatically from the split result.
- Keep each row's finance icon, participant name, debt direction subtitle, and
  signed amount.
- Place the existing small circular `pencil` icon button beside the amount.
- The button uses the same visual treatment as Mistia's calculator button.
- Only rows involving the current user remain visible.

## Editing Interaction

- Tapping `pencil` changes that row's amount into a currency input and changes
  the icon to `checkmark`.
- The input receives focus, selects the entire existing amount, and opens the
  numeric keyboard automatically.
- Only one debt row can be edited at a time.
- Other debt-row edit buttons and settlement actions are disabled while an edit
  is active.
- Tapping `checkmark` commits the draft and returns the row to display mode.
- The edited amount must be greater than zero.
- Zero or empty input remains in edit mode and shows a validation alert.
- The debt direction cannot be changed. A receivable remains a receivable and a
  payable remains a payable.

## Calculation And Persistence

- Automatic participant shares and linked-bill reporting remain unchanged.
- Editing one debt row changes only that row's final debt principal.
- Other debt rows keep their automatic or manually saved amounts.
- Manual debt overrides do not regenerate or redistribute settlement
  suggestions.
- Finalization creates or updates each debt principal using its manually saved
  amount when present; otherwise it uses the automatic suggestion amount.
- Existing stale principal debt records must be reconciled so the persisted
  records match the current effective debt rows.
- The event's expected settlement total is the sum of effective debt-row
  amounts.

## Reset Behavior

- Show `Chia lại chi phí` whenever at least one debt amount has a committed
  manual override.
- Tapping it clears all debt overrides and any active debt draft.
- The debt rows immediately return to their automatically calculated amounts.
- Resetting debt overrides does not change paid inputs, participant shares, or
  linked-bill reporting.

## State And Dismissal

- Store committed debt overrides by a stable debt-row identity containing payer
  and receiver participant IDs.
- Store the active debt-row identity and its draft text separately.
- Include committed debt overrides and an active draft in the modal's unsaved
  changes guard.
- Clear debt editing state after successful finalization or event reset.

## Localization

Add or update String Catalog entries for:

- Edit debt amount accessibility label.
- Save debt amount accessibility label.
- Amount-must-be-greater-than-zero validation.

Remove participant-share edit and total-difference strings when no callers
remain. Keep `Chia lại chi phí` because it now resets debt overrides.

## Verification

- Add focused tests for applying a debt override without changing automatic
  participant shares or linked-bill reporting inputs.
- Add tests proving one debt override does not change another suggestion.
- Add tests for stable debt-row identity and effective debt amount selection.
- Verify zero is rejected at the modal commit boundary.
- Verify String Catalog generation.
- Build the Mistia app target for generic iOS.
- Run `git diff --check`.
