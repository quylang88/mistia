import Foundation

@MainActor
protocol FamilyRemoteServicing {
    func fetchState(session: SupabaseAuthSession) async throws -> FamilyStateSnapshot
    func createFamily(
        name: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot
    func joinInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot
    func previewInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInvitePreviewRecord
    func acceptInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot
    func declineInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord
    func createInvite(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord
    func revokeInvite(
        inviteID: UUID,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord
    func updateMember(
        membershipID: UUID,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        session: SupabaseAuthSession
    ) async throws
    func setPermissionGrant(
        familyID: UUID,
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        isGranted: Bool,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionGrantRecord
    func removeMember(
        membershipID: UUID,
        session: SupabaseAuthSession
    ) async throws
    func transferOwner(
        familyID: UUID,
        newOwnerMembershipID: UUID,
        session: SupabaseAuthSession
    ) async throws
    func deleteFamily(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws
    func fetchAccessibleFinanceSnapshot(
        userIDs: [UUID],
        session: SupabaseAuthSession
    ) async throws -> MistiaRemoteSnapshot
    func fetchFamilyNotifications(session: SupabaseAuthSession) async throws -> [FamilyNotificationRemoteRecord]
    func createFamilyPermissionRequest(
        input: FamilyPermissionRequestInput,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord
    func respondFamilyPermissionRequest(
        requestID: UUID,
        approve: Bool,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord
    func markFamilyNotificationsRead(
        ids: [UUID],
        session: SupabaseAuthSession
    ) async throws
}

extension FamilyRemoteServicing {
    func previewInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInvitePreviewRecord {
        throw SupabaseServiceError.serverMessage("Family invite links are unavailable.")
    }

    func acceptInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        try await joinInvite(code: token, session: session)
    }

    func declineInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        throw SupabaseServiceError.serverMessage("Family invite decline is unavailable.")
    }

    func revokeInvite(
        inviteID: UUID,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        throw SupabaseServiceError.serverMessage("Family invite revocation is unavailable.")
    }

    func fetchFamilyNotifications(session: SupabaseAuthSession) async throws -> [FamilyNotificationRemoteRecord] {
        []
    }

    func createFamilyPermissionRequest(
        input: FamilyPermissionRequestInput,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord {
        throw SupabaseServiceError.serverMessage("Family permission requests are unavailable.")
    }

    func respondFamilyPermissionRequest(
        requestID: UUID,
        approve: Bool,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord {
        throw SupabaseServiceError.serverMessage("Family permission responses are unavailable.")
    }

    func markFamilyNotificationsRead(
        ids: [UUID],
        session: SupabaseAuthSession
    ) async throws {}

    func setPermissionGrant(
        familyID: UUID,
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        isGranted: Bool,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionGrantRecord {
        throw SupabaseServiceError.serverMessage("Family permission grants are unavailable.")
    }
}

struct FamilyGroupRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let ownerUserID: UUID
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerUserID = "owner_user_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FamilyMembershipRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let familyID: UUID
    let userID: UUID
    var roleRawValue: String
    var canViewFamilyDashboard: Bool
    var canViewOthers: Bool
    var canEditOthers: Bool
    var canViewWallets: Bool
    var canViewDebts: Bool
    var canViewKids: Bool
    var canEditKids: Bool
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case userID = "user_id"
        case roleRawValue = "role"
        case canViewFamilyDashboard = "can_view_family_dashboard"
        case canViewOthers = "can_view_others"
        case canEditOthers = "can_edit_others"
        case canViewWallets = "can_view_wallets"
        case canViewDebts = "can_view_debts"
        case canViewKids = "can_view_kids"
        case canEditKids = "can_edit_kids"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var role: FamilyRole {
        FamilyRole(rawValue: roleRawValue) ?? .member
    }

    var policy: FamilyPermissionPolicy {
        FamilyPermissionPolicy(
            canViewFamilyDashboard: canViewFamilyDashboard,
            canViewOthers: canViewOthers,
            canEditOthers: canEditOthers,
            canViewWallets: canViewWallets,
            canViewDebts: canViewDebts,
            canViewKids: canViewKids,
            canEditKids: canEditKids
        )
    }
}

struct FamilyInviteRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let familyID: UUID
    let code: String
    let token: String?
    let createdByUserID: UUID
    var defaultRoleRawValue: String
    let expiresAt: Date
    let acceptedAt: Date?
    let acceptedByUserID: UUID?
    let declinedAt: Date?
    let declinedByUserID: UUID?
    let revokedAt: Date?
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case code
        case token
        case createdByUserID = "created_by_user_id"
        case defaultRoleRawValue = "default_role"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case acceptedByUserID = "accepted_by_user_id"
        case declinedAt = "declined_at"
        case declinedByUserID = "declined_by_user_id"
        case revokedAt = "revoked_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var defaultRole: FamilyRole {
        FamilyRole(rawValue: defaultRoleRawValue) ?? .member
    }

    var status: FamilyInviteStatus {
        if deletedAt != nil {
            return .invalid
        }
        if acceptedAt != nil {
            return .accepted
        }
        if declinedAt != nil {
            return .declined
        }
        if revokedAt != nil {
            return .revoked
        }
        if expiresAt < .now {
            return .expired
        }
        return .pending
    }
}

struct FamilyUserProfileRecord: Codable, Identifiable, Equatable {
    let userID: UUID
    var displayName: String
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }

    var id: UUID { userID }
}

struct FamilySyncStatusRecord: Codable, Equatable {
    let userID: UUID
    let hasSyncedCloudData: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case hasSyncedCloudData = "has_synced_cloud_data"
    }
}

struct FamilyPermissionGrantRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let familyID: UUID
    let granteeUserID: UUID
    let ownerUserID: UUID
    let resourceTypeRawValue: String
    let resourceID: UUID?
    let permissionScopeRawValue: String
    let grantedByUserID: UUID
    let createdAt: Date
    let updatedAt: Date
    let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case granteeUserID = "grantee_user_id"
        case ownerUserID = "owner_user_id"
        case resourceTypeRawValue = "resource_type"
        case resourceID = "resource_id"
        case permissionScopeRawValue = "permission_scope"
        case grantedByUserID = "granted_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revokedAt = "revoked_at"
    }

    var resourceType: MistiaFamilyNotificationResourceType? {
        MistiaFamilyNotificationResourceType(rawValue: resourceTypeRawValue)
    }

    var permissionScope: MistiaFamilyPermissionScope? {
        MistiaFamilyPermissionScope(rawValue: permissionScopeRawValue)
    }

    var isActive: Bool {
        revokedAt == nil
    }
}

struct FamilyMember: Codable, Identifiable, Equatable {
    let membershipID: UUID
    let familyID: UUID
    let userID: UUID
    var displayName: String
    var avatarURL: URL?
    var hasSyncedCloudData: Bool = false
    var role: FamilyRole
    var policy: FamilyPermissionPolicy
    var isCurrentUser: Bool

