# Owned product images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans, inline under the user's autonomous TXT instructions. Steps use checkboxes. Commit only the complete coherent slice.

**Goal:** Actual native inventory product-photo add/replace/remove/camera/picker/thumbnail with durable private owner-scoped cache and gated Storage adapters.
**Architecture:** Typed asset image intent, immutable canonical private object identities, a dedicated image repository and durable manifest. Metadata Room CAS and cache staging are linked by conservative committed-result probing; file cleanup cannot retire a current reference. Existing asset/trade atomic RPC publication integration is the next sync slice.
**Tech Stack:** Existing Kotlin/Compose/Room6/OkHttp/JPEG tooling; Swift reference and current official Supabase docs.
**Spec:** docs/android/investment-product-images-design-2026-10-24.md

## Global Constraints

- All11cloudflagsfalse/Room6/SwiftDataV11, no production write/deploy/migration/RLS/push. Every remote write method rejects while investment gate is false.
- Canonical asset image_path is private ownerUUID/assetUUID/randomUUID.jpg or explicitnull; no public URL/base64. Bucketinvestment-product-images is private, image/jpeg,5242880limit. Normalize full1600px<=4000000bytes and thumb240px/quality78.
- Work in user-requested /Users/quyln/Project/mistia on codex/android-apk2-4-parity; preserve completed148/147 artifacts, no checkout/reset/rebootstrap. Main nextversion148.
- RuntimeTDD, direct Swift/diff review, complete appropriate checks/evidence/progress/handoff and immediate local slicecommit; no repeated approvals/OAuth/account-switch replay.

## Review Focus

- Cached prior-account bytes must not render under a replacement account or arbitrary subject/path, even offline.
- Late upload/asset ACK cannot delete a newer still-referenced replacement; ACK is asset+path/revision-specific.
- Crash/cancellation/lost Room response after metadata commit retains exactly referenced immutable files; uncertain probe never deletes them.
- Duplicate immutable-object upload accepts only matching server bytes; never x-upsert or overwrite a different object's data.
- Canceled native picker/camera/old draft callback cannot attach an image to a newer asset/form.

### Task 1: Complete actual owned product images

**Files:** core/model new InvestmentProductImages.kt, InvestmentProductImagesTest.kt and typed image intent in InvestmentAssets.kt; dedicated database ProductImageRepository/cache-manifest and tests, typed asset save integration; network private Storage adapter and MockWebServer tests; actual feature/investment photo selection/processing/thumbnail/editor/screen and native tests; app repository injection/navigation. Reuse existing core ReceiptImagePreparation and transactions camera/picker patterns where suitable without putting product images in the receipt table. Canonical copy already provides investment.asset.* image labels; regenerate only if genuinely new keys are needed.
**Interfaces:** InvestmentProductImagePath.create(owner:UserId,assetId:String,objectId:String) and parse(owner:UserId,assetId:String,raw:String):InvestmentProductImagePath with value:String and strict canonical identity. InvestmentAssetImageChange.Keep / Replace(staged reference) / Remove defaultsKeep in asset draft. Dedicated InvestmentProductImageRepository stages immutable full/thumb, reads authorized cache, conditionally links/discards, exposes pending uploads and revision-bound cleanup; explicit immutable staged token includes owner/asset/path/content hash. Private remote adapter authenticates read with current JWT/apikey, gated upload/delete exactbytes/404 handling. Repository interface signatures for persistence are fixed with tests before implementing their consumers, preserving these constraints.

- [x] Write path tests with literal private object path and cross-owner/asset/absolute/URL/encoded-traversal/malformed UUID rejection. Observe actual runtime RED using a narrow unsupported boundary, then implement minimum canonical validation and run fullmodel.
- [x] Add meaningful filesystem/native runtime RED for stage/full+thumb/replace/remove/cancel/recreate/unknown probe/owner and immutable identity collisions. Implement dedicated atomic owner-scoped manifest/cache with captured caller/active-owner fences, conservative durable result probe and revision-bound pending/deferred/ready states. Verify corrupted manifest/file and failure rollback, not silent empty state.
- [x] Write typed asset image-intent RED: Keep preserves old path, Replace validates owner/asset/staging, Remove emits explicitnull, stale baseline cannot overwrite new photo. Implement repository/cache+Room conditional publication and exact result retry; real Room queue failure and caller/owner/CAS tests preserve old metadata/files.
- [x] Write MockWebServer RED for authorized private read,404/cache, encoded path and owner rejection, gated immutable POST/400-409 exactbytes probe, gated DELETE2xx/404/retry, source/path-specific ACK order. Implement remote port without enabling writes or production access; no automatic retries replay a stale operation.
- [x] Write actual native missing-image-action RED. Implement Photo Picker/camera/permission, bounded orientation-normalized JPEG prep, asset add/replace/remove preview, existing remote thumbnail/cache and actual list/trade picker/detail display. Normal draft restore uses durable staged identity; prompts/late picker results never rebind to a new form. Native save/cancel/sourcechange/owner/readerror/processrestore and ENVIJA lightdark/font130/320 matrix.
- [x] Run full testDebugUnitTest, affected Room/native compilation and appropriate actual instrumentation, app lint/build, Swift627, all11checks and direct author Swift/diff review (no independent final-clean claim). Fix actionable findings with runtimeRED→GREEN/full relevant checks. Verify privacy/token/body redaction and allgatesfalse without production calls.
- [x] Archive version148 APKs/source patch/hash/install-r/installed proof/native image evidence, update design/plan/progress/handoff, commit complete149 immediately. Then150 existing atomic RPC push/result/conflict and upload-beforeasset/publication/cleanup integration, remaining fullAPK1–4/RC.


Acceptance: final2206JVM/209zero,Swift627zero,11checks0,Room343GREEN8.381s,wholeInvestment189GREEN1078.039s; all three APK archives/installed hashes match, main148 install-r/COLD1229ms. Source38files/237399bytes SHA97a9fd0f91927913f1bc1392add1ec343c37c0f99b849c0e58bade79d07bb92e. Six final native photo originals inspected/hashed. Author review found two substantive mismatches and fixed both RED→GREEN. Automatic startup/cloud publication integration is explicitly150; unknown files remain held. No whole APK1–4/finalbranch completion claim. See evidence/2026-10-24-investment-product-images.md.
