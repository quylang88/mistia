# Design Document: Family UI Fixes, Category Archiving Restrictions, and Translation Updates

## Overview
This design addresses:
1. UI responsiveness of the family overview "Add Member" button.
2. Prevention of archiving categories linked to active child categories, or any transactions, budgets, or bills in the database.
3. Accurate translations of the "Bỉm tã" (diapers_milk) category to English and Japanese.
4. Simplified Japanese shortcut title and description.
5. Extraction and implementation of all alert and notification strings into `Localizable.xcstrings` and `L10n.generated.swift`.

---

## Detailed Design

### 1. Add Member Button UI & Sheet Presenter
- **Responsive Hit Target:** Add `.contentShape(Rectangle())` to the plain invite button `VStack` in `FamilyOverviewHeader` inside `FamilyView.swift` to ensure the entire region responds immediately to touch gestures.
- **Active Sheet Presenter:** Move the `.sheet(item: $activeSheet)` modifier from `FamilyMonthlyBillListSection` to `FamilyOverviewHeader` inside the `FamilyOverviewContent` view. This guarantees that the sheet is attached to a component that is always rendered when the overview is visible.

### 2. Category Archiving Validation Logic
- Add `@Query private var storedTransactions: [LedgerTransaction]` to `ManagementCategoryEditorSheet` in `ManagementEditors.swift`.
- Modify `archiveCategory()` to enforce the following restriction sequence:
  1. **Subcategories:** If category is a parent and has any child category in `storedCategories` where `deletedAt == nil && !isArchived`, block archiving with `categoryArchiveBlockedHasChildren`.
  2. **Transactions:** If there are any non-deleted transactions linked to the category (`$0.category?.id == category.id`), block archiving with `categoryArchiveBlockedHasTransactions`.
  3. **Budgets:** If there are any non-deleted budgets linked to the category (`$0.category?.id == category.id`), block archiving with `categoryArchiveBlockedHasBudgets`.
  4. **Bills:** If there are any non-deleted recurring bills linked to the category (`$0.category?.id == category.id`), block archiving with `categoryArchiveBlockedHasBills`.

### 3. Translation Updates
- **Category `diapers_milk`:**
  - Update English translation to `"Diapers"` and Japanese translation to `"おむつ"` in `MistiaSystemCategories.json` and in `20260521224709_normalize_category_language_records.sql`.
- **Mistia Shortcut:**
  - Update Japanese localization values for `settings.shortcut.title` to `"ショートカット"` and `settings.shortcut.description` to `"ショートカットを有効にするとタブバーに固定ボタンが表示されます。選んだ項目を直接開きます。"` in `Localizable.xcstrings`.

### 4. Localization Keys
- Add the following keys to `Mistia/Localizable.xcstrings`:
  - `management.management.categoryArchiveBlockedHasChildren`
  - `management.management.categoryArchiveBlockedHasTransactions`
  - `management.management.categoryArchiveBlockedHasBudgets`
  - `management.management.categoryArchiveBlockedHasBills`
- Run the localized generation script `generate-l10n.swift` to update `L10n.generated.swift`.

---

## Verification
- Run Swift build and test:
  ```bash
  swift build
  swift test
  ```
