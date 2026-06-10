# Codebase Performance Optimization Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Improve app responsiveness, memory efficiency, and database search queries by optimizing main thread CPU usage, image compression autorelease loops, SQLite fetches, and subview allocations.

**Architecture:** We will apply targeted performance patches: pointer-based O(1) signature checking for SwiftUI queries, autoreleasepools for transient UIImage data, consolidated SQL fetches with DB-side sorting/limiting, and non-allocating recursion for layouts.

**Tech Stack:** Swift, UIKit, SwiftUI, SwiftData, Foundation

---

### Task 1: Tab Bar Layout Subview Traversal Optimization

**Files:**
- Modify: `Mistia/App/MistiaNativeTabShell.swift:929-937`

**Step 1: Write the traversal optimization**
Modify `allDescendantControls` to use an accumulation function instead of `flatMap`.

```swift
  private var allDescendantControls: [UIControl] {
    var controls: [UIControl] = []
    accumulateDescendantControls(in: self, result: &controls)
    return controls
  }

  private func accumulateDescendantControls(in view: UIView, result: inout [UIControl]) {
    for subview in view.subviews {
      if let control = subview as? UIControl {
        result.append(control)
      }
      accumulateDescendantControls(in: subview, result: &result)
    }
  }
```

**Step 2: Commit changes**
```bash
git add Mistia/App/MistiaNativeTabShell.swift
git commit -m "perf: optimize tab bar subview search traversal"
```

---

### Task 2: SwiftUI Query Signature Caching in FamilyView

**Files:**
- Modify: `Mistia/Features/Family/FamilyView.swift:1977-2280`

**Step 1: Add GenericSignatureCache and Query signature caches**
Add `GenericSignatureCache` class at the bottom of the file (or private utility scope):

```swift
final class GenericSignatureCache<Record> {
    private var lastBaseAddress: UnsafeRawPointer?
    private var lastCount: Int = 0
    private var cachedSignature: MistiaCollectionChangeSignature = .empty

    func signature(
        for records: [Record],
        generator: () -> MistiaCollectionChangeSignature
    ) -> MistiaCollectionChangeSignature {
        let currentAddress = records.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
        if currentAddress == lastBaseAddress && records.count == lastCount {
            return cachedSignature
        }

        let newSignature = generator()
        lastBaseAddress = currentAddress
        lastCount = records.count
        cachedSignature = newSignature
        return newSignature
    }
}
```

Add cache properties to `FamilyOverviewDataHost`:
```swift
    @State private var walletsSignatureCache = GenericSignatureCache<LedgerWallet>()
    @State private var transactionsSignatureCache = GenericSignatureCache<LedgerTransaction>()
    @State private var budgetsSignatureCache = GenericSignatureCache<BudgetPlan>()
    @State private var goalsSignatureCache = GenericSignatureCache<SavingsGoal>()
    @State private var billsSignatureCache = GenericSignatureCache<RecurringBillPlan>()
    @State private var installmentsSignatureCache = GenericSignatureCache<InstallmentPlan>()
    @State private var occurrencesSignatureCache = GenericSignatureCache<DueOccurrenceRecord>()
    @State private var ownershipSignatureCache = GenericSignatureCache<OwnedRecordScope>()
    @State private var auditSignatureCache = GenericSignatureCache<TransactionAuditRecord>()
```

Modify `overviewDataCacheKey` to use caches:
```swift
    private var overviewDataCacheKey: FamilyOverviewDataCacheKey {
        let selectedMonth = selectedMonth(for: timeframe, now: .now)
        return FamilyOverviewDataCacheKey(
            timeframeRawValue: timeframe.rawValue,
            activeScope: familyContextStore.activeContext.scope,
            familyID: familyContextStore.family?.id,
            ownerUserID: familyContextStore.family?.ownerUserID,
            budgetManagerUserID: familyContextStore.family?.budgetManagerUserID,
            goalManagerUserID: familyContextStore.family?.goalManagerUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            currencyCode: currencyCode,
            currencyRateMode: currencyRateMode,
            manualJPYToVNDRate: manualJPYToVNDRate,
            cachedRatesSignature: cachedCurrencyRatesData.hashValue,
            referenceDayStart: calendar.startOfDay(for: .now).timeIntervalSince1970,
            selectedMonthStart: selectedMonth.timeIntervalSince1970,
            localeIdentifier: locale.identifier,
            membersSignature: membersSignature,
            walletsSignature: walletsSignatureCache.signature(for: storedWallets) {
                MistiaCollectionChangeSignature.make(
                    storedWallets,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    isArchived: \.isArchived,
                    remoteVersion: \.remoteVersion
                )
            },
            transactionsSignature: transactionsSignatureCache.signature(for: storedTransactions) {
                MistiaCollectionChangeSignature.make(
                    storedTransactions,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    isArchived: \.isArchived,
                    remoteVersion: \.remoteVersion
                )
            },
            budgetsSignature: budgetsSignatureCache.signature(for: storedBudgets) {
                MistiaCollectionChangeSignature.make(
                    storedBudgets,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    isArchived: \.isArchived,
                    remoteVersion: \.remoteVersion
                )
            },
            goalsSignature: goalsSignatureCache.signature(for: storedGoals) {
                MistiaCollectionChangeSignature.make(
                    storedGoals,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    isArchived: \.isArchived,
                    remoteVersion: \.remoteVersion
                )
            },
            billsSignature: billsSignatureCache.signature(for: storedBills) {
                MistiaCollectionChangeSignature.make(
                    storedBills,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    isArchived: \.isArchived,
                    remoteVersion: \.remoteVersion
                )
            },
            installmentsSignature: installmentsSignatureCache.signature(for: storedInstallments) {
                MistiaCollectionChangeSignature.make(
                    storedInstallments,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    isArchived: \.isArchived,
                    remoteVersion: \.remoteVersion
                )
            },
            occurrencesSignature: occurrencesSignatureCache.signature(for: storedOccurrences) {
                MistiaCollectionChangeSignature.make(
                    storedOccurrences,
                    updatedAt: \.updatedAt,
                    deletedAt: \.deletedAt,
                    remoteVersion: \.remoteVersion
                )
            },
            ownershipSignature: ownershipSignatureCache.signature(for: ownershipScopes) {
                MistiaCollectionChangeSignature.make(
                    ownershipScopes,
                    updatedAt: \.updatedAt,
                    deletedAt: { _ in nil }
                )
            },
            auditSignature: auditSignatureCache.signature(for: transactionAuditRecords) {
                MistiaCollectionChangeSignature.make(
                    transactionAuditRecords,
                    updatedAt: \.updatedAt,
                    deletedAt: { _ in nil }
                )
            }
        )
    }
```

