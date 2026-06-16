import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaMigrationCompatibilityTests: XCTestCase {
    func testOldV5TopLevelTransactionStoreOpensThroughDataStackRoute() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }
        try copyFixtureStore(
            named: "old-v5-top-level-ledger-transaction",
            to: storeURL
        )

        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try MistiaDataStack.LaunchState.openContainer(
            schema: schema,
            configuration: configuration,
            storeURL: storeURL,
            fileManager: .default
        )
        let transactions = try ModelContext(container).fetch(FetchDescriptor<LedgerTransaction>())

        XCTAssertEqual(transactions.map(\.title), ["Old lunch"])
        XCTAssertNil(transactions.first?.settlementGroupID)
        XCTAssertNil(transactions.first?.settlementObligationID)
        XCTAssertNil(transactions.first?.settlementRole)
        XCTAssertNil(transactions.first?.reportingExpenseMinor)
        XCTAssertNil(transactions.first?.reportingIncomeMinor)
    }

    private func copyFixtureStore(named fixtureName: String, to storeURL: URL) throws {
        let sourceURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: fixtureName,
                withExtension: "store",
                subdirectory: "Fixtures"
            )
        )
        try FileManager.default.copyItem(at: sourceURL, to: storeURL)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "mistia-migration-compat-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("store")
    }

    private func removeStoreArtifacts(at storeURL: URL) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
