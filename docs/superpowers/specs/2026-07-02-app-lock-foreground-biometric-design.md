# App Lock Foreground Biometric Design

## Goal

When app lock and biometric unlock are enabled, Mistia must automatically request biometric authentication every time the app returns from the background and locks again. The existing biometric button remains available for an explicit retry after cancellation or failure.

## Root Cause

`MistiaApp` correctly locks the controller when the scene enters the background. That immediately inserts `MistiaAppLockScreen`, whose `.task` starts biometric authentication while the app is still in the background. The system cannot present the Face ID prompt there, but the view has already recorded `didAttemptBiometric = true`. Returning to the foreground therefore has no remaining automatic attempt.

Triggering authentication indiscriminately whenever the scene becomes active is also unsafe because the system biometric prompt can itself affect scene phase. The attempt must wait for the first active phase within a new lock cycle and then be claimed exactly once.

## Design

`MistiaAppLockController` will expose a monotonically changing lock-cycle identifier. It advances only when `lockIfNeeded()` performs a real transition from unlocked to locked. Repeated background notifications while already locked do not create additional cycles.

The root lock overlay will give `MistiaAppLockScreen` an identity derived from that lock cycle. Each new cycle therefore receives fresh local presentation state.

`MistiaAppLockScreen` will observe `scenePhase` and own a small automatic-attempt state machine. A background or inactive phase does not consume the attempt. The first active phase claims the attempt synchronously, then starts biometric authentication. Later inactive-to-active transitions caused by the system prompt cannot claim it again in the same lock cycle.

Cold launch behavior remains unchanged: an enabled controller starts locked and the first lock screen automatically requests biometrics. Manual app-code fallback remains inside the same opaque lock overlay, and the biometric button continues to retry authentication explicitly.

## State Transitions

1. Cold launch with app lock enabled: controller starts locked; lock screen appears; biometrics run once.
2. Successful authentication: controller becomes unlocked; protected overlay disappears.
3. App enters background: `lockIfNeeded()` transitions the controller to locked, advances the lock cycle, and presents the opaque lock screen without starting biometrics.
4. App returns to foreground: the first active scene phase claims the automatic attempt and starts biometrics.
5. The biometric prompt causes later phase changes: the attempt is already claimed, so no automatic loop occurs.
6. Authentication cancellation or failure: the app remains locked; the user can retry or use the app code.

## Error and Privacy Behavior

- A failed or cancelled biometric request never unlocks the app.
- No retry loop is initiated automatically within the same lock cycle.
- App content remains covered by the existing full-screen opaque lock overlay.
- Devices without available biometrics continue to use the app-code screen.

## Testing

Keep controller regression coverage proving that:

- a real unlocked-to-locked transition advances the lock cycle;
- repeated lock requests while already locked do not advance it;
- unlocking and then locking again advances it again.

Add automatic-attempt state coverage proving that:

- background and inactive phases do not consume the attempt;
- the first active phase claims it;
- later active phases in the same lock cycle cannot claim it again.

Run the focused app-lock controller tests, then build the Mistia app target for a generic iOS destination with code signing disabled.
