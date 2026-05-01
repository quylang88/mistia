import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    var body: some View {
        @Bindable var familyContextStore = familyContextStore

        RootTabView()
            .sheet(item: $familyContextStore.pendingInviteRoute) { route in
                FamilyInviteAcceptanceSheet(route: route)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            .task(id: familyRefreshToken) {
                await familyContextStore.refresh(sessionStore: sessionStore)
            }
    }

    private var familyRefreshToken: String {
        "\(sessionStore.activeLocalProfileID?.uuidString.lowercased() ?? "none"):\(sessionStore.isSignedIn)"
    }
}
