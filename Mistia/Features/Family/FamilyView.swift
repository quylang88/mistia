import SwiftData
import SwiftUI

private enum FamilyDestination: String, Identifiable {
    case overview
    case members

    var id: String { rawValue }
}

private enum FamilySheet: String, Identifiable {
    case create
    case join
    case invite

    var id: String { rawValue }
}

struct FamilyManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var destination: FamilyDestination?
    @State private var activeSheet: FamilySheet?

    private var cardTint: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white.opacity(0.22)
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: familyContextStore.family == nil ? nil : "arrow.clockwise",
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            onTrailingTap: {
                Task {
                    await familyContextStore.refresh(sessionStore: sessionStore)
                }
            },
            contentSpacing: 18
        ) {
            if let lastErrorMessage = familyContextStore.lastErrorMessage {
                FamilyAlertBanner(message: lastErrorMessage)
            }

            if familyContextStore.family == nil {
                emptyStateContent
            } else {
                familyHubContent
            }
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .overview:
                FamilyOverviewScreen()
            case .members:
                FamilyMembersScreen()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                FamilyCreateSheet()
            case .join:
                FamilyJoinSheet()
            case .invite:
                FamilyInviteSheet()
            }
        }
        .task {
            await familyContextStore.refresh(sessionStore: sessionStore)
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(spacing: 18) {
            // Hero illustration card
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.18),
                                    Color.red.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "person.3.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(.top, 8)

                Text(mistiaLocalized(vi: "Chưa có gia đình", en: "No family yet", ja: "家族はまだありません"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text(
                    mistiaLocalized(
                        vi: "Mỗi người vẫn giữ dữ liệu tài chính riêng của mình. Gia đình chỉ thêm lớp tổng hợp, quyền xem và quyền chỉnh sửa.",
                        en: "Everyone keeps their own financial data. Family adds a shared layer for aggregates, visibility, and editing rights.",
                        ja: "各メンバーは自分の財務データを保持したまま、家族では集計・閲覧・編集権限を重ねます。"
                    )
                )
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 12)

            // Action card — Apple grouped style
            MistiaGlassCard(cornerRadius: 14, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    FamilySettingsRow(
                        title: mistiaLocalized(vi: "Tạo gia đình", en: "Create family", ja: "家族を作成"),
                        subtitle: mistiaLocalized(vi: "Bạn trở thành owner và mời thêm thành viên sau.", en: "You become the owner and invite others later.", ja: "作成者が owner になり、あとでメンバーを招待できます。"),
                        icon: "plus.circle.fill",
                        iconColor: .mint
                    ) {
                        activeSheet = .create
                    }

                    FamilyRowDivider()

                    FamilySettingsRow(
                        title: mistiaLocalized(vi: "Nhập mã mời", en: "Join with code", ja: "招待コードで参加"),
                        subtitle: mistiaLocalized(vi: "Dùng mã hoặc link mời từ owner của gia đình.", en: "Use the invite code or link shared by the family owner.", ja: "owner が共有した招待コードまたはリンクを使います。"),
                        icon: "number.circle.fill",
                        iconColor: .cyan
                    ) {
                        activeSheet = .join
                    }
                }
            }
        }
    }

    // MARK: - Hub Content (has family)

    private var familyHubContent: some View {
        VStack(spacing: 18) {
            // Apple-style family header card
            FamilyAppleHeaderCard(
                family: familyContextStore.family,
                currentMembership: familyContextStore.currentMembership,
                members: familyContextStore.members,
                tint: cardTint
            )

            // Actions card — Apple grouped style
            MistiaGlassCard(cornerRadius: 14, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    FamilySettingsRow(
                        title: mistiaLocalized(vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要"),
                        subtitle: mistiaLocalized(vi: "Tài sản, công nợ, sắp đến hạn và top chi tiêu của cả nhà.", en: "Assets, debts, upcoming due items, and top spending across the household.", ja: "家計全体の資産・負債・支払予定・支出の要点を確認します。"),
                        icon: "chart.bar.xaxis",
                        iconColor: .indigo
                    ) {
                        destination = .overview
                    }

                    FamilyRowDivider()

                    FamilySettingsRow(
                        title: mistiaLocalized(vi: "Thành viên", en: "Members", ja: "メンバー"),
                        subtitle: mistiaLocalized(vi: "Xem role, quyền và chọn view as member.", en: "Review roles, permissions, and switch into view-as member.", ja: "役割と権限を確認し、view-as member に切り替えます。"),
                        icon: "person.2.fill",
                        iconColor: Color(red: 0.96, green: 0.36, blue: 0.56)
                    ) {
                        destination = .members
                    }

                    if familyContextStore.canInviteMembers {
                        FamilyRowDivider()

                        FamilySettingsRow(
                            title: mistiaLocalized(vi: "Mời thành viên", en: "Invite member", ja: "メンバーを招待"),
                            subtitle: mistiaLocalized(vi: "Tạo mã mời mặc định 7 ngày và share ngay.", en: "Create a 7-day invite code and share it immediately.", ja: "7 日間有効な招待コードを作成してすぐ共有します。"),
                            icon: "person.badge.plus.fill",
                            iconColor: .mint
                        ) {
                            activeSheet = .invite
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Apple-style Family Header Card

private struct FamilyAppleHeaderCard: View {
    let family: FamilyGroupRecord?
    let currentMembership: FamilyMembershipRecord?
    let members: [FamilyMember]
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MistiaGlassCard(cornerRadius: 14, tint: tint) {
            VStack(spacing: 16) {
                // Avatar stack — Apple Family style, centered
                HStack(spacing: -10) {
                    ForEach(Array(members.prefix(5).enumerated()), id: \.element.membershipID) { index, member in
                        MistiaAvatarBadge(
                            initials: String(member.displayName.prefix(2)).uppercased(),
                            avatarURL: member.avatarURL,
                            size: 52,
                            showsStatus: false
                        )
                        .overlay {
                            Circle().stroke(
                                colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : .white,
                                lineWidth: 3
                            )
                        }
                        .zIndex(Double(members.count - index))
                    }
                }
                .padding(.top, 4)

                // Family name
                VStack(spacing: 6) {
                    Text(family?.name ?? "Mistia Family")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    if let currentMembership {
                        FamilyRoleBadge(role: currentMembership.role)
                    }
                }

                // Member count
                Text(
                    mistiaLocalized(
                        vi: "\(members.count) thành viên",
                        en: "\(members.count) members",
                        ja: "\(members.count) 人のメンバー"
                    )
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Settings-style Row

private struct FamilySettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Apple-style icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.gradient)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 14))
    }
}

// MARK: - Alert Banner

private struct FamilyAlertBanner: View {
    let message: String

    var body: some View {
        MistiaGlassCard(cornerRadius: 14, tint: Color.orange.opacity(0.12)) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mistiaLocalized(vi: "Gia đình cần kiểm tra", en: "Family needs attention", ja: "家族設定の確認が必要です"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    Text(message)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Row Divider

private struct FamilyRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 60)
            .padding(.trailing, 0)
    }
}

// MARK: - Role Badge

private struct FamilyRoleBadge: View {
    let role: FamilyRole

    var body: some View {
        MistiaChip(title: role.title, tint: role.tint)
    }
}

// MARK: - Family Overview Screen

struct FamilyOverviewScreen: View {
    @Environment(\.calendar) private var calendar
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var storedTransactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]

    private var familyMemberIDs: Set<UUID> {
        Set(familyContextStore.members.map(\.userID))
    }

    private var allWallets: [LedgerWallet] {
        FamilyScopedData.visible(
            storedWallets,
            entity: .wallet,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var allTransactions: [LedgerTransaction] {
        FamilyScopedData.visible(
            storedTransactions,
            entity: .transaction,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var summary: FamilyAggregateSummary {
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let startOfMonth = calendar.dateInterval(of: .month, for: .now) ?? DateInterval(start: .distantPast, end: .distantFuture)

        return FamilyLogic.aggregateSummary(
            wallets: allWallets.map { wallet in
                FamilyAggregateWalletSnapshot(
                    ownerUserID: walletOwnerMap[wallet.id] ?? sessionStore.signedInUserID ?? UUID(),
                    kind: wallet.kind.familyAggregateKind,
                    balanceMinor: wallet.kind == .creditCard ? 0 : max(wallet.openingBalanceMinor, 0),
                    debtMinor: wallet.kind == .creditCard ? max(abs(wallet.openingBalanceMinor), 0) : 0
                )
            },
            transactions: allTransactions.map { transaction in
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: transactionOwnerMap[transaction.id] ?? sessionStore.signedInUserID ?? UUID(),
                    categoryName: transaction.category?.localizedDisplayName,
                    occurredAt: transaction.occurredAt,
                    kind: transaction.primaryKind.familyAggregateKind,
                    amountMinor: abs(transaction.amountMinor)
                )
            },
            monthInterval: startOfMonth,
            visibleMemberIDs: familyMemberIDs
        )
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要"),
            contentSpacing: 18
        ) {
            FamilyStatCard(
                title: mistiaLocalized(vi: "Tổng tài sản", en: "Total assets", ja: "総資産"),
                value: summary.totalAssetsMinor.formattedCurrency(code: "JPY")
            )
            FamilyStatCard(
                title: mistiaLocalized(vi: "Tổng công nợ", en: "Total debts", ja: "総負債"),
                value: summary.totalDebtMinor.formattedCurrency(code: "JPY")
            )
            FamilyStatCard(
                title: mistiaLocalized(vi: "Có thể chi", en: "Available to spend", ja: "使える金額"),
                value: summary.spendableMinor.formattedCurrency(code: "JPY")
            )

            MistiaGlassCard(cornerRadius: 14, tint: Color(UIColor.secondarySystemGroupedBackground)) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(mistiaLocalized(vi: "Top chi tháng này", en: "Top spending this month", ja: "今月の主な支出"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    ForEach(summary.expenseByCategory.sorted(by: { $0.value > $1.value }).prefix(3), id: \.key) { item in
                        HStack {
                            Text(item.key)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(item.value.formattedCurrency(code: "JPY"))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Stat Card

private struct FamilyStatCard: View {
    let title: String
    let value: String

    var body: some View {
        MistiaGlassCard(cornerRadius: 14, tint: Color(UIColor.secondarySystemGroupedBackground)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Members Screen

struct FamilyMembersScreen: View {
    @Environment(FamilyContextStore.self) private var familyContextStore

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Thành viên", en: "Members", ja: "メンバー"),
            contentSpacing: 18
        ) {
            ForEach(familyContextStore.members) { member in
                NavigationLink {
                    FamilyMemberProfileScreen(member: member)
                } label: {
                    MistiaGlassCard(cornerRadius: 14, tint: Color(UIColor.secondarySystemGroupedBackground)) {
                        HStack(spacing: 14) {
                            MistiaAvatarBadge(
                                initials: String(member.displayName.prefix(2)).uppercased(),
                                avatarURL: member.avatarURL,
                                size: 42,
                                showsStatus: false
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.displayName)
                                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text(member.role.title)
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Member Profile Screen

private struct FamilyMemberProfileScreen: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    let member: FamilyMember

    @State private var showsPermissionsSheet = false

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: member.displayName,
            contentSpacing: 18
        ) {
            MistiaGlassCard(cornerRadius: 14, tint: Color(UIColor.secondarySystemGroupedBackground)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        MistiaAvatarBadge(
                            initials: String(member.displayName.prefix(2)).uppercased(),
                            avatarURL: member.avatarURL,
                            size: 56,
                            showsStatus: false
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(member.displayName)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            FamilyRoleBadge(role: member.role)
                        }
                    }

                    let capabilities = familyContextStore.capabilities(for: member)
                    if capabilities.canViewTarget {
                        Button(mistiaLocalized(vi: "Xem dữ liệu trong app", en: "View data in app", ja: "アプリでデータを見る")) {
                            familyContextStore.viewMember(member)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
                    }

                    if familyContextStore.canInviteMembers && member.role != .owner {
                        Button(mistiaLocalized(vi: "Chỉnh role & quyền", en: "Edit role & permissions", ja: "役割と権限を編集")) {
                            showsPermissionsSheet = true
                        }
                        .buttonStyle(.glass)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showsPermissionsSheet) {
            FamilyPermissionsSheet(member: member)
        }
    }
}

// MARK: - Create Sheet

private struct FamilyCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var familyName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Gia đình mới", en: "New family", ja: "新しい家族")) {
                    TextField(mistiaLocalized(vi: "Tên gia đình", en: "Family name", ja: "家族名"), text: $familyName)
                }
            }
            .navigationTitle(mistiaLocalized(vi: "Tạo gia đình", en: "Create family", ja: "家族を作成"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(mistiaLocalized(vi: "Tạo", en: "Create", ja: "作成")) {
                        Task {
                            await familyContextStore.createFamily(name: familyName, sessionStore: sessionStore)
                            dismiss()
                        }
                    }
                    .disabled(familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Join Sheet

private struct FamilyJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Mã mời", en: "Invite code", ja: "招待コード")) {
                    TextField("ABCD1234", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(mistiaLocalized(vi: "Tham gia gia đình", en: "Join family", ja: "家族に参加"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(mistiaLocalized(vi: "Tham gia", en: "Join", ja: "参加")) {
                        Task {
                            await familyContextStore.joinFamily(inviteCode: inviteCode, sessionStore: sessionStore)
                            dismiss()
                        }
                    }
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Invite Sheet

private struct FamilyInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var selectedRole: FamilyRole = .viewer
    @State private var createdInvite: FamilyInviteRecord?

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Role mặc định", en: "Default role", ja: "デフォルトの役割")) {
                    Picker(mistiaLocalized(vi: "Role", en: "Role", ja: "役割"), selection: $selectedRole) {
                        ForEach([FamilyRole.viewer, .editor, .kid], id: \.self) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if let createdInvite {
                    Section(mistiaLocalized(vi: "Mã mời mới", en: "New invite code", ja: "新しい招待コード")) {
                        Text(createdInvite.code)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                        ShareLink(item: familyContextStore.shareMessage(for: createdInvite))
                    }
                }
            }
            .navigationTitle(mistiaLocalized(vi: "Mời thành viên", en: "Invite member", ja: "メンバーを招待"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(mistiaLocalized(vi: "Tạo mã", en: "Create code", ja: "コードを作成")) {
                        Task {
                            createdInvite = await familyContextStore.createInvite(
                                defaultRole: selectedRole,
                                sessionStore: sessionStore
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Permissions Sheet

private struct FamilyPermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    let member: FamilyMember

    @State private var role: FamilyRole
    @State private var policy: FamilyPermissionPolicy

    init(member: FamilyMember) {
        self.member = member
        _role = State(initialValue: member.role)
        _policy = State(initialValue: member.policy)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Role", en: "Role", ja: "役割")) {
                    Picker(mistiaLocalized(vi: "Role", en: "Role", ja: "役割"), selection: $role) {
                        ForEach([FamilyRole.viewer, .editor, .kid], id: \.self) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(mistiaLocalized(vi: "Quyền", en: "Permissions", ja: "権限")) {
                    Toggle(mistiaLocalized(vi: "Xem dashboard gia đình", en: "View family dashboard", ja: "家族ダッシュボードを見る"), isOn: $policy.canViewFamilyDashboard)
                    Toggle(mistiaLocalized(vi: "Xem dữ liệu người khác", en: "View others", ja: "他メンバーを表示"), isOn: $policy.canViewOthers)
                    Toggle(mistiaLocalized(vi: "Sửa dữ liệu người khác", en: "Edit others", ja: "他メンバーを編集"), isOn: $policy.canEditOthers)
                    Toggle(mistiaLocalized(vi: "Xem ví / tài khoản", en: "View wallets", ja: "ウォレットを見る"), isOn: $policy.canViewWallets)
                    Toggle(mistiaLocalized(vi: "Xem công nợ", en: "View debts", ja: "負債を見る"), isOn: $policy.canViewDebts)
                    Toggle(mistiaLocalized(vi: "Xem kid", en: "View kids", ja: "kid を表示"), isOn: $policy.canViewKids)
                    Toggle(mistiaLocalized(vi: "Sửa kid", en: "Edit kids", ja: "kid を編集"), isOn: $policy.canEditKids)
                }
            }
            .navigationTitle(mistiaLocalized(vi: "Role & quyền", en: "Role & permissions", ja: "役割と権限"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(mistiaLocalized(vi: "Lưu", en: "Save", ja: "保存")) {
                        Task {
                            await familyContextStore.updateMember(
                                member,
                                role: role,
                                policy: policy,
                                sessionStore: sessionStore
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
        .onChange(of: role) { _, newRole in
            policy = FamilyPermissionPolicy.preset(for: newRole)
        }
    }
}

// MARK: - Role Extensions

private extension FamilyRole {
    var title: String {
        switch self {
        case .owner:
            mistiaLocalized(vi: "Owner", en: "Owner", ja: "Owner")
        case .viewer:
            mistiaLocalized(vi: "Viewer", en: "Viewer", ja: "Viewer")
        case .editor:
            mistiaLocalized(vi: "Editor", en: "Editor", ja: "Editor")
        case .kid:
            mistiaLocalized(vi: "Kid", en: "Kid", ja: "Kid")
        }
    }

    var tint: Color {
        switch self {
        case .owner:
            .orange
        case .viewer:
            .cyan
        case .editor:
            .mint
        case .kid:
            .red
        }
    }
}

// MARK: - Wallet/Transaction Kind Extensions

private extension LedgerWalletKind {
    var familyAggregateKind: FamilyAggregateWalletSnapshot.Kind {
        switch self {
        case .cash:
            .cash
        case .payPay, .eWallet, .prepaid:
            .ewallet
        case .bank:
            .bank
        case .creditCard:
            .creditCard
        case .investment, .crypto, .other:
            .other
        }
    }
}

private extension TransactionPrimaryKind {
    var familyAggregateKind: FamilyAggregateTransactionSnapshot.Kind {
        switch self {
        case .expense:
            .expense
        case .income:
            .income
        case .transfer:
            .transfer
        }
    }
}
