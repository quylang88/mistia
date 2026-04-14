import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FamilyContextStore {
    var activeContext: FamilyContext = .personalSelf
    var family: FamilyGroupRecord?
    var currentMembership: FamilyMembershipRecord?
    var members: [FamilyMember] = []
    var invites: [FamilyInviteRecord] = []
    var lastErrorMessage: String?
    var isLoading = false
    var isSwitchingContext = false
    var didBootstrap = false

    @ObservationIgnored private let service: FamilyRemoteService
    @ObservationIgnored private let modelContainer: ModelContainer

    init(
        modelContainer: ModelContainer,
        service: FamilyRemoteService
    ) {
        self.modelContainer = modelContainer
        self.service = service
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(modelContainer: modelContainer, service: FamilyRemoteService())
    }

    var currentUserID: UUID? {
        currentMembership?.userID
    }

    var currentRole: FamilyRole {
        currentMembership?.role ?? .viewer
    }

    var currentPolicy: FamilyPermissionPolicy {
        currentMembership?.policy ?? .preset(for: .viewer)
    }

    var selectedSubjectUserID: UUID? {
        switch activeContext.scope {
        case .personalSelf, .familyHome:
            currentUserID
        case .member(let userID):
            userID
        }
    }

    var isViewingMemberContext: Bool {
        if case .member = activeContext.scope {
            return true
        }
        return false
    }

    var isViewingFamilyAggregate: Bool {
        if case .familyHome = activeContext.scope {
            return true
        }
        return false
    }

    var isViewingSelfContext: Bool {
        activeContext.scope == .personalSelf
    }

    var isViewingOtherMemberContext: Bool {
        guard case .member(let userID) = activeContext.scope else { return false }
        return userID != currentUserID
    }

    var viewedMember: FamilyMember? {
        guard case .member(let userID) = activeContext.scope else { return nil }
        return members.first(where: { $0.userID == userID })
    }

    var canPresentFamilyHome: Bool {
        currentRole != .kid && currentPolicy.canViewFamilyDashboard
    }

    var canInviteMembers: Bool {
        currentRole == .owner
    }

    var canEditSelectedSubject: Bool {
        guard let viewedMember else { return true }
        return capabilities(for: viewedMember).canEditTarget
    }

    var canViewSelectedSubject: Bool {
        guard let viewedMember else { return true }
        return capabilities(for: viewedMember).canViewTarget
    }

    var contextChipTitle: String? {
        guard isViewingOtherMemberContext, let viewedMember else { return nil }
        return mistiaLocalized(
            vi: "Đang xem: \(viewedMember.displayName)",
            en: "Viewing: \(viewedMember.displayName)",
            ja: "表示中: \(viewedMember.displayName)"
        )
    }

    func bootstrapIfNeeded(sessionStore: SessionStore) async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await refresh(sessionStore: sessionStore)
    }

    func refresh(sessionStore: SessionStore) async {
        guard sessionStore.isSignedIn else {
            clear()
            return
        }

        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else {
            lastErrorMessage = mistiaLocalized(
                vi: "Không thể làm mới phiên gia đình.",
                en: "Couldn't refresh the family session.",
                ja: "家族セッションを更新できませんでした。"
            )
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await service.fetchState(session: session)
            family = snapshot.family
            currentMembership = snapshot.currentMembership
            members = snapshot.members
            invites = snapshot.invites
            lastErrorMessage = nil

            if let familyID = snapshot.family?.id, activeContext.scope == .familyHome(familyID: familyID) {
                activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
            } else if case .member(let userID) = activeContext.scope,
                      !members.contains(where: { $0.userID == userID }) {
                activeContext = .personalSelf
            }

            if let sessionUserID = sessionStore.signedInUserID {
                let subjectIDs = [sessionUserID] + members.map(\.userID)
                let financeSnapshot = try await service.fetchAccessibleFinanceSnapshot(
                    userIDs: Array(Set(subjectIDs)),
                    session: session
                )
                try MistiaSyncLocalStore.applySnapshotIncrementally(
                    financeSnapshot,
                    shouldPruneMissing: false,
                    protectedRecordIDs: [],
                    in: modelContainer
                )
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteFamily(sessionStore: SessionStore) async {
        guard let familyID = family?.id else { return }
        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else { return }

        do {
            try await service.deleteFamily(familyID: familyID, session: session)
            activeContext = .personalSelf
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func createFamily(
        name: String,
        sessionStore: SessionStore
    ) async {
        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else { return }

        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await service.createFamily(name: name, session: session)
            family = snapshot.family
            currentMembership = snapshot.currentMembership
            members = snapshot.members
            invites = snapshot.invites
            lastErrorMessage = nil
            if let familyID = snapshot.family?.id {
                activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
            }
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func joinFamily(
        inviteCode: String,
        sessionStore: SessionStore
    ) async {
        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await service.joinInvite(code: inviteCode, session: session)
            family = snapshot.family
            currentMembership = snapshot.currentMembership
            members = snapshot.members
            invites = snapshot.invites
            lastErrorMessage = nil
            if let familyID = snapshot.family?.id {
                activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
            }
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func createInvite(
        defaultRole: FamilyRole,
        sessionStore: SessionStore
    ) async -> FamilyInviteRecord? {
        guard let familyID = family?.id else { return nil }
        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else { return nil }

        do {
            let invite = try await service.createInvite(
                familyID: familyID,
                defaultRole: defaultRole,
                expiresAt: Calendar.current.date(byAdding: .minute, value: 10, to: .now) ?? .now,
                session: session
            )
            invites.insert(invite, at: 0)
            return invite
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func updateMember(
        _ member: FamilyMember,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        sessionStore: SessionStore
    ) async {
        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else { return }

        do {
            try await service.updateMember(
                membershipID: member.membershipID,
                role: role,
                policy: policy,
                session: session
            )
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeMember(
        _ member: FamilyMember,
        sessionStore: SessionStore
    ) async {
        let refreshedSession = try? await sessionStore.refreshedSession()
        guard let session = refreshedSession ?? nil else { return }

        do {
            try await service.removeMember(
                membershipID: member.membershipID,
                session: session
            )
            if viewedMember?.userID == member.userID {
                activeContext = .personalSelf
            }
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func activateFamilyHome() {
        guard let familyID = family?.id else { return }
        activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
    }

    func activateSelfView() {
        activeContext = .personalSelf
    }

    func activateMemberView(_ member: FamilyMember) {
        let capabilities = capabilities(for: member)
        guard capabilities.canViewTarget else { return }

        isSwitchingContext = true
        defer { isSwitchingContext = false }

        if member.userID == currentUserID {
            activeContext = .personalSelf
        } else {
            activeContext = FamilyContext(scope: .member(userID: member.userID))
        }
    }

    func returnToSelf() {
        activeContext = .personalSelf
    }

    func capabilities(for member: FamilyMember) -> FamilyMemberAccessCapabilities {
        FamilyLogic.access(
            viewerRole: currentRole,
            viewerPolicy: currentPolicy,
            targetRole: member.role,
            isSameUser: member.userID == currentUserID
        )
    }

    func shareMessage(for invite: FamilyInviteRecord) -> String {
        guard let family else {
            return invite.code
        }

        return """
        \(mistiaLocalized(vi: "Mời bạn vào gia đình", en: "Join my family", ja: "家族に参加してください")): \(family.name)
        \(mistiaLocalized(vi: "Mã mời", en: "Invite code", ja: "招待コード")): \(invite.code)
        """
    }

    func clear() {
        activeContext = .personalSelf
        family = nil
        currentMembership = nil
        members = []
        invites = []
        lastErrorMessage = nil
    }
}
