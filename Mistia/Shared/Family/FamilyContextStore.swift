import Foundation
import Observation
import SwiftData

enum FamilyRefreshSource {
    case enterFamily
    case userInitiated
    case postManualSync
}

struct FamilyOverviewPresentationRoute: Identifiable, Equatable {
    let familyID: UUID

    var id: UUID { familyID }
}

private struct FamilyPendingPermissionRequestKey: Hashable {
    let ownerUserID: UUID
    let resourceTypeRawValue: String
    let resourceID: UUID?
    let scopeRawValue: String
}

@MainActor
@Observable
final class FamilyContextStore {
    private static let pendingInviteTokenKey = "Mistia.pendingFamilyInviteToken"
    private static let latestRefreshCooldown: TimeInterval = 45
    private static let passiveRefreshCooldown: TimeInterval = 45

    var activeContext: FamilyContext = .personalSelf
    var family: FamilyGroupRecord?
    var currentMembership: FamilyMembershipRecord?
    var members: [FamilyMember] = []
    var invites: [FamilyInviteRecord] = []
    var permissionGrants: [FamilyPermissionGrantRecord] = []
    var pendingInviteRoute: FamilyInviteRoute?
    var pendingFamilyOverviewRoute: FamilyOverviewPresentationRoute?
    var lastErrorMessage: String?
    var isLoading = false
    var isRefreshingLatest = false
    var isSwitchingContext = false
    var didBootstrap = false

    @ObservationIgnored private let service: any FamilyRemoteServicing
    @ObservationIgnored private let launchState: MistiaDataStack.LaunchState?
    @ObservationIgnored private var modelContainer: ModelContainer
    @ObservationIgnored private var refreshTask: Task<Bool, Never>?
    @ObservationIgnored private var lastPassiveRefreshCompletedAt: Date?
    @ObservationIgnored private var lastLatestRefreshCompletedAt: Date?
    @ObservationIgnored private var avatarHydrationTask: Task<Void, Never>?
    private var pendingPermissionRequestKeys: Set<FamilyPendingPermissionRequestKey> = []

    init(
        modelContainer: ModelContainer,
        launchState: MistiaDataStack.LaunchState? = nil,
        service: any FamilyRemoteServicing
    ) {
        self.modelContainer = modelContainer
        self.launchState = launchState
        self.service = service
        if let token = UserDefaults.standard.string(forKey: Self.pendingInviteTokenKey),
           let normalizedToken = FamilyInviteLinking.normalizedToken(token) {
            self.pendingInviteRoute = FamilyInviteRoute(token: normalizedToken)
        }
    }

    convenience init(
        modelContainer: ModelContainer,
        launchState: MistiaDataStack.LaunchState? = nil
    ) {
        self.init(
            modelContainer: modelContainer,
            launchState: launchState,
            service: FamilyRemoteService()
        )
    }

    var currentUserID: UUID? {
        currentMembership?.userID
    }

    var currentRole: FamilyRole {
        currentMembership?.role ?? .member
    }

    var currentPolicy: FamilyPermissionPolicy {
        currentMembership?.policy ?? .preset(for: .member)
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

    var activePendingInviteCount: Int {
        invites.filter { $0.status == .pending }.count
    }

    var canCreatePendingInvite: Bool {
        activePendingInviteCount < 2
    }

    var hasCachedRemoteState: Bool {
        family != nil
            || currentMembership != nil
            || !members.isEmpty
            || !invites.isEmpty
            || !permissionGrants.isEmpty
    }

    var operableTargetUserIDs: Set<UUID> {
        guard let currentUserID else { return [] }

        let grantedTargetUserIDs = permissionGrants
            .filter {
                $0.granteeUserID == currentUserID
                    && $0.revokedAt == nil
                    && $0.resourceType == .wallet
                    && $0.permissionScope == .use
            }
            .map(\.ownerUserID)
        return Set(grantedTargetUserIDs).union([currentUserID])
    }

    var viewableTargetUserIDs: Set<UUID> {
        guard let currentUserID else { return [] }

        let viewableMemberIDs = members
            .filter { capabilities(for: $0).canViewTarget }
            .map(\.userID)
        return Set(viewableMemberIDs).union([currentUserID])
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
        return L10n.shared.family.familycontext.viewingValue(String(describing: viewedMember.displayName))
    }

    func bootstrapIfNeeded(sessionStore: SessionStore) async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await refreshIfStale(sessionStore: sessionStore)
    }

