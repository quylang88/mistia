import SwiftData
import SwiftUI

private enum ManagementNavigationDestination: String, Identifiable {
    case authPlaceholder
    case settings
    case family
    case backupRestore
    case archivedItems
    case familyOverview

    var id: String { rawValue }
}

private struct ManagementInfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ManagementPermissionPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
}

private struct ManagementWalletPermissionPrompt: Identifiable {
    let id = UUID()
    let walletID: UUID
    let walletName: String
    let ownerUserID: UUID
    let title: String
    let message: String
}

private struct ManagementFamilyOwnerConflictAlert: Identifiable {
    let entity: MistiaSyncEntity
    let recordID: UUID

    var id: String {
        FamilyOwnerPushConflict.key(entity: entity, recordID: recordID)
    }
}

private struct ManagementSystemCategoryUseRequestTarget: Identifiable {
    let id = UUID()
    let ownerUserID: UUID
}

private enum ManagementAlertPresentation: Identifiable {
    case info(ManagementInfoAlert)
    case permission(ManagementPermissionPrompt)
    case wallet(ManagementWalletPermissionPrompt)
    case familyOwnerConflict(ManagementFamilyOwnerConflictAlert)

    var id: String {
        switch self {
        case .info(let alert):
            alert.id.uuidString
        case .permission(let prompt):
            prompt.id.uuidString
        case .wallet(let prompt):
            prompt.id.uuidString
        case .familyOwnerConflict(let alert):
            alert.id
        }
    }

    var title: String {
        switch self {
        case .info(let alert):
            alert.title
        case .permission(let prompt):
            prompt.title
        case .wallet(let prompt):
            prompt.title
        case .familyOwnerConflict:
            L10n.shared.sync.familyOwnerPushConflict.alertTitle
        }
    }

    var message: String {
        switch self {
        case .info(let alert):
            alert.message
        case .permission(let prompt):
            prompt.message
        case .wallet(let prompt):
            prompt.message
        case .familyOwnerConflict:
            L10n.shared.sync.familyOwnerPushConflict.alertMessage
        }
    }
}

private struct ManagementRenderSnapshot {
    let activeWallets: [LedgerWallet]
    let walletBalancesByID: [UUID: Int64]
    let visibleCategorySections: [TransactionCategoryGroupSection]
}

private struct ManagementRenderSnapshotCache {
    let key: ManagementRenderSnapshotCacheKey
    let snapshot: ManagementRenderSnapshot
}

private struct ManagementRenderSnapshotCacheKey: Hashable {
    let selectedCategoryKindRawValue: String
    let activeScope: FamilyContext.Scope
    let selectedSubjectUserID: UUID?
    let currentUserID: UUID?
    let activeLocalProfileUserID: UUID?
    let signedInUserID: UUID?
    let familyID: UUID?
    let familyAccessSignature: Int
    let walletSignature: MistiaCollectionChangeSignature
    let categorySignature: MistiaCollectionChangeSignature
    let transactionSignature: MistiaCollectionChangeSignature
    let settlementGroupSignature: MistiaCollectionChangeSignature
    let ownershipSignature: MistiaCollectionChangeSignature
    let auditSignature: MistiaCollectionChangeSignature
}

private struct ManagementProfileRowPresentation {
    let initials: String
    let avatarURL: URL?
    let displayName: String
    let email: String
    let opensOwnProfile: Bool
}

