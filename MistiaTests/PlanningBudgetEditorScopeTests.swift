import XCTest
@testable import Mistia

final class PlanningBudgetEditorScopeTests: XCTestCase {
    func testVisibleCategoriesOnlyIncludeTargetOwnerCatalog() {
        let selfUserID = UUID()
        let memberUserID = UUID()
        let selfCategory = makeCategory(name: "Self food")
        let memberCategory = makeCategory(name: "Member food")

        let visibleCategories = PlanningBudgetEditorScope.visibleCategories(
            [selfCategory, memberCategory],
            categoryOwnerMap: [memberCategory.id: memberUserID],
            targetOwnerUserID: selfUserID,
            signedInUserID: selfUserID
        )

        XCTAssertEqual(visibleCategories.map(\.id), [selfCategory.id])
    }

    func testVisibleBudgetsOnlyIncludeTargetOwnerPlans() {
        let selfUserID = UUID()
        let memberUserID = UUID()
        let selfBudget = BudgetPlan(
            category: makeCategory(name: "Self budget"),
            monthAnchor: Date(timeIntervalSince1970: 1_770_000_000),
            limitMinor: 10_000
        )
        let memberBudget = BudgetPlan(
            category: makeCategory(name: "Member budget"),
            monthAnchor: Date(timeIntervalSince1970: 1_770_000_000),
            limitMinor: 20_000
        )

        let visibleBudgets = PlanningBudgetEditorScope.visibleBudgets(
            [selfBudget, memberBudget],
            budgetOwnerMap: [memberBudget.id: memberUserID],
            targetOwnerUserID: selfUserID,
            signedInUserID: selfUserID
        )

        XCTAssertEqual(visibleBudgets.map(\.id), [selfBudget.id])
    }

    private func makeCategory(name: String) -> TransactionCategory {
        TransactionCategory(
            name: name,
            kind: .expense,
            iconSymbolName: "fork.knife",
            iconColorHex: "#2DAA9E",
            hierarchyRole: .child
        )
    }
}