    var id: UUID { membershipID }
}

struct FamilyInvitePreview: Codable, Equatable {
    let invite: FamilyInviteRecord
    let family: FamilyGroupRecord
}

struct FamilyInvitePreviewRecord: Codable, Equatable {
    let inviteID: UUID
    let familyID: UUID
    let familyName: String
    let inviterUserID: UUID
    let inviterName: String
    let roleRawValue: String
    let expiresAt: Date
    let createdAt: Date
    let acceptedByUserID: UUID?
    let statusRawValue: String
    let alreadyMemberOfFamily: Bool
    let belongsToAnotherFamily: Bool

    enum CodingKeys: String, CodingKey {
        case inviteID = "invite_id"
        case familyID = "family_id"
        case familyName = "family_name"
        case inviterUserID = "inviter_user_id"
        case inviterName = "inviter_name"
        case roleRawValue = "role"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case acceptedByUserID = "accepted_by_user_id"
        case statusRawValue = "status"
        case alreadyMemberOfFamily = "already_member_of_family"
        case belongsToAnotherFamily = "belongs_to_another_family"
    }

    var role: FamilyRole {
        FamilyRole(rawValue: roleRawValue) ?? .member
    }

    var status: FamilyInviteStatus {
        FamilyInviteStatus(rawValue: statusRawValue) ?? .invalid
    }
}

struct FamilyStateSnapshot: Codable, Equatable {
    var family: FamilyGroupRecord?
    var currentMembership: FamilyMembershipRecord?
    var members: [FamilyMember]
    var invites: [FamilyInviteRecord]
    var permissionGrants: [FamilyPermissionGrantRecord] = []

    enum CodingKeys: String, CodingKey {
        case family
        case currentMembership
        case members
        case invites
        case permissionGrants
    }

