# APK 2 bill scheduling and due occurrence foundation

Typed DueOccurrenceRecord plus pure owner-scoped bill due rows and unpaid-cycle
guard ported directly from Swift PlanningLogic. This is the common calculation
needed by native bills, archive/pause/resume, payment and later due maintenance.

- [x] RED occurrence wire tests: complete keys/nulls, Long endpoints, strict
  required/optional decoding, lossless raw enum strings with Swift fallbacks.
- [x] RED scheduling tests: local month/frequency/first/resume anchor, day clamp,
  next-month deadline, one-time exact dates, auto-pay normalization, paused
  exclusion, archived paid history, duplicate precedence, snapshots/scope and
  skipped/unpaid current/past cycles preventing archive.
- [x] Minimal implementation and GREEN; direct Swift review and fix regressions.
- [x] Full Android/Room/lint/build, focused Swift planning, contract/generators,
  ADB status, evidence/progress and commit; continue offline bill lifecycle.

No cloud writes/deployments. All seven write gates remain false.
