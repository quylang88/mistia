import Charts
import SwiftData
import SwiftUI
import UIKit

private enum FamilyDestination: String, Identifiable {
    case overview
    case inviteManagement

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

private enum FamilyMemberProfileAction: String, Identifiable {
    case sharing
    case permissions
    case transferOwner
    case viewData
    case destructive

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

    private var visibleErrorMessage: String? {
        guard let lastErrorMessage = familyContextStore.lastErrorMessage else {
            return nil
        }

        if lastErrorMessage == sessionStore.remoteUnavailableReason {
            return nil
        }

        if familyContextStore.family == nil && shouldSuppressNoFamilyPermissionError(lastErrorMessage) {
            return nil
        }

        return lastErrorMessage
    }

    private var remoteActionsDisabled: Bool {
        !sessionStore.canPerformRemoteActions
    }

    private var remoteActionsDisabledReason: String? {
        remoteActionsDisabled ? sessionStore.remoteUnavailableReason : nil
    }

    private var showsOfflineEmptyState: Bool {
        remoteActionsDisabled && familyContextStore.family == nil && !familyContextStore.hasCachedRemoteState
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: "",
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: familyContextStore.family == nil || remoteActionsDisabled || !familyContextStore.canInviteMembers ? nil : "person.badge.plus",
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            onTrailingTap: {
                activeSheet = .invite
            },
            onRefresh: {
                await familyContextStore.refreshLatest(
                    sessionStore: sessionStore,
                    source: .userInitiated
                )
            },
            contentSpacing: 22
        ) {
            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                FamilyAlertBanner(message: remoteUnavailableReason)
            }

            if let visibleErrorMessage {
                FamilyAlertBanner(message: visibleErrorMessage)
            }

            familyHeaderSection

            if showsOfflineEmptyState {
                offlineEmptyStateContent
            } else if familyContextStore.family == nil {
                emptyStateContent
            } else {
                familyHubContent
            }
        }
        .overlay(alignment: .topTrailing) {
            if familyContextStore.isRefreshingLatest {
                FamilySyncOverlayIndicator()
                    .padding(.top, 12)
                    .padding(.trailing, 18)
            }
        }
        .navigationDestination(item: $destination) { route in
            switch route {
            case .overview:
                FamilyOverviewScreen()
            case .inviteManagement:
                FamilyInviteManagementScreen()
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
            await familyContextStore.refreshLatest(
                sessionStore: sessionStore,
                source: .enterFamily
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        MistiaGlassCard(cornerRadius: 14, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                FamilySettingsRow(
                    title: mistiaLocalized(vi: "Tạo gia đình", en: "Create family", ja: "家族を作成"),
                    subtitle: remoteActionsDisabledReason ?? mistiaLocalized(vi: "Bạn trở thành owner và mời thêm thành viên sau.", en: "You become the owner and invite others later.", ja: "作成者が owner になり、あとでメンバーを招待できます。"),
                    icon: "plus",
                    iconColor: .mint,
                    isDisabled: remoteActionsDisabled
                ) {
                    activeSheet = .create
                }

                FamilyRowDivider()

                FamilySettingsRow(
                    title: mistiaLocalized(vi: "Dùng link mời", en: "Use invite link", ja: "招待リンクを使う"),
                    subtitle: remoteActionsDisabledReason ?? mistiaLocalized(vi: "Bấm link owner đã chia sẻ, hoặc dán link nếu bạn đã copy.", en: "Tap the owner's shared link, or paste the link if you've copied it.", ja: "owner が共有したリンクを開くか、コピー済みのリンクを貼り付けます。"),
                    icon: "link",
                    iconColor: .cyan,
                    isDisabled: remoteActionsDisabled
                ) {
                    activeSheet = .join
                }
            }
        }
    }

    private var offlineEmptyStateContent: some View {
        MistiaGlassCard(cornerRadius: 14, tint: cardTint, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    mistiaLocalized(
                        vi: "Gia đình đang chờ kết nối",
                        en: "Family is waiting for the connection",
                        ja: "家族機能は接続待ちです"
                    ),
                    systemImage: "wifi.slash"
                )
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

                Text(sessionStore.remoteUnavailableReason ?? mistiaLocalized(
                    vi: "Kết nối lại mạng để tạo gia đình mới, dùng link mời hoặc đồng bộ lại dữ liệu gia đình.",
                    en: "Reconnect to create a family, use an invite link, or sync family data again.",
                    ja: "ネットワークに再接続すると、家族の作成、招待リンクの使用、家族データの再同期が行えます。"
                ))
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

            FamilyHubRouteSection(rows: familyHubRouteRows, tint: cardTint) { row in
                destination = row.destination
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

    private var familyHubRouteRows: [FamilyHubRouteRowItem] {
        var rows = [
            FamilyHubRouteRowItem(
                destination: .overview,
                title: mistiaLocalized(vi: "Tổng quan gia đình", en: "Family overview", ja: "家族の概要"),
                icon: "chart.bar.xaxis",
                iconColor: .indigo
            )
        ]

        if familyContextStore.canInviteMembers {
            rows.append(
                FamilyHubRouteRowItem(
                    destination: .inviteManagement,
                    title: mistiaLocalized(vi: "Quản lý lời mời", en: "Manage invites", ja: "招待を管理"),
                    icon: "link.badge.plus",
                    iconColor: .cyan
                )
            )
        }

        return rows
    }

    private func shouldSuppressNoFamilyPermissionError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("permission denied")
            && (normalized.contains("family_memberships") || normalized.contains("family membership"))
    }
}

// MARK: - Family Overview Support

private enum FamilyTimeframe: String, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return mistiaLocalized(vi: "Tuần", en: "Week", ja: "週")
        case .month: return mistiaLocalized(vi: "Tháng", en: "Month", ja: "月")
        case .year: return mistiaLocalized(vi: "Năm", en: "Year", ja: "年")
        }
    }
}

private enum FamilyDistributionMode: String, CaseIterable, Identifiable {
    case spending, accounts, members
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spending: return mistiaLocalized(vi: "Chi tiêu", en: "Spending", ja: "支出")
        case .accounts: return mistiaLocalized(vi: "Tài khoản", en: "Accounts", ja: "口座")
        case .members: return mistiaLocalized(vi: "Thành viên", en: "Members", ja: "メンバー")
        }
    }
}

private enum FamilyComparisonMode: String, CaseIterable, Identifiable {
    case spending, income
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spending: return mistiaLocalized(vi: "Chi tiêu", en: "Spending", ja: "支出")
        case .income: return mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
        }
    }
}

private enum FamilyOverviewSheet: String, Identifiable {
    case invite
    case filterTransactions
    var id: String { rawValue }
}

private struct FamilyAggregateWalletRow: Identifiable {
    let wallet: LedgerWallet
    let currentBalanceMinor: Int64

    var id: UUID { wallet.id }
}

private struct FamilyOverviewDerivedData {
    let walletRows: [FamilyAggregateWalletRow]
    let summary: FamilyAggregateSummary
    let monthlySpendable: FamilyMonthlySpendableSnapshot
    let categorySpendingSnapshot: OverviewCategorySpendingMonthSnapshot
    let budgetRows: [OverviewBudgetAlertSnapshot]
    let dueAlerts: [OverviewDueAlertSnapshot]
}

private struct FamilyHubRouteRowItem: Identifiable {
    let destination: FamilyDestination
    let title: String
    let icon: String
    let iconColor: Color

    var id: FamilyDestination { destination }
}

private struct FamilyChartSegment: Identifiable {
    let label: String
    let valueMinor: Int64
    let color: Color

    var id: String { label }

    var asDonutSegment: FamilyDonutSegment {
        FamilyDonutSegment(label: label, valueMinor: valueMinor, colorHex: nil)
    }
}

// MARK: - Hero Components

private struct FamilyHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: FamilyAggregateSummary
    let monthlySpendable: FamilyMonthlySpendableSnapshot
    let currencyCode: String

    var body: some View {
        MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mistiaLocalized(vi: "Tổng tài sản", en: "Total assets", ja: "総資産"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text(summary.totalAssetsMinor.formattedCurrency(code: currencyCode))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    // Mini trend chart
                    FamilyMiniTrendChart(points: summary.assetTrend)
                        .frame(width: 80, height: 40)
                }

                HStack(spacing: 20) {
                    FamilyMetricCompact(
                        title: mistiaLocalized(vi: "Đang nợ", en: "Current debt", ja: "現在の負債"),
                        value: summary.totalDebtMinor.formattedCurrency(code: currencyCode),
                        color: .red
                    )
                    
                    FamilyMetricCompact(
                        title: mistiaLocalized(vi: "Có thể chi tháng này", en: "Spendable this month", ja: "今月使える金額"),
                        value: monthlySpendable.displayMinor.formattedCurrency(code: currencyCode),
                        color: MistiaAccent.income.color
                    )
                }

                if monthlySpendable.isShortfall {
                    FamilySpendableWarning(
                        shortfallMinor: monthlySpendable.shortfallMinor,
                        currencyCode: currencyCode
                    )
                }
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }
}

