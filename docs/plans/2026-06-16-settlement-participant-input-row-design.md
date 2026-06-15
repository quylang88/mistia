# Settlement Participant Input Row Design

## Goal

Make the participant input section in the split-cost modal denser and clearer.

## Behavior

- Show only non-self participants in the participant input section.
- Keep the self participant in settlement calculations and split results.
- Render each participant name and paid amount field on one row.
- Use `Đã trả` only as the currency field placeholder, without a separate label.

## Scope

Only `SettlementSplitCalculatorSheet` presentation changes. Settlement calculations,
validation, persistence, and localization keys remain unchanged.

## Verification

- Build the Mistia app target for generic iOS.
- Run `git diff --check`.
