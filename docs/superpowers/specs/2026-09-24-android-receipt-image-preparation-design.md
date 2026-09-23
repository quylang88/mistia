# Android Receipt Image Preparation Design

## Intent

Port the deterministic image-budget policy used by Mistia's iOS itemized bill
flow before Android adds Photo Picker and CameraX. Any selected or captured
image must become an opaque JPEG that is sharp enough for literal OCR, small
enough for the Edge Function, and accompanied by a lightweight thumbnail.

## Scope

- Add a platform-neutral image codec boundary and preparation algorithm.
- Normalize the analysis image to at most 3,000 px on its longest side.
- Encode JPEG from quality 0.90 down by 0.08 to 0.42.
- If quality reduction is insufficient, reduce the longest side by 0.86 and
  retry, stopping before going below 900 px.
- Accept output only at or below 3,800,000 bytes, leaving margin below the Edge
  Function's 4 MiB ceiling.
- Produce a 240 px thumbnail at JPEG quality 0.68.
- Return only `image/jpeg` prepared data; invalid decode/dimensions, failed
  scaling/encoding, or an image that cannot fit the budget returns a typed
  preparation failure.

## Boundaries

- This slice does not add an Android bitmap codec, URI access, Photo Picker,
  CameraX, permissions, Compose UI, persistence, or an Edge Function call.
- Orientation correction and white-background rendering belong to the concrete
  Android codec that follows; the algorithm requires the codec's decoded frame
  to be orientation-normalized and its scaling output to be opaque.
- No localization, cloud access or production state is involved.

## Architecture and verification

`core:model` owns the generic `ReceiptImageCodec<Frame>`, immutable prepared
result/failure types, and `ReceiptImagePreparer<Frame>`. A fake codec drives
deterministic JVM tests without Android bitmap/native dependencies. The later
Android codec can use the exact same algorithm for Photo Picker and CameraX.

Tests cover initial scaling, quality descent, dimension descent, exact byte
boundary acceptance, too-large rejection, thumbnail policy, decode/scale/
encode failures and cancellation checkpoints.
