import Foundation
import Observation
import SwiftData

enum SessionRemoteAccessError: LocalizedError {
    case offline

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Offline"
        }
    }
}

struct SessionSummary: Equatable {
    let userID: UUID
    let displayName: String
    let email: String
    let avatarURL: URL?

    var initials: String {
        let components = displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if components.isEmpty {
            return "MI"
        }

        return components.joined()
    }
}

enum SessionAuthPhase: Equatable {
    case signIn
    case signUp
    case forgotPassword
    case verifyEmailPending
}

enum SessionAuthField: Hashable {
    case displayName
    case email
    case password
    case confirmPassword
}

enum SessionAuthBannerStyle: Equatable {
    case info
    case success
    case error
}

enum SessionAuthAction: Equatable {
    case credentials
    case google
    case passwordReset
    case resendConfirmation
}

struct SessionAuthBanner: Equatable {
    let title: String
    let message: String
    let style: SessionAuthBannerStyle
}

enum SessionLocalContext: Equatable {
    case authenticated(profileID: UUID, cloudUserID: UUID)
    case guestAttached(profileID: UUID, cloudUserID: UUID)
    case guestUnbound(profileID: UUID)
}

enum SessionPendingAuthenticationPromptKind: Equatable {
    case keepOrDeleteGuestData
    case attachGuestData
}

enum SessionPendingAuthenticationDecision: Equatable {
    case keepGuestDataSeparate
    case deleteGuestData
    case attachGuestData
}

struct SessionPendingAuthenticationPrompt: Identifiable {
    let id = UUID()
    let kind: SessionPendingAuthenticationPromptKind
    let title: String
    let message: String
}

private struct PendingAuthenticationState {
    let result: SessionAuthResult
    let sourceGuestDescriptor: MistiaLocalProfileDescriptor
    let prompt: SessionPendingAuthenticationPrompt
}

private enum SessionSyncTrigger {
    case manual
    case automaticLoop
    case foregroundCatchUp
    case backgroundRefresh
}

@MainActor
@Observable
final class SessionStore {
    // MARK: - Auto-sync Configuration
    private static let AUTOMATIC_SYNC_INTERVAL: TimeInterval = 1800 // 30 minutes in seconds
    private static let QUEUED_AUTO_SYNC_DEBOUNCE: Duration = .milliseconds(600)

    var summary: SessionSummary?
    var isWorking = false
    var isManualSyncInProgress = false
    var syncProgress: Double?
    var syncTimeRemaining: TimeInterval?
    var isCheckingData = false
    var syncStatusTitle: String
    var syncStatusDetail: String
    var syncStatusSystemImage: String
    var lastErrorMessage: String?
    var lastSyncAt: Date?
    var initialSyncPreview: MistiaInitialSyncPreview?
    var possibleDuplicateCount = 0
    var isAutoSyncEnabled: Bool
    var authPhase: SessionAuthPhase = .signIn
    var authBanner: SessionAuthBanner?
    var authPendingEmail: String?
    var authFieldErrors: [SessionAuthField: String] = [:]
    var activeAuthAction: SessionAuthAction?
    var pendingAuthenticationPrompt: SessionPendingAuthenticationPrompt?
    var isAuthTransitioning = false

    var networkStatus: SessionNetworkStatus = .checking
    var remoteUnavailableReason: String?

    @ObservationIgnored private let authService: any SessionAuthServicing
    @ObservationIgnored private let userProfileStore: any UserProfileRemoteStoring
    @ObservationIgnored private let launchState: MistiaDataStack.LaunchState?
    @ObservationIgnored private var modelContainer: ModelContainer
    @ObservationIgnored private var syncCoordinator: SyncCoordinator
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let connectivityMonitor: SessionConnectivityMonitor?
    @ObservationIgnored private var currentSession: SupabaseAuthSession?
    @ObservationIgnored private var legacyLocalModeProfileUserID: UUID?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var liveSyncTask: Task<Void, Never>?
    @ObservationIgnored private var isSyncInFlight = false
    @ObservationIgnored private var autoSyncPaused = false
    @ObservationIgnored private var shouldShowSyncProgress = false
    @ObservationIgnored private var syncStartTime: Date?
    @ObservationIgnored var requiresInitialSync = false
    @ObservationIgnored private var requiresManualSyncAfterRestore: Bool
    @ObservationIgnored private var pendingInitialSyncChoice: MistiaInitialSyncChoice?
    @ObservationIgnored private var subjectUserIDProvider: (() -> UUID?)?
    @ObservationIgnored private var postSyncRefreshHandler: (() async -> Void)?
    @ObservationIgnored private var queuedAutoSyncTask: Task<Void, Never>?
    @ObservationIgnored private var pendingQueuedAutoSync = false
    @ObservationIgnored private var reconnectValidationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingAuthenticationState: PendingAuthenticationState?

