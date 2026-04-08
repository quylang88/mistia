import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        RootTabView()
            .task {
                await runStartupTasks()
            }
    }

    @MainActor
    private func runStartupTasks() async {
        await Task.yield()
        await sessionStore.bootstrapIfNeeded()

        do {
            let context = MistiaDataStack.sharedModelContainer.mainContext
            try MistiaBootstrap.cleanupExpiredArchivedData(modelContext: context, sessionStore: sessionStore)
        } catch {
            print("Failed to clean up expired archived data: \(error)")
        }
    }
}
