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
                    }
                    familyContextStore.setModelContainer(sessionStore.currentModelContainer)
                    await runStartupTasks()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        sessionStore.handleSceneDidBecomeActive()
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

        do {
            let context = sessionStore.currentModelContainer.mainContext
            try MistiaBootstrap.seedDefaultCategoriesIfNeeded(
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

        sessionStore.finishBootstrapping()
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

                Text(mistiaLocalized(
                    vi: "Đang chuyển phiên...",
                    en: "Switching session...",
                    ja: "セッションを切り替えています..."
                ))
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
                    Text(mistiaLocalized(
                        vi: "Mistia đang bảo vệ dữ liệu của bạn",
                        en: "Mistia is protecting your data",
                        ja: "Mistia はデータを保護しています",
                        language: appLanguage
                    ))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                    Text(mistiaLocalized(
                        vi: "Ứng dụng không thể mở cơ sở dữ liệu cục bộ sau khi cập nhật. Mistia đã chuyển sang chế độ an toàn và không xóa dữ liệu trên máy.",
                        en: "The app couldn't open the local database after the update. Mistia switched to safe mode and did not delete the data on this device.",
                        ja: "アップデート後にローカルデータベースを開けなかったため、Mistia はセーフモードに切り替わり、この端末のデータは削除していません。",
                        language: appLanguage
                    ))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))

                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            mistiaLocalized(
                                vi: "Dữ liệu local vẫn được giữ nguyên trên máy",
                                en: "Local data has been kept on this device",
                                ja: "ローカルデータはこの端末に保持されています",
                                language: appLanguage
                            ),
                            systemImage: "internaldrive.fill"
                        )

                        Label(
                            mistiaLocalized(
                                vi: "App sẽ không tự tạo DB mới để tránh ghi đè hoặc đồng bộ nhầm",
                                en: "The app will not create a replacement database that could overwrite or sync bad state",
                                ja: "上書きや誤同期を防ぐため、代わりのデータベースは自動作成しません",
                                language: appLanguage
                            ),
                            systemImage: "lock.shield.fill"
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(mistiaLocalized(
                            vi: "Chi tiết kỹ thuật",
                            en: "Technical details",
                            ja: "技術的な詳細",
                            language: appLanguage
                        ))
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

                Text(mistiaLocalized(
                    vi: "Đang tải dữ liệu...",
                    en: "Loading your data...",
                    ja: "データを読み込み中..."
                ))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .environment(\.locale, appLanguage.locale)
        .environment(\.calendar, appLanguage.calendar)
    }
}
