import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct MistiaApp: App {
    @AppStorage(MistiaAppStorageKey.appearanceMode) private var appearanceModeRawValue = MistiaAppearanceMode.automatic.rawValue
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchState: MistiaDataStack.LaunchState
    @State private var sessionStore: SessionStore
    @State private var familyContextStore: FamilyContextStore
    @State private var uiState = MistiaUIState()
    @State private var deferredStartupWorkTask: Task<Void, Never>?

    init() {
        MistiaAppLanguage.bootstrapStoredPreference()
        let launchState = MistiaDataStack.sharedLaunchState
        _launchState = State(initialValue: launchState)
        _sessionStore = State(initialValue: SessionStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState
        ))
        let familyStore = FamilyContextStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState
        )
        _familyContextStore = State(initialValue: familyStore)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let launchIssue = launchState.issue {
                    MistiaProtectedLaunchView(launchIssue: launchIssue, appLanguage: appLanguage)
                } else if sessionStore.isAuthTransitioning {
                    MistiaAuthTransitionView(appLanguage: appLanguage)
                } else if sessionStore.isBootstrapping {
                    MistiaStartupLoadingView(appLanguage: appLanguage)
                } else {
                    ContentView()
                }
            }
                .id(appRootIdentity)
                .preferredColorScheme(appearanceMode.colorScheme)
                .environment(\.locale, appLanguage.locale)
                .environment(\.calendar, appLanguage.calendar)
                .environment(sessionStore)
                .environment(familyContextStore)
                .environment(uiState)
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) {
                        _ = familyContextStore.handleInviteURL(url)
                    }
                }
                .task {
                    let store = familyContextStore
                    sessionStore.setSubjectUserIDProvider { [weak store] in
                        store?.selectedSubjectUserID
                    }
                    sessionStore.setPostSyncRefreshHandler { [weak store, sessionStore] in
                        guard let store else { return }
                        await store.refreshLatest(
                            sessionStore: sessionStore,
                            source: .postManualSync
                        )
                        await MistiaDueMaintenance.run(
                            modelContext: sessionStore.currentModelContainer.mainContext,
                            sessionStore: sessionStore
                        )
                    }
                    familyContextStore.setModelContainer(sessionStore.currentModelContainer)
                    await runStartupTasks()
                    scheduleDeferredStartupWork()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        sessionStore.handleSceneDidBecomeActive(runsForegroundCatchUp: false)
                        if !sessionStore.isBootstrapping {
                            scheduleDeferredStartupWork()
                        }
                    case .background:
                        sessionStore.handleSceneDidEnterBackground()
                    default:
                        break
                    }
                }
                .modelContainer(launchState.modelContainer)
        }
    }

    private var appRootIdentity: String {
        let profileID = launchState.activeProfileID?.uuidString.lowercased() ?? "none"
        let signedInUserID = sessionStore.signedInUserID?.uuidString.lowercased() ?? "guest"
        let authState = sessionStore.isSignedIn ? "signed-in" : "signed-out"
        let launchStateKind = launchState.issue == nil ? "healthy" : "protected"
        return [profileID, signedInUserID, authState, launchStateKind].joined(separator: ":")
    }

    private var appearanceMode: MistiaAppearanceMode {
        MistiaAppearanceMode(rawValue: appearanceModeRawValue) ?? .automatic
    }

    private var appLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }

    @MainActor
    private func runStartupTasks() async {
        await sessionStore.bootstrapIfNeeded()
        await familyContextStore.bootstrapIfNeeded(sessionStore: sessionStore)
        sessionStore.finishBootstrapping()
    }

    @MainActor
    private func scheduleDeferredStartupWork(delay: Duration = .milliseconds(850)) {
        guard deferredStartupWorkTask == nil else { return }
        deferredStartupWorkTask = Task { @MainActor in
            defer { deferredStartupWorkTask = nil }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await runDeferredStartupWork()
        }
    }

    @MainActor
    private func runDeferredStartupWork() async {
        do {
            let context = sessionStore.currentModelContainer.mainContext
            try MistiaBootstrap.seedDefaultCategoriesForLaunchIfNeeded(
                modelContext: context,
                sessionStore: sessionStore
            )
        } catch {
            print("Failed to seed category hierarchy: \(error)")
        }

        do {
            let context = sessionStore.currentModelContainer.mainContext
            try MistiaBootstrap.cleanupExpiredArchivedData(modelContext: context, sessionStore: sessionStore)
        } catch {
            print("Failed to clean up expired archived data: \(error)")
        }

        _ = await sessionStore.runDeferredStartupSyncIfNeeded()
        await MistiaCurrencyRateMaintenance.refreshIfNeeded()
        await runCategoryTranslationMaintenance()
        await runDueMaintenance()
    }

    @MainActor
    private func runCategoryTranslationMaintenance() async {
        await CategoryNameTranslationMaintenance.run(
            modelContext: sessionStore.currentModelContainer.mainContext,
            sessionStore: sessionStore
        )
    }

    @MainActor
    private func runDueMaintenance() async {
        await MistiaDueMaintenance.run(
            modelContext: sessionStore.currentModelContainer.mainContext,
            sessionStore: sessionStore
        )
    }
}

private struct MistiaAuthTransitionView: View {
    let appLanguage: MistiaAppLanguage

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text(L10n.app.mistia.switchingSession)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .environment(\.locale, appLanguage.locale)
        .environment(\.calendar, appLanguage.calendar)
    }
}

private struct MistiaProtectedLaunchView: View {
    let launchIssue: MistiaDataStack.LaunchIssue
    let appLanguage: MistiaAppLanguage

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.13, green: 0.16, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.app.mistia.mistiaIsProtectingYourData)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                    Text(L10n.app.mistia.theAppCouldnTOpenTheLocal)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))

                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            L10n.app.mistia.localDataHasBeenKeptOnThis,
                            systemImage: "internaldrive.fill"
                        )

                        Label(
                            L10n.app.mistia.theAppWillNotCreateAReplacement,
                            systemImage: "lock.shield.fill"
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.app.mistia.technicalDetails)
                        .font(.headline)
                        .foregroundStyle(.white)

                        Text(launchIssue.underlyingErrorDescription)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .textSelection(.enabled)

                        if let storeURL = launchIssue.storeURL {
                            Text(storeURL.path)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.68))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(18)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Startup Loading View

private struct MistiaStartupLoadingView: View {
    let appLanguage: MistiaAppLanguage

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text(L10n.app.mistia.loadingYourData)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .environment(\.locale, appLanguage.locale)
        .environment(\.calendar, appLanguage.calendar)
    }
}
