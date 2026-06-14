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

enum SessionSyncTrigger: Equatable {
    case manual
    case automaticLoop
    case initial
    case backgroundRefresh
}

struct FamilyOwnerPushConflict: Codable, Equatable, Hashable, Identifiable {
    let entity: MistiaSyncEntity
    let recordID: UUID
    let ownerUserID: UUID
    let kind: MistiaSyncMutationKind
    let detectedAt: Date

    var id: String {
        Self.key(entity: entity, recordID: recordID)
    }

    init(
        entity: MistiaSyncEntity,
        recordID: UUID,
        ownerUserID: UUID,
        kind: MistiaSyncMutationKind,
        detectedAt: Date = .now
    ) {
        self.entity = entity
        self.recordID = recordID
        self.ownerUserID = ownerUserID
        self.kind = kind
        self.detectedAt = detectedAt
    }

    init(mutation: MistiaSyncMutation, detectedAt: Date = .now) {
        self.init(
            entity: mutation.entity,
            recordID: mutation.recordID,
            ownerUserID: mutation.subjectUserID,
            kind: mutation.kind,
            detectedAt: detectedAt
        )
    }

    static func key(entity: MistiaSyncEntity, recordID: UUID) -> String {
        "\(entity.rawValue):\(recordID.uuidString.lowercased())"
    }
}

@MainActor
@Observable
final class SessionStore {
    // MARK: - Auto-sync Configuration
    private static let AUTOMATIC_SYNC_INTERVAL: TimeInterval = 1_200 // 20 minutes in seconds
    private static let QUEUED_AUTO_SYNC_DEBOUNCE: Duration = .milliseconds(600)
    private static let FAMILY_OWNER_PUSH_CONFLICTS_KEY = "mistia.familyOwnerPushConflicts.v1"
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
    var isAutoSyncEnabled: Bool
    var authPhase: SessionAuthPhase = .signIn
    var authBanner: SessionAuthBanner?
    var authPendingEmail: String?
    var authFieldErrors: [SessionAuthField: String] = [:]
    var activeAuthAction: SessionAuthAction?
    var pendingAuthenticationPrompt: SessionPendingAuthenticationPrompt?
    var isAuthTransitioning = false
    var isBootstrapping = false
    var familyOwnerPushConflicts: [FamilyOwnerPushConflict] = []

    var networkStatus: SessionNetworkStatus = .checking
    var remoteUnavailableReason: String?
    var accountDevices: [MistiaAccountDevice] = []
    var isLoadingAccountDevices = false
    var accountDevicesErrorMessage: String?

    @ObservationIgnored private let authService: any SessionAuthServicing
    @ObservationIgnored private let userProfileStore: any UserProfileRemoteStoring
    @ObservationIgnored private let accountDeviceStore: any AccountDeviceRegistryServicing
    @ObservationIgnored private let launchState: MistiaDataStack.LaunchState?
    @ObservationIgnored private var modelContainer: ModelContainer
    @ObservationIgnored private var syncCoordinator: SyncCoordinator
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let connectivityMonitor: SessionConnectivityMonitor?
    @ObservationIgnored private var currentSession: SupabaseAuthSession?
    @ObservationIgnored private var legacyLocalModeProfileUserID: UUID?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var isSyncInFlight = false
    @ObservationIgnored private var shouldShowSyncProgress = false
    @ObservationIgnored private var syncStartTime: Date?
    @ObservationIgnored var requiresInitialSync = false
    @ObservationIgnored private var requiresManualSyncAfterRestore: Bool
    @ObservationIgnored private var pendingInitialSyncChoice: MistiaInitialSyncChoice?
    @ObservationIgnored private var subjectUserIDProvider: (() -> UUID?)?
    @ObservationIgnored private var postSyncRefreshHandler: ((SessionSyncTrigger) async -> Void)?
    @ObservationIgnored private var pendingQueuedAutoSync = false
    @ObservationIgnored private var queuedFamilyOwnerPushTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFamilyOwnerPush = false
    @ObservationIgnored private var reconnectValidationTask: Task<Void, Never>?
    @ObservationIgnored private var remoteValidationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingAuthenticationState: PendingAuthenticationState?