    init(
        family: FamilyGroupRecord?,
        currentMembership: FamilyMembershipRecord?,
        members: [FamilyMember],
        invites: [FamilyInviteRecord],
        permissionGrants: [FamilyPermissionGrantRecord] = []
    ) {
        self.family = family
        self.currentMembership = currentMembership
        self.members = members
        self.invites = invites
        self.permissionGrants = permissionGrants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decodeIfPresent(FamilyGroupRecord.self, forKey: .family)
        currentMembership = try container.decodeIfPresent(FamilyMembershipRecord.self, forKey: .currentMembership)
        members = try container.decodeIfPresent([FamilyMember].self, forKey: .members) ?? []
        invites = try container.decodeIfPresent([FamilyInviteRecord].self, forKey: .invites) ?? []
        permissionGrants = try container.decodeIfPresent([FamilyPermissionGrantRecord].self, forKey: .permissionGrants) ?? []
    }
}

@MainActor
struct FamilyRemoteService: FamilyRemoteServicing {
    private let configurationProvider: () -> MistiaSyncConfiguration?
    private let decoder = JSONDecoder.mistiaRemoteAPIDecoder
    private let encoder = JSONEncoder.mistiaRemoteAPIEncoder

    init(configurationProvider: @escaping () -> MistiaSyncConfiguration? = { MistiaSyncConfiguration.load() }) {
        self.configurationProvider = configurationProvider
    }

    func fetchState(session: SupabaseAuthSession) async throws -> FamilyStateSnapshot {
        let currentMembership = try await fetchCurrentMembership(session: session)
        guard let currentMembership else {
            return FamilyStateSnapshot(
                family: nil,
                currentMembership: nil,
                members: [],
                invites: [],
                permissionGrants: []
            )
        }

        async let family = fetchFamily(id: currentMembership.familyID, session: session)
        async let membershipRowsTask = fetchMemberships(familyID: currentMembership.familyID, session: session)
        async let invitesTask: [FamilyInviteRecord] = currentMembership.role == .owner
            ? fetchInvites(familyID: currentMembership.familyID, session: session)
            : []
        async let permissionGrantsTask = fetchPermissionGrants(
            familyID: currentMembership.familyID,
            session: session,
            userID: currentMembership.role == .owner ? nil : session.user.id
        )
        async let syncStatusRowsTask = fetchCloudSyncStatuses(
            familyID: currentMembership.familyID,
            session: session
        )

        let membershipRows = try await membershipRowsTask
        let profileRows = try await fetchProfiles(
            userIDs: membershipRows.map(\.userID),
            session: session
        )
        let syncStatusRows = (try? await syncStatusRowsTask) ?? []
        let profileByUserID = Dictionary(profileRows.map { ($0.userID, $0) }, uniquingKeysWith: { _, latest in latest })
        let hasSyncedCloudDataByUserID = Dictionary(
            syncStatusRows.map { ($0.userID, $0.hasSyncedCloudData) },
            uniquingKeysWith: { lhs, rhs in lhs || rhs }
        )
        let members = membershipRows.map { row in
            let profile = profileByUserID[row.userID]
            return FamilyMember(
                membershipID: row.id,
                familyID: row.familyID,
                userID: row.userID,
                displayName: profile?.displayName ?? "Mistia",
                avatarURL: profile?.avatarURL.flatMap(URL.init(string:)),
                hasSyncedCloudData: hasSyncedCloudDataByUserID[row.userID] ?? false,
                role: row.role,
                policy: row.policy,
                isCurrentUser: row.userID == session.user.id
            )
        }
        let resolvedFamily = try await family
        let invites = try await invitesTask
        let permissionGrants = try await permissionGrantsTask

        return FamilyStateSnapshot(
            family: resolvedFamily,
            currentMembership: currentMembership,
            members: members,
            invites: invites,
            permissionGrants: permissionGrants
        )
    }

    func createFamily(
        name: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        let family = try await insertFamily(name: name, session: session)
        let ownerPolicy = FamilyPermissionPolicy.preset(for: .owner)
        _ = try await insertMembership(
            familyID: family.id,
            userID: session.user.id,
            role: .owner,
            policy: ownerPolicy,
            session: session
        )
        return try await fetchState(session: session)
    }

    func previewInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInvitePreview? {
        let invite = try await fetchInvite(code: code, session: session)
        let family = try await fetchFamily(id: invite.familyID, session: session)
        return FamilyInvitePreview(invite: invite, family: family)
    }

    func joinInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        try await acceptInvite(token: code, session: session)
    }

    func previewInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInvitePreviewRecord {
        let rows: [FamilyInvitePreviewRecord] = try await callRPC(
            functionName: "preview_family_invite",
            body: PreviewFamilyInviteRPCBody(token: token),
            session: session
        )
        guard let preview = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return preview
    }