    init(
        modelContainer: ModelContainer,
        launchState: MistiaDataStack.LaunchState? = nil,
        userDefaults: UserDefaults = .standard,
        authService: (any SessionAuthServicing)? = nil,
        userProfileStore: (any UserProfileRemoteStoring)? = nil,
        syncCoordinator providedSyncCoordinator: SyncCoordinator? = nil,
        connectivityMonitor providedConnectivityMonitor: SessionConnectivityMonitor? = nil,
        registerBackgroundRefresh: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.launchState = launchState
        self.userDefaults = userDefaults
        self.authService = authService ?? SupabaseAuthService()
        self.userProfileStore = userProfileStore ?? SupabaseUserProfileStore()
        self.syncCoordinator = providedSyncCoordinator ?? SyncCoordinator(modelContainer: modelContainer)
        self.connectivityMonitor = providedConnectivityMonitor ?? SessionConnectivityMonitor()
        isAutoSyncEnabled = userDefaults.bool(forKey: MistiaAppStorageKey.syncAutoEnabled)
        legacyLocalModeProfileUserID = Self.storedLocalModeProfileUserID(in: userDefaults)
        requiresManualSyncAfterRestore = Self.storedManualSyncReviewRequired(
            in: userDefaults,
            profileID: launchState?.activeProfileDescriptor?.id
        )
        networkStatus = self.connectivityMonitor?.currentStatus ?? .checking

        if MistiaSyncConfiguration.load() == nil {
            syncStatusTitle = mistiaLocalized(
                vi: "Chưa cấu hình dịch vụ đồng bộ",
                en: "Cloud sync isn't configured",
                ja: "クラウド同期が未設定です"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist để bật đăng nhập và đồng bộ.",
                en: "Fill in the service URL and public key in MistiaSyncConfig.plist to enable sign-in and sync.",
                ja: "ログインと同期を有効にするには MistiaSyncConfig.plist にサービス URL と公開キーを設定してください。"
            )
            syncStatusSystemImage = "bolt.horizontal.circle"
        } else {
            syncStatusTitle = mistiaLocalized(
                vi: "Chưa đăng nhập",
                en: "Signed out",
                ja: "未ログイン"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Đăng nhập để đồng bộ dữ liệu Mistia giữa các thiết bị.",
                en: "Sign in to sync Mistia data across devices.",
                ja: "ログインすると Mistia のデータを端末間で同期できます。"
            )
            syncStatusSystemImage = "person.crop.circle.badge.plus"
        }

        configureSyncCoordinator()

        if registerBackgroundRefresh {
            MistiaSyncBackgroundScheduler.shared.registerIfNeeded(sessionStore: self)
        }
        self.connectivityMonitor?.onStatusChange = { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                self.handleConnectivityChanged(status)
            }
        }
        self.connectivityMonitor?.start()
    }

    var isConfigured: Bool {
        MistiaSyncConfiguration.load() != nil
    }

    var isSignedIn: Bool {
        summary != nil
    }

    var signedInUserID: UUID? {
        summary?.userID
    }

    var activeLocalProfileID: UUID? {
        switch activeLocalContext {
        case .authenticated(let profileID, _),
                .guestAttached(let profileID, _),
                .guestUnbound(let profileID):
            return profileID
        case nil:
            return nil
        }
    }

    var activeLocalProfileUserID: UUID? {
        switch activeLocalContext {
        case .authenticated(_, let cloudUserID),
                .guestAttached(_, let cloudUserID):
            return cloudUserID
        case .guestUnbound(let profileID):
            return profileID
        case nil:
            return nil
        }
    }

    var localModeProfileUserID: UUID? {
        switch activeLocalContext {
        case .guestAttached(_, let cloudUserID):
            return cloudUserID
        case .authenticated,
                .guestUnbound,
                nil:
            return nil
        }
    }

    var activeLocalContext: SessionLocalContext? {
        if let descriptor = launchState?.activeProfileDescriptor {
            switch descriptor.kind {
            case .cloudUser:
                guard let cloudUserID = descriptor.cloudUserID else { return nil }
                if signedInUserID == cloudUserID && currentSession != nil {
                    return .authenticated(profileID: descriptor.id, cloudUserID: cloudUserID)
                }
                return .guestAttached(profileID: descriptor.id, cloudUserID: cloudUserID)
            case .guestUnbound:
                return .guestUnbound(profileID: descriptor.id)
            }
        }

        if let signedInUserID {
            return .authenticated(profileID: signedInUserID, cloudUserID: signedInUserID)
        }
        if let legacyLocalModeProfileUserID {
            return .guestAttached(
                profileID: legacyLocalModeProfileUserID,
                cloudUserID: legacyLocalModeProfileUserID
            )
        }
        return nil
    }

    var isGuestLocalModeActive: Bool {
        if case .guestAttached = activeLocalContext {
            return !isSignedIn
        }
        return false
    }

    var isGuestUnboundModeActive: Bool {
        if case .guestUnbound = activeLocalContext {
            return !isSignedIn
        }
        return false
    }

    var canManageSync: Bool {
        currentSession != nil && isConfigured
    }

    var currentModelContainer: ModelContainer {
        modelContainer
    }

    var isOfflineModeActive: Bool {
        isSignedIn && networkStatus == .disconnected
    }

    var canPerformRemoteActions: Bool {
        canManageSync && networkStatus != .disconnected
    }

    var isReadyForAutomaticSync: Bool {
        isAutoSyncEnabled
            && canManageSync
            && canPerformRemoteActions
            && !requiresInitialSync
            && !requiresManualSyncAfterRestore
    }

    var isManualSyncRequiredAfterRestore: Bool {
        requiresManualSyncAfterRestore
    }

    var nextAutomaticSyncDate: Date? {
        guard isReadyForAutomaticSync else { return nil }
        return (lastSyncAt ?? .now).addingTimeInterval(Self.AUTOMATIC_SYNC_INTERVAL)
    }

    var isAnySyncInProgress: Bool {
        isSyncInFlight
    }

    func storedBirthday(for userID: UUID) -> Date? {
        storedProfile(for: userID)?.birthday
    }

    func updateProfile(
        displayName: String,
        birthday: Date?,
        avatarJPEGData: Data? = nil
    ) async throws {
        let validSession = try await prepareRemoteSession()

        let baseSummary = SessionSummary(user: validSession.user)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = trimmedName.isEmpty ? baseSummary.displayName : trimmedName
        let profile = try ensureStoredProfileExists(
            for: baseSummary,
            preferredDisplayName: resolvedDisplayName
        )
        let existingRemoteProfile = try await userProfileStore.fetchProfile(session: validSession)
        var remoteAvatarURL = existingRemoteProfile?.avatarURL ?? baseSummary.avatarURL

        if let avatarJPEGData {
            profile.avatarFileName = try saveAvatarImageData(avatarJPEGData, for: baseSummary.userID)
            remoteAvatarURL = try await userProfileStore.uploadAvatarImageData(
                avatarJPEGData,
                session: validSession
            )
        }

        let remoteProfile = try await userProfileStore.upsertProfile(
            displayName: resolvedDisplayName,
            avatarURL: remoteAvatarURL,
            birthday: birthday,
            session: validSession
        )
        await cacheRemoteAvatarIfNeeded(
            for: profile,
            remoteAvatarURL: remoteProfile.avatarURL ?? remoteAvatarURL
        )
        syncStoredProfile(profile, with: remoteProfile, email: baseSummary.email)
        try modelContainer.mainContext.save()
        summary = applyStoredProfile(
            profile,
            to: baseSummary,
            remoteAvatarURL: remoteProfile.avatarURL
        )
    }

    func setAutoSyncEnabled(_ isEnabled: Bool) {
        guard isAutoSyncEnabled != isEnabled else { return }
        isAutoSyncEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: MistiaAppStorageKey.syncAutoEnabled)
        if !isEnabled {
            cancelQueuedAutoSync()
        }
        updateAutoSyncLoopState()
    }

    func setSubjectUserIDProvider(_ provider: (() -> UUID?)?) {
        subjectUserIDProvider = provider
    }

    func setPostSyncRefreshHandler(_ handler: (() async -> Void)?) {
        postSyncRefreshHandler = handler
    }

    func handleSceneDidBecomeActive() {
        if requiresInitialSync && hasCompletedCloudSyncHistory() {
            requiresInitialSync = false
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
        }
        updateAutoSyncLoopState()

        guard shouldRunForegroundCatchUp() else { return }
        Task {
            _ = await runMergeSync(trigger: .foregroundCatchUp, showProgress: false)
        }
    }

    func handleSceneDidEnterBackground() {
        updateAutoSyncLoopState()
    }

    func handleBackgroundRefresh() async -> Bool {
        guard isReadyForAutomaticSync, !isSyncInFlight else { return false }
        return await runMergeSync(trigger: .backgroundRefresh, showProgress: false)
    }

    func showAuthPhase(_ phase: SessionAuthPhase) {
        authPhase = phase
        authBanner = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        if phase != .verifyEmailPending {
            authPendingEmail = nil
        }
    }

    func setAuthFieldErrors(_ errors: [SessionAuthField: String]) {
        authFieldErrors = errors
    }

    func clearAuthFieldError(_ field: SessionAuthField) {
        authFieldErrors.removeValue(forKey: field)
    }

    func clearAuthBanner() {
        authBanner = nil
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        // Nếu đã có session do thao tác đăng nhập thủ công chạy trước, bỏ qua bootstrap
        guard summary == nil else { return }

        syncStatusTitle = mistiaLocalized(
            vi: "Đang khôi phục phiên",
            en: "Restoring session",
            ja: "セッションを復元中"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Mistia đang kiểm tra tài khoản đã đăng nhập trước đó.",
            en: "Mistia is checking for a previously signed-in account.",
            ja: "以前のログイン状態を確認しています。"
        )
        syncStatusSystemImage = "key.horizontal"

        do {
            guard let restoredSession = try authService.loadPersistedSession() else {
                if summary == nil {
                    applySignedOutState()
                }
                return
            }

            if summary == nil {
                try await handleAuthenticationResult(
                    SessionAuthResult(
                        session: restoredSession,
                        origin: .existing
                    ),
                    restoringExistingSession: true
                )
            }
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
            if summary == nil {
                applySignedOutState(preservingBanner: true)
                authBanner = SessionAuthBanner(
                    title: mistiaLocalized(
                        vi: "Chưa thể đọc phiên đã lưu",
                        en: "Couldn't read the saved session",
                        ja: "保存済みセッションを読み取れませんでした"
                    ),
                    message: friendlyErrorMessage(for: error),
                    style: .error
                )
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil
        authBanner = nil
        activeAuthAction = .credentials

        do {
            let result = try await authService.signIn(email: email, password: password)
            try await handleAuthenticationResult(result, restoringExistingSession: false)
        } catch {
            handleSignInFailure(error, email: email)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil
        authBanner = nil
        activeAuthAction = .credentials

        do {
            let result = try await authService.signUp(
                email: email,
                password: password,
                displayName: displayName
            )
            switch result {
            case .signedIn(let authResult):
                try await handleAuthenticationResult(authResult, restoringExistingSession: false)
            case .emailConfirmationRequired:
                presentEmailConfirmationState(for: email)
            }
        } catch {
            handleSignUpFailure(error)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signInWithGoogle() async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        lastErrorMessage = nil
        authBanner = nil
        activeAuthAction = .google

        do {
            let result = try await authService.signInWithGoogle()
            try await handleAuthenticationResult(result, restoringExistingSession: false)
        } catch {
            handleGoogleSignInFailure(error)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func requestPasswordReset(email: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        authBanner = nil
        activeAuthAction = .passwordReset

        do {
            try await authService.requestPasswordReset(email: email)
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Kiểm tra email của bạn",
                    en: "Check your email",
                    ja: "メールを確認してください"
                ),
                message: mistiaLocalized(
                    vi: "Nếu email hợp lệ, Mistia sẽ gửi một email đặt lại mật khẩu trong giây lát.",
                    en: "If the email is valid, Mistia will send a password reset email shortly.",
                    ja: "有効なメールアドレスであれば、まもなくパスワード再設定メールが送信されます。"
                ),
                style: .success
            )
        } catch {
            handleRecoveryFailure(error, isResend: false)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func resendConfirmation(email: String) async {
        guard isConfigured else {
            applyConfigurationMissingState()
            return
        }

        isWorking = true
        authBanner = nil
        activeAuthAction = .resendConfirmation

        do {
            try await authService.resendConfirmation(email: email)
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Đã gửi lại email xác nhận",
                    en: "Confirmation email sent again",
                    ja: "確認メールを再送しました"
                ),
                message: mistiaLocalized(
                    vi: "Nếu email đang chờ xác nhận, hệ thống sẽ gửi lại email mới đến hộp thư của bạn.",
                    en: "If this account is pending confirmation, the system will send a fresh email to your inbox.",
                    ja: "このアカウントが確認待ちの場合、システムが新しい確認メールを再送します。"
                ),
                style: .info
            )
        } catch {
            handleRecoveryFailure(error, isResend: true)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signOut() async {
        stopLiveSyncLoop()
        isWorking = true
        lastErrorMessage = nil
        let activeSession = currentSession

        disableShortcutIfNeededOnLogout()

        await beginAuthTransition()
        defer { endAuthTransition() }

        do {
            try await authService.signOut(session: activeSession)
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
        }

        if launchState == nil {
            setLocalModeProfileUserID(activeSession?.user.id)
        }
        clearSessionRuntimeState()
        isWorking = false
        applySignedOutState()
    }

    func signOutAndDeleteLocalData() async {
        stopLiveSyncLoop()
        isWorking = true
        lastErrorMessage = nil
        let activeSession = currentSession
        let currentDescriptor = launchState?.activeProfileDescriptor

        disableShortcutIfNeededOnLogout()

        await beginAuthTransition()
        defer { endAuthTransition() }

        do {
            try await authService.signOut(session: activeSession)
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
        }

        do {
            if let currentDescriptor,
               let fallbackDescriptor = try fallbackGuestDescriptor(excluding: currentDescriptor.id) {
                try activateLocalProfile(fallbackDescriptor)
                try deleteLocalProfile(currentDescriptor)
            } else if launchState == nil {
                try MistiaSyncLocalStore.clearAllProfileData(in: modelContainer)
                setLocalModeProfileUserID(nil)
            }
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
        }

        clearSessionRuntimeState()
        isWorking = false
        applySignedOutState()
    }

    func deleteAccountKeepingLocalData() async {
        stopLiveSyncLoop()
        isWorking = true
        lastErrorMessage = nil
        await beginAuthTransition()
        defer { endAuthTransition() }

        do {
            let activeSession = try await prepareRemoteSession()
            try await authService.deleteAccount(session: activeSession)
            if let launchState, let currentDescriptor = launchState.activeProfileDescriptor {
                try MistiaSyncLocalStore.detachFromCloud(in: modelContainer)
                let guestDescriptor = try launchState.convertProfileToGuestUnbound(currentDescriptor)
                try activateLocalProfile(guestDescriptor)
            } else {
                setLocalModeProfileUserID(activeSession.user.id)
            }
            clearSessionRuntimeState()
            applySignedOutState(preservingBanner: true)
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Đã xóa tài khoản cloud",
                    en: "Cloud account deleted",
                    ja: "クラウドアカウントを削除しました"
                ),
                message: mistiaLocalized(
                    vi: "Tài khoản và dữ liệu trên cloud đã được xóa. Dữ liệu local trên máy này vẫn được giữ lại.",
                    en: "Your cloud account and server data were deleted. Local data on this device has been kept.",
                    ja: "クラウドアカウントとサーバーデータを削除しました。この端末のローカルデータは保持されています。"
                ),
                style: .success
            )
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
            updateAutoSyncLoopState()
        }

        isWorking = false
    }

    func syncNow(isManual: Bool = false) async -> Bool {
        guard currentSession != nil, !isSyncInFlight else { return false }

        if requiresInitialSync && hasCompletedCloudSyncHistory() {
            requiresInitialSync = false
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
        }

        if isManual {
            pauseAutoSyncLoop()
            isManualSyncInProgress = true
        }
        defer {
            if isManual {
                isManualSyncInProgress = false
                resumeAutoSyncLoop()
            }
        }

        let didSync: Bool
        if requiresInitialSync {
            didSync = await runInitialSyncFlow(showProgress: isManual)
        } else {
            didSync = await runMergeSync(
                trigger: isManual ? .manual : .automaticLoop,
                showProgress: isManual
            )
        }
        if didSync && isManual && requiresManualSyncAfterRestore {
            setRequiresManualSyncAfterRestore(false)
        }
        return didSync
    }

    func startInitialSync(with choice: MistiaInitialSyncChoice) async {
        guard currentSession != nil, !isSyncInFlight else { return }
        pendingInitialSyncChoice = choice
        initialSyncPreview = nil
        _ = await runInitialSyncFlow()
    }

    func cancelInitialSyncSelection() {
        if pendingInitialSyncChoice != nil {
            initialSyncPreview = nil
            return
        }

        guard requiresInitialSync else {
            initialSyncPreview = nil
            return
        }

        initialSyncPreview = nil
        pendingInitialSyncChoice = nil
        syncStatusTitle = mistiaLocalized(
            vi: "Đã tạm hoãn đồng bộ lần đầu",
            en: "Initial sync postponed",
            ja: "初回同期を保留しました"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Nhấn Đồng bộ ngay khi bạn sẵn sàng chọn cách đồng bộ dữ liệu với cloud.",
            en: "Tap Sync now when you're ready to choose how to sync with the cloud.",
            ja: "クラウドとの同期方法を選ぶ準備ができたら「今すぐ同期」を押してください。"
        )
        syncStatusSystemImage = "pause.circle"
        updateAutoSyncLoopState()
    }

    func restoreBackup(
        data: Data,
        mode: MistiaBackupRestoreMode
    ) async throws -> MistiaBackupRestoreResult {
        guard !isSyncInFlight else {
            throw MistiaBackupStoreError.syncInProgress
        }

        pauseAutoSyncLoop()
        cancelQueuedAutoSync()
        syncCoordinator.clearQueuedMutations()

        do {
            let fallbackOwnerUserID = summary?.userID
                ?? currentSession?.user.id
                ?? MistiaSyncDeviceIdentity.current()

            let result = try MistiaBackupStore.restoreBackup(
                data,
                mode: mode,
                in: modelContainer,
                fallbackOwnerUserID: fallbackOwnerUserID
            )

            syncCoordinator.clearQueuedMutations()
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
            try MistiaBootstrap.seedDefaultCategoriesIfNeeded(modelContext: modelContainer.mainContext)

            lastSyncAt = nil
            if let activeSession = currentSession {
                let baseSummary = SessionSummary(user: activeSession.user)
                if let profile = storedProfile(for: baseSummary.userID) {
                    profile.lastSyncAt = nil
                }
                summary = applyStoredProfile(
                    storedProfile(for: baseSummary.userID),
                    to: baseSummary
                )
            }

            try? modelContainer.mainContext.save()

            possibleDuplicateCount = ((try? MistiaSyncLocalStore.possibleDuplicateTransactions(
                in: modelContainer
            ).count) ?? 0)
            lastErrorMessage = nil
            setRequiresManualSyncAfterRestore(isConfigured)

            syncStatusTitle = mistiaLocalized(
                vi: "Đã khôi phục snapshot",
                en: "Snapshot restored",
                ja: "スナップショットを復元しました"
            )
            syncStatusDetail = isConfigured
                ? mistiaLocalized(
                    vi: "Mistia đã khôi phục dữ liệu local. Hãy kiểm tra dữ liệu rồi nhấn Đồng bộ ngay khi bạn sẵn sàng cập nhật cloud.",
                    en: "Mistia restored your local data. Review it first, then tap Sync now when you're ready to update the cloud.",
                    ja: "ローカルデータを復元しました。内容を確認してから、クラウドを更新する準備ができた時点で「今すぐ同期」を押してください。"
                )
                : mistiaLocalized(
                    vi: "Mistia đã khôi phục dữ liệu local từ snapshot đã chọn.",
                    en: "Mistia restored local data from the selected snapshot.",
                    ja: "選択したスナップショットからローカルデータを復元しました。"
                )
            syncStatusSystemImage = "externaldrive.badge.checkmark"
            updateAutoSyncLoopState()
            return result
        } catch {
            lastErrorMessage = error.localizedDescription
            updateAutoSyncLoopState()
            throw error
        }
    }

    func exportBackup(
        appVersion: String,
        appBuild: String
    ) throws -> MistiaBackupExportResult {
        let fallbackOwnerUserID = summary?.userID
            ?? currentSession?.user.id
            ?? MistiaSyncDeviceIdentity.current()

        return try MistiaBackupStore.exportBackup(
            from: modelContainer,
            fallbackOwnerUserID: fallbackOwnerUserID,
            appVersion: appVersion,
            appBuild: appBuild
        )
    }

    func handleConnectivityChanged(_ status: SessionNetworkStatus) {
        guard networkStatus != status else { return }

        let wasOffline = networkStatus == .disconnected
        networkStatus = status

        switch status {
        case .checking:
            break
        case .disconnected:
            reconnectValidationTask?.cancel()
            reconnectValidationTask = nil
            queuedAutoSyncTask?.cancel()
            queuedAutoSyncTask = nil
            if isSignedIn {
                applySignedInOfflineState()
            }
            updateAutoSyncLoopState()
        case .connected:
            updateAutoSyncLoopState()
            guard wasOffline, currentSession != nil else { return }

            reconnectValidationTask?.cancel()
            reconnectValidationTask = Task { [weak self] in
                await self?.revalidateRemoteSessionAfterReconnect()
            }
        }
    }

    func refreshedSession() async throws -> SupabaseAuthSession? {
        guard currentSession != nil else { return nil }
        return try await prepareRemoteSession()
    }

    func prepareRemoteSession() async throws -> SupabaseAuthSession {
        guard isConfigured else {
            throw SupabaseServiceError.configurationMissing
        }

        guard let currentSession else {
            throw SupabaseServiceError.missingSession
        }

        guard networkStatus != .disconnected else {
            applySignedInOfflineState()
            throw SessionRemoteAccessError.offline
        }

        do {
            let validSession = try await authService.refreshSessionIfNeeded(currentSession)
            self.currentSession = validSession
            remoteUnavailableReason = nil
            return validSession
        } catch {
            if invalidateSessionIfNeeded(for: error) {
                throw error
            }

            if isSignedIn {
                applyRemoteUnavailableState(error, restoringExistingSession: true)
            }
            throw error
        }
    }

    func resolveSyncConflict(
        id: UUID,
        resolution: MistiaSyncConflictResolution
    ) async {
        guard currentSession != nil, !isSyncInFlight else { return }

        isSyncInFlight = true
        defer { isSyncInFlight = false }

        do {
            let validSession = try await prepareRemoteSession()
            applySyncingState()
            try await syncCoordinator.resolveConflict(
                id: id,
                resolution: resolution,
                session: validSession
            )
            try normalizeCategoryHierarchyIfNeeded()
            lastSyncAt = .now
            lastErrorMessage = nil
            syncStatusTitle = mistiaLocalized(
                vi: "Conflict đã được xử lý",
                en: "Conflict resolved",
                ja: "競合を解決しました"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Mistia đã cập nhật lại bản ghi theo lựa chọn của bạn.",
                en: "Mistia updated the record with your selected resolution.",
                ja: "選択した内容でレコードを更新しました。"
            )
            syncStatusSystemImage = "checkmark.icloud"
            updateAutoSyncLoopState()
        } catch {
            applySyncErrorState(error)
            updateAutoSyncLoopState()
        }
    }

    func canHardPurge(
        entity: MistiaSyncEntity,
        recordID: UUID
    ) -> Bool {
        let hasQueuedMutation = syncCoordinator.hasQueuedMutation(entity: entity, recordID: recordID)
        let hasConflict = (try? MistiaSyncLocalStore.hasConflict(
            entity: entity,
            recordID: recordID,
            in: modelContainer
        )) ?? false
        return !hasQueuedMutation && !hasConflict
    }

    func recordUpsert(
        entity: MistiaSyncEntity,
        recordID: UUID,
        modifiedAt: Date,
        subjectUserIDOverride: UUID? = nil
    ) {
        let subjectUserID = subjectUserIDOverride
            ?? resolvedSubjectUserID(entity: entity, recordID: recordID)
        guard let subjectUserID else {
            return
        }
        try? MistiaRecordOwnershipStore.upsert(
            entity: entity,
            recordID: recordID,
            ownerUserID: subjectUserID,
            updatedAt: modifiedAt,
            in: modelContainer
        )
        guard currentSession != nil else { return }
        let queuedMutations = queueReadyMutations(
            for: [
                MistiaSyncMutation(
                    entity: entity,
                    recordID: recordID,
                    subjectUserID: subjectUserID,
                    kind: .upsert,
                    modifiedAt: modifiedAt,
                    baseVersion: 0,
                    deviceID: MistiaSyncDeviceIdentity.current()
                )
            ]
        )
        guard !queuedMutations.isEmpty else { return }
        syncCoordinator.queue(queuedMutations)
        scheduleQueuedSyncIfAllowed()
    }

    func recordDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        modifiedAt: Date,
        subjectUserIDOverride: UUID? = nil
    ) {
        let subjectUserID = subjectUserIDOverride
            ?? resolvedSubjectUserID(entity: entity, recordID: recordID)
        guard let subjectUserID else {
            return
        }
        try? MistiaRecordOwnershipStore.upsert(
            entity: entity,
            recordID: recordID,
            ownerUserID: subjectUserID,
            updatedAt: modifiedAt,
            in: modelContainer
        )
        guard currentSession != nil else { return }
        let queuedMutations = queueReadyMutations(
            for: [
                MistiaSyncMutation(
                    entity: entity,
                    recordID: recordID,
                    subjectUserID: subjectUserID,
                    kind: .delete,
                    modifiedAt: modifiedAt,
                    baseVersion: 0,
                    deviceID: MistiaSyncDeviceIdentity.current()
                )
            ]
        )
        guard !queuedMutations.isEmpty else { return }
        syncCoordinator.queue(queuedMutations)
        scheduleQueuedSyncIfAllowed()
    }

    func recordMutations(_ mutations: [MistiaSyncMutation]) {
        guard currentSession != nil else { return }
        let queuedMutations = queueReadyMutations(for: mutations)
        guard !queuedMutations.isEmpty else { return }
        syncCoordinator.queue(queuedMutations)
        scheduleQueuedSyncIfAllowed()
    }

    func protectedQueuedRecordIDs() -> Set<String> {
        syncCoordinator.queuedMutationIDs()
    }

    private func handleSignInFailure(_ error: Error, email: String) {
        if isEmailConfirmationError(error) {
            presentEmailConfirmationState(for: email)
            return
        }

        authPhase = .signIn

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Chưa thể kết nối",
                    en: "Can't connect right now",
                    ja: "現在接続できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Đăng nhập chưa thành công",
                en: "Couldn't sign in",
                ja: "ログインできませんでした"
            ),
            message: mistiaLocalized(
                vi: "Email hoặc mật khẩu chưa đúng. Kiểm tra lại rồi thử thêm lần nữa.",
                en: "The email or password is incorrect. Check them and try again.",
                ja: "メールアドレスまたはパスワードが正しくありません。確認してもう一度お試しください。"
            ),
            style: .error
        )
    }

    private func handleSignUpFailure(_ error: Error) {
        authPhase = .signUp

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Chưa thể tạo tài khoản",
                    en: "Can't create the account right now",
                    ja: "現在アカウントを作成できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isRateLimitedError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Bạn thao tác hơi nhanh",
                    en: "You're moving a bit fast",
                    ja: "少し操作が速すぎます"
                ),
                message: mistiaLocalized(
                    vi: "Hệ thống tạm chậm lại để bảo vệ tài khoản. Chờ một chút rồi thử lại nhé.",
                    en: "The service temporarily slowed things down to protect the account flow. Please wait a moment and try again.",
                    ja: "サービス保護のため一時的に制限されています。少し待ってからもう一度お試しください。"
                ),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Tạo tài khoản chưa thành công",
                en: "Couldn't create the account",
                ja: "アカウントを作成できませんでした"
            ),
            message: mistiaLocalized(
                vi: "Email này chưa sẵn sàng để tạo tài khoản mới. Thử đăng nhập hoặc dùng quên mật khẩu nhé.",
                en: "This email isn't ready for a new account right now. Try signing in or use password recovery instead.",
                ja: "このメールアドレスでは現在新しいアカウントを作成できません。ログインするか、パスワード再設定をお試しください。"
            ),
            style: .error
        )
    }

    private func handleGoogleSignInFailure(_ error: Error) {
        authPhase = .signIn

        if let serviceError = error as? SupabaseServiceError, case .oauthCancelled = serviceError {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Đã hủy đăng nhập Google",
                    en: "Google sign-in was cancelled",
                    ja: "Google ログインはキャンセルされました"
                ),
                message: mistiaLocalized(
                    vi: "Bạn có thể thử lại bất cứ lúc nào khi sẵn sàng.",
                    en: "You can try again any time when you're ready.",
                    ja: "準備ができたらいつでも再試行できます。"
                ),
                style: .info
            )
            return
        }

        if isGoogleSignInSetupError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Google Sign-In chưa sẵn sàng",
                    en: "Google sign-in isn't ready yet",
                    ja: "Google ログインの設定がまだ完了していません"
                ),
                message: googleSetupErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Google chưa thể kết nối",
                    en: "Google sign-in can't connect right now",
                    ja: "現在 Google ログインに接続できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Google đăng nhập chưa thành công",
                en: "Google sign-in couldn't finish",
                ja: "Google ログインを完了できませんでした"
            ),
            message: friendlyErrorMessage(for: error),
            style: .error
        )
    }

    private func handleRecoveryFailure(_ error: Error, isResend: Bool) {
        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: isResend ? "Chưa thể gửi lại email" : "Chưa thể gửi email",
                    en: isResend ? "Can't resend the email yet" : "Can't send the email yet",
                    ja: isResend ? "メールを再送できません" : "メールを送信できません"
                ),
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isRateLimitedError(error) {
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Bạn vừa yêu cầu gần đây",
                    en: "A request was just sent",
                    ja: "直前にリクエストされました"
                ),
                message: mistiaLocalized(
                    vi: "Chờ một chút rồi thử lại để tránh gửi email quá dày.",
                    en: "Please wait a bit before trying again to avoid sending too many emails.",
                    ja: "メール送信が多すぎないよう、少し待ってからもう一度お試しください。"
                ),
                style: .info
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: isResend ? "Email đang được xử lý" : "Yêu cầu đang được xử lý",
                en: isResend ? "The email request is being processed" : "The request is being processed",
                ja: isResend ? "メール再送を処理中です" : "リクエストを処理中です"
            ),
                message: mistiaLocalized(
                    vi: isResend
                    ? "Nếu tài khoản đang chờ xác nhận, hệ thống sẽ tiếp tục gửi email xác nhận đến đúng hộp thư."
                    : "Nếu email hợp lệ, hệ thống sẽ tiếp tục gửi email đặt lại mật khẩu đến đúng hộp thư.",
                en: isResend
                    ? "If the account is pending confirmation, the system will still deliver the confirmation email to the right inbox."
                    : "If the email is valid, the system will still deliver the reset email to the right inbox.",
                ja: isResend
                    ? "アカウントが確認待ちであれば、システムが正しい受信箱へ確認メールを送信します。"
                    : "有効なメールアドレスであれば、システムが正しい受信箱へ再設定メールを送信します。"
            ),
            style: .info
        )
    }

    private func presentEmailConfirmationState(for email: String) {
        authPhase = .verifyEmailPending
        authPendingEmail = email
        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Kiểm tra email để xác nhận",
                en: "Check your email to confirm",
                ja: "確認メールをチェックしてください"
            ),
            message: mistiaLocalized(
                vi: "Tài khoản của bạn đã được tạo. Mở email xác nhận rồi quay lại đăng nhập trong Mistia nhé.",
                en: "Your account has been created. Open the confirmation email, then come back and sign in to Mistia.",
                ja: "アカウントが作成されました。確認メールを開いてから Mistia にログインしてください。"
            ),
            style: .info
        )
    }

    func resolvePendingAuthentication(
        _ decision: SessionPendingAuthenticationDecision
    ) async {
        guard let state = pendingAuthenticationState else { return }
        clearPendingAuthenticationState()

        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        do {
            await beginAuthTransition()
            defer { endAuthTransition() }
            try resolvePendingAuthenticationState(state, decision: decision)
            try authService.persistSession(state.result.session)
            clearPendingAuthenticationState()
            try await finishAuthentication(
                state.result.session,
                restoringExistingSession: false
            )
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
            authBanner = SessionAuthBanner(
                title: mistiaLocalized(
                    vi: "Chưa thể hoàn tất đăng nhập",
                    en: "Couldn't finish signing in",
                    ja: "ログインを完了できませんでした"
                ),
                message: friendlyErrorMessage(for: error),
                style: .error
            )
        }
    }

    func clearPendingAuthenticationPrompt() {
        clearPendingAuthenticationState()
    }

    private func handleAuthenticationResult(
        _ result: SessionAuthResult,
        restoringExistingSession: Bool
    ) async throws {
        if let pendingState = try preparePendingAuthenticationState(for: result) {
            pendingAuthenticationState = pendingState
            pendingAuthenticationPrompt = pendingState.prompt
            return
        }

        await beginAuthTransition()
        defer { endAuthTransition() }
        try authService.persistSession(result.session)
        clearPendingAuthenticationState()
        try await finishAuthentication(
            result.session,
            restoringExistingSession: restoringExistingSession
        )
    }

    private func preparePendingAuthenticationState(
        for result: SessionAuthResult
    ) throws -> PendingAuthenticationState? {
        guard let launchState,
              let activeDescriptor = launchState.activeProfileDescriptor else {
            return nil
        }

        if activeDescriptor.kind == .guestUnbound {
            let guestHasData = try launchState.hasMeaningfulUserData(in: activeDescriptor)
            let existingCloudDescriptor = launchState.cloudProfileDescriptor(for: result.session.user.id)

            guard guestHasData else {
                let targetDescriptor = try launchState.ensureCloudProfile(for: result.session.user.id)
                if targetDescriptor.id != activeDescriptor.id {
                    try activateLocalProfile(targetDescriptor)
                }
                return nil
            }

            if existingCloudDescriptor != nil || result.origin == .existing {
                return PendingAuthenticationState(
                    result: result,
                    sourceGuestDescriptor: activeDescriptor,
                    prompt: SessionPendingAuthenticationPrompt(
                        kind: .keepOrDeleteGuestData,
                        title: mistiaLocalized(
                            vi: "Dữ liệu local guest đang tách riêng",
                            en: "Guest local data is separate",
                            ja: "ゲストのローカルデータは分離されています"
                        ),
                        message: mistiaLocalized(
                            vi: "Tài khoản này không được nhận dữ liệu local guest hiện tại. Giữ dữ liệu guest lại riêng hoặc xóa nó trước khi mở tài khoản.",
                            en: "This account can't automatically take the current guest local data. Keep the guest data separate or delete it before opening the account.",
                            ja: "このアカウントには現在のゲストローカルデータを自動で引き継げません。アカウントを開く前に、ゲストデータを分離したまま保持するか削除してください。"
                        )
                    )
                )
            }

            if result.origin == .unknown {
                return PendingAuthenticationState(
                    result: result,
                    sourceGuestDescriptor: activeDescriptor,
                    prompt: SessionPendingAuthenticationPrompt(
                        kind: .attachGuestData,
                        title: mistiaLocalized(
                            vi: "Chọn cách dùng dữ liệu local guest",
                            en: "Choose how to use the guest local data",
                            ja: "ゲストのローカルデータの使い方を選択してください"
                        ),
                        message: mistiaLocalized(
                            vi: "Mistia chưa thể xác định chắc dữ liệu local guest có nên gắn vào tài khoản này hay không. Bạn có thể gắn vào tài khoản hoặc giữ tách riêng.",
                            en: "Mistia can't confirm yet whether the current guest local data should attach to this account. You can attach it now or keep it separate.",
                            ja: "現在のゲストローカルデータをこのアカウントへ紐づけるべきか、Mistia がまだ確定できません。今すぐ紐づけるか、分離したまま保持できます。"
                        )
                    )
                )
            }

            if result.origin == .new {
                let claimedDescriptor = try launchState.claimGuestProfile(
                    activeDescriptor,
                    to: result.session.user.id
                )
                try activateLocalProfile(claimedDescriptor)
                return nil
            }
        }

        let targetUserID = result.session.user.id
        if let currentDescriptor = launchState.activeProfileDescriptor,
           currentDescriptor.kind == .cloudUser,
           currentDescriptor.cloudUserID == targetUserID {
            return nil
        }

        let targetDescriptor = try launchState.ensureCloudProfile(for: targetUserID)
        try activateLocalProfile(targetDescriptor)
        return nil
    }

    private func resolvePendingAuthenticationState(
        _ state: PendingAuthenticationState,
        decision: SessionPendingAuthenticationDecision
    ) throws {
        guard let launchState else { return }
        let targetUserID = state.result.session.user.id

        switch state.prompt.kind {
        case .keepOrDeleteGuestData:
            switch decision {
            case .keepGuestDataSeparate:
                let targetDescriptor = try launchState.ensureCloudProfile(for: targetUserID)
                try activateLocalProfile(targetDescriptor)
            case .deleteGuestData:
                let targetDescriptor = try launchState.ensureCloudProfile(for: targetUserID)
                try activateLocalProfile(targetDescriptor)
                try deleteLocalProfile(state.sourceGuestDescriptor)
            case .attachGuestData:
                let targetDescriptor = try launchState.ensureCloudProfile(for: targetUserID)
                try activateLocalProfile(targetDescriptor)
            }

        case .attachGuestData:
            switch decision {
            case .attachGuestData:
                let claimedDescriptor = try launchState.claimGuestProfile(
                    state.sourceGuestDescriptor,
                    to: targetUserID
                )
                try activateLocalProfile(claimedDescriptor)
            case .keepGuestDataSeparate:
                let targetDescriptor = try launchState.ensureCloudProfile(for: targetUserID)
                try activateLocalProfile(targetDescriptor)
            case .deleteGuestData:
                let targetDescriptor = try launchState.ensureCloudProfile(for: targetUserID)
                try activateLocalProfile(targetDescriptor)
                try deleteLocalProfile(state.sourceGuestDescriptor)
            }
        }
    }

    private func activateLocalProfile(
        _ descriptor: MistiaLocalProfileDescriptor
    ) throws {
        guard let launchState else { return }
        try launchState.activateProfile(descriptor)
        modelContainer = launchState.modelContainer
        syncCoordinator = SyncCoordinator(modelContainer: modelContainer)
        configureSyncCoordinator()
        requiresManualSyncAfterRestore = Self.storedManualSyncReviewRequired(
            in: userDefaults,
            profileID: descriptor.id
        )
        possibleDuplicateCount = ((try? MistiaSyncLocalStore.possibleDuplicateTransactions(
            in: modelContainer
        ).count) ?? 0)
    }

    private func deleteLocalProfile(
        _ descriptor: MistiaLocalProfileDescriptor
    ) throws {
        clearManualSyncReviewRequired(for: descriptor.id)
        if descriptor.id == activeLocalProfileID {
            try MistiaSyncLocalStore.clearAllProfileData(in: modelContainer)
            if launchState == nil {
                setLocalModeProfileUserID(nil)
            }
        }
        try launchState?.deleteProfile(descriptor)
    }

    private func beginAuthTransition() async {
        guard !isAuthTransitioning else { return }
        isAuthTransitioning = true
        await Task.yield()
    }

    private func endAuthTransition() {
        isAuthTransitioning = false
    }

    private func clearPendingAuthenticationState() {
        pendingAuthenticationState = nil
        pendingAuthenticationPrompt = nil
    }

    private func finishAuthentication(
        _ session: SupabaseAuthSession,
        restoringExistingSession: Bool
    ) async throws {
        try applyLocalAuthenticatedState(
            session,
            restoringExistingSession: restoringExistingSession
        )

        guard canPerformRemoteActions else {
            applySignedInOfflineState()
            updateAutoSyncLoopState()
            return
        }

        do {
            let validSession = try await prepareRemoteSession()
            try await syncAuthenticatedStateWithRemote(
                validSession,
                restoringExistingSession: restoringExistingSession
            )
        } catch {
            if invalidateSessionIfNeeded(for: error) {
                throw error
            }

            if isSignedIn {
                applyRemoteUnavailableState(
                    error,
                    restoringExistingSession: restoringExistingSession
                )
                return
            }

            throw error
        }
    }

    private func applyLocalAuthenticatedState(
        _ session: SupabaseAuthSession,
        restoringExistingSession: Bool
    ) throws {
        currentSession = session
        setLocalModeProfileUserID(nil)

        let baseSummary = SessionSummary(user: session.user)
        let storedProfile = try ensureStoredProfileExists(for: baseSummary)
        if launchState?.activeProfileDescriptor?.kind == .cloudUser || launchState == nil {
            try MistiaRecordOwnershipStore.ensureMissingOwnershipClaims(
                for: baseSummary.userID,
                in: modelContainer
            )
        }

        summary = applyStoredProfile(storedProfile, to: baseSummary)
        lastSyncAt = storedProfile.lastSyncAt
        lastErrorMessage = nil
        authBanner = nil
        authFieldErrors = [:]
        authPendingEmail = nil
        authPhase = .signIn
        activeAuthAction = nil
        requiresInitialSync = !hasCompletedCloudSyncHistory(storedProfile: storedProfile)
        initialSyncPreview = nil
        pendingInitialSyncChoice = nil

        if restoringExistingSession && networkStatus != .disconnected {
            syncStatusTitle = mistiaLocalized(
                vi: "Đang khôi phục phiên",
                en: "Restoring session",
                ja: "セッションを復元中"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Mistia đang kiểm tra tài khoản đã đăng nhập trước đó.",
                en: "Mistia is checking for a previously signed-in account.",
                ja: "以前のログイン状態を確認しています。"
            )
            syncStatusSystemImage = "key.horizontal"
        }
    }

    private func syncAuthenticatedStateWithRemote(
        _ session: SupabaseAuthSession,
        restoringExistingSession: Bool
    ) async throws {
        currentSession = session
        let baseSummary = SessionSummary(user: session.user)
        let storedProfile = try ensureStoredProfileExists(for: baseSummary)
        let remoteProfile = try await syncProfileWithRemote(
            session: session,
            baseSummary: baseSummary,
            storedProfile: storedProfile
        )
        await cacheRemoteAvatarIfNeeded(
            for: storedProfile,
            remoteAvatarURL: remoteProfile.avatarURL ?? baseSummary.avatarURL
        )
        summary = applyStoredProfile(
            storedProfile,
            to: baseSummary,
            remoteAvatarURL: remoteProfile.avatarURL
        )
        try normalizeCategoryHierarchyIfNeeded()
        lastSyncAt = storedProfile.lastSyncAt
        lastErrorMessage = nil
        remoteUnavailableReason = nil
        authBanner = nil
        authFieldErrors = [:]
        authPendingEmail = nil
        authPhase = .signIn
        activeAuthAction = nil
        requiresInitialSync = !hasCompletedCloudSyncHistory(storedProfile: storedProfile)
        initialSyncPreview = nil
        pendingInitialSyncChoice = nil
        syncStatusTitle = mistiaLocalized(
            vi: "Đã đăng nhập",
            en: "Signed in",
            ja: "ログイン済み"
        )
        syncStatusDetail = mistiaLocalized(
            vi: restoringExistingSession
                ? "Phiên đã được khôi phục. Nhấn Sync ngay khi bạn muốn đồng bộ với cloud."
                : "Đăng nhập thành công. Nhấn Sync ngay để bắt đầu đồng bộ dữ liệu.",
            en: restoringExistingSession
                ? "Your session has been restored. Tap Sync now when you want to sync with the cloud."
                : "Sign-in succeeded. Tap Sync now to start syncing your data.",
            ja: restoringExistingSession
                ? "セッションを復元しました。クラウドと同期するには「今すぐ同期」を押してください。"
                : "ログインに成功しました。データ同期を始めるには「今すぐ同期」を押してください。"
        )
        syncStatusSystemImage = "checkmark.circle"
        updateAutoSyncLoopState()
    }

    private func applySignedInOfflineState() {
        guard isSignedIn else { return }
        lastErrorMessage = nil
        remoteUnavailableReason = mistiaLocalized(
            vi: "Không có kết nối mạng. Hãy kết nối lại để đồng bộ, chỉnh sửa hồ sơ hoặc quản lý gia đình.",
            en: "No network connection. Reconnect to sync, edit your profile, or manage family features.",
            ja: "ネットワーク接続がありません。同期、プロフィール編集、家族機能の管理を行うには再接続してください。"
        )
        syncStatusTitle = mistiaLocalized(
            vi: "Đang ngoại tuyến",
            en: "Offline",
            ja: "オフライン"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Không có kết nối mạng. Hãy kết nối lại để đồng bộ, chỉnh sửa hồ sơ hoặc quản lý gia đình.",
            en: "No network connection. Reconnect to sync, edit your profile, or manage family features.",
            ja: "ネットワーク接続がありません。同期、プロフィール編集、家族機能の管理を行うには再接続してください。"
        )
        syncStatusSystemImage = "wifi.slash"
    }

    private func applyRemoteUnavailableState(
        _ error: Error,
        restoringExistingSession: Bool
    ) {
        if error is SessionRemoteAccessError || error is URLError || networkStatus == .disconnected {
            applySignedInOfflineState()
            updateAutoSyncLoopState()
            return
        }

        let message = friendlyErrorMessage(for: error)
        lastErrorMessage = message
        remoteUnavailableReason = message
        syncStatusTitle = restoringExistingSession
            ? mistiaLocalized(
                vi: "Phiên đã được giữ lại trên máy",
                en: "The session was kept on this device",
                ja: "この端末ではセッションを保持しています"
            )
            : mistiaLocalized(
                vi: "Đã đăng nhập trên máy này",
                en: "Signed in on this device",
                ja: "この端末ではログイン済みです"
            )
        syncStatusDetail = message
        syncStatusSystemImage = syncErrorSystemImage(for: error)
        updateAutoSyncLoopState()
    }

    private func revalidateRemoteSessionAfterReconnect() async {
        guard currentSession != nil else { return }

        do {
            let validSession = try await prepareRemoteSession()
            try await syncAuthenticatedStateWithRemote(
                validSession,
                restoringExistingSession: true
            )
        } catch {
            guard isSignedIn else { return }
            applyRemoteUnavailableState(error, restoringExistingSession: true)
        }
    }

    private func invalidateSessionIfNeeded(for error: Error) -> Bool {
        guard isSessionInvalidationError(error) else { return false }

        try? authService.clearPersistedSession()
        if launchState == nil {
            setLocalModeProfileUserID(activeLocalProfileUserID ?? currentSession?.user.id)
        }
        clearSessionRuntimeState()
        applySignedOutState(preservingBanner: true)
        authBanner = SessionAuthBanner(
            title: mistiaLocalized(
                vi: "Phiên đã hết hạn sau khi kết nối lại",
                en: "Session expired after reconnect",
                ja: "再接続後にセッションの期限が切れました"
            ),
            message: friendlyErrorMessage(for: error),
            style: .error
        )
        return true
    }

    private func isSessionInvalidationError(_ error: Error) -> Bool {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .missingRefreshToken:
                return true
            case .serverMessage(let message):
                let normalized = message.lowercased()
                return normalized.contains("401")
                    || normalized.contains("unauthorized")
                    || normalized.contains("jwt")
                    || normalized.contains("refresh token")
            case .configurationMissing,
                    .invalidURL,
                    .invalidResponse,
                    .missingSession,
                    .oauthCancelled,
                    .googleClientIDMissing,
                    .googleServerClientIDMissing,
                    .googleCallbackSchemeMissing,
                    .googlePresentationContextMissing,
                    .googleTokensMissing:
                return false
            }
        }

        let message = errorMessage(for: error)
        return message.contains("401")
            || message.contains("unauthorized")
            || message.contains("jwt")
    }

    private func applyConfigurationMissingState() {
        stopLiveSyncLoop()
        reconnectValidationTask?.cancel()
        reconnectValidationTask = nil
        MistiaSyncBackgroundScheduler.shared.cancelPendingRefresh()
        summary = nil
        currentSession = nil
        remoteUnavailableReason = nil
        requiresInitialSync = false
        initialSyncPreview = nil
        pendingInitialSyncChoice = nil
        authPhase = .signIn
        authBanner = nil
        authPendingEmail = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        syncStatusTitle = mistiaLocalized(
            vi: "Chưa cấu hình dịch vụ đồng bộ",
            en: "Cloud sync isn't configured",
            ja: "クラウド同期が未設定です"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Điền URL dịch vụ và public key trong MistiaSyncConfig.plist rồi build lại app.",
            en: "Fill in the service URL and public key in MistiaSyncConfig.plist, then rebuild the app.",
            ja: "MistiaSyncConfig.plist にサービス URL と公開キーを設定してから再ビルドしてください。"
        )
        syncStatusSystemImage = "wrench.and.screwdriver"
    }

    private func disableShortcutIfNeededOnLogout() {
        let shortcutKindsRequiringAuth: Set<MistiaShortcutKind> = [
            .familyOverview,
            .familyMember,
            .syncNow
        ]
        let storedKind = MistiaShortcutKind(rawValue: userDefaults.string(forKey: MistiaAppStorageKey.mistiaShortcutKind) ?? "")
        let isEnabled = userDefaults.bool(forKey: MistiaAppStorageKey.mistiaShortcutEnabled)

        if isEnabled, let kind = storedKind, shortcutKindsRequiringAuth.contains(kind) {
            userDefaults.set(false, forKey: MistiaAppStorageKey.mistiaShortcutEnabled)
        }
    }

    private func applySignedOutState(preservingBanner: Bool = false) {
        stopLiveSyncLoop()
        reconnectValidationTask?.cancel()
        reconnectValidationTask = nil
        MistiaSyncBackgroundScheduler.shared.cancelPendingRefresh()
        summary = nil
        currentSession = nil
        remoteUnavailableReason = nil
        requiresInitialSync = false
        initialSyncPreview = nil
        pendingInitialSyncChoice = nil
        authPhase = .signIn
        if !preservingBanner {
            authBanner = nil
        }
        authPendingEmail = nil
        authFieldErrors = [:]
        activeAuthAction = nil
        let guestUnboundHasData = currentGuestUnboundHasMeaningfulData()
        switch activeLocalContext {
        case .guestAttached:
            syncStatusTitle = mistiaLocalized(
                vi: "Đang dùng local",
                en: "Local mode",
                ja: "ローカルモード"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Bạn đang chỉnh sửa dữ liệu cục bộ của profile trước đó. Thay đổi chỉ đồng bộ khi đăng nhập lại đúng tài khoản.",
                en: "You're editing local data for the previous profile. Changes sync only after signing back into that same account.",
                ja: "以前のプロフィールのローカルデータを編集中です。変更は同じアカウントで再ログインした場合のみ同期されます。"
            )
            syncStatusSystemImage = "externaldrive.badge.person.crop"
        case .guestUnbound:
            syncStatusTitle = mistiaLocalized(
                vi: guestUnboundHasData ? "Guest local" : "Guest sạch",
                en: guestUnboundHasData ? "Guest local" : "Clean guest",
                ja: guestUnboundHasData ? "ゲストローカル" : "クリーンゲスト"
            )
            syncStatusDetail = mistiaLocalized(
                vi: guestUnboundHasData
                    ? "Dữ liệu local guest trên máy này đang tách riêng. Bạn có thể tiếp tục chỉnh sửa và quyết định sau sẽ gắn nó với tài khoản nào."
                    : "Thiết bị hiện chưa gắn với dữ liệu local của tài khoản nào. Đăng nhập để tải dữ liệu tài khoản của bạn hoặc bắt đầu dùng local mới.",
                en: guestUnboundHasData
                    ? "This device has separate guest local data. You can keep editing it now and decide later whether it should stay separate or attach to an account."
                    : "This device isn't attached to any saved account data right now. Sign in to load your account, or start fresh with new local data.",
                ja: guestUnboundHasData
                    ? "この端末には独立したゲストのローカルデータがあります。今のまま編集を続け、後でどのアカウントに紐づけるか決められます。"
                    : "この端末は現在どの保存済みアカウントデータにも紐づいていません。ログインしてアカウントデータを読み込むか、新しいローカルデータから始められます。"
            )
            syncStatusSystemImage = guestUnboundHasData
                ? "externaldrive.badge.plus"
                : "person.crop.circle.badge.questionmark"
        case .authenticated, nil:
            syncStatusTitle = mistiaLocalized(
                vi: "Chưa đăng nhập",
                en: "Signed out",
                ja: "未ログイン"
            )
            syncStatusDetail = mistiaLocalized(
                vi: "Đăng nhập để đồng bộ ví, danh mục, giao dịch và kế hoạch giữa các thiết bị.",
                en: "Sign in to sync wallets, categories, transactions, and planning data across devices.",
                ja: "ログインするとウォレット、カテゴリ、取引、計画データを端末間で同期できます。"
            )
            syncStatusSystemImage = "person.crop.circle.badge.plus"
        }
    }

    private func applySyncingState() {
        syncStatusTitle = mistiaLocalized(
            vi: "Đang đồng bộ",
            en: "Syncing",
            ja: "同期中"
        )
        syncStatusDetail = mistiaLocalized(
            vi: "Mistia đang đẩy thay đổi local và kéo dữ liệu mới từ cloud.",
            en: "Mistia is pushing local changes and pulling the latest cloud data.",
            ja: "ローカル変更を送信し、最新のクラウドデータを取得しています。"
        )
        syncStatusSystemImage = "arrow.triangle.2.circlepath.circle"
    }

    private func applySyncErrorState(_ error: Error) {
        lastErrorMessage = friendlyErrorMessage(for: error)
        syncStatusTitle = syncErrorTitle(for: error)
        syncStatusDetail = friendlyErrorMessage(for: error)
        syncStatusSystemImage = syncErrorSystemImage(for: error)
    }

    private func isInfrastructureAuthError(_ error: Error) -> Bool {
        if error is URLError || error is SessionRemoteAccessError {
            return true
        }

        guard let serviceError = error as? SupabaseServiceError else {
            return false
        }

        switch serviceError {
        case .configurationMissing, .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .googlePresentationContextMissing, .googleTokensMissing:
            return true
        case .serverMessage, .oauthCancelled, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing:
            return false
        }
    }

    private func isEmailConfirmationError(_ error: Error) -> Bool {
        errorMessage(for: error).contains("email not confirmed")
            || errorMessage(for: error).contains("confirm your email")
    }

    private func isRateLimitedError(_ error: Error) -> Bool {
        let message = errorMessage(for: error)
        return message.contains("rate limit") || message.contains("too many requests")
    }

    private func isGoogleSignInSetupError(_ error: Error) -> Bool {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing:
                return true
            case .configurationMissing, .invalidURL, .invalidResponse, .serverMessage, .missingSession, .missingRefreshToken, .oauthCancelled, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        let message = errorMessage(for: error)
        return message.contains("provider is not enabled")
            || message.contains("unsupported provider")
            || message.contains("client id")
            || message.contains("callback")
    }

    private func googleSetupErrorMessage(for error: Error) -> String {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .googleClientIDMissing, .googleServerClientIDMissing:
                return mistiaLocalized(
                    vi: "Điền Google iOS client ID và Google web client ID trong MistiaInfo.plist rồi build lại app.",
                    en: "Fill in the Google iOS client ID and Google web client ID in MistiaInfo.plist, then rebuild the app.",
                    ja: "MistiaInfo.plist に Google iOS client ID と Google web client ID を設定してから再ビルドしてください。"
                )
            case .googleCallbackSchemeMissing(let expected):
                return mistiaLocalized(
                    vi: "Thêm URL scheme Google `\(expected)` vào MistiaInfo.plist rồi build lại app.",
                    en: "Add the Google URL scheme `\(expected)` to MistiaInfo.plist, then rebuild the app.",
                    ja: "Google の URL スキーム `\(expected)` を MistiaInfo.plist に追加してから再ビルドしてください。"
                )
            case .configurationMissing, .invalidURL, .invalidResponse, .serverMessage, .missingSession, .missingRefreshToken, .oauthCancelled, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        return mistiaLocalized(
            vi: "Google Sign-In của app này còn thiếu cấu hình iOS cần thiết. Kiểm tra lại client ID và URL scheme rồi thử lại nhé.",
            en: "This build is missing the iOS settings Google Sign-In needs. Check the client IDs and URL scheme, then try again.",
            ja: "このビルドでは Google ログインに必要な iOS 設定が不足しています。client ID と URL スキームを確認してから再試行してください。"
        )
    }

    private func infrastructureErrorMessage(for error: Error) -> String {
        if error is URLError || error is SessionRemoteAccessError {
            return mistiaLocalized(
                vi: "Mistia chưa thể kết nối đến dịch vụ đồng bộ. Kiểm tra mạng rồi thử lại nhé.",
                en: "Mistia can't reach the sync service right now. Check your connection and try again.",
                ja: "現在 Mistia は同期サービスに接続できません。通信状況を確認してから再度お試しください。"
            )
        }

        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .configurationMissing:
                return mistiaLocalized(
                    vi: "Dịch vụ đồng bộ chưa được cấu hình đầy đủ trong app này.",
                    en: "The sync service hasn't been configured completely in this build.",
                    ja: "このビルドでは同期サービスの設定がまだ完了していません。"
                )
            case .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCancelled, .serverMessage, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        return mistiaLocalized(
            vi: "Hệ thống xác thực đang tạm bận. Thử lại sau ít phút nhé.",
            en: "The authentication service is temporarily busy. Please try again in a moment.",
            ja: "認証サービスが一時的に混み合っています。少し待ってからお試しください。"
        )
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let rawServerMessage: String?
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .serverMessage(let message):
                rawServerMessage = message
            case .configurationMissing, .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCancelled, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing, .googlePresentationContextMissing, .googleTokensMissing:
                rawServerMessage = nil
            }
        } else {
            rawServerMessage = nil
        }

        if let decodingError = error as? DecodingError {
            return localizedDecodingErrorMessage(decodingError)
        }

        let rawMessage = rawServerMessage ?? error.localizedDescription
        let message = rawMessage.lowercased()

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return mistiaLocalized(
                vi: "Phiên đăng nhập hết hạn hoặc không hợp lệ. Thử đăng nhập lại nhé.",
                en: "Session expired or invalid. Please try signing in again.",
                ja: "セッションの期限が切れたか無効です。もう一度ログインをお試しください。"
            )
        }

        if message.contains("404") || message.contains("not found") {
            return mistiaLocalized(
                vi: "Máy chủ chưa sẵn sàng (Lỗi 404). Có thể bạn chưa chạy database migrations trên Supabase.",
                en: "Server not ready (Error 404). You might need to run database migrations on Supabase.",
                ja: "サーバーの準備ができていません (Error 404)。Supabase でデータベースのマイグレーションを実行する必要があるかもしれません。"
            )
        }

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return mistiaLocalized(
                vi: "Bị từ chối truy cập (Lỗi 403). Kiểm tra lại quyền hạn (RLS) trên database Supabase nhé.",
                en: "Access denied (Error 403). Please check your database Row Level Security (RLS) policies.",
                ja: "アクセスが拒否されました (Error 403)。Supabase のデータベース権限 (RLS) を確認してください。"
            )
        }

        if message.contains("400") || message.contains("bad request") {
            return mistiaLocalized(
                vi: "Yêu cầu không hợp lệ (Lỗi 400). Kiểm tra lại cấu hình Client ID và URL Scheme của Google nhé.",
                en: "Bad request (Error 400). Please check your Google Client ID and URL Scheme configuration.",
                ja: "不正なリクエストです (Error 400)。Google の Client ID と URL スキームの設定を確認してください。"
            )
        }

        if message.contains("connection") || message.contains("offline") {
            return mistiaLocalized(
                vi: "Không có kết nối mạng. Kiểm tra wifi hoặc 4G rồi thử lại nhé.",
                en: "No internet connection. Check your Wi-Fi or cellular data and try again.",
                ja: "ネットワーク接続がありません. Wi-Fi またはデータ通信を確認してもう一度お試しください。"
            )
        }

        if message.contains("data couldn") || message.contains("missing") || message.contains("no data") {
            return mistiaLocalized(
                vi: "Không đọc được dữ liệu sync trả về. Khả năng response từ Supabase đang thiếu dữ liệu hoặc sai định dạng.",
                en: "The sync response couldn't be read. Supabase may be returning missing or malformed data.",
                ja: "同期レスポンスを読み取れませんでした。Supabase が不足または不正な形式のデータを返している可能性があります。"
            )
        }

        return rawMessage
    }

    private func localizedDecodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return mistiaLocalized(
                vi: "Supabase đang trả về dữ liệu thiếu trường `\(key.stringValue)`. Có thể schema cloud chưa khớp với app hiện tại.",
                en: "Supabase is returning data without the `\(key.stringValue)` field. The cloud schema may be out of sync with this app build.",
                ja: "Supabase が `\(key.stringValue)` フィールドのないデータを返しています。クラウドスキーマがこのアプリのビルドと一致していない可能性があります。"
            )
        case .typeMismatch(_, _), .valueNotFound(_, _), .dataCorrupted(_):
            return mistiaLocalized(
                vi: "Dữ liệu đồng bộ từ Supabase không đúng định dạng app đang cần. Kiểm tra lại schema bảng hoặc dữ liệu cũ trên cloud.",
                en: "The sync data from Supabase doesn't match the format this app expects. Check the table schema or older cloud data.",
                ja: "Supabase からの同期データが、このアプリが想定する形式と一致しません。テーブルスキーマまたは既存のクラウドデータを確認してください。"
            )
        @unknown default:
            return mistiaLocalized(
                vi: "Không đọc được dữ liệu đồng bộ từ Supabase. Kiểm tra lại schema và dữ liệu cloud nhé.",
                en: "The sync data from Supabase couldn't be read. Please check the cloud schema and data.",
                ja: "Supabase からの同期データを読み取れませんでした。クラウドのスキーマとデータを確認してください。"
            )
        }
    }

    private func syncErrorTitle(for error: Error) -> String {
        if error is URLError || error is SessionRemoteAccessError {
            return mistiaLocalized(
                vi: "Đồng bộ đang chờ mạng",
                en: "Sync is waiting for the network",
                ja: "同期はネットワーク待ちです"
            )
        }

        let message = errorMessage(for: error)

        if message.contains("failed to decode remote data") {
            return mistiaLocalized(
                vi: "Dữ liệu cloud hiện có không khớp format app đang cần.",
                en: "The existing cloud data doesn't match the format this app expects.",
                ja: "既存のクラウドデータが、このアプリの想定フォーマットと一致していません。"
            )
        }

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return mistiaLocalized(
                vi: "Đồng bộ bị từ chối",
                en: "Sync access denied",
                ja: "同期アクセスが拒否されました"
            )
        }

        if message.contains("404") || message.contains("not found") || message.contains("relation") {
            return mistiaLocalized(
                vi: "Thiếu bảng đồng bộ",
                en: "Sync tables missing",
                ja: "同期テーブルが見つかりません"
            )
        }

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return mistiaLocalized(
                vi: "Phiên sync không hợp lệ",
                en: "Sync session invalid",
                ja: "同期セッションが無効です"
            )
        }

        return mistiaLocalized(
            vi: "Đồng bộ cần kiểm tra cấu hình",
            en: "Sync needs configuration checks",
            ja: "同期設定の確認が必要です"
        )
    }

    private func syncErrorSystemImage(for error: Error) -> String {
        if error is URLError || error is SessionRemoteAccessError {
            return "wifi.exclamationmark"
        }

        let message = errorMessage(for: error)

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return "lock.slash"
        }

        if message.contains("404") || message.contains("not found") || message.contains("relation") {
            return "externaldrive.badge.exclamationmark"
        }

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return "key.slash"
        }

        return "exclamationmark.icloud"
    }

    private func errorMessage(for error: Error) -> String {
        error.localizedDescription.lowercased()
    }

    private func resolvedSubjectUserID(
        entity: MistiaSyncEntity,
        recordID: UUID,
        fallbackSubjectUserID: UUID? = nil
    ) -> UUID? {
        if let ownerUserID = try? MistiaRecordOwnershipStore.ownerUserID(
            entity: entity,
            recordID: recordID,
            in: modelContainer
        ) {
            return ownerUserID
        }

        if let fallbackSubjectUserID {
            return fallbackSubjectUserID
        }

        if let provided = subjectUserIDProvider?() {
            return provided
        }

        if let activeLocalProfileUserID {
            return activeLocalProfileUserID
        }

        return currentSession?.user.id
    }

    private func hasCompletedCloudSyncHistory(
        storedProfile: UserAccountProfile? = nil
    ) -> Bool {
        if storedProfile?.lastSyncAt != nil || lastSyncAt != nil {
            return true
        }

        let context = modelContainer.mainContext

        return hasAnyRemoteBackedRecord(in: context)
            || ((try? context.fetch(FetchDescriptor<SyncConflict>())) ?? []).isEmpty == false
    }

    private func hasAnyRemoteBackedRecord(in context: ModelContext) -> Bool {
        hasRemoteBackedRecord(LedgerWallet.self, in: context, predicate: #Predicate<LedgerWallet> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(CreditCardProfile.self, in: context, predicate: #Predicate<CreditCardProfile> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(TransactionCategory.self, in: context, predicate: #Predicate<TransactionCategory> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(LedgerTransaction.self, in: context, predicate: #Predicate<LedgerTransaction> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(BudgetPlan.self, in: context, predicate: #Predicate<BudgetPlan> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(SavingsGoal.self, in: context, predicate: #Predicate<SavingsGoal> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(RecurringBillPlan.self, in: context, predicate: #Predicate<RecurringBillPlan> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(InstallmentPlan.self, in: context, predicate: #Predicate<InstallmentPlan> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(DueOccurrenceRecord.self, in: context, predicate: #Predicate<DueOccurrenceRecord> { $0.remoteVersion > 0 })
    }

    private func hasRemoteBackedRecord<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext,
        predicate: Predicate<Model>
    ) -> Bool {
        var descriptor = FetchDescriptor<Model>(predicate: predicate)
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func startLiveSyncLoop() {
        stopLiveSyncLoop()
        liveSyncTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let delay = max(5, self.nextAutomaticSyncDate?.timeIntervalSinceNow ?? Self.AUTOMATIC_SYNC_INTERVAL)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                guard !self.autoSyncPaused, self.isReadyForAutomaticSync else {
                    continue
                }
                guard self.lastSyncAt.map({ Date().timeIntervalSince($0) >= Self.AUTOMATIC_SYNC_INTERVAL }) ?? true else {
                    continue
                }

                _ = await self.runMergeSync(trigger: .automaticLoop, showProgress: false)
            }
        }
    }

    private func stopLiveSyncLoop() {
        liveSyncTask?.cancel()
        liveSyncTask = nil
    }

    private func pauseAutoSyncLoop() {
        autoSyncPaused = true
    }

    private func resumeAutoSyncLoop() {
        autoSyncPaused = false
    }

    private func updateAutoSyncLoopState() {
        if requiresInitialSync && hasCompletedCloudSyncHistory() {
            requiresInitialSync = false
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
        }

        guard isReadyForAutomaticSync else {
            stopLiveSyncLoop()
            MistiaSyncBackgroundScheduler.shared.cancelPendingRefresh()
            return
        }

        startLiveSyncLoop()
        MistiaSyncBackgroundScheduler.shared.scheduleNextRefresh(after: nextAutomaticSyncDate)
    }

    private func shouldRunForegroundCatchUp() -> Bool {
        guard isReadyForAutomaticSync, !isSyncInFlight else { return false }
        guard let lastSyncAt else { return true }
        return Date().timeIntervalSince(lastSyncAt) >= Self.AUTOMATIC_SYNC_INTERVAL
    }

    private func runInitialSyncFlow(showProgress: Bool = true) async -> Bool {
        return await drainSyncQueue(showProgress: showProgress)
    }

    private func runMergeSync(
        trigger: SessionSyncTrigger,
        showProgress: Bool = true
    ) async -> Bool {
        guard currentSession != nil, !isSyncInFlight else { return false }
        if trigger != .manual {
            guard isReadyForAutomaticSync else { return false }
        }

        isSyncInFlight = true

        if showProgress {
            shouldShowSyncProgress = true
            isCheckingData = false
            syncStartTime = Date()
            syncProgress = 0.0
            syncTimeRemaining = nil
            applySyncingState()
        }

        defer {
            isSyncInFlight = false
            if showProgress {
                shouldShowSyncProgress = false
                isCheckingData = false
                syncProgress = nil
                syncTimeRemaining = nil
                syncStartTime = nil
            }
        }

        do {
            let validSession = try await prepareRemoteSession()
            try normalizeCategoryHierarchyIfNeeded()
            let result = try await syncCoordinator.sync(session: validSession)
            lastSyncAt = .now
            lastErrorMessage = nil
            possibleDuplicateCount = ((try? MistiaSyncLocalStore.possibleDuplicateTransactions(
                in: modelContainer
            ).count) ?? 0)

            if let userID = summary?.userID, let profile = storedProfile(for: userID) {
                profile.lastSyncAt = lastSyncAt
                try? modelContainer.mainContext.save()
            }

            if showProgress || trigger == .foregroundCatchUp {
                syncStatusTitle = mistiaLocalized(
                    vi: "Đồng bộ đã hoàn tất",
                    en: "Sync completed",
                    ja: "同期が完了しました"
                )
                if possibleDuplicateCount > 0 {
                    syncStatusDetail = result.statusMessage + " " + mistiaLocalized(
                        vi: "Mistia thấy \(possibleDuplicateCount) giao dịch có thể bị trùng và đang giữ an toàn cả hai bản ghi.",
                        en: "Mistia found \(possibleDuplicateCount) possible duplicate transactions and kept both records safely.",
                        ja: "重複の可能性がある取引を \(possibleDuplicateCount) 件検出したため, 両方のレコードを安全に保持しています。"
                    )
                } else {
                    syncStatusDetail = result.statusMessage
                }
                syncStatusSystemImage = "checkmark.icloud"
            }

            if showProgress {
                try? await Task.sleep(for: .seconds(0.5))
            }

            if let postSyncRefreshHandler {
                await postSyncRefreshHandler()
            }

            updateAutoSyncLoopState()
            if pendingQueuedAutoSync {
                scheduleQueuedSyncIfAllowed()
            }
            return true
        } catch {
            if showProgress || trigger == .manual || trigger == .foregroundCatchUp {
                applySyncErrorState(error)
                if showProgress {
                    try? await Task.sleep(for: .seconds(0.5))
                }
            } else {
                lastErrorMessage = friendlyErrorMessage(for: error)
            }
            updateAutoSyncLoopState()
            return false
        }
    }

    private func drainSyncQueue(showProgress: Bool = true) async -> Bool {
        isSyncInFlight = true
        
        if showProgress {
            shouldShowSyncProgress = true
            isCheckingData = true
            syncStartTime = Date()
            syncProgress = 0.0
            syncTimeRemaining = nil
        }
        
        defer {
            isSyncInFlight = false
            if showProgress {
                shouldShowSyncProgress = false
                isCheckingData = false
                syncProgress = nil
                syncTimeRemaining = nil
                syncStartTime = nil
            }
        }

        do {
            let validSession = try await prepareRemoteSession()
            try normalizeCategoryHierarchyIfNeeded()
            let result: MistiaSyncResult

            if requiresInitialSync {
                if showProgress {
                    try await Task.sleep(for: .seconds(1.5))
                }
                let preview = try await syncCoordinator.previewInitialSync(session: validSession)
                if showProgress {
                    isCheckingData = false
                }

                if preview.requiresChoice, pendingInitialSyncChoice == nil {
                    initialSyncPreview = preview
                    if showProgress {
                        syncStatusTitle = mistiaLocalized(
                            vi: "Cần chọn cách đồng bộ lần đầu",
                            en: "Choose how to run the first sync",
                            ja: "初回同期の方法を選んでください"
                        )
                        syncStatusDetail = mistiaLocalized(
                            vi: "Cloud và máy này đều đã có dữ liệu. Chọn cách hợp nhất an toàn trước khi tiếp tục.",
                            en: "Both this device and the cloud already have data. Choose the safest way to continue.",
                            ja: "この端末とクラウドの両方にデータがあります。続行方法を選択してください。"
                        )
                        syncStatusSystemImage = "arrow.triangle.branch"
                    }
                    return false
                }

                if showProgress {
                    syncStatusTitle = mistiaLocalized(
                        vi: "Đang đồng bộ lần đầu",
                        en: "Running initial sync",
                        ja: "初回同期を実行中"
                    )
                    syncStatusDetail = mistiaLocalized(
                        vi: "Mistia đang kiểm tra local và cloud rồi áp dụng chiến lược đồng bộ an toàn.",
                        en: "Mistia is comparing local and cloud data, then applying the safest sync strategy.",
                        ja: "ローカルとクラウドを比較して、安全な同期方法を適用しています。"
                    )
                    syncStatusSystemImage = "arrow.triangle.2.circlepath"
                }

                let initialChoice: MistiaInitialSyncChoice
                switch preview.mode {
                case .idle:
                    initialChoice = .mergeSafely
                case .uploadLocal:
                    initialChoice = .useDevice
                case .downloadCloud:
                    initialChoice = .useCloud
                case .choose:
                    initialChoice = pendingInitialSyncChoice ?? .mergeSafely
                }

                result = try await syncCoordinator.performInitialSync(
                    session: validSession,
                    choice: initialChoice
                )
                requiresInitialSync = false
                initialSyncPreview = nil
                pendingInitialSyncChoice = nil
                updateAutoSyncLoopState()
            } else {
                if showProgress {
                    applySyncingState()
                    isCheckingData = false
                }
                result = try await syncCoordinator.sync(session: validSession)
            }

            try normalizeCategoryHierarchyIfNeeded()
            lastSyncAt = .now
            lastErrorMessage = nil
            possibleDuplicateCount = ((try? MistiaSyncLocalStore.possibleDuplicateTransactions(
                in: modelContainer
            ).count) ?? 0)
            
            if showProgress {
                syncStatusTitle = mistiaLocalized(
                    vi: "Đồng bộ đã hoàn tất",
                    en: "Sync completed",
                    ja: "同期が完了しました"
                )
                if possibleDuplicateCount > 0 {
                    syncStatusDetail = result.statusMessage + " " + mistiaLocalized(
                        vi: "Mistia thấy \(possibleDuplicateCount) giao dịch có thể bị trùng và đang giữ an toàn cả hai bản ghi.",
                        en: "Mistia found \(possibleDuplicateCount) possible duplicate transactions and kept both records safely.",
                        ja: "重複の可能性がある取引を \(possibleDuplicateCount) 件検出したため, 両方のレコードを安全に保持しています。"
                    )
                } else {
                    syncStatusDetail = result.statusMessage
                }
                syncStatusSystemImage = "checkmark.icloud"
            }

            if let userID = summary?.userID, let profile = storedProfile(for: userID) {
                profile.lastSyncAt = .now
                try? modelContainer.mainContext.save()
            }

            if let postSyncRefreshHandler {
                await postSyncRefreshHandler()
            }

            if showProgress {
                try? await Task.sleep(for: .seconds(0.5))
            }
            updateAutoSyncLoopState()
            if pendingQueuedAutoSync {
                scheduleQueuedSyncIfAllowed()
            }
            return true
        } catch {
            if showProgress {
                applySyncErrorState(error)
            }
            if showProgress {
                try? await Task.sleep(for: .seconds(0.5))
            }
            updateAutoSyncLoopState()
            return false
        }
    }

    private func normalizeCategoryHierarchyIfNeeded() throws {
        try MistiaBootstrap.seedDefaultCategoriesIfNeeded(
            modelContext: modelContainer.mainContext,
            sessionStore: self
        )
    }

    private func queueReadyMutations(
        for mutations: [MistiaSyncMutation]
    ) -> [MistiaSyncMutation] {
        let normalized = mutations.flatMap(normalizedQueuedMutations(for:))
        guard !normalized.isEmpty else { return [] }

        var byKey: [String: MistiaSyncMutation] = [:]
        for mutation in normalized {
            let key = "\(mutation.entity.rawValue):\(mutation.recordID.uuidString.lowercased()):\(mutation.kind.rawValue)"
            if let existing = byKey[key] {
                byKey[key] = preferredQueuedMutation(existing, mutation)
            } else {
                byKey[key] = mutation
            }
        }

        return byKey.values.sorted { lhs, rhs in
            if lhs.entity.pushPriority != rhs.entity.pushPriority {
                return lhs.entity.pushPriority < rhs.entity.pushPriority
            }

            if lhs.entity == .category, rhs.entity == .category {
                let lhsParentID = categoryParentID(for: lhs.recordID)
                let rhsParentID = categoryParentID(for: rhs.recordID)

                if lhsParentID == nil && rhsParentID != nil { return true }
                if lhsParentID != nil && rhsParentID == nil { return false }
            }

            return lhs.modifiedAt < rhs.modifiedAt
        }
    }

    private func normalizedQueuedMutations(
        for mutation: MistiaSyncMutation
    ) -> [MistiaSyncMutation] {
        guard let subjectUserID = resolvedSubjectUserID(
            entity: mutation.entity,
            recordID: mutation.recordID,
            fallbackSubjectUserID: mutation.subjectUserID
        ) else {
            return []
        }

        let baseDeviceID = mutation.deviceID
        let dependencyMutations = promotedCategoryMutationsRequiredForSync(
            for: mutation,
            subjectUserID: subjectUserID,
            deviceID: baseDeviceID
        )

        guard shouldQueueMutation(entity: mutation.entity, recordID: mutation.recordID) else {
            return dependencyMutations
        }

        try? MistiaRecordOwnershipStore.upsert(
            entity: mutation.entity,
            recordID: mutation.recordID,
            ownerUserID: subjectUserID,
            updatedAt: mutation.modifiedAt,
            in: modelContainer
        )

        return dependencyMutations + [
            MistiaSyncMutation(
                entity: mutation.entity,
                recordID: mutation.recordID,
                subjectUserID: subjectUserID,
                kind: mutation.kind,
                modifiedAt: mutation.modifiedAt,
                baseVersion: currentRemoteVersion(
                    for: mutation.entity,
                    recordID: mutation.recordID,
                    fallback: mutation.baseVersion
                ),
                deviceID: baseDeviceID
            )
        ]
    }

    private func promotedCategoryMutationsRequiredForSync(
        for mutation: MistiaSyncMutation,
        subjectUserID: UUID,
        deviceID: UUID
    ) -> [MistiaSyncMutation] {
        guard mutation.kind == .upsert else { return [] }

        let promotedCategories = (try? MistiaSystemCategorySyncSupport.promoteCategoriesRequiredForSync(
            entity: mutation.entity,
            recordID: mutation.recordID,
            modifiedAt: mutation.modifiedAt,
            in: modelContainer
        )) ?? []

        return promotedCategories.compactMap { category in
            guard let categorySubjectUserID = resolvedSubjectUserID(
                entity: .category,
                recordID: category.id,
                fallbackSubjectUserID: subjectUserID
            ) else {
                return nil
            }

            try? MistiaRecordOwnershipStore.upsert(
                entity: .category,
                recordID: category.id,
                ownerUserID: categorySubjectUserID,
                updatedAt: mutation.modifiedAt,
                in: modelContainer
            )

            let effectiveModifiedAt = category.updatedAt > mutation.modifiedAt
                ? category.updatedAt
                : mutation.modifiedAt

            return MistiaSyncMutation(
                entity: .category,
                recordID: category.id,
                subjectUserID: categorySubjectUserID,
                kind: .upsert,
                modifiedAt: effectiveModifiedAt,
                baseVersion: currentRemoteVersion(
                    for: .category,
                    recordID: category.id,
                    fallback: 0
                ),
                deviceID: deviceID
            )
        }
    }

    private func shouldQueueMutation(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        guard entity == .category else { return true }
        guard let category = categoryRecord(for: recordID) else {
            return currentRemoteVersion(for: entity, recordID: recordID, fallback: 0) > 0
        }
        return MistiaSystemCategorySyncSupport.shouldQueueCategoryMutation(category)
    }

    private func categoryRecord(for recordID: UUID) -> TransactionCategory? {
        let descriptor = FetchDescriptor<TransactionCategory>(
            predicate: #Predicate<TransactionCategory> { category in
                category.id == recordID
            }
        )
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    private func categoryParentID(for recordID: UUID) -> UUID? {
        categoryRecord(for: recordID)?.parentCategory?.id
    }

    private func currentRemoteVersion(
        for entity: MistiaSyncEntity,
        recordID: UUID,
        fallback: Int64
    ) -> Int64 {
        (try? MistiaSyncLocalStore.currentRemoteVersion(
            for: entity,
            recordID: recordID,
            from: modelContainer
        )) ?? fallback
    }

    private func preferredQueuedMutation(
        _ lhs: MistiaSyncMutation,
        _ rhs: MistiaSyncMutation
    ) -> MistiaSyncMutation {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt >= rhs.modifiedAt ? lhs : rhs
        }
        return lhs.baseVersion >= rhs.baseVersion ? lhs : rhs
    }

    private func scheduleQueuedSyncIfAllowed() {
        guard isAutoSyncEnabled, canManageSync, !requiresInitialSync, !requiresManualSyncAfterRestore else {
            return
        }

        pendingQueuedAutoSync = true
        queuedAutoSyncTask?.cancel()
        queuedAutoSyncTask = Task { [weak self] in
            try? await Task.sleep(for: Self.QUEUED_AUTO_SYNC_DEBOUNCE)
            await self?.flushQueuedAutoSyncIfAllowed()
        }
    }

    private func flushQueuedAutoSyncIfAllowed() async {
        guard pendingQueuedAutoSync else { return }

        guard isAutoSyncEnabled, canManageSync, !requiresInitialSync, !requiresManualSyncAfterRestore else {
            cancelQueuedAutoSync()
            return
        }

        guard !isSyncInFlight else {
            queuedAutoSyncTask?.cancel()
            queuedAutoSyncTask = Task { [weak self] in
                try? await Task.sleep(for: Self.QUEUED_AUTO_SYNC_DEBOUNCE)
                await self?.flushQueuedAutoSyncIfAllowed()
            }
            return
        }

        pendingQueuedAutoSync = false
        queuedAutoSyncTask = nil
        _ = await syncNow(isManual: false)
    }

    private func cancelQueuedAutoSync() {
        pendingQueuedAutoSync = false
        queuedAutoSyncTask?.cancel()
        queuedAutoSyncTask = nil
    }

    private func clearSessionRuntimeState() {
        cancelQueuedAutoSync()
        reconnectValidationTask?.cancel()
        reconnectValidationTask = nil
        currentSession = nil
        summary = nil
        lastSyncAt = nil
        lastErrorMessage = nil
        remoteUnavailableReason = nil
        initialSyncPreview = nil
        possibleDuplicateCount = 0
        pendingInitialSyncChoice = nil
        syncCoordinator.clearQueuedMutations()
        MistiaSyncBackgroundScheduler.shared.cancelPendingRefresh()
        clearPendingAuthenticationState()
    }
}