struct ManagementView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState

    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var currencyRateMode = MistiaCurrencyRateMode.automatic.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = ""
    @AppStorage(MistiaCurrencySettings.StorageKey.cachedRatesData) private var cachedCurrencyRatesData = Data()

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> {
        $0.entryStatusRawValue == "posted" && !$0.isArchived && $0.deletedAt == nil
    })
    private var postedTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<SettlementGroup> { $0.deletedAt == nil })
    private var storedSettlementGroups: [SettlementGroup]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @Query private var transactionAuditRecords: [TransactionAuditRecord]

    @State private var destination: ManagementNavigationDestination?
    @State private var walletEditorTarget: ManagementWalletEditorTarget?
    @State private var categoryEditorTarget: ManagementCategoryEditorTarget?
    @State private var selectedCategoryKind: TransactionCategoryKind = .expense
    @State private var expandedCategoryParentIDs: Set<UUID> = []
    @State private var infoAlert: ManagementInfoAlert?
    @State private var permissionPrompt: ManagementPermissionPrompt?
    @State private var walletPermissionPrompt: ManagementWalletPermissionPrompt?
    @State private var familyOwnerConflictAlert: ManagementFamilyOwnerConflictAlert?
    @State private var memberViewingExitPrompt: FamilyMemberViewingExitPrompt?
    @State private var renderSnapshotCache: ManagementRenderSnapshotCache?
    @State private var quickCreateHideRequestID = UUID()

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private var accentPurple: Color {
        MistiaAccent.purple.color
    }

    private var appExchangeRates: [MistiaExchangeRate] {
        _ = currencyRateMode
        _ = manualJPYToVNDRate
        _ = cachedCurrencyRatesData
        return MistiaCurrencySettings.rates()
    }

    private let profileLeadingVisualWidth: CGFloat = 50
    private let profileRowSpacing: CGFloat = 20

    private var renderSnapshot: ManagementRenderSnapshot {
        let scopeSnapshot = FamilyScopedData.ScopeSnapshot(
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore,
            entities: [.wallet, .category, .settlementGroup, .transaction]
        )
        let visibleWallets = FamilyScopedData.visible(
            storedWallets,
            entity: .wallet,
            scopeSnapshot: scopeSnapshot
        )
        let visibleCategories = FamilyScopedData.visible(
            storedCategories,
            entity: .category,
            scopeSnapshot: scopeSnapshot
        )
        let visibleSettlementGroups = FamilyScopedData.visible(
            storedSettlementGroups,
            entity: .settlementGroup,
            scopeSnapshot: scopeSnapshot
        )
        let archivedEventIDs = SettlementLogic.archivedSharedExpenseEventIDs(
            from: visibleSettlementGroups.map(\.recordSnapshot)
        )
        let visiblePostedTransactions = FamilyScopedData.visibleTransactionsForHistory(
            postedTransactions,
            audits: transactionAuditRecords,
            scopeSnapshot: scopeSnapshot,
            archivedEventIDs: archivedEventIDs
        )
        let activeWallets = visibleWallets
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
        let transactionSnapshots = visiblePostedTransactions.map(\.planningRecordSnapshot)
        let activeWalletSnapshots = activeWallets.map {
            TransactionWalletSnapshot(
                id: $0.id,
                kind: $0.kind,
                openingBalanceMinor: $0.openingBalanceMinor
            )
        }
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: activeWalletSnapshots,
            records: transactionSnapshots
        )

        var balancesByID: [UUID: Int64] = [:]
        for (wallet, walletSnapshot) in zip(activeWallets, activeWalletSnapshots) {
            if wallet.kind == .creditCard, let profile = wallet.creditCardProfile {
                balancesByID[wallet.id] = TransactionLogic.creditCardBalance(
                    creditLimitMinor: profile.creditLimitMinor,
                    wallet: walletSnapshot,
                    balanceIndex: balanceIndex
                ).currentDebtMinor
            } else {
                balancesByID[wallet.id] = balanceIndex.balance(for: walletSnapshot)
            }
        }

        return ManagementRenderSnapshot(
            activeWallets: activeWallets,
            walletBalancesByID: balancesByID,
            visibleCategorySections: MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: selectedCategoryKind,
                includeArchived: false,
                includeEmptyParents: true
            )
        )
    }

    private func cachedRenderSnapshot(for key: ManagementRenderSnapshotCacheKey) -> ManagementRenderSnapshot {
        if let renderSnapshotCache, renderSnapshotCache.key == key {
            return renderSnapshotCache.snapshot
        }

        return renderSnapshot
    }

    private func refreshRenderSnapshotCache(
        for key: ManagementRenderSnapshotCacheKey,
        snapshot: ManagementRenderSnapshot
    ) {
        renderSnapshotCache = ManagementRenderSnapshotCache(
            key: key,
            snapshot: snapshot
        )
    }

    private var renderSnapshotCacheKey: ManagementRenderSnapshotCacheKey {
        ManagementRenderSnapshotCacheKey(
            selectedCategoryKindRawValue: selectedCategoryKind.rawValue,
            activeScope: familyContextStore.activeContext.scope,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.signedInUserID,
            familyID: familyContextStore.family?.id,
            familyAccessSignature: familyAccessSignature,
            walletSignature: MistiaCollectionChangeSignature.make(
                storedWallets,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            categorySignature: MistiaCollectionChangeSignature.make(
                storedCategories,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            transactionSignature: MistiaCollectionChangeSignature.make(
                postedTransactions,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            settlementGroupSignature: MistiaCollectionChangeSignature.make(
                storedSettlementGroups,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            ownershipSignature: MistiaCollectionChangeSignature.make(
                ownershipScopes,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            ),
            auditSignature: MistiaCollectionChangeSignature.make(
                transactionAuditRecords,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            )
        )
    }

    private var familyAccessSignature: Int {
        var hasher = Hasher()
        hasher.combine(familyContextStore.currentMembership?.id)
        hasher.combine(familyContextStore.currentMembership?.updatedAt.timeIntervalSince1970)
        hasher.combine(familyContextStore.members.count)
        for member in familyContextStore.members {
            hasher.combine(member.membershipID)
            hasher.combine(member.userID)
            hasher.combine(member.role.rawValue)
            hasher.combine(member.hasSyncedCloudData)
        }
        hasher.combine(familyContextStore.permissionGrants.count)
        for grant in familyContextStore.permissionGrants {
            hasher.combine(grant.id)
            hasher.combine(grant.granteeUserID)
            hasher.combine(grant.ownerUserID)
            hasher.combine(grant.resourceTypeRawValue)
            hasher.combine(grant.resourceID)
            hasher.combine(grant.permissionScopeRawValue)
            hasher.combine(grant.updatedAt.timeIntervalSince1970)
            hasher.combine(grant.revokedAt?.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    private var hasFamilyProfile: Bool {
        familyContextStore.family != nil && !familyContextStore.members.isEmpty
    }

    private var shouldRefreshFamilyBeforeOpening: Bool {
        familyContextStore.family != nil && familyContextStore.members.count >= 2
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var categoryOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
    }

    private var selectedSubjectUserID: UUID? {
        familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
    }

    private var canOpenOwnProfile: Bool {
        !familyContextStore.isViewingOtherMemberContext
    }

    private var profileRowPresentation: ManagementProfileRowPresentation? {
        if let memberToolbar = familyContextStore.memberViewingToolbarPresentation {
            return ManagementProfileRowPresentation(
                initials: memberToolbar.initials,
                avatarURL: familyContextStore.viewedMember?.avatarURL,
                displayName: memberToolbar.displayName,
                email: FamilyMemberViewingToolbarLogic.maskedEmail(nil),
                opensOwnProfile: false
            )
        }

        guard let summary = sessionStore.summary else {
            return nil
        }

        return ManagementProfileRowPresentation(
            initials: summary.initials,
            avatarURL: summary.avatarURL,
            displayName: summary.displayName,
            email: summary.email,
            opensOwnProfile: true
        )
    }

    var body: some View {
        let snapshotKey = renderSnapshotCacheKey
        let renderSnapshot = cachedRenderSnapshot(for: snapshotKey)
        let memberToolbar = familyContextStore.memberViewingToolbarPresentation
        let exchangeRateIndex = MistiaExchangeRateIndex(rates: appExchangeRates)

        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .muted,
                title: L10n.management.management.manage,
                embedsInNavigationStack: false,
                showsLeadingAvatar: memberToolbar != nil,
                leadingInitials: memberToolbar?.initials ?? "MI",
                leadingAvatarURL: memberToolbar != nil ? familyContextStore.viewedMember?.avatarURL : nil,
                leadingAccessibilityLabel: memberToolbar?.accessibilityLabel,
                leadingAvatarAttentionPulse: memberToolbar != nil,
                trailingSystemImage: "gearshape",
                onLeadingTap: {
                    if let memberToolbar {
                        memberViewingExitPrompt = FamilyMemberViewingExitPrompt(presentation: memberToolbar)
                    }
                },
                onTrailingTap: { destination = .settings },
                contentSpacing: 20,
                titleDisplayMode: .large
            ) {
                profileSection
                walletsSection(
                    activeWallets: renderSnapshot.activeWallets,
                    walletBalancesByID: renderSnapshot.walletBalancesByID,
                    primaryCurrencyCode: primaryCurrencyCode,
                    exchangeRateIndex: exchangeRateIndex
                )
                categoriesSection(visibleCategorySections: renderSnapshot.visibleCategorySections)
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .authPlaceholder:
                    ManagementAccountView()
                case .settings:
                    SettingsView()
                case .family:
                    FamilyManagementView()
                case .backupRestore:
                    ManagementBackupRestoreView()
                case .archivedItems:
                    ManagementArchivedItemsView()
                case .familyOverview:
                    FamilyOverviewScreen()
                }
            }
        }
        .familyMemberViewingExitAlert(
            prompt: $memberViewingExitPrompt,
            familyContextStore: familyContextStore
        )
        .sheet(item: $walletEditorTarget) { target in
            ManagementWalletEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $categoryEditorTarget) { target in
            ManagementCategoryEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        familyOwnerConflictAlert = nil
                        walletPermissionPrompt = nil
                        permissionPrompt = nil
                        infoAlert = nil
                    }
                }
            ),
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .info:
                Button(L10n.common.ok) {}
            case .familyOwnerConflict(let conflict):
                Button(L10n.common.ok) {
                    Task { @MainActor in
                        await sessionStore.discardFamilyOwnerPushConflictAndRefresh(
                            entity: conflict.entity,
                            recordID: conflict.recordID,
                            familyContextStore: familyContextStore
                        )
                        familyOwnerConflictAlert = nil
                    }
                }
            case .permission(let prompt):
                Button(prompt.actionTitle) {
                    prompt.action()
                }
                Button(L10n.common.cancel, role: .cancel) {}
            case .wallet(let prompt):
                if shouldShowWalletPermissionAction(for: prompt, scope: .use) {
                    Button(walletPermissionActionTitle(for: prompt, scope: .use)) {
                        requestWalletPermission(prompt, scope: .use)
                    }
                }
                if shouldShowWalletPermissionAction(for: prompt, scope: .edit) {
                    Button(walletPermissionActionTitle(for: prompt, scope: .edit)) {
                        requestWalletPermission(prompt, scope: .edit)
                    }
                }
                Button(L10n.common.cancel, role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: destination, initial: true) { _, newValue in
            uiState.requestQuickCreateHidden(newValue != nil, id: quickCreateHideRequestID)
        }
        .onChange(of: uiState.managementNavigationRequest?.id, initial: true) { _, _ in
            handleManagementNavigationRequest()
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: quickCreateHideRequestID)
        }
        .task(id: snapshotKey) {
            refreshRenderSnapshotCache(for: snapshotKey, snapshot: renderSnapshot)
        }
    }

    private func handleManagementNavigationRequest() {
        guard let request = uiState.managementNavigationRequest else { return }

        switch request.destination {
        case .backupRestore:
            destination = .backupRestore
        case .archivedItems:
            destination = .archivedItems
        case .familyOverview:
            familyContextStore.activateFamilyHome()
            destination = .familyOverview
        }

        uiState.clearManagementNavigationRequest(id: request.id)
    }

    private var profileSection: some View {
        VStack(spacing: 12) {
            if let profileRow = profileRowPresentation {
                ManagementCard(tint: cardTint) {
                    VStack(spacing: 0) {
                        Button {
                            guard profileRow.opensOwnProfile else { return }
                            destination = .authPlaceholder
                        } label: {
                            HStack(spacing: profileRowSpacing) {
                                MistiaAvatarBadge(
                                    initials: profileRow.initials,
                                    avatarURL: profileRow.avatarURL,
                                    size: 50,
                                    showsStatus: false
                                )
                                .frame(width: profileLeadingVisualWidth, height: 50)
                                .opacity(profileRow.opensOwnProfile ? 1 : 0.72)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(profileRow.displayName)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(profileRow.opensOwnProfile ? .primary : .secondary)

                                    Text(profileRow.email)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .opacity(profileRow.opensOwnProfile ? 1 : 0.6)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .opacity(profileRow.opensOwnProfile ? 1 : 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                        .disabled(!profileRow.opensOwnProfile)

                        Divider()
                            .padding(.leading, 52)
                            .padding(.trailing, 0)

                        Button(action: openFamily) {
                            HStack(spacing: profileRowSpacing) {
                                if hasFamilyProfile {
                                    HStack(spacing: -12) {
                                        ForEach(Array(familyContextStore.members.prefix(3).enumerated()), id: \.element.membershipID) { index, member in
                                            MistiaAvatarBadge(
                                                initials: String(member.displayName.prefix(2)).uppercased(),
                                                avatarURL: member.avatarURL,
                                                size: 34,
                                                showsStatus: false
                                            )
                                            .overlay {
                                                Circle().stroke(
                                                    colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white,
                                                    lineWidth: 2
                                                )
                                            }
                                            .zIndex(Double(familyContextStore.members.count - index))
                                        }
                                    }
                                    .frame(width: profileLeadingVisualWidth, height: 44, alignment: .leading)
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(MistiaAccent.lightPurple.color.opacity(0.24))

                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(MistiaAccent.lightPurple.color)
                                    }
                                    .frame(width: profileLeadingVisualWidth, height: 44)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.management.management.family)
                                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }

                                Spacer(minLength: 12)

                                Text(familyContextStore.family?.name ?? L10n.management.management.none)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                        .disabled(!sessionStore.canPerformRemoteActions)
                        .opacity(sessionStore.canPerformRemoteActions ? 1 : 0.55)
                    }
                }
            } else {
                ManagementSignedOutCard(accent: accentPurple, tint: cardTint) {
                    guard canOpenOwnProfile else { return }
                    destination = .authPlaceholder
                }
                .disabled(!canOpenOwnProfile)
                .opacity(canOpenOwnProfile ? 1 : 0.55)
            }
        }
    }

    private func openFamily() {
        destination = .family
        guard shouldRefreshFamilyBeforeOpening else {
            return
        }

        Task { @MainActor in
            await familyContextStore.refreshFamilyMetadata(sessionStore: sessionStore)
        }
    }

    private func walletsSection(
        activeWallets: [LedgerWallet],
        walletBalancesByID: [UUID: Int64],
        primaryCurrencyCode: String,
        exchangeRateIndex: MistiaExchangeRateIndex
    ) -> some View {
        ManagementSection(title: L10n.management.management.wallets, titleColor: sectionLabelColor) {
            ManagementCard(tint: cardTint) {
                if activeWallets.isEmpty {
                    ManagementEmptyState(
                        title: L10n.management.management.noWalletsYet,
                        message: L10n.management.management.addCashPayPayBankOrCreditCard,
                        buttonTitle: L10n.management.management.addWallet,
                        accent: accentPurple,
                        symbols: ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
                    ) {
                        if canCreateWallet {
                            walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                        } else {
                            presentCreatePermissionPrompt(
                                resourceType: .wallet,
                                resourceName: L10n.management.management.walletsCards,
                                actionTitle: L10n.management.management.requestWalletCardCreation
                            ) {
                                walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(activeWallets.enumerated()), id: \.element.id) { index, wallet in
                            ManagementWalletRow(
                                wallet: wallet,
                                currentBalanceMinor: walletBalancesByID[wallet.id] ?? wallet.openingBalanceMinor,
                                primaryCurrencyCode: primaryCurrencyCode,
                                exchangeRateIndex: exchangeRateIndex
                            ) {
                                if presentFamilyOwnerConflictIfNeeded(entity: .wallet, recordID: wallet.id) {
                                    return
                                }
                                if canOpenWalletEditor(wallet) {
                                    walletEditorTarget = ManagementWalletEditorTarget(wallet: wallet, defaultKind: wallet.kind)
                                } else {
                                    presentWalletPermissionPrompt(wallet)
                                }
                            }

                            if index < activeWallets.count - 1 {
                                Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                            }
                        }

                        Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)

                        ManagementFooterAddButton(
                            title: L10n.management.management.addWallet,
                            accent: accentPurple
                        ) {
                            if canCreateWallet {
                                walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                            } else {
                                presentCreatePermissionPrompt(
                                    resourceType: .wallet,
                                    resourceName: L10n.management.management.walletsCards,
                                    actionTitle: L10n.management.management.requestWalletCardCreation
                                ) {
                                    walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private var canCreateWallet: Bool {
        guard let ownerUserID = selectedSubjectUserID else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canCreate(ownerUserID: ownerUserID, resourceType: .wallet)
    }

    private var activeAlert: ManagementAlertPresentation? {
        if let familyOwnerConflictAlert {
            return .familyOwnerConflict(familyOwnerConflictAlert)
        }
        if let walletPermissionPrompt {
            return .wallet(walletPermissionPrompt)
        }
        if let permissionPrompt {
            return .permission(permissionPrompt)
        }
        if let infoAlert {
            return .info(infoAlert)
        }
        return nil
    }

    private func walletOwnerUserID(for wallet: LedgerWallet) -> UUID? {
        walletOwnerMap[wallet.id] ?? selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
    }

    private func canOpenWalletEditor(_ wallet: LedgerWallet) -> Bool {
        guard let ownerUserID = walletOwnerUserID(for: wallet) else { return false }
        if ownerUserID == sessionStore.activeLocalProfileUserID {
            return true
        }
        return familyContextStore.canUseWallet(walletID: wallet.id, ownerUserID: ownerUserID)
            && familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .wallet, resourceID: wallet.id)
    }

    private func presentWalletPermissionPrompt(_ wallet: LedgerWallet) {
        guard let ownerUserID = walletOwnerUserID(for: wallet) else { return }
        let prompt = ManagementWalletPermissionPrompt(
            walletID: wallet.id,
            walletName: wallet.name,
            ownerUserID: ownerUserID,
            title: L10n.management.management.noWalletAccess,
            message: L10n.management.management.youDoNotHaveEnoughAccessFor(String(describing: wallet.name))
        )
        guard hasPendingWalletPermission(prompt, scope: .use)
            || hasPendingWalletPermission(prompt, scope: .edit) else {
            walletPermissionPrompt = prompt
            return
        }

        Task { @MainActor in
            if await resolvePendingWalletPermissionBeforePrompt(prompt) {
                return
            }
            walletPermissionPrompt = prompt
        }
    }

    private func walletPermissionActionTitle(
        for prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> String {
        if isWalletPermissionGranted(for: prompt, scope: scope) {
            switch scope {
            case .use:
                return L10n.management.management.useRequestApproved
            case .edit:
                return L10n.management.management.editRequestApproved
            case .create:
                return L10n.management.management.createRequestApproved
            case .view:
                return L10n.management.management.requestApproved
            }
        }

        if familyContextStore.hasPendingPermissionRequest(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        ) {
            switch scope {
            case .use:
                return L10n.management.management.useRequested
            case .edit:
                return L10n.management.management.editRequested
            case .create:
                return L10n.management.management.createRequested
            case .view:
                return L10n.management.management.accessRequested
            }
        }

        switch scope {
        case .use:
            return L10n.management.management.requestUse
        case .edit:
            return L10n.management.management.requestEdit
        case .create:
            return L10n.management.management.requestCreate
        case .view:
            return L10n.management.management.requestAccess
        }
    }

    private func isWalletPermissionGranted(
        for prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        familyContextStore.hasPermission(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        )
    }

    private func hasPendingWalletPermission(
        _ prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        familyContextStore.hasPendingPermissionRequest(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        )
    }

    private func resolvePendingWalletPermissionBeforePrompt(
        _ prompt: ManagementWalletPermissionPrompt
    ) async -> Bool {
        for scope in [MistiaFamilyPermissionScope.use, .edit] {
            guard !isWalletPermissionGranted(for: prompt, scope: scope),
                  hasPendingWalletPermission(prompt, scope: scope) else {
                continue
            }
            _ = await familyContextStore.resolvePendingPermissionBeforePrompt(
                ownerUserID: prompt.ownerUserID,
                resourceType: .wallet,
                resourceID: prompt.walletID,
                scope: scope,
                sessionStore: sessionStore
            )
        }

        guard let wallet = storedWallets.first(where: { $0.id == prompt.walletID }),
              canOpenWalletEditor(wallet) else {
            return false
        }
        performApprovedWalletPermissionAction(prompt, scope: .edit)
        return true
    }

    private func shouldShowWalletPermissionAction(
        for prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> Bool {
        !isWalletPermissionGranted(for: prompt, scope: scope)
    }

    private func requestWalletPermission(
        _ prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) {
        guard !isWalletPermissionGranted(for: prompt, scope: scope) else {
            performApprovedWalletPermissionAction(prompt, scope: scope)
            return
        }

        guard !familyContextStore.hasPendingPermissionRequest(
            ownerUserID: prompt.ownerUserID,
            resourceType: .wallet,
            resourceID: prompt.walletID,
            scope: scope
        ) else {
            refreshPendingWalletPermission(prompt, scope: scope)
            return
        }

        sendPermissionRequest(
            resourceType: .wallet,
            resourceID: prompt.walletID,
            ownerUserID: prompt.ownerUserID,
            scope: scope,
            resourceName: prompt.walletName
        )
    }

    private func refreshPendingWalletPermission(
        _ prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) {
        Task { @MainActor in
            let isApproved = await familyContextStore.refreshPermissionGrant(
                ownerUserID: prompt.ownerUserID,
                resourceType: .wallet,
                resourceID: prompt.walletID,
                scope: scope,
                sessionStore: sessionStore
            )

            if isApproved {
                performApprovedWalletPermissionAction(prompt, scope: scope)
            } else {
                infoAlert = ManagementInfoAlert(
                    title: L10n.management.management.requestSent2,
                    message: familyContextStore.lastErrorMessage ?? L10n.management.management.theRequestIsWaitingForTheData
                )
            }
        }
    }

    private func performApprovedWalletPermissionAction(
        _ prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) {
        walletPermissionPrompt = nil

        switch scope {
        case .use:
            uiState.requestQuickCreateMenuPresentation()
        case .edit:
            guard let wallet = storedWallets.first(where: { $0.id == prompt.walletID }) else { return }
            walletEditorTarget = ManagementWalletEditorTarget(wallet: wallet, defaultKind: wallet.kind)
        case .create, .view:
            break
        }
    }

    private func sendPermissionRequest(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        ownerUserID: UUID,
        scope: MistiaFamilyPermissionScope,
        resourceName: String
    ) {
        Task { @MainActor in
            let didSend = await familyContextStore.requestPermission(
                resourceType: resourceType,
                resourceID: resourceID,
                ownerUserID: ownerUserID,
                scope: scope,
                resourceName: resourceName,
                sessionStore: sessionStore
            )

            walletPermissionPrompt = nil
            permissionPrompt = nil
            infoAlert = ManagementInfoAlert(
                title: didSend
                    ? L10n.management.management.requestSent
                    : L10n.management.management.couldnTSend,
                message: didSend
                    ? L10n.management.management.thePermissionRequestWasSentToThe
                    : (familyContextStore.lastErrorMessage ?? L10n.management.management.couldnTSendTheRequestRightNow)
            )
        }
    }

    private func presentCreatePermissionPrompt(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceName: String,
        actionTitle: String,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID = selectedSubjectUserID,
              ownerUserID != sessionStore.activeLocalProfileUserID else {
            return
        }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: resourceType,
            resourceID: nil,
            scope: .create
        )
        if isPending {
            Task { @MainActor in
                if await familyContextStore.resolvePendingPermissionBeforePrompt(
                    ownerUserID: ownerUserID,
                    resourceType: resourceType,
                    resourceID: nil,
                    scope: .create,
                    sessionStore: sessionStore
                ) {
                    permissionPrompt = nil
                    onGranted()
                    return
                }
                showCreatePermissionPrompt(
                    resourceType: resourceType,
                    resourceName: resourceName,
                    actionTitle: actionTitle,
                    ownerUserID: ownerUserID,
                    isPending: true,
                    onGranted: onGranted
                )
            }
            return
        }

        showCreatePermissionPrompt(
            resourceType: resourceType,
            resourceName: resourceName,
            actionTitle: actionTitle,
            ownerUserID: ownerUserID,
            isPending: false,
            onGranted: onGranted
        )
    }

    private func showCreatePermissionPrompt(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceName: String,
        actionTitle: String,
        ownerUserID: UUID,
        isPending: Bool,
        onGranted: @escaping () -> Void
    ) {
        permissionPrompt = ManagementPermissionPrompt(
            title: L10n.management.management.noCreateAccess,
            message: L10n.management.management.youDoNotHavePermissionToCreate2(String(describing: resourceName)),
            actionTitle: isPending
                ? L10n.management.management.createRequestSent
                : actionTitle
        ) {
            resolvePermissionPromptAction(
                resourceType: resourceType,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .create,
                resourceName: resourceName,
                wasPending: isPending,
                onGranted: onGranted
            )
        }
    }

    private func resolvePermissionPromptAction(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        ownerUserID: UUID,
        scope: MistiaFamilyPermissionScope,
        resourceName: String,
        wasPending: Bool,
        onGranted: @escaping () -> Void
    ) {
        Task { @MainActor in
            if wasPending {
                let isApproved = await familyContextStore.refreshPermissionGrant(
                    ownerUserID: ownerUserID,
                    resourceType: resourceType,
                    resourceID: resourceID,
                    scope: scope,
                    sessionStore: sessionStore
                )

                if isApproved {
                    permissionPrompt = nil
                    onGranted()
                    return
                }

                permissionPrompt = nil
                infoAlert = ManagementInfoAlert(
                    title: L10n.management.management.requestSent2,
                    message: familyContextStore.lastErrorMessage ?? L10n.management.management.theRequestIsWaitingForTheData
                )
                return
            }

            let didSend = await familyContextStore.requestPermission(
                resourceType: resourceType,
                resourceID: resourceID,
                ownerUserID: ownerUserID,
                scope: scope,
                resourceName: resourceName,
                sessionStore: sessionStore
            )

            permissionPrompt = nil
            infoAlert = ManagementInfoAlert(
                title: didSend
                    ? L10n.management.management.requestSent
                    : L10n.management.management.couldnTSend,
                message: didSend
                    ? L10n.management.management.thePermissionRequestWasSentToThe
                    : (familyContextStore.lastErrorMessage ?? L10n.management.management.couldnTSendTheRequestRightNow)
            )
        }
    }

    private func categoriesSection(
        visibleCategorySections: [TransactionCategoryGroupSection]
    ) -> some View {
        ManagementSection(title: L10n.management.management.categories2, titleColor: sectionLabelColor) {
            VStack(alignment: .leading, spacing: 12) {
                ManagementCategoryKindPicker(selection: $selectedCategoryKind)

                ManagementCard(tint: cardTint) {
                    if visibleCategorySections.isEmpty {
                        VStack(spacing: 0) {
                            ManagementEmptyState(
                                title: selectedCategoryKind == .expense
                                    ? L10n.management.management.noExpenseCategoriesYet
                                    : L10n.management.management.noIncomeCategoriesYet,
                                message: selectedCategoryKind == .expense
                                    ? L10n.management.management.createExpenseGroupsSoYourTransactionsAnd
                                    : L10n.management.management.separateYourIncomeSourcesToClearlyTrack,
                                buttonTitle: L10n.management.management.addCategory,
                                accent: accentPurple,
                                symbols: selectedCategoryKind == .expense
                                    ? ["fork.knife", "bag.fill", "airplane", "plus"]
                                    : ["briefcase.fill", "gift.fill", "chart.line.uptrend.xyaxis", "plus"]
                            ) {
                                openCategoryEditorIfAllowed(
                                    category: nil,
                                    defaultKind: selectedCategoryKind,
                                    preferredParentCategoryID: nil
                                )
                            }

                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleCategorySections.enumerated()), id: \.element.id) { index, section in
                                ManagementCategoryParentCard(
                                    parent: section.parent,
                                    children: section.children,
                                    isExpanded: Binding(
                                        get: { expandedCategoryParentIDs.contains(section.parent.id) },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedCategoryParentIDs.insert(section.parent.id)
                                            } else {
                                                expandedCategoryParentIDs.remove(section.parent.id)
                                            }
                                        }
                                    ),
                                    onEditParent: {
                                        openCategoryEditorIfAllowed(
                                            category: section.parent,
                                            defaultKind: section.parent.kind,
                                            preferredParentCategoryID: nil
                                        )
                                    },
                                    onEditChild: { category in
                                        openCategoryEditorIfAllowed(
                                            category: category,
                                            defaultKind: category.kind,
                                            preferredParentCategoryID: category.parentCategory?.id
                                        )
                                    },
                                    onToggleFavorite: { category in
                                        if canEditCategory(category) {
                                            toggleFavorite(for: category)
                                        } else {
                                            presentCategoryEditPermissionPrompt(category) {
                                                toggleFavorite(for: category)
                                            }
                                        }
                                    },
                                    onAddChild: {
                                        openCategoryEditorIfAllowed(
                                            category: nil,
                                            defaultKind: section.parent.kind,
                                            preferredParentCategoryID: section.parent.id
                                        )
                                    }
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)

                                if index < visibleCategorySections.count - 1 {
                                    Divider()
                                        .padding(.leading, 52)
                                        .padding(.trailing, 0)
                                }
                            }

                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)

                            ManagementFooterAddButton(
                                title: L10n.management.management.addParentCategory,
                                accent: accentPurple
                            ) {
                                openCategoryEditorIfAllowed(
                                    category: nil,
                                    defaultKind: selectedCategoryKind,
                                    preferredParentCategoryID: nil
                                )
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)

                        }
                    }
                }
            }
        }
    }

    private func openCategoryEditorIfAllowed(
        category: TransactionCategory?,
        defaultKind: TransactionCategoryKind,
        preferredParentCategoryID: UUID?
    ) {
        if let category {
            if presentFamilyOwnerConflictIfNeeded(entity: .category, recordID: category.id) {
                return
            }
            guard canEditCategory(category) else {
                presentCategoryEditPermissionPrompt(category) {
                    openCategoryEditorIfAllowed(
                        category: category,
                        defaultKind: defaultKind,
                        preferredParentCategoryID: preferredParentCategoryID
                    )
                }
                return
            }
        } else {
            let ownerUserID = categoryCreateOwnerUserID(preferredParentCategoryID: preferredParentCategoryID)
            guard canCreateCategory(ownerUserID: ownerUserID) else {
                presentCategoryCreatePermissionPrompt(ownerUserID: ownerUserID) {
                    openCategoryEditorIfAllowed(
                        category: nil,
                        defaultKind: defaultKind,
                        preferredParentCategoryID: preferredParentCategoryID
                    )
                }
                return
            }
        }

        categoryEditorTarget = ManagementCategoryEditorTarget(
            category: category,
            defaultKind: defaultKind,
            preferredParentCategoryID: preferredParentCategoryID
        )
    }

    private func presentFamilyOwnerConflictIfNeeded(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        guard sessionStore.hasFamilyOwnerPushConflict(entity: entity, recordID: recordID) else {
            return false
        }
        familyOwnerConflictAlert = ManagementFamilyOwnerConflictAlert(entity: entity, recordID: recordID)
        return true
    }

    private func categoryOwnerUserID(for category: TransactionCategory) -> UUID? {
        categoryOwnerMap[category.id] ?? selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID
    }

    private func categoryCreateOwnerUserID(preferredParentCategoryID: UUID?) -> UUID? {
        if let preferredParentCategoryID,
           let parent = storedCategories.first(where: { $0.id == preferredParentCategoryID }) {
            return categoryOwnerUserID(for: parent)
        }
        return selectedSubjectUserID
    }

    private func canEditCategory(_ category: TransactionCategory) -> Bool {
        guard let ownerUserID = categoryOwnerUserID(for: category) else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .category)
    }

    private func canCreateCategory(ownerUserID: UUID?) -> Bool {
        guard let ownerUserID else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canCreate(ownerUserID: ownerUserID, resourceType: .category)
    }

    private func presentCategoryEditPermissionPrompt(
        _ category: TransactionCategory,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID = categoryOwnerUserID(for: category),
              ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .category,
            resourceID: nil,
            scope: .edit
        )
        if isPending {
            Task { @MainActor in
                if await familyContextStore.resolvePendingPermissionBeforePrompt(
                    ownerUserID: ownerUserID,
                    resourceType: .category,
                    resourceID: nil,
                    scope: .edit,
                    sessionStore: sessionStore
                ) {
                    permissionPrompt = nil
                    onGranted()
                    return
                }
                showCategoryEditPermissionPrompt(ownerUserID: ownerUserID, isPending: true, onGranted: onGranted)
            }
            return
        }

        showCategoryEditPermissionPrompt(ownerUserID: ownerUserID, isPending: false, onGranted: onGranted)
    }

    private func showCategoryEditPermissionPrompt(
        ownerUserID: UUID,
        isPending: Bool,
        onGranted: @escaping () -> Void
    ) {
        permissionPrompt = ManagementPermissionPrompt(
            title: L10n.management.management.noCategoryEditAccess,
            message: L10n.management.management.youDoNotHavePermissionToEdit,
            actionTitle: isPending
                ? L10n.management.management.editRequestSent
                : L10n.management.management.requestEditAccess
        ) {
            resolvePermissionPromptAction(
                resourceType: .category,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .edit,
                resourceName: L10n.management.management.categories,
                wasPending: isPending,
                onGranted: onGranted
            )
        }
    }

    private func presentCategoryCreatePermissionPrompt(
        ownerUserID: UUID?,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID,
              ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .category,
            resourceID: nil,
            scope: .create
        )
        if isPending {
            Task { @MainActor in
                if await familyContextStore.resolvePendingPermissionBeforePrompt(
                    ownerUserID: ownerUserID,
                    resourceType: .category,
                    resourceID: nil,
                    scope: .create,
                    sessionStore: sessionStore
                ) {
                    permissionPrompt = nil
                    onGranted()
                    return
                }
                showCategoryCreatePermissionPrompt(ownerUserID: ownerUserID, isPending: true, onGranted: onGranted)
            }
            return
        }

        showCategoryCreatePermissionPrompt(ownerUserID: ownerUserID, isPending: false, onGranted: onGranted)
    }

    private func showCategoryCreatePermissionPrompt(
        ownerUserID: UUID,
        isPending: Bool,
        onGranted: @escaping () -> Void
    ) {
        permissionPrompt = ManagementPermissionPrompt(
            title: L10n.management.management.noCategoryCreateAccess,
            message: L10n.management.management.youDoNotHavePermissionToCreate,
            actionTitle: isPending
                ? L10n.management.management.createRequestSent
                : L10n.management.management.requestCategoryCreation
        ) {
            resolvePermissionPromptAction(
                resourceType: .category,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .create,
                resourceName: L10n.management.management.categories,
                wasPending: isPending,
                onGranted: onGranted
            )
        }
    }

    private func toggleFavorite(for category: TransactionCategory) {
        guard category.isChildCategory else { return }

        category.isFavorite.toggle()
        category.updatedAt = .now

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .category,
                recordID: category.id,
                modifiedAt: category.updatedAt
            )
        } catch {
            modelContext.rollback()
            infoAlert = ManagementInfoAlert(
                title: L10n.management.management.couldnTUpdateFavorite,
                message: error.localizedDescription
            )
        }
    }
}

struct ManagementSection<Content: View>: View {
    let title: String
    let titleColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(titleColor)
                .padding(.horizontal, 2)

            content
        }
    }
}