    func acceptInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        let _: FamilyMembershipRecord = try await callRPC(
            functionName: "accept_family_invite",
            body: AcceptFamilyInviteRPCBody(token: token),
            session: session
        )
        return try await fetchState(session: session)
    }

    func declineInvite(
        token: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        try await callRPC(
            functionName: "decline_family_invite",
            body: DeclineFamilyInviteRPCBody(token: token),
            session: session
        )
    }

    func createInvite(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        try await callRPC(
            functionName: "create_family_invite_link",
            body: CreateFamilyInviteLinkRPCBody(
                familyID: familyID,
                defaultRole: defaultRole,
                expiresAt: expiresAt
            ),
            session: session
        )
    }

    func revokeInvite(
        inviteID: UUID,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        try await callRPC(
            functionName: "revoke_family_invite",
            body: RevokeFamilyInviteRPCBody(inviteID: inviteID),
            session: session
        )
    }

    private func legacyCreateInvite(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        let body = FamilyInviteInsertPayload(
            familyID: familyID,
            code: makeInviteCode(),
            token: makeInviteToken(),
            createdByUserID: session.user.id,
            defaultRoleRawValue: defaultRole.rawValue,
            expiresAt: expiresAt
        )

        let rows: [FamilyInviteRecord] = try await insertRows(
            path: "family_invites",
            body: [body],
            session: session
        )

        guard let invite = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return invite
    }

    func updateMember(
        membershipID: UUID,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        session: SupabaseAuthSession
    ) async throws {
        let payload = FamilyMembershipUpdatePayload(
            roleRawValue: role.rawValue,
            canViewFamilyDashboard: policy.canViewFamilyDashboard,
            canViewOthers: policy.canViewOthers,
            canEditOthers: policy.canEditOthers,
            canViewWallets: policy.canViewWallets,
            canViewDebts: policy.canViewDebts,
            canViewKids: policy.canViewKids,
            canEditKids: policy.canEditKids
        )
        _ = try await patchRows(
            path: "family_memberships",
            filters: [
                URLQueryItem(name: "id", value: "eq.\(membershipID.uuidString.lowercased())")
            ],
            body: payload,
            session: session
        ) as [FamilyMembershipRecord]
    }

    func setPermissionGrant(
        familyID: UUID,
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        isGranted: Bool,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionGrantRecord {
        try await callRPC(
            functionName: "set_family_permission_grant",
            body: SetFamilyPermissionGrantRPCBody(
                familyID: familyID,
                granteeUserID: granteeUserID,
                ownerUserID: ownerUserID,
                resourceType: resourceType,
                resourceID: resourceID,
                permissionScope: scope,
                isGranted: isGranted
            ),
            session: session
        )
    }

    func removeMember(
        membershipID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        let _: FamilyMembershipRecord = try await callRPC(
            functionName: "remove_family_member",
            body: RemoveFamilyMemberRPCBody(membershipID: membershipID),
            session: session
        )
    }

    func transferOwner(
        familyID: UUID,
        newOwnerMembershipID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        let _: FamilyMembershipRecord = try await callRPC(
            functionName: "transfer_family_owner",
            body: TransferFamilyOwnerRPCBody(
                familyID: familyID,
                newOwnerMembershipID: newOwnerMembershipID
            ),
            session: session
        )
    }

    func deleteFamily(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        let _: EmptyResponse = try await callRPC(
            functionName: "delete_family",
            body: DeleteFamilyRPCBody(familyID: familyID),
            session: session
        )
    }

    func fetchAccessibleFinanceSnapshot(
        userIDs: [UUID],
        session: SupabaseAuthSession
    ) async throws -> MistiaRemoteSnapshot {
        guard !userIDs.isEmpty else {
            return MistiaRemoteSnapshot(
                wallets: [],
                creditCardProfiles: [],
                categories: [],
                transactions: [],
                budgetPlans: [],
                savingsGoals: [],
                recurringBillPlans: [],
                installmentPlans: [],
                dueOccurrences: []
            )
        }

        let wallets: [RemoteLedgerWallet] = try await fetchFinanceRows(
            path: MistiaSyncEntity.wallet.tableName,
            userIDs: userIDs,
            session: session
        )
        let profiles: [RemoteCreditCardProfile] = try await fetchFinanceRows(
            path: MistiaSyncEntity.creditCardProfile.tableName,
            userIDs: userIDs,
            session: session
        )
        let categories: [RemoteTransactionCategory] = try await fetchFinanceRows(
            path: MistiaSyncEntity.category.tableName,
            userIDs: userIDs,
            session: session
        )
        let transactions: [RemoteLedgerTransaction] = try await fetchAccessibleTransactionRows(session: session)
        let budgets: [RemoteBudgetPlan] = try await fetchFinanceRows(
            path: MistiaSyncEntity.budgetPlan.tableName,
            userIDs: userIDs,
            session: session
        )
        let goals: [RemoteSavingsGoal] = try await fetchFinanceRows(
            path: MistiaSyncEntity.savingsGoal.tableName,
            userIDs: userIDs,
            session: session
        )
        let bills: [RemoteRecurringBillPlan] = try await fetchFinanceRows(
            path: MistiaSyncEntity.recurringBillPlan.tableName,
            userIDs: userIDs,
            session: session
        )
        let installments: [RemoteInstallmentPlan] = try await fetchFinanceRows(
            path: MistiaSyncEntity.installmentPlan.tableName,
            userIDs: userIDs,
            session: session
        )
        let dueOccurrences: [RemoteDueOccurrenceRecord] = try await fetchFinanceRows(
            path: MistiaSyncEntity.dueOccurrenceRecord.tableName,
            userIDs: userIDs,
            session: session
        )

        return MistiaRemoteSnapshot(
            wallets: wallets,
            creditCardProfiles: profiles,
            categories: categories,
            transactions: transactions,
            budgetPlans: budgets,
            savingsGoals: goals,
            recurringBillPlans: bills,
            installmentPlans: installments,
            dueOccurrences: dueOccurrences
        )
    }

    func fetchFamilyNotifications(session: SupabaseAuthSession) async throws -> [FamilyNotificationRemoteRecord] {
        try await fetchRows(
            path: "family_notifications",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "100")
            ],
            session: session
        )
    }

    func createFamilyPermissionRequest(
        input: FamilyPermissionRequestInput,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord {
        try await callRPC(
            functionName: "create_family_permission_request",
            body: CreateFamilyPermissionRequestRPCBody(input: input),
            session: session
        )
    }

    func respondFamilyPermissionRequest(
        requestID: UUID,
        approve: Bool,
        session: SupabaseAuthSession
    ) async throws -> FamilyPermissionRequestRemoteRecord {
        try await callRPC(
            functionName: "respond_family_permission_request",
            body: RespondFamilyPermissionRequestRPCBody(
                requestID: requestID,
                approve: approve
            ),
            session: session
        )
    }

    func markFamilyNotificationsRead(
        ids: [UUID],
        session: SupabaseAuthSession
    ) async throws {
        guard !ids.isEmpty else { return }
        let _: EmptyResponse = try await callRPC(
            functionName: "mark_family_notifications_read",
            body: MarkFamilyNotificationsReadRPCBody(notificationIDs: ids),
            session: session
        )
    }

    private func fetchCurrentMembership(session: SupabaseAuthSession) async throws -> FamilyMembershipRecord? {
        let rows: [FamilyMembershipRecord] = try await fetchRows(
            path: "family_memberships",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "limit", value: "1")
            ],
            session: session
        )
        return rows.first
    }

    private func fetchFamily(
        id: UUID,
        session: SupabaseAuthSession
    ) async throws -> FamilyGroupRecord {
        let rows: [FamilyGroupRecord] = try await fetchRows(
            path: "families",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "limit", value: "1")
            ],
            session: session
        )
        guard let family = rows.first else {
            throw SupabaseServiceError.serverMessage("Family not found.")
        }
        return family
    }

    private func fetchMemberships(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws -> [FamilyMembershipRecord] {
        try await fetchRows(
            path: "family_memberships",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "family_id", value: "eq.\(familyID.uuidString.lowercased())"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ],
            session: session
        )
    }

    private func fetchProfiles(
        userIDs: [UUID],
        session: SupabaseAuthSession
    ) async throws -> [FamilyUserProfileRecord] {
        try await fetchRows(
            path: "user_profiles",
            filters: [
                URLQueryItem(name: "select", value: "user_id,display_name,avatar_url"),
                URLQueryItem(name: "user_id", value: inFilter(for: userIDs))
            ],
            session: session
        )
    }

    private func fetchCloudSyncStatuses(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws -> [FamilySyncStatusRecord] {
        try await callRPC(
            functionName: "family_cloud_sync_status",
            body: FamilyCloudSyncStatusRPCBody(familyID: familyID),
            session: session
        )
    }

    private func fetchInvites(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws -> [FamilyInviteRecord] {
        try await fetchRows(
            path: "family_invites",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "family_id", value: "eq.\(familyID.uuidString.lowercased())"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            session: session
        )
    }

    private func fetchPermissionGrants(
        familyID: UUID,
        session: SupabaseAuthSession,
        userID: UUID? = nil
    ) async throws -> [FamilyPermissionGrantRecord] {
        var filters = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "family_id", value: "eq.\(familyID.uuidString.lowercased())"),
            URLQueryItem(name: "revoked_at", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]

        if let userID {
            filters.append(
                URLQueryItem(
                    name: "or",
                    value: "(grantee_user_id.eq.\(userID.uuidString.lowercased()),owner_user_id.eq.\(userID.uuidString.lowercased()))"
                )
            )
        }

        return try await fetchRows(
            path: "family_permission_grants",
            filters: filters,
            session: session
        )
    }

    private func fetchInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let rows: [FamilyInviteRecord] = try await fetchRows(
            path: "family_invites",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "code", value: "eq.\(normalizedCode)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            session: session
        )

        guard let invite = rows.first, invite.deletedAt == nil else {
            throw SupabaseServiceError.serverMessage(mistiaLocalized(
                vi: "Mã mời không tồn tại hoặc đã bị xóa.",
                en: "Invite code does not exist or has been deleted.",
                ja: "招待コードが存在しないか、削除されました。"
            ))
        }

        if invite.acceptedAt != nil || invite.declinedAt != nil || invite.revokedAt != nil {
            throw SupabaseServiceError.serverMessage(mistiaLocalized(
                vi: "Mã mời này không còn hiệu lực.",
                en: "This invite code is no longer valid.",
                ja: "この招待コードはもう有効ではありません。"
            ))
        }

        if invite.expiresAt < .now {
            throw SupabaseServiceError.serverMessage(mistiaLocalized(
                vi: "Mã mời đã hết hạn.",
                en: "Invite code has expired.",
                ja: "招待コードの期限が切れました。"
            ))
        }

        return invite
    }

    private func insertFamily(
        name: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyGroupRecord {
        let payload = FamilyGroupInsertPayload(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerUserID: session.user.id
        )
        let rows: [FamilyGroupRecord] = try await insertRows(
            path: "families",
            body: [payload],
            session: session
        )
        guard let family = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return family
    }

    private func insertMembership(
        familyID: UUID,
        userID: UUID,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        session: SupabaseAuthSession
    ) async throws -> FamilyMembershipRecord {
        let payload = FamilyMembershipInsertPayload(
            familyID: familyID,
            userID: userID,
            roleRawValue: role.rawValue,
            canViewFamilyDashboard: policy.canViewFamilyDashboard,
            canViewOthers: policy.canViewOthers,
            canEditOthers: policy.canEditOthers,
            canViewWallets: policy.canViewWallets,
            canViewDebts: policy.canViewDebts,
            canViewKids: policy.canViewKids,
            canEditKids: policy.canEditKids
        )
        let rows: [FamilyMembershipRecord] = try await insertRows(
            path: "family_memberships",
            body: [payload],
            session: session
        )
        guard let membership = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return membership
    }

    private func markInviteAccepted(
        inviteID: UUID,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        let payload = FamilyInviteAcceptPayload(
            acceptedAt: .now,
            acceptedByUserID: session.user.id
        )
        let rows: [FamilyInviteRecord] = try await patchRows(
            path: "family_invites",
            filters: [
                URLQueryItem(name: "id", value: "eq.\(inviteID.uuidString.lowercased())")
            ],
            body: payload,
            session: session
        )
        guard let invite = rows.first else {
            throw SupabaseServiceError.invalidResponse
        }
        return invite
    }

    private func fetchRows<Row: Decodable>(
        path: String,
        filters: [URLQueryItem],
        session: SupabaseAuthSession
    ) async throws -> [Row] {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }
        components.queryItems = filters

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }
        return try await performRequest(request: authorizedRequest(url: url, session: session))
    }

    private func insertRows<Body: Encodable, Row: Decodable>(
        path: String,
        body: Body,
        session: SupabaseAuthSession
    ) async throws -> [Row] {
        let configuration = try configuration()
        let url = configuration.restBaseURL.appending(path: path)
        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        return try await performRequest(request: request)
    }

    private func patchRows<Body: Encodable, Row: Decodable>(
        path: String,
        filters: [URLQueryItem],
        body: Body,
        session: SupabaseAuthSession
    ) async throws -> [Row] {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }
        components.queryItems = filters
        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "PATCH"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        return try await performRequest(request: request)
    }

    private func deleteRows<Row: Decodable>(
        path: String,
        filters: [URLQueryItem],
        session: SupabaseAuthSession
    ) async throws -> [Row] {
        let configuration = try configuration()
        guard var components = URLComponents(
            url: configuration.restBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseServiceError.invalidURL
        }
        components.queryItems = filters
        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "DELETE"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        return try await performRequest(request: request)
    }

    private func callRPC<Body: Encodable, Response: Decodable>(
        functionName: String,
        body: Body,
        session: SupabaseAuthSession
    ) async throws -> Response {
        let configuration = try configuration()
        let url = configuration.restBaseURL
            .appending(path: "rpc")
            .appending(path: functionName)
        var request = authorizedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        return try await performRequest(request: request)
    }

    private func fetchFinanceRows<Row: Decodable>(
        path: String,
        userIDs: [UUID],
        session: SupabaseAuthSession
    ) async throws -> [Row] {
        try await fetchRows(
            path: path,
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: inFilter(for: userIDs)),
                URLQueryItem(name: "order", value: "updated_at.asc")
            ],
            session: session
        )
    }

    private func fetchAccessibleTransactionRows(
        session: SupabaseAuthSession
    ) async throws -> [RemoteLedgerTransaction] {
        try await fetchRows(
            path: MistiaSyncEntity.transaction.tableName,
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.asc")
            ],
            session: session
        )
    }

    private func configuration() throws -> MistiaSyncConfiguration {
        guard let configuration = configurationProvider() else {
            throw SupabaseServiceError.configurationMissing
        }
        return configuration
    }

    private func authorizedRequest(
        url: URL,
        session: SupabaseAuthSession
    ) -> URLRequest {
        let apiKey = configurationProvider()?.anonKey ?? ""
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest<Response: Decodable>(
        request: URLRequest
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(SupabaseServiceErrorResponse.self, from: data)
            throw SupabaseServiceError.serverMessage(
                errorResponse?.message
                    ?? errorResponse?.errorDescription
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func inFilter(for userIDs: [UUID]) -> String {
        let values = userIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        return "in.(\(values))"
    }

    private func makeInviteCode() -> String {
        String(UUID().uuidString.prefix(8)).uppercased()
    }

    private func makeInviteToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

private struct EmptyResponse: Decodable {}

private struct FamilyGroupInsertPayload: Encodable {
    let name: String
    let ownerUserID: UUID

    enum CodingKeys: String, CodingKey {
        case name
        case ownerUserID = "owner_user_id"
    }
}

private struct FamilyMembershipInsertPayload: Encodable {
    let familyID: UUID
    let userID: UUID
    let roleRawValue: String
    let canViewFamilyDashboard: Bool
    let canViewOthers: Bool
    let canEditOthers: Bool
    let canViewWallets: Bool
    let canViewDebts: Bool
    let canViewKids: Bool
    let canEditKids: Bool

    enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case userID = "user_id"
        case roleRawValue = "role"
        case canViewFamilyDashboard = "can_view_family_dashboard"
        case canViewOthers = "can_view_others"
        case canEditOthers = "can_edit_others"
        case canViewWallets = "can_view_wallets"
        case canViewDebts = "can_view_debts"
        case canViewKids = "can_view_kids"
        case canEditKids = "can_edit_kids"
    }
}

private struct FamilyInviteInsertPayload: Encodable {
    let familyID: UUID
    let code: String
    let token: String
    let createdByUserID: UUID
    let defaultRoleRawValue: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case code
        case token
        case createdByUserID = "created_by_user_id"
        case defaultRoleRawValue = "default_role"
        case expiresAt = "expires_at"
    }
}

private struct CreateFamilyInviteLinkRPCBody: Encodable {
    let familyID: UUID
    let defaultRole: String
    let expiresAt: Date

    init(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date
    ) {
        self.familyID = familyID
        self.defaultRole = defaultRole.rawValue
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case defaultRole = "p_default_role"
        case expiresAt = "p_expires_at"
    }
}

private struct PreviewFamilyInviteRPCBody: Encodable {
    let token: String

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
    }
}

