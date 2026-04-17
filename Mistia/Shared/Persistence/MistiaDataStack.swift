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
            let schema = Schema(versionedSchema: MistiaSchemaV1.self)
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let fallbackContainer = try! ModelContainer(
                for: schema,
                configurations: [fallbackConfiguration]
            )

            return LaunchState(
                modelContainer: fallbackContainer,
                issue: LaunchIssue(
                    storeURL: defaultStoreURL(),
                    underlyingErrorDescription: String(describing: error)
                )
            )
        }
    }()

    static let sharedModelContainer: ModelContainer = sharedLaunchState.modelContainer
    static let launchIssue: LaunchIssue? = sharedLaunchState.issue

    private static func makeLaunchState() throws -> LaunchState {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let storeURL = defaultStoreURL()
        let modelContainer = try makePersistentContainer(schema: schema, storeURL: storeURL)
        return LaunchState(modelContainer: modelContainer, issue: nil)
    }

    private static func defaultStoreURL() -> URL {
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
            configurations: [configuration]
        )
    }
}
