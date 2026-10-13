# APK 2 offline recurring bill lifecycle

Match PlanningBillEditor.save/normalizedBillSchedule, PlanningBillPauseActions
and archive unpaid-cycle guard. Typed owner-scoped bills (including archived
paid history) and occurrences. Atomic Room record/outbox save/pause/resume/archive.
Preserve created/version/currency, first-month anchor and recurring pause state
on edits; one-time conversion clears irrelevant recurrence/pause fields.
Validate owner-scoped expense child category/payment wallet; preferred archived
references remain eligible. Credit card wallet allowed like iOS.

- [x] RED repository tests: creation normalization, nullable/one-time fields,
  first/next/resume anchors, existing version/currency/paused state, scope/forged
  payload/stale edits, invalid dependencies/dates, archive unpaid/skipped guard,
  unchanged historical occurrences, storage failure/cancellation.
- [x] Implement and GREEN; Room persistence/reopen lifecycle test compilation.
- [x] Direct Swift review and final full Android/Swift/contract/localization
  checks, ADB status, evidence/progress, APK checksum and commit.
- [ ] Continue separately gated bill/occurrence push, native bill form/payment
  and due maintenance/notifications. All seven write gates remain false.