private struct AcceptFamilyInviteRPCBody: Encodable {
    let token: String

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
    }
}

private struct DeclineFamilyInviteRPCBody: Encodable {
    let token: String

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
    }
}

private struct RevokeFamilyInviteRPCBody: Encodable {
    let inviteID: UUID

    enum CodingKeys: String, CodingKey {
        case inviteID = "p_invite_id"
    }
}

private struct RemoveFamilyMemberRPCBody: Encodable {
    let membershipID: UUID

    enum CodingKeys: String, CodingKey {
        case membershipID = "p_membership_id"
    }
}

private struct TransferFamilyOwnerRPCBody: Encodable {
    let familyID: UUID
    let newOwnerMembershipID: UUID

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case newOwnerMembershipID = "p_new_owner_membership_id"
    }
}

private struct DeleteFamilyRPCBody: Encodable {
    let familyID: UUID

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
    }
}

private struct FamilyCloudSyncStatusRPCBody: Encodable {
    let familyID: UUID

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
    }
}

private struct FamilyInviteAcceptPayload: Encodable {
    let acceptedAt: Date
    let acceptedByUserID: UUID

    enum CodingKeys: String, CodingKey {
        case acceptedAt = "accepted_at"
        case acceptedByUserID = "accepted_by_user_id"
    }
}

