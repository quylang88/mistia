import SwiftUI

@main
struct MistiaApp: App {
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }

    private var appearanceMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }
}
