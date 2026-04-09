import Foundation

struct TransactionCategoryGroupSection: Identifiable {
    let parent: TransactionCategory
    let children: [TransactionCategory]

    var id: UUID { parent.id }
}

enum MistiaCategoryHierarchy {
    static func defaultParentKey(for systemKey: MistiaSystemCategoryKey) -> MistiaSystemCategoryParentKey {
        switch systemKey {
        case .food, .housing, .billing:
            .livingExpense
        case .transportation, .travel:
            .mobilityTravel
        case .shopping, .entertainment, .health, .education:
            .personalLifestyle
        case .loanRepayment:
            .financialObligations
        case .salary, .bonus, .freelance, .allowance:
            .workIncome
        case .investment, .refund, .bankInterest:
            .investmentReturn
        case .sales, .gift:
            .salesOther
        }
    }

    static func uncategorizedParentKey(for kind: TransactionCategoryKind) -> MistiaSystemCategoryParentKey {
        switch kind {
        case .expense:
            .uncategorizedExpense
        case .income:
            .uncategorizedIncome
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
            .sorted(by: categorySort)
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
            }
            .sorted(by: categorySort)
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
            let children = childrenByParentID[parent.id]?.sorted(by: categorySort) ?? []
            if !includeEmptyParents && children.isEmpty {
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
        parentCategory?.localizedDisplayName ?? localizedDisplayName
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