private struct FamilyMembershipUpdatePayload: Encodable {
    let roleRawValue: String
    let canViewFamilyDashboard: Bool
    let canViewOthers: Bool
    let canEditOthers: Bool
    let canViewWallets: Bool
    let canViewDebts: Bool
    let canViewKids: Bool
    let canEditKids: Bool

    enum CodingKeys: String, CodingKey {
        case roleRawValue = "role"
        case canViewFamilyDashboard = "can_view_family_dashboard"
        case canViewOthers = "can_view_others"
        case canEditOthers = "can_edit_others"
        case canViewWallets = "can_view_wallets"
        case canViewDebts = "can_view_debts"
        case canViewKids = "can_view_kids"
        case canEditKids = "can_edit_kids"
    }
}

private struct SetFamilyPermissionGrantRPCBody: Encodable {
    let familyID: UUID
    let granteeUserID: UUID
    let ownerUserID: UUID
    let resourceType: String
    let resourceID: UUID?
    let permissionScope: String
    let isGranted: Bool

    init(
        familyID: UUID,
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        permissionScope: MistiaFamilyPermissionScope,
        isGranted: Bool
    ) {
        self.familyID = familyID
        self.granteeUserID = granteeUserID
        self.ownerUserID = ownerUserID
        self.resourceType = resourceType.rawValue
        self.resourceID = resourceID
        self.permissionScope = permissionScope.rawValue
        self.isGranted = isGranted
    }

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case granteeUserID = "p_grantee_user_id"
        case ownerUserID = "p_owner_user_id"
        case resourceType = "p_resource_type"
        case resourceID = "p_resource_id"
        case permissionScope = "p_permission_scope"
        case isGranted = "p_is_granted"
    }
}

