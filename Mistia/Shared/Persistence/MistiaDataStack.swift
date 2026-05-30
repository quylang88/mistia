import Foundation
import Observation
import SwiftData

/// App storage keys for persistence (Package target version).
/// This is a subset to avoid dependency on UI target.
private enum MistiaPersistenceStorageKey {
    static let localModeProfileUserID = "mistia.local-mode.profile-user-id"
    static let localProfileDescriptors = "mistia.local-profile.descriptors"
    static let activeLocalProfileID = "mistia.local-profile.active-id"
}

enum MistiaDataStack {
    struct LaunchIssue: Error {
        let storeURL: URL?
        let underlyingErrorDescription: String
    }

    @Observable
    final class LaunchState {
        var modelContainer: ModelContainer
        var issue: LaunchIssue?

        private(set) var profileDescriptors: [MistiaLocalProfileDescriptor]
        private(set) var activeProfileID: UUID?

        private let schema: Schema
        private let userDefaults: UserDefaults
        private let fileManager: FileManager

        init(
            userDefaults: UserDefaults = .standard,
            fileManager: FileManager = .default
        ) throws {
            self.schema = Schema(versionedSchema: MistiaSchemaV4.self)
            self.userDefaults = userDefaults
            self.fileManager = fileManager

            let bootstrapState = try Self.bootstrapProfileState(
                schema: schema,
                userDefaults: userDefaults,
                fileManager: fileManager
            )
            self.modelContainer = bootstrapState.modelContainer
            self.profileDescriptors = bootstrapState.profileDescriptors
            self.activeProfileID = bootstrapState.activeProfileID
            self.issue = nil
        }

        init(
            fallbackContainer: ModelContainer,
            issue: LaunchIssue,
            userDefaults: UserDefaults = .standard,
            fileManager: FileManager = .default
        ) {
            self.schema = Schema(versionedSchema: MistiaSchemaV4.self)
            self.userDefaults = userDefaults
            self.fileManager = fileManager
            self.modelContainer = fallbackContainer
            self.issue = issue
            self.profileDescriptors = []
            self.activeProfileID = nil
        }

        var activeProfileDescriptor: MistiaLocalProfileDescriptor? {
            guard let activeProfileID else { return nil }
            return profileDescriptors.first(where: { $0.id == activeProfileID })
        }

        func cloudProfileDescriptor(for userID: UUID) -> MistiaLocalProfileDescriptor? {
            profileDescriptors.first {
                $0.kind == .cloudUser && $0.cloudUserID == userID
            }
        }