private extension SessionSummary {
    init(user: SupabaseAuthUser) {
        let resolvedEmail = user.email ?? ""
        let resolvedName = user.userMetadata?.displayName
            ?? user.userMetadata?.fullName
            ?? user.userMetadata?.name
            ?? resolvedEmail.components(separatedBy: "@").first
            ?? "Mistia"
        let resolvedAvatarURL = user.userMetadata?.resolvedAvatarURL

        self.init(
            userID: user.id,
            displayName: resolvedName,
            email: resolvedEmail,
            avatarURL: resolvedAvatarURL
        )
    }
}

private extension SessionStore {
    func storedProfile(for userID: UUID) -> UserAccountProfile? {
        let descriptor = FetchDescriptor<UserAccountProfile>(
            predicate: #Predicate { profile in
                profile.userID == userID
            }
        )
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    func ensureStoredProfileExists(
        for summary: SessionSummary,
        preferredDisplayName: String? = nil
    ) throws -> UserAccountProfile {
        if let storedProfile = storedProfile(for: summary.userID) {
            let resolvedDisplayName = preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if storedProfile.email != summary.email {
                storedProfile.email = summary.email
            }
            if let resolvedDisplayName, !resolvedDisplayName.isEmpty, storedProfile.displayName != resolvedDisplayName {
                storedProfile.displayName = resolvedDisplayName
            }
            try modelContainer.mainContext.save()
            return storedProfile
        }

        let newProfile = UserAccountProfile(
            userID: summary.userID,
            email: summary.email,
            displayName: preferredDisplayName?.isEmpty == false ? preferredDisplayName! : summary.displayName
        )
        modelContainer.mainContext.insert(newProfile)
        try modelContainer.mainContext.save()
        return newProfile
    }

