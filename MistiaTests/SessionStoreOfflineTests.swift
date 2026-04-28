import Foundation
import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class SessionStoreOfflineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("MISTIA_SUPABASE_URL", "https://example.supabase.co", 1)
        setenv("MISTIA_SUPABASE_ANON_KEY", "test-anon-key", 1)
        MistiaAppLanguage.persist(.english)
    }

    func testBootstrapOfflineRestoresPersistedSessionWithoutRefreshingRemoteState() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let userProfileStore = UserProfileStoreSpy()
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: userProfileStore,
            networkStatus: .disconnected
        )

        await store.bootstrapIfNeeded()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.summary?.userID, session.user.id)
        XCTAssertEqual(store.summary?.displayName, "Taylor Offline")
        XCTAssertTrue(store.isOfflineModeActive)
        XCTAssertFalse(store.canPerformRemoteActions)
        XCTAssertEqual(store.syncStatusTitle, "Offline")
        XCTAssertNotNil(store.remoteUnavailableReason)
        XCTAssertEqual(authService.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(authService.refreshSessionCallCount, 0)
        XCTAssertEqual(userProfileStore.fetchProfileCallCount, 0)
    }

    func testBootstrapOfflineKeepsExpiredSessionSignedInUntilReconnect() async throws {
        let session = makeSession(expiresAt: .now.addingTimeInterval(-600))
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )

        await store.bootstrapIfNeeded()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertTrue(store.canManageSync)
        XCTAssertTrue(store.isOfflineModeActive)
        XCTAssertEqual(authService.refreshSessionCallCount, 0)
        XCTAssertNil(store.authBanner)
    }

    func testReconnectRefreshesExpiredSessionAndClearsOfflineMode() async throws {
        let userID = UUID()
        let expiredSession = makeSession(
            userID: userID,
            email: "taylor@example.com",
            displayName: "Taylor Offline",
            expiresAt: .now.addingTimeInterval(-600)
        )
        let refreshedSession = makeSession(
            userID: userID,
            email: "taylor@example.com",
            displayName: "Taylor Remote",
            accessToken: "refreshed-token",
            refreshToken: "refresh-token",
            expiresAt: .now.addingTimeInterval(3600)
        )
        let authService = SessionAuthServiceSpy(
            persistedSession: expiredSession,
            refreshResult: .success(refreshedSession)
        )
        let userProfileStore = UserProfileStoreSpy(
            fetchProfileResult: RemoteUserProfile(
                userID: userID,
                displayName: "Taylor Remote",
                avatarURL: URL(string: "https://example.com/avatar.jpg"),
                birthday: nil,
                createdAt: .now,
                updatedAt: .now
            )
        )
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: userProfileStore,
            networkStatus: .disconnected
        )

        await store.bootstrapIfNeeded()
        store.handleConnectivityChanged(.connected)
        await waitUntil("session reconnects") {
            authService.refreshSessionCallCount == 1
                && userProfileStore.fetchProfileCallCount == 1
                && store.canPerformRemoteActions
        }

        XCTAssertTrue(store.isSignedIn)
        XCTAssertFalse(store.isOfflineModeActive)
        XCTAssertTrue(store.canPerformRemoteActions)
        XCTAssertNil(store.remoteUnavailableReason)
        XCTAssertEqual(store.summary?.displayName, "Taylor Offline")
        XCTAssertEqual(userProfileStore.fetchProfileCallCount, 1)
    }

    func testReconnectWithInvalidRefreshTokenSignsOutAndShowsExpiredBanner() async throws {
        let session = makeSession(expiresAt: .now.addingTimeInterval(-600))
        let authService = SessionAuthServiceSpy(
            persistedSession: session,
            refreshResult: .failure(
                SupabaseServiceError.serverMessage("[POST token] HTTP 401: refresh token not found")
            )
        )
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )

        await store.bootstrapIfNeeded()
        store.handleConnectivityChanged(.connected)
        await waitUntil("session invalidates after reconnect") {
            authService.clearPersistedSessionCallCount == 1 && !store.isSignedIn
        }

        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(store.summary)
        XCTAssertEqual(authService.refreshSessionCallCount, 1)
        XCTAssertEqual(authService.clearPersistedSessionCallCount, 1)
        XCTAssertEqual(store.authBanner?.title, "Session expired after reconnect")
        XCTAssertEqual(
            store.authBanner?.message,
            "Session expired or invalid. Please try signing in again."
        )
    }

    func testFamilyRefreshKeepsCachedSnapshotWhenOffline() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(
            persistedSession: session,
            refreshResult: .success(session)
        )
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected
        )
        let familySnapshot = makeFamilySnapshot(userID: session.user.id)
        let familyService = FamilyRemoteServiceSpy(snapshot: familySnapshot)
        let familyStore = FamilyContextStore(
            modelContainer: try storeTestContainer(),
            service: familyService
        )

        await store.bootstrapIfNeeded()
        await familyStore.refresh(sessionStore: store)

        XCTAssertEqual(familyStore.family?.id, familySnapshot.family?.id)
        XCTAssertTrue(familyStore.hasCachedRemoteState)
        XCTAssertEqual(familyService.fetchStateCallCount, 1)

        store.handleConnectivityChanged(.disconnected)
        await familyStore.refresh(sessionStore: store)

        XCTAssertEqual(familyStore.family?.id, familySnapshot.family?.id)
        XCTAssertEqual(familyService.fetchStateCallCount, 1)
        XCTAssertEqual(familyStore.lastErrorMessage, store.remoteUnavailableReason)
        XCTAssertTrue(familyStore.hasCachedRemoteState)
    }

    func testFamilyRefreshWithoutCachedStateShowsOfflineMessageInsteadOfAuthFailure() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        let familyService = FamilyRemoteServiceSpy(snapshot: .empty)
        let familyStore = FamilyContextStore(
            modelContainer: try storeTestContainer(),
            service: familyService
        )

        await store.bootstrapIfNeeded()
        await familyStore.refresh(sessionStore: store)

        XCTAssertNil(familyStore.family)
        XCTAssertFalse(familyStore.hasCachedRemoteState)
        XCTAssertEqual(familyService.fetchStateCallCount, 0)
        XCTAssertEqual(familyStore.lastErrorMessage, store.remoteUnavailableReason)
    }

    func testSignOutKeepsPreviousAccountAsEditableLocalProfile() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )

        await store.bootstrapIfNeeded()
        await store.signOut()

        XCTAssertFalse(store.isSignedIn)
        XCTAssertTrue(store.isGuestLocalModeActive)
        XCTAssertEqual(store.localModeProfileUserID, session.user.id)
        XCTAssertEqual(store.syncStatusTitle, "Local mode")
        XCTAssertTrue(store.syncStatusDetail.contains("same account"))
    }

    func testGuestLocalEditIsOwnedByPreviousLocalProfile() throws {
        let localProfileUserID = UUID()
        let container = try storeTestContainer()
        let userDefaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        userDefaults.set(
            localProfileUserID.uuidString.lowercased(),
            forKey: MistiaAppStorageKey.localModeProfileUserID
        )
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: nil),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            userDefaults: userDefaults
        )

        let wallet = LedgerWallet(
            name: "Local cash",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        container.mainContext.insert(wallet)
        try container.mainContext.save()

        store.recordUpsert(
            entity: .wallet,
            recordID: wallet.id,
            modifiedAt: wallet.updatedAt
        )

        let ownerUserID = try MistiaRecordOwnershipStore.ownerUserID(
            entity: .wallet,
            recordID: wallet.id,
            in: container
        )
        XCTAssertEqual(ownerUserID, localProfileUserID)
    }

    private func makeSessionStore(
        authService: SessionAuthServiceSpy,
        userProfileStore: UserProfileStoreSpy,
        networkStatus: SessionNetworkStatus,
        modelContainer: ModelContainer? = nil,
        userDefaults: UserDefaults? = nil
    ) throws -> SessionStore {
        let resolvedContainer: ModelContainer
        if let modelContainer {
            resolvedContainer = modelContainer
        } else {
            resolvedContainer = try storeTestContainer()
        }

        return SessionStore(
            modelContainer: resolvedContainer,
            userDefaults: userDefaults ?? UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
            authService: authService,
            userProfileStore: userProfileStore,
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: networkStatus),
            registerBackgroundRefresh: false
        )
    }

    private func storeTestContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSession(
        userID: UUID = UUID(),
        email: String = "taylor@example.com",
        displayName: String = "Taylor Offline",
        accessToken: String = "access-token",
        refreshToken: String = "refresh-token",
        expiresAt: Date? = .now.addingTimeInterval(3600)
    ) -> SupabaseAuthSession {
        SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: "bearer",
            expiresAt: expiresAt,
            user: SupabaseAuthUser(
                id: userID,
                email: email,
                userMetadata: SupabaseUserMetadata(
                    displayName: displayName,
                    fullName: nil,
                    name: nil,
                    avatarURL: nil,
                    picture: nil
                )
            )
        )
    }

    private func makeFamilySnapshot(userID: UUID) -> FamilyStateSnapshot {
        let familyID = UUID()
        let membershipID = UUID()
        let now = Date()
        return FamilyStateSnapshot(
            family: FamilyGroupRecord(
                id: familyID,
                name: "Offline Family",
                ownerUserID: userID,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            currentMembership: FamilyMembershipRecord(
                id: membershipID,
                familyID: familyID,
                userID: userID,
                roleRawValue: FamilyRole.owner.rawValue,
                canViewFamilyDashboard: true,
                canViewOthers: true,
                canEditOthers: true,
                canViewWallets: true,
                canViewDebts: true,
                canViewKids: true,
                canEditKids: true,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            members: [
                FamilyMember(
                    membershipID: membershipID,
                    familyID: familyID,
                    userID: userID,
                    displayName: "Taylor Offline",
                    avatarURL: nil,
                    role: .owner,
                    policy: .preset(for: .owner),
                    isCurrentUser: true
                )
            ],
            invites: [],
            walletAccessGrants: []
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        condition: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTFail("Timed out waiting for \(description)")
    }
}

@MainActor
private final class SessionAuthServiceSpy: SessionAuthServicing {
    private let persistedSession: SupabaseAuthSession?
    private let refreshResult: Result<SupabaseAuthSession, Error>

    private(set) var loadPersistedSessionCallCount = 0
    private(set) var refreshSessionCallCount = 0
    private(set) var clearPersistedSessionCallCount = 0

    init(
        persistedSession: SupabaseAuthSession?,
        refreshResult: Result<SupabaseAuthSession, Error>? = nil
    ) {
        self.persistedSession = persistedSession
        self.refreshResult = refreshResult
            ?? persistedSession.map { .success($0) }
            ?? .failure(SessionRemoteAccessError.offline)
    }

    func loadPersistedSession() throws -> SupabaseAuthSession? {
        loadPersistedSessionCallCount += 1
        return persistedSession
    }

    func restoreSession() async throws -> SupabaseAuthSession? {
        persistedSession
    }

    func signUp(
        email: String,
        password: String,
        displayName: String
    ) async throws -> SupabaseSignUpOutcome {
        fatalError("Unused in tests")
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> SupabaseAuthSession {
        fatalError("Unused in tests")
    }

    func signInWithGoogle() async throws -> SupabaseAuthSession {
        fatalError("Unused in tests")
    }

    func refreshSessionIfNeeded(_ session: SupabaseAuthSession) async throws -> SupabaseAuthSession {
        refreshSessionCallCount += 1
        return try refreshResult.get()
    }

    func signOut(session: SupabaseAuthSession?) async throws {
        // no-op for tests
    }

    func deleteAccount(session: SupabaseAuthSession) async throws {
        fatalError("Unused in tests")
    }

    func requestPasswordReset(email: String) async throws {
        fatalError("Unused in tests")
    }

    func resendConfirmation(email: String) async throws {
        fatalError("Unused in tests")
    }

    func clearPersistedSession() throws {
        clearPersistedSessionCallCount += 1
    }
}

@MainActor
private final class UserProfileStoreSpy: UserProfileRemoteStoring {
    private let fetchProfileResult: RemoteUserProfile?

    private(set) var fetchProfileCallCount = 0

    init(fetchProfileResult: RemoteUserProfile? = nil) {
        self.fetchProfileResult = fetchProfileResult
    }

    func fetchProfile(session: SupabaseAuthSession) async throws -> RemoteUserProfile? {
        fetchProfileCallCount += 1
        return fetchProfileResult
    }

    func upsertProfile(
        displayName: String,
        avatarURL: URL?,
        birthday: Date?,
        session: SupabaseAuthSession
    ) async throws -> RemoteUserProfile {
        RemoteUserProfile(
            userID: session.user.id,
            displayName: displayName,
            avatarURL: avatarURL,
            birthday: birthday,
            createdAt: .now,
            updatedAt: .now
        )
    }

    func uploadAvatarImageData(
        _ data: Data,
        session: SupabaseAuthSession
    ) async throws -> URL {
        URL(string: "https://example.com/avatar.jpg")!
    }
}

@MainActor
private final class FamilyRemoteServiceSpy: FamilyRemoteServicing {
    private let snapshot: FamilyStateSnapshot

    private(set) var fetchStateCallCount = 0

    init(snapshot: FamilyStateSnapshot) {
        self.snapshot = snapshot
    }

    func fetchState(session: SupabaseAuthSession) async throws -> FamilyStateSnapshot {
        fetchStateCallCount += 1
        return snapshot
    }

    func createFamily(
        name: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        fatalError("Unused in tests")
    }

    func joinInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        fatalError("Unused in tests")
    }

    func createInvite(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        fatalError("Unused in tests")
    }

    func updateMember(
        membershipID: UUID,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        session: SupabaseAuthSession
    ) async throws {
        fatalError("Unused in tests")
    }

    func syncWalletAccessGrants(
        familyID: UUID,
        granteeUserID: UUID,
        targetUserIDs: Set<UUID>,
        session: SupabaseAuthSession
    ) async throws {
        fatalError("Unused in tests")
    }

    func removeMember(
        membershipID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        fatalError("Unused in tests")
    }

    func deleteFamily(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        fatalError("Unused in tests")
    }

    func fetchAccessibleFinanceSnapshot(
        userIDs: [UUID],
        session: SupabaseAuthSession
    ) async throws -> MistiaRemoteSnapshot {
        .empty
    }
}

private extension FamilyStateSnapshot {
    static let empty = FamilyStateSnapshot(
        family: nil,
        currentMembership: nil,
        members: [],
        invites: [],
        walletAccessGrants: []
    )
}
