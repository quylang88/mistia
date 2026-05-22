import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class MistiaMigrationPlanTests: XCTestCase {
    func testV4StoreOpensWithoutDuplicateVersionChecksums() throws {
        let storeURL = temporaryStoreURL()
        defer { try? removeStoreArtifacts(at: storeURL) }

        let billID = UUID()
        try createCurrentV4Store(at: storeURL, billID: billID)

        let container = try openCurrentStore(at: storeURL)
        let context = ModelContext(container)
        let bills = try context.fetch(FetchDescriptor<RecurringBillPlan>())

        XCTAssertEqual(bills.map(\.id), [billID])
        XCTAssertEqual(bills.first?.name, "Internet")
        XCTAssertEqual(bills.first?.scheduleKind, .recurring)
        XCTAssertEqual(bills.first?.resolvedPaymentStartDay, 12)
        XCTAssertFalse(bills.first?.resolvedHasExplicitDueDate ?? true)

        bills.first?.autoPayEnabled = true
        bills.first?.autoPayDay = 10
        try context.save()

        let reopenedContainer = try openCurrentStore(at: storeURL)
        let reopenedBills = try ModelContext(reopenedContainer).fetch(FetchDescriptor<RecurringBillPlan>())
        XCTAssertEqual(reopenedBills.first?.autoPayEnabled, true)
        XCTAssertEqual(reopenedBills.first?.autoPayDay, 10)
    }

    func testMigrationPlanDoesNotAddDuplicateV5() {
        let schemaNames = MistiaMigrationPlan.schemas.map { String(reflecting: $0) }

        XCTAssertEqual(schemaNames.count, Set(schemaNames).count)
        XCTAssertEqual(schemaNames, ["MistiaCoreLogic.MistiaSchemaV4"])
        XCTAssertTrue(MistiaMigrationPlan.stages.isEmpty)
        XCTAssertFalse(
            schemaNames.contains { $0.contains("MistiaSchemaV5") },
            "Do not add V5 unless SwiftData produces a distinct schema checksum; duplicate checksums crash before the container opens."
        )
    }

    private func createCurrentV4Store(at storeURL: URL, billID: UUID) throws {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            RecurringBillPlan(
                id: billID,
                name: "Internet",
                iconSymbolName: "wifi",
                amountMinor: 4_200,
                dueDay: 12,
                frequencyMonths: 1
            )
        )
        try context.save()
    }

    private func openCurrentStore(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV4.self)
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)

        return try ModelContainer(
            for: schema,
            migrationPlan: MistiaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "mistia-migration-\(UUID().uuidString.lowercased())")
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
