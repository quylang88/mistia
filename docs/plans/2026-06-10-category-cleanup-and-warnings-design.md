# Design Document: Category Cleanup, Translation Fixes, and Warning Resolution

## Overview
This design resolves strict concurrency warnings in `FinanceEnums.swift` and `MistiaSystemCategoryIdentity.swift` under Swift 6 checking, removes the temporary `test_dynamic_pizza` category, reorders system categories in `MistiaSystemCategories.json` to prioritize essential categories, and refines translations for Vietnamese and Japanese locales.

## Design Details

### 1. Concurrency Warning Resolution (Approach A)
- **Problem**: 26 compiler warnings are generated because `MistiaSystemCategoryRegistry` is implicitly treated as `@MainActor` (as a class in the app target), but its static `shared` instance and lookup methods are accessed synchronously from the `nonisolated` enums `MistiaSystemCategoryParentKey` and `MistiaSystemCategoryKey` as well as the utility `MistiaSystemCategoryIdentity`.
- **Solution**: 
  - Mark `MistiaSystemCategoryRegistry.shared` as `nonisolated static let shared`.
  - Mark all instance properties and methods of `MistiaSystemCategoryRegistry` as `nonisolated`.
  - Mark `ParsedSystemCategory` methods as `nonisolated`.
  - This allows callers to query categories from background and UI threads safely.

### 2. Category JSON Updates (`MistiaSystemCategories.json`)
- **Pizza Removal**: Remove `test_dynamic_pizza` block completely.
- **Reordering**:
  - Move `grocery` (`grocery`) to the first slot of children under `parent_expense_food`.
  - Ensure that general "Khác" (other) child categories and `parent_expense_uncategorized` are at the end of their respective parent/children lists.
- **Vietnamese translation adjustment**:
  - `child_extracurricular` (id: `child_extracurricular`): "Hoạt động ngoại khóa" -> "Hoạt động vui chơi"
- **Japanese translation adjustment**:
  - Parent: `parent_expense_cost_of_goods` (id: `parent_expense_cost_of_goods`): "仕入れ" -> "仕入高"
  - Child: `import_goods` (id: `import_goods`): "仕入れ" -> "仕入れ" (remain as is, to differentiate parent and child).

### 3. Test Cleanup
- Clean up test cases referencing `test_dynamic_pizza` in `MistiaSystemCategorySyncSupportTests.swift` and `MistiaSystemCategoryIdentityTests.swift`.

## Verification
- Compile code using `swift build` and `xcodebuild` targeting Simulator to ensure zero compiler warnings.
- Run tests (`swift test`) to ensure functionality is intact.