    init(
        modelContainer: ModelContainer,
        launchState: MistiaDataStack.LaunchState? = nil,
        userDefaults: UserDefaults = .standard,
        authService: (any SessionAuthServicing)? = nil,
        userProfileStore: (any UserProfileRemoteStoring)? = nil,
        accountDeviceStore: (any AccountDeviceRegistryServicing)? = nil,
        syncCoordinator providedSyncCoordinator: SyncCoordinator? = nil,
        connectivityMonitor providedConnectivityMonitor: SessionConnectivityMonitor? = nil,
        registerBackgroundRefresh: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.launchState = launchState
        self.userDefaults = userDefaults
        self.authService = authService ?? SupabaseAuthService()
        self.userProfileStore = userProfileStore ?? SupabaseUserProfileStore()
        self.accountDeviceStore = accountDeviceStore ?? MistiaAccountDeviceRegistryService()
        self.syncCoordinator = providedSyncCoordinator ?? SyncCoordinator(modelContainer: modelContainer)
        self.connectivityMonitor = providedConnectivityMonitor ?? SessionConnectivityMonitor()
        isAutoSyncEnabled = userDefaults.bool(forKey: MistiaAppStorageKey.syncAutoEnabled)
        legacyLocalModeProfileUserID = Self.storedLocalModeProfileUserID(in: userDefaults)
        familyOwnerPushConflicts = Self.loadFamilyOwnerPushConflicts(from: userDefaults)
        requiresManualSyncAfterRestore = Self.storedManualSyncReviewRequired(
            in: userDefaults,
            profileID: launchState?.activeProfileDescriptor?.id
        )
        networkStatus = self.connectivityMonitor?.currentStatus ?? .checking
        isBootstrapping = true

        if MistiaSyncConfiguration.load() == nil {
            syncStatusTitle = L10n.shared.session.session.cloudSyncIsnTConfigured
            syncStatusDetail = L10n.shared.session.session.fillInTheServiceURLAndPublic2
            syncStatusSystemImage = "bolt.horizontal.circle"
        } else {
            syncStatusTitle = L10n.shared.session.session.signedOut
            syncStatusDetail = L10n.shared.session.session.signInToSyncMistiaDataAcross
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
                if signedInUserID == cloudUserID {
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

    func setPostSyncRefreshHandler(_ handler: ((SessionSyncTrigger) async -> Void)?) {
        postSyncRefreshHandler = handler
    }

    func refreshAccountDevices() async {
        guard let currentSession, canPerformRemoteActions else {
            accountDevices = []
            accountDevicesErrorMessage = remoteUnavailableReason
            return
        }

        isLoadingAccountDevices = true
        accountDevicesErrorMessage = nil
        defer { isLoadingAccountDevices = false }

        do {
            _ = try await accountDeviceStore.registerCurrentDevice(session: currentSession)
            accountDevices = try await accountDeviceStore.fetchDevices(session: currentSession)
        } catch {
            accountDevicesErrorMessage = friendlyErrorMessage(for: error)
        }
    }

    func requestAccountDeviceSignOut(_ device: MistiaAccountDevice) async {
        if device.isCurrentDevice() {
            await signOut()
            return
        }

        guard let currentSession, canPerformRemoteActions else {
            accountDevicesErrorMessage = remoteUnavailableReason
            return
        }

        isLoadingAccountDevices = true
        accountDevicesErrorMessage = nil
        defer { isLoadingAccountDevices = false }

        do {
            let updatedDevice = try await accountDeviceStore.requestSignOut(
                deviceID: device.deviceID,
                session: currentSession
            )
            upsertAccountDevice(updatedDevice)
        } catch {
            accountDevicesErrorMessage = friendlyErrorMessage(for: error)
        }
    }

    func forgetAccountDevice(_ device: MistiaAccountDevice) async {
        guard let currentSession, canPerformRemoteActions else {
            accountDevicesErrorMessage = remoteUnavailableReason
            return
        }

        isLoadingAccountDevices = true
        accountDevicesErrorMessage = nil
        defer { isLoadingAccountDevices = false }

        do {
            try await accountDeviceStore.forgetDevice(deviceID: device.deviceID, session: currentSession)
            accountDevices.removeAll { $0.deviceID == device.deviceID }
            if device.isCurrentDevice() {
                await signOut()
            }
        } catch {
            accountDevicesErrorMessage = friendlyErrorMessage(for: error)
        }
    }

    func checkForRemoteAccountDeviceSignOutIfNeeded() async {
        guard let currentSession, canPerformRemoteActions else { return }

        do {
            guard let currentDevice = try await accountDeviceStore.fetchCurrentDevice(session: currentSession) else {
                return
            }
            upsertAccountDevice(currentDevice)
            if currentDevice.requiresLocalSignOut() {
                await signOut()
            }
        } catch {
            accountDevicesErrorMessage = friendlyErrorMessage(for: error)
        }
    }

    func handleSceneDidBecomeActive() {
        if requiresInitialSync && hasCompletedCloudSyncHistory() {
            requiresInitialSync = false
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
        }
        updateAutoSyncLoopState()
        scheduleFamilyOwnerOutboxRecoveryIfNeeded()
        Task { @MainActor [weak self] in
            await self?.checkForRemoteAccountDeviceSignOutIfNeeded()
        }
    }

    func handleSceneDidEnterBackground() {
        updateAutoSyncLoopState()
    }

    func handleBackgroundRefresh() async -> Bool {
        await MistiaCurrencyRateMaintenance.refreshIfNeeded()
        if hasQueuedFamilyOwnerMutations() {
            _ = await flushQueuedFamilyOwnerPushIfAllowed()
        }
        guard shouldRunForegroundCatchUp() else { return false }
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

        syncStatusTitle = L10n.shared.session.session.restoringSession
        syncStatusDetail = L10n.shared.session.session.mistiaIsCheckingForAPreviouslySigned
        syncStatusSystemImage = "key.horizontal"

        do {
            guard let restoredSession = try authService.loadPersistedSession() else {
                if summary == nil {
                    if !restorePreservedSignedInProfile(reason: nil) {
                        applySignedOutState()
                    }
                }
                return
            }

            if summary == nil {
                try applyLocalAuthenticatedState(
                    restoredSession,
                    restoringExistingSession: true
                )
                applyLocalRestoredSessionStateIfNeeded()
                await refreshAccountDevicesAfterAuthentication(
                    session: restoredSession,
                    respectsRemoteSignOut: true
                )
            }
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
            if summary == nil {
                if !restorePreservedSignedInProfile(reason: error) {
                    applySignedOutState(preservingBanner: true)
                    authBanner = SessionAuthBanner(
                        title: L10n.shared.session.session.couldnTReadTheSavedSession,
                        message: friendlyErrorMessage(for: error),
                        style: .error
                    )
                }
            }
        }
    }

    /// Called by ContentView after all startup tasks complete
    func finishBootstrapping() {
        isBootstrapping = false
    }

    func validateRestoredSessionInBackgroundIfNeeded() async {
        if let remoteValidationTask {
            await remoteValidationTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRemoteSessionValidation()
        }
        remoteValidationTask = task
        await task.value
        remoteValidationTask = nil
    }

    func runDeferredStartupSyncIfNeeded() async -> Bool {
        await validateRestoredSessionInBackgroundIfNeeded()
        return false
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
                title: L10n.shared.session.session.checkYourEmail,
                message: L10n.shared.session.session.ifTheEmailIsValidMistiaWill,
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
                title: L10n.shared.session.session.confirmationEmailSentAgain,
                message: L10n.shared.session.session.ifThisAccountIsPendingConfirmationThe,
                style: .info
            )
        } catch {
            handleRecoveryFailure(error, isResend: true)
        }

        activeAuthAction = nil
        isWorking = false
    }

    func signOut() async {
        isWorking = true
        lastErrorMessage = nil
        let activeSession = currentSession

        disableShortcutIfNeededOnLogout()
        clearPreservedSignedInUserID()

        await beginAuthTransition()
        defer { endAuthTransition() }

        if networkStatus != .disconnected {
            await markCurrentAccountDeviceSignedOut(session: activeSession)
        }

        do {
            try await authService.signOut(session: activeSession)
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
        }

        if launchState == nil {
            setLocalModeProfileUserID(activeSession?.user.id ?? summary?.userID ?? activeLocalProfileUserID)
        }
        clearSessionRuntimeState()
        isWorking = false
        applySignedOutState()
    }

    func signOutAndDeleteLocalData() async {
        isWorking = true
        lastErrorMessage = nil
        let activeSession = currentSession
        let currentDescriptor = launchState?.activeProfileDescriptor

        disableShortcutIfNeededOnLogout()
        clearPreservedSignedInUserID()

        await beginAuthTransition()
        defer { endAuthTransition() }

        if networkStatus != .disconnected {
            await markCurrentAccountDeviceSignedOut(session: activeSession)
        }

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
        isWorking = true
        lastErrorMessage = nil
        await beginAuthTransition()
        defer { endAuthTransition() }

        do {
            let activeSession = try await prepareRemoteSession()
            await markCurrentAccountDeviceSignedOut(session: activeSession)
            try await authService.deleteAccount(session: activeSession)
            if let launchState, let currentDescriptor = launchState.activeProfileDescriptor {
                try MistiaSyncLocalStore.detachFromCloud(in: modelContainer)
                let guestDescriptor = try launchState.convertProfileToGuestUnbound(currentDescriptor)
                try activateLocalProfile(guestDescriptor)
            } else {
                setLocalModeProfileUserID(activeSession.user.id)
            }
            clearPreservedSignedInUserID()
            clearSessionRuntimeState()
            applySignedOutState(preservingBanner: true)
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.cloudAccountDeleted,
                message: L10n.shared.session.session.yourCloudAccountAndServerDataWere,
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
            isManualSyncInProgress = true
        }
        defer {
            if isManual {
                isManualSyncInProgress = false
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

    func syncPermissionApprovalChanges() async -> Bool {
        guard currentSession != nil, !isSyncInFlight else { return false }

        if requiresInitialSync {
            return await syncNow(isManual: true)
        }

        // Category-use approval must push the explicitly granted system category before
        // normal eligibility repair can prune unused default categories from the outbox.
        return await runMergeSync(
            trigger: .manual,
            showProgress: false,
            normalizesBeforeSync: false
        )
    }

    func syncFamilyActivityChanges() async -> Bool {
        guard currentSession != nil else { return false }

        await waitForCurrentSyncToFinish()

        guard !isSyncInFlight else { return false }

        if requiresInitialSync {
            return await syncNow(isManual: true)
        }

        return await runMergeSync(
            trigger: .manual,
            showProgress: false
        )
    }

    func pushQueuedFamilyOwnerChangesNow() async -> Bool {
        guard currentSession != nil else { return false }
        await waitForCurrentSyncToFinish()
        guard !isSyncInFlight else { return false }
        return await flushQueuedFamilyOwnerPushIfAllowed()
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
        syncStatusTitle = L10n.shared.session.session.initialSyncPostponed
        syncStatusDetail = L10n.shared.session.session.tapSyncNowWhenYouReReady
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

            lastErrorMessage = nil
            setRequiresManualSyncAfterRestore(isConfigured)

            syncStatusTitle = L10n.shared.session.session.snapshotRestored
            syncStatusDetail = isConfigured
                ? L10n.shared.session.session.mistiaRestoredYourLocalDataReviewIt
                : L10n.shared.session.session.mistiaRestoredLocalDataFromTheSelected
            syncStatusSystemImage = "externaldrive.badge.checkmark"
            updateAutoSyncLoopState()
            return result
        } catch {
            lastErrorMessage = error.localizedDescription
            updateAutoSyncLoopState()
            throw error
        }
    }

    func resetCurrentDeviceLocalData() async throws {
        guard !isSyncInFlight else {
            throw MistiaBackupStoreError.syncInProgress
        }

        isWorking = true
        lastErrorMessage = nil
        cancelQueuedAutoSync()
        syncCoordinator.clearQueuedMutations()
        setAutoSyncEnabled(false)

        do {
            let context = modelContainer.mainContext
            try MistiaSyncLocalStore.clearLocalDeviceLiveData(context: context)
            try MistiaBootstrap.resetCategoriesToSystemDefaults(modelContext: context)
            syncCoordinator.clearQueuedMutations()
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
            lastSyncAt = nil

            if let activeUserID = summary?.userID ?? currentSession?.user.id,
               let profile = storedProfile(for: activeUserID) {
                profile.lastSyncAt = nil
                try? modelContainer.mainContext.save()
            }

            if canManageSync {
                setRequiresManualSyncAfterRestore(true)
            }

            syncStatusTitle = L10n.shared.session.session.localDataCleared
            syncStatusDetail = canManageSync
                ? L10n.shared.session.session.thisDeviceIsBackToAClean2
                : L10n.shared.session.session.thisDeviceIsBackToAClean
            syncStatusSystemImage = "trash.circle"
            isWorking = false
            updateAutoSyncLoopState()
        } catch {
            isWorking = false
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
            if isSignedIn {
                applySignedInOfflineState()
            }
            updateAutoSyncLoopState()
        case .connected:
            updateAutoSyncLoopState()
            scheduleFamilyOwnerOutboxRecoveryIfNeeded()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await CategoryNameTranslationMaintenance.run(
                    modelContext: self.currentModelContainer.mainContext,
                    sessionStore: self
                )
            }
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
            setPreservedSignedInUserID(validSession.user.id)
            remoteUnavailableReason = nil
            return validSession
        } catch {
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
            syncStatusTitle = L10n.shared.session.session.conflictResolved
            syncStatusDetail = L10n.shared.session.session.mistiaUpdatedTheRecordWithYourSelected
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
        schedulePush(for: queuedMutations)
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
        schedulePush(for: queuedMutations)
    }

    func recordMutations(_ mutations: [MistiaSyncMutation]) {
        guard currentSession != nil else { return }
        let queuedMutations = queueReadyMutations(for: mutations)
        guard !queuedMutations.isEmpty else { return }
        syncCoordinator.queue(queuedMutations)
        schedulePush(for: queuedMutations)
    }

    func protectedQueuedRecordIDs() -> Set<String> {
        syncCoordinator.queuedMutationIDs()
    }

    func hasFamilyOwnerPushConflict(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        familyOwnerPushConflict(entity: entity, recordID: recordID) != nil
    }

    func familyOwnerPushConflict(
        entity: MistiaSyncEntity,
        recordID: UUID
    ) -> FamilyOwnerPushConflict? {
        let key = FamilyOwnerPushConflict.key(entity: entity, recordID: recordID)
        return familyOwnerPushConflicts.first { $0.id == key }
    }

    func discardFamilyOwnerPushConflictAndRefresh(
        entity: MistiaSyncEntity,
        recordID: UUID,
        familyContextStore: FamilyContextStore
    ) async {
        guard let conflict = familyOwnerPushConflict(entity: entity, recordID: recordID) else {
            return
        }

        syncCoordinator.removeQueuedMutation(entity: entity, recordID: recordID)
        clearFamilyOwnerPushConflict(entity: entity, recordID: recordID)
        pendingFamilyOwnerPush = hasQueuedFamilyOwnerMutations()

        await familyContextStore.refreshAccessibleFinance(
            sessionStore: self,
            userIDs: [conflict.ownerUserID],
            preserveLocalNewerRows: false
        )
    }

    private func handleSignInFailure(_ error: Error, email: String) {
        if isEmailConfirmationError(error) {
            presentEmailConfirmationState(for: email)
            return
        }

        authPhase = .signIn

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.canTConnectRightNow,
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: L10n.shared.session.session.couldnTSignIn,
            message: L10n.shared.session.session.theEmailOrPasswordIsIncorrectCheck,
            style: .error
        )
    }

    private func handleSignUpFailure(_ error: Error) {
        authPhase = .signUp

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.canTCreateTheAccountRightNow,
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isRateLimitedError(error) {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.youReMovingABitFast,
                message: L10n.shared.session.session.theServiceTemporarilySlowedThingsDownTo,
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: L10n.shared.session.session.couldnTCreateTheAccount,
            message: L10n.shared.session.session.thisEmailIsnTReadyForA,
            style: .error
        )
    }

    private func handleGoogleSignInFailure(_ error: Error) {
        authPhase = .signIn

        if let serviceError = error as? SupabaseServiceError, case .oauthCancelled = serviceError {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.googleSignInWasCancelled,
                message: L10n.shared.session.session.youCanTryAgainAnyTimeWhen,
                style: .info
            )
            return
        }

        if isGoogleSignInSetupError(error) {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.googleSignInIsnTReadyYet,
                message: googleSetupErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.googleSignInCanTConnectRight,
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: L10n.shared.session.session.googleSignInCouldnTFinish,
            message: friendlyErrorMessage(for: error),
            style: .error
        )
    }

    private func handleRecoveryFailure(_ error: Error, isResend: Bool) {
        if isInfrastructureAuthError(error) {
            authBanner = SessionAuthBanner(
                title: isResend ? L10n.session.auth.cantResendEmailTitle : L10n.session.auth.cantSendEmailTitle,
                message: infrastructureErrorMessage(for: error),
                style: .error
            )
            return
        }

        if isRateLimitedError(error) {
            authBanner = SessionAuthBanner(
                title: L10n.shared.session.session.aRequestWasJustSent,
                message: L10n.shared.session.session.pleaseWaitABitBeforeTryingAgain,
                style: .info
            )
            return
        }

        authBanner = SessionAuthBanner(
            title: isResend ? L10n.session.auth.emailRequestProcessingTitle : L10n.session.auth.requestProcessingTitle,
            message: isResend ? L10n.session.auth.confirmationEmailDeliveryMessage : L10n.session.auth.resetEmailDeliveryMessage,
            style: .info
        )
    }

    private func presentEmailConfirmationState(for email: String) {
        authPhase = .verifyEmailPending
        authPendingEmail = email
        authBanner = SessionAuthBanner(
            title: L10n.shared.session.session.checkYourEmailToConfirm,
            message: L10n.shared.session.session.yourAccountHasBeenCreatedOpenThe,
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
                title: L10n.shared.session.session.couldnTFinishSigningIn,
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
                        title: L10n.shared.session.session.guestLocalDataIsSeparate,
                        message: L10n.shared.session.session.thisAccountCanTAutomaticallyTakeThe
                    )
                )
            }

