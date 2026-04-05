import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        RootTabView()
            .task {
                await sessionStore.bootstrapIfNeeded()
                do {
                    let context = MistiaDataStack.sharedModelContainer.mainContext
                    try MistiaBootstrap.cleanupExpiredArchivedData(modelContext: context)
                } catch {
                    print("Failed to clean up expired archived data: \(error)")
                }
            }
    }
}
