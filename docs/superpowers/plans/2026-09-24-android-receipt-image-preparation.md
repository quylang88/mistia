# Android Receipt Image Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the tested, iOS-equivalent receipt image budgeting algorithm that Android Photo Picker and CameraX will consume.

**Architecture:** A generic model-layer preparer owns all scaling/quality policy while an injected codec owns platform decoding, opaque rendering and JPEG encoding. JVM tests use a deterministic fake codec.

**Tech Stack:** Kotlin, coroutines, JUnit.

**Spec:** `docs/superpowers/specs/2026-09-24-android-receipt-image-preparation-design.md`

## Global constraints

- Maximum analysis dimension 3,000 px; minimum retry dimension 900 px.
- Maximum analysis payload 3,800,000 bytes.
- JPEG qualities 0.90 down to 0.42 in 0.08 steps.
- Dimension retry factor 0.86; thumbnail 240 px at quality 0.68.
- The algorithm must be cancellable and must not depend on Android framework
  image classes.
- No picker/camera UI, persistence, cloud call or localization in this slice.

### Task 1: TDD the preparation policy

**Files:**
- Create: `android/core/model/src/main/java/vn/com/quyln/mistia/core/model/ReceiptImagePreparation.kt`
- Create: `android/core/model/src/test/java/vn/com/quyln/mistia/core/model/ReceiptImagePreparationTest.kt`

- [ ] Write failing tests for dimension/quality policy, exact byte boundary,
  fallback resizing, failure paths, thumbnail policy and cancellation.
- [ ] Run the focused test and confirm RED because the contract is absent.
- [ ] Implement the smallest generic algorithm that passes.
- [ ] Re-run focused tests and confirm GREEN.

### Task 2: Evidence and independent commit

**Files:**
- Modify: `docs/android/android-parity-progress.md`
- Create: `docs/android/evidence/2026-09-24-apk1-receipt-image-preparation.md`

- [ ] Run the full Android gate, contract/localization checks and artifact
  checksum.
- [ ] Record the Android-codec/UI/device boundary without claiming it complete.
- [ ] Run `git diff --check`, self-review and commit independently.