private struct ManagementCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                ManagementCardBackground(tint: tint)
            }
    }
}


private struct ManagementSignedOutCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    let tint: Color
    let action: () -> Void

    private var badgeFill: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(colorScheme == .dark ? 0.46 : 0.18),
                accent.opacity(colorScheme == .dark ? 0.24 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var badgeForeground: Color {
        colorScheme == .dark ? MistiaAccent.tabActive.color : accent
    }

    private var buttonFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? MistiaAccent.tabActive.color : accent
    }

    var body: some View {
        ManagementCard(tint: tint) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(badgeFill)

                        Circle()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.24), lineWidth: 0.8)

                        Image(systemName: "person.crop.circle.fill.badge.plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(badgeForeground)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.management.management.signInToSyncYourData)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            L10n.management.management.yourWalletsCategoriesAndTransactionsAreReady
                        )
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: action) {
                    Text(L10n.management.management.signInOrCreateAnAccount)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(buttonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            Capsule()
                                .fill(buttonFill)
                        }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 22, tint: buttonForeground))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

private struct ManagementWalletRow: View {
    let wallet: LedgerWallet
    let currentBalanceMinor: Int64
    let primaryCurrencyCode: String
    let exchangeRateIndex: MistiaExchangeRateIndex
    let action: () -> Void
    