private struct FamilyMetricCompact: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FamilySpendableWarning: View {
    @Environment(\.colorScheme) private var colorScheme
    let shortfallMinor: Int64
    let currencyCode: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MistiaAccent.amber.color)

            Text(warningText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(warningForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MistiaAccent.amber.color.opacity(colorScheme == .dark ? 0.14 : 0.12))
        }
    }

    private var warningText: String {
        let amount = shortfallMinor.formattedCurrency(code: currencyCode)
        return mistiaLocalized(
            vi: "Cần bù thêm \(amount) trong tháng này.",
            en: "Need \(amount) more this month.",
            ja: "今月あと \(amount) 必要です。"
        )
    }

    private var warningForeground: Color {
        colorScheme == .dark ? MistiaAccent.amber.color : Color(red: 0.67, green: 0.32, blue: 0.04)
    }
}

// MARK: - Distribution Components

private struct FamilyOverviewSectionTitleStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(titleColor)
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }
}

private extension View {
    func familyOverviewSectionTitleStyle() -> some View {
        modifier(FamilyOverviewSectionTitleStyle())
    }
}

private struct FamilyDistributionSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: FamilyAggregateSummary
    let categorySpendingSnapshot: OverviewCategorySpendingMonthSnapshot
    @Binding var timeframe: FamilyTimeframe
    @Binding var mode: FamilyDistributionMode
    let currencyCode: String
    let onSegmentTap: (FamilyDonutSegment) -> Void

    var body: some View {
        if availableModes.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 12) {
                Picker("", selection: $timeframe) {
                    ForEach(FamilyTimeframe.allCases) { tf in
                        Text(tf.title).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)

                MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(mistiaLocalized(vi: "Phân bổ", en: "Distribution", ja: "内訳"))
                                .familyOverviewSectionTitleStyle()

                            Spacer(minLength: 10)

                            Text(totalValueMinor.formattedCurrency(code: currencyCode))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Picker("", selection: resolvedModeBinding) {
                            ForEach(availableModes) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)

                        if resolvedMode == .spending {
                            MistiaCategorySpendingChartView(
                                snapshot: categorySpendingSnapshot,
                                resetKey: "family-\(timeframe.rawValue)-\(categorySpendingSignature)",
                                accessibilityPrefix: "family.category"
                            )
                        } else {
                            HStack(alignment: .top, spacing: 14) {
                                FamilyPieChart(segments: chartSegments) { segment in
                                    onSegmentTap(segment.asDonutSegment)
                                }
                                .frame(width: 150, height: 150)
                                .frame(width: 150)

                                FamilyPieLegendList(
                                    segments: chartSegments,
                                    totalValueMinor: totalValueMinor,
                                    currencyCode: currencyCode
                                ) { segment in
                                    onSegmentTap(segment.asDonutSegment)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture().onEnded { value in
                        if value.translation.width > 50 {
                            switchTimeframe(back: true)
                        } else if value.translation.width < -50 {
                            switchTimeframe(back: false)
                        }
                    }
                )
            }
            .onAppear(perform: normalizeMode)
            .onChange(of: availableModeKey) { _, _ in
                normalizeMode()
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }

    private var availableModes: [FamilyDistributionMode] {
        FamilyDistributionMode.allCases.filter { mode in
            switch mode {
            case .spending:
                return !categorySpendingSnapshot.slices.isEmpty
            case .accounts, .members:
                return !chartSegments(for: mode).isEmpty
            }
        }
    }

    private var availableModeKey: String {
        "\(availableModes.map(\.rawValue).joined(separator: "|"))-\(categorySpendingSignature)"
    }

    private var categorySpendingSignature: String {
        categorySpendingSnapshot.slices
            .map { "\($0.id):\($0.amountMinor):\($0.childSlices.map(\.id).joined(separator: ","))" }
            .joined(separator: "|")
    }

    private var resolvedMode: FamilyDistributionMode {
        availableModes.contains(mode) ? mode : (availableModes.first ?? mode)
    }

    private var resolvedModeBinding: Binding<FamilyDistributionMode> {
        Binding(
            get: { resolvedMode },
            set: { selectedMode in
                withAnimation(.snappy) {
                    mode = selectedMode
                }
            }
        )
    }

    private func baseSegments(for mode: FamilyDistributionMode) -> [FamilyDonutSegment] {
        switch mode {
        case .spending:
            return summary.expenseByCategory
        case .accounts:
            return summary.balanceByWalletKind
                .map {
                    FamilyDonutSegment(
                        label: walletKindTitle($0.key),
                        valueMinor: $0.value,
                        colorHex: nil
                    )
                }
                .sorted { $0.valueMinor > $1.valueMinor }
        case .members:
            return summary.spendingByMember.map { FamilyDonutSegment(label: $0.name, valueMinor: $0.amountMinor, colorHex: nil) }
        }
    }

    private var chartSegments: [FamilyChartSegment] {
        chartSegments(for: resolvedMode)
    }

    private func chartSegments(for mode: FamilyDistributionMode) -> [FamilyChartSegment] {
        let filtered = baseSegments(for: mode)
            .map { FamilyDonutSegment(label: $0.label, valueMinor: max($0.valueMinor, 0), colorHex: $0.colorHex) }
            .filter { $0.valueMinor > 0 }
            .sorted { $0.valueMinor > $1.valueMinor }

        guard !filtered.isEmpty else { return [] }

        let leading = Array(filtered.prefix(5))
        let remainder = filtered.dropFirst(5)

        var displaySegments = leading
        if !remainder.isEmpty {
            let otherValue = remainder.reduce(into: Int64.zero) { partial, segment in
                partial += segment.valueMinor
            }
            displaySegments.append(
                FamilyDonutSegment(
                    label: mistiaLocalized(vi: "Khác", en: "Other", ja: "その他"),
                    valueMinor: otherValue,
                    colorHex: nil
                )
            )
        }

        return displaySegments.enumerated().map { index, segment in
            FamilyChartSegment(
                label: segment.label,
                valueMinor: segment.valueMinor,
                color: chartColor(for: index)
            )
        }
    }

    private var totalValueMinor: Int64 {
        if resolvedMode == .spending {
            return categorySpendingSnapshot.totalExpenseMinor
        }

        return chartSegments.reduce(into: Int64.zero) { partial, segment in
            partial += segment.valueMinor
        }
    }

    private func chartColor(for index: Int) -> Color {
        let palette: [Color] = [
            Color(hex: "#2DAA9E"),
            Color(hex: "#5B7BFF"),
            Color(hex: "#5FAEFF"),
            Color(hex: "#F59B3F"),
            Color(hex: "#F45C7E"),
            MistiaAccent.slate.color
        ]

        return palette[index % palette.count]
    }

    private func walletKindTitle(_ kind: FamilyAggregateWalletSnapshot.Kind) -> String {
        switch kind {
        case .cash:
            return mistiaLocalized(vi: "Tiền mặt", en: "Cash", ja: "現金")
        case .bank:
            return mistiaLocalized(vi: "Ngân hàng", en: "Bank", ja: "銀行")
        case .ewallet:
            return mistiaLocalized(vi: "Ví điện tử", en: "E-wallet", ja: "電子ウォレット")
        case .creditCard:
            return mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード")
        case .other:
            return mistiaLocalized(vi: "Khác", en: "Other", ja: "その他")
        }
    }

    private func normalizeMode() {
        guard !availableModes.isEmpty, !availableModes.contains(mode), let firstMode = availableModes.first else {
            return
        }

        mode = firstMode
    }

    private func switchTimeframe(back: Bool) {
        let all = FamilyTimeframe.allCases
        if let currentIdx = all.firstIndex(of: timeframe) {
            let nextIdx = back ? max(0, currentIdx - 1) : min(all.count - 1, currentIdx + 1)
            withAnimation(.snappy) {
                timeframe = all[nextIdx]
            }
        }
    }
}

private struct FamilyPieChart: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAngle: Double?

    let segments: [FamilyChartSegment]
    let onSelectSegment: (FamilyChartSegment) -> Void

    private var prominentSegment: FamilyChartSegment? {
        segments.max { $0.valueMinor < $1.valueMinor }
    }

    private var prominentColor: Color {
        prominentSegment?.color ?? MistiaAccent.income.color
    }

    var body: some View {
        ZStack {
            if segments.count != 1 {
                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
                    }
            }

            if let singleSegment = segments.first, segments.count == 1 {
                FamilySingleSegmentSemiGauge(tint: singleSegment.color)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectSegment(singleSegment)
                    }
            } else {
                Chart(segments) { segment in
                    let isProminent = segment.id == prominentSegment?.id

                    SectorMark(
                        angle: .value("Giá trị", Double(segment.valueMinor)),
                        innerRadius: .ratio(0.0),
                        outerRadius: .ratio(isProminent ? 1.0 : 0.92),
                        angularInset: 1.8
                    )
                    .cornerRadius(isProminent ? 7 : 4)
                    .foregroundStyle(segment.color.gradient)
                    .opacity(isProminent ? 1 : 0.90)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngle)
                .padding(2)
            }
        }
        .shadow(color: prominentColor.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 12, y: 5)
        .onChange(of: selectedAngle) { _, value in
            guard let value,
                  let segment = segment(at: value)
            else {
                return
            }

            onSelectSegment(segment)
            DispatchQueue.main.async {
                selectedAngle = nil
            }
        }
    }

    private func segment(at selectedValue: Double) -> FamilyChartSegment? {
        var lowerBound = 0.0

        for segment in segments {
            let upperBound = lowerBound + Double(segment.valueMinor)
            if selectedValue >= lowerBound && selectedValue <= upperBound {
                return segment
            }
            lowerBound = upperBound
        }

        return nil
    }
}