        func latestGuestProfile(excluding profileID: UUID? = nil) -> MistiaLocalProfileDescriptor? {
            profileDescriptors
                .filter { $0.kind == .guestUnbound && $0.id != profileID }
                .sorted { lhs, rhs in
                    if lhs.lastUsedAt != rhs.lastUsedAt {
                        return lhs.lastUsedAt > rhs.lastUsedAt
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                .first
        }

        func ensureCloudProfile(
            for userID: UUID,
            activate shouldActivate: Bool = false
        ) throws -> MistiaLocalProfileDescriptor {
            if var existing = cloudProfileDescriptor(for: userID) {
                existing.lastUsedAt = .now
                upsertDescriptor(existing)
                if shouldActivate {
                    try activateProfile(existing)
                }
                return existing
            }

            let descriptor = MistiaLocalProfileDescriptor(
                kind: .cloudUser,
                cloudUserID: userID
            )
            try ensureProfileDirectoryExists(for: descriptor)
            upsertDescriptor(descriptor)
            if shouldActivate {
                try activateProfile(descriptor)
            }
            return descriptor
        }

        func createGuestProfile(
            activate shouldActivate: Bool = true
        ) throws -> MistiaLocalProfileDescriptor {
            let descriptor = MistiaLocalProfileDescriptor(kind: .guestUnbound)
            try ensureProfileDirectoryExists(for: descriptor)
            upsertDescriptor(descriptor)
            if shouldActivate {
                try activateProfile(descriptor)
            }
            return descriptor
        }

        func activateProfile(_ descriptor: MistiaLocalProfileDescriptor) throws {
            var updatedDescriptor = descriptor
            updatedDescriptor.lastUsedAt = .now
            let container = try openContainer(for: updatedDescriptor)
            modelContainer = container
            activeProfileID = updatedDescriptor.id
            upsertDescriptor(updatedDescriptor)
            userDefaults.set(
                updatedDescriptor.id.uuidString.lowercased(),
                forKey: MistiaPersistenceStorageKey.activeLocalProfileID
            )
        }

        func hasMeaningfulUserData(
            in descriptor: MistiaLocalProfileDescriptor? = nil
        ) throws -> Bool {
            let targetDescriptor = descriptor ?? activeProfileDescriptor
            guard let targetDescriptor else { return false }
            let container = targetDescriptor.id == activeProfileDescriptor?.id
                ? modelContainer
                : try openContainer(for: targetDescriptor)
            return try MistiaSyncLocalStore.hasMeaningfulUserData(in: container)
        }

        func claimGuestProfile(
            _ descriptor: MistiaLocalProfileDescriptor,
            to userID: UUID
        ) throws -> MistiaLocalProfileDescriptor {
            let container = descriptor.id == activeProfileDescriptor?.id
                ? modelContainer
                : try openContainer(for: descriptor)
            try MistiaSyncLocalStore.reassignLocalOwnership(
                from: descriptor.id,
                to: userID,
                in: container
            )

            var claimedDescriptor = descriptor
            claimedDescriptor.kind = .cloudUser
            claimedDescriptor.cloudUserID = userID
            claimedDescriptor.lastUsedAt = .now
            upsertDescriptor(claimedDescriptor)
            return claimedDescriptor
        }

        func convertProfileToGuestUnbound(
            _ descriptor: MistiaLocalProfileDescriptor
        ) throws -> MistiaLocalProfileDescriptor {
            let container = descriptor.id == activeProfileDescriptor?.id
                ? modelContainer
                : try openContainer(for: descriptor)
            if let cloudUserID = descriptor.cloudUserID {
                try MistiaSyncLocalStore.reassignLocalOwnership(
                    from: cloudUserID,
                    to: descriptor.id,
                    in: container
                )
            }

            var guestDescriptor = descriptor
            guestDescriptor.kind = .guestUnbound
            guestDescriptor.cloudUserID = nil
            guestDescriptor.lastUsedAt = .now
            upsertDescriptor(guestDescriptor)
            let familyCacheURL = familyCacheURL(for: guestDescriptor)
            if fileManager.fileExists(atPath: familyCacheURL.path) {
                try? fileManager.removeItem(at: familyCacheURL)
            }
            return guestDescriptor
        }

        func deleteProfile(_ descriptor: MistiaLocalProfileDescriptor) throws {
            profileDescriptors.removeAll { $0.id == descriptor.id }
            persistProfileRegistry()

            if activeProfileID == descriptor.id {
                activeProfileID = nil
                userDefaults.removeObject(forKey: MistiaPersistenceStorageKey.activeLocalProfileID)
            }

            try removeProfileArtifactsIfPossible(for: descriptor)
        }

        func familyCacheURL(for descriptor: MistiaLocalProfileDescriptor) -> URL {
            profileDirectoryURL(for: descriptor)
                .appendingPathComponent("family-cache")
                .appendingPathExtension("json")
        }

        private static func bootstrapProfileState(
            schema: Schema,
            userDefaults: UserDefaults,
            fileManager: FileManager
        ) throws -> (
            modelContainer: ModelContainer,
            profileDescriptors: [MistiaLocalProfileDescriptor],
            activeProfileID: UUID
        ) {
            var descriptors = try loadProfileRegistry(userDefaults: userDefaults)
            if descriptors.isEmpty, let migratedDescriptor = try migrateLegacyDefaultStoreIfNeeded(
                userDefaults: userDefaults,
                fileManager: fileManager
            ) {
                descriptors = [migratedDescriptor]
                try saveProfileRegistry(descriptors, userDefaults: userDefaults)
            }

            // Heal registry if descriptors are missing but files exist
            descriptors = try healProfileRegistryIfNeeded(
                descriptors,
                schema: schema,
                userDefaults: userDefaults,
                fileManager: fileManager
            )

            if descriptors.isEmpty {
                let guestDescriptor = MistiaLocalProfileDescriptor(kind: .guestUnbound)
                try ensureProfileDirectoryExists(
                    for: guestDescriptor,
                    fileManager: fileManager
                )
                descriptors = [guestDescriptor]
                try saveProfileRegistry(descriptors, userDefaults: userDefaults)
                userDefaults.set(
                    guestDescriptor.id.uuidString.lowercased(),
                    forKey: MistiaPersistenceStorageKey.activeLocalProfileID
                )
            }

            let activeProfileID = storedActiveProfileID(
                in: userDefaults,
                descriptors: descriptors
            ) ?? descriptors.first?.id ?? UUID()
            let activeDescriptor = descriptors.first(where: { $0.id == activeProfileID }) ?? descriptors[0]
            let container = try openContainer(
                for: activeDescriptor,
                schema: schema,
                fileManager: fileManager
            )

            return (
                modelContainer: container,
                profileDescriptors: descriptors,
                activeProfileID: activeDescriptor.id
            )
        }

        private func upsertDescriptor(_ descriptor: MistiaLocalProfileDescriptor) {
            if let index = profileDescriptors.firstIndex(where: { $0.id == descriptor.id }) {
                profileDescriptors[index] = descriptor
            } else {
                profileDescriptors.append(descriptor)
            }
            persistProfileRegistry()
        }

        private func persistProfileRegistry() {
            try? Self.saveProfileRegistry(profileDescriptors, userDefaults: userDefaults)
        }

        private func openContainer(
            for descriptor: MistiaLocalProfileDescriptor
        ) throws -> ModelContainer {
            try Self.openContainer(
                for: descriptor,
                schema: schema,
                fileManager: fileManager
            )
        }

        private static func openContainer(
            for descriptor: MistiaLocalProfileDescriptor,
            schema: Schema,
            fileManager: FileManager
        ) throws -> ModelContainer {
            let storeURL = self.storeURL(
                for: descriptor,
                fileManager: fileManager
            )
            let configuration = ModelConfiguration("default", schema: schema, url: storeURL)
            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: MistiaMigrationPlan.self,
                    configurations: [configuration]
                )
            } catch {
                throw LaunchIssue(
                    storeURL: storeURL,
                    underlyingErrorDescription: String(describing: error)
                )
            }
        }