    private var availableCreditMinor: Int64? {
        guard wallet.kind == .creditCard,
              let profile = wallet.creditCardProfile else {
            return nil
        }
        let creditLimitMinor = profile.creditLimitMinor
        let debt = max(currentBalanceMinor, 0)
        return max(creditLimitMinor - debt, 0)
    }

    private var balanceColor: Color {
        if wallet.kind == .creditCard {
            // For credit cards, available credit is always positive (good)
            return MistiaAccent.income.color
        }
        if currentBalanceMinor < 1000 {
            return MistiaAccent.expense.color
        }
        return .primary
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ManagementIconTile(icon: wallet.iconSymbolName, color: wallet.iconColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallet.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle = wallet.subtitleText {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if wallet.kind == .creditCard, availableCreditMinor != nil {
                        Text(L10n.management.management.available)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(balanceAmountMinor.formattedCurrency(code: wallet.currencyCode))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(balanceColor)

                    if let approximatePrimaryAmountText {
                        Text(approximatePrimaryAmountText)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
    }

    private var balanceAmountMinor: Int64 {
        availableCreditMinor ?? currentBalanceMinor
    }

    private var approximatePrimaryAmountText: String? {
        MistiaCurrencyLogic.approximatePrimaryAmountText(
            amountMinor: balanceAmountMinor,
            sourceCurrencyCode: wallet.currencyCode,
            primaryCurrencyCode: primaryCurrencyCode,
            rateIndex: exchangeRateIndex
        )
    }
}

private struct ManagementCategoryRow: View {
    let category: TransactionCategory
    let action: () -> Void
    let onToggleFavorite: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ManagementIconTile(icon: category.iconSymbolName, color: category.iconColor)

                    Text(category.localizedDisplayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    ManagementChevron()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))

            if let onToggleFavorite, category.isChildCategory {
                Button(action: onToggleFavorite) {
                    Image(systemName: category.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(category.isFavorite ? Color.yellow : Color.secondary.opacity(0.45))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    category.isFavorite
                        ? L10n.management.management.removeFavorite
                        : L10n.management.management.markAsFavorite
                )
            }
        }
    }
}

private struct ManagementCategoryParentCard: View {
    let parent: TransactionCategory
    let children: [TransactionCategory]
    @Binding var isExpanded: Bool
    let onEditParent: () -> Void
    let onEditChild: (TransactionCategory) -> Void
    let onToggleFavorite: (TransactionCategory) -> Void
    let onAddChild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        ManagementIconTile(icon: parent.iconSymbolName, color: parent.iconColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(parent.localizedDisplayName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(
                                L10n.management.management.valueChildCategories(String(describing: children.count))
                            )
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                Button(action: onEditParent) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(spacing: 10) {
                    if children.isEmpty {
                        Text(
                            L10n.management.management.thereAreNoChildCategoriesInThis
                        )
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            ManagementCategoryRow(
                                category: child,
                                action: {
                                    onEditChild(child)
                                },
                                onToggleFavorite: {
                                    onToggleFavorite(child)
                                }
                            )

                            if index < children.count - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }

                    ManagementFooterAddButton(
                        title: L10n.management.management.addChildCategory,
                        accent: MistiaAccent.purple.color
                    ) {
                        onAddChild()
                    }
                }
            }
        }
    }
}

private struct ManagementCategoryTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let category: TransactionCategory
    let action: () -> Void