    func setModelContainer(_ modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @discardableResult
    func refresh(sessionStore: SessionStore) async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performRefresh(sessionStore: sessionStore)
        }
        refreshTask = task

        let didRefresh = await task.value
        refreshTask = nil
        if didRefresh {
            lastPassiveRefreshCompletedAt = Date()
        }
        return didRefresh
    }

    @discardableResult
    func refreshIfStale(sessionStore: SessionStore) async -> Bool {
        setModelContainer(sessionStore.currentModelContainer)
        restoreCachedStateIfAvailable(sessionStore: sessionStore)

        if let refreshTask {
            return await refreshTask.value
        }

        if didCompletePassiveRefreshRecently {
            return sessionStore.isSignedIn ? hasCachedRemoteState || family != nil : true
        }

        return await refresh(sessionStore: sessionStore)
    }

    private var didCompletePassiveRefreshRecently: Bool {
        guard let lastPassiveRefreshCompletedAt else { return false }
        return Date().timeIntervalSince(lastPassiveRefreshCompletedAt) < Self.passiveRefreshCooldown
    }

    private func performRefresh(sessionStore: SessionStore) async -> Bool {
        setModelContainer(sessionStore.currentModelContainer)
        restoreCachedStateIfAvailable(sessionStore: sessionStore)

        guard sessionStore.isSignedIn else {
            restoreSignedOutLocalState(sessionStore: sessionStore)
            return false
        }

        guard let session = await prepareRemoteSession(using: sessionStore) else {
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await service.fetchState(session: session)
            apply(snapshot: snapshot)
            persistCachedState(currentSnapshot)
            hydrateFamilyAvatars(from: snapshot.members)
            lastErrorMessage = nil

            normalizeActiveContextAfterStateLoad()

            try await refreshAccessibleFinance(
                sessionStore: sessionStore,
                session: session
            )
            try await refreshFamilyNotifications(session: session)
            try await pushPendingNotificationReadState(session: session)
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }

    func refreshNotifications(sessionStore: SessionStore) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            try await refreshFamilyNotifications(session: session)
            try await pushPendingNotificationReadState(session: session)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func pushNotificationReadState(sessionStore: SessionStore) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            try await pushPendingNotificationReadState(session: session)
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func refreshLatest(
        sessionStore: SessionStore,
        source: FamilyRefreshSource
    ) async {
        switch source {
        case .enterFamily:
            guard sessionStore.isAutoSyncEnabled else { return }
            guard !didCompleteLatestRefreshRecently else { return }
            await refreshWithLatestSync(
                sessionStore: sessionStore,
                isManualSync: false
            )
        case .userInitiated:
            await refreshWithLatestSync(
                sessionStore: sessionStore,
                isManualSync: true
            )
        case .postManualSync:
            await refresh(sessionStore: sessionStore)
            lastLatestRefreshCompletedAt = Date()
        }
    }

    private var didCompleteLatestRefreshRecently: Bool {
        guard let lastLatestRefreshCompletedAt else { return false }
        return Date().timeIntervalSince(lastLatestRefreshCompletedAt) < Self.latestRefreshCooldown
    }

    private func didCompleteLatestRefresh(after startDate: Date) -> Bool {
        guard let lastLatestRefreshCompletedAt else { return false }
        return lastLatestRefreshCompletedAt >= startDate
    }

    private func refreshWithLatestSync(
        sessionStore: SessionStore,
        isManualSync: Bool
    ) async {
        guard !isRefreshingLatest else { return }
        guard sessionStore.canPerformRemoteActions else {
            lastErrorMessage = sessionStore.remoteUnavailableReason
            return
        }

        isRefreshingLatest = true
        defer { isRefreshingLatest = false }

        let refreshStartedAt = Date()
        let didSync = await sessionStore.syncNow(isManual: isManualSync)
        if !didSync && sessionStore.isAnySyncInProgress {
            while sessionStore.isAnySyncInProgress {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        guard !didCompleteLatestRefresh(after: refreshStartedAt) else { return }
        guard !Task.isCancelled else { return }
        await refresh(sessionStore: sessionStore)
        lastLatestRefreshCompletedAt = Date()
    }

    func refreshAccessibleFinance(sessionStore: SessionStore) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            try await refreshAccessibleFinance(
                sessionStore: sessionStore,
                session: session
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func deleteFamily(sessionStore: SessionStore) async {
        guard let familyID = family?.id else { return }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            try await service.deleteFamily(familyID: familyID, session: session)
            activeContext = .personalSelf
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func createFamily(
        name: String,
        sessionStore: SessionStore
    ) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await service.createFamily(name: name, session: session)
            apply(snapshot: snapshot)
            lastErrorMessage = nil
            if let familyID = snapshot.family?.id {
                activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
            }
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func joinFamily(
        inviteCode: String,
        sessionStore: SessionStore
    ) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await service.joinInvite(code: inviteCode, session: session)
            apply(snapshot: snapshot)
            lastErrorMessage = nil
            if let familyID = snapshot.family?.id {
                activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
            }
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func handleInviteURL(_ url: URL) -> Bool {
        guard let token = FamilyInviteLinking.token(from: url) else {
            return false
        }

        presentInvite(token: token)
        return true
    }

    func presentInvite(token: String) {
        guard let normalizedToken = FamilyInviteLinking.normalizedToken(token) else {
            return
        }

        UserDefaults.standard.set(normalizedToken, forKey: Self.pendingInviteTokenKey)
        pendingInviteRoute = FamilyInviteRoute(token: normalizedToken)
    }

    func clearPendingInvite() {
        UserDefaults.standard.removeObject(forKey: Self.pendingInviteTokenKey)
        pendingInviteRoute = nil
    }

    func dismissPendingInviteForNow() {
        pendingInviteRoute = nil
    }

    func requestFamilyOverviewPresentation(familyID: UUID? = nil) {
        guard let familyID = familyID ?? family?.id else { return }
        pendingFamilyOverviewRoute = FamilyOverviewPresentationRoute(familyID: familyID)
    }

    func clearFamilyOverviewPresentationRequest() {
        pendingFamilyOverviewRoute = nil
    }

    func previewInvite(
        token: String,
        sessionStore: SessionStore
    ) async throws -> FamilyInvitePreviewRecord {
        let session = try await requireRemoteSession(using: sessionStore)
        return try await service.previewInvite(token: token, session: session)
    }

    func acceptInvite(
        token: String,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await service.acceptInvite(token: token, session: session)
            apply(snapshot: snapshot)
            persistCachedState(currentSnapshot)
            hydrateFamilyAvatars(from: snapshot.members)
            lastErrorMessage = nil
            if let familyID = snapshot.family?.id {
                activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
            }
            UserDefaults.standard.removeObject(forKey: Self.pendingInviteTokenKey)
            await refresh(sessionStore: sessionStore)
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }

    func declineInvite(
        token: String,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            let declinedInvite = try await service.declineInvite(token: token, session: session)
            upsertInvite(declinedInvite)
            lastErrorMessage = nil
            clearPendingInvite()
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }

    func createInvite(
        defaultRole: FamilyRole,
        sessionStore: SessionStore
    ) async -> FamilyInviteRecord? {
        guard let familyID = family?.id else { return nil }
        guard canCreatePendingInvite else {
            lastErrorMessage = L10n.shared.family.familycontext.youCanOnlyHaveUpTo
            return nil
        }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return nil }

        do {
            let invite = try await service.createInvite(
                familyID: familyID,
                defaultRole: defaultRole,
                expiresAt: MistiaCalendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
                session: session
            )
            upsertInvite(invite)
            return invite
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return nil
        }
    }

    func revokeInvite(
        _ invite: FamilyInviteRecord,
        sessionStore: SessionStore
    ) async {
        guard invite.status == .pending else { return }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            let revokedInvite = try await service.revokeInvite(inviteID: invite.id, session: session)
            upsertInvite(revokedInvite)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func updateMember(
        _ member: FamilyMember,
        role: FamilyRole,
        policy: FamilyPermissionPolicy,
        sessionStore: SessionStore
    ) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            try await service.updateMember(
                membershipID: member.membershipID,
                role: role,
                policy: policy,
                session: session
            )
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    @discardableResult
    func requestPermission(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        ownerUserID: UUID,
        scope: MistiaFamilyPermissionScope,
        resourceName: String,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let familyID = family?.id else {
            lastErrorMessage = L10n.shared.family.familycontext.familyDataHasNotLoadedYetSync
            return false
        }
        guard let session = await prepareRemoteSession(using: sessionStore) else {
            lastErrorMessage = L10n.shared.family.familycontext.signInAndEnableCloudSyncTo
            return false
        }

        let requesterName = sessionStore.summary?.displayName
            ?? displayName(for: session.user.id)
            ?? L10n.shared.family.familycontext.aFamilyMember

        let input = FamilyPermissionRequestInput(
            familyID: familyID,
            recipientUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: resourceID,
            permissionScope: scope,
            title: permissionRequestTitle(
                resourceType: resourceType,
                scope: scope
            ),
            body: permissionRequestBody(
                requesterName: requesterName,
                scope: scope,
                resourceName: resourceName
            ),
            message: nil
        )

        do {
            _ = try await service.createFamilyPermissionRequest(input: input, session: session)
            pendingPermissionRequestKeys.insert(
                permissionRequestKey(
                    ownerUserID: ownerUserID,
                    resourceType: resourceType,
                    resourceID: resourceID,
                    scope: scope
                )
            )
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }

    @discardableResult
    func setPermissionGrant(
        granteeUserID: UUID,
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        isGranted: Bool,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let familyID = family?.id else { return false }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return false }

        do {
            let grant = try await service.setPermissionGrant(
                familyID: familyID,
                granteeUserID: granteeUserID,
                ownerUserID: ownerUserID,
                resourceType: resourceType,
                resourceID: resourceID,
                scope: scope,
                isGranted: isGranted,
                session: session
            )
            upsertPermissionGrant(grant)
            lastErrorMessage = nil
            await refresh(sessionStore: sessionStore)
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }

    @discardableResult
    func setFamilyPlanningManager(
        resourceType: MistiaFamilyNotificationResourceType,
        managerUserID: UUID?,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let familyID = family?.id else { return false }
        guard resourceType == .budget || resourceType == .goal else { return false }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return false }

        do {
            let updatedFamily = try await service.setFamilyPlanningManager(
                familyID: familyID,
                resourceType: resourceType,
                managerUserID: managerUserID,
                session: session
            )
            family = updatedFamily
            lastErrorMessage = nil
            await refresh(sessionStore: sessionStore)
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }

    @discardableResult
    func respondToPermissionNotification(
        _ notification: AppNotificationRecord,
        approve: Bool,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let requestID = notification.permissionRequestID else { return false }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return false }

        do {
            _ = try await service.respondFamilyPermissionRequest(
                requestID: requestID,
                approve: approve,
                session: session
            )
            notification.actionState = approve ? .approved : .rejected
            notification.isRead = true
            notification.readAt = notification.readAt ?? .now
            notification.updatedAt = .now
            if notification.source == .family {
                notification.needsReadSync = true
            }
            try? modelContainer.mainContext.save()
            await refresh(sessionStore: sessionStore)
            return true
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return false
        }
    }


    func removeMember(
        _ member: FamilyMember,
        sessionStore: SessionStore
    ) async {
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

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
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
        }
    }

    func transferOwner(
        to member: FamilyMember,
        sessionStore: SessionStore
    ) async {
        guard let familyID = family?.id else { return }
        guard let session = await prepareRemoteSession(using: sessionStore) else { return }

        do {
            try await service.transferOwner(
                familyID: familyID,
                newOwnerMembershipID: member.membershipID,
                session: session
            )
            await refresh(sessionStore: sessionStore)
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
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
        let inviteLinkText = inviteLink(for: invite).absoluteString
        guard let family else {
            return inviteLinkText
        }

        return """
        \(L10n.shared.family.familycontext.youVeBeenInvitedToJoinThe) \(family.name) \(L10n.shared.family.familycontext.onMistia)

        \(L10n.shared.family.familycontext.openTheLinkBelowToJoinNow)

        \(inviteLinkText)
        """
    }

    func inviteLink(for invite: FamilyInviteRecord) -> URL {
        appInviteLink(for: invite)
    }

    func appInviteLink(for invite: FamilyInviteRecord) -> URL {
        FamilyInviteLinking.appInviteURL(token: invite.token ?? invite.code)
    }

    func webInviteLink(for invite: FamilyInviteRecord) -> URL {
        FamilyInviteLinking.webInviteURL(token: invite.token ?? invite.code)
    }

    func walletAccessTargetUserIDs(for member: FamilyMember) -> Set<UUID> {
        Set(
            permissionGrants
                .filter {
                    $0.granteeUserID == member.userID
                        && $0.revokedAt == nil
                        && $0.resourceType == .wallet
                        && $0.permissionScope == .use
                }
                .map(\.ownerUserID)
        )
    }

    func hasPermission(
        granteeUserID: UUID? = nil,
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        guard let ownerUserID else { return false }
        let resolvedGranteeUserID = granteeUserID ?? currentUserID
        guard let resolvedGranteeUserID else { return false }
        if resolvedGranteeUserID == ownerUserID {
            return true
        }

        return permissionGrants.contains {
            $0.revokedAt == nil
                && $0.granteeUserID == resolvedGranteeUserID
                && $0.ownerUserID == ownerUserID
                && $0.resourceType == resourceType
                && $0.permissionScope == scope
                && $0.resourceID == resourceID
        }
    }

    func canUseWallet(
        walletID: UUID,
        ownerUserID: UUID?
    ) -> Bool {
        hasPermission(
            ownerUserID: ownerUserID,
            resourceType: .wallet,
            resourceID: walletID,
            scope: .use
        )
    }

    func canEdit(
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID? = nil
    ) -> Bool {
        hasPermission(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: resourceID,
            scope: .edit
        )
    }

    func canCreate(
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType
    ) -> Bool {
        hasPermission(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: nil,
            scope: .create
        )
    }

    @discardableResult
    func refreshPermissionGrant(
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope,
        sessionStore: SessionStore
    ) async -> Bool {
        guard let ownerUserID else { return false }
        if hasPermission(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: resourceID,
            scope: scope
        ) {
            return true
        }

        guard await refresh(sessionStore: sessionStore) else {
            return false
        }

        return hasPermission(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: resourceID,
            scope: scope
        )
    }

    func hasPendingPermissionRequest(
        ownerUserID: UUID?,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        guard let ownerUserID else { return false }
        if hasPermission(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: resourceID,
            scope: scope
        ) {
            return false
        }
        return pendingPermissionRequestKeys.contains(
            permissionRequestKey(
                ownerUserID: ownerUserID,
                resourceType: resourceType,
                resourceID: resourceID,
                scope: scope
            )
        )
    }

    func displayName(for userID: UUID?) -> String? {
        guard let userID else { return nil }
        return members.first(where: { $0.userID == userID })?.displayName
    }

    func hasSyncedCloudData(userID: UUID?) -> Bool {
        guard let userID else { return false }
        return members.first(where: { $0.userID == userID })?.hasSyncedCloudData == true
    }

    func canRequestSystemCategoryUse(ownerUserID: UUID?) -> Bool {
        guard let currentUserID else { return false }
        return hasSyncedCloudData(userID: currentUserID)
            && hasSyncedCloudData(userID: ownerUserID)
    }


    func clear() {
        activeContext = .personalSelf
        family = nil
        currentMembership = nil
        members = []
        invites = []
        permissionGrants = []
        pendingPermissionRequestKeys = []
        lastErrorMessage = nil
        isRefreshingLatest = false
        avatarHydrationTask?.cancel()
        avatarHydrationTask = nil
    }

    private func apply(snapshot: FamilyStateSnapshot) {
        family = snapshot.family
        currentMembership = snapshot.currentMembership
        members = snapshot.members.map(memberWithCachedAvatar)
        invites = snapshot.invites
        permissionGrants = snapshot.permissionGrants
        removeGrantedPendingPermissionRequests()
    }

    private func restoreSignedOutLocalState(sessionStore: SessionStore) {
        switch sessionStore.activeLocalContext {
        case .guestAttached(let profileID, _):
            if restoreCachedState(profileID: profileID) {
                lastErrorMessage = nil
            } else {
                clear()
            }
        case .guestUnbound, .authenticated, nil:
            clear()
        }
    }

    private func restoreCachedStateIfAvailable(sessionStore: SessionStore) {
        guard !hasCachedRemoteState,
              let profileID = sessionStore.activeLocalProfileID else {
            return
        }

        _ = restoreCachedState(profileID: profileID)
    }

    private func normalizeActiveContextAfterStateLoad() {
        if let familyID = family?.id,
           activeContext.scope == .familyHome(familyID: familyID) {
            activeContext = FamilyContext(scope: .familyHome(familyID: familyID))
        } else if case .member(let userID) = activeContext.scope,
                  !members.contains(where: { $0.userID == userID }) {
            activeContext = .personalSelf
        } else if family == nil {
            activeContext = .personalSelf
        }
    }

    private func persistCachedState(_ snapshot: FamilyStateSnapshot) {
        guard let cacheURL = activeFamilyCacheURL() else { return }
        do {
            let data = try JSONEncoder.mistiaSyncEncoder.encode(snapshot)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
    }

    private var currentSnapshot: FamilyStateSnapshot {
        FamilyStateSnapshot(
            family: family,
            currentMembership: currentMembership,
            members: members,
            invites: invites,
            permissionGrants: permissionGrants
        )
    }

    private func memberWithCachedAvatar(_ member: FamilyMember) -> FamilyMember {
        var resolvedMember = member
        if let cachedAvatarURL = MistiaProfileAvatarCache.cachedAvatarURL(for: member.userID) {
            resolvedMember.avatarURL = cachedAvatarURL
        } else if member.avatarURL?.isFileURL == true,
                  let avatarURL = member.avatarURL,
                  !FileManager.default.fileExists(atPath: avatarURL.path) {
            resolvedMember.avatarURL = nil
        }
        return resolvedMember
    }

    private func hydrateFamilyAvatars(from remoteMembers: [FamilyMember]) {
        let membersToCache = remoteMembers.filter { member in
            guard let avatarURL = member.avatarURL else { return false }
            return !avatarURL.isFileURL
        }
        guard !membersToCache.isEmpty else { return }

        avatarHydrationTask?.cancel()
        avatarHydrationTask = Task { [weak self] in
            for member in membersToCache {
                guard !Task.isCancelled else { return }
                guard let cachedURL = await MistiaProfileAvatarCache.cacheRemoteAvatarIfNeeded(
                    from: member.avatarURL,
                    for: member.userID
                ) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                self?.updateCachedAvatar(cachedURL, for: member.userID)
            }
        }
    }

    private func updateCachedAvatar(_ avatarURL: URL, for userID: UUID) {
        guard let memberIndex = members.firstIndex(where: { $0.userID == userID }),
              members[memberIndex].avatarURL?.absoluteString != avatarURL.absoluteString else {
            return
        }

        members[memberIndex].avatarURL = avatarURL
        persistCachedState(currentSnapshot)
    }

    private func restoreCachedState(profileID: UUID) -> Bool {
        guard let cacheURL = familyCacheURL(profileID: profileID),
              let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder.mistiaSyncDecoder.decode(
                FamilyStateSnapshot.self,
                from: data
              ) else {
            return false
        }

        apply(snapshot: snapshot)
        normalizeActiveContextAfterStateLoad()
        return true
    }

    private func activeFamilyCacheURL() -> URL? {
        guard let descriptor = launchState?.activeProfileDescriptor else { return nil }
        return launchState?.familyCacheURL(for: descriptor)
    }

    private func familyCacheURL(profileID: UUID) -> URL? {
        guard let descriptor = launchState?.profileDescriptors.first(where: { $0.id == profileID }) else {
            return nil
        }
        return launchState?.familyCacheURL(for: descriptor)
    }

    private func refreshAccessibleFinance(
        sessionStore: SessionStore,
        session: SupabaseAuthSession
    ) async throws {
        let accessibleUserIDs = Array(viewableTargetUserIDs.union(operableTargetUserIDs))
        guard !accessibleUserIDs.isEmpty else { return }

        let financeSnapshot = try await service.fetchAccessibleFinanceSnapshot(
            userIDs: accessibleUserIDs,
            session: session
        )
        let reconciledFinanceSnapshot = MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
            financeSnapshot
        )
        let protectedRecordIDs = sessionStore.protectedQueuedRecordIDs()

        let nonTransactionSnapshot = MistiaRemoteSnapshot(
            wallets: reconciledFinanceSnapshot.wallets,
            creditCardProfiles: reconciledFinanceSnapshot.creditCardProfiles,
            categories: reconciledFinanceSnapshot.categories,
            transactions: [],
            budgetPlans: reconciledFinanceSnapshot.budgetPlans,
            savingsGoals: reconciledFinanceSnapshot.savingsGoals,
            recurringBillPlans: reconciledFinanceSnapshot.recurringBillPlans,
            installmentPlans: reconciledFinanceSnapshot.installmentPlans,
            dueOccurrences: reconciledFinanceSnapshot.dueOccurrences
        )

        try MistiaSyncLocalStore.applySnapshotIncrementally(
            nonTransactionSnapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: protectedRecordIDs,
            preserveLocalNewerRows: true,
            familyCategoryScopedTo: session.user.id,
            familyCategoryPruneOwnerIDs: Set(accessibleUserIDs).subtracting([session.user.id]),
            in: modelContainer
        )
        try MistiaSyncLocalStore.mergeAccessibleTransactions(
            reconciledFinanceSnapshot.transactions,
            protectedRecordIDs: protectedRecordIDs,
            familyCategoryScopedTo: session.user.id,
            in: modelContainer
        )
    }

    private func refreshFamilyNotifications(session: SupabaseAuthSession) async throws {
        guard MistiaNotificationPreferences.familyInboxSyncEnabled() else { return }

        let remoteRows = try await service.fetchFamilyNotifications(session: session)
        try MistiaNotificationStore.applyRemoteNotifications(
            remoteRows,
            currentUserID: session.user.id,
            in: modelContainer.mainContext
        )
    }

    private func pushPendingNotificationReadState(session: SupabaseAuthSession) async throws {
        let context = modelContainer.mainContext
        let ids = try MistiaNotificationStore.pendingReadSyncIDs(
            for: session.user.id,
            in: context
        )
        guard !ids.isEmpty else { return }

        try await service.markFamilyNotificationsRead(ids: ids, session: session)
        try MistiaNotificationStore.clearReadSyncFlags(ids: ids, in: context)
    }

    private func prepareRemoteSession(
        using sessionStore: SessionStore
    ) async -> SupabaseAuthSession? {
        do {
            let session = try await sessionStore.prepareRemoteSession()
            lastErrorMessage = nil
            return session
        } catch {
            lastErrorMessage = visibleErrorMessage(for: error, sessionStore: sessionStore)
            return nil
        }
    }

    private func requireRemoteSession(
        using sessionStore: SessionStore
    ) async throws -> SupabaseAuthSession {
        if let session = await prepareRemoteSession(using: sessionStore) {
            return session
        }

        throw SupabaseServiceError.serverMessage(
            lastErrorMessage
                ?? L10n.shared.family.familycontext.canTCheckThisInviteBecauseThe
        )
    }

    private func visibleErrorMessage(
        for error: Error,
        sessionStore: SessionStore
    ) -> String {
        if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
            return remoteUnavailableReason
        }

        return error.localizedDescription
    }

    private func upsertInvite(_ invite: FamilyInviteRecord) {
        if let index = invites.firstIndex(where: { $0.id == invite.id }) {
            invites[index] = invite
        } else {
            invites.insert(invite, at: 0)
        }
    }

    private func upsertPermissionGrant(_ grant: FamilyPermissionGrantRecord) {
        if let index = permissionGrants.firstIndex(where: { $0.id == grant.id }) {
            permissionGrants[index] = grant
        } else if grant.revokedAt == nil {
            permissionGrants.append(grant)
        }
        removeGrantedPendingPermissionRequests()
    }

    private func permissionRequestKey(
        ownerUserID: UUID,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope
    ) -> FamilyPendingPermissionRequestKey {
        FamilyPendingPermissionRequestKey(
            ownerUserID: ownerUserID,
            resourceTypeRawValue: resourceType.rawValue,
            resourceID: resourceID,
            scopeRawValue: scope.rawValue
        )
    }

    private func removeGrantedPendingPermissionRequests() {
        guard let currentUserID else { return }
        for grant in permissionGrants where grant.revokedAt == nil && grant.granteeUserID == currentUserID {
            guard let resourceType = grant.resourceType,
                  let scope = grant.permissionScope else { continue }
            pendingPermissionRequestKeys.remove(
                permissionRequestKey(
                    ownerUserID: grant.ownerUserID,
                    resourceType: resourceType,
                    resourceID: grant.resourceID,
                    scope: scope
                )
            )
        }
    }

    private func permissionRequestTitle(
        resourceType: MistiaFamilyNotificationResourceType,
        scope: MistiaFamilyPermissionScope
    ) -> String {
        let action = scope.localizedActionName
        let resource = resourceType.localizedName
        
        return L10n.shared.family.familycontext.requestToValueValue(String(describing: action), String(describing: resource))
    }

    private func permissionRequestBody(
        requesterName: String,
        scope: MistiaFamilyPermissionScope,
        resourceName: String
    ) -> String {
        let action = scope.localizedActionName
        
        return L10n.shared.family.familycontext.valueWantsToValueYourValue(String(describing: requesterName), String(describing: action), String(describing: resourceName))
    }
}