    func applyStoredProfile(
        _ profile: UserAccountProfile?,
        to summary: SessionSummary,
        remoteAvatarURL: URL? = nil
    ) -> SessionSummary {
        let resolvedDisplayName = {
            guard let storedName = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                  !storedName.isEmpty else {
                return summary.displayName
            }
            return storedName
        }()
        let resolvedEmail = profile?.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? profile!.email
            : summary.email
        let resolvedAvatarURL = profile?.avatarFileName.flatMap(cachedProfileAvatarURL(forFileName:))
            ?? remoteAvatarURL
            ?? summary.avatarURL
        return SessionSummary(
            userID: summary.userID,
            displayName: resolvedDisplayName,
            email: resolvedEmail,
            avatarURL: resolvedAvatarURL
        )
    }

    func syncProfileWithRemote(
        session: SupabaseAuthSession,
        baseSummary: SessionSummary,
        storedProfile: UserAccountProfile
    ) async throws -> RemoteUserProfile {
        let existingRemoteProfile = try await userProfileStore.fetchProfile(session: session)
        let localDisplayName = normalizedStoredDisplayName(
            storedProfile.displayName,
            fallback: baseSummary.displayName
        )

        let baseAvatarURL = baseSummary.avatarURL
        let remoteMirrorsBaseAvatar = existingRemoteProfile?.avatarURL?.absoluteString == baseAvatarURL?.absoluteString
        let shouldUploadLocalAvatar = (existingRemoteProfile?.avatarURL == nil || remoteMirrorsBaseAvatar)
            && storedProfile.avatarFileName != nil

        var resolvedRemoteAvatarURL = existingRemoteProfile?.avatarURL ?? baseAvatarURL
        if shouldUploadLocalAvatar,
           let avatarFileName = storedProfile.avatarFileName,
           let avatarData = try? loadAvatarImageData(forFileName: avatarFileName) {
            resolvedRemoteAvatarURL = try await userProfileStore.uploadAvatarImageData(
                avatarData,
                session: session
            )
        }

        let resolvedRemoteDisplayName: String = {
            guard let existingRemoteProfile else { return localDisplayName }
            let remoteDisplayName = existingRemoteProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseDisplayName = baseSummary.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            if remoteDisplayName.isEmpty {
                return localDisplayName
            }

            if remoteDisplayName == baseDisplayName && localDisplayName != baseDisplayName {
                return localDisplayName
            }

            return existingRemoteProfile.displayName
        }()

        let resolvedRemoteBirthday = existingRemoteProfile?.birthday ?? storedProfile.birthday

        let needsRemoteUpsert = {
            guard let existingRemoteProfile else { return true }

            let avatarMatches = existingRemoteProfile.avatarURL?.absoluteString == resolvedRemoteAvatarURL?.absoluteString
            return existingRemoteProfile.displayName != resolvedRemoteDisplayName
                || existingRemoteProfile.birthday != resolvedRemoteBirthday
                || !avatarMatches
        }()

        let remoteProfile = if needsRemoteUpsert {
            try await userProfileStore.upsertProfile(
                displayName: resolvedRemoteDisplayName,
                avatarURL: resolvedRemoteAvatarURL,
                birthday: resolvedRemoteBirthday,
                session: session
            )
        } else {
            existingRemoteProfile!
        }

        syncStoredProfile(storedProfile, with: remoteProfile, email: baseSummary.email)
        try modelContainer.mainContext.save()
        return remoteProfile
    }

