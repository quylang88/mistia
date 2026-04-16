import Foundation
import SwiftData

enum MistiaDataStack {
    struct LaunchIssue: Error {
        let storeURL: URL?
        let underlyingErrorDescription: String
    }

    struct LaunchState {
        let modelContainer: ModelContainer
        let issue: LaunchIssue?
    }

    static let sharedLaunchState: LaunchState = {
        do {
            return try makeLaunchState()
        } catch {
            let schema = Schema(versionedSchema: MistiaSchemaV10.self)
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let fallbackContainer = try! ModelContainer(
                for: schema,
                configurations: [fallbackConfiguration]
            )

            return LaunchState(
                modelContainer: fallbackContainer,
                issue: LaunchIssue(
                    storeURL: defaultStoreURL(for: schema),
                    underlyingErrorDescription: String(describing: error)
                )
            )
        }
    }()

    static let sharedModelContainer: ModelContainer = sharedLaunchState.modelContainer
    static let launchIssue: LaunchIssue? = sharedLaunchState.issue

    private static func makeLaunchState() throws -> LaunchState {
        let schema = Schema(versionedSchema: MistiaSchemaV10.self)
        let primaryStoreURL = defaultStoreURL(for: schema)
        let recoveredStoreURL = MistiaLegacyStoreRecovery.recoveredStoreURL(for: primaryStoreURL)
        let legacyBackupStoreURL = legacyBackupStoreURL(for: primaryStoreURL)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: legacyBackupStoreURL.path) {
            do {
                if try MistiaLegacyStoreRecovery.recoverLegacyStoreIfNeeded(
                    at: legacyBackupStoreURL,
                    recoveredStoreURL: recoveredStoreURL
                ) {
                    let recoveredFromBackupContainer = try makePersistentContainer(
                        schema: schema,
                        storeURL: recoveredStoreURL
                    )
                    print(
                        "MistiaDataStack: opened recovered store from legacy backup at \(legacyBackupStoreURL.path)"
                    )
                    return LaunchState(modelContainer: recoveredFromBackupContainer, issue: nil)
                }
            } catch {
                print("MistiaDataStack: legacy backup recovery failed: \(error)")
            }
        }

        if fileManager.fileExists(atPath: primaryStoreURL.path) {
            do {
                let primaryContainer = try makePersistentContainer(schema: schema, storeURL: primaryStoreURL)
                return LaunchState(modelContainer: primaryContainer, issue: nil)
            } catch {
                print("MistiaDataStack: primary store failed to open: \(error)")

                do {
                    if try MistiaLegacyStoreRecovery.recoverLegacyStoreIfNeeded(
                        at: primaryStoreURL,
                        recoveredStoreURL: recoveredStoreURL
                    ) {
                        do {
                            try promoteRecoveredStore(
                                recoveredStoreURL: recoveredStoreURL,
                                toPrimaryStoreURL: primaryStoreURL
                            )
                            let recoveredPrimaryContainer = try makePersistentContainer(
                                schema: schema,
                                storeURL: primaryStoreURL
                            )
                            return LaunchState(modelContainer: recoveredPrimaryContainer, issue: nil)
                        } catch {
                            do {
                                try restorePrimaryStoreFromLegacyBackup(primaryStoreURL: primaryStoreURL)
                            } catch {
                                print("MistiaDataStack: failed to restore legacy backup after recovery promotion: \(error)")
                            }
                            throw error
                        }
                    }
                } catch {
                    print("MistiaDataStack: proactive legacy recovery failed: \(error)")
                }
            }
        }

        if fileManager.fileExists(atPath: recoveredStoreURL.path) {
            do {
                let recoveredContainer = try makePersistentContainer(schema: schema, storeURL: recoveredStoreURL)
                return LaunchState(modelContainer: recoveredContainer, issue: nil)
            } catch {
                print("MistiaDataStack: recovered store exists but failed to open: \(error)")
            }
        }

        let primaryContainer = try makePersistentContainer(schema: schema, storeURL: primaryStoreURL)
        return LaunchState(modelContainer: primaryContainer, issue: nil)
    }

    private static func defaultStoreURL(for schema: Schema) -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("default")
            .appendingPathExtension("store")
    }

    private static func makePersistentContainer(
        schema: Schema,
        storeURL: URL
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration("default", schema: schema, url: storeURL)

        return try ModelContainer(
            for: schema,
            migrationPlan: MistiaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func promoteRecoveredStore(
        recoveredStoreURL: URL,
        toPrimaryStoreURL primaryStoreURL: URL
    ) throws {
        let backupStoreURL = legacyBackupStoreURL(for: primaryStoreURL)
        try removeStoreFamily(at: backupStoreURL)
        try moveStoreFamily(from: primaryStoreURL, to: backupStoreURL)
        try removeStoreFamily(at: primaryStoreURL)
        try moveStoreFamily(from: recoveredStoreURL, to: primaryStoreURL)
    }

    private static func legacyBackupStoreURL(for primaryStoreURL: URL) -> URL {
        let directoryURL = primaryStoreURL.deletingLastPathComponent()
        let baseName = primaryStoreURL.deletingPathExtension().lastPathComponent
        return directoryURL
            .appendingPathComponent("\(baseName).legacy")
            .appendingPathExtension(primaryStoreURL.pathExtension)
    }

    private static func restorePrimaryStoreFromLegacyBackup(primaryStoreURL: URL) throws {
        let backupStoreURL = legacyBackupStoreURL(for: primaryStoreURL)
        guard FileManager.default.fileExists(atPath: backupStoreURL.path) else {
            return
        }

        try removeStoreFamily(at: primaryStoreURL)
        try moveStoreFamily(from: backupStoreURL, to: primaryStoreURL)
    }

    private static func removeStoreFamily(at storeURL: URL) throws {
        let fileManager = FileManager.default
        for url in storeFamilyURLs(for: storeURL) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func moveStoreFamily(from sourceStoreURL: URL, to destinationStoreURL: URL) throws {
        let fileManager = FileManager.default
        for (sourceURL, destinationURL) in zip(storeFamilyURLs(for: sourceStoreURL), storeFamilyURLs(for: destinationStoreURL)) {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func storeFamilyURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }
}

private struct RecoveryLaunchError: LocalizedError {
    let primaryStoreURL: URL
    let primaryError: Error
    let recoveryStoreURL: URL
    let recoveryError: Error

    var errorDescription: String? {
        """
        Primary store open failed at \(primaryStoreURL.path): \(primaryError)
        Recovery to \(recoveryStoreURL.path) failed: \(recoveryError)
        """
    }
}
