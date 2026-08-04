import Foundation
import XCTest
@testable import Mistia

final class AvatarSyncCacheTests: XCTestCase {
    private var fileManager: FileManager!
    private var avatarDirURL: URL!

    override func setUp() {
        super.setUp()
        fileManager = .default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        avatarDirURL = appSupport.appendingPathComponent("ProfileAvatars", isDirectory: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: avatarDirURL)
        super.tearDown()
    }

    func testSaveRemoteAvatarDataStoresImageAndSourceURL() throws {
        let userID = UUID()
        let sampleData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let sourceURL = URL(string: "https://example.com/storage/profile-avatars/\(userID)/avatar.jpg?t=100")!

        let fileName = try MistiaProfileAvatarCache.saveRemoteAvatarImageData(
            sampleData,
            mimeType: "image/jpeg",
            sourceURL: sourceURL,
            for: userID
        )

        XCTAssertEqual(fileName, "\(userID.uuidString.lowercased()).jpg")
        let cachedURL = try XCTUnwrap(MistiaProfileAvatarCache.cachedAvatarURL(for: userID))
        XCTAssertTrue(cachedURL.isFileURL)

        let fileData = try Data(contentsOf: cachedURL)
        XCTAssertEqual(fileData, sampleData)
    }

    func testCacheRemoteAvatarIfNeededReturnsExistingWhenURLMatches() async throws {
        let userID = UUID()
        let sampleData = Data([0x01, 0x02, 0x03])
        let sourceURL = URL(string: "https://example.com/avatar.jpg?t=200")!

        _ = try MistiaProfileAvatarCache.saveRemoteAvatarImageData(
            sampleData,
            mimeType: "image/jpeg",
            sourceURL: sourceURL,
            for: userID
        )

        let cachedURL = await MistiaProfileAvatarCache.cacheRemoteAvatarIfNeeded(
            from: sourceURL,
            for: userID
        )

        XCTAssertNotNil(cachedURL)
        XCTAssertTrue(cachedURL?.isFileURL == true)
    }
}
