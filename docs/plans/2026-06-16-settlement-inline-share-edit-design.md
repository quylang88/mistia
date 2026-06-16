# Settlement Inline Share Edit Design

## Goal

Simplify the `Chia chi phí` section and let users edit each participant's
allocated share directly in its result row.

## Chosen Approach

Use an inline, commit-based editor for each participant row.

Alternatives considered:

- Keep the current always-visible currency fields. This is simpler internally
  but leaves the section visually heavy and has no explicit save action.
- Open a child sheet for each amount. This isolates editing but adds navigation
  for a small change and does not match the requested inline behavior.

The inline editor best matches the requested interaction while preserving the
existing Mistia icon-button style.

## Row Layout

- Remove the separate `Đã trả` and `Phần chia` blocks from each result row.
- Do not render the self participant as an editable row in the
  `Chia chi phí` section.
- Keep the participant name on the leading side.
- Show `Đã sửa +...` or `Đã sửa -...` beside the name only after the saved
  share differs from that participant's automatic share.
- Show the participant's current share amount on the trailing side.
- Place a small circular `pencil` icon button beside the amount, visually
  aligned with the calculator icon button used by Mistia currency inputs.
- Keep settlement suggestions below the participant rows; those suggestions
  continue to show the resulting amount each person should pay or receive.

## Editing Interaction

- Tapping `pencil` changes only that row's displayed share into a currency
  input and changes the button icon to `checkmark`.
- The input receives focus, selects all existing text, and opens the numeric
  keyboard automatically.
- Input changes remain a local draft until the user taps `checkmark`.
- Tapping `checkmark` commits the draft and returns the row to display mode.
- Only one row can be actively edited at a time. Other edit buttons are
  disabled until the active row is saved.
- An empty committed value is treated as zero.

## Calculation Rules

- Keep the self participant in the split calculation even though the self row
  is hidden from this section.
- Automatic shares are calculated without considering manual overrides.
- Saving a manual share changes only that participant.
- Other participants keep their existing automatic or manually saved shares.
- Manual shares may produce a total above or below the total paid.
- This mismatch is allowed and never disables saving or shows an error.
- Show an informational `Chênh lệch tổng +...` or
  `Chênh lệch tổng -...` row when the allocated-share total differs from the
  paid total.
- Settlement suggestions match available payers and receivers. Any unmatched
  difference remains visible through the total-difference row and is not
  assigned automatically.
- Keep settlement suggestions involving the self participant visible.
- The user must choose `Chia lại chi phí` to discard manual shares and return
  all participants to automatic allocation.
- Before finalization, show `Chia lại chi phí` at the bottom of the section
  whenever at least one committed manual share exists. This draft reset does
  not need confirmation.
- Keep the existing confirmed reset flow for an already-finalized split.

## State And Persistence

- Keep committed manual shares in `shareTextsByParticipantID`.
- Add separate active-row and draft-text state for inline editing.
- Include an active unsaved draft in the modal dismissal guard.
- `Chia lại chi phí` clears all committed share overrides and any active draft
  before recalculating automatic shares.

## Localization

Add String Catalog entries for:

- Edit participant share accessibility label.
- Save participant share accessibility label.
- Total difference with a formatted signed amount.

Existing `Đã sửa +/−` localization remains reusable.

## Verification

- Add focused core-logic tests proving one manual override does not redistribute
  any other participant.
- Add tests for over-allocated and under-allocated total differences.
- Verify the String Catalog and generated `L10n` file.
- Build the Mistia app target for generic iOS.
- Run `git diff --check`.
