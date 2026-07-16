# Member Permission Instant Feedback Design

## Problem

In another member's data context, permission-gated actions feel unresponsive because Mistia waits for remote work before updating the interface:

- A new request keeps the permission alert on screen while session preparation and `create_family_permission_request` complete.
- A repeated attempt for an already-pending request waits for a full family refresh before showing that the request was already sent.
- The same blocking pattern is duplicated across Planning, Management, Overview, Transactions, Transaction Editor, and settlement event entry points.

The delay is network latency presented as input latency. A tap should receive visible feedback without waiting for Supabase.

## Goals

- Update the visible UI in the next main-actor turn after a permission action.
- Mark a newly submitted request as pending locally before the first network suspension.
- Coalesce duplicate submissions for the same owner, resource, resource ID, and scope.
- Show cached "request already sent" state immediately.
- Refresh pending approvals in the background so a remotely approved action still unlocks automatically.
- Roll back optimistic pending state and show the existing localized error when submission fails.
- Apply the behavior consistently to every member-context permission request path.

## Non-goals

- Changing Supabase RPCs, RLS policies, or notification delivery.
- Adding realtime subscriptions.
- Redesigning permission alert visuals.
- Changing the permission model or resource/scope semantics.

## Options Considered

### 1. Add a progress indicator while keeping current awaits

This acknowledges the tap but repeated attempts still wait for a full refresh before showing cached pending state. It does not remove network work from the interaction boundary.

### 2. Optimistic local pending with rollback and background reconciliation

This is the selected approach. It gives immediate feedback, prevents duplicate RPCs, preserves remote correctness, and fits the existing `FamilyContextStore` cache model.

### 3. Add realtime permission-request/grant subscriptions

This can reduce later reconciliation delay but is substantially broader. It does not replace the need for immediate local feedback and is unnecessary for this fix.

## Architecture

### Store-level submission reservation

`FamilyContextStore.requestPermission(...)` remains the authoritative submission method. Before its first `await`, it computes `FamilyPendingPermissionRequestKey` and reserves that key in `pendingPermissionRequestKeys`.

If the key is already pending, the method returns success without preparing a session or calling the remote service. This makes duplicate taps idempotent on the client.

The reservation is transient until the RPC returns a real request record. On success, the returned record is upserted and cached normally. On failure, the provisional key is removed only when no real pending request record owns the same key, then `lastErrorMessage` is populated as today.

### Immediate presentation

Each feature dismisses its permission prompt and presents a localized "sending request" info alert before awaiting `requestPermission(...)`. When the task completes, it replaces the progress copy with the existing sent or failed result.

For cached pending requests, each feature presents its existing pending prompt or "request sent" info alert synchronously. It then launches `resolvePendingPermissionBeforePrompt(...)` in the background. If refresh discovers a grant, the prompt is dismissed and the originally requested action continues.

### Shared localized copy

Two shared String Catalog keys describe the in-flight state:

- `shared.family.permissionRequest.sendingTitle`
- `shared.family.permissionRequest.sendingMessage`

They include Vietnamese, English, and Japanese values and are accessed through generated `L10n` APIs.

## Data Flow

1. User taps a permission action.
2. UI clears the blocking permission prompt and shows "sending" immediately.
3. `requestPermission(...)` reserves the local pending key before session/network work.
4. The RPC runs.
5. Success replaces the provisional reservation with the returned pending record and shows "sent".
6. Failure removes the provisional reservation and shows the existing visible error.
7. A later tap finds cached pending state synchronously, shows it immediately, and reconciles approval in the background.

## Error and Concurrency Handling

- A second identical submission while the first is in flight returns without issuing another RPC.
- Different scopes or resources use different keys and can proceed independently.
- A failed provisional submission is rolled back so the user can retry.
- A real cached pending record is never removed merely because a duplicate local call fails elsewhere.
- Cancellation and authentication errors follow the existing `visibleErrorMessage` path.

## Testing

Store regression tests use a controllable service stub to prove:

- pending state becomes visible before a delayed RPC completes;
- a duplicate request while the first is in flight produces only one service call;
- a failed request rolls back provisional pending state.

UI source-contract tests cover all permission surfaces and ensure cached-pending presentation happens before the refresh await. Existing family permission resolution tests continue to prove that background reconciliation recognizes remotely approved grants.

Final verification includes focused XCTest, localization strict checks, a generic iOS build, and `git diff --check`.
