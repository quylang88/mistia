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

    override func setUp() {
        super.setUp()
        clearProfileArtifacts()
    }

    override func tearDown() {
        clearProfileArtifacts()
        super.tearDown()
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

    func testBootstrapConnectedRestoresPersistedSessionWithoutRefreshingRemoteState() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let userProfileStore = UserProfileStoreSpy()
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: userProfileStore,
            networkStatus: .connected
        )

        await store.bootstrapIfNeeded()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.summary?.userID, session.user.id)
        XCTAssertTrue(store.canPerformRemoteActions)
        XCTAssertEqual(authService.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(authService.refreshSessionCallCount, 0)
        XCTAssertEqual(userProfileStore.fetchProfileCallCount, 0)
    }

    func testDeferredValidationRefreshesExpiredSessionAfterLocalBootstrap() async throws {
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
            networkStatus: .connected
        )

        await store.bootstrapIfNeeded()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(authService.refreshSessionCallCount, 0)
        XCTAssertEqual(userProfileStore.fetchProfileCallCount, 0)

        await store.validateRestoredSessionInBackgroundIfNeeded()

        XCTAssertTrue(store.canPerformRemoteActions)
        XCTAssertNil(store.remoteUnavailableReason)
        XCTAssertEqual(authService.refreshSessionCallCount, 1)
        XCTAssertEqual(userProfileStore.fetchProfileCallCount, 1)
    }

    func testFamilyBootstrapRestoresCachedSnapshotWithoutFetchingRemoteState() async throws {
        let userID = UUID()
        let userDefaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        let launchState = try MistiaDataStack.LaunchState(userDefaults: userDefaults)
        _ = try launchState.ensureCloudProfile(for: userID, activate: true)
        let session = makeSession(userID: userID)
        let store = SessionStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            userDefaults: userDefaults,
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .connected),
            registerBackgroundRefresh: false
        )
        await store.bootstrapIfNeeded()

        let cachedSnapshot = makeFamilySnapshot(userID: userID)
        let cacheWriterService = FamilyRemoteServiceSpy(snapshot: cachedSnapshot)
        let cacheWriter = FamilyContextStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            service: cacheWriterService
        )
        await cacheWriter.refresh(sessionStore: store)
        XCTAssertEqual(cacheWriterService.fetchStateCallCount, 1)

        let bootstrapService = FamilyRemoteServiceSpy(snapshot: .empty)
        let bootstrapStore = FamilyContextStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            service: bootstrapService
        )

        await bootstrapStore.bootstrapIfNeeded(sessionStore: store)

        XCTAssertEqual(bootstrapStore.family?.id, cachedSnapshot.family?.id)
        XCTAssertTrue(bootstrapStore.hasCachedRemoteState)
        XCTAssertEqual(bootstrapService.fetchStateCallCount, 0)
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

    func testReconnectWithInvalidRefreshTokenKeepsAccountSignedIn() async throws {
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
        await waitUntil("session stays signed in after reconnect refresh failure") {
            authService.refreshSessionCallCount == 1 && store.remoteUnavailableReason != nil
        }

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.summary?.userID, session.user.id)
        XCTAssertEqual(authService.refreshSessionCallCount, 1)
        XCTAssertEqual(authService.clearPersistedSessionCallCount, 0)
        XCTAssertNil(store.authBanner)
        XCTAssertEqual(store.syncStatusTitle, "The session was kept on this device")
        XCTAssertEqual(
            store.remoteUnavailableReason,
            "The cloud session needs to reconnect. The account is still kept signed in on this device."
        )
    }

    func testBootstrapWithoutPersistedSessionRestoresPreservedCloudProfileLocally() async throws {
        let userID = UUID()
        let userDefaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        let launchState = try MistiaDataStack.LaunchState(userDefaults: userDefaults)
        _ = try launchState.ensureCloudProfile(for: userID, activate: true)
        userDefaults.set(
            userID.uuidString.lowercased(),
            forKey: MistiaAppStorageKey.authPreservedSignedInUserID
        )

        let profile = UserAccountProfile(
            userID: userID,
            email: "preserved@example.com",
            displayName: "Preserved User"
        )
        launchState.modelContainer.mainContext.insert(profile)
        try launchState.modelContainer.mainContext.save()

        let authService = SessionAuthServiceSpy(persistedSession: nil)
        let store = SessionStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            userDefaults: userDefaults,
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .connected),
            registerBackgroundRefresh: false
        )

        await store.bootstrapIfNeeded()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertFalse(store.canManageSync)
        XCTAssertEqual(store.summary?.userID, userID)
        XCTAssertEqual(store.summary?.email, "preserved@example.com")
        XCTAssertEqual(store.summary?.displayName, "Preserved User")
        XCTAssertEqual(store.syncStatusTitle, "Signed in on this device")
        XCTAssertEqual(authService.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(authService.clearPersistedSessionCallCount, 0)
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

    func testFamilyMetadataRefreshDoesNotPullMemberFinanceWhenEnteringFamily() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "family-entry-refresh"
                )
            )
        )
        let familyService = FamilyRemoteServiceSpy(
            snapshot: makeFamilySnapshot(userID: currentUserID, ownerUserID: memberUserID)
        )
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = nil
        XCTAssertFalse(store.isAutoSyncEnabled)

        await familyStore.refreshFamilyMetadata(sessionStore: store)

        XCTAssertNil(store.lastSyncAt)
        XCTAssertEqual(syncRemoteStore.fetchSnapshotCallCount, 0)
        XCTAssertEqual(familyService.fetchStateCallCount, 1)
        XCTAssertEqual(familyService.accessibleFinanceUserIDBatches.map(Set.init), [])
    }

    func testFamilyOverviewRefreshPullsMembersOnlyWithoutPersonalSync() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "family-user-refresh"
                )
            )
        )
        let familyService = FamilyRemoteServiceSpy(
            snapshot: makeFamilySnapshot(userID: currentUserID, ownerUserID: memberUserID)
        )
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = nil
        XCTAssertFalse(store.isAutoSyncEnabled)

        await familyStore.refreshLatest(sessionStore: store, source: .familyOverview)

        XCTAssertNil(store.lastSyncAt)
        XCTAssertEqual(syncRemoteStore.fetchSnapshotCallCount, 0)
        XCTAssertEqual(familyService.fetchStateCallCount, 1)
        XCTAssertEqual(
            familyService.accessibleFinanceUserIDBatches.map(Set.init),
            [Set([memberUserID])]
        )
    }

    func testFamilyMemberRefreshPullsOnlySelectedMemberFinance() async throws {
        let currentUserID = UUID()
        let ownerUserID = UUID()
        let selectedMemberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container
        )
        var snapshot = makeFamilySnapshot(userID: currentUserID, ownerUserID: ownerUserID)
        snapshot.members.append(
            FamilyMember(
                membershipID: UUID(),
                familyID: snapshot.family!.id,
                userID: selectedMemberUserID,
                displayName: "Member",
                avatarURL: nil,
                role: .member,
                policy: .preset(for: .member),
                isCurrentUser: false
            )
        )
        let familyService = FamilyRemoteServiceSpy(snapshot: snapshot)
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()
        await familyStore.refreshFamilyMetadata(sessionStore: store)
        await familyStore.refreshMemberFinance(
            sessionStore: store,
            memberUserID: selectedMemberUserID
        )

        XCTAssertEqual(familyService.fetchStateCallCount, 1)
        XCTAssertEqual(
            familyService.accessibleFinanceUserIDBatches.map(Set.init),
            [Set([selectedMemberUserID])]
        )
    }

    func testFamilyMemberRefreshCoalescesRequestsForTheSameMember() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container
        )
        let familyService = FamilyRemoteServiceSpy(
            snapshot: makeFamilySnapshot(userID: currentUserID, ownerUserID: memberUserID)
        )
        familyService.fetchFinanceDelayNanoseconds = 200_000_000
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()
        await familyStore.refreshFamilyMetadata(sessionStore: store)
        guard let member = familyStore.members.first(where: { $0.userID == memberUserID }) else {
            return XCTFail("Expected member")
        }
        familyStore.activateMemberView(member)

        async let first: Void = familyStore.refreshMemberFinance(
            sessionStore: store,
            memberUserID: memberUserID
        )
        await waitUntil("member refresh to start") {
            familyService.accessibleFinanceUserIDBatches.count == 1
        }
        XCTAssertTrue(familyStore.isRefreshingViewedMemberFinance)

        async let second: Void = familyStore.refreshMemberFinance(
            sessionStore: store,
            memberUserID: memberUserID
        )
        _ = await (first, second)

        XCTAssertEqual(familyService.accessibleFinanceUserIDBatches.count, 1)
        XCTAssertFalse(familyStore.isRefreshingViewedMemberFinance)
    }

    func testFamilyMemberRefreshCancelsStaleRequestWhenViewedMemberChanges() async throws {
        let currentUserID = UUID()
        let firstMemberUserID = UUID()
        let secondMemberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container
        )
        var snapshot = makeFamilySnapshot(userID: currentUserID, ownerUserID: firstMemberUserID)
        snapshot.members.append(
            FamilyMember(
                membershipID: UUID(),
                familyID: snapshot.family!.id,
                userID: secondMemberUserID,
                displayName: "Second member",
                avatarURL: nil,
                role: .member,
                policy: .preset(for: .member),
                isCurrentUser: false
            )
        )
        let familyService = FamilyRemoteServiceSpy(snapshot: snapshot)
        familyService.fetchFinanceDelayNanoseconds = 300_000_000
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()
        await familyStore.refreshFamilyMetadata(sessionStore: store)
        let firstMember = try XCTUnwrap(
            familyStore.members.first(where: { $0.userID == firstMemberUserID })
        )
        let secondMember = try XCTUnwrap(
            familyStore.members.first(where: { $0.userID == secondMemberUserID })
        )

        familyStore.activateMemberView(firstMember)
        let firstTask = Task {
            await familyStore.refreshMemberFinance(
                sessionStore: store,
                memberUserID: firstMemberUserID
            )
        }
        await waitUntil("first member refresh to start") {
            familyService.accessibleFinanceUserIDBatches.count == 1
        }

        familyStore.activateMemberView(secondMember)
        await familyStore.refreshMemberFinance(
            sessionStore: store,
            memberUserID: secondMemberUserID
        )
        await firstTask.value

        XCTAssertEqual(
            familyService.accessibleFinanceUserIDBatches.map(Set.init),
            [Set([firstMemberUserID]), Set([secondMemberUserID])]
        )
        XCTAssertEqual(familyStore.viewedMember?.userID, secondMemberUserID)
        XCTAssertFalse(familyStore.isRefreshingViewedMemberFinance)
        XCTAssertNil(familyStore.lastErrorMessage)
    }

    func testQueuedLocalMutationRunsAutomaticSyncWithoutWaitingForCadence() async throws {
        let session = makeSession()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "queued-local-mutation"
                )
            )
        )

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = .now
        store.setAutoSyncEnabled(true)
        let wallet = LedgerWallet(
            name: "Cash",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        container.mainContext.insert(wallet)
        try container.mainContext.save()

        store.recordUpsert(
            entity: .wallet,
            recordID: wallet.id,
            modifiedAt: wallet.updatedAt,
            subjectUserIDOverride: session.user.id
        )

        await waitUntil(
            "queued local mutation runs automatic sync",
            timeout: .seconds(8)
        ) {
            syncRemoteStore.createCallCount > 0
        }
    }

    func testFamilyOwnerMutationPushesImmediatelyWithoutWaitingForAutoSyncCadence() async throws {
        let session = makeSession()
        let memberUserID = UUID()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "family-owner-mutation"
                )
            )
        )
        let wallet = LedgerWallet(
            name: "Member cash",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        container.mainContext.insert(wallet)
        try container.mainContext.save()

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = .now
        store.setAutoSyncEnabled(false)

        store.recordUpsert(
            entity: .wallet,
            recordID: wallet.id,
            modifiedAt: wallet.updatedAt,
            subjectUserIDOverride: memberUserID
        )

        await waitUntil("family owner mutation pushes immediately") {
            syncRemoteStore.createCallCount > 0
        }
        XCTAssertEqual(syncRemoteStore.createdSubjectUserIDs, [memberUserID])
    }

    func testFamilyOwnerRemoteChangeCreatesConflictMarkerAndKeepsQueuedMutation() async throws {
        let session = makeSession()
        let memberUserID = UUID()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "family-owner-remote-change"
                )
            )
        )
        let wallet = LedgerWallet(
            name: "Member cash",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        container.mainContext.insert(wallet)
        try container.mainContext.save()
        syncRemoteStore.fetchRecordResult = .wallet(remoteWallet(
            id: wallet.id,
            userID: memberUserID,
            name: "Cloud member cash",
            syncVersion: 2
        ))

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = .now

        store.recordUpsert(
            entity: .wallet,
            recordID: wallet.id,
            modifiedAt: wallet.updatedAt,
            subjectUserIDOverride: memberUserID
        )

        await waitUntil("family owner conflict marker appears") {
            store.hasFamilyOwnerPushConflict(entity: .wallet, recordID: wallet.id)
        }
        let conflict = try XCTUnwrap(store.familyOwnerPushConflict(entity: .wallet, recordID: wallet.id))
        XCTAssertEqual(conflict.ownerUserID, memberUserID)
        XCTAssertEqual(conflict.kind, .upsert)
        XCTAssertTrue(store.protectedQueuedRecordIDs().contains("ledger_wallets:\(wallet.id.uuidString.lowercased())"))
    }

    func testDiscardFamilyOwnerConflictRemovesQueuedMutationAndRefreshesOwnerFinance() async throws {
        let session = makeSession()
        let memberUserID = UUID()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "family-owner-discard"
                )
            )
        )
        let familyService = FamilyRemoteServiceSpy(
            snapshot: makeFamilySnapshot(userID: session.user.id, ownerUserID: memberUserID)
        )
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )
        let wallet = LedgerWallet(
            name: "Member cash",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        container.mainContext.insert(wallet)
        try container.mainContext.save()
        syncRemoteStore.fetchRecordResult = .wallet(remoteWallet(
            id: wallet.id,
            userID: memberUserID,
            name: "Cloud member cash",
            syncVersion: 2
        ))

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = .now
        store.recordUpsert(
            entity: .wallet,
            recordID: wallet.id,
            modifiedAt: wallet.updatedAt,
            subjectUserIDOverride: memberUserID
        )
        await waitUntil("family owner conflict marker appears") {
            store.hasFamilyOwnerPushConflict(entity: .wallet, recordID: wallet.id)
        }

        await store.discardFamilyOwnerPushConflictAndRefresh(
            entity: .wallet,
            recordID: wallet.id,
            familyContextStore: familyStore
        )

        XCTAssertFalse(store.hasFamilyOwnerPushConflict(entity: .wallet, recordID: wallet.id))
        XCTAssertFalse(store.protectedQueuedRecordIDs().contains("ledger_wallets:\(wallet.id.uuidString.lowercased())"))
        XCTAssertEqual(familyService.accessibleFinanceUserIDBatches.map(Set.init), [Set([memberUserID])])
    }

    func testForegroundActivationDoesNotRunAutomaticSyncWhenNoLocalWorkIsQueued() async throws {
        let session = makeSession()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let accountDeviceStore = AccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "foreground-catch-up"
                )
            ),
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = Date().addingTimeInterval(-1_201)
        store.setAutoSyncEnabled(true)

        store.handleSceneDidBecomeActive()

        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(syncRemoteStore.fetchSnapshotCallCount, 0)
    }

    func testManualSyncReportsManualPostSyncTrigger() async throws {
        let session = makeSession()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "manual-post-sync-trigger"
                )
            )
        )
        var receivedTriggers: [SessionSyncTrigger] = []

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.setPostSyncRefreshHandler { trigger in
            receivedTriggers.append(trigger)
        }

        let didSync = await store.syncNow(isManual: true)
        XCTAssertTrue(didSync)
        XCTAssertEqual(receivedTriggers, [.manual])
    }

    func testBackgroundRefreshReportsBackgroundPostSyncTrigger() async throws {
        let session = makeSession()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "background-post-sync-trigger"
                )
            )
        )
        var receivedTriggers: [SessionSyncTrigger] = []

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = Date().addingTimeInterval(-1_201)
        store.setAutoSyncEnabled(true)
        store.setPostSyncRefreshHandler { trigger in
            receivedTriggers.append(trigger)
        }

        let didSync = await store.handleBackgroundRefresh()

        XCTAssertTrue(didSync)
        XCTAssertEqual(syncRemoteStore.fetchSnapshotCallCount, 2)
        XCTAssertEqual(receivedTriggers, [.backgroundRefresh])
    }

    func testDeferredActiveStartupDoesNotFetchSyncSnapshotAfterInitialSyncCompleted() async throws {
        let session = makeSession()
        let container = try storeTestContainer()
        let syncRemoteStore = SessionSyncRemoteStoreSpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container,
            syncCoordinator: SyncCoordinator(
                modelContainer: container,
                remoteStore: syncRemoteStore,
                outbox: MistiaSyncOutbox(
                    defaults: UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard,
                    key: "deferred-startup-no-sync"
                )
            )
        )

        await store.bootstrapIfNeeded()
        store.requiresInitialSync = false
        store.lastSyncAt = Date().addingTimeInterval(-1_201)
        store.setAutoSyncEnabled(true)

        let didSync = await store.runDeferredStartupSyncIfNeeded()

        XCTAssertFalse(didSync)
        XCTAssertEqual(syncRemoteStore.fetchSnapshotCallCount, 0)
    }

    func testFamilyOverviewRefreshCoalescesRapidRequests() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container
        )
        let familyService = FamilyRemoteServiceSpy(
            snapshot: makeFamilySnapshot(userID: currentUserID, ownerUserID: memberUserID)
        )
        familyService.fetchStateDelayNanoseconds = 100_000_000
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()

        async let first: Void = familyStore.refreshLatest(sessionStore: store, source: .familyOverview)
        async let second: Void = familyStore.refreshLatest(sessionStore: store, source: .familyOverview)
        _ = await (first, second)

        XCTAssertEqual(familyService.fetchStateCallCount, 1)
        XCTAssertEqual(
            familyService.accessibleFinanceUserIDBatches.map(Set.init),
            [Set([memberUserID])]
        )
    }

    func testFamilyOverviewRefreshKeepsCachedStateWhenRemoteFails() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let container = try storeTestContainer()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(
                persistedSession: session,
                refreshResult: .success(session)
            ),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            modelContainer: container
        )
        let initialSnapshot = makeFamilySnapshot(userID: currentUserID, ownerUserID: memberUserID)
        let familyService = FamilyRemoteServiceSpy(snapshot: initialSnapshot)
        let familyStore = FamilyContextStore(
            modelContainer: container,
            service: familyService
        )

        await store.bootstrapIfNeeded()
        await familyStore.refresh(sessionStore: store)
        XCTAssertEqual(familyStore.family?.id, initialSnapshot.family?.id)

        familyService.fetchStateError = SupabaseServiceError.serverMessage("temporary family outage")
        await familyStore.refreshLatest(sessionStore: store, source: .familyOverview)

        XCTAssertEqual(familyStore.family?.id, initialSnapshot.family?.id)
        XCTAssertTrue(familyStore.hasCachedRemoteState)
        XCTAssertEqual(familyStore.lastErrorMessage, "temporary family outage")
    }

    func testFamilyGranularPermissionGrantsSeparateUseEditAndCreate() async throws {
        let currentUserID = UUID()
        let ownerUserID = UUID()
        let usableWalletID = UUID()
        let editableWalletID = UUID()
        let session = makeSession(userID: currentUserID)
        let authService = SessionAuthServiceSpy(
            persistedSession: session,
            refreshResult: .success(session)
        )
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected
        )
        let snapshot = makeFamilySnapshot(
            userID: currentUserID,
            ownerUserID: ownerUserID,
            permissionGrants: [
                makePermissionGrant(
                    granteeUserID: currentUserID,
                    ownerUserID: ownerUserID,
                    resourceType: .wallet,
                    resourceID: usableWalletID,
                    scope: .use
                ),
                makePermissionGrant(
                    granteeUserID: currentUserID,
                    ownerUserID: ownerUserID,
                    resourceType: .wallet,
                    resourceID: editableWalletID,
                    scope: .edit
                ),
                makePermissionGrant(
                    granteeUserID: currentUserID,
                    ownerUserID: ownerUserID,
                    resourceType: .transaction,
                    resourceID: nil,
                    scope: .create
                )
            ]
        )
        let familyStore = FamilyContextStore(
            modelContainer: try storeTestContainer(),
            service: FamilyRemoteServiceSpy(snapshot: snapshot)
        )

        await store.bootstrapIfNeeded()
        await familyStore.refresh(sessionStore: store)

        XCTAssertTrue(familyStore.canUseWallet(walletID: usableWalletID, ownerUserID: ownerUserID))
        XCTAssertFalse(familyStore.canEdit(ownerUserID: ownerUserID, resourceType: .wallet, resourceID: usableWalletID))
        XCTAssertTrue(familyStore.canEdit(ownerUserID: ownerUserID, resourceType: .wallet, resourceID: editableWalletID))
        XCTAssertFalse(familyStore.canUseWallet(walletID: editableWalletID, ownerUserID: ownerUserID))
        XCTAssertTrue(familyStore.canCreate(ownerUserID: ownerUserID, resourceType: .transaction))
        XCTAssertFalse(familyStore.canEdit(ownerUserID: ownerUserID, resourceType: .transaction))
        XCTAssertFalse(familyStore.canCreate(ownerUserID: ownerUserID, resourceType: .category))
    }

    func testFamilyRefreshClearsPendingWalletUseRequestAfterGrantArrives() async throws {
        let currentUserID = UUID()
        let ownerUserID = UUID()
        let walletID = UUID()
        let session = makeSession(userID: currentUserID)
        let authService = SessionAuthServiceSpy(
            persistedSession: session,
            refreshResult: .success(session)
        )
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected
        )
        let restrictedPolicy = FamilyPermissionPolicy(
            canViewFamilyDashboard: false,
            canViewOthers: false,
            canEditOthers: false,
            canViewWallets: false,
            canViewDebts: false,
            canViewKids: false,
            canEditKids: false
        )
        let initialSnapshot = makeFamilySnapshot(
            userID: currentUserID,
            ownerUserID: ownerUserID,
            currentPolicy: restrictedPolicy
        )
        let familyService = FamilyRemoteServiceSpy(snapshot: initialSnapshot)
        let familyStore = FamilyContextStore(
            modelContainer: try storeTestContainer(),
            service: familyService
        )

        await store.bootstrapIfNeeded()
        let didInitialRefresh = await familyStore.refresh(sessionStore: store)
        XCTAssertTrue(didInitialRefresh)

        let didRequestPermission = await familyStore.requestPermission(
            resourceType: .wallet,
            resourceID: walletID,
            ownerUserID: ownerUserID,
            scope: .use,
            resourceName: "Shared Wallet",
            sessionStore: store
        )
        XCTAssertTrue(didRequestPermission)
        XCTAssertTrue(
            familyStore.hasPendingPermissionRequest(
                ownerUserID: ownerUserID,
                resourceType: .wallet,
                resourceID: walletID,
                scope: .use
            )
        )

        familyService.setSnapshot(
            makeFamilySnapshot(
                userID: currentUserID,
                ownerUserID: ownerUserID,
                currentPolicy: restrictedPolicy,
                permissionGrants: [
                    makePermissionGrant(
                        granteeUserID: currentUserID,
                        ownerUserID: ownerUserID,
                        resourceType: .wallet,
                        resourceID: walletID,
                        scope: .use
                    )
                ]
            )
        )

        let didRefreshGrantedState = await familyStore.refreshPermissionGrant(
            ownerUserID: ownerUserID,
            resourceType: .wallet,
            resourceID: walletID,
            scope: .use,
            sessionStore: store
        )
        XCTAssertTrue(didRefreshGrantedState)
        XCTAssertTrue(familyStore.canUseWallet(walletID: walletID, ownerUserID: ownerUserID))
        XCTAssertTrue(familyService.accessibleFinanceUserIDBatches.contains { Set($0).contains(ownerUserID) })
        XCTAssertFalse(
            familyStore.hasPendingPermissionRequest(
                ownerUserID: ownerUserID,
                resourceType: .wallet,
                resourceID: walletID,
                scope: .use
            )
        )
    }

    func testLocalAndSystemNotificationsAreRecipientScoped() {
        let currentUserID = UUID()
        let otherUserID = UUID()
        let referenceDate = Date()
        let currentLocal = AppNotificationRecord(
            key: "current.local",
            createdAt: referenceDate,
            updatedAt: referenceDate,
            title: "Current",
            body: "Current",
            kind: .budgetWarning,
            source: .localReminder,
            recipientUserID: currentUserID
        )
        let otherLocal = AppNotificationRecord(
            key: "other.local",
            createdAt: referenceDate,
            updatedAt: referenceDate,
            title: "Other",
            body: "Other",
            kind: .budgetWarning,
            source: .localReminder,
            recipientUserID: otherUserID
        )
        let legacyUnscopedSystem = AppNotificationRecord(
            key: "legacy.system",
            createdAt: referenceDate,
            updatedAt: referenceDate,
            title: "Legacy",
            body: "Legacy",
            kind: .lowWallet,
            source: .system
        )
        let currentSystem = AppNotificationRecord(
            key: "current.system",
            createdAt: referenceDate,
            updatedAt: referenceDate,
            title: "System",
            body: "System",
            kind: .lowWallet,
            source: .system,
            recipientUserID: currentUserID
        )
        let familyForOther = AppNotificationRecord(
            key: "family.other",
            createdAt: referenceDate,
            updatedAt: referenceDate,
            title: "Family",
            body: "Family",
            kind: .permissionRequestApproved,
            source: .family,
            recipientUserID: otherUserID
        )

        let rows = [currentLocal, otherLocal, legacyUnscopedSystem, currentSystem, familyForOther]

        XCTAssertEqual(
            MistiaNotificationStore.visibleRows(rows, userID: currentUserID, referenceDate: referenceDate).map(\.key),
            ["current.local", "current.system"]
        )
        XCTAssertEqual(
            MistiaNotificationStore.visibleRows(rows, userID: otherUserID, referenceDate: referenceDate).map(\.key),
            ["other.local", "family.other"]
        )
    }

    func testFamilyNotificationDecodesLegacyMixedTypeMetadata() throws {
        let notificationID = UUID()
        let familyID = UUID()
        let recipientUserID = UUID()
        let actorUserID = UUID()
        let transactionID = UUID()
        let sourceWalletID = UUID()
        let destinationWalletID = UUID()
        let json = """
        {
          "id": "\(notificationID.uuidString)",
          "source_event_key": "family-transfer:\(transactionID.uuidString.lowercased())",
          "family_id": "\(familyID.uuidString)",
          "user_id": "\(recipientUserID.uuidString)",
          "actor_user_id": "\(actorUserID.uuidString)",
          "kind": "family_activity",
          "resource_type": "transaction",
          "resource_id": "\(transactionID.uuidString)",
          "permission_scope": null,
          "permission_request_id": null,
          "action_state": "informational",
          "title": "Nhận tiền",
          "body": "Transfer received",
          "metadata": {
            "action": "family_transfer",
            "sender_transaction_id": "\(transactionID.uuidString.lowercased())",
            "source_wallet_id": "\(sourceWalletID.uuidString.lowercased())",
            "destination_wallet_id": "\(destinationWalletID.uuidString.lowercased())",
            "amount_minor": 123456
          },
          "read_at": null,
          "created_at": "2026-05-24T12:00:00.000Z",
          "updated_at": "2026-05-24T12:00:00.000Z",
          "sync_version": 1
        }
        """

        let record = try JSONDecoder.mistiaRemoteAPIDecoder.decode(
            FamilyNotificationRemoteRecord.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(record.metadata?["action"], "family_transfer")
        XCTAssertEqual(record.metadata?["amount_minor"], "123456")
        XCTAssertEqual(record.metadata?["source_wallet_id"], sourceWalletID.uuidString.lowercased())
    }

    func testCreditCardStatementMaintenanceIgnoresFamilyMemberCards() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        await store.bootstrapIfNeeded()
        XCTAssertEqual(store.activeLocalProfileUserID, currentUserID)

        let defaults = UserDefaults.standard
        let changedKeys = [
            MistiaAppStorageKey.notificationsEnabled,
            MistiaAppStorageKey.notificationsGroupRemindersEnabled,
            MistiaAppStorageKey.notificationsReminderCreditCardsEnabled
        ]
        let previousValues = Dictionary(
            uniqueKeysWithValues: changedKeys.compactMap { key in
                defaults.object(forKey: key).map { (key, $0) }
            }
        )
        changedKeys.forEach { defaults.set(true, forKey: $0) }
        defer {
            for key in changedKeys {
                if let previousValue = previousValues[key] {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let transactionDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 12)))
        let updatedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let memberCard = LedgerWallet(
            name: "Mercard",
            kind: .creditCard,
            iconSymbolName: "creditcard.fill",
            iconColorHex: "#E5484D",
            openingBalanceMinor: 0,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        let memberProfile = CreditCardProfile(
            issuerName: "Mercard",
            creditLimitMinor: 100_000,
            statementClosingDay: 10,
            paymentDueDay: 26,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            wallet: memberCard
        )
        memberCard.creditCardProfile = memberProfile
        let memberExpense = LedgerTransaction(
            primaryKind: .expense,
            title: "Member card charge",
            amountMinor: 32_456,
            occurredAt: transactionDate,
            createdAt: transactionDate,
            updatedAt: transactionDate,
            sourceWallet: memberCard
        )

        let context = store.currentModelContainer.mainContext
        context.insert(memberCard)
        context.insert(memberProfile)
        context.insert(memberExpense)
        context.insert(OwnedRecordScope(entity: .wallet, recordID: memberCard.id, ownerUserID: memberUserID, updatedAt: updatedAt))
        context.insert(OwnedRecordScope(entity: .creditCardProfile, recordID: memberProfile.id, ownerUserID: memberUserID, updatedAt: updatedAt))
        context.insert(OwnedRecordScope(entity: .transaction, recordID: memberExpense.id, ownerUserID: memberUserID, updatedAt: transactionDate))
        context.insert(AppNotificationRecord(
            key: "mistia.credit.statement.ready.\(memberCard.id.uuidString.lowercased()).2026-02",
            title: "Statement ready",
            body: "Mercard stale statement",
            kind: .creditCardStatementReady,
            source: .system,
            recipientUserID: currentUserID,
            resourceType: .card,
            resourceID: memberCard.id
        ))
        try context.save()

        await MistiaCreditCardStatementMaintenance.run(
            modelContext: context,
            sessionStore: store,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let rows = try context.fetch(FetchDescriptor<AppNotificationRecord>())
        XCTAssertFalse(rows.contains { $0.kind == .creditCardStatementReady })
        XCTAssertFalse(rows.contains { $0.body.localizedCaseInsensitiveContains("Mercard") })
    }

    func testCreditCardStatementMaintenanceReusesExistingAutoPaymentTransaction() async throws {
        let currentUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        await store.bootstrapIfNeeded()

        let calendar = Calendar(identifier: .gregorian)
        let statementMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let expenseDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 12)))
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9)))
        let seedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let paymentWallet = LedgerWallet(
            name: "Main",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#2F80ED",
            openingBalanceMinor: 100_000,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let cardWallet = LedgerWallet(
            name: "SMBC Card",
            kind: .creditCard,
            iconSymbolName: "creditcard.fill",
            iconColorHex: "#E5484D",
            openingBalanceMinor: 0,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let profile = CreditCardProfile(
            issuerName: "SMBC",
            creditLimitMinor: 200_000,
            statementClosingDay: 10,
            paymentDueDay: 26,
            autoPayEnabled: true,
            createdAt: seedDate,
            updatedAt: seedDate,
            wallet: cardWallet,
            paymentSourceWallet: paymentWallet
        )
        cardWallet.creditCardProfile = profile
        let charge = LedgerTransaction(
            primaryKind: .expense,
            title: "Card charge",
            amountMinor: 32_456,
            occurredAt: expenseDate,
            createdAt: expenseDate,
            updatedAt: expenseDate,
            sourceWallet: cardWallet
        )
        let existingPayment = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Auto payment for SMBC Card",
            amountMinor: 32_456,
            occurredAt: dueDate,
            createdAt: dueDate,
            updatedAt: dueDate,
            sourceWallet: paymentWallet,
            destinationWallet: cardWallet
        )
        let staleOccurrence = DueOccurrenceRecord(
            sourceKind: .creditCard,
            sourceID: cardWallet.id,
            selectedMonthKey: PlanningLogic.monthKey(for: statementMonth, calendar: calendar),
            scheduledDate: dueDate,
            amountMinorSnapshot: 32_456,
            status: .pending,
            createdAt: seedDate,
            updatedAt: seedDate
        )

        let context = store.currentModelContainer.mainContext
        [paymentWallet, cardWallet].forEach(context.insert)
        context.insert(profile)
        context.insert(charge)
        context.insert(existingPayment)
        context.insert(staleOccurrence)
        try context.save()

        await MistiaCreditCardStatementMaintenance.run(
            modelContext: context,
            sessionStore: store,
            referenceDate: dueDate,
            calendar: calendar
        )

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let autoPayments = transactions.filter {
            $0.primaryKind == .transfer
                && $0.transferSubtype == .internalTransfer
                && $0.sourceWallet?.id == paymentWallet.id
                && $0.destinationWallet?.id == cardWallet.id
                && $0.amountMinor == 32_456
                && calendar.isDate($0.occurredAt, inSameDayAs: dueDate)
        }
        XCTAssertEqual(autoPayments.count, 1)
        XCTAssertEqual(staleOccurrence.status, .paid)
        XCTAssertEqual(staleOccurrence.linkedTransactionID, existingPayment.id)
    }

    func testCreditCardStatementMaintenanceResetsPaidOccurrenceWhenLinkedPaymentWasDeleted() async throws {
        let currentUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        await store.bootstrapIfNeeded()

        let calendar = Calendar(identifier: .gregorian)
        let statementMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let expenseDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 12, hour: 12)))
        let paymentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9)))
        let deletedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 9)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12)))
        let seedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let paymentWallet = LedgerWallet(
            name: "Main",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#2F80ED",
            openingBalanceMinor: 100_000,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let cardWallet = LedgerWallet(
            name: "SMBC Card",
            kind: .creditCard,
            iconSymbolName: "creditcard.fill",
            iconColorHex: "#E5484D",
            openingBalanceMinor: 0,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let profile = CreditCardProfile(
            issuerName: "SMBC",
            creditLimitMinor: 200_000,
            statementClosingDay: 10,
            paymentDueDay: 26,
            autoPayEnabled: false,
            createdAt: seedDate,
            updatedAt: seedDate,
            wallet: cardWallet,
            paymentSourceWallet: paymentWallet
        )
        cardWallet.creditCardProfile = profile
        let charge = LedgerTransaction(
            primaryKind: .expense,
            title: "Card charge",
            amountMinor: 32_456,
            occurredAt: expenseDate,
            createdAt: expenseDate,
            updatedAt: expenseDate,
            sourceWallet: cardWallet
        )
        let deletedPayment = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Deleted card payment",
            amountMinor: 32_456,
            occurredAt: paymentDate,
            createdAt: paymentDate,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            sourceWallet: paymentWallet,
            destinationWallet: cardWallet
        )
        let paidOccurrence = DueOccurrenceRecord(
            sourceKind: .creditCard,
            sourceID: cardWallet.id,
            selectedMonthKey: PlanningLogic.monthKey(for: statementMonth, calendar: calendar),
            scheduledDate: paymentDate,
            amountMinorSnapshot: 32_456,
            status: .paid,
            paidAt: paymentDate,
            linkedTransactionID: deletedPayment.id,
            createdAt: seedDate,
            updatedAt: paymentDate
        )

        let context = store.currentModelContainer.mainContext
        [paymentWallet, cardWallet].forEach(context.insert)
        context.insert(profile)
        context.insert(charge)
        context.insert(deletedPayment)
        context.insert(paidOccurrence)
        context.insert(OwnedRecordScope(entity: .wallet, recordID: paymentWallet.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(OwnedRecordScope(entity: .wallet, recordID: cardWallet.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(OwnedRecordScope(entity: .creditCardProfile, recordID: profile.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(OwnedRecordScope(entity: .transaction, recordID: charge.id, ownerUserID: currentUserID, updatedAt: expenseDate))
        context.insert(OwnedRecordScope(entity: .transaction, recordID: deletedPayment.id, ownerUserID: currentUserID, updatedAt: deletedAt))
        context.insert(OwnedRecordScope(entity: .dueOccurrenceRecord, recordID: paidOccurrence.id, ownerUserID: currentUserID, updatedAt: paymentDate))
        try context.save()

        await MistiaCreditCardStatementMaintenance.run(
            modelContext: context,
            sessionStore: store,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(paidOccurrence.status, .pending)
        XCTAssertNil(paidOccurrence.paidAt)
        XCTAssertNil(paidOccurrence.linkedTransactionID)
    }

    func testCreditCardStatementMaintenanceLinksMemberCreatedManualPaymentWhenAutoPayIsDisabled() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        await store.bootstrapIfNeeded()

        let calendar = Calendar(identifier: .gregorian)
        let statementMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let expenseDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 12)))
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 26, hour: 9)))
        let paymentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        let seedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let paymentWallet = LedgerWallet(
            name: "Main",
            kind: .bank,
            iconSymbolName: "building.columns.fill",
            iconColorHex: "#2F80ED",
            openingBalanceMinor: 100_000,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let cardWallet = LedgerWallet(
            name: "SMBC Card",
            kind: .creditCard,
            iconSymbolName: "creditcard.fill",
            iconColorHex: "#E5484D",
            openingBalanceMinor: 0,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let profile = CreditCardProfile(
            issuerName: "SMBC",
            creditLimitMinor: 200_000,
            statementClosingDay: 10,
            paymentDueDay: 26,
            autoPayEnabled: false,
            createdAt: seedDate,
            updatedAt: seedDate,
            wallet: cardWallet,
            paymentSourceWallet: paymentWallet
        )
        cardWallet.creditCardProfile = profile
        let charge = LedgerTransaction(
            primaryKind: .expense,
            title: "Card charge",
            amountMinor: 44_298,
            occurredAt: expenseDate,
            createdAt: expenseDate,
            updatedAt: expenseDate,
            sourceWallet: cardWallet
        )
        let memberCreatedPayment = LedgerTransaction(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Manual card payment",
            amountMinor: 44_298,
            occurredAt: paymentDate,
            createdAt: paymentDate,
            updatedAt: paymentDate,
            sourceWallet: paymentWallet,
            destinationWallet: cardWallet
        )
        let pendingOccurrence = DueOccurrenceRecord(
            sourceKind: .creditCard,
            sourceID: cardWallet.id,
            selectedMonthKey: PlanningLogic.monthKey(for: statementMonth, calendar: calendar),
            scheduledDate: dueDate,
            amountMinorSnapshot: 44_298,
            status: .pending,
            createdAt: seedDate,
            updatedAt: seedDate
        )

        let context = store.currentModelContainer.mainContext
        [paymentWallet, cardWallet].forEach(context.insert)
        context.insert(profile)
        context.insert(charge)
        context.insert(memberCreatedPayment)
        context.insert(pendingOccurrence)
        context.insert(OwnedRecordScope(entity: .wallet, recordID: paymentWallet.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(OwnedRecordScope(entity: .wallet, recordID: cardWallet.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(OwnedRecordScope(entity: .creditCardProfile, recordID: profile.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(OwnedRecordScope(entity: .transaction, recordID: charge.id, ownerUserID: currentUserID, updatedAt: expenseDate))
        context.insert(OwnedRecordScope(entity: .transaction, recordID: memberCreatedPayment.id, ownerUserID: currentUserID, updatedAt: paymentDate))
        context.insert(OwnedRecordScope(entity: .dueOccurrenceRecord, recordID: pendingOccurrence.id, ownerUserID: currentUserID, updatedAt: seedDate))
        context.insert(TransactionAuditRecord(
            transactionID: memberCreatedPayment.id,
            createdByUserID: memberUserID,
            lastModifiedByUserID: memberUserID,
            updatedAt: paymentDate
        ))
        try context.save()

        await MistiaCreditCardStatementMaintenance.run(
            modelContext: context,
            sessionStore: store,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(pendingOccurrence.status, .paid)
        XCTAssertEqual(pendingOccurrence.linkedTransactionID, memberCreatedPayment.id)
        XCTAssertEqual(pendingOccurrence.paidAt, memberCreatedPayment.occurredAt)
    }

    func testRecurringBillMaintenanceIgnoresFamilyMemberBills() async throws {
        let currentUserID = UUID()
        let memberUserID = UUID()
        let session = makeSession(userID: currentUserID)
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        await store.bootstrapIfNeeded()
        XCTAssertEqual(store.activeLocalProfileUserID, currentUserID)

        let defaults = UserDefaults.standard
        let changedKeys = [
            MistiaAppStorageKey.notificationsEnabled,
            MistiaAppStorageKey.notificationsGroupRemindersEnabled,
            MistiaAppStorageKey.notificationsReminderBillsEnabled
        ]
        let previousValues = Dictionary(
            uniqueKeysWithValues: changedKeys.compactMap { key in
                defaults.object(forKey: key).map { (key, $0) }
            }
        )
        changedKeys.forEach { defaults.set(true, forKey: $0) }
        defer {
            for key in changedKeys {
                if let previousValue = previousValues[key] {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let updatedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let memberBill = RecurringBillPlan(
            name: "Member electricity",
            iconSymbolName: "bolt.fill",
            amountMinor: nil,
            dueDay: 5,
            paymentWallet: nil,
            currencyCode: "JPY",
            createdAt: updatedAt,
            updatedAt: updatedAt
        )

        let context = store.currentModelContainer.mainContext
        context.insert(memberBill)
        context.insert(OwnedRecordScope(entity: .recurringBillPlan, recordID: memberBill.id, ownerUserID: memberUserID, updatedAt: updatedAt))
        context.insert(AppNotificationRecord(
            key: "mistia.bill.payment.required.\(memberBill.id.uuidString.lowercased()).2026-03",
            title: "Bill due soon",
            body: "Member electricity stale bill",
            kind: .billPaymentRequired,
            source: .system,
            recipientUserID: currentUserID,
            resourceType: .bill,
            resourceID: memberBill.id
        ))
        try context.save()

        await MistiaRecurringBillMaintenance.run(
            modelContext: context,
            sessionStore: store,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let rows = try context.fetch(FetchDescriptor<AppNotificationRecord>())
        XCTAssertFalse(rows.contains { $0.kind == .billPaymentRequired })
        XCTAssertFalse(rows.contains { $0.kind == .billOverdue })
        XCTAssertFalse(rows.contains { $0.body.localizedCaseInsensitiveContains("Member electricity") })
    }

    func testRecurringBillAutoPayMarksDuplicateCycleOccurrencesPaid() async throws {
        let session = makeSession()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected
        )
        await store.bootstrapIfNeeded()

        let calendar = Calendar(identifier: .gregorian)
        let selectedMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let autoPayDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 12)))
        let seedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let monthKey = PlanningLogic.monthKey(for: selectedMonth, calendar: calendar)

        let paymentWallet = LedgerWallet(
            name: "Main",
            kind: .bank,
            iconSymbolName: LedgerWalletKind.bank.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.bank.defaultColorHex,
            openingBalanceMinor: 100_000,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let bill = RecurringBillPlan(
            name: "Internet",
            iconSymbolName: MistiaSystemCategoryKey.internet.iconSymbolName,
            amountMinor: 5_000,
            dueDay: 5,
            scheduleKind: .recurring,
            paymentStartDay: 5,
            firstScheduledMonth: selectedMonth,
            hasExplicitDueDate: false,
            autoPayEnabled: true,
            autoPayDay: nil,
            frequencyMonths: 1,
            paymentWallet: paymentWallet,
            currencyCode: "JPY",
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let firstOccurrence = DueOccurrenceRecord(
            sourceKind: .recurringBill,
            sourceID: bill.id,
            selectedMonthKey: monthKey,
            scheduledDate: autoPayDate,
            amountMinorSnapshot: 5_000,
            status: .pending,
            createdAt: seedDate,
            updatedAt: seedDate
        )
        let duplicateOccurrence = DueOccurrenceRecord(
            sourceKind: .recurringBill,
            sourceID: bill.id,
            selectedMonthKey: monthKey,
            scheduledDate: autoPayDate,
            amountMinorSnapshot: 5_000,
            status: .pending,
            createdAt: seedDate,
            updatedAt: seedDate
        )

        let context = store.currentModelContainer.mainContext
        context.insert(paymentWallet)
        context.insert(bill)
        context.insert(firstOccurrence)
        context.insert(duplicateOccurrence)
        try context.save()

        await MistiaRecurringBillMaintenance.run(
            modelContext: context,
            sessionStore: store,
            referenceDate: autoPayDate,
            calendar: calendar
        )

        let matchingOccurrences = try context.fetch(FetchDescriptor<DueOccurrenceRecord>())
            .filter {
                $0.sourceKind == .recurringBill
                    && $0.sourceID == bill.id
                    && $0.selectedMonthKey == monthKey
            }
        let autoPayments = try context.fetch(FetchDescriptor<LedgerTransaction>())
            .filter {
                $0.primaryKind == .expense
                    && $0.sourceWallet?.id == paymentWallet.id
                    && $0.amountMinor == 5_000
            }

        XCTAssertEqual(autoPayments.count, 1)
        XCTAssertEqual(matchingOccurrences.count, 2)
        XCTAssertTrue(matchingOccurrences.allSatisfy { $0.status == .paid })
        XCTAssertTrue(matchingOccurrences.allSatisfy { $0.linkedTransactionID == autoPayments.first?.id })
    }

    func testSignOutKeepsPreviousAccountAsEditableLocalProfile() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let accountDeviceStore = AccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .disconnected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()
        await store.signOut()

        XCTAssertFalse(store.isSignedIn)
        XCTAssertTrue(store.isGuestLocalModeActive)
        XCTAssertEqual(store.localModeProfileUserID, session.user.id)
        XCTAssertEqual(store.syncStatusTitle, "Local mode")
        XCTAssertTrue(store.syncStatusDetail.contains("same account"))
    }

    func testBootstrapRestoresLocalSessionWithoutWaitingForSlowAccountDeviceRefresh() async throws {
        let session = makeSession()
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let accountDeviceStore = BlockingFailingAccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.summary?.userID, session.user.id)
        XCTAssertEqual(authService.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(accountDeviceStore.registerCurrentDeviceCallCount, 0)
        XCTAssertEqual(accountDeviceStore.fetchDevicesCallCount, 0)

        await waitUntil("background account device validation starts") {
            accountDeviceStore.fetchCurrentDeviceCallCount == 1
        }
        accountDeviceStore.releaseFetchCurrentDeviceWithFailure()
        await waitUntil("background account device validation records failure") {
            store.accountDevicesErrorMessage != nil
        }
        XCTAssertTrue(store.isSignedIn)
    }

    func testBootstrapRegistersCurrentAccountDevice() async throws {
        let userID = UUID()
        let sessionID = UUID()
        let session = makeSession(
            userID: userID,
            accessToken: makeAccessToken(sessionID: sessionID)
        )
        let accountDeviceStore = AccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()

        await waitUntil("account device registration") {
            accountDeviceStore.registeredDevices.count == 1
        }
        XCTAssertEqual(accountDeviceStore.registeredDevices.first?.sessionID, sessionID)
        XCTAssertEqual(accountDeviceStore.registeredDevices.first?.userID, userID)
        XCTAssertEqual(store.accountDevices.first?.sessionID, sessionID)
    }

    func testSignOutMarksCurrentAccountDeviceSignedOut() async throws {
        let session = makeSession()
        let accountDeviceStore = AccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()
        await store.signOut()

        XCTAssertEqual(accountDeviceStore.signedOutDevices, [MistiaSyncDeviceIdentity.current()])
    }

    func testRemoteAccountDeviceSignOutRequestTriggersLocalSignOut() async throws {
        let session = makeSession()
        let accountDeviceStore = AccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()
        accountDeviceStore.requestRemoteSignOutForCurrentDevice()

        await store.checkForRemoteAccountDeviceSignOutIfNeeded()

        XCTAssertFalse(store.isSignedIn)
        XCTAssertEqual(accountDeviceStore.signedOutDevices, [MistiaSyncDeviceIdentity.current()])
    }

    func testBootstrapHonorsRemoteAccountDeviceSignOutBeforeRegisteringAgain() async throws {
        let session = makeSession()
        var remoteRequestedDevice = MistiaAccountDevice.current(session: session)
        remoteRequestedDevice.remoteSignOutRequestedAt = Date()
        let accountDeviceStore = AccountDeviceRegistrySpy()
        accountDeviceStore.stageCurrentDevice(remoteRequestedDevice)
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()

        await waitUntil("remote account device sign-out is processed after bootstrap") {
            !store.isSignedIn
        }
        XCTAssertTrue(accountDeviceStore.registeredDevices.isEmpty)
        XCTAssertEqual(accountDeviceStore.signedOutDevices, [MistiaSyncDeviceIdentity.current()])
    }

    func testForgetCurrentAccountDeviceHidesDeviceAndSignsOut() async throws {
        let session = makeSession()
        let accountDeviceStore = AccountDeviceRegistrySpy()
        let store = try makeSessionStore(
            authService: SessionAuthServiceSpy(persistedSession: session),
            userProfileStore: UserProfileStoreSpy(),
            networkStatus: .connected,
            accountDeviceStore: accountDeviceStore
        )

        await store.bootstrapIfNeeded()
        let currentDevice = try XCTUnwrap(store.accountDevices.first)

        await store.forgetAccountDevice(currentDevice)

        XCTAssertFalse(store.isSignedIn)
        XCTAssertTrue(store.accountDevices.isEmpty)
        XCTAssertTrue(accountDeviceStore.registeredDevices.isEmpty)
        XCTAssertEqual(accountDeviceStore.signedOutDevices, [MistiaSyncDeviceIdentity.current()])
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

    func testGuestUnboundSignInToExistingAccountPromptsToKeepDataSeparate() async throws {
        let userDefaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        let launchState = try MistiaDataStack.LaunchState(userDefaults: userDefaults)
        let guestProfileID = try XCTUnwrap(launchState.activeProfileDescriptor?.id)
        let existingSession = makeSession(
            userID: UUID(),
            email: "existing@example.com",
            displayName: "Existing User"
        )
        let authService = SessionAuthServiceSpy(
            persistedSession: nil,
            signInResult: SessionAuthResult(
                session: existingSession,
                origin: .existing
            )
        )
        let store = SessionStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            userDefaults: userDefaults,
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .connected),
            registerBackgroundRefresh: false
        )

        let wallet = LedgerWallet(
            name: "Guest wallet",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        launchState.modelContainer.mainContext.insert(wallet)
        try launchState.modelContainer.mainContext.save()

        await store.signIn(email: existingSession.user.email ?? "", password: "password")

        XCTAssertEqual(store.pendingAuthenticationPrompt?.kind, .keepOrDeleteGuestData)
        XCTAssertFalse(store.isSignedIn)
        XCTAssertEqual(launchState.activeProfileDescriptor?.id, guestProfileID)

        await store.resolvePendingAuthentication(.keepGuestDataSeparate)

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.summary?.userID, existingSession.user.id)
        XCTAssertEqual(launchState.activeProfileDescriptor?.kind, .cloudUser)
        XCTAssertEqual(launchState.activeProfileDescriptor?.cloudUserID, existingSession.user.id)
        XCTAssertNotNil(launchState.profileDescriptors.first(where: { $0.id == guestProfileID }))
    }

    func testGuestUnboundSignInWithUnknownAccountShowsAttachPromptAndCompletesLogin() async throws {
        let userDefaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        let launchState = try MistiaDataStack.LaunchState(userDefaults: userDefaults)
        let guestProfileID = try XCTUnwrap(launchState.activeProfileDescriptor?.id)
        let unknownSession = makeSession(
            userID: UUID(),
            email: "unknown@example.com",
            displayName: "Unknown User"
        )
        let authService = SessionAuthServiceSpy(
            persistedSession: nil,
            signInResult: SessionAuthResult(
                session: unknownSession,
                origin: .unknown
            )
        )
        let store = SessionStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            userDefaults: userDefaults,
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .connected),
            registerBackgroundRefresh: false
        )

        let wallet = LedgerWallet(
            name: "Guest wallet",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        launchState.modelContainer.mainContext.insert(wallet)
        try launchState.modelContainer.mainContext.save()

        await store.signIn(email: unknownSession.user.email ?? "", password: "password")

        XCTAssertEqual(store.pendingAuthenticationPrompt?.kind, .attachGuestData)
        XCTAssertFalse(store.isSignedIn)
        XCTAssertFalse(store.isAuthTransitioning)
        XCTAssertEqual(launchState.activeProfileDescriptor?.id, guestProfileID)
        XCTAssertEqual(launchState.activeProfileDescriptor?.kind, .guestUnbound)

        await store.resolvePendingAuthentication(.attachGuestData)

        XCTAssertTrue(store.isSignedIn)
        XCTAssertEqual(store.summary?.userID, unknownSession.user.id)
        XCTAssertEqual(launchState.activeProfileDescriptor?.id, guestProfileID)
        XCTAssertEqual(launchState.activeProfileDescriptor?.kind, .cloudUser)
        XCTAssertEqual(launchState.activeProfileDescriptor?.cloudUserID, unknownSession.user.id)
    }

    func testSignOutAndDeleteLocalDataReturnsToCleanGuestProfile() async throws {
        let session = makeSession(
            userID: UUID(),
            email: "owner@example.com",
            displayName: "Owner"
        )
        let userDefaults = UserDefaults(suiteName: "MistiaTests.\(UUID().uuidString)") ?? .standard
        let launchState = try MistiaDataStack.LaunchState(userDefaults: userDefaults)
        let authService = SessionAuthServiceSpy(persistedSession: session)
        let store = SessionStore(
            modelContainer: launchState.modelContainer,
            launchState: launchState,
            userDefaults: userDefaults,
            authService: authService,
            userProfileStore: UserProfileStoreSpy(),
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .disconnected),
            registerBackgroundRefresh: false
        )

        await store.bootstrapIfNeeded()
        let cloudProfileID = try XCTUnwrap(launchState.activeProfileDescriptor?.id)
        let wallet = LedgerWallet(
            name: "Cloud wallet",
            kind: .cash,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759"
        )
        store.currentModelContainer.mainContext.insert(wallet)
        try store.currentModelContainer.mainContext.save()

        await store.signOutAndDeleteLocalData()

        XCTAssertFalse(store.isSignedIn)
        XCTAssertTrue(store.isGuestUnboundModeActive)
        XCTAssertEqual(launchState.activeProfileDescriptor?.kind, .guestUnbound)
        XCTAssertNotEqual(launchState.activeProfileDescriptor?.id, cloudProfileID)
        XCTAssertNil(launchState.cloudProfileDescriptor(for: session.user.id))
        XCTAssertFalse((try launchState.hasMeaningfulUserData()))
    }

    private func makeSessionStore(
        authService: SessionAuthServiceSpy,
        userProfileStore: UserProfileStoreSpy,
        networkStatus: SessionNetworkStatus,
        modelContainer: ModelContainer? = nil,
        userDefaults: UserDefaults? = nil,
        syncCoordinator: SyncCoordinator? = nil,
        accountDeviceStore: (any AccountDeviceRegistryServicing)? = nil
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
            accountDeviceStore: accountDeviceStore,
            syncCoordinator: syncCoordinator,
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: networkStatus),
            registerBackgroundRefresh: false
        )
    }

    private func storeTestContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func clearProfileArtifacts() {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let profilesRootURL = applicationSupportURL.appendingPathComponent("profiles", isDirectory: true)
        try? FileManager.default.removeItem(at: profilesRootURL)
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

    private func makeAccessToken(sessionID: UUID) -> String {
        let data = try! JSONEncoder().encode(["session_id": sessionID.uuidString])
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private func makeFamilySnapshot(
        userID: UUID,
        ownerUserID: UUID? = nil,
        currentPolicy: FamilyPermissionPolicy? = nil,
        permissionGrants: [FamilyPermissionGrantRecord] = []
    ) -> FamilyStateSnapshot {
        let familyID = UUID()
        let membershipID = UUID()
        let resolvedOwnerUserID = ownerUserID ?? userID
        let now = Date()
        let currentRole: FamilyRole = resolvedOwnerUserID == userID ? .owner : .member
        let resolvedCurrentPolicy = currentPolicy ?? .preset(for: currentRole)
        var members = [
            FamilyMember(
                membershipID: membershipID,
                familyID: familyID,
                userID: userID,
                displayName: "Taylor Offline",
                avatarURL: nil,
                role: currentRole,
                policy: resolvedCurrentPolicy,
                isCurrentUser: true
            )
        ]
        if resolvedOwnerUserID != userID {
            members.insert(
                FamilyMember(
                    membershipID: UUID(),
                    familyID: familyID,
                    userID: resolvedOwnerUserID,
                    displayName: "Owner",
                    avatarURL: nil,
                    role: .owner,
                    policy: .preset(for: .owner),
                    isCurrentUser: false
                ),
                at: 0
            )
        }

        return FamilyStateSnapshot(
            family: FamilyGroupRecord(
                id: familyID,
                name: "Offline Family",
                ownerUserID: resolvedOwnerUserID,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            currentMembership: FamilyMembershipRecord(
                id: membershipID,
                familyID: familyID,
                userID: userID,
                roleRawValue: currentRole.rawValue,
                canViewFamilyDashboard: resolvedCurrentPolicy.canViewFamilyDashboard,
                canViewOthers: resolvedCurrentPolicy.canViewOthers,
                canEditOthers: resolvedCurrentPolicy.canEditOthers,
                canViewWallets: resolvedCurrentPolicy.canViewWallets,
                canViewDebts: resolvedCurrentPolicy.canViewDebts,
                canViewKids: resolvedCurrentPolicy.canViewKids,
                canEditKids: resolvedCurrentPolicy.canEditKids,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            members: members,
            invites: [],
            permissionGrants: permissionGrants
        )
    }

    private func makePermissionGrant(
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        revokedAt: Date? = nil
    ) -> FamilyPermissionGrantRecord {
        let now = Date()
        return FamilyPermissionGrantRecord(
            id: UUID(),
            familyID: UUID(),
            granteeUserID: granteeUserID,
            ownerUserID: ownerUserID,
            resourceTypeRawValue: resourceType.rawValue,
            resourceID: resourceID,
            permissionScopeRawValue: scope.rawValue,
            grantedByUserID: ownerUserID,
            createdAt: now,
            updatedAt: now,
            revokedAt: revokedAt
        )
    }

    private func remoteWallet(
        id: UUID,
        userID: UUID,
        name: String,
        syncVersion: Int64
    ) -> RemoteLedgerWallet {
        RemoteLedgerWallet(
            userID: userID,
            id: id,
            name: name,
            kindRawValue: LedgerWalletKind.cash.rawValue,
            iconSymbolName: "banknote",
            iconColorHex: "#34C759",
            currencyCode: "JPY",
            openingBalanceMinor: 0,
            institutionDisplayName: nil,
            institutionPresetKey: nil,
            sortOrder: 0,
            isArchived: false,
            archivedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            syncVersion: syncVersion,
            lastModifiedByDeviceID: UUID()
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
    private let signInResult: SessionAuthResult?
    private let googleSignInResult: SessionAuthResult?

    private(set) var loadPersistedSessionCallCount = 0
    private(set) var refreshSessionCallCount = 0
    private(set) var clearPersistedSessionCallCount = 0
    private(set) var persistSessionCallCount = 0

    init(
        persistedSession: SupabaseAuthSession?,
        refreshResult: Result<SupabaseAuthSession, Error>? = nil,
        signInResult: SessionAuthResult? = nil,
        googleSignInResult: SessionAuthResult? = nil
    ) {
        self.persistedSession = persistedSession
        self.refreshResult = refreshResult
            ?? persistedSession.map { .success($0) }
            ?? .failure(SessionRemoteAccessError.offline)
        self.signInResult = signInResult
        self.googleSignInResult = googleSignInResult
    }

    func loadPersistedSession() throws -> SupabaseAuthSession? {
        loadPersistedSessionCallCount += 1
        return persistedSession
    }

    func restoreSession() async throws -> SupabaseAuthSession? {
        persistedSession
    }

    func persistSession(_ session: SupabaseAuthSession) throws {
        persistSessionCallCount += 1
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
    ) async throws -> SessionAuthResult {
        guard let signInResult else {
            fatalError("Unused in tests")
        }
        return signInResult
    }

    func signInWithGoogle() async throws -> SessionAuthResult {
        guard let googleSignInResult else {
            fatalError("Unused in tests")
        }
        return googleSignInResult
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
private final class BlockingFailingAccountDeviceRegistrySpy: AccountDeviceRegistryServicing {
    private(set) var registerCurrentDeviceCallCount = 0
    private(set) var fetchDevicesCallCount = 0
    private(set) var fetchCurrentDeviceCallCount = 0
    private var fetchCurrentDeviceContinuation: CheckedContinuation<MistiaAccountDevice?, Error>?

    func releaseFetchCurrentDeviceWithFailure() {
        fetchCurrentDeviceContinuation?.resume(throwing: SessionRemoteAccessError.offline)
        fetchCurrentDeviceContinuation = nil
    }

    func registerCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice {
        registerCurrentDeviceCallCount += 1
        throw SessionRemoteAccessError.offline
    }

    func fetchDevices(session: SupabaseAuthSession) async throws -> [MistiaAccountDevice] {
        fetchDevicesCallCount += 1
        throw SessionRemoteAccessError.offline
    }

    func fetchCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice? {
        fetchCurrentDeviceCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            fetchCurrentDeviceContinuation = continuation
        }
    }

    func requestSignOut(deviceID: UUID, session: SupabaseAuthSession) async throws -> MistiaAccountDevice {
        throw SessionRemoteAccessError.offline
    }

    func forgetDevice(deviceID: UUID, session: SupabaseAuthSession) async throws {
        throw SessionRemoteAccessError.offline
    }

    func markCurrentDeviceSignedOut(session: SupabaseAuthSession?) async throws {
        throw SessionRemoteAccessError.offline
    }
}

@MainActor
private final class AccountDeviceRegistrySpy: AccountDeviceRegistryServicing {
    private(set) var registeredDevices: [MistiaAccountDevice] = []
    private(set) var signedOutDevices: [UUID] = []
    private var stagedCurrentDevice: MistiaAccountDevice?

    func stageCurrentDevice(_ device: MistiaAccountDevice) {
        stagedCurrentDevice = device
    }

    func requestRemoteSignOutForCurrentDevice() {
        guard let index = registeredDevices.lastIndex(where: { $0.deviceID == MistiaSyncDeviceIdentity.current() }) else {
            return
        }
        registeredDevices[index].remoteSignOutRequestedAt = Date()
    }

    func registerCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice {
        let device = MistiaAccountDevice.current(session: session)
        stagedCurrentDevice = nil
        registeredDevices.append(device)
        return device
    }

    func fetchDevices(session: SupabaseAuthSession) async throws -> [MistiaAccountDevice] {
        registeredDevices
    }

    func fetchCurrentDevice(session: SupabaseAuthSession) async throws -> MistiaAccountDevice? {
        stagedCurrentDevice ?? registeredDevices.last
    }

    func requestSignOut(deviceID: UUID, session: SupabaseAuthSession) async throws -> MistiaAccountDevice {
        var device = registeredDevices.first { $0.deviceID == deviceID }
            ?? MistiaAccountDevice.current(session: session)
        device.remoteSignOutRequestedAt = Date()
        return device
    }

    func forgetDevice(deviceID: UUID, session: SupabaseAuthSession) async throws {
        registeredDevices.removeAll { $0.deviceID == deviceID }
    }

    func markCurrentDeviceSignedOut(session: SupabaseAuthSession?) async throws {
        signedOutDevices.append(MistiaSyncDeviceIdentity.current())
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
private final class SessionSyncRemoteStoreSpy: MistiaRemoteStore {
    private(set) var fetchSnapshotSubjectUserIDs: [UUID?] = []
    private(set) var createdSubjectUserIDs: [UUID] = []
    var fetchRecordResult: MistiaSyncUploadRecord?

    var fetchSnapshotCallCount: Int {
        fetchSnapshotSubjectUserIDs.count
    }

    var createCallCount: Int {
        createdSubjectUserIDs.count
    }

    func fetchSnapshot(session: SupabaseAuthSession, subjectUserID: UUID?) async throws -> MistiaRemoteSnapshot {
        fetchSnapshotSubjectUserIDs.append(subjectUserID)
        return .empty
    }

    func fetchRecord(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        fetchRecordResult
    }

    func create(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        createdSubjectUserIDs.append(subjectUserID)
        return record
    }

    func conditionalUpdate(
        _ record: MistiaSyncUploadRecord,
        expectedVersion: Int64,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        nil
    }

    func conditionalDelete(
        entity: MistiaSyncEntity,
        recordID: UUID,
        subjectUserID: UUID,
        expectedVersion: Int64,
        modifiedAt: Date,
        deviceID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord? {
        nil
    }

    func forceUpsert(
        _ record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        record
    }

    func createFamilyActivityNotification(
        _ event: RemoteFamilyActivityNotificationEvent,
        session: SupabaseAuthSession
    ) async throws {
        // no-op
    }
}

@MainActor
private final class FamilyRemoteServiceSpy: FamilyRemoteServicing {
    private var snapshot: FamilyStateSnapshot

    private(set) var fetchStateCallCount = 0
    private(set) var createPermissionRequestCallCount = 0
    private(set) var accessibleFinanceUserIDBatches: [[UUID]] = []
    var fetchStateDelayNanoseconds: UInt64?
    var fetchFinanceDelayNanoseconds: UInt64?
    var fetchStateError: Error?

    init(snapshot: FamilyStateSnapshot) {
        self.snapshot = snapshot
    }

    func setSnapshot(_ snapshot: FamilyStateSnapshot) {
        self.snapshot = snapshot
    }

    func fetchState(session: SupabaseAuthSession) async throws -> FamilyStateSnapshot {
        fetchStateCallCount += 1
        if let fetchStateDelayNanoseconds {
            try? await Task.sleep(nanoseconds: fetchStateDelayNanoseconds)
        }
        if let fetchStateError {
            throw fetchStateError
        }
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

    func removeMember(
        membershipID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        fatalError("Unused in tests")
    }

    func transferOwner(
        familyID: UUID,
        newOwnerMembershipID: UUID,
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
        accessibleFinanceUserIDBatches.append(userIDs)
        if let fetchFinanceDelayNanoseconds {
            try await Task.sleep(nanoseconds: fetchFinanceDelayNanoseconds)
        }
        return .empty
    }

    func createFamilyPermissionRequest(
        input: FamilyPermissionRequestInput,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord {
        createPermissionRequestCallCount += 1
        let now = Date()
        return FamilyPermissionRequestRemoteRecord(
            id: UUID(),
            familyID: input.familyID,
            requesterUserID: session.user.id,
            recipientUserID: input.recipientUserID,
            resourceTypeRawValue: input.resourceType.rawValue,
            resourceID: input.resourceID,
            permissionScopeRawValue: input.permissionScope.rawValue,
            statusRawValue: "pending",
            message: input.message,
            respondedByUserID: nil,
            respondedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

private extension FamilyStateSnapshot {
    static let empty = FamilyStateSnapshot(
        family: nil,
        currentMembership: nil,
        members: [],
        invites: [],
        permissionGrants: []
    )
}
