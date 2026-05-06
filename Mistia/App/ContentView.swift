import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    var body: some View {
        @Bindable var familyContextStore = familyContextStore

        RootTabView()
            .fullScreenCover(item: $familyContextStore.pendingInviteRoute) { route in
                FamilyInviteAcceptanceScreen(route: route)
            }
            .task(id: familyRefreshToken) {
                await familyContextStore.refresh(sessionStore: sessionStore)
            }
    }

    private var familyRefreshToken: String {
        "\(sessionStore.activeLocalProfileID?.uuidString.lowercased() ?? "none"):\(sessionStore.isSignedIn)"
    }
}
