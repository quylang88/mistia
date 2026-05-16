import Foundation

struct TransactionCategoryGroupSection: Identifiable {
    let parent: TransactionCategory
    let children: [TransactionCategory]

    var id: UUID { parent.id }
}

enum MistiaCategoryHierarchy {
    static func defaultParentKey(for systemKey: MistiaSystemCategoryKey) -> MistiaSystemCategoryParentKey {
        systemKey.parentKey ?? uncategorizedParentKey(for: systemKey.kind)
    }

    static func uncategorizedParentKey(for kind: TransactionCategoryKind) -> MistiaSystemCategoryParentKey {
        switch kind {
        case .expense:
            .expenseOther
        case .income:
            .incomeOther
        }
    }

    static func parentCategories(
        from categories: [TransactionCategory],
        kind: TransactionCategoryKind,
        includeArchived: Bool = false
    ) -> [TransactionCategory] {
        categories
            .filter {
                $0.deletedAt == nil
                    && (includeArchived || !$0.isArchived)
                    && $0.kind == kind
                    && $0.isParentCategory
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func childCategories(
        from categories: [TransactionCategory],
        kind: TransactionCategoryKind,
        includeArchived: Bool = false
    ) -> [TransactionCategory] {
        categories
            .filter {
                $0.deletedAt == nil
                    && (includeArchived || !$0.isArchived)
                    && $0.kind == kind
                    && $0.isChildCategory
                    && !$0.isBalanceAdjustmentSystemCategory
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func groupedSections(
        from categories: [TransactionCategory],
        kind: TransactionCategoryKind,
        includeArchived: Bool = false,
        includeEmptyParents: Bool = true
    ) -> [TransactionCategoryGroupSection] {
        let parents = parentCategories(
            from: categories,
            kind: kind,
            includeArchived: includeArchived
        )
        let childrenByParentID = Dictionary(grouping: childCategories(
            from: categories,
            kind: kind,
            includeArchived: includeArchived
        )) { $0.parentCategory?.id }

        return parents.compactMap { parent in
            let children = childrenByParentID[parent.id]?.sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            } ?? []
            let parentSystemKey = parent.systemKey.flatMap(MistiaSystemCategoryParentKey.init(rawValue:))
            let hidesWhenEmpty = parentSystemKey?.showsOnlyWhenHasChildren == true
            if children.isEmpty && (!includeEmptyParents || hidesWhenEmpty) {
                return nil
            }
            return TransactionCategoryGroupSection(parent: parent, children: children)
        }
    }

    static func categorySort(lhs: TransactionCategory, rhs: TransactionCategory) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }
}


extension TransactionCategory {
    var isParentCategory: Bool {
        hierarchyRole == .parent && parentCategory == nil
    }

    var isChildCategory: Bool {
        hierarchyRole == .child || parentCategory != nil
    }

    var branchCategoryID: UUID {
        parentCategory?.id ?? id
    }

    var branchIconSymbolName: String {
        parentCategory?.iconSymbolName ?? iconSymbolName
    }

    var branchColorHex: String {
        parentCategory?.iconColorHex ?? iconColorHex
    }

    var branchDisplayName: String {
        parentCategory?.mistiaHierarchyDisplayName ?? mistiaHierarchyDisplayName
    }

    var isBalanceAdjustmentSystemCategory: Bool {
        if id == MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID ||
            id == MistiaSystemCategoryIdentity.balanceAdjustmentIncomeID {
            return true
        }

        return systemKey == MistiaSystemCategoryKey.balanceAdjustmentExpense.rawValue ||
            systemKey == MistiaSystemCategoryKey.balanceAdjustmentIncome.rawValue
    }

    func canAssignParent(_ candidate: TransactionCategory?) -> Bool {
        guard let candidate else { return true }
        guard candidate.id != id else { return false }
        guard candidate.parentCategory == nil else { return false }
        guard candidate.kind == kind else { return false }
        guard candidate.parentCategory?.id != id else { return false }
        return true
    }
}

private extension TransactionCategory {
    var mistiaHierarchyDisplayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let systemKey,
           let parentKey = MistiaSystemCategoryParentKey(rawValue: systemKey),
           Set(parentKey.knownDefaultNames()).contains(trimmedName) {
            return parentKey.localizedTitle(for: .current)
        }

        if let systemKey,
           let categoryKey = MistiaSystemCategoryKey(rawValue: systemKey),
           Set(categoryKey.knownDefaultNames()).contains(trimmedName) {
            return categoryKey.localizedTitle(for: .current)
        }

        return name
    }
}
