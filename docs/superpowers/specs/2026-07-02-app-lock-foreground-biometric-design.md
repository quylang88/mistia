# App Lock Foreground Biometric Design

## Goal

When app lock and biometric unlock are enabled, Mistia must automatically request biometric authentication every time the app returns from the background and locks again. The existing biometric button remains available for an explicit retry after cancellation or failure.

## Root Cause

`MistiaApp` correctly locks the controller when the scene enters the background. However, `MistiaAppLockScreen` records its automatic attempt in local `didAttemptBiometric` state. SwiftUI can preserve that state when the conditional lock overlay is removed and later presented at the same structural identity. The next lock presentation therefore skips its automatic biometric task.

Triggering authentication directly whenever the scene becomes active is unsafe because the system biometric prompt can itself affect scene phase. Authentication must be driven by a real unlocked-to-locked transition instead.

## Design

`MistiaAppLockController` will expose a monotonically changing lock-cycle identifier. It advances only when `lockIfNeeded()` performs a real transition from unlocked to locked. Repeated background notifications while already locked do not create additional cycles.

The root lock overlay will give `MistiaAppLockScreen` an identity derived from that lock cycle. Each new cycle therefore receives fresh local presentation state and automatically starts biometric authentication exactly once through the existing `.task` path.

Cold launch behavior remains unchanged: an enabled controller starts locked and the first lock screen automatically requests biometrics. Manual app-code fallback remains inside the same opaque lock overlay, and the biometric button continues to retry authentication explicitly.

## State Transitions

1. Cold launch with app lock enabled: controller starts locked; lock screen appears; biometrics run once.
2. Successful authentication: controller becomes unlocked; protected overlay disappears.
3. App enters background: `lockIfNeeded()` transitions the controller to locked and advances the lock cycle.
4. App returns to foreground: the lock screen is recreated for the new cycle and biometrics run once automatically.
5. Authentication cancellation or failure: the app remains locked; no automatic loop occurs; the user can retry or use the app code.

## Error and Privacy Behavior

- A failed or cancelled biometric request never unlocks the app.
- No retry loop is initiated automatically within the same lock cycle.
- App content remains covered by the existing full-screen opaque lock overlay.
- Devices without available biometrics continue to use the app-code screen.

## Testing

Add controller regression coverage proving that:

- a real unlocked-to-locked transition advances the lock cycle;
- repeated lock requests while already locked do not advance it;
- unlocking and then locking again advances it again.

Run the focused app-lock controller tests, then build the Mistia app target for a generic iOS destination with code signing disabled.
