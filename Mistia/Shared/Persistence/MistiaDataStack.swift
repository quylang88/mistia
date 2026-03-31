import SwiftData

enum MistiaDataStack {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: MistiaSchemaV2.self)

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: MistiaMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }()
}
