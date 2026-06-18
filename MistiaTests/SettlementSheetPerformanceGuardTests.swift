import XCTest

final class SettlementSheetPerformanceGuardTests: XCTestCase {
    func testDraftBillRowsDoNotEagerlyBuildAttachableTransactionList() throws {
        let source = try settlementSheetsSource()

        XCTAssertFalse(
            source.contains("existingTransactions: attachableExpenseTransactions"),
            "Draft bill rows must not receive the full attachable transaction list; that forces an expensive history filter when opening a draft expense sheet."
        )
    }

    func testExistingExpenseSearchBuildsAttachableTransactionsOnceForPresentation() throws {
        let source = try settlementSheetsSource()
        let sheetBuilder = try XCTUnwrap(
            source.range(of: #".sheet(item: $billSearchTarget"#)
        )
        let sheetEnd = try XCTUnwrap(
            source[sheetBuilder.lowerBound...].range(of: #".presentationDetents([.large])"#)
        )
        let sheetSource = String(source[sheetBuilder.lowerBound..<sheetEnd.upperBound])
        let eagerReferences = sheetSource.components(separatedBy: "attachableExpenseTransactions").count - 1

        XCTAssertLessThanOrEqual(
            eagerReferences,
            1,
            "Opening existing-expense search should not repeatedly compute the full attachable transaction list in the sheet builder."
        )
    }

    private func settlementSheetsSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Mistia")
            .appendingPathComponent("Features")
            .appendingPathComponent("Transactions")
            .appendingPathComponent("SettlementSheets.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
