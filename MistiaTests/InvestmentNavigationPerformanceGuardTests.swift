import XCTest

final class InvestmentNavigationPerformanceGuardTests: XCTestCase {
    func testTabAndInvestmentAppearanceHooksDoNotRunAccountingReconciliation() throws {
        for relativePath in [
            "Investment/InvestmentHubView.swift",
            "Management/ManagementView.swift"
        ] {
            let source = try featureSource(relativePath: relativePath)
            XCTAssertFalse(
                source.contains("InvestmentPersistenceService.reconcileAllTrades"),
                "\(relativePath) must not run full Investment reconciliation from navigation or appearance hooks."
            )
        }
    }

    private func featureSource(relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot
                .appendingPathComponent("Mistia")
                .appendingPathComponent("Features")
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
