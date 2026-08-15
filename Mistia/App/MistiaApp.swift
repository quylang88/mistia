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
    @State private var appLockController = MistiaAppLockController()
    @State private var deferredStartupWorkTask: Task<Void, Never>?

    init() {
        MistiaAppLanguage.bootstrapStoredPreference()
        MistiaRootChromeLogic.normalizeLegacyPersistentFlags()
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
                    MistiaStartupLoadingView()
                } else {
                    ContentView()
                }
            }
                .overlay {
                    if !sessionStore.isAuthTransitioning,
                       !sessionStore.isBootstrapping,
                       launchState.issue == nil,
                       appLockController.shouldPresentLock {
                        MistiaAppLockScreen()
                            .environment(appLockController)
                            .id(appLockController.lockCycle)
                    }
                }
                .id(appRootIdentity)
                .preferredColorScheme(rootPreferredColorScheme)
                .environment(\.locale, appLanguage.locale)
                .environment(\.calendar, appLanguage.calendar)
                .environment(sessionStore)
                .environment(familyContextStore)
                .environment(uiState)
                .environment(appLockController)
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
                    sessionStore.setPostSyncRefreshHandler { [weak store, sessionStore] trigger in
                        guard let store else { return }
                        if trigger == .automaticLoop {
                            await store.refreshNotifications(sessionStore: sessionStore)
                            return
                        }
                        guard trigger == .manual || trigger == .backgroundRefresh || trigger == .initial else {
                            return
                        }
                        await store.refreshLatest(
                            sessionStore: sessionStore,
                            source: .postSync
                        )
                        let signpostID = MistiaPerformanceSignpost.begin("Maintenance")
                        await MistiaDueMaintenance.run(
                            modelContext: sessionStore.currentModelContainer.mainContext,
                            sessionStore: sessionStore,
                            familyContextStore: store
                        )
                        MistiaPerformanceSignpost.end("Maintenance", id: signpostID)
                    }
                    familyContextStore.setModelContainer(sessionStore.currentModelContainer)
                    await runStartupTasks()
                    scheduleDeferredStartupWork()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        sessionStore.handleSceneDidBecomeActive()
                        if !sessionStore.isBootstrapping {
                            scheduleDeferredStartupWork()
                        }
                    case .background:
                        sessionStore.handleSceneDidEnterBackground()
                        appLockController.lockIfNeeded()
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

    private var rootPreferredColorScheme: ColorScheme? {
        guard !sessionStore.isBootstrapping else { return nil }
        return appearanceMode.colorScheme
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
        let worker = MistiaStartupMaintenanceWorker(
            modelContainer: sessionStore.currentModelContainer
        )

        do {
            let signpostID = MistiaPerformanceSignpost.begin("Category Launch Repair")
            defer { MistiaPerformanceSignpost.end("Category Launch Repair", id: signpostID) }
            let syncMutations = try await worker.seedDefaultCategoriesForLaunchIfNeeded()
            MistiaBootstrap.queueSyncMutations(syncMutations, sessionStore: sessionStore)
        } catch {
            print("Failed to seed category hierarchy: \(error)")
        }

        if sessionStore.canManageSync, let signedInUserID = sessionStore.signedInUserID {
            do {
                let signpostID = MistiaPerformanceSignpost.begin("Archive Cleanup")
                defer { MistiaPerformanceSignpost.end("Archive Cleanup", id: signpostID) }
                let protectionIndex = sessionStore.archiveCleanupProtectionIndex()
                let deleteMutations = try await worker.cleanupExpiredArchivedData(
                    signedInUserID: signedInUserID,
                    cleanupProtectionIndex: protectionIndex
                )
                for mutation in deleteMutations {
                    sessionStore.recordDelete(
                        entity: mutation.entity,
                        recordID: mutation.recordID,
                        modifiedAt: mutation.modifiedAt
                    )
                }
            } catch {
                print("Failed to clean up expired archived data: \(error)")
            }
        }

        do {
            let signpostID = MistiaPerformanceSignpost.begin("Budget Snapshot Repair")
            defer { MistiaPerformanceSignpost.end("Budget Snapshot Repair", id: signpostID) }
            let syncMutations = try await worker.populateMissingBudgetCategorySnapshots()
            for mutation in syncMutations {
                sessionStore.recordUpsert(
                    entity: mutation.entity,
                    recordID: mutation.recordID,
                    modifiedAt: mutation.modifiedAt
                )
            }
        } catch {
            print("Failed to populate budget category snapshots: \(error)")
        }

        _ = await sessionStore.runDeferredStartupSyncIfNeeded()
        // Heavy network/persistence maintenance now runs after manual, initial,
        // or background sync. Active startup only validates the restored session.
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
            sessionStore: sessionStore,
            familyContextStore: familyContextStore
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
    private let iconSize: CGFloat = 184

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Image("AppIconAsset")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
        }
    }
}
