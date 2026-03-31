import SwiftData

enum MistiaDataStack {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LedgerAccount.self,
            CreditCardProfile.self,
            TransactionCategory.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }()
}
