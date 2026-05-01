import Foundation
import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class MistiaProfileHealTests: XCTestCase {

    var fileManager: FileManager!
    var userDefaults: UserDefaults!
    var profilesRootURL: URL!

    override func setUp() {
        super.setUp()
        fileManager = .default
        userDefaults = UserDefaults(suiteName: "MistiaProfileHealTests.\(UUID().uuidString)")

        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        profilesRootURL = applicationSupportURL.appendingPathComponent("profiles", isDirectory: true)

        // Clean up any existing test data
        try? fileManager.removeItem(at: profilesRootURL)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: profilesRootURL)
        userDefaults.removePersistentDomain(forName: "MistiaProfileHealTests")
        super.tearDown()
    }

    func testHealRegistryRecoversOrphanedProfile() throws {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let profileID = UUID()
        let cloudUserID = UUID()

        // 1. Create an orphaned profile directory and store
        let profileDir = profilesRootURL.appendingPathComponent(profileID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let storeURL = profileDir.appendingPathComponent("profile").appendingPathExtension("store")

        let configuration = ModelConfiguration("test", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let profile = UserAccountProfile(
            userID: cloudUserID,
            email: "heal@example.com",
            displayName: "Heal Me"
        )
        context.insert(profile)
        try context.save()

        // 2. Ensure Registry is empty in UserDefaults
        userDefaults.removeObject(forKey: MistiaAppStorageKey.localProfileDescriptors)

        // 3. Run bootstrap which should trigger healing
        let launchState = try MistiaDataStack.LaunchState(
            userDefaults: userDefaults,
            fileManager: fileManager
        )

        // 4. Verify healing
        XCTAssertEqual(launchState.profileDescriptors.count, 1)
        let recovered = try XCTUnwrap(launchState.profileDescriptors.first)
        XCTAssertEqual(recovered.id, profileID)
        XCTAssertEqual(recovered.kind, .cloudUser)
        XCTAssertEqual(recovered.cloudUserID, cloudUserID)
        XCTAssertEqual(launchState.activeProfileID, profileID)
    }

    func testHealRegistryWithMultipleOrphans() throws {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)

        // Create 2 orphaned profiles
        for i in 1...2 {
            let profileID = UUID()
            let profileDir = profilesRootURL.appendingPathComponent(profileID.uuidString.lowercased(), isDirectory: true)
            try fileManager.createDirectory(at: profileDir, withIntermediateDirectories: true)
            let storeURL = profileDir.appendingPathComponent("profile").appendingPathExtension("store")

            let configuration = ModelConfiguration("test\(i)", schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)

            if i == 1 {
                let profile = UserAccountProfile(userID: UUID(), email: "user1@ex.com", displayName: "User 1")
                context.insert(profile)
            }
            try context.save()
        }

        userDefaults.removeObject(forKey: MistiaAppStorageKey.localProfileDescriptors)

        let launchState = try MistiaDataStack.LaunchState(
            userDefaults: userDefaults,
            fileManager: fileManager
        )

        XCTAssertEqual(launchState.profileDescriptors.count, 2)
        XCTAssertTrue(launchState.profileDescriptors.contains(where: { $0.kind == .cloudUser }))
        XCTAssertTrue(launchState.profileDescriptors.contains(where: { $0.kind == .guestUnbound }))
    }
}
