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
                await familyContextStore.refreshFamilyMetadata(sessionStore: sessionStore)
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
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        MistiaGlassCard(cornerRadius: 14, tint: cardTint, padding: 0) {
            VStack(spacing: 0) {
                FamilySettingsRow(
                    title: L10n.family.family.createFamily,
                    subtitle: remoteActionsDisabledReason ?? L10n.family.family.youBecomeTheOwnerAndInviteOthers,
                    icon: "plus",
                    iconColor: .mint,
                    isDisabled: remoteActionsDisabled
                ) {
                    activeSheet = .create
                }

                FamilyRowDivider()

                FamilySettingsRow(
                    title: L10n.family.family.useInviteLink,
                    subtitle: remoteActionsDisabledReason ?? L10n.family.family.tapTheOwnerSSharedLinkOr,
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
                    L10n.family.family.familyIsWaitingForTheConnection,
                    systemImage: "wifi.slash"
                )
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

                Text(sessionStore.remoteUnavailableReason ?? L10n.family.family.reconnectToCreateAFamilyUseAn)
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

                Text(L10n.family.family.family)
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
                                                Text(L10n.family.family.you)
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
                Text(L10n.family.family.youCanCheckWhatFamilyMembersCan)
                .descriptionTextStyle()
                .padding(.horizontal, 2)
            }
            .cardDescriptionStyle()

            FamilyHubRouteSection(rows: familyHubRouteRows, tint: cardTint) { row in
                destination = row.destination
            }

            // Privacy Link
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.family.family.mistiaWillUseDataToSecurelySync)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)

                Button {
                    activeSheet = .privacy
                } label: {
                    Text(L10n.family.family.confirmDataPersonalInformationUsage)
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
                title: L10n.family.family.familyOverview,
                icon: "chart.bar.xaxis",
                iconColor: .indigo
            )
        ]

        if familyContextStore.canInviteMembers {
            rows.append(
                FamilyHubRouteRowItem(
                    destination: .inviteManagement,
                    title: L10n.family.family.manageInvites,
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
        case .week: return L10n.family.family.week
        case .month: return L10n.family.family.month
        case .year: return L10n.family.family.year
        }
    }
}

private enum FamilyDistributionMode: String, CaseIterable, Identifiable {
    case spending, accounts, members
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spending: return L10n.family.family.spending
        case .accounts: return L10n.family.family.accounts
        case .members: return L10n.family.family.members
        }
    }
}

private enum FamilyComparisonMode: String, CaseIterable, Identifiable {
    case spending, income
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spending: return L10n.family.family.spending
        case .income: return L10n.family.family.income
        }
    }
}

private enum FamilyOverviewSheet: String, Identifiable {
    case invite
    case filterTransactions
    var id: String { rawValue }
}

private typealias FamilyOverviewDerivedData = FamilyOverviewCalculationResult

private struct FamilyOverviewDataCache {
    let key: FamilyOverviewDataCacheKey
    let data: FamilyOverviewDerivedData
}

