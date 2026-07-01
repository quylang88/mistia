import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class FamilyPermissionResolutionTests: XCTestCase {
    func testPendingBillEditRequestRefreshesApprovedGrantBeforePrompting() async throws {
        let currentUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let ownerUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let familyID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        let billID = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
        let requestID = UUID(uuidString: "10000000-0000-4000-8000-000000000005")!

        let pendingRequest = makePermissionRequest(
            id: requestID,
            familyID: familyID,
            requesterUserID: currentUserID,
            recipientUserID: ownerUserID,
            resourceType: .bill,
            resourceID: billID,
            scope: .edit,
            status: "pending"
        )
        let approvedGrant = makePermissionGrant(
            familyID: familyID,
            granteeUserID: currentUserID,
            ownerUserID: ownerUserID,
            resourceType: .bill,
            resourceID: billID,
            scope: .edit
        )
        let service = PermissionResolutionServiceStub(
            snapshots: [
                makeFamilySnapshot(
                    familyID: familyID,
                    currentUserID: currentUserID,
                    ownerUserID: ownerUserID,
                    pendingPermissionRequests: [pendingRequest]
                ),
                makeFamilySnapshot(
                    familyID: familyID,
                    currentUserID: currentUserID,
                    ownerUserID: ownerUserID,
                    permissionGrants: [approvedGrant]
                )
            ]
        )
        let container = try makeContainer()
        let sessionStore = makeSessionStore(container: container, userID: currentUserID)
        await sessionStore.bootstrapIfNeeded()
        let familyContextStore = FamilyContextStore(
            modelContainer: container,
            service: service
        )

        await familyContextStore.refresh(sessionStore: sessionStore)
        XCTAssertTrue(
            familyContextStore.hasPendingPermissionRequest(
                ownerUserID: ownerUserID,
                resourceType: .bill,
                resourceID: billID,
                scope: .edit
            )
        )
        XCTAssertFalse(
            familyContextStore.canEdit(
                ownerUserID: ownerUserID,
                resourceType: .bill,
                resourceID: billID
            )
        )

        let didResolve = await familyContextStore.resolvePendingPermissionBeforePrompt(
            ownerUserID: ownerUserID,
            resourceType: .bill,
            resourceID: billID,
            scope: .edit,
            sessionStore: sessionStore
        )

        XCTAssertTrue(didResolve)
        XCTAssertEqual(service.fetchStateCallCount, 2)
        XCTAssertTrue(
            familyContextStore.canEdit(
                ownerUserID: ownerUserID,
                resourceType: .bill,
                resourceID: billID
            )
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: MistiaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSessionStore(container: ModelContainer, userID: UUID) -> SessionStore {
        let session = SupabaseAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "bearer",
            expiresAt: .now.addingTimeInterval(3600),
            user: SupabaseAuthUser(
                id: userID,
                email: "member@example.com",
                userMetadata: SupabaseUserMetadata(
                    displayName: "Member",
                    fullName: nil,
                    name: nil,
                    avatarURL: nil,
                    picture: nil
                )
            )
        )
        return SessionStore(
            modelContainer: container,
            userDefaults: UserDefaults(suiteName: "MistiaPermissionResolutionTests.\(UUID().uuidString)") ?? .standard,
            authService: PermissionResolutionAuthServiceStub(session: session),
            userProfileStore: PermissionResolutionProfileStoreStub(),
            connectivityMonitor: SessionConnectivityMonitor(initialStatus: .connected),
            registerBackgroundRefresh: false
        )
    }

    private func makeFamilySnapshot(
        familyID: UUID,
        currentUserID: UUID,
        ownerUserID: UUID,
        permissionGrants: [FamilyPermissionGrantRecord] = [],
        pendingPermissionRequests: [FamilyPermissionRequestRemoteRecord] = []
    ) -> FamilyStateSnapshot {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let memberPolicy = FamilyPermissionPolicy.preset(for: .member)
        let ownerPolicy = FamilyPermissionPolicy.preset(for: .owner)
        return FamilyStateSnapshot(
            family: FamilyGroupRecord(
                id: familyID,
                name: "Family",
                ownerUserID: ownerUserID,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            currentMembership: FamilyMembershipRecord(
                id: UUID(),
                familyID: familyID,
                userID: currentUserID,
                roleRawValue: FamilyRole.member.rawValue,
                canViewFamilyDashboard: memberPolicy.canViewFamilyDashboard,
                canViewOthers: memberPolicy.canViewOthers,
                canEditOthers: memberPolicy.canEditOthers,
                canViewWallets: memberPolicy.canViewWallets,
                canViewDebts: memberPolicy.canViewDebts,
                canViewKids: memberPolicy.canViewKids,
                canEditKids: memberPolicy.canEditKids,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now
            ),
            members: [
                FamilyMember(
                    membershipID: UUID(),
                    familyID: familyID,
                    userID: ownerUserID,
                    displayName: "Owner",
                    avatarURL: nil,
                    role: .owner,
                    policy: ownerPolicy,
                    isCurrentUser: false
                ),
                FamilyMember(
                    membershipID: UUID(),
                    familyID: familyID,
                    userID: currentUserID,
                    displayName: "Member",
                    avatarURL: nil,
                    role: .member,
                    policy: memberPolicy,
                    isCurrentUser: true
                )
            ],
            invites: [],
            permissionGrants: permissionGrants,
            pendingPermissionRequests: pendingPermissionRequests
        )
    }

    private func makePermissionRequest(
        id: UUID,
        familyID: UUID,
        requesterUserID: UUID,
        recipientUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        status: String
    ) -> FamilyPermissionRequestRemoteRecord {
        let now = Date(timeIntervalSince1970: 1_770_000_100)
        return FamilyPermissionRequestRemoteRecord(
            id: id,
            familyID: familyID,
            requesterUserID: requesterUserID,
            recipientUserID: recipientUserID,
            resourceTypeRawValue: resourceType.rawValue,
            resourceID: resourceID,
            permissionScopeRawValue: scope.rawValue,
            statusRawValue: status,
            message: nil,
            respondedByUserID: nil,
            respondedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makePermissionGrant(
        familyID: UUID,
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope
    ) -> FamilyPermissionGrantRecord {
        let now = Date(timeIntervalSince1970: 1_770_000_200)
        return FamilyPermissionGrantRecord(
            id: UUID(),
            familyID: familyID,
            granteeUserID: granteeUserID,
            ownerUserID: ownerUserID,
            resourceTypeRawValue: resourceType.rawValue,
            resourceID: resourceID,
            permissionScopeRawValue: scope.rawValue,
            grantedByUserID: ownerUserID,
            createdAt: now,
            updatedAt: now,
            revokedAt: nil
        )
    }
}

@MainActor
private final class PermissionResolutionServiceStub: FamilyRemoteServicing {
    private var snapshots: [FamilyStateSnapshot]
    private(set) var fetchStateCallCount = 0

    init(snapshots: [FamilyStateSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchState(session: SupabaseAuthSession) async throws -> FamilyStateSnapshot {
        fetchStateCallCount += 1
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }
        return snapshots.first ?? FamilyStateSnapshot(
            family: nil,
            currentMembership: nil,
            members: [],
            invites: []
        )
    }

    func createFamily(name: String, session: SupabaseAuthSession) async throws -> FamilyStateSnapshot {
        throw SupabaseServiceError.serverMessage("Unused in tests")
    }

    func joinInvite(code: String, session: SupabaseAuthSession) async throws -> FamilyStateSnapshot {
        throw SupabaseServiceError.serverMessage("Unused in tests")
    }

    func createInvite(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        throw SupabaseServiceError.serverMessage("Unused in tests")
    }

    func updateMember(
        membershipID: UUID,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        session: SupabaseAuthSession
    ) async throws {}

    func removeMember(membershipID: UUID, session: SupabaseAuthSession) async throws {}

    func transferOwner(
        familyID: UUID,
        newOwnerMembershipID: UUID,
        session: SupabaseAuthSession
    ) async throws {}

    func deleteFamily(familyID: UUID, session: SupabaseAuthSession) async throws {}

    func fetchAccessibleFinanceSnapshot(
        userIDs: [UUID],
        session: SupabaseAuthSession
    ) async throws -> MistiaRemoteSnapshot {
        .empty
    }
}

private final class PermissionResolutionAuthServiceStub: SessionAuthServicing {
    private let session: SupabaseAuthSession

    init(session: SupabaseAuthSession) {
        self.session = session
    }

    func loadPersistedSession() throws -> SupabaseAuthSession? { session }
    func restoreSession() async throws -> SupabaseAuthSession? { session }
    func persistSession(_ session: SupabaseAuthSession) throws {}
    func signUp(email: String, password: String, displayName: String) async throws -> SupabaseSignUpOutcome {
        throw SupabaseServiceError.serverMessage("Unused in tests")
    }
    func signIn(email: String, password: String) async throws -> SessionAuthResult {
        throw SupabaseServiceError.serverMessage("Unused in tests")
    }
    @MainActor
    func signInWithGoogle() async throws -> SessionAuthResult {
        throw SupabaseServiceError.serverMessage("Unused in tests")
    }
    func refreshSessionIfNeeded(_ session: SupabaseAuthSession) async throws -> SupabaseAuthSession { session }
    func signOut(session: SupabaseAuthSession?) async throws {}
    func deleteAccount(session: SupabaseAuthSession) async throws {}
    func requestPasswordReset(email: String) async throws {}
    func resendConfirmation(email: String) async throws {}
    func clearPersistedSession() throws {}
}

private final class PermissionResolutionProfileStoreStub: UserProfileRemoteStoring {
    func fetchProfile(session: SupabaseAuthSession) async throws -> RemoteUserProfile? { nil }
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
    func uploadAvatarImageData(_ data: Data, session: SupabaseAuthSession) async throws -> URL {
        URL(string: "https://example.com/avatar.jpg")!
    }
}
