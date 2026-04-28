import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    var body: some View {
        RootTabView()
            .task {
                await runStartupTasks()
            }
            .task(id: familyRefreshToken) {
                await familyContextStore.refresh(sessionStore: sessionStore)
            }
    }

    @MainActor
    private func runStartupTasks() async {
        await Task.yield()
        do {
            let context = sessionStore.currentModelContainer.mainContext
            try MistiaBootstrap.seedDefaultCategoriesIfNeeded(
                modelContext: context,
                sessionStore: sessionStore
            )
        } catch {
            print("Failed to seed category hierarchy: \(error)")
        }
        await sessionStore.bootstrapIfNeeded()
        await familyContextStore.bootstrapIfNeeded(sessionStore: sessionStore)

        do {
            let context = sessionStore.currentModelContainer.mainContext
            try MistiaBootstrap.cleanupExpiredArchivedData(modelContext: context, sessionStore: sessionStore)
        } catch {
            print("Failed to clean up expired archived data: \(error)")
        }
    }

    private var familyRefreshToken: String {
        "\(sessionStore.activeLocalProfileID?.uuidString.lowercased() ?? "none"):\(sessionStore.isSignedIn)"
    }
}
