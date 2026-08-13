import SwiftData
import XCTest
@testable import Mistia

@MainActor
final class FamilyPermissionResolutionTests: XCTestCase {
    func testInvestmentHubReconcilesApprovedViewGrantAndDataWhenOpened() throws {
        let source = try featureSource(relativePath: "Investment/InvestmentHubView.swift")
        XCTAssertTrue(
            source.contains(".task(id: ownerUserID)"),
            "Investment Hub must reconcile remotely approved access when the viewed owner changes."
        )

        let body = try functionBody(named: "refreshInvestmentAccessAndData", in: source)
        assertMarker(
            "await familyContextStore.refreshPermissionGrant(",
            appearsBefore: "await familyContextStore.refreshAccessibleFinance(",
            in: body,
            message: "Investment Hub must refresh the View grant before downloading the owner's Investment data."
        )
    }

    func testInvestmentHubRoutesRestrictedActionsThroughMatchingPermissionPrompts() throws {
        let source = try featureSource(relativePath: "Investment/InvestmentHubView.swift")
        let expectations: [(function: String, scope: String, destination: String)] = [
            ("openAsset", "presentPermissionPrompt(scope: .edit)", "activeSheet = .asset(asset.id)"),
            ("openTrade", "presentPermissionPrompt(scope: .edit)", "activeSheet = .trade(kind: trade.kind, id: trade.id)"),
            ("openNewTrade", "presentPermissionPrompt(scope: .create)", "activeSheet = .trade(kind: kind, id: nil)"),
            ("openInvestmentWallet", "presentPermissionPrompt(scope: .edit)", "activeSheet = .wallet"),
            ("sheetView", "if canEdit", "InvestmentWalletTransferSheet(ownerUserID: ownerUserID)")
        ]

        for expectation in expectations {
            let body = try functionBody(named: expectation.function, in: source)
            assertMarker(
                expectation.scope,
                appearsBefore: expectation.destination,
                in: body,
                message: "Investment Hub \(expectation.function) must request the matching permission before opening its destination."
            )
        }
    }

    func testInvestmentHubContextMenusExposeIconLabeledManagementActions() throws {
        let source = try featureSource(relativePath: "Investment/InvestmentHubView.swift")

        XCTAssertTrue(source.contains("Label(L10n.investment.lotHistory.title, systemImage: \"clock.arrow.circlepath\")"))
        XCTAssertTrue(source.contains("Label(L10n.management.management.edit, systemImage: \"pencil\")"))
        XCTAssertTrue(source.contains("Label(L10n.common.archive, systemImage: \"archivebox\")"))
        XCTAssertTrue(source.contains("Label(L10n.investment.trade.deleteAction, systemImage: \"trash\")"))
        XCTAssertTrue(source.contains("Label(permissionActionTitle(.edit), systemImage: \"lock.open\")"))
    }

    func testManagementInvestmentWalletRequiresInvestmentEditPermissionBeforeOpening() throws {
        let source = try featureSource(relativePath: "Management/ManagementView.swift")
        let openBody = try functionBody(named: "openInvestmentWallet", in: source)
        assertMarker(
            "guard canManageInvestment(ownerUserID: ownerUserID)",
            appearsBefore: "investmentWalletTarget = ManagementInvestmentWalletTarget(ownerUserID: ownerUserID)",
            in: openBody,
            message: "Management must require Investment edit access before opening the Investment Wallet transfer sheet."
        )

        let promptBody = try functionBody(named: "presentInvestmentManagementPermissionPrompt", in: source)
        XCTAssertTrue(promptBody.contains("resourceType: .investment"))
        XCTAssertTrue(promptBody.contains("scope: .edit"))
        assertMarker(
            "showInvestmentManagementPermissionPrompt(",
            appearsBefore: "await familyContextStore.resolvePendingPermissionBeforePrompt(",
            in: promptBody,
            message: "Management must show the cached pending Investment management request before refreshing it."
        )
        XCTAssertTrue(
            source.contains(".sheet(item: investmentWalletTargetBinding)"),
            "The Investment Wallet sheet binding must reject a target whose management permission was revoked."
        )
    }

