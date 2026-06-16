# Category Cleanup and Concurrency Warnings Resolution Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Clean up the JSON categories, update translations, reorder elements, and resolve 26 concurrency compilation warnings in Swift files by making the registry APIs nonisolated.

**Architecture:** Use explicit `nonisolated` annotations on `MistiaSystemCategoryRegistry` and `ParsedSystemCategory` read-only APIs to allow thread-safe lookup from non-actor-isolated enums and identities. Modify the categories JSON directly, reordering the elements to match user specifications.

**Tech Stack:** Swift, Swift Concurrency, Xcode, SPM

---

### Task 1: Update JSON Category Database (`MistiaSystemCategories.json`)

**Files:**
- Modify: [MistiaSystemCategories.json](file:///Users/quylang/Projects/mistia/Mistia/Shared/CoreLogic/MistiaSystemCategories.json)

**Step 1: Write the failing test**
Run tests before modification. Since tests currently verify the presence of `test_dynamic_pizza`, we will update the JSON first.
Wait, let's first prepare the modified JSON structure.

**Step 2: Modify JSON contents**
1. Delete the JSON object for `test_dynamic_pizza` under `parent_expense_food` children.
2. Move the `grocery` category to the first position of the `children` array under `parent_expense_food`.
3. In `parent_expense_family_children` children, change the Vietnamese translation for `child_extracurricular` (id: `child_extracurricular`) from `"Hoạt động ngoại khóa"` to `"Hoạt động vui chơi"`.
4. Differentiate the Japanese translations:
   - For `parent_expense_cost_of_goods` (parent): Change `"ja": "仕入れ"` to `"ja": "仕入高"`.
   - For `import_goods` (child): Keep `"ja": "仕入れ"`.
5. Verify that `other_expense` / `parent_expense_uncategorized` elements are at the end of their respective lists.

**Step 3: Run verify command**
Validate that the JSON is still valid by running `swift test`.
Expected: `testDynamicJSONCategoryDescriptorLoading` fails or errors out because `test_dynamic_pizza` was removed.

**Step 4: Commit**
```bash
git add Mistia/Shared/CoreLogic/MistiaSystemCategories.json
git commit -m "chore: clean up pizza category, fix translations, and reorder categories in JSON"
```

---

### Task 2: Make Category Registry APIs `nonisolated`

**Files:**
- Modify: [MistiaSystemCategoryRegistry.swift](file:///Users/quylang/Projects/mistia/Mistia/Shared/CoreLogic/MistiaSystemCategoryRegistry.swift)

**Step 1: Modify `MistiaSystemCategoryRegistry.swift`**
Add `nonisolated` keyword to the static property `shared`, class properties, and instance methods:
- `nonisolated static let shared = MistiaSystemCategoryRegistry()`
- `nonisolated let allParents: [ParsedSystemCategory]`
- `nonisolated func category(for id: String) -> ParsedSystemCategory?`
- `nonisolated func parentId(for childId: String) -> String?`
- `nonisolated func allActiveParents() -> [ParsedSystemCategory]`
- `nonisolated func children(forParentId parentId: String) -> [ParsedSystemCategory]`
- `nonisolated func metadata(forId id: String) -> ParsedSystemCategory?`
And in `ParsedSystemCategory` struct:
- `nonisolated func kind(in registry: MistiaSystemCategoryRegistry) -> TransactionCategoryKind`
- `nonisolated func localizedTitle(for language: MistiaAppLanguage) -> String`
- `nonisolated func knownDefaultNames() -> [String]`

**Step 2: Run verification**
Compile the app using `xcodebuild -scheme Mistia -destination "platform=iOS Simulator,name=iPhone 17" -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`.
Expected: The 26 warnings in `FinanceEnums.swift` and `MistiaSystemCategoryIdentity.swift` are successfully resolved!

**Step 3: Commit**
```bash
git add Mistia/Shared/CoreLogic/MistiaSystemCategoryRegistry.swift
git commit -m "fix: mark registry and parsed category lookups as nonisolated to fix 26 compiler warnings"
```

---

### Task 3: Clean up test references to `test_dynamic_pizza`

**Files:**
- Modify: [MistiaSystemCategorySyncSupportTests.swift](file:///Users/quylang/Projects/mistia/MistiaTests/MistiaSystemCategorySyncSupportTests.swift)
- Modify: [MistiaSystemCategoryIdentityTests.swift](file:///Users/quylang/Projects/mistia/Tests/MistiaCoreLogicTests/MistiaSystemCategoryIdentityTests.swift)

**Step 1: Modify tests**
- Delete `testEnsureSystemCategoryCreatesRecordForDynamicJSONCategory` in `MistiaSystemCategorySyncSupportTests.swift` (or the lines testing `test_dynamic_pizza`).
- Delete `testDynamicJSONCategoryDescriptorLoading` in `MistiaSystemCategoryIdentityTests.swift` (which queries `test_dynamic_pizza`).

**Step 2: Run tests**
Run `swift test`.
Expected: All package tests compile and run successfully (no failures for category tests).

**Step 3: Commit**
```bash
git add MistiaTests/MistiaSystemCategorySyncSupportTests.swift Tests/MistiaCoreLogicTests/MistiaSystemCategoryIdentityTests.swift
git commit -m "test: remove obsolete dynamic pizza category assertions from tests"
```

---

### Task 4: Final Verification

**Step 1: Compile and verify warnings**
Run `xcodebuild -scheme Mistia -destination "platform=iOS Simulator,name=iPhone 17" -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` and ensure there are no new warnings.

**Step 2: Verify git status**
Run `git status` to ensure all changes are clean and committed.
