import Foundation
import SwiftData

enum MistiaDataStack {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: MistiaSchemaV3.self)

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: MistiaMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // Fallback for development: wipe and recreate
            try? FileManager.default.removeItem(at: configuration.url)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()
}