            if result.origin == .unknown {
                return PendingAuthenticationState(
                    result: result,
                    sourceGuestDescriptor: activeDescriptor,
                    prompt: SessionPendingAuthenticationPrompt(
                        kind: .attachGuestData,
                        title: L10n.shared.session.session.chooseHowToUseTheGuestLocal,
                        message: L10n.shared.session.session.mistiaCanTConfirmYetWhetherThe
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
            scheduleFamilyOwnerOutboxRecoveryIfNeeded()
            return
        }

        do {
            let validSession = try await prepareRemoteSession()
            try await syncAuthenticatedStateWithRemote(
                validSession,
                restoringExistingSession: restoringExistingSession
            )
        } catch {
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
        setPreservedSignedInUserID(session.user.id)
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
            syncStatusTitle = L10n.shared.session.session.restoringSession
            syncStatusDetail = L10n.shared.session.session.mistiaIsCheckingForAPreviouslySigned
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
        syncStatusTitle = L10n.shared.session.session.signedIn
        syncStatusDetail = restoringExistingSession
            ? L10n.session.sync.sessionRestoredDetail
            : L10n.session.sync.signInSucceededDetail
        syncStatusSystemImage = "checkmark.circle"
        updateAutoSyncLoopState()
        scheduleFamilyOwnerOutboxRecoveryIfNeeded()
        await refreshAccountDevicesAfterAuthentication(
            session: session,
            respectsRemoteSignOut: restoringExistingSession
        )
    }

    private func refreshAccountDevicesAfterAuthentication(
        session: SupabaseAuthSession,
        respectsRemoteSignOut: Bool
    ) async {
        guard canPerformRemoteActions else { return }

        do {
            if respectsRemoteSignOut,
               let currentDevice = try await accountDeviceStore.fetchCurrentDevice(session: session) {
                upsertAccountDevice(currentDevice)
                if currentDevice.requiresLocalSignOut() {
                    await signOut()
                    return
                }
            }

            let registeredDevice = try await accountDeviceStore.registerCurrentDevice(session: session)
            let devices = try await accountDeviceStore.fetchDevices(session: session)
            accountDevices = devices.isEmpty ? [registeredDevice] : devices
            accountDevicesErrorMessage = nil
        } catch {
            accountDevicesErrorMessage = friendlyErrorMessage(for: error)
        }
    }

    private func markCurrentAccountDeviceSignedOut(session: SupabaseAuthSession?) async {
        do {
            try await accountDeviceStore.markCurrentDeviceSignedOut(session: session)
        } catch {
            lastErrorMessage = friendlyErrorMessage(for: error)
        }
    }

    private func upsertAccountDevice(_ device: MistiaAccountDevice) {
        accountDevices.removeAll { $0.deviceID == device.deviceID }
        guard device.forgetAt == nil else { return }
        accountDevices.append(device)
        accountDevices.sort { lhs, rhs in
            lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    private func applySignedInOfflineState() {
        guard isSignedIn else { return }
        lastErrorMessage = nil
        remoteUnavailableReason = L10n.shared.session.session.noNetworkConnectionReconnectToSyncEdit
        syncStatusTitle = L10n.shared.session.session.offline
        syncStatusDetail = L10n.shared.session.session.noNetworkConnectionReconnectToSyncEdit
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
            ? L10n.shared.session.session.theSessionWasKeptOnThisDevice
            : L10n.shared.session.session.signedInOnThisDevice2
        syncStatusDetail = message
        syncStatusSystemImage = syncErrorSystemImage(for: error)
        updateAutoSyncLoopState()
    }

    private func revalidateRemoteSessionAfterReconnect() async {
        guard currentSession != nil else { return }

        await performRemoteSessionValidation()
    }

    private func performRemoteSessionValidation() async {
        guard currentSession != nil, canPerformRemoteActions else { return }

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

    private func applyLocalRestoredSessionStateIfNeeded() {
        guard isSignedIn else { return }

        if networkStatus == .disconnected {
            applySignedInOfflineState()
            updateAutoSyncLoopState()
            scheduleFamilyOwnerOutboxRecoveryIfNeeded()
            return
        }

        remoteUnavailableReason = nil
        syncStatusTitle = L10n.shared.session.session.signedInOnThisDevice2
        syncStatusDetail = L10n.session.sync.sessionRestoredDetail
        syncStatusSystemImage = "person.crop.circle.badge.checkmark"
        updateAutoSyncLoopState()
        scheduleFamilyOwnerOutboxRecoveryIfNeeded()
    }

    private func restorePreservedSignedInProfile(reason: Error?) -> Bool {
        guard let userID = preservedSignedInUserID() else { return false }

        if let launchState {
            guard
                let activeDescriptor = launchState.activeProfileDescriptor,
                activeDescriptor.kind == .cloudUser,
                activeDescriptor.cloudUserID == userID
            else {
                return false
            }
        }

        let baseSummary = SessionSummary(
            userID: userID,
            displayName: "Mistia",
            email: "",
            avatarURL: nil
        )
        let profile = storedProfile(for: userID)
        currentSession = nil
        summary = applyStoredProfile(profile, to: baseSummary)
        lastSyncAt = profile?.lastSyncAt
        lastErrorMessage = reason.map { friendlyErrorMessage(for: $0) }
        authBanner = nil
        authFieldErrors = [:]
        authPendingEmail = nil
        authPhase = .signIn
        activeAuthAction = nil
        requiresInitialSync = false
        initialSyncPreview = nil
        pendingInitialSyncChoice = nil

        let detail = reason.map { friendlyErrorMessage(for: $0) } ?? L10n.shared.session.session.mistiaCouldnTFindTheSavedCloud
        remoteUnavailableReason = detail
        syncStatusTitle = L10n.shared.session.session.signedInOnThisDevice
        syncStatusDetail = detail
        syncStatusSystemImage = reason.map { syncErrorSystemImage(for: $0) } ?? "person.crop.circle.badge.checkmark"
        updateAutoSyncLoopState()
        return true
    }

    private func setPreservedSignedInUserID(_ userID: UUID) {
        userDefaults.set(userID.uuidString.lowercased(), forKey: MistiaAppStorageKey.authPreservedSignedInUserID)
    }

    private func clearPreservedSignedInUserID() {
        userDefaults.removeObject(forKey: MistiaAppStorageKey.authPreservedSignedInUserID)
    }

    private func preservedSignedInUserID() -> UUID? {
        guard let rawValue = userDefaults.string(forKey: MistiaAppStorageKey.authPreservedSignedInUserID) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func applyConfigurationMissingState() {
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
        syncStatusTitle = L10n.shared.session.session.cloudSyncIsnTConfigured
        syncStatusDetail = L10n.shared.session.session.fillInTheServiceURLAndPublic
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
            syncStatusTitle = L10n.shared.session.session.localMode
            syncStatusDetail = L10n.shared.session.session.youReEditingLocalDataForThe
            syncStatusSystemImage = "externaldrive.badge.person.crop"
        case .guestUnbound:
            syncStatusTitle = guestUnboundHasData ? L10n.session.guest.localTitle : L10n.session.guest.cleanTitle
            syncStatusDetail = guestUnboundHasData ? L10n.session.guest.localDataSeparateDetail : L10n.session.guest.cleanDataDetail
            syncStatusSystemImage = guestUnboundHasData
                ? "externaldrive.badge.plus"
                : "person.crop.circle.badge.questionmark"
        case .authenticated, nil:
            syncStatusTitle = L10n.shared.session.session.signedOut
            syncStatusDetail = L10n.shared.session.session.signInToSyncWalletsCategoriesTransactions
            syncStatusSystemImage = "person.crop.circle.badge.plus"
        }
    }

    private func applySyncingState() {
        syncStatusTitle = L10n.shared.session.session.syncing
        syncStatusDetail = L10n.shared.session.session.mistiaIsPushingLocalChangesAndPulling
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
            || isGoogleOAuthConfigurationMessage(message)
    }

    private func googleSetupErrorMessage(for error: Error) -> String {
        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .googleClientIDMissing, .googleServerClientIDMissing:
                return L10n.shared.session.session.fillInTheGoogleIOSClientID
            case .googleCallbackSchemeMissing(let expected):
                return L10n.shared.session.session.addTheGoogleURLSchemeValueTo(String(describing: expected))
            case .configurationMissing, .invalidURL, .invalidResponse, .serverMessage, .missingSession, .missingRefreshToken, .oauthCancelled, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        return L10n.shared.session.session.thisBuildIsMissingTheIOSSettings
    }

    private func infrastructureErrorMessage(for error: Error) -> String {
        if error is URLError || error is SessionRemoteAccessError {
            return L10n.shared.session.session.mistiaCanTReachTheSyncService
        }

        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .configurationMissing:
                return L10n.shared.session.session.theSyncServiceHasnTBeenConfigured
            case .invalidURL, .invalidResponse, .missingSession, .missingRefreshToken, .oauthCancelled, .serverMessage, .googleClientIDMissing, .googleServerClientIDMissing, .googleCallbackSchemeMissing, .googlePresentationContextMissing, .googleTokensMissing:
                break
            }
        }

        return L10n.shared.session.session.theAuthenticationServiceIsTemporarilyBusyPlease
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
            return L10n.shared.session.session.theCloudSessionNeedsToReconnectThe
        }

        if message.contains("404") || message.contains("not found") {
            return L10n.shared.session.session.serverNotReadyErrorYouMight
        }

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return L10n.shared.session.session.accessDeniedErrorPleaseCheckYour
        }

        if message.contains("400") || message.contains("bad request") {
            if isGoogleOAuthConfigurationMessage(message) {
                return L10n.shared.session.session.googleSignInRequestIsInvalidError
            }

            return L10n.shared.session.session.syncRequestIsInvalidErrorDetails(String(describing: rawMessage))
        }

        if message.contains("connection") || message.contains("offline") {
            return L10n.shared.session.session.noInternetConnectionCheckYourWiFi
        }

        if message.contains("data couldn") || message.contains("missing") || message.contains("no data") {
            return L10n.shared.session.session.theSyncResponseCouldnTBeRead
        }

        return rawMessage
    }

    private func isGoogleOAuthConfigurationMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let mentionsGoogle = normalized.contains("google")
            || normalized.contains("oauth")
            || normalized.contains("oidc")
            || normalized.contains("provider")
        let mentionsConfiguration = normalized.contains("client id")
            || normalized.contains("callback")
            || normalized.contains("redirect")
            || normalized.contains("url scheme")
        return mentionsGoogle && mentionsConfiguration
    }