private struct FamilySingleSegmentSemiGauge: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    private let lineWidth: CGFloat = 14

    var body: some View {
        ZStack(alignment: .bottom) {
            FamilySingleSegmentSemiGaugeArc(progress: 1)
                .stroke(
                    colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            FamilySingleSegmentSemiGaugeArc(progress: 1)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .shadow(color: tint.opacity(colorScheme == .dark ? 0.30 : 0.22), radius: 5, y: 2)

            Text("100%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.bottom, 2)
        }
        .frame(width: 132, height: 72)
        .frame(width: 150, height: 104, alignment: .center)
        .accessibilityLabel(mistiaLocalized(vi: "Một mục chiếm toàn bộ", en: "Single item fills the chart", ja: "1つの項目が全体を占めています"))
    }
}

private struct FamilySingleSegmentSemiGaugeArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(progress, 0), 1)
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * clamped),
            clockwise: false
        )
        return path
    }
}

private struct FamilyPieLegendList: View {
    let segments: [FamilyChartSegment]
    let totalValueMinor: Int64
    let currencyCode: String
    let onSelectSegment: (FamilyChartSegment) -> Void

    private var showsPercentage: Bool {
        segments.count > 1
    }

    var body: some View {
        VStack(spacing: 7) {
            ForEach(segments) { segment in
                Button {
                    onSelectSegment(segment)
                } label: {
                    FamilyPieLegendRow(
                        segment: segment,
                        totalValueMinor: totalValueMinor,
                        currencyCode: currencyCode,
                        showsPercentage: showsPercentage
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: showsPercentage ? nil : 150, alignment: showsPercentage ? .topLeading : .center)
    }
}

private struct FamilyPieLegendRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let segment: FamilyChartSegment
    let totalValueMinor: Int64
    let currencyCode: String
    let showsPercentage: Bool

    private var percentageText: String {
        guard totalValueMinor > 0 else { return "0%" }
        let percentage = Double(segment.valueMinor) / Double(totalValueMinor) * 100
        return "\(Int(percentage.rounded()))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(segment.color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(segment.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(segment.valueMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 6)

            if showsPercentage {
                Text(percentageText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(segment.color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? .white.opacity(0.035) : .white.opacity(0.50))
        }
    }
}

// MARK: - Comparison Components

private struct FamilyMemberComparisonSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: FamilyAggregateSummary
    @Binding var mode: FamilyComparisonMode
    let currencyCode: String

    var body: some View {
        if availableModes.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(mistiaLocalized(vi: "So sánh thành viên", en: "Member comparison", ja: "メンバー比較"))
                        .familyOverviewSectionTitleStyle()

                    Spacer()

                    if availableModes.count > 1 {
                        Picker("", selection: $mode) {
                            ForEach(availableModes) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                .padding(.horizontal, 4)

                MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
                    VStack(spacing: 20) {
                        ForEach(members) { m in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(m.name)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Text(m.amountMinor.formattedCurrency(code: currencyCode))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.05))
                                            .frame(height: 10)

                                        Capsule()
                                            .fill(MistiaAccent.income.color.gradient)
                                            .frame(width: geo.size.width * CGFloat(ratio(for: m.amountMinor)), height: 10)
                                    }
                                }
                                .frame(height: 10)
                            }
                        }
                    }
                }
            }
            .onAppear(perform: normalizeMode)
            .onChange(of: availableModeKey) { _, _ in
                normalizeMode()
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }

    private var availableModes: [FamilyComparisonMode] {
        FamilyComparisonMode.allCases.filter { !members(for: $0).isEmpty }
    }

    private var availableModeKey: String {
        availableModes.map(\.rawValue).joined(separator: "|")
    }

    private var resolvedMode: FamilyComparisonMode {
        availableModes.contains(mode) ? mode : (availableModes.first ?? mode)
    }

    private var members: [FamilyMemberSpendingSnapshot] {
        members(for: resolvedMode)
    }

    private func members(for mode: FamilyComparisonMode) -> [FamilyMemberSpendingSnapshot] {
        mode == .spending ? summary.spendingByMember : summary.incomeByMember
    }

    private func ratio(for amount: Int64) -> Double {
        let maxAmount = members.map(\.amountMinor).max() ?? 1
        return Double(max(amount, 0)) / Double(max(maxAmount, 1))
    }

    private func normalizeMode() {
        guard !availableModes.isEmpty, !availableModes.contains(mode), let firstMode = availableModes.first else {
            return
        }

        mode = firstMode
    }
}

// MARK: - Account List Components

private struct FamilyAggregateAccountList: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [FamilyAggregateWalletRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mistiaLocalized(vi: "Danh sách tài khoản gộp", en: "Merged accounts", ja: "統合口座リスト"))
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            MistiaFinanceIconView(icon: row.wallet.kind.defaultIconSymbolName, fallbackColor: MistiaAccent.purple.color, size: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.wallet.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                
                                if row.wallet.kind == .creditCard {
                                    Text(mistiaLocalized(vi: "Sắp đến hạn", en: "Upcoming", ja: "間もなく期限"))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Spacer()
                            
                            Text(row.currentBalanceMinor.formattedCurrency(code: row.wallet.currencyCode))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(amountColor(for: row))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }

    private func amountColor(for row: FamilyAggregateWalletRow) -> Color {
        if row.wallet.kind == .creditCard {
            // For credit cards, show available credit in green (positive)
            return MistiaAccent.income.color
        }
        if row.currentBalanceMinor < 1000 {
            return MistiaAccent.expense.color
        }
        return .primary
    }
}

// MARK: - Budget & Upcoming Components

private struct FamilyBudgetStatusSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [OverviewBudgetAlertSnapshot]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mistiaLocalized(vi: "Ngân sách gia đình", en: "Family budget", ja: "家族の予算"))
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(mistiaLocalized(vi: "Chưa có ngân sách nào đang toang", en: "No budgets are over limit", ja: "予算オーバーはありません"))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(row.name)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Text(row.progressPercentText)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(MistiaAccent.purple.color)
                                }
                                
                                ProgressView(value: min(max(row.progress, 0), 1))
                                    .tint(MistiaAccent.purple.color)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            
                            if index < rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }
}

private struct FamilyUpcomingSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [OverviewDueAlertSnapshot]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mistiaLocalized(vi: "Sắp đến hạn", en: "Upcoming", ja: "間もなく期限"))
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(mistiaLocalized(vi: "Không có khoản nào sắp đến hạn", en: "No upcoming items", ja: "間もなく期限の項目はありません"))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack {
                                Text(row.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Spacer()
                                Text(MistiaDateFormatting.shortDateString(for: row.dueDate))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if index < rows.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }
}

private struct FamilyTransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack {
                Text(mistiaLocalized(vi: "Danh sách giao dịch đã lọc", en: "Filtered transactions", ja: "フィルター済み取引"))
                    .font(.headline)
                Spacer()
                Text(mistiaLocalized(vi: "Tính năng lọc giao dịch đang được hoàn thiện.", en: "Transaction filtering is coming soon.", ja: "取引フィルター機能は近日公開予定です。"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle(mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる")) { dismiss() }
                }
            }
        }
    }
}

private struct FamilyAIInsightsSection: View {
    let insights: [FamilyInsight]

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(mistiaLocalized(vi: "Insight gia đình", en: "Family insights", ja: "家族のインサイト"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)

                ForEach(insights, id: \.text) { insight in
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(MistiaAccent.purple.color)
                        Text(insight.text)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(MistiaAccent.purple.color.opacity(0.1))
                    }
                }
            }
        }
    }
}

