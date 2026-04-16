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
        let fileManager = FileManager.default

        // 1. Try primary store first
        if fileManager.fileExists(atPath: primaryStoreURL.path) {
            do {
                let primaryContainer = try makePersistentContainer(schema: schema, storeURL: primaryStoreURL)
                return LaunchState(modelContainer: primaryContainer, issue: nil)
            } catch {
                print("MistiaDataStack: primary store failed to open: \(error)")

                // 2. Proactive recovery from primary store
                do {
                    if try MistiaLegacyStoreRecovery.recoverLegacyStoreIfNeeded(
                        at: primaryStoreURL,
                        recoveredStoreURL: recoveredStoreURL
                    ) {
                        let recoveredContainer = try makePersistentContainer(
                            schema: schema,
                            storeURL: recoveredStoreURL
                        )
                        return LaunchState(modelContainer: recoveredContainer, issue: nil)
                    }
                } catch {
                    print("MistiaDataStack: proactive legacy recovery from primary failed: \(error)")
                }
            }
        }

        // 3. Try alternative recovery sources (restore, backup, old)
        let alternativeFilenames = ["default.restore", "default.backup", "default.old"]
        let appSupportURL = primaryStoreURL.deletingLastPathComponent()

        for filename in alternativeFilenames {
            let altStoreURL = appSupportURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: altStoreURL.path) {
                print("MistiaDataStack: found alternative store at \(filename), attempting recovery...")
                do {
                    try MistiaLegacyStoreRecovery.recoverStore(
                        at: altStoreURL,
                        recoveredStoreURL: recoveredStoreURL
                    )
                    let recoveredContainer = try makePersistentContainer(
                        schema: schema,
                        storeURL: recoveredStoreURL
                    )
                    return LaunchState(modelContainer: recoveredContainer, issue: nil)
                } catch {
                    print("MistiaDataStack: recovery from \(filename) failed: \(error)")
                }
            }
        }

        // 4. Fallback to existing recovered store if it exists
        if fileManager.fileExists(atPath: recoveredStoreURL.path) {
            do {
                let recoveredContainer = try makePersistentContainer(schema: schema, storeURL: recoveredStoreURL)
                return LaunchState(modelContainer: recoveredContainer, issue: nil)
            } catch {
                print("MistiaDataStack: existing recovered store failed to open: \(error)")
            }
        }

        // 5. Fresh start if all else fails (or just let the caller handle the throw)
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
