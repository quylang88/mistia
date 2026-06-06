import Foundation
import SwiftData
import XCTest
@testable import MistiaCoreLogic

@MainActor
final class TransactionReceiptImageStoreTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }

    func testAttachReceiptStoresFilesAndMetadata() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transaction = makeTransaction()
        context.insert(transaction)
        try context.save()

        let store = makeStore()
        let receipt = try store.replaceReceipt(
            for: transaction.id,
            imageData: Data("full-image".utf8),
            thumbnailData: Data("thumb".utf8),
            context: context
        )

        XCTAssertEqual(receipt.transactionID, transaction.id)
        XCTAssertEqual(receipt.byteCount, Data("full-image".utf8).count)
        XCTAssertEqual(try store.imageData(for: receipt), Data("full-image".utf8))
        XCTAssertEqual(try store.thumbnailData(for: receipt), Data("thumb".utf8))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TransactionReceiptImage>()).count, 1)
    }

    func testReplaceReceiptDeletesOldFiles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transaction = makeTransaction()
        context.insert(transaction)
        try context.save()

        let store = makeStore()
        let oldReceipt = try store.replaceReceipt(
            for: transaction.id,
            imageData: Data("old-image".utf8),
            thumbnailData: Data("old-thumb".utf8),
            context: context
        )
        let oldImageURL = store.url(forFileName: oldReceipt.imageFileName)
        let oldThumbnailURL = store.url(forFileName: oldReceipt.thumbnailFileName)

        let newReceipt = try store.replaceReceipt(
            for: transaction.id,
            imageData: Data("new-image".utf8),
            thumbnailData: Data("new-thumb".utf8),
            context: context
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldImageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldThumbnailURL.path))
        XCTAssertEqual(try store.imageData(for: newReceipt), Data("new-image".utf8))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TransactionReceiptImage>()).count, 1)
    }

    func testRemoveReceiptDeletesFilesAndMetadata() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transaction = makeTransaction()
        context.insert(transaction)
        try context.save()

        let store = makeStore()
        let receipt = try store.replaceReceipt(
            for: transaction.id,
            imageData: Data("full-image".utf8),
            thumbnailData: Data("thumb".utf8),
            context: context
        )
        let imageURL = store.url(forFileName: receipt.imageFileName)

        try store.deleteReceipt(for: transaction.id, context: context)

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertNil(try store.receipt(for: transaction.id, context: context))
    }

    func testArchiveTransactionDoesNotDeleteReceipt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transaction = makeTransaction()
        context.insert(transaction)
        try context.save()

        let store = makeStore()
        let receipt = try store.replaceReceipt(
            for: transaction.id,
            imageData: Data("archived-image".utf8),
            thumbnailData: Data("archived-thumb".utf8),
            context: context
        )

        transaction.isArchived = true
        transaction.archivedAt = Date()
        try context.save()

        XCTAssertNotNil(try store.receipt(for: transaction.id, context: context))
        XCTAssertEqual(try store.imageData(for: receipt), Data("archived-image".utf8))
    }

    func testDeleteAllCleansReceiptFiles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let transaction = makeTransaction()
        context.insert(transaction)
        try context.save()

        let store = makeStore()
        let receipt = try store.replaceReceipt(
            for: transaction.id,
            imageData: Data("full-image".utf8),
            thumbnailData: Data("thumb".utf8),
            context: context
        )
        let imageURL = store.url(forFileName: receipt.imageFileName)

        try store.deleteAll(context: context)

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TransactionReceiptImage>()).count, 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeStore() -> TransactionReceiptImageStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "mistia-receipt-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        return TransactionReceiptImageStore(baseDirectory: directory)
    }

    private func makeTransaction() -> LedgerTransaction {
        LedgerTransaction(
            primaryKind: .expense,
            title: "Receipt",
            amountMinor: 1_000,
            occurredAt: Date()
        )
    }
}