    func syncStoredProfile(
        _ storedProfile: UserAccountProfile,
        with remoteProfile: RemoteUserProfile,
        email: String
    ) {
        storedProfile.email = email
        storedProfile.displayName = normalizedStoredDisplayName(
            remoteProfile.displayName,
            fallback: email.components(separatedBy: "@").first ?? "Mistia"
        )
        storedProfile.birthday = remoteProfile.birthday
        storedProfile.createdAt = remoteProfile.createdAt
        storedProfile.updatedAt = remoteProfile.updatedAt
    }

    func normalizedStoredDisplayName(
        _ displayName: String,
        fallback: String
    ) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func cacheRemoteAvatarIfNeeded(
        for storedProfile: UserAccountProfile,
        remoteAvatarURL: URL?
    ) async {
        guard let remoteAvatarURL else { return }

        if let avatarFileName = storedProfile.avatarFileName,
           cachedProfileAvatarURL(forFileName: avatarFileName) != nil {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteAvatarURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  !data.isEmpty else {
                return
            }

            let fileName = try saveRemoteAvatarImageData(
                data,
                mimeType: httpResponse.mimeType,
                sourceURL: remoteAvatarURL,
                for: storedProfile.userID
            )
            storedProfile.avatarFileName = fileName
        } catch {
            return
        }
    }

