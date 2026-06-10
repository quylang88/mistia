# Design Document - Codebase Performance Optimization

## Goal
Improve app performance, fluidity, memory efficiency, and database operations in Mistia by resolving critical bottlenecks on the main thread, database query overhead, image processing allocation spike, and redundant view layout overhead.

## Proposed Changes

### 1. Generic Signature Cache for SwiftUI Views
- **File:** [FamilyView.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Family/FamilyView.swift)
- **Problem:** `FamilyOverviewDataHost` computes `overviewDataCacheKey` on every render body evaluation by calling `MistiaCollectionChangeSignature.make` which loops through all database transactions ($O(N)$).
- **Solution:** Implement a fast pointer-based signature cache `GenericSignatureCache` using `@State` variables to bypass array loop in $O(1)$ when database array buffer has not changed.

### 2. Autoreleasepool in AIBillImageProcessor
- **File:** [AIBillAnalysisView.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Transactions/AIBillAnalysisView.swift)
- **Problem:** Loop resizing and nén JPEG image processes allocate many temporary `UIImage` and `Data` objects under ARC without immediate reclamation, generating high memory spikes.
- **Solution:** Wrap loop iterations inside `autoreleasepool { ... }` blocks to drain temporary memory allocations immediately.

### 3. Consolidated Database Query in Category Name Translation Service
- **File:** [CategoryNameTranslationService.swift](file:///Users/quylang/Projects/mistia/Mistia/Shared/Sync/CategoryNameTranslationService.swift)
- **Problem:** `fetchCandidateCategories` runs 5 distinct fetch descriptors, concatenating results and manually sorting, de-duplicating, and prefix limiting on RAM.
- **Solution:** Merge all conditions using logical `||` into a single query descriptor, leveraging SQLite native sorting (`sortBy`) and limit (`fetchLimit`).

### 4. Efficient Layout Subview Search in Tab Bar Shell
- **File:** [MistiaNativeTabShell.swift](file:///Users/quylang/Projects/mistia/Mistia/App/MistiaNativeTabShell.swift)
- **Problem:** `allDescendantControls` recursively traverses the view tree using `flatMap` on every layout update, allocating multiple transient arrays.
- **Solution:** Traverve recursively with an `inout` accumulator array, reducing heap allocation to a single array.

## Verification
- Run Swift package tests: `swift test`
- Build verification.