private struct CreateFamilyPermissionRequestRPCBody: Encodable {
    let familyID: UUID
    let recipientUserID: UUID
    let resourceType: String
    let resourceID: UUID?
    let permissionScope: String
    let title: String
    let body: String
    let message: String?

    init(input: FamilyPermissionRequestInput) {
        familyID = input.familyID
        recipientUserID = input.recipientUserID
        resourceType = input.resourceType.rawValue
        resourceID = input.resourceID
        permissionScope = input.permissionScope.rawValue
        title = input.title
        body = input.body
        message = input.message
    }

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case recipientUserID = "p_recipient_user_id"
        case resourceType = "p_resource_type"
        case resourceID = "p_resource_id"
        case permissionScope = "p_permission_scope"
        case title = "p_title"
        case body = "p_body"
        case message = "p_message"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(familyID, forKey: .familyID)
        try container.encode(recipientUserID, forKey: .recipientUserID)
        try container.encode(resourceType, forKey: .resourceType)
        if let resourceID {
            try container.encode(resourceID, forKey: .resourceID)
        } else {
            try container.encodeNil(forKey: .resourceID)
        }
        try container.encode(permissionScope, forKey: .permissionScope)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        if let message {
            try container.encode(message, forKey: .message)
        } else {
            try container.encodeNil(forKey: .message)
        }
    }
}

private struct RespondFamilyPermissionRequestRPCBody: Encodable {
    let requestID: UUID
    let approve: Bool

    enum CodingKeys: String, CodingKey {
        case requestID = "p_request_id"
        case approve = "p_approve"
    }
}

private struct MarkFamilyNotificationsReadRPCBody: Encodable {
    let notificationIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case notificationIDs = "p_notification_ids"
    }
}