    func configureSyncCoordinator() {
        syncCoordinator.onProgressUpdate = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.shouldShowSyncProgress else { return }
                self.syncProgress = progress

                if let startTime = self.syncStartTime, progress > 0.05 {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let totalEstimated = elapsed / progress
                    self.syncTimeRemaining = max(0, totalEstimated - elapsed)
                } else {
                    self.syncTimeRemaining = nil
                }
            }
        }
    }

    func fallbackGuestDescriptor(
        excluding profileID: UUID? = nil
    ) throws -> MistiaLocalProfileDescriptor? {
        guard let launchState else { return nil }
        if let existing = launchState.latestGuestProfile(excluding: profileID) {
            return existing
        }
        return try launchState.createGuestProfile(activate: false)
    }

    func currentGuestUnboundHasMeaningfulData() -> Bool {
        guard isGuestUnboundModeActive else { return false }
        if let launchState {
            return (try? launchState.hasMeaningfulUserData()) ?? false
        }
        return (try? MistiaSyncLocalStore.hasMeaningfulUserData(in: modelContainer)) ?? false
    }

    func setRequiresManualSyncAfterRestore(_ isRequired: Bool) {
        requiresManualSyncAfterRestore = isRequired
        let profileID = activeLocalProfileID
        userDefaults.set(isRequired, forKey: Self.manualSyncReviewRequiredKey(for: profileID))
        if profileID != nil {
            userDefaults.removeObject(forKey: MistiaAppStorageKey.syncManualReviewRequired)
        }
    }

    func setLocalModeProfileUserID(_ userID: UUID?) {
        legacyLocalModeProfileUserID = userID
        if let userID {
            userDefaults.set(userID.uuidString.lowercased(), forKey: MistiaAppStorageKey.localModeProfileUserID)
        } else {
            userDefaults.removeObject(forKey: MistiaAppStorageKey.localModeProfileUserID)
        }
    }

    func clearManualSyncReviewRequired(for profileID: UUID?) {
        userDefaults.removeObject(forKey: Self.manualSyncReviewRequiredKey(for: profileID))
        if profileID == nil {
            userDefaults.removeObject(forKey: MistiaAppStorageKey.syncManualReviewRequired)
        }
    }

    private static func manualSyncReviewRequiredKey(for profileID: UUID?) -> String {
        guard let profileID else { return MistiaAppStorageKey.syncManualReviewRequired }
        return "\(MistiaAppStorageKey.syncManualReviewRequired).\(profileID.uuidString.lowercased())"
    }

    private static func storedManualSyncReviewRequired(
        in userDefaults: UserDefaults,
        profileID: UUID?
    ) -> Bool {
        let key = manualSyncReviewRequiredKey(for: profileID)
        if userDefaults.object(forKey: key) != nil {
            return userDefaults.bool(forKey: key)
        }

        if let profileID, userDefaults.object(forKey: MistiaAppStorageKey.syncManualReviewRequired) != nil {
            let legacyValue = userDefaults.bool(forKey: MistiaAppStorageKey.syncManualReviewRequired)
            userDefaults.set(legacyValue, forKey: manualSyncReviewRequiredKey(for: profileID))
            userDefaults.removeObject(forKey: MistiaAppStorageKey.syncManualReviewRequired)
            return legacyValue
        }

        return userDefaults.bool(forKey: MistiaAppStorageKey.syncManualReviewRequired)
    }

    private static func storedLocalModeProfileUserID(in userDefaults: UserDefaults) -> UUID? {
        guard let rawValue = userDefaults.string(forKey: MistiaAppStorageKey.localModeProfileUserID) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    func saveAvatarImageData(_ data: Data, for userID: UUID) throws -> String {
        let directoryURL = try profileAvatarDirectoryURL()
        let fileName = "\(userID.uuidString.lowercased()).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    func saveRemoteAvatarImageData(
        _ data: Data,
        mimeType: String?,
        sourceURL: URL,
        for userID: UUID
    ) throws -> String {
        let directoryURL = try profileAvatarDirectoryURL()
        let fileExtension = avatarFileExtension(mimeType: mimeType, sourceURL: sourceURL)
        let fileName = "\(userID.uuidString.lowercased()).\(fileExtension)"
        try removeCachedAvatarFiles(for: userID, keeping: fileName, in: directoryURL)

        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    func loadAvatarImageData(forFileName fileName: String) throws -> Data {
        try Data(contentsOf: profileAvatarURL(forFileName: fileName))
    }

    func profileAvatarDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("ProfileAvatars", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    func profileAvatarURL(forFileName fileName: String) -> URL {
        let baseURL = (try? profileAvatarDirectoryURL()) ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(fileName)
    }

    func cachedProfileAvatarURL(forFileName fileName: String) -> URL? {
        let fileURL = profileAvatarURL(forFileName: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    func avatarFileExtension(mimeType: String?, sourceURL: URL) -> String {
        let trimmedExtension = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExtension.isEmpty {
            return trimmedExtension.lowercased()
        }

        switch mimeType?.lowercased() {
        case "image/png":
            return "png"
        case "image/heic", "image/heif":
            return "heic"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        default:
            return "jpg"
        }
    }

    func removeCachedAvatarFiles(
        for userID: UUID,
        keeping keptFileName: String,
        in directoryURL: URL
    ) throws {
        let fileManager = FileManager.default
        let filePrefix = userID.uuidString.lowercased() + "."
        let cachedFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for fileURL in cachedFiles where fileURL.lastPathComponent.hasPrefix(filePrefix)
            && fileURL.lastPathComponent != keptFileName {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
