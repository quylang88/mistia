import Foundation
import XCTest
@testable import MistiaCoreLogic

final class InvestmentProductImageStoreTests: XCTestCase {
    func testReplacementIsCachedAndQueuedForIdempotentUpload() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InvestmentProductImageStore(baseDirectory: directory)

        let path = try store.stageReplacement(
            ownerUserID: UUID(),
            assetID: UUID(),
            jpegData: Data([1, 2, 3]),
            thumbnailData: Data([4, 5]),
            replacing: nil
        )

        XCTAssertEqual(try store.cachedImageData(for: path), Data([1, 2, 3]))
        XCTAssertEqual(try store.cachedThumbnailData(for: path), Data([4, 5]))
        XCTAssertEqual(try store.uploadData(for: path), Data([1, 2, 3]))
        try store.markUploadSucceeded(for: path)
        XCTAssertNil(try store.uploadData(for: path))
        XCTAssertEqual(try store.cachedImageData(for: path), Data([1, 2, 3]))
    }

    func testReplacementDeletesOldObjectOnlyAfterRemoteConfirmation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InvestmentProductImageStore(baseDirectory: directory)
        let ownerID = UUID()
        let assetID = UUID()
        let oldPath = try store.stageReplacement(
            ownerUserID: ownerID,
            assetID: assetID,
            jpegData: Data([1]),
            thumbnailData: Data([1]),
            replacing: nil
        )
        try store.markUploadSucceeded(for: oldPath)

        _ = try store.stageReplacement(
            ownerUserID: ownerID,
            assetID: assetID,
            jpegData: Data([2]),
            thumbnailData: Data([2]),
            replacing: oldPath
        )

        XCTAssertTrue(try store.pendingDeletionPaths().isEmpty)
        try store.markAssetUpdateSucceeded(assetID: assetID)
        XCTAssertEqual(try store.pendingDeletionPaths(), [oldPath])
        XCTAssertNotNil(try store.cachedImageData(for: oldPath))
        try store.markDeletionSucceeded(for: oldPath)
        XCTAssertTrue(try store.pendingDeletionPaths().isEmpty)
        XCTAssertNil(try store.cachedImageData(for: oldPath))
    }

    func testRemovingNeverUploadedImageDoesNotQueueCloudDeletion() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InvestmentProductImageStore(baseDirectory: directory)
        let assetID = UUID()
        let path = try store.stageReplacement(
            ownerUserID: UUID(),
            assetID: assetID,
            jpegData: Data([1]),
            thumbnailData: Data([1]),
            replacing: nil
        )

        try store.stageRemoval(assetID: assetID, path: path)

        XCTAssertNil(try store.uploadData(for: path))
        XCTAssertTrue(try store.pendingDeletionPaths().isEmpty)
        XCTAssertNil(try store.cachedImageData(for: path))
    }

    func testReplacingPendingOfflineImageDiscardsSupersededUpload() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InvestmentProductImageStore(baseDirectory: directory)
        let ownerID = UUID()
        let assetID = UUID()
        let firstPath = try store.stageReplacement(
            ownerUserID: ownerID,
            assetID: assetID,
            jpegData: Data([1]),
            thumbnailData: Data([1]),
            replacing: nil
        )

        let secondPath = try store.stageReplacement(
            ownerUserID: ownerID,
            assetID: assetID,
            jpegData: Data([2]),
            thumbnailData: Data([2]),
            replacing: firstPath
        )

        XCTAssertNil(try store.uploadData(for: firstPath))
        XCTAssertNil(try store.cachedImageData(for: firstPath))
        XCTAssertEqual(try store.uploadData(for: secondPath), Data([2]))
        XCTAssertTrue(try store.pendingDeletionPaths().isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "mistia-investment-images-\(UUID().uuidString.lowercased())", directoryHint: .isDirectory)
    }
}
