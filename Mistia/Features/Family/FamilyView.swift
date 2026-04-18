import Charts
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

    private var visibleErrorMessage: String? {
        guard let lastErrorMessage = familyContextStore.lastErrorMessage else {
            return nil
        }

        if familyContextStore.family == nil && shouldSuppressNoFamilyPermissionError(lastErrorMessage) {
            return nil
        }

        return lastErrorMessage
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
            if let visibleErrorMessage {
                FamilyAlertBanner(message: visibleErrorMessage)
            }

            familyHeaderSection

            if familyContextStore.family == nil {
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
                    subtitle: mistiaLocalized(vi: "Bạn trở thành owner và mời thêm thành viên sau.", en: "You become the owner and invite others later.", ja: "作成者が owner になり、あとでメンバーを招待できます。"),
                    icon: "plus",
                    iconColor: .mint
                ) {
                    activeSheet = .create
                }

                FamilyRowDivider()

                FamilySettingsRow(
                    title: mistiaLocalized(vi: "Nhập mã mời", en: "Join with code", ja: "招待コードで参加"),
                    subtitle: mistiaLocalized(vi: "Dùng mã hoặc link mời từ owner của gia đình.", en: "Use the invite code or link shared by the family owner.", ja: "owner が共有した招待コードまたはリンクを使います。"),
                    icon: "number",
                    iconColor: .cyan
                ) {
                    activeSheet = .join
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

private struct FamilyChartSegment: Identifiable {
    let label: String
    let valueMinor: Int64
    let color: Color

    var id: String { label }
}

// MARK: - Hero Components

private struct FamilyHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: FamilyAggregateSummary
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
                        title: mistiaLocalized(vi: "Công nợ", en: "Debts", ja: "負債"),
                        value: summary.totalDebtMinor.formattedCurrency(code: currencyCode),
                        color: .red
                    )
                    
                    FamilyMetricCompact(
                        title: mistiaLocalized(vi: "Có thể chi", en: "Spendable", ja: "使える"),
                        value: summary.spendableMinor.formattedCurrency(code: currencyCode),
                        color: MistiaAccent.purple.color
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
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Distribution Components

private struct FamilyDistributionSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: FamilyAggregateSummary
    @Binding var timeframe: FamilyTimeframe
    @Binding var mode: FamilyDistributionMode
    let currencyCode: String
    let onSegmentTap: (FamilyDonutSegment) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Timeframe picker (Segmented)
            Picker("", selection: $timeframe) {
                ForEach(FamilyTimeframe.allCases) { tf in
                    Text(tf.title).tag(tf)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
                VStack(spacing: 18) {
                    // Mode picker
                    HStack(spacing: 8) {
                        ForEach(FamilyDistributionMode.allCases) { m in
                            Button {
                                withAnimation(.snappy) { mode = m }
                            } label: {
                                Text(m.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background {
                                        if mode == m {
                                            Capsule()
                                                .fill(MistiaAccent.purple.color)
                                        } else {
                                            Capsule()
                                                .fill(colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.05))
                                        }
                                    }
                                    .foregroundStyle(mode == m ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if chartSegments.isEmpty {
                        Text(mistiaLocalized(vi: "Chưa có dữ liệu để hiển thị", en: "No data to display yet", ja: "表示できるデータがまだありません"))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    } else {
                        VStack(spacing: 18) {
                            FamilyDonutChart(
                                segments: chartSegments,
                                modeTitle: mode.title,
                                totalValueMinor: totalValueMinor,
                                currencyCode: currencyCode
                            )
                            .frame(height: 220)

                            VStack(spacing: 10) {
                                ForEach(Array(chartSegments.enumerated()), id: \.element.id) { index, segment in
                                    Button {
                                        onSegmentTap(FamilyDonutSegment(label: segment.label, valueMinor: segment.valueMinor, colorHex: nil))
                                    } label: {
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(segment.color)
                                                .frame(width: 10, height: 10)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(segment.label)
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.primary)

                                                Text(legendDetailText(for: segment, index: index))
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Text(percentageText(for: segment))
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(colorScheme == .dark ? .white.opacity(0.03) : .white.opacity(0.54))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }

    private var baseSegments: [FamilyDonutSegment] {
        switch mode {
        case .spending:
            return summary.expenseByCategory
        case .accounts:
            return summary.balanceByWalletKind.map { FamilyDonutSegment(label: $0.key.rawValue.capitalized, valueMinor: $0.value, colorHex: nil) }.sorted { $0.valueMinor > $1.valueMinor }
        case .members:
            return summary.spendingByMember.map { FamilyDonutSegment(label: $0.name, valueMinor: $0.amountMinor, colorHex: nil) }
        }
    }

    private var chartSegments: [FamilyChartSegment] {
        let filtered = baseSegments
            .map { FamilyDonutSegment(label: $0.label, valueMinor: max($0.valueMinor, 0), colorHex: $0.colorHex) }
            .filter { $0.valueMinor > 0 }
            .sorted { $0.valueMinor > $1.valueMinor }

        guard !filtered.isEmpty else { return [] }

        let leading = Array(filtered.prefix(4))
        let remainder = filtered.dropFirst(4)

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
        chartSegments.reduce(into: Int64.zero) { partial, segment in
            partial += segment.valueMinor
        }
    }

    private func percentageText(for segment: FamilyChartSegment) -> String {
        guard totalValueMinor > 0 else { return "0%" }
        let percentage = (Double(segment.valueMinor) / Double(totalValueMinor)) * 100
        return "\(Int(percentage.rounded()))%"
    }

    private func legendDetailText(for segment: FamilyChartSegment, index: Int) -> String {
        let formattedValue = segment.valueMinor.formattedCurrency(code: currencyCode)
        if index == 0 {
            return mistiaLocalized(
                vi: "Lớn nhất • \(formattedValue)",
                en: "Largest • \(formattedValue)",
                ja: "最大 • \(formattedValue)"
            )
        }
        return formattedValue
    }

    private func chartColor(for index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.40, green: 0.56, blue: 0.97),
            Color(red: 0.48, green: 0.75, blue: 0.98),
            Color(red: 0.45, green: 0.81, blue: 0.75),
            Color(red: 0.97, green: 0.73, blue: 0.43),
            Color(red: 0.82, green: 0.84, blue: 0.89)
        ]

        return palette[index % palette.count]
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

// MARK: - Comparison Components

private struct FamilyMemberComparisonSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: FamilyAggregateSummary
    @Binding var mode: FamilyComparisonMode
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mistiaLocalized(vi: "So sánh thành viên", en: "Member comparison", ja: "メンバー比較"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Spacer()
                
                Picker("", selection: $mode) {
                    ForEach(FamilyComparisonMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
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
                                        .fill(MistiaAccent.purple.color.gradient)
                                        .frame(width: geo.size.width * ratio(for: m.amountMinor), height: 10)
                                }
                            }
                            .frame(height: 10)
                        }
                    }
                }
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }

    private var members: [FamilyMemberSpendingSnapshot] {
        mode == .spending ? summary.spendingByMember : summary.incomeByMember
    }

    private func ratio(for amount: Int64) -> Double {
        let maxAmount = members.map(\.amountMinor).max() ?? 1
        return Double(max(amount, 0)) / Double(max(maxAmount, 1))
    }
}

// MARK: - Account List Components

private struct FamilyAggregateAccountList: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [FamilyAggregateWalletRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mistiaLocalized(vi: "Danh sách tài khoản gộp", en: "Merged accounts", ja: "統合口座リスト"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
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
        if row.wallet.kind == .creditCard && row.currentBalanceMinor > 0 {
            return .red
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
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

private struct FamilyDonutChart: View {
    let segments: [FamilyChartSegment]
    let modeTitle: String
    let totalValueMinor: Int64
    let currencyCode: String

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 18)

            Chart(segments) { segment in
                SectorMark(
                    angle: .value("Value", Double(segment.valueMinor)),
                    innerRadius: .ratio(0.72),
                    outerRadius: .ratio(0.98),
                    angularInset: 2.2
                )
                .cornerRadius(6)
                .foregroundStyle(segment.color.gradient)
            }
            .chartLegend(.hidden)

            VStack(spacing: 4) {
                Text(modeTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(totalValueMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 30)
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    private var familyMemberIDs: Set<UUID> {
        var ids = Set(familyContextStore.members.map(\.userID))
        if let currentUserID = familyContextStore.currentUserID {
            ids.insert(currentUserID)
        }
        return ids
    }

    private var allWallets: [LedgerWallet] {
        FamilyScopedData.visibleForFamilyOverview(
            storedWallets,
            entity: .wallet,
            scopes: ownershipScopes,
            familyMemberUserIDs: familyMemberIDs,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var allTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleForFamilyOverview(
            storedTransactions,
            entity: .transaction,
            scopes: ownershipScopes,
            familyMemberUserIDs: familyMemberIDs,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleBudgets: [BudgetPlan] {
        FamilyScopedData.visibleForFamilyOverview(
            storedBudgets,
            entity: .budgetPlan,
            scopes: ownershipScopes,
            familyMemberUserIDs: familyMemberIDs,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleBills: [RecurringBillPlan] {
        FamilyScopedData.visibleForFamilyOverview(
            storedBills,
            entity: .recurringBillPlan,
            scopes: ownershipScopes,
            familyMemberUserIDs: familyMemberIDs,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleInstallments: [InstallmentPlan] {
        FamilyScopedData.visibleForFamilyOverview(
            storedInstallments,
            entity: .installmentPlan,
            scopes: ownershipScopes,
            familyMemberUserIDs: familyMemberIDs,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleOccurrences: [DueOccurrenceRecord] {
        FamilyScopedData.visibleForFamilyOverview(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
            scopes: ownershipScopes,
            familyMemberUserIDs: familyMemberIDs,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var transactionRecords: [TransactionRecordSnapshot] {
        allTransactions.map(\.planningRecordSnapshot)
    }

    private var aggregateWalletRows: [FamilyAggregateWalletRow] {
        allWallets
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
            .map { wallet in
                FamilyAggregateWalletRow(
                    wallet: wallet,
                    currentBalanceMinor: TransactionLogic.effectiveBalance(
                        for: TransactionWalletSnapshot(
                            id: wallet.id,
                            kind: wallet.kind,
                            openingBalanceMinor: wallet.openingBalanceMinor
                        ),
                        records: transactionRecords
                    )
                )
            }
    }

    private var currentMonth: Date {
        PlanningLogic.startOfMonth(for: .now, calendar: calendar)
    }

    private var budgetRows: [OverviewBudgetAlertSnapshot] {
        let activeBudgetPlans = visibleBudgets
            .filter {
                !$0.isArchived
                    && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == currentMonth
            }
            .map { $0.planningSnapshot(calendar: calendar) }

        return OverviewLogic.budgetAlerts(
            budgets: activeBudgetPlans,
            transactionRecords: transactionRecords,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var dueAlerts: [OverviewDueAlertSnapshot] {
        let occurrenceSnapshots = visibleOccurrences.map(\.planningSnapshot)
        
        let planningCreditCardAccounts = allWallets.compactMap { $0.planningCreditCardSnapshot(records: transactionRecords) }
        
        let creditCardDueItems = PlanningLogic.creditCardDueItems(
            accounts: planningCreditCardAccounts,
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            referenceDate: .now,
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

        return OverviewLogic.dueAlerts(
            creditCardDues: creditCardDueItems,
            recurringDues: recurringBillDueItems + installmentDueItems,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var summary: FamilyAggregateSummary {
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        
        let interval: DateInterval
        switch timeframe {
        case .week:
            interval = calendar.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 3600*24*7)
        case .month:
            interval = calendar.dateInterval(of: .month, for: .now) ?? DateInterval(start: .now, duration: 3600*24*30)
        case .year:
            interval = calendar.dateInterval(of: .year, for: .now) ?? DateInterval(start: .now, duration: 3600*24*365)
        }

        let memberNames = Dictionary(uniqueKeysWithValues: familyContextStore.members.map { ($0.userID, $0.displayName) })

        return FamilyLogic.aggregateSummary(
            wallets: aggregateWalletRows.map { row in
                FamilyAggregateWalletSnapshot(
                    ownerUserID: familyOwnerUserID(for: row.wallet.id, entity: .wallet),
                    kind: row.wallet.kind.familyAggregateKind,
                    balanceMinor: row.wallet.kind == .creditCard ? 0 : row.currentBalanceMinor,
                    debtMinor: row.wallet.kind == .creditCard ? max(row.currentBalanceMinor, 0) : 0
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
            selectedInterval: interval,
            visibleMemberIDs: familyMemberIDs,
            memberNames: memberNames,
            calendar: calendar
        )
    }

    @State private var timeframe: FamilyTimeframe = .month
    @State private var distributionMode: FamilyDistributionMode = .spending
    @State private var comparisonMode: FamilyComparisonMode = .spending
    @State private var activeSheet: FamilyOverviewSheet?

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: familyContextStore.family?.name ?? mistiaLocalized(vi: "Gia đình", en: "Family", ja: "家族"),
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 18,
            titleDisplayMode: .large
        ) {
            FamilyContextChipBar()
            
            FamilyOverviewHeader(
                walletRows: aggregateWalletRows,
                signedInUserID: sessionStore.signedInUserID,
                onInviteTap: { activeSheet = .invite }
            )
            .padding(.top, 8)

            FamilyHeroCard(
                summary: summary,
                currencyCode: currencyCode
            )

            FamilyDistributionSection(
                summary: summary,
                timeframe: $timeframe,
                mode: $distributionMode,
                currencyCode: currencyCode,
                onSegmentTap: { segment in
                    activeSheet = .filterTransactions
                }
            )

            FamilyMemberComparisonSection(
                summary: summary,
                mode: $comparisonMode,
                currencyCode: currencyCode
            )

            FamilyAggregateAccountList(
                rows: aggregateWalletRows
            )

            FamilyBudgetStatusSection(
                rows: budgetRows,
                currencyCode: currencyCode
            )

            FamilyUpcomingSection(
                rows: dueAlerts,
                currencyCode: currencyCode
            )

            FamilyAIInsightsSection(insights: summary.insights)
        }
        .overlay(alignment: .topTrailing) {
            if familyContextStore.isRefreshingLatest {
                FamilySyncOverlayIndicator()
                    .padding(.top, 12)
                    .padding(.trailing, 18)
            }
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
        .task {
            await familyContextStore.refreshLatest(
                sessionStore: sessionStore,
                source: .enterFamily
            )
        }
    }

    private func familyOwnerUserID(for recordID: UUID, entity: MistiaSyncEntity) -> UUID {
        let ownerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: entity)
        return ownerMap[recordID] ?? sessionStore.signedInUserID ?? UUID()
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
                                familyContextStore.activateMemberView(member)
                                dismiss()
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
                Section(mistiaLocalized(vi: "Gia đình mới", en: "New family", ja: "新しい家族")) {
                    TextField(mistiaLocalized(vi: "Tên gia đình", en: "Family name", ja: "家族名"), text: $familyName)
                        .focused($focusedField, equals: .familyName)
                }
            }
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
                    .disabled(familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    @State private var inviteCode = ""
    @FocusState private var focusedField: FamilySheetFocusedField?

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Mã mời", en: "Invite code", ja: "招待コード")) {
                    TextField("ABCD1234", text: $inviteCode)
                        .focused($focusedField, equals: .inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(mistiaLocalized(vi: "Tham gia gia đình", en: "Join family", ja: "家族に参加"))
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
                            await familyContextStore.joinFamily(inviteCode: inviteCode, sessionStore: sessionStore)
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
                    .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task {
            guard focusedField == nil else { return }
            try? await Task.sleep(for: .milliseconds(150))
            focusedField = .inviteCode
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
    @State private var grantedTargetUserIDs: Set<UUID>

    init(member: FamilyMember) {
        self.member = member
        _role = State(initialValue: member.role)
        _policy = State(initialValue: member.policy)
        _grantedTargetUserIDs = State(initialValue: [])
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

                if familyContextStore.currentRole == .owner {
                    Section(mistiaLocalized(vi: "Có thể dùng ví của ai", en: "Can use whose wallets", ja: "誰のウォレットを使えるか")) {
                        ForEach(grantTargets, id: \.membershipID) { target in
                            Toggle(
                                target.displayName,
                                isOn: Binding(
                                    get: { grantedTargetUserIDs.contains(target.userID) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            grantedTargetUserIDs.insert(target.userID)
                                        } else {
                                            grantedTargetUserIDs.remove(target.userID)
                                        }
                                    }
                                )
                            )
                        }

                        if grantTargets.isEmpty {
                            Text(mistiaLocalized(vi: "Không còn thành viên nào khác để cấp quyền.", en: "There are no other members to grant access to.", ja: "アクセス権を付与できる他のメンバーはいません。"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                                grantedTargetUserIDs: grantedTargetUserIDs,
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
        .task {
            grantedTargetUserIDs = familyContextStore.walletAccessTargetUserIDs(for: member)
        }
    }

    private var grantTargets: [FamilyMember] {
        familyContextStore.members.filter { $0.userID != member.userID }
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