private struct FamilyMiniTrendChart: View {
    let points: [FamilyTrendPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", Double(point.valueMinor))
            )
            .foregroundStyle(MistiaAccent.purple.color.gradient)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - Header components

private struct FamilyOverviewHeader: View {
    @Environment(FamilyContextStore.self) private var familyContextStore
    let walletRows: [FamilyAggregateWalletRow]
    let signedInUserID: UUID?
    let canInviteMembers: Bool
    let onInviteTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // "All family" button
                    Button {
                        withAnimation(.snappy) {
                            familyContextStore.activateFamilyHome()
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(familyContextStore.isViewingFamilyAggregate ? MistiaAccent.purple.color : Color(UIColor.secondarySystemGroupedBackground))
                                    .frame(width: 56, height: 56)
                                
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(familyContextStore.isViewingFamilyAggregate ? .white : MistiaAccent.purple.color)
                            }
                            
                            Text(mistiaLocalized(vi: "Cả nhà", en: "Family", ja: "家族"))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(familyContextStore.isViewingFamilyAggregate ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(familyContextStore.members) { member in
                        Button {
                            withAnimation(.snappy) {
                                if member.userID == signedInUserID {
                                    familyContextStore.activateSelfView()
                                } else {
                                    familyContextStore.activateMemberView(member)
                                }
                            }
                        } label: {
                            VStack(spacing: 8) {
                                MistiaAvatarBadge(
                                    initials: String(member.displayName.prefix(2)).uppercased(),
                                    avatarURL: member.avatarURL,
                                    size: 56,
                                    showsStatus: false
                                )
                                .overlay {
                                    if isSelected(member) {
                                        Circle()
                                            .stroke(MistiaAccent.purple.color, lineWidth: 3)
                                    }
                                }

                                Text(member.displayName)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(isSelected(member) ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Section(member.displayName) {
                                ForEach(walletRows.prefix(3)) { row in
                                    Button {} label: {
                                        HStack {
                                            Image(systemName: row.wallet.kind.defaultIconSymbolName)
                                            Text(row.wallet.name)
                                            Spacer()
                                            Text(row.currentBalanceMinor.formattedCurrency(code: row.wallet.currencyCode))
                                        }
                                    }
                                }

                                Divider()

                                Button {
                                    if member.userID == signedInUserID {
                                        familyContextStore.activateSelfView()
                                    } else {
                                        familyContextStore.activateMemberView(member)
                                    }
                                } label: {
                                    Label(mistiaLocalized(vi: "Xem chi tiết", en: "View details", ja: "詳細を見る"), systemImage: "eye.fill")
                                }
                            }
                        }
                    }

                    if canInviteMembers {
                        Button(action: onInviteTap) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                                        .frame(width: 56, height: 56)

                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }

                                Text(mistiaLocalized(vi: "Thêm", en: "Invite", ja: "招待"))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func isSelected(_ member: FamilyMember) -> Bool {
        if member.userID == signedInUserID {
            return familyContextStore.isViewingSelfContext
        }

        guard case .member(let userID) = familyContextStore.activeContext.scope else { return false }
        return userID == member.userID
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

private struct FamilyHubRouteSection: View {
    let rows: [FamilyHubRouteRowItem]
    let tint: Color
    let onTap: (FamilyHubRouteRowItem) -> Void

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    FamilyHubRouteRow(row: row) {
                        onTap(row)
                    }

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }
}

private struct FamilyHubRouteRow: View {
    let row: FamilyHubRouteRowItem
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(row.iconColor.opacity(0.15))

                    Image(systemName: row.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(row.iconColor)
                }
                .frame(width: 32, height: 32)

                Text(row.title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(titleColor)

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(valueColor.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18, tint: MistiaAccent.purple.color))
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.82)
    }

    private var valueColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : Color.black.opacity(0.48)
    }
}

// MARK: - Settings-style Row

private struct FamilySettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Apple-style icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 32, height: 32)

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
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
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

private struct FamilySyncOverlayIndicator: View {
    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .padding(10)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityLabel(
                Text(mistiaLocalized(
                    vi: "Đang đồng bộ gia đình",
                    en: "Syncing family",
                    ja: "家族データを同期中"
                ))
            )
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var storedTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgets: [BudgetPlan]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var storedBills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var storedInstallments: [InstallmentPlan]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query private var ownershipScopes: [OwnedRecordScope]