**Step 2: Commit changes**
```bash
git add Mistia/Features/Family/FamilyView.swift
git commit -m "perf: add GenericSignatureCache and optimize overview data cache key"
```

---

### Task 3: Image Processing Autoreleasepool in AIBillImageProcessor

**Files:**
- Modify: `Mistia/Features/Transactions/AIBillAnalysisView.swift:1410-1444`

**Step 1: Wrap loops in autoreleasepool**
Update `compressedJPEGData` and `qualityAdjustedJPEGData`:

```swift
    private static func compressedJPEGData(for image: UIImage) -> Data? {
        var candidateImage = image
        var candidateMaxDimension = max(image.size.width, image.size.height)
        var bestData: Data?

        while candidateMaxDimension >= minAnalysisImageDimension {
            var data: Data?
            autoreleasepool {
                data = qualityAdjustedJPEGData(for: candidateImage)
            }
            if let data, data.count <= maxAnalysisImageBytes {
                return data
            }
            if let data, bestData == nil || data.count < (bestData?.count ?? .max) {
                bestData = data
            }

            candidateMaxDimension *= 0.86
            autoreleasepool {
                candidateImage = scaledImage(image, maxDimension: candidateMaxDimension)
            }
        }

        if let bestData, bestData.count <= maxAnalysisImageBytes {
            return bestData
        }
        return nil
    }

    private static func qualityAdjustedJPEGData(for image: UIImage) -> Data? {
        var quality: CGFloat = 0.82
        var data = image.jpegData(compressionQuality: quality)

        while let current = data, current.count > maxAnalysisImageBytes, quality > 0.42 {
            quality -= 0.08
            autoreleasepool {
                data = image.jpegData(compressionQuality: quality)
            }
        }

        return data
    }
```

**Step 2: Commit changes**
```bash
git add Mistia/Features/Transactions/AIBillAnalysisView.swift
git commit -m "perf: wrap image compression loops in autoreleasepools"
```

---

### Task 4: Database Query Consolidation in Category Maintenance

**Files:**
- Modify: `Mistia/Shared/Sync/CategoryNameTranslationService.swift:289-361`

**Step 1: Consolidate fetch descriptor query**
Rewrite `fetchCandidateCategories`:

```swift
    private static func fetchCandidateCategories(
        modelContext: ModelContext,
        limit: Int
    ) -> [TransactionCategory] {
        let descriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate { category in
                category.deletedAt == nil
                    && category.isArchived == false
                    && category.isSystem == false
                    && (category.pendingTranslationSourceName != nil
                        || category.nameEnglish == nil
                        || category.nameEnglish == ""
                        || category.nameJapanese == nil
                        || category.nameJapanese == "")
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        var descriptorCopy = descriptor
        descriptorCopy.fetchLimit = limit

        return (try? modelContext.fetch(descriptorCopy)) ?? []
    }
```

**Step 2: Commit changes**
```bash
git add Mistia/Shared/Sync/CategoryNameTranslationService.swift
git commit -m "perf: consolidate category translation maintenance query to 1 fetch descriptor"
```

---

### Task 5: Build and Test Verification

**Files:**
- Test: Package tests and compiler verification

**Step 1: Run swift test**
Run: `swift test`
Expected: Passes logic verification tests.

**Step 2: Compile app**
Run swift build to verify target compilations.
