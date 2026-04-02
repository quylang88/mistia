import SwiftUI
import SwiftData

@main
struct MistiaApp: App {
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
    private let modelContainer: ModelContainer
    @State private var sessionStore: SessionStore

    init() {
        let resolvedContainer = MistiaDataStack.sharedModelContainer
        modelContainer = resolvedContainer
        _sessionStore = State(initialValue: SessionStore(modelContainer: resolvedContainer))

        if UserDefaults.standard.string(forKey: MistiaAppStorageKey.appLanguage) == nil {
            UserDefaults.standard.set(
                MistiaAppLanguage.infer().rawValue,
                forKey: MistiaAppStorageKey.appLanguage
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .environment(\.locale, appLanguage.locale)
                .environment(\.calendar, appLanguage.calendar)
                .environment(sessionStore)
                .modelContainer(modelContainer)
        }
    }

    private var appearanceMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }

    private var appLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }
}