    func testPermissionSurfacesPresentCachedPendingStateBeforeRefreshing() throws {
        let directRefresh = "await familyContextStore.resolvePendingPermissionBeforePrompt("
        let expectations: [(file: String, function: String, presentation: String, refresh: String)] = [
            ("Overview/OverviewView.swift", "presentTransactionEditPermissionPrompt", "showTransactionEditPermissionPrompt(", directRefresh),
            ("Overview/OverviewView.swift", "presentEventPermissionPrompt", "showEventPermissionPrompt(", directRefresh),
            ("Planning/PlanningView.swift", "presentCreditCardWalletPermissionPrompt", "walletPermissionPrompt = prompt", "await resolvePendingCreditCardWalletPermissionBeforePrompt("),
            ("Planning/PlanningView.swift", "presentEditPermissionPrompt", "showEditPermissionPrompt(", directRefresh),
            ("Planning/PlanningView.swift", "presentCreatePermissionPrompt", "showCreatePermissionPrompt(", directRefresh),
            ("Management/ManagementView.swift", "presentWalletPermissionPrompt", "walletPermissionPrompt = prompt", "await resolvePendingWalletPermissionBeforePrompt("),
            ("Management/ManagementView.swift", "presentCreatePermissionPrompt", "showCreatePermissionPrompt(", directRefresh),
            ("Management/ManagementView.swift", "presentCategoryEditPermissionPrompt", "showCategoryEditPermissionPrompt(", directRefresh),
            ("Management/ManagementView.swift", "presentCategoryCreatePermissionPrompt", "showCategoryCreatePermissionPrompt(", directRefresh),
            ("Transactions/TransactionsView.swift", "presentEventPermissionPrompt", "showEventPermissionPrompt(", directRefresh),
            ("Transactions/TransactionsView.swift", "presentTransactionEditPermissionPrompt", "showTransactionEditPermissionPrompt(", directRefresh),
            ("Transactions/TransactionEditorSheet.swift", "presentTransferPermissionPrompt", "transferPermissionPrompt = prompt", directRefresh),
            ("Transactions/SettlementSheets.swift", "guardSharedExpenseEventPermission", "alertMessage =", directRefresh),
            ("Investment/InvestmentHubView.swift", "presentPermissionPrompt", "activeAlert = InvestmentHubAlert(", directRefresh),
            ("Management/ManagementView.swift", "presentInvestmentManagementPermissionPrompt", "showInvestmentManagementPermissionPrompt(", directRefresh)
        ]

        for expectation in expectations {
            let source = try featureSource(relativePath: expectation.file)
            let body = try functionBody(named: expectation.function, in: source)
            assertMarker(
                expectation.presentation,
                appearsBefore: expectation.refresh,
                in: body,
                message: "\(expectation.file) \(expectation.function) must present cached pending state before refreshing cloud permissions."
            )
        }
    }

    func testPermissionSubmissionHandlersShowSendingFeedbackBeforeAwaitingRemoteRequest() throws {
        let expectations: [(file: String, function: String, feedback: String)] = [
            ("Overview/OverviewView.swift", "showEventPermissionPrompt", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Overview/OverviewView.swift", "sendPermissionRequest", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Planning/PlanningView.swift", "resolvePermissionPromptAction", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Planning/PlanningView.swift", "sendPermissionRequest", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Management/ManagementView.swift", "resolvePermissionPromptAction", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Management/ManagementView.swift", "sendPermissionRequest", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Transactions/TransactionsView.swift", "showEventPermissionPrompt", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Transactions/TransactionsView.swift", "showTransactionEditPermissionPrompt", "L10n.shared.family.permissionRequest.sendingTitle"),
            ("Transactions/TransactionEditorSheet.swift", "requestTransferCreatePermission", "L10n.shared.family.permissionRequest.sendingMessage"),
            ("Investment/InvestmentHubView.swift", "requestPermission", "L10n.shared.family.permissionRequest.sendingTitle")
        ]

        for expectation in expectations {
            let source = try featureSource(relativePath: expectation.file)
            let body = try functionBody(named: expectation.function, in: source)
            assertMarker(
                expectation.feedback,
                appearsBefore: "await familyContextStore.requestPermission(",
                in: body,
                message: "\(expectation.file) \(expectation.function) must show sending feedback before awaiting the remote request."
            )
        }
    }

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

    private func featureSource(relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Mistia")
            .appendingPathComponent("Features")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func functionBody(named functionName: String, in source: String) throws -> String {
        let marker = "private func \(functionName)("
        guard let range = source.range(of: marker) else {
            XCTFail("Missing \(marker)")
            return ""
        }
        let tail = String(source[range.lowerBound...])
        let searchStart = tail.index(after: tail.startIndex)
        guard let nextFunction = tail.range(
            of: "\n    private func ",
            options: [],
            range: searchStart..<tail.endIndex
        ) else {
            return tail
        }
        return String(tail[..<nextFunction.lowerBound])
    }

    private func assertMarker(
        _ firstMarker: String,
        appearsBefore secondMarker: String,
        in source: String,
        message: String
    ) {
        guard let firstRange = source.range(of: firstMarker) else {
            XCTFail("\(message) Missing first marker: \(firstMarker)")
            return
        }
        guard let secondRange = source.range(of: secondMarker) else {
            XCTFail("\(message) Missing second marker: \(secondMarker)")
            return
        }
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound, message)
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
    func upsertOverviewSectionConfig(
        _ items: [RemoteOverviewSectionItemConfig],
        modifiedAt: Date,
        session: SupabaseAuthSession
    ) async throws -> RemoteUserProfile {
        RemoteUserProfile(
            userID: session.user.id,
            displayName: session.user.userMetadata?.displayName ?? "Mistia",
            avatarURL: nil,
            birthday: nil,
            overviewSectionConfig: items,
            overviewSectionConfigUpdatedAt: modifiedAt,
            createdAt: .now,
            updatedAt: .now
        )
    }
    func uploadAvatarImageData(_ data: Data, session: SupabaseAuthSession) async throws -> URL {
        URL(string: "https://example.com/avatar.jpg")!
    }
}
