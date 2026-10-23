# Notification preference ordering implementation plan

> Inline superpowers:executing-plans + TDD. User TXT authorizes local complete-slice commits and overrides confirmation pauses. Do not mix142 source into141 commit.

Goal: no stale preference StateFlow publication after a newer mutation.
Spec: notification-preference-ordering-design-2026-10-23.md.
Constraints: all11cloud gatesfalse, Room6/SwiftDataV11, noSamsung/prod/deploy/migration/push. Same existing branch/checkout; no new worktree or product question.
Review focus: old listener read racing a newer write; multiple stores for one preference file; whole-field snapshot coherence; reentrant main listener; no uncommitted changes outside this domain.

### Task 1: Reproduce and fix ordered publication

Files: LocalNotificationPreferencesStore.kt; new database/androidTest NotificationPreferencesPublicationRoomTest.kt; existing NotificationPreferencesStoreTest.kt unchanged.

- [x] Read concrete141 failure /tmp/mistia141-database-accepted-native.log and actual store/Android callback path.
- [x] Add actualAndroid regression: real preferences through ContextWrapper; latch one main listener read after capturing enabled=true; collect StateFlow, start off mutation on background thread, then release listener. Test actual emissions never revert to true after the off result. Support getBoolean/getAll interception to exercise both existing and corrected reader. Observe runtime RED and record exact sequence. Use bounded coordination that releases listener even when the corrected setter waits for the shared lock.
- [x] Serialize update and listener refresh with private file-level lock; read one all-fields snapshot per publication. Keep platform callback reentrancy valid. Do not add test-only APIs.
- [x] Focused native GREEN plus existing recreation/legacy tests and full database JVM. Check multiple-store mutation/read boundaries directly; add a behavior test if a separate concrete failure needs coverage.

### Task 2: Verify and commit complete142

- [x] Full JVM/Room native compile/lint/main/testAPK, Swift/contracts/bothstrictl10n/guard/schema/assets/icons/fold/whitespace checks. Full Room native294 including new tests on current source; relevant notification native/UI scope.
- [x] One final scoped fresh review required by executing-plans; correct Important/Critical in one observed TDD pass, no re-review loop.
- [x] Version141 APK contents/hash/install-r/installed checksum/cold start and precise emulator/Samsung/cloud boundary. Evidence/progress/handoff/source patch; commit142 separately and immediately continue actual resale purchase/sale and full remaining goal.
