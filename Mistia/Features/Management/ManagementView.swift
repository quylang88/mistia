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

private struct ManagementSystemCategoryUseRequestTarget: Identifiable {
    let id = UUID()
    let ownerUserID: UUID
}

private enum ManagementAlertPresentation: Identifiable {
    case info(ManagementInfoAlert)
    case permission(ManagementPermissionPrompt)
    case wallet(ManagementWalletPermissionPrompt)

    var id: UUID {
        switch self {
        case .info(let alert):
            alert.id
        case .permission(let prompt):
            prompt.id
        case .wallet(let prompt):
            prompt.id
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
        }
    }
}

struct ManagementView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState

    @AppStorage(MistiaAppStorageKey.hideQuickCreate) private var hideQuickCreate = false

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> {
        $0.entryStatusRawValue == "posted" && !$0.isArchived && $0.deletedAt == nil
    })
    private var postedTransactions: [LedgerTransaction]
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
    @State private var isOpeningFamily = false

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private var accentPurple: Color {
        MistiaAccent.purple.color
    }

    private let profileLeadingVisualWidth: CGFloat = 50
    private let profileRowSpacing: CGFloat = 20

    private var hasFamilyProfile: Bool {
        familyContextStore.family != nil && !familyContextStore.members.isEmpty
    }

    private var shouldRefreshFamilyBeforeOpening: Bool {
        familyContextStore.family != nil && familyContextStore.members.count >= 2
    }

    private var activeWallets: [LedgerWallet] {
        visibleWallets
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var visibleCategorySections: [TransactionCategoryGroupSection] {
        MistiaCategoryHierarchy.groupedSections(
            from: visibleCategories,
            kind: selectedCategoryKind,
            includeArchived: false,
            includeEmptyParents: true
        )
    }

    private var visibleWallets: [LedgerWallet] {
        FamilyScopedData.visible(
            storedWallets,
            entity: .wallet,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleCategories: [TransactionCategory] {
        FamilyScopedData.visible(
            storedCategories,
            entity: .category,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visiblePostedTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForHistory(
            postedTransactions,
            audits: transactionAuditRecords,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
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


    private var activeAlert: ManagementAlertPresentation? {
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

    var body: some View {
        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .muted,
                title: mistiaLocalized(vi: "Quản lý", en: "Manage", ja: "管理"),
                embedsInNavigationStack: false,
                showsLeadingAvatar: false,
                trailingSystemImage: "gearshape",
                onTrailingTap: { destination = .settings },
                contentSpacing: 20,
                titleDisplayMode: .large
            ) {
                FamilyContextChipBar()
                profileSection
                walletsSection
                categoriesSection
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
                Button(mistiaLocalized(vi: "OK", en: "OK", ja: "OK")) {}
            case .permission(let prompt):
                Button(prompt.actionTitle) {
                    prompt.action()
                }
                Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {}
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
                Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .onAppear {
            hideQuickCreate = destination != nil
        }
        .onChange(of: destination, initial: true) { _, newValue in
            hideQuickCreate = newValue != nil
        }
        .onChange(of: uiState.managementNavigationRequest?.id, initial: true) { _, _ in
            handleManagementNavigationRequest()
        }
        .onDisappear {
            hideQuickCreate = false
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
            if let summary = sessionStore.summary {
                ManagementCard(tint: cardTint) {
                    VStack(spacing: 0) {
                        Button {
                            destination = .authPlaceholder
                        } label: {
                            HStack(spacing: profileRowSpacing) {
                                MistiaAvatarBadge(
                                    initials: summary.initials,
                                    avatarURL: summary.avatarURL,
                                    size: 50,
                                    showsStatus: false
                                )
                                .frame(width: profileLeadingVisualWidth, height: 50)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(summary.displayName)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)

                                    Text(summary.email)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))

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
                                    Text(mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"))
                                        .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }

                                Spacer(minLength: 12)

                                if !hasFamilyProfile {
                                    Text(mistiaLocalized(vi: "Chưa có", en: "None", ja: "未設定"))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                if isOpeningFamily && shouldRefreshFamilyBeforeOpening {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                        .disabled(!sessionStore.canPerformRemoteActions || isOpeningFamily)
                        .opacity(sessionStore.canPerformRemoteActions ? 1 : 0.55)
                    }
                }
            } else {
                ManagementSignedOutCard(accent: accentPurple, tint: cardTint) {
                    destination = .authPlaceholder
                }
            }
        }
    }

    private func openFamily() {
        guard shouldRefreshFamilyBeforeOpening else {
            destination = .family
            return
        }

        guard !isOpeningFamily else { return }
        isOpeningFamily = true
        destination = .family

        Task { @MainActor in
            await familyContextStore.refreshLatest(
                sessionStore: sessionStore,
                source: .userInitiated
            )
            isOpeningFamily = false
        }
    }

    private var walletsSection: some View {
        ManagementSection(title: mistiaLocalized(vi: "Ví", en: "Wallets", ja: "ウォレット"), titleColor: sectionLabelColor) {
            ManagementCard(tint: cardTint) {
                if activeWallets.isEmpty {
                    ManagementEmptyState(
                        title: mistiaLocalized(vi: "Chưa có ví nào", en: "No wallets yet", ja: "ウォレットはまだありません"),
                        message: mistiaLocalized(
                            vi: "Thêm ví tiền mặt, PayPay, ví ngân hàng hoặc credit card để bắt đầu quản lý nguồn tiền.",
                            en: "Add cash, PayPay, bank, or credit card wallets to start managing your money sources.",
                            ja: "現金、PayPay、銀行口座、クレジットカードのウォレットを追加して資金管理を始めましょう。"
                        ),
                        buttonTitle: mistiaLocalized(vi: "Thêm ví", en: "Add wallet", ja: "ウォレットを追加"),
                        accent: accentPurple,
                        symbols: ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
                    ) {
                        if canCreateWallet {
                            walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                        } else {
                            presentCreatePermissionPrompt(
                                resourceType: .wallet,
                                resourceName: mistiaLocalized(vi: "ví / thẻ", en: "wallets / cards", ja: "ウォレット・カード"),
                                actionTitle: mistiaLocalized(vi: "Yêu cầu thêm mới ví / thẻ", en: "Request wallet / card creation", ja: "ウォレット・カード作成をリクエスト")
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
                                transactions: visiblePostedTransactions
                            ) {
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
                            title: mistiaLocalized(vi: "Thêm ví", en: "Add wallet", ja: "ウォレットを追加"),
                            accent: accentPurple
                        ) {
                            if canCreateWallet {
                                walletEditorTarget = ManagementWalletEditorTarget(wallet: nil, defaultKind: .cash)
                            } else {
                                presentCreatePermissionPrompt(
                                    resourceType: .wallet,
                                    resourceName: mistiaLocalized(vi: "ví / thẻ", en: "wallets / cards", ja: "ウォレット・カード"),
                                    actionTitle: mistiaLocalized(vi: "Yêu cầu thêm mới ví / thẻ", en: "Request wallet / card creation", ja: "ウォレット・カード作成をリクエスト")
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
        walletPermissionPrompt = ManagementWalletPermissionPrompt(
            walletID: wallet.id,
            walletName: wallet.name,
            ownerUserID: ownerUserID,
            title: mistiaLocalized(vi: "Chưa có quyền thao tác ví", en: "No wallet access", ja: "ウォレット権限がありません"),
            message: mistiaLocalized(
                vi: "Bạn chưa có đủ quyền với \(wallet.name).",
                en: "You do not have enough access for \(wallet.name).",
                ja: "\(wallet.name) の権限が不足しています。"
            )
        )
    }

    private func walletPermissionActionTitle(
        for prompt: ManagementWalletPermissionPrompt,
        scope: MistiaFamilyPermissionScope
    ) -> String {
        if isWalletPermissionGranted(for: prompt, scope: scope) {
            switch scope {
            case .use:
                return mistiaLocalized(vi: "Đã chấp nhận yêu cầu sử dụng", en: "Use request approved", ja: "使用リクエストが承認済み")
            case .edit:
                return mistiaLocalized(vi: "Đã chấp nhận yêu cầu chỉnh sửa", en: "Edit request approved", ja: "編集リクエストが承認済み")
            case .create:
                return mistiaLocalized(vi: "Đã chấp nhận yêu cầu thêm mới", en: "Create request approved", ja: "作成リクエストが承認済み")
            case .view:
                return mistiaLocalized(vi: "Đã chấp nhận yêu cầu", en: "Request approved", ja: "リクエストが承認済み")
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
                return mistiaLocalized(vi: "Đã yêu cầu sử dụng", en: "Use requested", ja: "使用権限をリクエスト済み")
            case .edit:
                return mistiaLocalized(vi: "Đã yêu cầu chỉnh sửa", en: "Edit requested", ja: "編集権限をリクエスト済み")
            case .create:
                return mistiaLocalized(vi: "Đã yêu cầu thêm mới", en: "Create requested", ja: "作成権限をリクエスト済み")
            case .view:
                return mistiaLocalized(vi: "Đã yêu cầu quyền", en: "Access requested", ja: "権限をリクエスト済み")
            }
        }

        switch scope {
        case .use:
            return mistiaLocalized(vi: "Yêu cầu sử dụng", en: "Request use", ja: "使用をリクエスト")
        case .edit:
            return mistiaLocalized(vi: "Yêu cầu chỉnh sửa", en: "Request edit", ja: "編集をリクエスト")
        case .create:
            return mistiaLocalized(vi: "Yêu cầu thêm mới", en: "Request create", ja: "作成をリクエスト")
        case .view:
            return mistiaLocalized(vi: "Yêu cầu quyền", en: "Request access", ja: "権限をリクエスト")
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
                    title: mistiaLocalized(vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエスト送信済み"),
                    message: familyContextStore.lastErrorMessage ?? mistiaLocalized(
                        vi: "Yêu cầu đang chờ chủ dữ liệu phản hồi.",
                        en: "The request is waiting for the data owner.",
                        ja: "リクエストはデータ所有者の返答待ちです。"
                    )
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
                    ? mistiaLocalized(vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました")
                    : mistiaLocalized(vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした"),
                message: didSend
                    ? mistiaLocalized(
                        vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.",
                        en: "The permission request was sent to the data owner.",
                        ja: "権限リクエストをデータ所有者へ送信しました。"
                    )
                    : (familyContextStore.lastErrorMessage ?? mistiaLocalized(
                        vi: "Không thể gửi yêu cầu lúc này.",
                        en: "Couldn't send the request right now.",
                        ja: "現在リクエストは送信できません。"
                    ))
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
        permissionPrompt = ManagementPermissionPrompt(
            title: mistiaLocalized(vi: "Chưa có quyền thêm mới", en: "No create access", ja: "作成権限がありません"),
            message: mistiaLocalized(
                vi: "Bạn chưa có quyền thêm mới \(resourceName) cho thành viên này.",
                en: "You do not have permission to create \(resourceName) for this member.",
                ja: "このメンバーの\(resourceName)を作成する権限がありません。"
            ),
            actionTitle: isPending
                ? mistiaLocalized(vi: "Đã gửi yêu cầu thêm mới", en: "Create request sent", ja: "作成リクエスト送信済み")
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
                    title: mistiaLocalized(vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエスト送信済み"),
                    message: familyContextStore.lastErrorMessage ?? mistiaLocalized(
                        vi: "Yêu cầu đang chờ chủ dữ liệu phản hồi.",
                        en: "The request is waiting for the data owner.",
                        ja: "リクエストはデータ所有者の返答待ちです。"
                    )
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
                    ? mistiaLocalized(vi: "Đã gửi yêu cầu", en: "Request sent", ja: "リクエストを送信しました")
                    : mistiaLocalized(vi: "Chưa thể gửi", en: "Couldn't send", ja: "送信できませんでした"),
                message: didSend
                    ? mistiaLocalized(
                        vi: "Yêu cầu quyền đã được gửi tới chủ dữ liệu.",
                        en: "The permission request was sent to the data owner.",
                        ja: "権限リクエストをデータ所有者へ送信しました。"
                    )
                    : (familyContextStore.lastErrorMessage ?? mistiaLocalized(
                        vi: "Không thể gửi yêu cầu lúc này.",
                        en: "Couldn't send the request right now.",
                        ja: "現在リクエストは送信できません。"
                    ))
            )
        }
    }

    private var categoriesSection: some View {
        ManagementSection(title: mistiaLocalized(vi: "Danh mục", en: "Categories", ja: "カテゴリ"), titleColor: sectionLabelColor) {
            VStack(alignment: .leading, spacing: 12) {
                ManagementCategoryKindPicker(selection: $selectedCategoryKind)

                ManagementCard(tint: cardTint) {
                    if visibleCategorySections.isEmpty {
                        VStack(spacing: 0) {
                            ManagementEmptyState(
                                title: selectedCategoryKind == .expense
                                    ? mistiaLocalized(vi: "Chưa có danh mục chi tiêu", en: "No expense categories yet", ja: "支出カテゴリはまだありません")
                                    : mistiaLocalized(vi: "Chưa có danh mục thu nhập", en: "No income categories yet", ja: "収入カテゴリはまだありません"),
                                message: selectedCategoryKind == .expense
                                    ? mistiaLocalized(
                                        vi: "Tạo nhóm chi tiêu riêng để giao dịch và ngân sách bám sát cách bạn quản lý hằng ngày.",
                                        en: "Create expense groups so your transactions and budgets match how you manage money every day.",
                                        ja: "支出グループを作成すると、取引や予算を日々の管理方法に合わせやすくなります。"
                                    )
                                    : mistiaLocalized(
                                        vi: "Tách riêng nguồn thu để nhìn rõ tiền lương, thưởng, freelance hay hoàn tiền.",
                                        en: "Separate your income sources to clearly track salary, bonuses, freelance work, or refunds.",
                                        ja: "収入源を分けておくと、給与、賞与、副業、返金などを分かりやすく把握できます。"
                                    ),
                                buttonTitle: mistiaLocalized(vi: "Thêm danh mục", en: "Add category", ja: "カテゴリを追加"),
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
                                title: mistiaLocalized(vi: "Thêm danh mục cha", en: "Add parent category", ja: "親カテゴリを追加"),
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
        permissionPrompt = ManagementPermissionPrompt(
            title: mistiaLocalized(vi: "Chưa có quyền chỉnh sửa danh mục", en: "No category edit access", ja: "カテゴリ編集権限がありません"),
            message: mistiaLocalized(
                vi: "Bạn chưa có quyền chỉnh sửa danh mục của thành viên này.",
                en: "You do not have permission to edit this member's categories.",
                ja: "このメンバーのカテゴリを編集する権限がありません。"
            ),
            actionTitle: isPending
                ? mistiaLocalized(vi: "Đã gửi yêu cầu chỉnh sửa", en: "Edit request sent", ja: "編集リクエスト送信済み")
                : mistiaLocalized(vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト")
        ) {
            resolvePermissionPromptAction(
                resourceType: .category,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .edit,
                resourceName: mistiaLocalized(vi: "danh mục", en: "categories", ja: "カテゴリ"),
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
        permissionPrompt = ManagementPermissionPrompt(
            title: mistiaLocalized(vi: "Chưa có quyền thêm mới danh mục", en: "No category create access", ja: "カテゴリ作成権限がありません"),
            message: mistiaLocalized(
                vi: "Bạn chưa có quyền thêm mới danh mục cho thành viên này.",
                en: "You do not have permission to create categories for this member.",
                ja: "このメンバーのカテゴリを作成する権限がありません。"
            ),
            actionTitle: isPending
                ? mistiaLocalized(vi: "Đã gửi yêu cầu thêm mới", en: "Create request sent", ja: "作成リクエスト送信済み")
                : mistiaLocalized(vi: "Yêu cầu thêm mới danh mục", en: "Request category creation", ja: "カテゴリ作成をリクエスト")
        ) {
            resolvePermissionPromptAction(
                resourceType: .category,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .create,
                resourceName: mistiaLocalized(vi: "danh mục", en: "categories", ja: "カテゴリ"),
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
                title: mistiaLocalized(vi: "Không thể cập nhật yêu thích", en: "Couldn't update favorite", ja: "お気に入りを更新できませんでした"),
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
        colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : accent
    }

    private var buttonFill: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.90, green: 0.74, blue: 1.00) : accent
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
                        Text(mistiaLocalized(vi: "Đăng nhập để đồng bộ dữ liệu", en: "Sign in to sync your data", ja: "ログインしてデータを同期"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(
                            mistiaLocalized(
                                vi: "Ví, danh mục và giao dịch của bạn đã sẵn sàng cho backup, khôi phục và đồng bộ giữa các thiết bị.",
                                en: "Your wallets, categories, and transactions are ready for backup, restore, and sync across devices.",
                                ja: "ウォレット、カテゴリ、取引はバックアップ、復元、端末間同期に対応しています。"
                            )
                        )
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: action) {
                    Text(mistiaLocalized(vi: "Đăng nhập hoặc tạo tài khoản", en: "Sign in or create an account", ja: "ログインまたはアカウント作成"))
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
    let transactions: [LedgerTransaction]
    let action: () -> Void

    private var currentBalanceMinor: Int64 {
        let snapshot = TransactionWalletSnapshot(
            id: wallet.id,
            kind: wallet.kind,
            openingBalanceMinor: wallet.openingBalanceMinor
        )

        let snapshots = transactions.map {
            TransactionRecordSnapshot(
                id: $0.id,
                primaryKind: $0.primaryKind,
                transferSubtype: $0.transferSubtype,
                debtIntent: $0.debtIntent,
                entryStatus: $0.entryStatus,
                title: $0.title,
                note: $0.note,
                amountMinor: $0.amountMinor,
                isArchived: $0.isArchived,
                occurredAt: $0.occurredAt,
                createdAt: $0.createdAt,
                sourceWalletID: $0.sourceWallet?.id,
                sourceWalletKind: $0.sourceWallet?.kind,
                destinationWalletID: $0.destinationWallet?.id,
                destinationWalletKind: $0.destinationWallet?.kind,
                categoryID: $0.category?.id,
                counterpartyName: $0.counterpartyName,
                normalizedCounterpartyKey: $0.normalizedCounterpartyKey
            )
        }

        return TransactionLogic.effectiveBalance(for: snapshot, records: snapshots)
    }
    
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

                if wallet.kind == .creditCard, let availableCredit = availableCreditMinor {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(mistiaLocalized(vi: "Khả dụng", en: "Available", ja: "利用可能"))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(availableCredit.formattedCurrency(code: wallet.currencyCode))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(balanceColor)
                    }
                } else {
                    Text(currentBalanceMinor.formattedCurrency(code: wallet.currencyCode))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(balanceColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 16))
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
                        ? mistiaLocalized(vi: "Bỏ yêu thích", en: "Remove favorite", ja: "お気に入り解除")
                        : mistiaLocalized(vi: "Đánh dấu yêu thích", en: "Mark as favorite", ja: "お気に入りに追加")
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
                                mistiaLocalized(
                                    vi: "\(children.count) danh mục con",
                                    en: "\(children.count) child categories",
                                    ja: "子カテゴリ \(children.count) 件"
                                )
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
                            mistiaLocalized(
                                vi: "Chưa có danh mục con nào trong nhánh này.",
                                en: "There are no child categories in this branch yet.",
                                ja: "この枝にはまだ子カテゴリがありません。"
                            )
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
                        title: mistiaLocalized(vi: "Thêm danh mục con", en: "Add child category", ja: "子カテゴリを追加"),
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
        MistiaFooterAddButton(title: title, accent: accent, action: action)
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

    private var accentPurple: Color {
        MistiaAccent.purple.color
    }

    var body: some View {
        MistiaNativeSegmentedControl(
            selection: $selection,
            options: TransactionCategoryKind.allCases,
            title: \.title,
            accent: accentPurple
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
