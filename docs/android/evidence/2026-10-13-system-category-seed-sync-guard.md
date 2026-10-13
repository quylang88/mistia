# Untouched system category seed sync protection — 2026-10-13

Added a narrow classifier: active catalog definition, exact owner cloud ID,
version0, matching creation/update instants, real device, exact seed semantic
fields and validated actual parent identity/system key. Existing legacy parent
IDs/custom parent metadata are eligible; unrelated/foreign parent is not.
Name/translation/favorite/archive/deletion/version/time edits fail classification.
Raw local payload must match its typed representation, preventing unknown local
semantic fields from being treated as untouched defaults.

Category coordinator gets shared catalog through DI and opts into a remote
preference hook only for base-version0 unmodified seeds. Same-ID existing remote
customization/tombstone ACKs without overwrite, including create-race refetch.
User edits and previously uploaded system rows retain normal conflict winners.
Stale preference ACK cannot clear a replacement edit; next push uses normal
local winner. Other domains default to no remote preference; all prior tests pass.

TDD missing classifier/coordinator APIs RED then GREEN. Core tests exercise all
147 real active definitions plus explicit edits and legacy-parent cases. Nine
focused sync tests cover custom remote, tombstone, create race, next user edit,
stale ACK, normal new create, disabled gate and versioned normal winners.
Direct review of Swift bootstrap/identity and typed ownership contracts done.
No automatic startup seed wired yet: different-ID legacy system-key collisions
and canonical budget comparisons must be resolved before startup integration.

Full Android testDebugUnitTest, Room compilation, lintDebug and assembleDebug
passed (715 tasks/45s). 538 JVM tests across70 suites, zero failures. Four Swift
identity + nine transaction conflict tests passed. Contract15, Android/strict
Swift localization and diff checks pass. VersionCode13, all eight write gates
false. ADB empty; no device/production requests, writes, migration/deployment or
independent final reviewer approval claimed.

Artifact: android/build/outputs/apk2/2026-10-13/mistia-0.2.0-apk2-category-seed-sync-guard-v13.apk
SHA-256: acac3c43d13b7638c4545b14f425ddeb55e8a660e120abee3db3cb905ef4c35a

Scope boundary: protects existing remote at the same owner-scoped category ID.
Legacy remote row at a different ID for the same system key still needs identity
reconciliation. Native bill UI/payment, maintenance and remaining APK2–4 plus
final visual/physical verification remain incomplete.
