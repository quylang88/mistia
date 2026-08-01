import Foundation
import SwiftData
import XCTest
@testable import Mistia

final class PlanningBudgetSnapshotMaintenanceTests: XCTestCase {
    @MainActor
    func testPopulateMissingCategorySnapshotsOnlyUpdatesEligibleBudgets() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let category = TransactionCategory(
            name: "Groceries",
            nameEnglish: "Groceries",
            nameJapanese: "食料品",
            kind: .expense,
            iconSymbolName: "cart.fill",
            iconColorHex: "#00AA66",
            hierarchyRole: .child
        )
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let completeBudget = BudgetPlan(
            category: category,
            categoryIDSnapshot: category.id,
            categoryNameSnapshot: category.name,
            monthAnchor: originalUpdatedAt,
            limitMinor: 50_000,
            updatedAt: originalUpdatedAt
        )
        let missingSnapshotBudget = BudgetPlan(
            category: category,
            monthAnchor: originalUpdatedAt,
            limitMinor: 60_000,
            updatedAt: originalUpdatedAt
        )
        let deletedBudget = BudgetPlan(
            category: category,
            monthAnchor: originalUpdatedAt,
            limitMinor: 70_000,
            updatedAt: originalUpdatedAt,
            deletedAt: originalUpdatedAt
        )
        let missingCategoryBudget = BudgetPlan(
            monthAnchor: originalUpdatedAt,
            limitMinor: 80_000,
            updatedAt: originalUpdatedAt
        )

        context.insert(category)
        context.insert(completeBudget)
        context.insert(missingSnapshotBudget)
        context.insert(deletedBudget)
        context.insert(missingCategoryBudget)
        try context.save()

        let mutations = try PlanningBudgetSnapshotMaintenance.populateMissingCategorySnapshots(
            modelContext: context
        )

        XCTAssertEqual(mutations.map(\.recordID), [missingSnapshotBudget.id])
        XCTAssertEqual(missingSnapshotBudget.categoryIDSnapshot, category.id)
        XCTAssertEqual(missingSnapshotBudget.categoryNameSnapshot, category.name)
        XCTAssertGreaterThan(missingSnapshotBudget.updatedAt, originalUpdatedAt)
        XCTAssertEqual(completeBudget.updatedAt, originalUpdatedAt)
        XCTAssertNil(deletedBudget.categoryIDSnapshot)
        XCTAssertEqual(deletedBudget.updatedAt, originalUpdatedAt)
        XCTAssertNil(missingCategoryBudget.categoryIDSnapshot)
        XCTAssertEqual(missingCategoryBudget.updatedAt, originalUpdatedAt)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