    private var overviewData: FamilyOverviewDerivedData {
        let now = Date.now
        let currentMonth = PlanningLogic.startOfMonth(for: now, calendar: calendar)
        let interval = selectedInterval(for: timeframe, now: now)
        let familyMemberUserIDs = familyMemberIDs
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
        let billOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let installmentOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)
        let visibleWallets = visibleForFamilyOverview(
            storedWallets,
            entity: .wallet,
            ownerMap: walletOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let visibleTransactions = visibleForFamilyOverview(
            storedTransactions,
            entity: .transaction,
            ownerMap: transactionOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let visibleBudgets = visibleForFamilyOverview(
            storedBudgets,
            entity: .budgetPlan,
            ownerMap: budgetOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let visibleBills = visibleForFamilyOverview(
            storedBills,
            entity: .recurringBillPlan,
            ownerMap: billOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let visibleInstallments = visibleForFamilyOverview(
            storedInstallments,
            entity: .installmentPlan,
            ownerMap: installmentOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let visibleOccurrences = visibleForFamilyOverview(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
            ownerMap: occurrenceOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let transactionRecords = visibleTransactions.map(\.planningRecordSnapshot)
        let occurrenceSnapshots = visibleOccurrences.map(\.planningSnapshot)
        let walletRows = visibleWallets
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
            .map { wallet in
                let debt = TransactionLogic.effectiveBalance(
                    for: TransactionWalletSnapshot(
                        id: wallet.id,
                        kind: wallet.kind,
                        openingBalanceMinor: wallet.openingBalanceMinor
                    ),
                    records: transactionRecords
                )

                let displayBalance: Int64
                if wallet.kind == .creditCard, let profile = wallet.creditCardProfile {
                    displayBalance = max(profile.creditLimitMinor - debt, 0)
                } else {
                    displayBalance = debt
                }

                return FamilyAggregateWalletRow(
                    wallet: wallet,
                    currentBalanceMinor: displayBalance
                )
            }
        let creditCardAccounts = visibleWallets.compactMap {
            $0.planningCreditCardSnapshot(records: transactionRecords)
        }
        let creditCardStatementDueItems = PlanningLogic.creditCardStatementsDue(
            in: currentMonth,
            accounts: creditCardAccounts,
            records: transactionRecords,
            occurrences: occurrenceSnapshots,
            referenceDate: now,
            calendar: calendar
        )
        let creditCardDueItems = PlanningLogic.creditCardDueItems(
            accounts: creditCardAccounts,
            records: transactionRecords,
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            referenceDate: now,
            calendar: calendar
        )
        let recurringBillDueItems = PlanningLogic.recurringBillDueItems(
            bills: visibleBills.filter { !$0.isArchived }.map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            calendar: calendar
        )
        let installmentDueItems = PlanningLogic.installmentDueItems(
            plans: visibleInstallments.filter { !$0.isArchived }.map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            calendar: calendar
        )
        let monthlyDueSummary = PlanningLogic.dueSummary(
            creditStatements: creditCardStatementDueItems,
            recurring: recurringBillDueItems + installmentDueItems,
            selectedMonth: currentMonth,
            referenceDate: now,
            calendar: calendar
        )
        let activeBudgetPlans = visibleBudgets
            .filter {
                !$0.isArchived
                    && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == currentMonth
            }
            .map { $0.planningSnapshot(calendar: calendar) }
        let budgetRows = OverviewLogic.budgetAlerts(
            budgets: activeBudgetPlans,
            transactionRecords: transactionRecords,
            referenceDate: now,
            calendar: calendar
        )
        let dueAlerts = OverviewLogic.dueAlerts(
            creditCardDues: creditCardDueItems,
            recurringDues: recurringBillDueItems + installmentDueItems,
            referenceDate: now,
            calendar: calendar
        )
        let memberNames = Dictionary(
            familyContextStore.members.map { ($0.userID, $0.displayName) },
            uniquingKeysWith: { _, latest in latest }
        )
        let summary = FamilyLogic.aggregateSummary(
            wallets: walletRows.map { row in
                let debt: Int64
                if row.wallet.kind == .creditCard, let profile = row.wallet.creditCardProfile {
                    debt = max(profile.creditLimitMinor - row.currentBalanceMinor, 0)
                } else {
                    debt = 0
                }

                return FamilyAggregateWalletSnapshot(
                    ownerUserID: walletOwnerMap[row.wallet.id] ?? sessionStore.signedInUserID ?? UUID(),
                    kind: row.wallet.kind.familyAggregateKind,
                    balanceMinor: row.wallet.kind == .creditCard ? 0 : row.currentBalanceMinor,
                    debtMinor: debt
                )
            },
            transactions: visibleTransactions.map { transaction in
                FamilyAggregateTransactionSnapshot(
                    ownerUserID: transactionOwnerMap[transaction.id] ?? sessionStore.signedInUserID ?? UUID(),
                    categoryName: transaction.category?.localizedDisplayName,
                    occurredAt: transaction.occurredAt,
                    kind: transaction.primaryKind.familyAggregateKind,
                    amountMinor: abs(transaction.amountMinor),
                    isCreditCardPayment: TransactionLogic.isCreditCardPayment(transaction.snapshot)
                )
            },
            selectedInterval: interval,
            visibleMemberIDs: familyMemberUserIDs,
            memberNames: memberNames,
            calendar: calendar
        )
        let categorySpendingSnapshot = OverviewLogic.categorySpendingInterval(
            from: visibleTransactions.map(\.overviewSnapshot),
            interval: interval,
            title: timeframe.title,
            currencyCode: currencyCode,
            calendar: calendar
        )
        let monthlySpendable = FamilyLogic.monthlySpendable(
            totalAssetsMinor: summary.totalAssetsMinor,
            monthlyDueMinor: monthlyDueSummary.totalDueMinor
        )

        return FamilyOverviewDerivedData(
            walletRows: walletRows,
            summary: summary,
            monthlySpendable: monthlySpendable,
            categorySpendingSnapshot: categorySpendingSnapshot,
            budgetRows: budgetRows,
            dueAlerts: dueAlerts
        )
    }

    private var familyMemberIDs: Set<UUID> {
        var ids = Set(familyContextStore.members.map(\.userID))
        if let currentUserID = familyContextStore.currentUserID {
            ids.insert(currentUserID)
        }
        return ids
    }

    private func visibleForFamilyOverview<Record: MistiaOwnedRecord>(
        _ records: [Record],
        entity: MistiaSyncEntity,
        ownerMap: [UUID: UUID],
        familyMemberUserIDs: Set<UUID>
    ) -> [Record] {
        switch familyContextStore.activeContext.scope {
        case .familyHome:
            return records.filter { record in
                let ownerUserID = ownerMap[record.id] ?? sessionStore.activeLocalProfileUserID
                guard let ownerUserID else { return false }
                return familyMemberUserIDs.contains(ownerUserID)
            }
        case .personalSelf, .member:
            return MistiaRecordOwnershipStore.visibleRecords(
                records,
                entity: entity,
                ownerMap: ownerMap,
                subjectUserID: familyContextStore.selectedSubjectUserID ?? sessionStore.activeLocalProfileUserID,
                signedInUserID: sessionStore.activeLocalProfileUserID
            )
        }
    }

    private func selectedInterval(for timeframe: FamilyTimeframe, now: Date) -> DateInterval {
        switch timeframe {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 3600*24*7)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 3600*24*30)
        case .year:
            return calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 3600*24*365)
        }
    }

    @State private var timeframe: FamilyTimeframe = .month
    @State private var distributionMode: FamilyDistributionMode = .spending
    @State private var comparisonMode: FamilyComparisonMode = .spending
    @State private var activeSheet: FamilyOverviewSheet?

    var body: some View {
        let data = overviewData

        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: familyContextStore.family?.name ?? mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            onRefresh: {
                await familyContextStore.refreshLatest(
                    sessionStore: sessionStore,
                    source: .userInitiated
                )
            },
            contentSpacing: 18,
            titleDisplayMode: .large
        ) {
            FamilyContextChipBar()

            FamilyOverviewHeader(
                walletRows: data.walletRows,
                signedInUserID: sessionStore.signedInUserID,
                canInviteMembers: familyContextStore.canInviteMembers,
                onInviteTap: { activeSheet = .invite }
            )
            .padding(.top, 8)

            FamilyHeroCard(
                summary: data.summary,
                monthlySpendable: data.monthlySpendable,
                currencyCode: currencyCode
            )

            FamilyDistributionSection(
                summary: data.summary,
                categorySpendingSnapshot: data.categorySpendingSnapshot,
                timeframe: $timeframe,
                mode: $distributionMode,
                currencyCode: currencyCode,
                onSegmentTap: { segment in
                    activeSheet = .filterTransactions
                }
            )

            FamilyMemberComparisonSection(
                summary: data.summary,
                mode: $comparisonMode,
                currencyCode: currencyCode
            )

            if !data.walletRows.isEmpty {
                FamilyAggregateAccountList(
                    rows: data.walletRows
                )
            }

            if !data.budgetRows.isEmpty {
                FamilyBudgetStatusSection(
                    rows: data.budgetRows,
                    currencyCode: currencyCode
                )
            }

            if !data.dueAlerts.isEmpty {
                FamilyUpcomingSection(
                    rows: data.dueAlerts,
                    currencyCode: currencyCode
                )
            }

            FamilyAIInsightsSection(insights: data.summary.insights)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .invite:
                FamilyInviteSheet()
            case .filterTransactions:
                FamilyTransactionFilterSheet()
            }
        }
        .task(id: familyContextStore.family?.id) {
            if !familyContextStore.isViewingOtherMemberContext {
                familyContextStore.activateFamilyHome()
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

    @State private var showsSharingSheet = false
    @State private var showsPermissionsSheet = false
    @State private var destructiveAction: FamilyMemberDestructiveAction?
    @State private var confirmsTransferOwner = false

    private var isMe: Bool {
        member.userID == sessionStore.signedInUserID
    }

    private var isOwner: Bool {
        familyContextStore.currentRole == .owner
    }

    private var remoteActionsDisabled: Bool {
        !sessionStore.canPerformRemoteActions
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: "",
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
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

            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                FamilyAlertBanner(message: remoteUnavailableReason)
            }

            memberActionBlock
            memberDestructiveActionBlock
        }
        .sheet(isPresented: $showsSharingSheet) {
            FamilySharingSheet(member: member)
        }
        .sheet(isPresented: $showsPermissionsSheet) {
            FamilyPermissionsSheet(member: member)
        }
    }

    private var memberActions: [FamilyMemberProfileAction] {
        var actions: [FamilyMemberProfileAction] = []

        if !isMe {
            actions.append(.sharing)
        }

        if !isMe && isOwner && member.role != .owner {
            actions.append(.permissions)
        }

        if !isMe && isOwner && member.role == .member {
            actions.append(.transferOwner)
        }

        if !isMe && familyContextStore.capabilities(for: member).canViewTarget {
            actions.append(.viewData)
        }

        return actions
    }

    @ViewBuilder
    private var memberActionBlock: some View {
        let actions = memberActions

        if !actions.isEmpty {
            MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        memberActionButton(action)

                        if index < actions.count - 1 {
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var memberDestructiveActionBlock: some View {
        if isMe || isOwner {
            MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
                memberActionButton(.destructive)
            }
        }
    }

    @ViewBuilder
    private func memberActionButton(_ action: FamilyMemberProfileAction) -> some View {
        switch action {
        case .sharing:
            Button {
                showsSharingSheet = true
            } label: {
                memberActionRowContent(action)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 0))
            .disabled(remoteActionsDisabled)
            .opacity(remoteActionsDisabled ? 0.55 : 1)

        case .permissions:
            Button {
                showsPermissionsSheet = true
            } label: {
                memberActionRowContent(action)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 0))
            .disabled(remoteActionsDisabled)
            .opacity(remoteActionsDisabled ? 0.55 : 1)

        case .transferOwner:
            Button {
                confirmsTransferOwner = true
            } label: {
                memberActionRowContent(action)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 0))
            .disabled(remoteActionsDisabled)
            .opacity(remoteActionsDisabled ? 0.55 : 1)
            .confirmationDialog(
                mistiaLocalized(vi: "Nhượng quyền owner?", en: "Transfer owner?", ja: "owner を譲渡しますか？"),
                isPresented: $confirmsTransferOwner,
                titleVisibility: .visible
            ) {
                Button(mistiaLocalized(vi: "Nhượng quyền owner", en: "Transfer owner", ja: "owner を譲渡"), role: .destructive) {
                    Task {
                        await familyContextStore.transferOwner(to: member, sessionStore: sessionStore)
                        dismiss()
                    }
                }

                Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) {}
            } message: {
                Text(mistiaLocalized(
                    vi: "\(member.displayName) sẽ là owner duy nhất của gia đình này. Bạn sẽ không còn quyền quản lý thành viên sau khi chuyển.",
                    en: "\(member.displayName) will be the only owner of this family. You will no longer manage members after transfer.",
                    ja: "\(member.displayName) がこの家族の唯一の owner になります。譲渡後、あなたはメンバー管理ができません。"
                ))
            }

        case .viewData:
            Button {
                familyContextStore.activateMemberView(member)
                dismiss()
            } label: {
                memberActionRowContent(action)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 0))
            .disabled(familyContextStore.isSwitchingContext)

        case .destructive:
            Button(role: .destructive) {
                destructiveAction = isMe ? (isOwner ? .deleteFamily : .leaveFamily) : .removeMember
            } label: {
                memberActionRowContent(action)
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 0))
            .disabled(remoteActionsDisabled)
            .opacity(remoteActionsDisabled ? 0.55 : 1)
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
    }