        private func ensureProfileDirectoryExists(
            for descriptor: MistiaLocalProfileDescriptor
        ) throws {
            try Self.ensureProfileDirectoryExists(
                for: descriptor,
                fileManager: fileManager
            )
        }

        private func profileDirectoryURL(
            for descriptor: MistiaLocalProfileDescriptor
        ) -> URL {
            Self.profileDirectoryURL(for: descriptor, fileManager: fileManager)
        }

        private static func ensureProfileDirectoryExists(
            for descriptor: MistiaLocalProfileDescriptor,
            fileManager: FileManager
        ) throws {
            let directoryURL = profileDirectoryURL(for: descriptor, fileManager: fileManager)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        private func removeProfileArtifactsIfPossible(
            for descriptor: MistiaLocalProfileDescriptor
        ) throws {
            let directoryURL = Self.profileDirectoryURL(for: descriptor, fileManager: fileManager)
            guard fileManager.fileExists(atPath: directoryURL.path) else { return }
            try? fileManager.removeItem(at: directoryURL)
        }

        private static func loadProfileRegistry(
            userDefaults: UserDefaults
        ) throws -> [MistiaLocalProfileDescriptor] {
            guard let data = userDefaults.data(forKey: MistiaPersistenceStorageKey.localProfileDescriptors) else {
                return []
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                if let stringValue = try? container.decode(String.self) {
                    if let date = MistiaISO8601DateCoding.date(from: stringValue) {
                        return date
                    }
                }
                let doubleValue = try container.decode(Double.self)
                return Date(timeIntervalSince1970: doubleValue)
            }
            
            return try decoder.decode(
                [MistiaLocalProfileDescriptor].self,
                from: data
            )
        }

        private static func saveProfileRegistry(
            _ descriptors: [MistiaLocalProfileDescriptor],
            userDefaults: UserDefaults
        ) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(MistiaISO8601DateCoding.stringWithFractionalSeconds(from: date))
            }
            let data = try encoder.encode(descriptors)
            userDefaults.set(data, forKey: MistiaPersistenceStorageKey.localProfileDescriptors)
        }

        private static func storedActiveProfileID(
            in userDefaults: UserDefaults,
            descriptors: [MistiaLocalProfileDescriptor]
        ) -> UUID? {
            guard let rawValue = userDefaults.string(forKey: MistiaPersistenceStorageKey.activeLocalProfileID),
                  let profileID = UUID(uuidString: rawValue),
                  descriptors.contains(where: { $0.id == profileID }) else {
                return nil
            }
            return profileID
        }

        private static func migrateLegacyDefaultStoreIfNeeded(
            userDefaults: UserDefaults,
            fileManager: FileManager
        ) throws -> MistiaLocalProfileDescriptor? {
            let legacyStoreURL = defaultStoreURL(fileManager: fileManager)
            let directoryContents = (try? fileManager.contentsOfDirectory(
                at: legacyStoreURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )) ?? []
            let legacyArtifacts = directoryContents.filter {
                $0.lastPathComponent.hasPrefix(legacyStoreURL.lastPathComponent)
            }

            guard fileManager.fileExists(atPath: legacyStoreURL.path) || !legacyArtifacts.isEmpty else {
                return nil
            }

            // Note: SupabaseAuthService is not available in this target.
            // Legacy migration will rely on the local mode profile user ID stored in UserDefaults.
            let persistedUserID: UUID? = nil
            let guestAttachedUserID = persistedUserID ?? storedLegacyLocalModeProfileUserID(in: userDefaults)
            let descriptor = MistiaLocalProfileDescriptor(
                kind: guestAttachedUserID == nil ? .guestUnbound : .cloudUser,
                cloudUserID: guestAttachedUserID
            )

            try ensureProfileDirectoryExists(
                for: descriptor,
                fileManager: fileManager
            )

            let destinationStoreURL = storeURL(for: descriptor, fileManager: fileManager)
            for artifactURL in legacyArtifacts {
                let suffix = String(artifactURL.lastPathComponent.dropFirst(legacyStoreURL.lastPathComponent.count))
                let destinationURL = destinationStoreURL.deletingLastPathComponent()
                    .appendingPathComponent(destinationStoreURL.lastPathComponent + suffix)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: artifactURL, to: destinationURL)
            }

