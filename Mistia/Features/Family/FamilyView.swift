import SwiftData
import SwiftUI

private enum FamilyDestination: String, Identifiable {
    case overview

    var id: String { rawValue }
}

private enum FamilySheet: String, Identifiable {
    case create
    case join
    case invite
    case privacy

    var id: String { rawValue }
}

private enum FamilyMemberDestructiveAction: String, Identifiable {
    case deleteFamily
    case leaveFamily
    case removeMember

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

    private var accent: Color {
        colorScheme == .dark
            ? MistiaAccent.lightPurple.color
            : MistiaAccent.purple.color
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: "",
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: familyContextStore.family == nil ? nil : "person.badge.plus",
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            onTrailingTap: {
                activeSheet = .invite
            },
            contentSpacing: 22
        ) {
            if let lastErrorMessage = familyContextStore.lastErrorMessage {
                FamilyAlertBanner(message: lastErrorMessage)
            }

            familyHeaderSection

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
            case .privacy:
                MistiaPrivacySheet()
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
                        .fill(MistiaAccent.purple.color.opacity(0.18))
                        .frame(width: 72, height: 72)

                    Image(systemName: "person.3.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(MistiaAccent.purple.color)
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

    // MARK: - Header Section

    private var familyHeaderSection: some View {
        VStack(spacing: 12) {
            if familyContextStore.family != nil && !familyContextStore.members.isEmpty {
                // Avatars for family
                HStack(spacing: -14) {
                    ForEach(Array(familyContextStore.members.prefix(5).enumerated()), id: \.element.membershipID) { index, member in
                        MistiaAvatarBadge(
                            initials: String(member.displayName.prefix(2)).uppercased(),
                            avatarURL: member.avatarURL,
                            size: 64,
                            showsStatus: false
                        )
                        .overlay {
                            Circle().stroke(
                                colorScheme == .dark ? Color.black : .white,
                                lineWidth: 3
                            )
                        }
                        .zIndex(Double(familyContextStore.members.count - index))
                    }
                }
                
                VStack(spacing: 4) {
                    Text(familyContextStore.family?.name ?? "Mistia Family")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            } else {
                // Single avatar for individual
                MistiaAvatarBadge(
                    initials: sessionStore.summary?.initials ?? "M",
                    avatarURL: sessionStore.summary?.avatarURL,
                    size: 64,
                    showsStatus: false
                )

                Text(mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Hub Content (has family)

    private var familyHubContent: some View {
        VStack(spacing: 12) {
            // Member List Card
            MistiaGlassCard(cornerRadius: 18, tint: cardTint, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(familyContextStore.members.enumerated()), id: \.element.membershipID) { index, member in
                            NavigationLink {
                                FamilyMemberProfileScreen(member: member)
                            } label: {
                                HStack(spacing: 14) {
                                    MistiaAvatarBadge(
                                        initials: String(member.displayName.prefix(2)).uppercased(),
                                        avatarURL: member.avatarURL,
                                        size: 40,
                                        showsStatus: false
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 4) {
                                            Text(member.role.title)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                            
                                            if member.userID == sessionStore.signedInUserID {
                                                Text(mistiaLocalized(vi: "(Bạn)", en: "(You)", ja: "(自分)"))
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                            if index < familyContextStore.members.count - 1 {
                                Divider()
                                    .padding(.leading, 70)
                            }
                        }
                    }
                }

            // Member description
            VStack(alignment: .leading, spacing: 4) {
                Text(mistiaLocalized(
                    vi: "Bạn có thể kiểm tra những gì các thành viên trong gia đình có thể truy cập hoặc chia sẻ, đồng thời quản lý cài đặt tài khoản của trẻ em và các kiểm soát của phụ huynh.",
                    en: "You can check what family members can access or share, while managing child account settings and parental controls.",
                    ja: "ファミリーメンバーがアクセスまたは共有できるもの確認でき、お子様のアカウント設定と保護者による制限を管理できます。"
                ))
                .descriptionTextStyle()
                .padding(.horizontal, 2)
            }
            .cardDescriptionStyle()

            // Overview Block
            MistiaGlassCard(cornerRadius: 18, tint: cardTint, padding: 0) {
                FamilySettingsRow(
                    title: mistiaLocalized(vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要"),
                    subtitle: mistiaLocalized(vi: "Tài sản, công nợ, sắp đến hạn và top chi tiêu của cả nhà.", en: "Assets, debts, upcoming due items, and top spending across the household.", ja: "家計全体の資産・負債・支払予定・支出の要点を確認します。"),
                    icon: "chart.bar.xaxis",
                    iconColor: .indigo
                ) {
                    destination = .overview
                }
            }

            // Privacy Link
            VStack(alignment: .leading, spacing: 6) {
                Text(mistiaLocalized(
                    vi: "Mistia sẽ sử dụng dữ liệu để đồng bộ và hiển thị thông tin gia đình của bạn một cách an toàn.",
                    en: "Mistia will use data to securely sync and display your family information.",
                    ja: "Mistiaはデータを安全に同期し、家族情報を表示するために使用します。"
                ))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)

                Button {
                    activeSheet = .privacy
                } label: {
                    Text(mistiaLocalized(
                        vi: "Xác nhận sử dụng dữ liệu & thông tin cá nhân",
                        en: "Confirm data & personal information usage",
                        ja: "データおよび個人情報の使用を確認する"
                    ))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
            .cardDescriptionStyle()
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
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 14))
            }
        }
    }
}

// MARK: - Member Profile Screen

private struct FamilyMemberProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    let member: FamilyMember

    @State private var showsPermissionsSheet = false
    @State private var destructiveAction: FamilyMemberDestructiveAction?

    private var isMe: Bool {
        member.userID == sessionStore.signedInUserID
    }

    private var isOwner: Bool {
        familyContextStore.currentRole == .owner
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: "",
            leadingSystemImage: "chevron.left",
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 22
        ) {
            // Profile Header
            VStack(spacing: 12) {
                MistiaAvatarBadge(
                    initials: String(member.displayName.prefix(2)).uppercased(),
                    avatarURL: member.avatarURL,
                    size: 80,
                    showsStatus: false
                )

                VStack(spacing: 4) {
                    Text(member.displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    FamilyRoleBadge(role: member.role)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 10)

            if !isMe {
                // Roles & Permissions Card (Moved to First position)
                if isOwner && member.role != .owner {
                    VStack(alignment: .leading, spacing: 0) {
                        MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
                            Button {
                                showsPermissionsSheet = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.badge.key.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 32)

                                    Text(mistiaLocalized(vi: "Role & Quyền hạn", en: "Role & Permissions", ja: "役割と権限"))
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                        }

                        Text(mistiaLocalized(
                            vi: "Thiết lập quyền xem hoặc chỉnh sửa dữ liệu cho thành viên này trong gia đình.",
                            en: "Configure viewing or editing permissions for this member.",
                            ja: "このメンバーの閲覧・編集権限を設定します。"
                        ))
                        .descriptionTextStyle()
                    }
                    .cardDescriptionStyle()
                }

                // View Data Card (Moved to Second position)
                let capabilities = familyContextStore.capabilities(for: member)
                if capabilities.canViewTarget {
                    VStack(alignment: .leading, spacing: 0) {
                        MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
                            Button {
                                Task {
                                    await familyContextStore.viewMember(member)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    if familyContextStore.isSwitchingContext {
                                        ProgressView()
                                            .frame(width: 32)
                                    } else {
                                        Image(systemName: "eye.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(MistiaAccent.purple.color)
                                            .frame(width: 32)
                                    }

                                    Text(mistiaLocalized(
                                        vi: "Xem dữ liệu của \(member.displayName)",
                                        en: "View \(member.displayName)'s data",
                                        ja: "\(member.displayName)のデータを見る"
                                    ))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                            .disabled(familyContextStore.isSwitchingContext)
                        }

                        Text(mistiaLocalized(
                            vi: "Xem các giao dịch, ví và ngân sách mà \(member.displayName) đã chia sẻ với gia đình.",
                            en: "View transactions, wallets, and budgets shared by \(member.displayName).",
                            ja: "\(member.displayName)が共有した履歴やウォレットを確認します。"
                        ))
                        .descriptionTextStyle()
                    }
                    .cardDescriptionStyle()
                }
            }

            // Destructive Actions
            if isMe || isOwner {
                VStack(alignment: .leading, spacing: 0) {
                    MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
                        Button {
                            destructiveAction = isMe ? (isOwner ? .deleteFamily : .leaveFamily) : .removeMember
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: isMe && isOwner ? "trash.fill" : "person.badge.minus.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                                    .frame(width: 32)

                                Text(
                                    isMe
                                        ? (isOwner
                                           ? mistiaLocalized(vi: "Xóa gia đình", en: "Delete family", ja: "家族を削除")
                                           : mistiaLocalized(vi: "Rời khỏi gia đình", en: "Leave family", ja: "家族を退会"))
                                        : (isOwner
                                           ? mistiaLocalized(vi: "Xóa \(member.displayName) khỏi gia đình", en: "Remove \(member.displayName)", ja: "\(member.displayName)を削除")
                                           : "")
                                )
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                    }

                    Text(
                        isMe
                            ? (isOwner
                               ? mistiaLocalized(
                                    vi: "Tất cả dữ liệu chia sẻ và kết nối gia đình sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.",
                                    en: "All shared data and family connections will be permanently deleted. This cannot be undone.",
                                    ja: "共有データと家族のつながりはすべて完全に削除されます。この操作は取り消せません。"
                               )
                               : mistiaLocalized(
                                    vi: "Bạn sẽ không còn quyền truy cập vào dữ liệu chung của gia đình này nữa.",
                                    en: "You will no longer have access to this family's shared data.",
                                    ja: "この家族の共有データにアクセスできなくなります。"
                               ))
                            : (isOwner
                               ? mistiaLocalized(
                                    vi: "Thành viên này sẽ bị xóa khỏi gia đình và không còn quyền truy cập dữ liệu chung.",
                                    en: "This member will be removed and lose access to shared data.",
                                    ja: "このメンバーは家族から削除され、共有データにアクセスできなくなります。"
                               )
                               : "")
                    )
                    .descriptionTextStyle()
                }
                .cardDescriptionStyle()
            }
        }
        .sheet(isPresented: $showsPermissionsSheet) {
            FamilyPermissionsSheet(member: member)
        }
        .confirmationDialog(
            destructiveActionTitle,
            isPresented: Binding(
                get: { destructiveAction != nil },
                set: { if !$0 { destructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(destructiveActionButtonTitle, role: .destructive) {
                let action = destructiveAction
                destructiveAction = nil
                Task {
                    switch action {
                    case .deleteFamily:
                        await familyContextStore.deleteFamily(sessionStore: sessionStore)
                    case .leaveFamily, .removeMember:
                        await familyContextStore.removeMember(member, sessionStore: sessionStore)
                    case nil:
                        break
                    }
                    dismiss()
                }
            }
            
            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {
                destructiveAction = nil
            }
        } message: {
            Text(destructiveActionMessage)
        }
    }

    private var destructiveActionTitle: String {
        switch destructiveAction {
        case .deleteFamily:
            return mistiaLocalized(vi: "Xóa gia đình?", en: "Delete family?", ja: "家族を削除しますか？")
        case .leaveFamily:
            return mistiaLocalized(vi: "Rời khỏi gia đình?", en: "Leave family?", ja: "家族を退会しますか？")
        case .removeMember:
            return mistiaLocalized(vi: "Xóa thành viên?", en: "Remove member?", ja: "メンバーを削除しますか？")
        case nil:
            return ""
        }
    }

    private var destructiveActionButtonTitle: String {
        switch destructiveAction {
        case .deleteFamily:
            return mistiaLocalized(vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除")
        case .leaveFamily:
            return mistiaLocalized(vi: "Rời khỏi", en: "Leave", ja: "退会")
        case .removeMember:
            return mistiaLocalized(vi: "Xóa khỏi gia đình", en: "Remove from family", ja: "家族から削除")
        case nil:
            return ""
        }
    }

    private var destructiveActionMessage: String {
        switch destructiveAction {
        case .deleteFamily:
            return mistiaLocalized(
                vi: "Tất cả dữ liệu chia sẻ và kết nối gia đình sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.",
                en: "All shared data and family connections will be permanently deleted. This cannot be undone.",
                ja: "共有データと家族のつながりはすべて完全に削除されます。この操作は取り消せません。"
            )
        case .leaveFamily:
            return mistiaLocalized(
                vi: "Bạn sẽ không còn quyền truy cập vào dữ liệu chung của gia đình này nữa.",
                en: "You will no longer have access to this family's shared data.",
                ja: "この家族の共有データにアクセスできなくなります。"
            )
        case .removeMember:
            return mistiaLocalized(
                vi: "Thành viên này sẽ bị xóa khỏi gia đình và không còn quyền truy cập dữ liệu chung.",
                en: "This member will be removed and lose access to shared data.",
                ja: "このメンバーは家族から削除され、共有データにアクセスできなくなります。"
            )
        case nil:
            return ""
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
            .dismissKeyboardOnTap()
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
            .dismissKeyboardOnTap()
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
            .dismissKeyboardOnTap()
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
            .dismissKeyboardOnTap()
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
            mistiaLocalized(vi: "Chủ sở hữu", en: "Owner", ja: "Owner")
        case .viewer:
            mistiaLocalized(vi: "Thành viên", en: "Viewer", ja: "Viewer")
        case .editor:
            mistiaLocalized(vi: "Quản trị viên", en: "Editor", ja: "Editor")
        case .kid:
            mistiaLocalized(vi: "Trẻ con", en: "Kid", ja: "Kid")
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
