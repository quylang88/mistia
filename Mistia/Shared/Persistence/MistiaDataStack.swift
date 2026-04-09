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
        let schema = Schema(versionedSchema: MistiaSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return LaunchState(
                modelContainer: try ModelContainer(
                    for: schema,
                    migrationPlan: MistiaMigrationPlan.self,
                    configurations: [configuration]
                ),
                issue: nil
            )
        } catch {
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let fallbackContainer = try! ModelContainer(
                for: schema,
                configurations: [fallbackConfiguration]
            )

            return LaunchState(
                modelContainer: fallbackContainer,
                issue: LaunchIssue(
                    storeURL: configuration.url,
                    underlyingErrorDescription: String(describing: error)
                )
            )
        }
    }()

    static let sharedModelContainer: ModelContainer = sharedLaunchState.modelContainer
    static let launchIssue: LaunchIssue? = sharedLaunchState.issue
}