    private func localizedDecodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return L10n.shared.session.session.supabaseIsReturningDataWithoutTheValue(String(describing: key.stringValue))
        case .typeMismatch(_, _), .valueNotFound(_, _), .dataCorrupted(_):
            return L10n.shared.session.session.theSyncDataFromSupabaseDoesnT
        @unknown default:
            return L10n.shared.session.session.theSyncDataFromSupabaseCouldnT
        }
    }

    private func syncErrorTitle(for error: Error) -> String {
        if error is URLError || error is SessionRemoteAccessError {
            return L10n.shared.session.session.syncIsWaitingForTheNetwork
        }

        let message = errorMessage(for: error)

        if message.contains("failed to decode remote data") {
            return L10n.shared.session.session.theExistingCloudDataDoesnTMatch
        }

        if message.contains("403") || message.contains("forbidden") || message.contains("policy") {
            return L10n.shared.session.session.syncAccessDenied
        }

        if message.contains("404") || message.contains("not found") || message.contains("relation") {
            return L10n.shared.session.session.syncTablesMissing
        }

        if message.contains("401") || message.contains("unauthorized") || message.contains("jwt") {
            return L10n.shared.session.session.syncSessionInvalid
        }

        return L10n.shared.session.session.syncNeedsConfigurationChecks
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
            || hasAnySyncConflict(in: context)
    }

    private func hasAnyRemoteBackedRecord(in context: ModelContext) -> Bool {
        hasRemoteBackedRecord(LedgerWallet.self, in: context, predicate: #Predicate<LedgerWallet> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(CreditCardProfile.self, in: context, predicate: #Predicate<CreditCardProfile> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(TransactionCategory.self, in: context, predicate: #Predicate<TransactionCategory> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(SettlementGroup.self, in: context, predicate: #Predicate<SettlementGroup> { $0.remoteVersion > 0 })
            || hasRemoteBackedRecord(SettlementParticipant.self, in: context, predicate: #Predicate<SettlementParticipant> { $0.remoteVersion > 0 })
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

    private func hasAnySyncConflict(in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<SyncConflict>()
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func updateAutoSyncLoopState() {
        if requiresInitialSync && hasCompletedCloudSyncHistory() {
            requiresInitialSync = false
            initialSyncPreview = nil
            pendingInitialSyncChoice = nil
        }

        guard isReadyForAutomaticSync else {
            MistiaSyncBackgroundScheduler.shared.cancelPendingRefresh()
            return
        }

        MistiaSyncBackgroundScheduler.shared.scheduleNextRefresh(after: nextAutomaticSyncDate)
    }

    private func shouldRunForegroundCatchUp() -> Bool {
        guard isReadyForAutomaticSync, !isSyncInFlight else { return false }
        guard let lastSyncAt else { return true }
        return Date().timeIntervalSince(lastSyncAt) >= Self.AUTOMATIC_SYNC_INTERVAL
    }

    private func runInitialSyncFlow(showProgress: Bool = true) async -> Bool {
        return await drainSyncQueue(showProgress: showProgress, trigger: .initial)
    }

    private func runMergeSync(
        trigger: SessionSyncTrigger,
        showProgress: Bool = true,
        normalizesBeforeSync: Bool = true
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
            let pushedFamilyOwnerMutations = try await pushQueuedFamilyOwnerMutations(
                session: validSession
            )
            if normalizesBeforeSync {
                try normalizeCategoryHierarchyIfNeeded()
            }
            let result = try await syncCoordinator.sync(session: validSession)
            lastSyncAt = .now
            lastErrorMessage = nil

            if let userID = summary?.userID, let profile = storedProfile(for: userID) {
                profile.lastSyncAt = lastSyncAt
                try? modelContainer.mainContext.save()
            }

            if showProgress {
                syncStatusTitle = L10n.shared.session.session.syncCompleted
                syncStatusDetail = pushedFamilyOwnerMutations
                    ? L10n.shared.session.session.pushedMemberWalletChangesToCloudValue(String(describing: result.statusMessage))
                    : result.statusMessage
                syncStatusSystemImage = "checkmark.icloud"
            }

            if showProgress {
                try? await Task.sleep(for: .seconds(0.5))
            }

            if let postSyncRefreshHandler {
                await postSyncRefreshHandler(trigger)
            }

            updateAutoSyncLoopState()
            if pendingQueuedAutoSync {
                updateQueuedAutoSyncAfterSync()
            }
            return true
        } catch {
            if showProgress || trigger == .manual {
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

    private func drainSyncQueue(
        showProgress: Bool = true,
        trigger: SessionSyncTrigger
    ) async -> Bool {
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
            let pushedFamilyOwnerMutations = try await pushQueuedFamilyOwnerMutations(
                session: validSession
            )
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
                        syncStatusTitle = L10n.shared.session.session.chooseHowToRunTheFirstSync
                        syncStatusDetail = L10n.shared.session.session.bothThisDeviceAndTheCloudAlready
                        syncStatusSystemImage = "arrow.triangle.branch"
                    }
                    return false
                }

                if showProgress {
                    syncStatusTitle = L10n.shared.session.session.runningInitialSync
                    syncStatusDetail = L10n.shared.session.session.mistiaIsComparingLocalAndCloudData
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
            
            if showProgress {
                syncStatusTitle = L10n.shared.session.session.syncCompleted
                syncStatusDetail = pushedFamilyOwnerMutations
                    ? L10n.shared.session.session.pushedMemberWalletChangesToCloudValue(String(describing: result.statusMessage))
                    : result.statusMessage
                syncStatusSystemImage = "checkmark.icloud"
            }

            if let userID = summary?.userID, let profile = storedProfile(for: userID) {
                profile.lastSyncAt = .now
                try? modelContainer.mainContext.save()
            }

            if let postSyncRefreshHandler {
                await postSyncRefreshHandler(trigger)
            }

            if showProgress {
                try? await Task.sleep(for: .seconds(0.5))
            }
            updateAutoSyncLoopState()
            if pendingQueuedAutoSync {
                updateQueuedAutoSyncAfterSync()
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

        try? MistiaRecordOwnershipStore.upsert(
            entity: mutation.entity,
            recordID: mutation.recordID,
            ownerUserID: subjectUserID,
            updatedAt: mutation.modifiedAt,
            in: modelContainer
        )

        return [
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
                deviceID: mutation.deviceID
            )
        ]
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

    private func schedulePush(for mutations: [MistiaSyncMutation]) {
        let activeUserID = activeLocalProfileUserID ?? currentSession?.user.id
        let hasFamilyOwnerMutations = mutations.contains { mutation in
            guard let activeUserID else { return false }
            return mutation.subjectUserID != activeUserID
        }
        let hasOwnMutations = mutations.contains { mutation in
            guard let activeUserID else { return true }
            return mutation.subjectUserID == activeUserID
        }

        if hasFamilyOwnerMutations {
            scheduleQueuedFamilyOwnerPushIfAllowed()
        }
        if hasOwnMutations {
            scheduleQueuedSyncIfAllowed()
        } else {
            updateAutoSyncLoopState()
        }
    }

    private func waitForCurrentSyncToFinish() async {
        guard isSyncInFlight else { return }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            guard currentSession != nil else { return }
            if !isSyncInFlight {
                break
            }
        }
    }

    private func scheduleFamilyOwnerOutboxRecoveryIfNeeded() {
        guard currentSession != nil,
              isConfigured,
              networkStatus != .disconnected,
              !requiresInitialSync,
              !requiresManualSyncAfterRestore,
              hasQueuedFamilyOwnerMutations() else {
            return
        }
        scheduleQueuedFamilyOwnerPushIfAllowed()
    }

    private func scheduleQueuedSyncIfAllowed() {
        guard isAutoSyncEnabled, canManageSync, !requiresInitialSync, !requiresManualSyncAfterRestore else {
            return
        }

        pendingQueuedAutoSync = true
        updateAutoSyncLoopState()
    }

    private func updateQueuedAutoSyncAfterSync() {
        if hasQueuedOwnMutations() {
            scheduleQueuedSyncIfAllowed()
        } else {
            cancelQueuedAutoSync()
        }
    }

    private func scheduleQueuedFamilyOwnerPushIfAllowed() {
        guard currentSession != nil, isConfigured else {
            return
        }

        pendingFamilyOwnerPush = true
        queuedFamilyOwnerPushTask?.cancel()
        queuedFamilyOwnerPushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.QUEUED_AUTO_SYNC_DEBOUNCE)
            _ = await self?.flushQueuedFamilyOwnerPushIfAllowed()
        }
    }

    private func flushQueuedFamilyOwnerPushIfAllowed() async -> Bool {
        guard currentSession != nil, isConfigured else {
            cancelQueuedFamilyOwnerPush()
            return false
        }

        guard !isSyncInFlight else {
            queuedFamilyOwnerPushTask?.cancel()
            queuedFamilyOwnerPushTask = Task { [weak self] in
                try? await Task.sleep(for: Self.QUEUED_AUTO_SYNC_DEBOUNCE)
                _ = await self?.flushQueuedFamilyOwnerPushIfAllowed()
            }
            return false
        }

        guard hasQueuedFamilyOwnerMutations() else {
            let wasPending = pendingFamilyOwnerPush
            cancelQueuedFamilyOwnerPush()
            return wasPending
        }

        pendingFamilyOwnerPush = false
        queuedFamilyOwnerPushTask = nil
        isSyncInFlight = true
        defer {
            isSyncInFlight = false
            updateAutoSyncLoopState()
        }

        do {
            let validSession = try await prepareRemoteSession()
            _ = try await pushQueuedFamilyOwnerMutations(session: validSession)
            lastSyncAt = .now
            lastErrorMessage = nil
            return true
        } catch {
            recordFamilyOwnerPushConflictIfNeeded(from: error)
            pendingFamilyOwnerPush = hasQueuedFamilyOwnerMutations()
            applySyncErrorState(error)
            return false
        }
    }

    private func queuedFamilyOwnerMutations(
        activeUserID: UUID? = nil
    ) -> [MistiaSyncMutation] {
        let resolvedActiveUserID = activeUserID ?? activeLocalProfileUserID ?? currentSession?.user.id
        guard let resolvedActiveUserID else { return [] }
        return syncCoordinator.queuedMutations().filter { mutation in
            mutation.subjectUserID != resolvedActiveUserID
        }
    }

    private func hasQueuedFamilyOwnerMutations(
        activeUserID: UUID? = nil
    ) -> Bool {
        !queuedFamilyOwnerMutations(activeUserID: activeUserID).isEmpty
    }

    private func hasQueuedOwnMutations(
        activeUserID: UUID? = nil
    ) -> Bool {
        let resolvedActiveUserID = activeUserID ?? activeLocalProfileUserID ?? currentSession?.user.id
        guard let resolvedActiveUserID else { return false }
        return syncCoordinator.queuedMutations().contains { mutation in
            mutation.subjectUserID == resolvedActiveUserID
        }
    }

    private func pushQueuedFamilyOwnerMutations(
        session: SupabaseAuthSession
    ) async throws -> Bool {
        let mutations = queuedFamilyOwnerMutations(activeUserID: session.user.id)
        guard !mutations.isEmpty else {
            cancelQueuedFamilyOwnerPush()
            return false
        }

        pendingFamilyOwnerPush = false
        queuedFamilyOwnerPushTask = nil
        do {
            _ = try await syncCoordinator.pushQueuedFamilyOwnerMutationsCloudFirst(
                mutations,
                session: session
            )
            pendingFamilyOwnerPush = hasQueuedFamilyOwnerMutations(activeUserID: session.user.id)
            return true
        } catch {
            recordFamilyOwnerPushConflictIfNeeded(from: error)
            pendingFamilyOwnerPush = hasQueuedFamilyOwnerMutations(activeUserID: session.user.id)
            throw error
        }
    }

    private func cancelQueuedAutoSync() {
        pendingQueuedAutoSync = false
    }

    private func cancelQueuedFamilyOwnerPush() {
        pendingFamilyOwnerPush = false
        queuedFamilyOwnerPushTask?.cancel()
        queuedFamilyOwnerPushTask = nil
    }

    private func clearSessionRuntimeState() {
        cancelQueuedAutoSync()
        cancelQueuedFamilyOwnerPush()
        reconnectValidationTask?.cancel()
        reconnectValidationTask = nil
        currentSession = nil
        summary = nil
        lastSyncAt = nil
        lastErrorMessage = nil
        remoteUnavailableReason = nil
        accountDevices = []
        accountDevicesErrorMessage = nil
        isLoadingAccountDevices = false
        initialSyncPreview = nil
        pendingInitialSyncChoice = nil
        syncCoordinator.clearQueuedMutations()
        clearFamilyOwnerPushConflicts()
        MistiaSyncBackgroundScheduler.shared.cancelPendingRefresh()
        clearPendingAuthenticationState()
    }

    private func recordFamilyOwnerPushConflictIfNeeded(from error: Error) {
        guard let cloudFirstError = error as? MistiaFamilyCloudFirstPushError,
              let mutation = cloudFirstError.mutation else {
            return
        }
        recordFamilyOwnerPushConflict(for: mutation)
    }

    private func recordFamilyOwnerPushConflict(for mutation: MistiaSyncMutation) {
        let conflict = FamilyOwnerPushConflict(mutation: mutation)
        familyOwnerPushConflicts.removeAll { $0.id == conflict.id }
        familyOwnerPushConflicts.append(conflict)
        persistFamilyOwnerPushConflicts()
    }

    private func clearFamilyOwnerPushConflict(entity: MistiaSyncEntity, recordID: UUID) {
        let key = FamilyOwnerPushConflict.key(entity: entity, recordID: recordID)
        familyOwnerPushConflicts.removeAll { $0.id == key }
        persistFamilyOwnerPushConflicts()
    }

    private func clearFamilyOwnerPushConflicts() {
        familyOwnerPushConflicts.removeAll()
        userDefaults.removeObject(forKey: Self.FAMILY_OWNER_PUSH_CONFLICTS_KEY)
    }

    private func persistFamilyOwnerPushConflicts() {
        guard !familyOwnerPushConflicts.isEmpty else {
            userDefaults.removeObject(forKey: Self.FAMILY_OWNER_PUSH_CONFLICTS_KEY)
            return
        }

        guard let data = try? JSONEncoder.mistiaSyncEncoder.encode(familyOwnerPushConflicts) else {
            return
        }
        userDefaults.set(data, forKey: Self.FAMILY_OWNER_PUSH_CONFLICTS_KEY)
    }

    private static func loadFamilyOwnerPushConflicts(from userDefaults: UserDefaults) -> [FamilyOwnerPushConflict] {
        guard let data = userDefaults.data(forKey: FAMILY_OWNER_PUSH_CONFLICTS_KEY) else {
            return []
        }
        return (try? JSONDecoder.mistiaSyncDecoder.decode([FamilyOwnerPushConflict].self, from: data)) ?? []
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
