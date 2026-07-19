# Design Spec: Redesign Invitation Management Screen

## Goal
Redesign the Invitation Management Screen (`FamilyInviteManagementScreen` and its sub-components) in the Mistia iOS app to adopt a premium, minimalist native Apple iOS 16+ style. The redesign removes the technical engineering timeline markers and tidies up inactive/historical invitations by hiding redundant action buttons and URL links.

## Current Problems
1. **Engineering Timeline Style:** The current view uses a vertical timeline line with circle markers, which looks like a git log/audit log rather than a premium, minimalist consumer app.
2. **Raw Link Exposure:** Long raw URL strings are printed on the screen, creating visual clutter.
3. **Redundant Actions:** Inactive invitations (declined, accepted/used, expired, revoked) still display "Copy" buttons and/or the full URL path, which is unnecessary and confusing.
4. **Bulky Metrics Grid:** The 2x2 statistics grid card at the top occupies too much vertical space.

## Proposed Design (Option A: Grouped iOS List Layout)

### 1. Minimalist Metrics Summary Card
- Group all metrics (Pending, Used, Declined, Expired) in a single horizontal `HStack` inside `inviteSummarySection` wrapper (`MistiaGlassCard`).
- Separate the counts and labels with thin vertical dividers.
- This reduces vertical space consumption and aligns with iOS settings metrics styles.

### 2. Redesigned Invitation Rows (`FamilyInviteTimelineRow`)
- **Remove Timeline Marker:** The vertical indicator line and circle marker on the left are completely removed.
- **Left Icon Indicator:** Add a rounded-rect or circular icon backdrop (size 36x36) representing the state of the invite with soft accent backgrounds and white SF Symbols:
  - `pending` (orange background): `envelope.fill` or `link`
  - `accepted` (mint/green background): `person.fill.checkmark`
  - `declined` (red background): `person.fill.xmark`
  - `expired` / `revoked` (gray background): `clock.fill` or `trash.fill`
- **Right Badge:** Display a compact state name using the custom component `MistiaMiniBadge`.
- **Text Hierarchy:**
  - Title: Invitee's name (if accepted) or "Lời mời tham gia" (Invite to join) + default role.
  - Subtitle 1: Role detail (e.g. "Vai trò: Thành viên", "Vai trò: Trẻ em").
  - Subtitle 2: Timestamps for "Sent" and "Expired/Accepted/Declined/Revoked" in clean, small gray text.
- **Action Buttons Area (Only for `.pending` invites):**
  - Displays a compact HStack of capsule-styled buttons: **Chia sẻ** (Share), **Sao chép** (Copy), and **Thu hồi** (Revoke, right-aligned with destructive styling).
  - No raw URLs are rendered in any invitation state.
  - For all inactive states (`accepted`, `declined`, `expired`, `revoked`), the action buttons area is hidden entirely, automatically shrinking the row size and giving a clean, minimal look.

## Verification Plan
1. **Compilation:** Verify the SwiftUI project compiles without any compiler errors.
2. **Visual Inspection:** Verify layout elements are grouped correctly, dividers are drawn, and buttons/links are hidden on inactive states.
3. **Functional Check:** Verify Copy, Share, and Revoke actions still function properly for pending invitations.
