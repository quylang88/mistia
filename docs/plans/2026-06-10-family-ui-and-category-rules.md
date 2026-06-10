# Family UI and Category Archiving Rules Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Resolve the family overview "Add Member" button gesture issues, enforce category archiving rules based on children and active records (transactions, budgets, bills), and fix English/Japanese translations for diapers and shortcuts.

**Architecture:** Enforce data-integrity checks at the UI action level in `ManagementCategoryEditorSheet.archiveCategory()`, adjust SwiftUI view hierarchy and tap target bounds in `FamilyView.swift` to ensure responsiveness, and synchronize schema/localization assets.

**Tech Stack:** Swift, SwiftUI, SwiftData, Supabase PostgreSQL, Xcode Localization (xcstrings).

---

### Task 1: Update Localization Strings
**Files:**
- Modify: [Localizable.xcstrings](file:///Users/quylang/Projects/mistia/Mistia/Localizable.xcstrings)

**Step 1: Add new alert keys and update shortcut translations**
Locate `settings.shortcut.title` and change its `ja` translation value to `"ショートカット"`.
Locate `settings.shortcut.description` and change its `ja` translation value to `"ショートカットを有効にするとタブバーに固定ボタンが表示されます。選んだ項目を直接開きます。"`.
Add new keys under `management.management`:
- `categoryArchiveBlockedHasChildren`:
  - `vi`: "Không thể lưu trữ danh mục này vì vẫn còn các danh mục con đang hoạt động."
  - `en`: "Cannot archive this category because it still has active subcategories."
  - `ja`: "有効なサブカテゴリがまだ存在するため、このカテゴリをアーカイブできません。"
- `categoryArchiveBlockedHasTransactions`:
  - `vi`: "Không thể lưu trữ danh mục này vì đang được liên kết với các khoản thu chi."
  - `en`: "Cannot archive this category because it is linked to transactions."
  - `ja`: "取引が関連付けられているため、このカテゴリをアーカイブできません。"
- `categoryArchiveBlockedHasBudgets`:
  - `vi`: "Không thể lưu trữ danh mục này vì đang được liên kết với ngân sách."
  - `en`: "Cannot archive this category because it is linked to budgets."
  - `ja`: "予算が関連付けられているため、このカテゴリをアーカイブできません。"
- `categoryArchiveBlockedHasBills`:
  - `vi`: "Không thể lưu trữ danh mục này vì đang được liên kết với hóa đơn."
  - `en`: "Cannot archive this category because it is linked to bills."
  - `ja`: "請求書が関連付けられているため、このカテゴリをアーカイブできません。"

**Step 2: Commit changes**
```bash
git add Mistia/Localizable.xcstrings
git commit -m "loc: add category archive block keys and update shortcut ja translation"
```

---

### Task 2: Regenerate L10n.generated.swift
**Files:**
- Modify: [L10n.generated.swift](file:///Users/quylang/Projects/mistia/Mistia/Shared/CoreLogic/L10n.generated.swift)

**Step 1: Run generation script**
Run: `swift Scripts/generate-l10n.swift --input Mistia/Localizable.xcstrings --output Mistia/Shared/CoreLogic/L10n.generated.swift`
Expected: Passes and regenerates `L10n.generated.swift` containing the new static methods.

**Step 2: Commit**
```bash
git add Mistia/Shared/CoreLogic/L10n.generated.swift
git commit -m "loc: regenerate L10n file"
```

---

### Task 3: Enforce Category Archiving Restrictions
**Files:**
- Modify: [ManagementEditors.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Management/ManagementEditors.swift)

**Step 1: Add SwiftData query for LedgerTransaction**
Add inside `ManagementCategoryEditorSheet` at line 640:
```swift
    @Query
    private var storedTransactions: [LedgerTransaction]
```

**Step 2: Implement sequential validation checks in archiveCategory()**
Replace the old `archiveCategory()` logic with the following check:
```swift
    private func archiveCategory() {
        guard let category = target.category else { return }

        // 1. Check active subcategories (for parent categories)
        if category.hierarchyRole == .parent {
            let activeChildren = category.childCategories.filter { $0.deletedAt == nil && !$0.isArchived }
            if !activeChildren.isEmpty {
                alertMessage = L10n.management.management.categoryArchiveBlockedHasChildren
                return
            }
        }

        // 2. Check linked transactions
        let linkedTransactions = storedTransactions.filter { $0.deletedAt == nil && $0.category?.id == category.id }
        if !linkedTransactions.isEmpty {
            alertMessage = L10n.management.management.categoryArchiveBlockedHasTransactions
            return
        }

        // 3. Check linked budgets
        let linkedBudgets = storedBudgets.filter { $0.deletedAt == nil && $0.category?.id == category.id }
        if !linkedBudgets.isEmpty {
            alertMessage = L10n.management.management.categoryArchiveBlockedHasBudgets
            return
        }

        // 4. Check linked bills
        let linkedBills = storedBills.filter { $0.deletedAt == nil && $0.category?.id == category.id }
        if !linkedBills.isEmpty {
            alertMessage = L10n.management.management.categoryArchiveBlockedHasBills
            return
        }

        category.isArchived = true
        category.archivedAt = .now
        category.updatedAt = .now

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .category,
                recordID: category.id,
                modifiedAt: category.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.management.management.couldnTSaveTheArchiveState + " \(error.localizedDescription)"
        }
    }
```

**Step 3: Commit**
```bash
git add Mistia/Features/Management/ManagementEditors.swift
git commit -m "feat: enforce category archiving rules and add SwiftData checks"
```

---

### Task 4: Fix Add Member Button UI & Sheet Presenter
**Files:**
- Modify: [FamilyView.swift](file:///Users/quylang/Projects/mistia/Mistia/Features/Family/FamilyView.swift)

**Step 1: Increase tap target bounds in FamilyOverviewHeader**
Modify the invite button at line 1686:
```swift
                    if canInviteMembers {
                        Button(action: onInviteTap) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                                        .frame(width: 56, height: 56)

                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }

                                Text(L10n.family.family.invite)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
```

**Step 2: Relocate .sheet modifier in FamilyOverviewContent**
Attach `.sheet` directly to `FamilyOverviewHeader` in `FamilyOverviewContent`'s body:
```swift
        FamilyOverviewHeader(
            walletRows: data.walletRows,
            signedInUserID: sessionStore.signedInUserID,
            canInviteMembers: familyContextStore.canInviteMembers,
            onInviteTap: { activeSheet = .invite }
        )
        .padding(.top, 8)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .invite:
                FamilyInviteSheet()
            case .filterTransactions:
                FamilyTransactionFilterSheet()
            }
        }
```
And remove the duplicate `.sheet` call at the bottom of the body (lines 2484–2491).

**Step 3: Commit**
```bash
git add Mistia/Features/Family/FamilyView.swift
git commit -m "fix: resolve family add member button tap hit test and sheet presentation"
```

---

### Task 5: Update Diapers / Milk Category Translations
**Files:**
- Modify: [MistiaSystemCategories.json](file:///Users/quylang/Projects/mistia/Mistia/Shared/CoreLogic/MistiaSystemCategories.json)
- Modify: [20260521224709_normalize_category_language_records.sql](file:///Users/quylang/Projects/mistia/supabase/migrations/20260521224709_normalize_category_language_records.sql)

**Step 1: Edit JSON category translations**
Modify category `diapers_milk` in `MistiaSystemCategories.json` to change the translations to:
```json
        "translations" : {
          "en" : "Diapers",
          "ja" : "おむつ",
          "vi" : "Bỉm / tã"
        }
```

**Step 2: Edit seed migration file**
Update line 65 of `20260521224709_normalize_category_language_records.sql` to match these translations:
```sql
  ('diapers_milk', 'Bỉm / tã', 'Diapers', 'おむつ', 9),
```

**Step 3: Commit**
```bash
git add Mistia/Shared/CoreLogic/MistiaSystemCategories.json supabase/migrations/20260521224709_normalize_category_language_records.sql
git commit -m "fix: translate diapers_milk category correctly to diapers and おむつ"
```

---

### Task 6: Build Verification
**Step 1: Run swift build & test**
Run: `swift build` and `swift test`
Expected: Compiles with 0 warnings/errors and all tests pass.
