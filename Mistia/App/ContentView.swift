import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        RootTabView()
            .task {
                await sessionStore.bootstrapIfNeeded()
            }
    }
}