    private func memberActionRowContent(_ action: FamilyMemberProfileAction) -> some View {
        HStack(spacing: 14) {
            if action == .viewData && familyContextStore.isSwitchingContext {
                ProgressView()
                    .frame(width: 32)
            } else {
                Image(systemName: memberActionIcon(action))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(memberActionTint(action))
                    .frame(width: 32)
            }

            Text(memberActionTitle(action))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(action == .destructive ? .red : .primary)

            Spacer()

            if action != .destructive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func memberActionTitle(_ action: FamilyMemberProfileAction) -> String {
        switch action {
        case .sharing:
            return mistiaLocalized(vi: "Đang chia sẻ", en: "Sharing", ja: "共有中")
        case .permissions:
            return mistiaLocalized(vi: "Quyền hạn", en: "Permissions", ja: "権限")
        case .transferOwner:
            return mistiaLocalized(vi: "Nhượng quyền owner", en: "Transfer owner", ja: "owner を譲渡")
        case .viewData:
            return mistiaLocalized(
                vi: "Xem dữ liệu của \(member.displayName)",
                en: "View \(member.displayName)'s data",
                ja: "\(member.displayName)のデータを見る"
            )
        case .destructive:
            if isMe {
                return isOwner
                    ? mistiaLocalized(vi: "Xóa gia đình", en: "Delete family", ja: "家族を削除")
                    : mistiaLocalized(vi: "Rời khỏi gia đình", en: "Leave family", ja: "家族を退会")
            }

            return mistiaLocalized(
                vi: "Xóa \(member.displayName) khỏi gia đình",
                en: "Remove \(member.displayName)",
                ja: "\(member.displayName)を削除"
            )
        }
    }

    private func memberActionIcon(_ action: FamilyMemberProfileAction) -> String {
        switch action {
        case .sharing:
            return "square.and.arrow.up.fill"
        case .permissions:
            return "person.badge.key.fill"
        case .transferOwner:
            return "crown.fill"
        case .viewData:
            return "eye.fill"
        case .destructive:
            return isMe && isOwner ? "trash.fill" : "person.badge.minus.fill"
        }
    }

    private func memberActionTint(_ action: FamilyMemberProfileAction) -> Color {
        switch action {
        case .sharing, .viewData:
            return action == .sharing ? .blue : MistiaAccent.purple.color
        case .permissions, .transferOwner:
            return .orange
        case .destructive:
            return .red
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

private enum FamilySheetFocusedField: Hashable {
    case familyName
    case inviteCode
}

private struct FamilyCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var familyName = ""
    @FocusState private var focusedField: FamilySheetFocusedField?

    var body: some View {
        NavigationStack {
            Form {
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    Section {
                        Text(remoteUnavailableReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(mistiaLocalized(vi: "Gia đình mới", en: "New family", ja: "新しい家族")) {
                    TextField(mistiaLocalized(vi: "Tên gia đình", en: "Family name", ja: "家族名"), text: $familyName)
                        .focused($focusedField, equals: .familyName)
                }
            }
            .disabled(!sessionStore.canPerformRemoteActions)
            .dismissKeyboardOnTap()
            .navigationTitle(mistiaLocalized(vi: "Tạo gia đình", en: "Create family", ja: "家族を作成"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await familyContextStore.createFamily(name: familyName, sessionStore: sessionStore)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MistiaAccent.lightPurple.color)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(MistiaAccent.purple.color)
                    .disabled(
                        familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !sessionStore.canPerformRemoteActions
                    )
                }
            }
        }
        .task {
            guard focusedField == nil else { return }
            try? await Task.sleep(for: .milliseconds(150))
            focusedField = .familyName
        }
    }
}

// MARK: - Join Sheet

private struct FamilyJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var inviteLink = ""
    @State private var validationMessage: String?
    @FocusState private var focusedField: FamilySheetFocusedField?

    var body: some View {
        NavigationStack {
            Form {
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    Section {
                        Text(remoteUnavailableReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(mistiaLocalized(
                        vi: "Nếu bạn đã copy link mời, hãy dán link ở đây. Mistia sẽ mở màn hình chào mừng và không tự tham gia cho đến khi bạn xác nhận.",
                        en: "If you've copied an invite link, paste it here. Mistia will open the welcome screen and won't join until you confirm.",
                        ja: "招待リンクをコピー済みの場合はここに貼り付けてください。確認するまで自動参加はしません。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section(mistiaLocalized(vi: "Link mời", en: "Invite link", ja: "招待リンク")) {
                    TextField("mistia://family-invite/...", text: $inviteLink)
                        .focused($focusedField, equals: .inviteCode)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(!sessionStore.canPerformRemoteActions)
            .dismissKeyboardOnTap()
            .navigationTitle(mistiaLocalized(vi: "Dùng link mời", en: "Use invite link", ja: "招待リンクを使う"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let token = inviteToken else {
                            validationMessage = mistiaLocalized(
                                vi: "Link mời không hợp lệ.",
                                en: "This invite link isn't valid.",
                                ja: "招待リンクが無効です。"
                            )
                            return
                        }

                        familyContextStore.presentInvite(token: token)
                            dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MistiaAccent.lightPurple.color)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(MistiaAccent.purple.color)
                    .disabled(
                        inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !sessionStore.canPerformRemoteActions
                    )
                }
            }
        }
        .task {
            guard focusedField == nil else { return }
            try? await Task.sleep(for: .milliseconds(150))
            focusedField = .inviteCode
        }
    }

    private var inviteToken: String? {
        let trimmed = inviteLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let token = FamilyInviteLinking.token(from: url) {
            return token
        }
        return FamilyInviteLinking.normalizedToken(trimmed)
    }
}

// MARK: - Invite Management Screen

private struct FamilyInviteManagementScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var copiedInviteID: UUID?
    @State private var activeShareItem: FamilyInviteShareItem?

    private var sortedInvites: [FamilyInviteRecord] {
        familyContextStore.invites.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var pendingCount: Int {
        familyContextStore.invites.filter { $0.status == .pending }.count
    }

    private var acceptedCount: Int {
        familyContextStore.invites.filter { $0.status == .accepted }.count
    }

    private var declinedCount: Int {
        familyContextStore.invites.filter { $0.status == .declined }.count
    }

    private var expiredCount: Int {
        familyContextStore.invites.filter { $0.status == .expired }.count
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Quản lý lời mời", en: "Manage invites", ja: "招待を管理"),
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18
        ) {
            if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                FamilyAlertBanner(message: remoteUnavailableReason)
            }

            if sortedInvites.isEmpty {
                emptyInviteTimeline
            } else {
                inviteSummarySection
                inviteTimelineSection
            }
        }
        .sheet(item: $activeShareItem) { item in
            FamilyInviteActivitySheet(message: item.message) {
                activeShareItem = nil
            }
        }
    }

    private var emptyInviteTimeline: some View {
        MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    mistiaLocalized(vi: "Chưa có lời mời nào", en: "No invites yet", ja: "招待はまだありません"),
                    systemImage: "link.badge.plus"
                )
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

                Text(mistiaLocalized(
                    vi: "Các link đã tạo sẽ xuất hiện ở đây cùng trạng thái chờ, đã dùng, đã từ chối, hết hạn hoặc đã thu hồi.",
                    en: "Created links will appear here with pending, used, declined, expired, or revoked states.",
                    ja: "作成済みリンクは、待機中・使用済み・辞退済み・期限切れ・取り消し済みの状態でここに表示されます。"
                ))
                .descriptionTextStyle()
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inviteSummarySection: some View {
        MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 14) {
                inviteSummaryMetric(
                    title: mistiaLocalized(vi: "Đang chờ", en: "Pending", ja: "待機中"),
                    count: pendingCount,
                    tint: .orange
                )
                inviteSummaryMetric(
                    title: mistiaLocalized(vi: "Đã dùng", en: "Used", ja: "使用済み"),
                    count: acceptedCount,
                    tint: .mint
                )
                inviteSummaryMetric(
                    title: mistiaLocalized(vi: "Đã từ chối", en: "Declined", ja: "辞退済み"),
                    count: declinedCount,
                    tint: .red
                )
                inviteSummaryMetric(
                    title: mistiaLocalized(vi: "Hết hạn", en: "Expired", ja: "期限切れ"),
                    count: expiredCount,
                    tint: .secondary
                )
            }
        }
    }

    private var inviteTimelineSection: some View {
        MistiaGlassCard(cornerRadius: 18, tint: Color(UIColor.secondarySystemGroupedBackground), padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(sortedInvites.enumerated()), id: \.element.id) { index, invite in
                    FamilyInviteTimelineRow(
                        invite: invite,
                        acceptedDisplayName: acceptedDisplayName(for: invite),
                        linkText: familyContextStore.inviteLink(for: invite).absoluteString,
                        copiedInviteID: copiedInviteID,
                        isLast: index == sortedInvites.count - 1,
                        canRevoke: sessionStore.canPerformRemoteActions,
                        onShare: { shareInvite(invite) },
                        onCopy: { copyInviteLink(invite) },
                        onRevoke: {
                            Task {
                                await familyContextStore.revokeInvite(invite, sessionStore: sessionStore)
                            }
                        }
                    )

                    if index < sortedInvites.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
        }
    }

    private func inviteSummaryMetric(title: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func acceptedDisplayName(for invite: FamilyInviteRecord) -> String? {
        guard invite.status == .accepted,
              let acceptedByUserID = invite.acceptedByUserID else {
            return nil
        }

        return familyContextStore.displayName(for: acceptedByUserID)
            ?? mistiaLocalized(vi: "Thành viên đã chấp nhận", en: "Accepted member", ja: "承認済みメンバー")
    }

    private func shareInvite(_ invite: FamilyInviteRecord) {
        activeShareItem = FamilyInviteShareItem(
            message: familyContextStore.shareMessage(for: invite)
        )
    }

    private func copyInviteLink(_ invite: FamilyInviteRecord) {
        UIPasteboard.general.string = familyContextStore.inviteLink(for: invite).absoluteString
        copiedInviteID = invite.id
    }
}

private struct FamilyInviteTimelineRow: View {
    let invite: FamilyInviteRecord
    let acceptedDisplayName: String?
    let linkText: String
    let copiedInviteID: UUID?
    let isLast: Bool
    let canRevoke: Bool
    let onShare: () -> Void
    let onCopy: () -> Void
    let onRevoke: () -> Void

    private var statusTint: Color {
        familyInviteStatusTint(invite.status)
    }

    private var title: String {
        acceptedDisplayName ?? invite.defaultRole.title
    }

    private var roleDetail: String {
        if acceptedDisplayName != nil {
            return mistiaLocalized(
                vi: "Vai trò: \(invite.defaultRole.title)",
                en: "Role: \(invite.defaultRole.title)",
                ja: "役割: \(invite.defaultRole.title)"
            )
        }

        return mistiaLocalized(
            vi: "Vai trò được mời: \(invite.defaultRole.title)",
            en: "Invite role: \(invite.defaultRole.title)",
            ja: "招待する役割: \(invite.defaultRole.title)"
        )
    }

    private var copyTitle: String {
        if copiedInviteID == invite.id {
            return mistiaLocalized(vi: "Đã copy", en: "Copied", ja: "コピー済み")
        }
        return mistiaLocalized(vi: "Sao chép", en: "Copy", ja: "コピー")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timelineMarker

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(roleDetail)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text(familyInviteStatusTitle(invite.status))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(familyInviteCreatedText(invite))
                    Text(familyInviteLifecycleText(invite))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(linkText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    if invite.status == .pending {
                        Button(action: onShare) {
                            Label(mistiaLocalized(vi: "Chia sẻ", en: "Share", ja: "共有"), systemImage: "square.and.arrow.up")
                        }
                    }

                    Button(action: onCopy) {
                        Label(copyTitle, systemImage: copiedInviteID == invite.id ? "checkmark" : "doc.on.doc")
                    }

                    if invite.status == .pending {
                        Spacer(minLength: 0)

                        Button(role: .destructive, action: onRevoke) {
                            Label(mistiaLocalized(vi: "Thu hồi", en: "Revoke", ja: "取り消す"), systemImage: "xmark.circle")
                        }
                        .disabled(!canRevoke)
                        .opacity(canRevoke ? 1 : 0.45)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.vertical, 14)
            .padding(.trailing, 14)
        }
        .padding(.leading, 14)
    }

    private var timelineMarker: some View {
        ZStack(alignment: .top) {
            if !isLast {
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 2)
                    .padding(.top, 24)
            }

            Circle()
                .fill(statusTint)
                .frame(width: 10, height: 10)
                .padding(.top, 19)
        }
        .frame(width: 20)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Invite Sheet

private struct FamilyInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @State private var selectedRole: FamilyRole = .member
    @State private var isCreatingInvite = false
    @State private var activeShareItem: FamilyInviteShareItem?

    private var isCreateDisabled: Bool {
        !sessionStore.canPerformRemoteActions
            || isCreatingInvite
            || !familyContextStore.canCreatePendingInvite
    }

    private var inviteLimitMessage: String? {
        guard !familyContextStore.canCreatePendingInvite else { return nil }
        return mistiaLocalized(
            vi: "Bạn đang có 2 lời mời chờ phản hồi. Khi một lời mời hết hạn, bị từ chối, được chấp nhận hoặc thu hồi, bạn có thể tạo link mới.",
            en: "You already have 2 pending invites. You can create another link after one expires, is declined, accepted, or revoked.",
            ja: "待機中の招待が2件あります。いずれかが期限切れ、辞退、承認、取り消しになると新しいリンクを作成できます。"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    Section {
                        Text(remoteUnavailableReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(mistiaLocalized(vi: "Vai trò được mời", en: "Invite role", ja: "招待する役割")) {
                    ForEach([FamilyRole.member, .kid], id: \.self) { role in
                        Button {
                            selectedRole = role
                        } label: {
                            FamilyInviteRoleOptionRow(
                                role: role,
                                isSelected: selectedRole == role
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(roleDescription(selectedRole))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let inviteLimitMessage {
                        Text(inviteLimitMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(!sessionStore.canPerformRemoteActions || isCreatingInvite)
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
                    Button {
                        Task {
                            await createInviteAndPresentShareSheet()
                        }
                    } label: {
                        if isCreatingInvite {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(mistiaLocalized(vi: "Tạo link", en: "Create link", ja: "リンク作成"))
                        }
                    }
                    .disabled(isCreateDisabled)
                }
            }
        }
        .sheet(item: $activeShareItem) { item in
            FamilyInviteActivitySheet(message: item.message) {
                activeShareItem = nil
                dismiss()
            }
        }
    }

    private func createInviteAndPresentShareSheet() async {
        guard !isCreatingInvite else { return }
        guard familyContextStore.canCreatePendingInvite else { return }

        isCreatingInvite = true
        defer { isCreatingInvite = false }

        guard let invite = await familyContextStore.createInvite(
            defaultRole: selectedRole,
            sessionStore: sessionStore
        ) else {
            return
        }

        activeShareItem = FamilyInviteShareItem(
            message: familyContextStore.shareMessage(for: invite)
        )
    }

    private func roleDescription(_ role: FamilyRole) -> String {
        switch role {
        case .owner:
            return mistiaLocalized(
                vi: "Gia đình chỉ có một owner. Hãy mời thành viên rồi nhượng quyền owner từ màn hình thông tin thành viên.",
                en: "A family has one owner. Invite a member, then transfer ownership from that member's info screen.",
                ja: "家族の owner は1人です。メンバーとして招待してから、メンバー情報画面で owner を譲渡します。"
            )
        case .member:
            return mistiaLocalized(
                vi: "Thành viên có thể xem dữ liệu gia đình theo quyền xem mặc định, nhưng muốn sửa hoặc dùng ví thì cần được cấp quyền.",
                en: "Members can view family data by default, but editing or using wallets requires an explicit grant.",
                ja: "メンバーは既定で家族データを表示できますが、編集やウォレット利用には明示的な許可が必要です。"
            )
        case .kid:
            return mistiaLocalized(
                vi: "Trẻ em mặc định bị giới hạn và có thể chịu sự quản lý của phụ huynh hoặc chủ gia đình.",
                en: "Kids are limited by default and can be managed by a parent or family owner.",
                ja: "子どもは初期状態で制限され、保護者または所有者が管理できます。"
            )
        }
    }
}

private struct FamilyInviteRoleOptionRow: View {
    let role: FamilyRole
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(role.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MistiaAccent.lightPurple.color)
            }
        }
    }
}

private struct FamilyInviteShareItem: Identifiable {
    let id = UUID()
    let message: String
}

private struct FamilyInviteActivitySheet: UIViewControllerRepresentable {
    let message: String
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.complete()
        }
        controller.presentationController?.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        private let onComplete: () -> Void
        private var didComplete = false

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            complete()
        }

        func complete() {
            guard !didComplete else { return }
            didComplete = true
            Task { @MainActor in
                onComplete()
            }
        }
    }
}

private func familyInviteCreatedText(_ invite: FamilyInviteRecord) -> String {
    mistiaLocalized(
        vi: "Đã gửi: \(invite.createdAt.formatted(date: .abbreviated, time: .shortened))",
        en: "Sent: \(invite.createdAt.formatted(date: .abbreviated, time: .shortened))",
        ja: "送信: \(invite.createdAt.formatted(date: .abbreviated, time: .shortened))"
    )
}

private func familyInviteLifecycleText(_ invite: FamilyInviteRecord) -> String {
    if invite.status == .accepted, let acceptedAt = invite.acceptedAt {
        return mistiaLocalized(
            vi: "Đã chấp nhận: \(acceptedAt.formatted(date: .abbreviated, time: .shortened))",
            en: "Accepted: \(acceptedAt.formatted(date: .abbreviated, time: .shortened))",
            ja: "承認: \(acceptedAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    if invite.status == .revoked, let revokedAt = invite.revokedAt {
        return mistiaLocalized(
            vi: "Đã thu hồi: \(revokedAt.formatted(date: .abbreviated, time: .shortened))",
            en: "Revoked: \(revokedAt.formatted(date: .abbreviated, time: .shortened))",
            ja: "取り消し: \(revokedAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    if invite.status == .declined, let declinedAt = invite.declinedAt {
        return mistiaLocalized(
            vi: "Đã từ chối: \(declinedAt.formatted(date: .abbreviated, time: .shortened))",
            en: "Declined: \(declinedAt.formatted(date: .abbreviated, time: .shortened))",
            ja: "辞退: \(declinedAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    return mistiaLocalized(
        vi: "Hết hạn: \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))",
        en: "Expires: \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))",
        ja: "期限: \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))"
    )
}

private func familyInviteStatusTitle(_ status: FamilyInviteStatus) -> String {
    switch status {
    case .pending:
        return mistiaLocalized(vi: "Đang chờ", en: "Pending", ja: "待機中")
    case .accepted:
        return mistiaLocalized(vi: "Đã dùng", en: "Used", ja: "使用済み")
    case .declined:
        return mistiaLocalized(vi: "Đã từ chối", en: "Declined", ja: "辞退済み")
    case .expired:
        return mistiaLocalized(vi: "Hết hạn", en: "Expired", ja: "期限切れ")
    case .revoked:
        return mistiaLocalized(vi: "Đã thu hồi", en: "Revoked", ja: "取り消し済み")
    case .invalid:
        return mistiaLocalized(vi: "Không hợp lệ", en: "Invalid", ja: "無効")
    }
}

private func familyInviteStatusTint(_ status: FamilyInviteStatus) -> Color {
    switch status {
    case .pending:
        return .orange
    case .accepted:
        return .mint
    case .declined:
        return .red
    case .expired:
        return .secondary
    case .revoked, .invalid:
        return .red
    }
}

// MARK: - Sharing Sheet

private struct FamilySharingChange: Identifiable {
    let id = UUID()
    let granteeUserID: UUID
    let ownerUserID: UUID
    let resourceType: MistiaFamilyNotificationResourceType
    let resourceID: UUID?
    let scope: MistiaFamilyPermissionScope
    let isGranted: Bool
    let title: String
}

private struct FamilySharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let member: FamilyMember

    @State private var pendingChange: FamilySharingChange?

    private var ownerUserID: UUID? {
        sessionStore.activeLocalProfileUserID ?? sessionStore.signedInUserID
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var ownWallets: [LedgerWallet] {
        guard let ownerUserID else { return [] }
        return storedWallets
            .filter { !$0.isArchived && (walletOwnerMap[$0.id] ?? ownerUserID) == ownerUserID }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    Section {
                        Text(remoteUnavailableReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(mistiaLocalized(vi: "Quyền chỉnh sửa", en: "Edit access", ja: "編集権限")) {
                    sharingToggle(
                        title: mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引"),
                        resourceType: .transaction,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Danh mục", en: "Categories", ja: "カテゴリ"),
                        resourceType: .category,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Ngân sách", en: "Budgets", ja: "予算"),
                        resourceType: .budget,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Hóa đơn", en: "Bills", ja: "請求書"),
                        resourceType: .bill,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入"),
                        resourceType: .installment,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Mục tiêu", en: "Goals", ja: "目標"),
                        resourceType: .goal,
                        resourceID: nil,
                        scope: .edit
                    )
                }

                Section(mistiaLocalized(vi: "Quyền thêm mới", en: "Create access", ja: "作成権限")) {
                    sharingToggle(
                        title: mistiaLocalized(vi: "Ví / thẻ", en: "Wallets / cards", ja: "ウォレット・カード"),
                        resourceType: .wallet,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引"),
                        resourceType: .transaction,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Danh mục", en: "Categories", ja: "カテゴリ"),
                        resourceType: .category,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Ngân sách", en: "Budgets", ja: "予算"),
                        resourceType: .budget,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Hóa đơn", en: "Bills", ja: "請求書"),
                        resourceType: .bill,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入"),
                        resourceType: .installment,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: mistiaLocalized(vi: "Mục tiêu", en: "Goals", ja: "目標"),
                        resourceType: .goal,
                        resourceID: nil,
                        scope: .create
                    )
                }

                Section(mistiaLocalized(vi: "Quyền sử dụng ví", en: "Wallet use access", ja: "ウォレット使用権限")) {
                    if ownWallets.isEmpty {
                        Text(mistiaLocalized(vi: "Bạn chưa có ví nào để chia sẻ quyền sử dụng.", en: "You do not have wallets to share use access for yet.", ja: "使用権限を共有できるウォレットはまだありません。"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ownWallets, id: \.id) { wallet in
                            sharingToggle(
                                title: wallet.name,
                                resourceType: .wallet,
                                resourceID: wallet.id,
                                scope: .use
                            )
                        }
                    }
                }

                Section(mistiaLocalized(vi: "Quyền chỉnh sửa ví", en: "Wallet edit access", ja: "ウォレット編集権限")) {
                    if ownWallets.isEmpty {
                        Text(mistiaLocalized(vi: "Bạn chưa có ví nào để chia sẻ quyền chỉnh sửa.", en: "You do not have wallets to share edit access for yet.", ja: "編集権限を共有できるウォレットはまだありません。"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ownWallets, id: \.id) { wallet in
                            sharingToggle(
                                title: wallet.name,
                                resourceType: .wallet,
                                resourceID: wallet.id,
                                scope: .edit
                            )
                        }
                    }
                }
            }
            .disabled(!sessionStore.canPerformRemoteActions || ownerUserID == nil)
            .navigationTitle(mistiaLocalized(vi: "Đang chia sẻ", en: "Sharing", ja: "共有中"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(mistiaLocalized(vi: "Xong", en: "Done", ja: "完了"))
                }
            }
        }
        .alert(item: $pendingChange) { change in
            let title = change.isGranted
                ? mistiaLocalized(vi: "Chia sẻ quyền?", en: "Share access?", ja: "権限を共有しますか？")
                : mistiaLocalized(vi: "Thu hồi quyền?", en: "Revoke access?", ja: "権限を取り消しますか？")
            let message = change.isGranted
                ? mistiaLocalized(
                    vi: "Bạn sẽ chia sẻ quyền \(change.title) với \(member.displayName).",
                    en: "You will share \(change.title) access with \(member.displayName).",
                    ja: "\(member.displayName)に\(change.title)の権限を共有します。"
                )
                : mistiaLocalized(
                    vi: "Bạn sẽ thu hồi quyền \(change.title) với \(member.displayName).",
                    en: "You will revoke \(change.title) access from \(member.displayName).",
                    ja: "\(member.displayName)から\(change.title)の権限を取り消します。"
                )

            if change.isGranted {
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    primaryButton: .default(Text(mistiaLocalized(vi: "Đồng ý", en: "Confirm", ja: "確認"))) {
                        applySharingChange(change)
                    },
                    secondaryButton: .cancel(Text(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")))
                )
            }

            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .destructive(Text(mistiaLocalized(vi: "Đồng ý", en: "Confirm", ja: "確認"))) {
                        applySharingChange(change)
                },
                secondaryButton: .cancel(Text(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")))
            )
        }
    }

    @ViewBuilder
    private func sharingToggle(
        title: String,
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        scope: MistiaFamilyPermissionScope
    ) -> some View {
        if let ownerUserID {
            Toggle(
                title,
                isOn: Binding(
                    get: {
                        familyContextStore.hasPermission(
                            granteeUserID: member.userID,
                            ownerUserID: ownerUserID,
                            resourceType: resourceType,
                            resourceID: resourceID,
                            scope: scope
                        )
                    },
                    set: { isGranted in
                        pendingChange = FamilySharingChange(
                            granteeUserID: member.userID,
                            ownerUserID: ownerUserID,
                            resourceType: resourceType,
                            resourceID: resourceID,
                            scope: scope,
                            isGranted: isGranted,
                            title: title
                        )
                    }
                )
            )
            .tint(MistiaAccent.purple.color)
            .toggleStyle(.switch)
        }
    }

    private func applySharingChange(_ change: FamilySharingChange) {
        Task { @MainActor in
            await familyContextStore.setPermissionGrant(
                granteeUserID: change.granteeUserID,
                ownerUserID: change.ownerUserID,
                resourceType: change.resourceType,
                resourceID: change.resourceID,
                scope: change.scope,
                isGranted: change.isGranted,
                sessionStore: sessionStore
            )
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
                if let remoteUnavailableReason = sessionStore.remoteUnavailableReason {
                    Section {
                        Text(remoteUnavailableReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(mistiaLocalized(vi: "Role", en: "Role", ja: "役割")) {
                    Picker(mistiaLocalized(vi: "Role", en: "Role", ja: "役割"), selection: $role) {
                        ForEach([FamilyRole.member, .kid], id: \.self) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(mistiaLocalized(vi: "Quyền", en: "Permissions", ja: "権限")) {
                    Toggle(mistiaLocalized(vi: "Xem dashboard gia đình", en: "View family dashboard", ja: "家族ダッシュボードを見る"), isOn: $policy.canViewFamilyDashboard)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(mistiaLocalized(vi: "Xem dữ liệu người khác", en: "View others", ja: "他メンバーを表示"), isOn: $policy.canViewOthers)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(mistiaLocalized(vi: "Sửa dữ liệu người khác", en: "Edit others", ja: "他メンバーを編集"), isOn: $policy.canEditOthers)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(mistiaLocalized(vi: "Xem ví / tài khoản", en: "View wallets", ja: "ウォレットを見る"), isOn: $policy.canViewWallets)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(mistiaLocalized(vi: "Xem công nợ", en: "View debts", ja: "負債を見る"), isOn: $policy.canViewDebts)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(mistiaLocalized(vi: "Xem kid", en: "View kids", ja: "kid を表示"), isOn: $policy.canViewKids)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(mistiaLocalized(vi: "Sửa kid", en: "Edit kids", ja: "kid を編集"), isOn: $policy.canEditKids)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                }

            }
            .disabled(!sessionStore.canPerformRemoteActions)
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
                    .disabled(!sessionStore.canPerformRemoteActions)
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
        case .member:
            mistiaLocalized(vi: "Thành viên", en: "Member", ja: "Member")
        case .kid:
            mistiaLocalized(vi: "Trẻ con", en: "Kid", ja: "Kid")
        }
    }

    var tint: Color {
        switch self {
        case .owner:
            .orange
        case .member:
            .cyan
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