private struct FamilyOverviewDataCacheKey: Hashable {
    let timeframeRawValue: String
    let activeScope: FamilyContext.Scope
    let familyID: UUID?
    let ownerUserID: UUID?
    let budgetManagerUserID: UUID?
    let goalManagerUserID: UUID?
    let currentUserID: UUID?
    let activeLocalProfileUserID: UUID?
    let currencyCode: String
    let currencyRateMode: String
    let manualJPYToVNDRate: String
    let cachedRatesSignature: Int
    let referenceDayStart: TimeInterval
    let membersSignature: Int
    let walletsSignature: MistiaCollectionChangeSignature
    let transactionsSignature: MistiaCollectionChangeSignature
    let budgetsSignature: MistiaCollectionChangeSignature
    let goalsSignature: MistiaCollectionChangeSignature
    let billsSignature: MistiaCollectionChangeSignature
    let installmentsSignature: MistiaCollectionChangeSignature
    let occurrencesSignature: MistiaCollectionChangeSignature
    let ownershipSignature: MistiaCollectionChangeSignature
    let auditSignature: MistiaCollectionChangeSignature
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
                        Text(L10n.family.family.totalAssets)
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
                        title: L10n.family.family.currentDebt,
                        value: summary.totalDebtMinor.formattedCurrency(code: currencyCode),
                        color: .red
                    )
                    
                    FamilyMetricCompact(
                        title: L10n.family.family.spendableThisMonth,
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
        return L10n.family.family.needValueMoreThisMonth(String(describing: amount))
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
    let accountSegments: [FamilyDonutSegment]
    let currencyCode: String
    let onSegmentTap: (FamilyDonutSegment) -> Void

    var body: some View {
        if availableModes.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 12) {
                Picker(String(), selection: $timeframe) {
                    ForEach(FamilyTimeframe.allCases) { tf in
                        Text(tf.title).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)

                MistiaGlassCard(cornerRadius: 24, tint: cardTint) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.family.family.distribution)
                                .familyOverviewSectionTitleStyle()

                            Spacer(minLength: 10)

                            Text(totalValueMinor.formattedCurrency(code: currencyCode))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Picker(String(), selection: resolvedModeBinding) {
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
            return accountSegments
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
                    label: L10n.family.family.other,
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

    private func normalizeMode() {
        guard !availableModes.isEmpty, !availableModes.contains(mode), let firstMode = availableModes.first else {
            return
        }

        mode = firstMode
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

            Text(verbatim: "100%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.bottom, 2)
        }
        .frame(width: 132, height: 72)
        .frame(width: 150, height: 104, alignment: .center)
        .accessibilityLabel(L10n.family.family.singleItemFillsTheChart)
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
                    Text(L10n.family.family.memberComparison)
                        .familyOverviewSectionTitleStyle()

                    Spacer()

                    if availableModes.count > 1 {
                        Picker(String(), selection: $mode) {
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
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var currencyRateMode = MistiaCurrencyRateMode.automatic.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = ""
    @AppStorage(MistiaCurrencySettings.StorageKey.cachedRatesData) private var cachedCurrencyRatesData = Data()
    let rows: [FamilyWalletAggregateSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.family.family.mergedAccounts)
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            MistiaFinanceIconView(icon: row.kind.defaultIconSymbolName, fallbackColor: MistiaAccent.purple.color, size: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                
                                if row.kind == .creditCard {
                                    Text(L10n.family.family.upcoming)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(row.currentBalanceMinor.formattedCurrency(code: row.currencyCode))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(amountColor(for: row))

                                if let approximatePrimaryAmountText = approximatePrimaryAmountText(for: row) {
                                    Text(approximatePrimaryAmountText)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
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

    private var exchangeRates: [MistiaExchangeRate] {
        _ = currencyRateMode
        _ = manualJPYToVNDRate
        _ = cachedCurrencyRatesData
        return MistiaCurrencySettings.rates()
    }

    private func approximatePrimaryAmountText(for row: FamilyWalletAggregateSnapshot) -> String? {
        MistiaCurrencyLogic.approximatePrimaryAmountText(
            amountMinor: row.currentBalanceMinor,
            sourceCurrencyCode: row.currencyCode,
            primaryCurrencyCode: primaryCurrencyCode,
            rates: exchangeRates
        )
    }

    private func amountColor(for row: FamilyWalletAggregateSnapshot) -> Color {
        if row.kind == .creditCard {
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
    let rows: [FamilyBudgetAggregateSnapshot]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.family.family.familyBudget)
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(L10n.family.family.noBudgetsAreOverLimit)
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

private struct FamilyGoalStatusSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [FamilyGoalAggregateSnapshot]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.family.family.familyGoals)
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: row.iconSymbolName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(MistiaAccent.income.color)
                                    .frame(width: 20)

                                Text(row.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                                Spacer()

                                Text(row.progressPercentText)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(MistiaAccent.income.color)
                            }

                            ProgressView(value: min(max(row.progress, 0), 1))
                                .tint(MistiaAccent.income.color)

                            Text(goalAmountText(for: row))
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
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

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.04) : .white.opacity(0.16)
    }

    private func goalAmountText(for row: FamilyGoalAggregateSnapshot) -> String {
        let saved = row.currentSavedMinor.formattedCurrency(code: row.currencyCode)
        let target = row.targetMinor.formattedCurrency(code: row.currencyCode)
        return "\(saved) / \(target)"
    }
}

private struct FamilyUpcomingSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: [OverviewDueAlertSnapshot]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.family.family.upcoming)
                .familyOverviewSectionTitleStyle()
                .padding(.horizontal, 4)

            MistiaGlassCard(cornerRadius: 24, tint: cardTint, padding: 0) {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(L10n.family.family.noUpcomingItems)
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
                Text(L10n.family.family.filteredTransactions)
                    .font(.headline)
                Spacer()
                Text(L10n.family.family.transactionFilteringIsComingSoon)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle(L10n.family.family.transactions)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.family.family.close) { dismiss() }
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
                Text(L10n.family.family.familyInsights)
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
    @Environment(SessionStore.self) private var sessionStore
    let walletRows: [FamilyWalletAggregateSnapshot]
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
                            
                            Text(L10n.family.family.family2)
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
                                            Image(systemName: row.kind.defaultIconSymbolName)
                                            Text(row.name)
                                            Spacer()
                                            Text(row.currentBalanceMinor.formattedCurrency(code: row.currencyCode))
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
                                    Label(L10n.family.family.viewDetails, systemImage: "eye.fill")
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

                                Text(L10n.family.family.invite)
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
                    L10n.family.family.valueMembers(String(describing: members.count))
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
                    Text(L10n.family.family.familyNeedsAttention)
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
                Text(L10n.family.family.syncingFamily)
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
    var body: some View {
        FamilyOverviewDataHost()
    }
}

private struct FamilyOverviewDataHost: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @AppStorage(MistiaCurrencySettings.StorageKey.rateMode) private var currencyRateMode = MistiaCurrencyRateMode.automatic.rawValue
    @AppStorage(MistiaCurrencySettings.StorageKey.manualJPYToVNDRate) private var manualJPYToVNDRate = ""
    @AppStorage(MistiaCurrencySettings.StorageKey.cachedRatesData) private var cachedCurrencyRatesData = Data()

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var storedTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgets: [BudgetPlan]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil })
    private var storedGoals: [SavingsGoal]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var storedBills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var storedInstallments: [InstallmentPlan]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @Query private var transactionAuditRecords: [TransactionAuditRecord]

    private var appExchangeRates: [MistiaExchangeRate] {
        _ = currencyRateMode
        _ = manualJPYToVNDRate
        _ = cachedCurrencyRatesData
        return MistiaCurrencySettings.rates()
    }

    private func makeOverviewInputSnapshot() -> FamilyOverviewCalculationInput {
        let now = Date.now
        let currentMonth = PlanningLogic.startOfMonth(for: now, calendar: calendar)
        let interval = selectedInterval(for: timeframe, now: now)
        let familyMemberUserIDs = familyMemberIDs
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let budgetOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
        let goalOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
        let billOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
        let installmentOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
        let occurrenceOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .dueOccurrenceRecord)
        let transactionAuditMap = TransactionAuditStore.auditMap(from: transactionAuditRecords)
        let visibleWallets = visibleForFamilyOverview(
            storedWallets,
            entity: .wallet,
            ownerMap: walletOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        .filter { !$0.isArchived }
        let visibleTransactions = visibleForFamilyOverview(
            storedTransactions,
            entity: .transaction,
            ownerMap: transactionOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        .filter { !$0.isArchived }
        let visibleBudgets = visibleForFamilyOverview(
            storedBudgets,
            entity: .budgetPlan,
            ownerMap: budgetOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        .filter { !$0.isArchived }
        let visibleGoals = visibleForFamilyOverview(
            storedGoals,
            entity: .savingsGoal,
            ownerMap: goalOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        .filter { !$0.isArchived }
        let visibleBills = visibleForFamilyOverview(
            storedBills,
            entity: .recurringBillPlan,
            ownerMap: billOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        .filter { !$0.isArchived }
        let visibleInstallments = visibleForFamilyOverview(
            storedInstallments,
            entity: .installmentPlan,
            ownerMap: installmentOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        .filter { !$0.isArchived }
        let visibleOccurrences = visibleForFamilyOverview(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
            ownerMap: occurrenceOwnerMap,
            familyMemberUserIDs: familyMemberUserIDs
        )
        let walletSnapshots = visibleWallets.map { wallet in
            let profile = wallet.creditCardProfile.map {
                FamilyOverviewCreditCardProfileSnapshot(
                    issuerName: $0.issuerName,
                    network: $0.network,
                    last4: $0.last4,
                    creditLimitMinor: $0.creditLimitMinor,
                    statementClosingDay: $0.statementClosingDay,
                    paymentDueDay: $0.paymentDueDay,
                    paymentSourceWalletID: $0.paymentSourceWallet?.id,
                    paymentSourceWalletName: $0.paymentSourceWallet?.name,
                    autoPayEnabled: $0.autoPayEnabled
                )
            }

            return FamilyOverviewWalletInputSnapshot(
                id: wallet.id,
                ownerUserID: walletOwnerMap[wallet.id] ?? sessionStore.signedInUserID ?? UUID(),
                name: wallet.name,
                kind: wallet.kind,
                openingBalanceMinor: wallet.openingBalanceMinor,
                creditCardProfile: profile,
                currencyCode: wallet.currencyCode,
                sortOrder: wallet.sortOrder,
                createdAt: wallet.createdAt
            )
        }
        let transactionSnapshots = visibleTransactions.map { transaction in
            let record = transaction.planningRecordSnapshot
            return FamilyOverviewTransactionInputSnapshot(
                record: record,
                overview: transaction.overviewSnapshot,
                aggregate: FamilyAggregateTransactionSnapshot(
                    ownerUserID: transactionOwnerMap[transaction.id] ?? sessionStore.signedInUserID ?? UUID(),
                    createdByUserID: transactionAuditMap[transaction.id]?.createdByUserID,
                    categoryName: transaction.category?.localizedDisplayName,
                    categoryParentName: transaction.category?.parentCategory?.localizedDisplayName,
                    occurredAt: transaction.occurredAt,
                    kind: transaction.primaryKind.familyAggregateKind,
                    amountMinor: abs(transaction.amountMinor),
                    currencyCode: record.sourceCurrencyCode ?? transaction.sourceWallet?.currencyCode ?? "JPY",
                    isCreditCardPayment: TransactionLogic.isCreditCardPayment(record),
                    isAdjustment: TransactionLogic.isAdjustment(record),
                    isInstallmentPayment: TransactionLogic.isInstallmentPayment(record)
                )
            )
        }
        let activeBudgetPlans = visibleBudgets
            .filter {
                PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == currentMonth
            }
            .map { budget in
                let plan = budget.planningSnapshot(calendar: calendar)
                return FamilyBudgetPlanSnapshot(
                    id: plan.id,
                    ownerUserID: budgetOwnerMap[plan.id] ?? sessionStore.signedInUserID ?? UUID(),
                    categoryName: plan.categoryName,
                    iconSymbolName: plan.categoryIconSymbolName,
                    colorHex: plan.categoryColorHex,
                    limitMinor: plan.limitMinor,
                    currencyCode: plan.currencyCode,
                    monthAnchor: plan.monthAnchor
                )
            }
        let goalSnapshots = visibleGoals.map { goal in
            let snapshot = goal.planningSnapshot
            return FamilyGoalSnapshot(
                id: snapshot.id,
                ownerUserID: goalOwnerMap[goal.id] ?? sessionStore.signedInUserID ?? UUID(),
                name: snapshot.name,
                iconSymbolName: snapshot.iconSymbolName,
                targetMinor: snapshot.targetMinor,
                currentSavedMinor: snapshot.currentSavedMinor,
                targetDate: snapshot.targetDate,
                currencyCode: snapshot.currencyCode,
                sortOrder: snapshot.sortOrder
            )
        }
        let memberNames = Dictionary(
            familyContextStore.members.map { ($0.userID, $0.displayName) },
            uniquingKeysWith: { _, latest in latest }
        )

        return FamilyOverviewCalculationInput(
            now: now,
            currentMonth: currentMonth,
            selectedInterval: interval,
            timeframeTitle: timeframe.title,
            familyMemberUserIDs: familyMemberUserIDs,
            memberNames: memberNames,
            memberOrder: familyMemberOrder,
            familyOwnerUserID: familyContextStore.family?.ownerUserID,
            budgetManagerUserID: familyContextStore.family?.budgetManagerUserID,
            goalManagerUserID: familyContextStore.family?.goalManagerUserID,
            reportingCurrencyCode: currencyCode,
            exchangeRates: appExchangeRates,
            calendar: calendar,
            wallets: walletSnapshots,
            transactions: transactionSnapshots,
            budgets: activeBudgetPlans,
            goals: goalSnapshots,
            bills: visibleBills.map(\.planningSnapshot),
            installments: visibleInstallments.map(\.planningSnapshot),
            occurrences: visibleOccurrences.map(\.planningSnapshot)
        )
    }

    private var cachedOverviewData: FamilyOverviewDerivedData? {
        overviewDataCache?.data
    }

    private func refreshOverviewDataCache(for key: FamilyOverviewDataCacheKey) async {
        let input = makeOverviewInputSnapshot()
        let data = await Task.detached(priority: .userInitiated) {
            FamilyOverviewCalculator.compute(input: input)
        }.value

        guard !Task.isCancelled, overviewDataCacheKey == key else {
            return
        }

        withAnimation(.snappy) {
            overviewDataCache = FamilyOverviewDataCache(
                key: key,
                data: data
            )
        }
    }

    private var overviewDataCacheKey: FamilyOverviewDataCacheKey {
        FamilyOverviewDataCacheKey(
            timeframeRawValue: timeframe.rawValue,
            activeScope: familyContextStore.activeContext.scope,
            familyID: familyContextStore.family?.id,
            ownerUserID: familyContextStore.family?.ownerUserID,
            budgetManagerUserID: familyContextStore.family?.budgetManagerUserID,
            goalManagerUserID: familyContextStore.family?.goalManagerUserID,
            currentUserID: familyContextStore.currentUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            currencyCode: currencyCode,
            currencyRateMode: currencyRateMode,
            manualJPYToVNDRate: manualJPYToVNDRate,
            cachedRatesSignature: cachedCurrencyRatesData.hashValue,
            referenceDayStart: calendar.startOfDay(for: .now).timeIntervalSince1970,
            membersSignature: membersSignature,
            walletsSignature: MistiaCollectionChangeSignature.make(
                storedWallets,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            transactionsSignature: MistiaCollectionChangeSignature.make(
                storedTransactions,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            budgetsSignature: MistiaCollectionChangeSignature.make(
                storedBudgets,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            goalsSignature: MistiaCollectionChangeSignature.make(
                storedGoals,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            billsSignature: MistiaCollectionChangeSignature.make(
                storedBills,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            installmentsSignature: MistiaCollectionChangeSignature.make(
                storedInstallments,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            occurrencesSignature: MistiaCollectionChangeSignature.make(
                storedOccurrences,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
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

    private var membersSignature: Int {
        var hasher = Hasher()
        hasher.combine(familyContextStore.members.count)
        for member in familyContextStore.members {
            hasher.combine(member.membershipID)
            hasher.combine(member.userID)
            hasher.combine(member.displayName)
            hasher.combine(member.role.rawValue)
            hasher.combine(member.hasSyncedCloudData)
        }
        return hasher.finalize()
    }

    private var familyMemberIDs: Set<UUID> {
        var ids = Set(familyContextStore.members.map(\.userID))
        if let currentUserID = familyContextStore.currentUserID {
            ids.insert(currentUserID)
        }
        return ids
    }

    private var familyMemberOrder: [UUID] {
        var seen = Set<UUID>()
        return ([familyContextStore.family?.ownerUserID].compactMap { $0 } + familyContextStore.members.map(\.userID))
            .filter { seen.insert($0).inserted }
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
    @State private var overviewDataCache: FamilyOverviewDataCache?

    var body: some View {
        let dataKey = overviewDataCacheKey

        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: familyContextStore.family?.name ?? L10n.family.family.family,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            onRefresh: {
                await familyContextStore.refreshLatest(
                    sessionStore: sessionStore,
                    source: .familyOverview
                )
            },
            contentSpacing: 18,
            titleDisplayMode: .large
        ) {
            if let data = cachedOverviewData {
                FamilyOverviewContent(
                    data: data,
                    timeframe: $timeframe,
                    currencyCode: currencyCode
                )
            } else {
                FamilyOverviewLoadingState()
            }
        }
        .task(id: familyContextStore.family?.id) {
            if !familyContextStore.isViewingOtherMemberContext {
                familyContextStore.activateFamilyHome()
            }
            await familyContextStore.refreshLatest(
                sessionStore: sessionStore,
                source: .familyOverview
            )
        }
        .task(id: dataKey) {
            await refreshOverviewDataCache(for: dataKey)
        }
    }

}

private struct FamilyOverviewContent: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    let data: FamilyOverviewDerivedData
    @Binding var timeframe: FamilyTimeframe
    let currencyCode: String

    @State private var distributionMode: FamilyDistributionMode = .spending
    @State private var comparisonMode: FamilyComparisonMode = .spending
    @State private var activeSheet: FamilyOverviewSheet?

    var body: some View {
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
            accountSegments: data.summary.balanceByWalletName,
            currencyCode: currencyCode,
            onSegmentTap: { _ in
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

        if !data.goalRows.isEmpty {
            FamilyGoalStatusSection(
                rows: data.goalRows,
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .invite:
                    FamilyInviteSheet()
                case .filterTransactions:
                    FamilyTransactionFilterSheet()
                }
            }
    }
}

private struct FamilyOverviewLoadingState: View {
    var body: some View {
        VStack {
            ProgressView()
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
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
            title: L10n.family.family.members,
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
    @Environment(MistiaUIState.self) private var uiState

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
                L10n.family.family.transferOwner2,
                isPresented: $confirmsTransferOwner,
                titleVisibility: .visible
            ) {
                Button(L10n.family.family.transferOwner, role: .destructive) {
                    Task {
                        await familyContextStore.transferOwner(to: member, sessionStore: sessionStore)
                        dismiss()
                    }
                }

                Button(L10n.common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.family.family.valueWillBeTheOnlyOwnerOf(String(describing: member.displayName)))
            }

        case .viewData:
            Button {
                familyContextStore.activateMemberView(member)
                uiState.requestTabSelection(.overview)
                Task { @MainActor in
                    await familyContextStore.refreshMemberFinance(
                        sessionStore: sessionStore,
                        memberUserID: member.userID
                    )
                }
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

                Button(L10n.common.cancel, role: .cancel) {
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
            return L10n.family.family.sharing
        case .permissions:
            return L10n.family.family.permissions2
        case .transferOwner:
            return L10n.family.family.transferOwner
        case .viewData:
            return L10n.family.family.viewValueSData(String(describing: member.displayName))
        case .destructive:
            if isMe {
                return isOwner
                    ? L10n.family.family.deleteFamily2
                    : L10n.family.family.leaveFamily2
            }

            return L10n.family.family.removeValue(String(describing: member.displayName))
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
            return L10n.family.family.deleteFamily
        case .leaveFamily:
            return L10n.family.family.leaveFamily
        case .removeMember:
            return L10n.family.family.removeMember
        case nil:
            return ""
        }
    }

    private var destructiveActionButtonTitle: String {
        switch destructiveAction {
        case .deleteFamily:
            return L10n.family.family.deletePermanently
        case .leaveFamily:
            return L10n.family.family.leave
        case .removeMember:
            return L10n.family.family.removeFromFamily
        case nil:
            return ""
        }
    }

    private var destructiveActionMessage: String {
        switch destructiveAction {
        case .deleteFamily:
            return L10n.family.family.allSharedDataAndFamilyConnectionsWill
        case .leaveFamily:
            return L10n.family.family.youWillNoLongerHaveAccessTo
        case .removeMember:
            return L10n.family.family.thisMemberWillBeRemovedAndLose
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

                Section(L10n.family.family.newFamily) {
                    TextField(L10n.family.family.familyName, text: $familyName)
                        .focused($focusedField, equals: .familyName)
                }
            }
            .disabled(!sessionStore.canPerformRemoteActions)
            .dismissKeyboardOnTap()
            .navigationTitle(L10n.family.family.createFamily)
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
                    Text(L10n.family.family.ifYouVeCopiedAnInviteLink)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section(L10n.family.family.inviteLink) {
                    TextField(L10n.family.invite.linkPlaceholder, text: $inviteLink)
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
            .navigationTitle(L10n.family.family.useInviteLink)
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
                            validationMessage = L10n.family.family.thisInviteLinkIsnTValid
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
            title: L10n.family.family.manageInvites,
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
                    L10n.family.family.noInvitesYet,
                    systemImage: "link.badge.plus"
                )
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

                Text(L10n.family.family.createdLinksWillAppearHereWithPending)
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
                    title: L10n.family.family.pending,
                    count: pendingCount,
                    tint: .orange
                )
                inviteSummaryMetric(
                    title: L10n.family.family.used,
                    count: acceptedCount,
                    tint: .mint
                )
                inviteSummaryMetric(
                    title: L10n.family.family.declined,
                    count: declinedCount,
                    tint: .red
                )
                inviteSummaryMetric(
                    title: L10n.family.family.expired,
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
            Text(verbatim: "\(count)")
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
            ?? L10n.family.family.acceptedMember
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
            return L10n.family.family.roleValue(String(describing: invite.defaultRole.title))
        }

        return L10n.family.family.inviteRoleValue(String(describing: invite.defaultRole.title))
    }

    private var copyTitle: String {
        if copiedInviteID == invite.id {
            return L10n.family.family.copied
        }
        return L10n.family.family.copy
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
                            Label(L10n.family.family.share, systemImage: "square.and.arrow.up")
                        }
                    }

                    Button(action: onCopy) {
                        Label(copyTitle, systemImage: copiedInviteID == invite.id ? "checkmark" : "doc.on.doc")
                    }

                    if invite.status == .pending {
                        Spacer(minLength: 0)

                        Button(role: .destructive, action: onRevoke) {
                            Label(L10n.family.family.revoke, systemImage: "xmark.circle")
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
        return L10n.family.family.youAlreadyHavePendingInvitesYou
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

                Section(L10n.family.family.inviteRole) {
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
            .navigationTitle(L10n.family.family.inviteMember)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.family.family.close) {
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
                            Text(L10n.family.family.createLink)
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
            return L10n.family.family.aFamilyHasOneOwnerInviteA
        case .member:
            return L10n.family.family.membersCanViewFamilyDataByDefault
        case .kid:
            return L10n.family.family.kidsAreLimitedByDefaultAndCan
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
    L10n.family.family.sentValue(String(describing: invite.createdAt.formatted(date: .abbreviated, time: .shortened)))
}

private func familyInviteLifecycleText(_ invite: FamilyInviteRecord) -> String {
    if invite.status == .accepted, let acceptedAt = invite.acceptedAt {
        return L10n.family.family.acceptedValue(String(describing: acceptedAt.formatted(date: .abbreviated, time: .shortened)))
    }

    if invite.status == .revoked, let revokedAt = invite.revokedAt {
        return L10n.family.family.revokedValue(String(describing: revokedAt.formatted(date: .abbreviated, time: .shortened)))
    }

    if invite.status == .declined, let declinedAt = invite.declinedAt {
        return L10n.family.family.declinedValue(String(describing: declinedAt.formatted(date: .abbreviated, time: .shortened)))
    }

    return L10n.family.family.expiresValue(String(describing: invite.expiresAt.formatted(date: .abbreviated, time: .shortened)))
}

private func familyInviteStatusTitle(_ status: FamilyInviteStatus) -> String {
    switch status {
    case .pending:
        return L10n.family.family.pending
    case .accepted:
        return L10n.family.family.used
    case .declined:
        return L10n.family.family.declined
    case .expired:
        return L10n.family.family.expired
    case .revoked:
        return L10n.family.family.revoked
    case .invalid:
        return L10n.family.family.invalid
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

private struct FamilySharingPermissionKey: Hashable {
    let resourceType: MistiaFamilyNotificationResourceType
    let resourceID: UUID?
    let scope: MistiaFamilyPermissionScope

    var sortKey: String {
        [
            resourceType.rawValue,
            resourceID?.uuidString.lowercased() ?? "",
            scope.rawValue
        ].joined(separator: ":")
    }
}

private struct FamilySharingPermissionCommit {
    let key: FamilySharingPermissionKey
    let isGranted: Bool
}

private struct FamilySharingManagerCommit {
    let resourceType: MistiaFamilyNotificationResourceType
    let managerUserID: UUID
}

private struct FamilySharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let member: FamilyMember

    @State private var stagedPermissionValues: [FamilySharingPermissionKey: Bool] = [:]
    @State private var stagedPlanningManagerValues: [MistiaFamilyNotificationResourceType: UUID] = [:]
    @State private var isApplyingSharingChanges = false
    @State private var sharingErrorMessage: String?

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

                if let sharingErrorMessage {
                    Section {
                        Text(sharingErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if familyContextStore.currentRole == .owner {
                    Section(L10n.family.family.familyOverviewManagers) {
                        planningManagerToggle(
                            title: L10n.family.family.manageFamilyBudgets,
                            resourceType: .budget
                        )
                        planningManagerToggle(
                            title: L10n.family.family.manageFamilyGoals,
                            resourceType: .goal
                        )
                    }
                }

                Section(L10n.family.family.editAccess) {
                    sharingToggle(
                        title: L10n.family.family.transactions,
                        resourceType: .transaction,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: L10n.family.family.categories,
                        resourceType: .category,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: L10n.family.family.budgets,
                        resourceType: .budget,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: L10n.family.family.bills,
                        resourceType: .bill,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: L10n.family.family.installmentsLoans,
                        resourceType: .installment,
                        resourceID: nil,
                        scope: .edit
                    )
                    sharingToggle(
                        title: L10n.family.family.goals,
                        resourceType: .goal,
                        resourceID: nil,
                        scope: .edit
                    )
                }

                Section(L10n.family.family.createAccess) {
                    sharingToggle(
                        title: L10n.family.family.walletsCards,
                        resourceType: .wallet,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.transactions,
                        resourceType: .transaction,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.createFamilyTransfer,
                        resourceType: .familyTransfer,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.createDebtTransfer,
                        resourceType: .debt,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.categories,
                        resourceType: .category,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.budgets,
                        resourceType: .budget,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.bills,
                        resourceType: .bill,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.installmentsLoans,
                        resourceType: .installment,
                        resourceID: nil,
                        scope: .create
                    )
                    sharingToggle(
                        title: L10n.family.family.goals,
                        resourceType: .goal,
                        resourceID: nil,
                        scope: .create
                    )
                }

                Section(L10n.family.family.walletUseAccess) {
                    if ownWallets.isEmpty {
                        Text(L10n.family.family.youDoNotHaveWalletsToShare2)
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

                Section(L10n.family.family.walletEditAccess) {
                    if ownWallets.isEmpty {
                        Text(L10n.family.family.youDoNotHaveWalletsToShare)
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
            .disabled(!sessionStore.canPerformRemoteActions || ownerUserID == nil || isApplyingSharingChanges)
            .navigationTitle(L10n.family.family.sharing)
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
                    .accessibilityLabel(L10n.family.family.close)
                    .disabled(isApplyingSharingChanges)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        applyStagedSharingChanges()
                    } label: {
                        if isApplyingSharingChanges {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(red: 0.88, green: 0.78, blue: 1.0))
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
                                .frame(width: 30, height: 30)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
                    .disabled(
                        isApplyingSharingChanges
                            || (hasStagedSharingChanges && (!sessionStore.canPerformRemoteActions || ownerUserID == nil))
                    )
                    .accessibilityLabel(L10n.family.family.done)
                }
            }
        }
    }

    @ViewBuilder
    private func planningManagerToggle(
        title: String,
        resourceType: MistiaFamilyNotificationResourceType
    ) -> some View {
        if let family = familyContextStore.family {
            Toggle(
                title,
                isOn: Binding(
                    get: {
                        stagedPlanningManagerUserID(for: resourceType, family: family) == member.userID
                    },
                    set: { isManager in
                        stagePlanningManager(resourceType: resourceType, isManager: isManager, family: family)
                    }
                )
            )
            .tint(MistiaAccent.purple.color)
            .toggleStyle(.switch)
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
            let key = FamilySharingPermissionKey(
                resourceType: resourceType,
                resourceID: resourceID,
                scope: scope
            )
            Toggle(
                title,
                isOn: Binding(
                    get: {
                        stagedPermissionValue(for: key, ownerUserID: ownerUserID)
                    },
                    set: { isGranted in
                        stagedPermissionValues[key] = isGranted
                        sharingErrorMessage = nil
                    }
                )
            )
            .tint(MistiaAccent.purple.color)
            .toggleStyle(.switch)
        }
    }

    private func resolvedPlanningManagerUserID(
        for resourceType: MistiaFamilyNotificationResourceType,
        family: FamilyGroupRecord
    ) -> UUID {
        switch resourceType {
        case .budget:
            return family.budgetManagerUserID ?? family.ownerUserID
        case .goal:
            return family.goalManagerUserID ?? family.ownerUserID
        default:
            return family.ownerUserID
        }
    }

    private func stagedPlanningManagerUserID(
        for resourceType: MistiaFamilyNotificationResourceType,
        family: FamilyGroupRecord
    ) -> UUID {
        stagedPlanningManagerValues[resourceType] ?? resolvedPlanningManagerUserID(for: resourceType, family: family)
    }

    private func stagePlanningManager(
        resourceType: MistiaFamilyNotificationResourceType,
        isManager: Bool,
        family: FamilyGroupRecord
    ) {
        let currentManagerUserID = resolvedPlanningManagerUserID(for: resourceType, family: family)
        guard isManager || currentManagerUserID == member.userID else { return }
        stagedPlanningManagerValues[resourceType] = isManager ? member.userID : family.ownerUserID
        sharingErrorMessage = nil
    }

    private func currentPermissionValue(
        for key: FamilySharingPermissionKey,
        ownerUserID: UUID
    ) -> Bool {
        familyContextStore.hasPermission(
            granteeUserID: member.userID,
            ownerUserID: ownerUserID,
            resourceType: key.resourceType,
            resourceID: key.resourceID,
            scope: key.scope
        )
    }

    private func stagedPermissionValue(
        for key: FamilySharingPermissionKey,
        ownerUserID: UUID
    ) -> Bool {
        stagedPermissionValues[key] ?? currentPermissionValue(for: key, ownerUserID: ownerUserID)
    }

    private var hasStagedSharingChanges: Bool {
        guard let ownerUserID else { return false }
        if stagedPermissionValues.contains(where: { key, isGranted in
            currentPermissionValue(for: key, ownerUserID: ownerUserID) != isGranted
        }) {
            return true
        }

        guard let family = familyContextStore.family else {
            return false
        }

        return stagedPlanningManagerValues.contains { resourceType, managerUserID in
            resolvedPlanningManagerUserID(for: resourceType, family: family) != managerUserID
        }
    }

    private func applyStagedSharingChanges() {
        guard !isApplyingSharingChanges else { return }
        guard hasStagedSharingChanges else {
            dismiss()
            return
        }
        guard sessionStore.canPerformRemoteActions, let ownerUserID else { return }

        let permissionCommits = stagedPermissionValues
            .filter { key, isGranted in
                currentPermissionValue(for: key, ownerUserID: ownerUserID) != isGranted
            }
            .map { key, isGranted in
                FamilySharingPermissionCommit(key: key, isGranted: isGranted)
            }
            .sorted { $0.key.sortKey < $1.key.sortKey }

        let managerCommits: [FamilySharingManagerCommit]
        if let family = familyContextStore.family {
            managerCommits = stagedPlanningManagerValues
                .filter { resourceType, managerUserID in
                    resolvedPlanningManagerUserID(for: resourceType, family: family) != managerUserID
                }
                .map { resourceType, managerUserID in
                    FamilySharingManagerCommit(resourceType: resourceType, managerUserID: managerUserID)
                }
                .sorted { $0.resourceType.rawValue < $1.resourceType.rawValue }
        } else {
            managerCommits = []
        }

        Task { @MainActor in
            isApplyingSharingChanges = true
            sharingErrorMessage = nil
            var didFail = false

            if let family = familyContextStore.family {
                for commit in managerCommits {
                    let managerUserID = commit.managerUserID == family.ownerUserID ? nil : commit.managerUserID
                    let didApply = await familyContextStore.setFamilyPlanningManager(
                        resourceType: commit.resourceType,
                        managerUserID: managerUserID,
                        sessionStore: sessionStore,
                        refreshAfterChange: false
                    )
                    if !didApply {
                        didFail = true
                        break
                    }
                }
            }

            if !didFail {
                for commit in permissionCommits {
                    let didApply = await familyContextStore.setPermissionGrant(
                        granteeUserID: member.userID,
                        ownerUserID: ownerUserID,
                        resourceType: commit.key.resourceType,
                        resourceID: commit.key.resourceID,
                        scope: commit.key.scope,
                        isGranted: commit.isGranted,
                        sessionStore: sessionStore,
                        refreshAfterChange: false
                    )
                    if !didApply {
                        didFail = true
                        break
                    }
                }
            }

            if didFail {
                sharingErrorMessage = familyContextStore.lastErrorMessage ?? sessionStore.remoteUnavailableReason
                isApplyingSharingChanges = false
                return
            }

            await familyContextStore.refresh(sessionStore: sessionStore)
            stagedPermissionValues.removeAll()
            stagedPlanningManagerValues.removeAll()
            isApplyingSharingChanges = false
            dismiss()
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

                Section(L10n.family.family.role) {
                    Picker(L10n.family.family.role, selection: $role) {
                        ForEach([FamilyRole.member, .kid], id: \.self) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(L10n.family.family.permissions) {
                    Toggle(L10n.family.family.viewFamilyDashboard, isOn: $policy.canViewFamilyDashboard)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(L10n.family.family.viewOthers, isOn: $policy.canViewOthers)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(L10n.family.family.editOthers, isOn: $policy.canEditOthers)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(L10n.family.family.viewWallets, isOn: $policy.canViewWallets)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(L10n.family.family.viewDebts, isOn: $policy.canViewDebts)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(L10n.family.family.viewKids, isOn: $policy.canViewKids)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                    Toggle(L10n.family.family.editKids, isOn: $policy.canEditKids)
                        .tint(MistiaAccent.purple.color)
                    .toggleStyle(.switch)
                }

            }
            .disabled(!sessionStore.canPerformRemoteActions)
            .dismissKeyboardOnTap()
            .navigationTitle(L10n.family.family.rolePermissions)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.common.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.common.save) {
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
            L10n.family.family.owner
        case .member:
            L10n.family.family.member
        case .kid:
            L10n.family.family.kid
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
