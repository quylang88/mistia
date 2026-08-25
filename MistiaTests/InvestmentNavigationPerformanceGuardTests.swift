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

    func testSyncReconcilesOnlyTradeRowsAcceptedByConflictChecks() throws {
        let source = try sharedSource(relativePath: "Sync/MistiaSyncLocalStore.swift")
        let loopStart = try XCTUnwrap(source.range(of: "for row in snapshot.investmentTrades"))
        let postingStart = try XCTUnwrap(
            source[loopStart.lowerBound...].range(of: "for row in snapshot.investmentPostings")
        )
        let block = String(source[loopStart.lowerBound..<postingStart.lowerBound])
        let guardRange = try XCTUnwrap(block.range(of: "guard shouldApplyRemoteRow("))
        let insertRange = try XCTUnwrap(
            block.range(of: "appliedInvestmentAssetIDs.insert(row.assetID)")
        )

        XCTAssertLessThan(guardRange.lowerBound, insertRange.lowerBound)
        XCTAssertFalse(block.contains("snapshot.investmentTrades.isEmpty"))
        XCTAssertFalse(block.contains("reconcileAllTrades"))
        XCTAssertTrue(source.contains("assetIDs: [row.assetID]"))
    }

    func testReconciliationUsesFixedPrivacySafePerformanceSignposts() throws {
        let source = try sharedSource(relativePath: "Persistence/InvestmentPersistence.swift")

        XCTAssertTrue(source.contains("category: \"InvestmentPerformance\""))
        XCTAssertTrue(source.contains("\"Investment Targeted Reconciliation\""))
        XCTAssertTrue(source.contains("\"Investment Full Reconciliation\""))
        XCTAssertTrue(source.contains("assets=%{public}d trades=%{public}d"))
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

    private func sharedSource(relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot
                .appendingPathComponent("Mistia")
                .appendingPathComponent("Shared")
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
