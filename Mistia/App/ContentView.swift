import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(FamilyContextStore.self) private var familyContextStore

    var body: some View {
        @Bindable var familyContextStore = familyContextStore

        RootTabView()
            .fullScreenCover(item: $familyContextStore.pendingInviteRoute) { route in
                FamilyInviteAcceptanceScreen(route: route)
            }
    }
}