            return descriptor
        }

        private static func healProfileRegistryIfNeeded(
            _ currentDescriptors: [MistiaLocalProfileDescriptor],
            schema: Schema,
            userDefaults: UserDefaults,
            fileManager: FileManager
        ) throws -> [MistiaLocalProfileDescriptor] {
            let rootURL = profilesRootURL(fileManager: fileManager)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil
            ) else {
                return currentDescriptors
            }

            var updatedDescriptors = currentDescriptors
            var didHeal = false

            for directoryURL in contents where directoryURL.hasDirectoryPath {
                guard let profileID = UUID(uuidString: directoryURL.lastPathComponent) else { continue }
                if updatedDescriptors.contains(where: { $0.id == profileID }) { continue }

                // Orphaned directory found
                let storeURL = directoryURL.appendingPathComponent("profile").appendingPathExtension("store")
                guard fileManager.fileExists(atPath: storeURL.path) else { continue }

                // Try to infer owner from the store
                let configuration = ModelConfiguration("inference", schema: schema, url: storeURL)
                guard let container = try? ModelContainer(
                    for: schema,
                    migrationPlan: MistiaMigrationPlan.self,
                    configurations: [configuration]
                ) else { continue }
                let context = ModelContext(container)
                let profile = (try? context.fetch(FetchDescriptor<UserAccountProfile>()))?.first

                let descriptor = MistiaLocalProfileDescriptor(
                    id: profileID,
                    kind: profile == nil ? .guestUnbound : .cloudUser,
                    cloudUserID: profile?.userID
                )
                updatedDescriptors.append(descriptor)
                didHeal = true
            }

            if didHeal {
                try saveProfileRegistry(updatedDescriptors, userDefaults: userDefaults)
            }
            return updatedDescriptors
        }

        private static func storedLegacyLocalModeProfileUserID(
            in userDefaults: UserDefaults
        ) -> UUID? {
            guard let rawValue = userDefaults.string(forKey: MistiaPersistenceStorageKey.localModeProfileUserID) else {
                return nil
            }
            return UUID(uuidString: rawValue)
        }

        private static func profilesRootURL(fileManager: FileManager) -> URL {
            let applicationSupportURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory

            return applicationSupportURL.appendingPathComponent("profiles", isDirectory: true)
        }

        private static func profileDirectoryURL(
            for descriptor: MistiaLocalProfileDescriptor,
            fileManager: FileManager
        ) -> URL {
            profilesRootURL(fileManager: fileManager)
                .appendingPathComponent(descriptor.id.uuidString.lowercased(), isDirectory: true)
        }

        private static func storeURL(
            for descriptor: MistiaLocalProfileDescriptor,
            fileManager: FileManager
        ) -> URL {
            profileDirectoryURL(for: descriptor, fileManager: fileManager)
                .appendingPathComponent("profile")
                .appendingPathExtension("store")
        }
    }

    @MainActor
    static let sharedLaunchState: LaunchState = {
        do {
            return try LaunchState()
        } catch {
            let schema = Schema(versionedSchema: MistiaSchemaV4.self)
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let fallbackContainer = try! ModelContainer(
                for: schema,
                migrationPlan: MistiaMigrationPlan.self,
                configurations: [fallbackConfiguration]
            )
            let launchIssue: LaunchIssue
            if let existingIssue = error as? LaunchIssue {
                launchIssue = existingIssue
            } else {
                launchIssue = LaunchIssue(
                    storeURL: defaultStoreURL(),
                    underlyingErrorDescription: String(describing: error)
                )
            }

            return LaunchState(
                fallbackContainer: fallbackContainer,
                issue: launchIssue
            )
        }
    }()

    @MainActor
    static var sharedModelContainer: ModelContainer {
        sharedLaunchState.modelContainer
    }

    @MainActor
    static var launchIssue: LaunchIssue? {
        sharedLaunchState.issue
    }

    private static func defaultStoreURL(
        fileManager: FileManager = .default
    ) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("default")
            .appendingPathExtension("store")
    }
}
