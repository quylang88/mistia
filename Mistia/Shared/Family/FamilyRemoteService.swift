import Foundation

struct FamilyGroupRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let ownerUserID: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerUserID = "owner_user_id"
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var role: FamilyRole {
        FamilyRole(rawValue: roleRawValue) ?? .viewer
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
    let createdByUserID: UUID
    var defaultRoleRawValue: String
    let expiresAt: Date
    let acceptedAt: Date?
    let acceptedByUserID: UUID?
    let revokedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case code
        case createdByUserID = "created_by_user_id"
        case defaultRoleRawValue = "default_role"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case acceptedByUserID = "accepted_by_user_id"
        case revokedAt = "revoked_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var defaultRole: FamilyRole {
        FamilyRole(rawValue: defaultRoleRawValue) ?? .viewer
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

struct FamilyMember: Identifiable, Equatable {
    let membershipID: UUID
    let familyID: UUID
    let userID: UUID
    var displayName: String
    var avatarURL: URL?
    var role: FamilyRole
    var policy: FamilyPermissionPolicy
    var isCurrentUser: Bool

    var id: UUID { membershipID }
}

struct FamilyInvitePreview: Equatable {
    let invite: FamilyInviteRecord
    let family: FamilyGroupRecord
}

struct FamilyStateSnapshot: Equatable {
    var family: FamilyGroupRecord?
    var currentMembership: FamilyMembershipRecord?
    var members: [FamilyMember]
    var invites: [FamilyInviteRecord]
}

@MainActor
struct FamilyRemoteService {
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
                invites: []
            )
        }

        let family = try await fetchFamily(id: currentMembership.familyID, session: session)
        let membershipRows = try await fetchMemberships(familyID: currentMembership.familyID, session: session)
        let profileRows = try await fetchProfiles(
            userIDs: membershipRows.map(\.userID),
            session: session
        )
        let profileByUserID = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.userID, $0) })
        let members = membershipRows.map { row in
            let profile = profileByUserID[row.userID]
            return FamilyMember(
                membershipID: row.id,
                familyID: row.familyID,
                userID: row.userID,
                displayName: profile?.displayName ?? "Mistia",
                avatarURL: profile?.avatarURL.flatMap(URL.init(string:)),
                role: row.role,
                policy: row.policy,
                isCurrentUser: row.userID == session.user.id
            )
        }
        let invites = currentMembership.role == .owner
            ? try await fetchInvites(familyID: currentMembership.familyID, session: session)
            : []

        return FamilyStateSnapshot(
            family: family,
            currentMembership: currentMembership,
            members: members,
            invites: invites
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
        guard let invite = try await fetchInvite(code: code, session: session) else {
            return nil
        }
        let family = try await fetchFamily(id: invite.familyID, session: session)
        return FamilyInvitePreview(invite: invite, family: family)
    }

    func joinInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyStateSnapshot {
        guard let preview = try await previewInvite(code: code, session: session) else {
            throw SupabaseServiceError.serverMessage("Invite code is invalid or expired.")
        }

        let policy = FamilyPermissionPolicy.preset(for: preview.invite.defaultRole)
        _ = try await insertMembership(
            familyID: preview.family.id,
            userID: session.user.id,
            role: preview.invite.defaultRole,
            policy: policy,
            session: session
        )
        _ = try await markInviteAccepted(
            inviteID: preview.invite.id,
            session: session
        )

        return try await fetchState(session: session)
    }

    func createInvite(
        familyID: UUID,
        defaultRole: FamilyRole,
        expiresAt: Date,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord {
        let body = FamilyInviteInsertPayload(
            familyID: familyID,
            code: makeInviteCode(),
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

    func removeMember(
        membershipID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        _ = try await deleteRows(
            path: "family_memberships",
            filters: [
                URLQueryItem(name: "id", value: "eq.\(membershipID.uuidString.lowercased())")
            ],
            session: session
        ) as [FamilyMembershipRecord]
    }

    func deleteFamily(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws {
        _ = try await deleteRows(
            path: "families",
            filters: [
                URLQueryItem(name: "id", value: "eq.\(familyID.uuidString.lowercased())")
            ],
            session: session
        ) as [FamilyGroupRecord]
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

        async let wallets: [RemoteLedgerWallet] = fetchFinanceRows(path: MistiaSyncEntity.wallet.tableName, userIDs: userIDs, session: session)
        async let profiles: [RemoteCreditCardProfile] = fetchFinanceRows(path: MistiaSyncEntity.creditCardProfile.tableName, userIDs: userIDs, session: session)
        async let categories: [RemoteTransactionCategory] = fetchFinanceRows(path: MistiaSyncEntity.category.tableName, userIDs: userIDs, session: session)
        async let transactions: [RemoteLedgerTransaction] = fetchFinanceRows(path: MistiaSyncEntity.transaction.tableName, userIDs: userIDs, session: session)
        async let budgets: [RemoteBudgetPlan] = fetchFinanceRows(path: MistiaSyncEntity.budgetPlan.tableName, userIDs: userIDs, session: session)
        async let goals: [RemoteSavingsGoal] = fetchFinanceRows(path: MistiaSyncEntity.savingsGoal.tableName, userIDs: userIDs, session: session)
        async let bills: [RemoteRecurringBillPlan] = fetchFinanceRows(path: MistiaSyncEntity.recurringBillPlan.tableName, userIDs: userIDs, session: session)
        async let installments: [RemoteInstallmentPlan] = fetchFinanceRows(path: MistiaSyncEntity.installmentPlan.tableName, userIDs: userIDs, session: session)
        async let dueOccurrences: [RemoteDueOccurrenceRecord] = fetchFinanceRows(path: MistiaSyncEntity.dueOccurrenceRecord.tableName, userIDs: userIDs, session: session)

        return try await MistiaRemoteSnapshot(
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

    private func fetchCurrentMembership(session: SupabaseAuthSession) async throws -> FamilyMembershipRecord? {
        let rows: [FamilyMembershipRecord] = try await fetchRows(
            path: "family_memberships",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(session.user.id.uuidString.lowercased())"),
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

    private func fetchInvites(
        familyID: UUID,
        session: SupabaseAuthSession
    ) async throws -> [FamilyInviteRecord] {
        try await fetchRows(
            path: "family_invites",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "family_id", value: "eq.\(familyID.uuidString.lowercased())"),
                URLQueryItem(name: "accepted_at", value: "is.null"),
                URLQueryItem(name: "revoked_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            session: session
        )
    }

    private func fetchInvite(
        code: String,
        session: SupabaseAuthSession
    ) async throws -> FamilyInviteRecord? {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let rows: [FamilyInviteRecord] = try await fetchRows(
            path: "family_invites",
            filters: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "code", value: "eq.\(normalizedCode)"),
                URLQueryItem(name: "accepted_at", value: "is.null"),
                URLQueryItem(name: "revoked_at", value: "is.null"),
                URLQueryItem(name: "limit", value: "1")
            ],
            session: session
        )
        guard let invite = rows.first, invite.expiresAt >= .now else {
            return nil
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
    let createdByUserID: UUID
    let defaultRoleRawValue: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case code
        case createdByUserID = "created_by_user_id"
        case defaultRoleRawValue = "default_role"
        case expiresAt = "expires_at"
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