    private var tileFill: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.035)
    }

    private var tileStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.22)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 10) {
                ManagementIconTile(icon: category.iconSymbolName, color: category.iconColor)

                Text(category.localizedDisplayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tileFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tileStroke, lineWidth: 0.8)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
    }
}

private struct ManagementFooterAddButton: View {
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        MistiaFooterAddButton(title: title, accent: MistiaAccent.tabActive.color, action: action)
    }
}

private struct ManagementEmptyState: View {
    let title: String
    let message: String
    let buttonTitle: String
    let accent: Color
    let symbols: [String]
    let action: () -> Void

    var body: some View {
        MistiaEmptyStateContent(
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            accent: accent,
            symbols: symbols,
            action: action
        )
    }
}

private struct ManagementCategoryKindPicker: View {
    @Binding var selection: TransactionCategoryKind

    var body: some View {
        MistiaNativeSegmentedControl(
            selection: $selection,
            options: TransactionCategoryKind.allCases,
            title: \.title
        )
    }
}

private struct ManagementIconTile: View {
    let icon: String
    let color: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: color, size: 30)
    }
}

private struct ManagementChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tertiary)
    }
}

private struct ManagementCardBackground: View {
    let tint: Color

    var body: some View {
        MistiaBlockCardBackground(tint: tint, cornerRadius: 20)
    }
}
