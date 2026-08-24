import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum InvestmentHubPeriod: String, CaseIterable, Identifiable {
    case month
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: L10n.investment.hub.month
        case .allTime: L10n.investment.hub.allTime
        }
    }
}

private enum InvestmentHubTab: String, CaseIterable, Identifiable {
    case assets
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assets: L10n.investment.hub.assetsTab
        case .activity: L10n.investment.hub.activityTab
        }
    }
}

private enum InvestmentPromotionalAppearance {
    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? MistiaAccent.checkmarkPurple.color : MistiaAccent.purple.color
    }
}

private enum InvestmentHubSheet: Identifiable {
    case channel(UUID?)
    case asset(UUID?)
    case trade(kind: InvestmentTradeKind, id: UUID?)
    case lotHistory(InvestmentAsset)

    var id: String {
        switch self {
        case .channel(let id): "channel-\(id?.uuidString ?? "new")"
        case .asset(let id): "asset-\(id?.uuidString ?? "new")"
        case .trade(let kind, let id): "trade-\(kind.rawValue)-\(id?.uuidString ?? "new")"
        case .lotHistory(let asset): "lotHistory-\(asset.id.uuidString)"
        }
    }
}

private struct InvestmentHubAlert: Identifiable {
    let id: UUID
    let title: String
    let message: String
    let actionTitle: String?
    let actionIsDestructive: Bool
    let action: (() -> Void)?

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        actionTitle: String? = nil,
        actionIsDestructive: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionIsDestructive = actionIsDestructive
        self.action = action
    }
}

private struct InvestmentAssetPositionState {
    let quantity: Decimal
    let costBasisMinor: Int64
    let openLotCount: Int
    let unitPositions: [InvestmentUnitPosition]
}

struct InvestmentHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState: MistiaUIState?
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"

    @Query private var channels: [InvestmentChannel]
    @Query private var assets: [InvestmentAsset]
    @Query private var trades: [InvestmentTrade]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil }) private var wallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var ledgerTransactions: [LedgerTransaction]

    let ownerUserIDOverride: UUID?
    let isModalPresentation: Bool
    let embedsInNavigationStack: Bool

    @State private var viewID = UUID()
    @State private var selectedChannelID: UUID?
    @State private var period: InvestmentHubPeriod = .allTime
    @State private var selectedMonth = Date()
    @State private var selectedTab: InvestmentHubTab = .assets
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var activeSheet: InvestmentHubSheet?
    @State private var showsInvestmentWalletDetail = false
    @State private var activeAlert: InvestmentHubAlert?
    @State private var isRequestingPermission = false

    init(
        ownerUserIDOverride: UUID? = nil,
        isModalPresentation: Bool = false,
        embedsInNavigationStack: Bool = true,
        opensWalletDetailInitially: Bool = false
    ) {
        self.ownerUserIDOverride = ownerUserIDOverride
        self.isModalPresentation = isModalPresentation
        self.embedsInNavigationStack = embedsInNavigationStack
        _showsInvestmentWalletDetail = State(initialValue: opensWalletDetailInitially)
    }

    private var ownerUserID: UUID? {
        ownerUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
            ?? sessionStore.signedInUserID
    }

    private var isOwner: Bool {
        guard let ownerUserID else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || ownerUserID == sessionStore.signedInUserID
    }

    private var canView: Bool {
        isOwner || familyContextStore.canViewInvestment(ownerUserID: ownerUserID)
    }

    private var canCreate: Bool {
        isOwner || familyContextStore.canCreate(ownerUserID: ownerUserID, resourceType: .investment)
    }

    private var canEdit: Bool {
        isOwner || familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .investment)
    }

    private var ownerChannels: [InvestmentChannel] {
        guard let ownerUserID else { return [] }
        return channels
            .filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil && !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
    }

    private var ownerAssets: [InvestmentAsset] {
        guard let ownerUserID else { return [] }
        return assets.filter {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && !$0.isArchived
                && (selectedChannelID == nil || $0.channelID == selectedChannelID)
        }
        .sorted(by: newestAssetFirst)
    }

    private var archivedOwnerChannels: [InvestmentChannel] {
        guard let ownerUserID else { return [] }
        return channels.filter {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && $0.isArchived
        }
    }

    private var archivedOwnerAssets: [InvestmentAsset] {
        guard let ownerUserID else { return [] }
        return assets.filter {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && $0.isArchived
        }
    }

    private var ownerTrades: [InvestmentTrade] {
        guard let ownerUserID else { return [] }
        return trades.filter {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && (selectedChannelID == nil || $0.channelID == selectedChannelID)
        }
    }

    private var systemWallet: LedgerWallet? {
        guard let ownerUserID else { return nil }
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.first { $0.id == id }
    }

    private var systemWalletBalanceMinor: Int64 {
        guard let systemWallet else { return 0 }
        let walletSnapshot = TransactionWalletSnapshot(
            id: systemWallet.id,
            kind: systemWallet.kind,
            openingBalanceMinor: systemWallet.openingBalanceMinor
        )
        return TransactionLogic.walletBalanceIndex(
            wallets: [walletSnapshot],
            records: ledgerTransactions.map(\.snapshot)
        ).balance(for: walletSnapshot)
    }

    private var accountingCurrencyCode: String {
        systemWallet?.currencyCode ?? MistiaCurrencyLogic.normalizedCode(primaryCurrencyCode)
    }

    private var portfolioSummary: InvestmentPortfolioSummary {
        let positionSnapshots = ownerAssets.map { asset in
            let position = position(for: asset)
            return InvestmentAssetPositionSnapshot(
                id: asset.id,
                channelID: asset.channelID,
                quantity: position.quantity,
                remainingCostBasisMinor: position.costBasisMinor,
                openLotCount: position.openLotCount
            )
        }
        let calculations = ownerTrades.map {
            InvestmentTradeCalculation(
                id: $0.id,
                releasedCostBasisMinor: $0.releasedCostBasisMinor,
                realizedProfitLossMinor: $0.realizedProfitLossMinor,
                positionQuantityAfter: $0.positionQuantityAfter,
                positionCostBasisAfterMinor: $0.positionCostBasisAfterMinor,
                openLotCountAfter: 0
            )
        }
        return InvestmentSummaryLogic.summary(
            positions: positionSnapshots,
            trades: calculations,
            tradeDates: Dictionary(uniqueKeysWithValues: ownerTrades.map { ($0.id, $0.occurredAt) }),
            period: selectedDateInterval,
            investmentWalletBalanceMinor: systemWalletBalanceMinor
        )
    }

    private var selectedDateInterval: DateInterval? {
        switch period {
        case .month:
            InvestmentPeriodLogic.monthInterval(
                containing: selectedMonth,
                calendar: calendar
            )
        case .allTime:
            nil
        }
    }

    private var visibleTrades: [InvestmentTrade] {
        ownerTrades.filter { selectedDateInterval?.contains($0.occurredAt) ?? true }
    }

    private var filteredOwnerAssets: [InvestmentAsset] {
        ownerAssets.filter { asset in
            InvestmentAssetSearchLogic.matches(
                productName: asset.name,
                channelName: channelName(for: asset.channelID),
                query: searchText
            )
        }
    }

    private var filteredVisibleTrades: [InvestmentTrade] {
        let searchableTrades = isSearchPresented ? ownerTrades : visibleTrades
        return searchableTrades.filter { trade in
            InvestmentAssetSearchLogic.matches(
                values: [
                    assetName(for: trade.assetID),
                    channelName(for: trade.channelID),
                    trade.note ?? ""
                ],
                query: searchText
            )
        }
    }

    private var searchPrompt: String {
        switch selectedTab {
        case .assets: L10n.investment.hub.searchAssets
        case .activity: L10n.investment.hub.searchActivity
        }
    }

    private var monthSelectionBounds: MistiaMonthSelectionBounds {
        let relevantDates = ownerTrades.map(\.occurredAt) + [Date()]
        return MistiaMonthSelectionBounds(
            minimumMonth: relevantDates.min() ?? selectedMonth,
            maximumMonth: relevantDates.max() ?? selectedMonth,
            calendar: calendar
        )
    }

    var body: some View {
        presentedHub
            .sheet(item: $activeSheet) { sheet in
                sheetView(sheet)
            }
            .alert(item: $activeAlert, content: investmentAlert)
            .onChange(of: ownerChannels.map(\.id)) { oldIDs, ids in
                handleOwnerChannelIDsChanged(oldIDs, ids)
            }
            .onAppear {
                uiState?.requestQuickCreateHidden(true, id: viewID)
            }
            .onDisappear {
                uiState?.requestQuickCreateHidden(false, id: viewID)
            }
            .task(id: ownerUserID) {
                await refreshInvestmentAccessAndData()
            }
    }

    private var presentedHub: some View {
        Group {
            if embedsInNavigationStack {
                NavigationStack { hubNavigationContent }
            } else {
                hubNavigationContent
            }
        }
    }

    private var hubNavigationContent: some View {
        Group {
            if canView {
                hubContent
            } else {
                privateContent
            }
        }
        .navigationTitle(L10n.investment.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            prompt: searchPrompt
        )
        .searchToolbarBehavior(.minimize)
        .toolbar {
            if isModalPresentation {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.common.close)
                }
            }
            if canView {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    managementMenu
                }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            searchText = ""
        }
        .onChange(of: isSearchPresented) { _, presented in
            if !presented {
                searchText = ""
            }
        }
        .navigationDestination(isPresented: $showsInvestmentWalletDetail) {
            if let ownerUserID {
                InvestmentWalletDetailView(ownerUserID: ownerUserID)
            }
        }
    }

    private func investmentAlert(_ alert: InvestmentHubAlert) -> Alert {
        if let actionTitle = alert.actionTitle,
           let action = alert.action {
            let buttonAction: () -> Void = {
                _ = Task { @MainActor in
                    await Task.yield()
                    action()
                }
            }
            let actionButton: Alert.Button = alert.actionIsDestructive
                ? .destructive(Text(actionTitle), action: buttonAction)
                : .default(Text(actionTitle), action: buttonAction)
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: actionButton,
                secondaryButton: .cancel(Text(L10n.common.cancel))
            )
        }
        return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text(L10n.common.ok))
        )
    }

    private func handleOwnerChannelIDsChanged(_ oldIDs: [UUID], _ ids: [UUID]) {
        if let selectedChannelID, !ids.contains(selectedChannelID) {
            self.selectedChannelID = nil
        }
    }

    @ViewBuilder
    private var hubContent: some View {
        if ownerChannels.isEmpty && ownerTrades.isEmpty && ownerAssets.isEmpty {
            ContentUnavailableView {
                Label(L10n.investment.hub.emptyTitle, systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text(L10n.investment.hub.emptyMessage)
            } actions: {
                if canCreate {
                    Button {
                        activeSheet = .channel(nil)
                    } label: {
                        Label(L10n.investment.hub.addChannel, systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MistiaAccent.purple.color)
                    .clipShape(Capsule())
                } else {
                    permissionButton(scope: .create)
                }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !isSearchPresented {
                        summaryCard
                        primaryActions
                    }
                    tabControl
                    switch selectedTab {
                    case .assets:
                        positionsSection
                    case .activity:
                        if !isSearchPresented {
                            periodControl
                        }
                        activitySection
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var privateContent: some View {
        ContentUnavailableView {
            Label(L10n.investment.permission.accessRequired, systemImage: "lock.shield")
        } description: {
            Text(L10n.investment.permission.viewMessage)
        } actions: {
            permissionButton(scope: .view)
        }
    }

    private var periodControl: some View {
        InvestmentPeriodControl(
            period: $period,
            selectedMonth: $selectedMonth,
            calendar: calendar,
            monthSelectionBounds: monthSelectionBounds
        )
    }

    private var summaryCard: some View {
        InvestmentPortfolioSummaryCard(
            summary: portfolioSummary,
            currencyCode: accountingCurrencyCode
        )
    }

    private var primaryActions: some View {
        InvestmentPrimaryActions(
            canBuy: !canCreate || canStartBuyTrade,
            canSell: !canCreate || canStartSellTrade,
            onBuy: { openNewTrade(kind: .buy) },
            onSell: { openNewTrade(kind: .sell) }
        )
    }

    private var tabControl: some View {
        Picker(String(), selection: $selectedTab) {
            ForEach(InvestmentHubTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(L10n.investment.hub.contentMode)
    }

    private var canStartBuyTrade: Bool {
        !ownerAssets.isEmpty
    }

    private var canStartSellTrade: Bool {
        ownerAssets.contains { position(for: $0).quantity > 0 }
    }

    private var managementMenu: some View {
        Menu {
            if canCreate {
                if ownerChannels.isEmpty {
                    Button(L10n.investment.hub.addChannel, systemImage: "square.stack.3d.up.badge.a") {
                        activeSheet = .channel(nil)
                    }
                } else {
                    Button(L10n.investment.hub.addAsset, systemImage: "shippingbox.fill") {
                        activeSheet = .asset(nil)
                    }
                    Button(L10n.investment.hub.addChannel, systemImage: "square.stack.3d.up.badge.a") {
                        activeSheet = .channel(nil)
                    }
                }
            }

            if ownerChannels.count > 1 {
                Menu(L10n.investment.hub.channels, systemImage: "line.3.horizontal.decrease.circle") {
                    Button {
                        selectedChannelID = nil
                    } label: {
                        if selectedChannelID == nil {
                            Label(L10n.investment.hub.allChannels, systemImage: "checkmark")
                        } else {
                            Text(L10n.investment.hub.allChannels)
                        }
                    }
                    ForEach(ownerChannels) { channel in
                        Button {
                            selectedChannelID = channel.id
                        } label: {
                            if selectedChannelID == channel.id {
                                Label(channel.name, systemImage: "checkmark")
                            } else {
                                Text(channel.name)
                            }
                        }
                    }
                }
            }

            if canEdit, !ownerChannels.isEmpty {
                Menu(L10n.management.management.manage, systemImage: "slider.horizontal.3") {
                    ForEach(ownerChannels) { channel in
                        Button(channel.name) { activeSheet = .channel(channel.id) }
                    }
                }
            }

            Button(L10n.investment.hub.walletBalance, systemImage: "wallet.bifold") {
                openInvestmentWallet()
            }

            if canEdit, (!archivedOwnerChannels.isEmpty || !archivedOwnerAssets.isEmpty) {
                Menu(
                    L10n.management.managementarchiveditems.archivedItems,
                    systemImage: "archivebox"
                ) {
                    ForEach(archivedOwnerChannels) { channel in
                        Button(channel.name) { restore(channel) }
                    }
                    ForEach(archivedOwnerAssets) { asset in
                        Button(asset.name) { restore(asset) }
                            .disabled(!ownerChannels.contains { $0.id == asset.channelID })
                    }
                }
            }
        } label: {
            Image(systemName: "briefcase.fill")
        }
        .accessibilityLabel(L10n.management.management.manage)
    }

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.hub.positions)
                .font(.headline)

            if filteredOwnerAssets.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
            }

            ForEach(filteredOwnerAssets) { asset in
                let position = position(for: asset)
                let hasTrades = trades.contains { $0.assetID == asset.id && $0.deletedAt == nil }
                let isSettled = hasTrades && position.quantity <= 0
                let detail = positionDetail(for: position, asset: asset, hasTrades: hasTrades)
                let showsCostBasis = hasTrades && position.quantity > 0
                Button {
                    openAsset(asset)
                } label: {
                    InvestmentPositionRow(
                        imagePath: asset.imagePath,
                        assetName: asset.name,
                        detail: detail,
                        remainingCapitalMinor: position.costBasisMinor,
                        currencyCode: accountingCurrencyCode,
                        isSettled: isSettled,
                        showsCostBasis: showsCostBasis
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        activeSheet = .lotHistory(asset)
                    } label: {
                        Label(L10n.investment.lotHistory.title, systemImage: "clock.arrow.circlepath")
                    }

                    if canEdit {
                        Button {
                            activeSheet = .asset(asset.id)
                        } label: {
                            Label(L10n.management.management.edit, systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            archive(asset)
                        } label: {
                            Label(L10n.common.archive, systemImage: "archivebox")
                        }
                        Button(role: .destructive) {
                            confirmDelete(asset)
                        } label: {
                            Label(L10n.investment.asset.deleteAction, systemImage: "trash")
                        }
                    } else {
                        Button {
                            handlePermissionMenuAction(.edit)
                        } label: {
                            Label(permissionActionTitle(.edit), systemImage: "lock.open")
                        }
                    }
                }
            }
        }
    }

    private func positionDetail(
        for position: InvestmentAssetPositionState,
        asset: InvestmentAsset,
        hasTrades: Bool
    ) -> String {
        guard hasTrades else {
            return L10n.investment.hub.statusNew
        }
        guard position.quantity > 0 else {
            return L10n.investment.hub.outOfStock
        }
        let defaultKey = InvestmentUnitLabel.comparisonKey(asset.defaultUnitLabel)
        let unitDetails = position.unitPositions
            .sorted { lhs, rhs in
                if lhs.unitKey == defaultKey { return true }
                if rhs.unitKey == defaultKey { return false }
                if lhs.unitLabel == nil { return true }
                if rhs.unitLabel == nil { return false }
                return (lhs.unitLabel ?? "").localizedStandardCompare(rhs.unitLabel ?? "") == .orderedAscending
            }
            .map { formattedInvestmentQuantity($0.quantity, unitLabel: $0.unitLabel) }
            .joined(separator: " ・ ")
        let details = unitDetails.isEmpty
            ? formattedInvestmentQuantity(position.quantity, unitLabel: asset.defaultUnitLabel)
            : unitDetails
        return L10n.investment.hub.positionDetails(details)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.hub.activity)
                .font(.headline)
            if filteredVisibleTrades.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.investment.hub.noActivityForPeriod)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(filteredVisibleTrades.sorted(by: newestTradeFirst)) { trade in
                Button {
                    openTrade(trade)
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            InvestmentProductThumbnail(
                                imagePath: assets.first(where: { $0.id == trade.assetID })?.imagePath,
                                size: 44
                            )
                            Image(
                                systemName: trade.kind == .buy
                                    ? (trade.grossAmountMinor == 0 ? "gift.circle.fill" : "arrow.down.circle.fill")
                                    : (trade.grossAmountMinor == 0 ? "minus.circle.fill" : "arrow.up.circle.fill")
                            )
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    trade.kind == .buy
                                        ? (
                                            trade.grossAmountMinor == 0
                                                ? InvestmentPromotionalAppearance.accent(for: colorScheme)
                                                : Color.blue
                                        )
                                        : (trade.grossAmountMinor == 0 ? Color.red : Color.green)
                                )
                                .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetName(for: trade.assetID))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(
                                L10n.investment.hub.activityDetails(
                                    formattedInvestmentQuantity(
                                        trade.quantity,
                                        unitLabel: effectiveUnitLabel(for: trade)
                                    ),
                                    MistiaDateFormatting.fullDateString(for: trade.occurredAt)
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            if trade.kind == .sell && trade.grossAmountMinor == 0 {
                                Text(L10n.investment.trade.totalLossBadge(trade.grossAmountMinor.formattedCurrency(code: trade.currencyCode)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.red)
                            } else if trade.kind == .buy && trade.grossAmountMinor == 0 {
                                Text(L10n.investment.trade.promotionalFreeBadge)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(InvestmentPromotionalAppearance.accent(for: colorScheme))
                            } else {
                                Text(trade.grossAmountMinor.formattedCurrency(code: trade.currencyCode))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            if trade.kind == .sell {
                                Text(trade.realizedProfitLossMinor.formattedCurrency(code: trade.accountingCurrencyCode))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(trade.realizedProfitLossMinor >= 0 ? Color.green : Color.red)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if canEdit {
                        Button {
                            activeSheet = .trade(kind: trade.kind, id: trade.id)
                        } label: {
                            Label(L10n.management.management.edit, systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmDelete(trade)
                        } label: {
                            Label(L10n.investment.trade.deleteAction, systemImage: "trash")
                        }
                    } else {
                        Button {
                            handlePermissionMenuAction(.edit)
                        } label: {
                            Label(permissionActionTitle(.edit), systemImage: "lock.open")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: InvestmentHubSheet) -> some View {
        if let ownerUserID {
            switch sheet {
            case .channel(let channelID):
                InvestmentChannelEditorSheet(
                    ownerUserID: ownerUserID,
                    channel: channels.first { $0.id == channelID },
                    primaryCurrencyCode: primaryCurrencyCode,
                    canEditExisting: canEdit
                ) { showError($0) }
            case .asset(let assetID):
                InvestmentAssetEditorSheet(
                    ownerUserID: ownerUserID,
                    channels: ownerChannels,
                    asset: assets.first { $0.id == assetID },
                    selectedChannelID: selectedChannelID,
                    hasHistory: assetID.map { id in
                        trades.contains { $0.assetID == id }
                    } ?? false,
                    canEditExisting: canEdit
                ) { showError($0) }
            case .trade(let kind, let tradeID):
                InvestmentTradeEditorSheet(
                    ownerUserID: ownerUserID,
                    channels: ownerChannels,
                    assets: assets.filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil && !$0.isArchived },
                    trades: trades.filter { $0.deletedAt == nil },
                    trade: trades.first { $0.id == tradeID },
                    initialKind: kind,
                    wallets: wallets,
                    ledgerTransactions: ledgerTransactions,
                    canUseOrdinaryWallet: canUseOrdinaryWallet,
                    canEditExisting: canEdit,
                    onDelete: { trade in
                        delete(trade)
                    }
                ) { showError($0) }
            case .lotHistory(let asset):
                InvestmentAssetLotHistorySheet(
                    asset: asset,
                    trades: trades.filter { $0.assetID == asset.id && $0.deletedAt == nil },
                    wallets: wallets
                )
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func permissionButton(scope: MistiaFamilyPermissionScope) -> some View {
        Button(permissionActionTitle(scope)) {
            handlePermissionMenuAction(scope)
        }
        .disabled(isRequestingPermission || ownerUserID == nil)
        .buttonStyle(.borderedProminent)
        .tint(MistiaAccent.purple.color)
        .clipShape(Capsule())
    }

    private func permissionTitle(_ scope: MistiaFamilyPermissionScope) -> String {
        switch scope {
        case .view: L10n.investment.permission.requestView
        case .create: L10n.investment.permission.requestCreate
        case .edit: L10n.investment.permission.requestEdit
        case .use: L10n.investment.permission.requestCreate
        }
    }

    private func permissionActionTitle(_ scope: MistiaFamilyPermissionScope) -> String {
        let pending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .investment,
            resourceID: nil,
            scope: scope
        )
        guard pending else { return permissionTitle(scope) }
        switch scope {
        case .view:
            return L10n.investment.permission.requestViewSent
        case .create, .use:
            return L10n.investment.permission.requestCreateSent
        case .edit:
            return L10n.investment.permission.requestEditSent
        }
    }

    private func openAsset(_ asset: InvestmentAsset) {
        guard canEdit else {
            presentPermissionPrompt(scope: .edit) {
                activeSheet = .asset(asset.id)
            }
            return
        }
        activeSheet = .asset(asset.id)
    }

    private func openTrade(_ trade: InvestmentTrade) {
        guard canEdit else {
            presentPermissionPrompt(scope: .edit) {
                activeSheet = .trade(kind: trade.kind, id: trade.id)
            }
            return
        }
        activeSheet = .trade(kind: trade.kind, id: trade.id)
    }

    private func openNewTrade(kind: InvestmentTradeKind) {
        guard canCreate else {
            presentPermissionPrompt(scope: .create) {
                openNewTrade(kind: kind)
            }
            return
        }
        guard kind == .buy ? canStartBuyTrade : canStartSellTrade else { return }
        activeSheet = .trade(kind: kind, id: nil)
    }

    private func openInvestmentWallet() {
        showsInvestmentWalletDetail = true
    }

    private func presentPermissionPrompt(
        scope: MistiaFamilyPermissionScope,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID, !isOwner else { return }
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .investment,
            resourceID: nil,
            scope: scope
        )
        let alertID = UUID()
        activeAlert = InvestmentHubAlert(
            id: alertID,
            title: permissionRequiredTitle(scope),
            message: permissionRequiredMessage(scope),
            actionTitle: permissionActionTitle(scope)
        ) {
            resolvePermissionPromptAction(
                scope: scope,
                wasPending: isPending,
                onGranted: onGranted
            )
        }

        guard isPending else { return }
        Task { @MainActor in
            if await familyContextStore.resolvePendingPermissionBeforePrompt(
                ownerUserID: ownerUserID,
                resourceType: .investment,
                resourceID: nil,
                scope: scope,
                sessionStore: sessionStore
            ) {
                if activeAlert?.id == alertID {
                    activeAlert = nil
                }
                onGranted()
            }
        }
    }

    private func permissionRequiredTitle(_ scope: MistiaFamilyPermissionScope) -> String {
        switch scope {
        case .view:
            return L10n.investment.permission.accessRequired
        case .create, .use:
            return L10n.investment.permission.tradeRequiredTitle
        case .edit:
            return L10n.investment.permission.managementRequiredTitle
        }
    }

    private func permissionRequiredMessage(_ scope: MistiaFamilyPermissionScope) -> String {
        switch scope {
        case .view:
            return L10n.investment.permission.viewMessage
        case .create, .use:
            return L10n.investment.permission.tradeMessage
        case .edit:
            return L10n.investment.permission.managementMessage
        }
    }

    private func resolvePermissionPromptAction(
        scope: MistiaFamilyPermissionScope,
        wasPending: Bool,
        onGranted: @escaping () -> Void
    ) {
        if wasPending {
            refreshPendingPermission(scope: scope, onGranted: onGranted)
        } else {
            requestPermission(scope)
        }
    }

    private func handlePermissionMenuAction(_ scope: MistiaFamilyPermissionScope) {
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .investment,
            resourceID: nil,
            scope: scope
        )
        if isPending {
            refreshPendingPermission(scope: scope)
        } else {
            requestPermission(scope)
        }
    }

    private func refreshPendingPermission(
        scope: MistiaFamilyPermissionScope,
        onGranted: @escaping () -> Void = {}
    ) {
        guard let ownerUserID else { return }
        activeAlert = InvestmentHubAlert(
            title: L10n.investment.permission.requestSentTitle,
            message: L10n.investment.permission.requestPendingMessage
        )
        Task { @MainActor in
            let isApproved = await familyContextStore.refreshPermissionGrant(
                ownerUserID: ownerUserID,
                resourceType: .investment,
                resourceID: nil,
                scope: scope,
                sessionStore: sessionStore
            )
            if isApproved {
                activeAlert = nil
                onGranted()
            }
        }
    }

    private func requestPermission(_ scope: MistiaFamilyPermissionScope) {
        guard let ownerUserID, !isRequestingPermission else { return }
        isRequestingPermission = true
        activeAlert = InvestmentHubAlert(
            title: L10n.shared.family.permissionRequest.sendingTitle,
            message: L10n.shared.family.permissionRequest.sendingMessage
        )
        Task { @MainActor in
            let didRequest = await familyContextStore.requestPermission(
                resourceType: .investment,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: scope,
                resourceName: L10n.investment.title,
                sessionStore: sessionStore
            )
            isRequestingPermission = false
            activeAlert = InvestmentHubAlert(
                title: didRequest
                    ? L10n.investment.permission.requestSentTitle
                    : L10n.investment.permission.sendFailedTitle,
                message: didRequest
                    ? L10n.investment.permission.requestSentMessage
                    : (familyContextStore.lastErrorMessage ?? L10n.investment.permission.sendFailedMessage)
            )
        }
    }

    private func showError(_ message: String) {
        activeAlert = InvestmentHubAlert(
            title: L10n.common.error,
            message: message
        )
    }

    private func confirmDelete(_ trade: InvestmentTrade) {
        activeAlert = InvestmentHubAlert(
            title: L10n.investment.trade.deleteAction,
            message: L10n.investment.trade.deleteConfirmation,
            actionTitle: L10n.common.delete,
            actionIsDestructive: true
        ) {
            _ = delete(trade)
        }
    }

    private func confirmDelete(_ asset: InvestmentAsset) {
        activeAlert = InvestmentHubAlert(
            title: L10n.investment.asset.deleteAction,
            message: L10n.investment.asset.deleteConfirmation,
            actionTitle: L10n.common.delete,
            actionIsDestructive: true
        ) {
            _ = delete(asset)
        }
    }

    private func refreshInvestmentAccessAndData() async {
        guard let ownerUserID, !isOwner else { return }
        let canAccess = await familyContextStore.refreshPermissionGrant(
            ownerUserID: ownerUserID,
            resourceType: .investment,
            resourceID: nil,
            scope: .view,
            sessionStore: sessionStore
        )
        guard canAccess, !Task.isCancelled else { return }

        await familyContextStore.refreshAccessibleFinance(
            sessionStore: sessionStore,
            userIDs: [ownerUserID]
        )
    }

    private func position(for asset: InvestmentAsset) -> InvestmentAssetPositionState {
        let assetTrades = trades
            .filter { $0.assetID == asset.id && $0.deletedAt == nil }
            .sorted(by: oldestTradeFirst)
        guard !assetTrades.isEmpty else {
            return InvestmentAssetPositionState(
                quantity: 0,
                costBasisMinor: 0,
                openLotCount: 0,
                unitPositions: []
            )
        }
        let inputs = assetTrades.map {
            InvestmentTradeInput(
                id: $0.id,
                kind: $0.kind,
                quantity: $0.quantity,
                unitLabel: $0.unitLabel ?? asset.defaultUnitLabel,
                accountingGrossAmountMinor: $0.accountingGrossAmountMinor,
                occurredAt: $0.occurredAt,
                createdAt: $0.createdAt
            )
        }
        guard let calculations = try? InvestmentAccountingEngine.recalculate(trades: inputs),
              let unitPositions = try? InvestmentAccountingEngine.unitPositions(trades: inputs),
              let last = calculations.last else {
            let persisted = assetTrades.last
            return InvestmentAssetPositionState(
                quantity: persisted?.positionQuantityAfter ?? 0,
                costBasisMinor: persisted?.positionCostBasisAfterMinor ?? 0,
                openLotCount: 0,
                unitPositions: []
            )
        }
        return InvestmentAssetPositionState(
            quantity: last.positionQuantityAfter,
            costBasisMinor: last.positionCostBasisAfterMinor,
            openLotCount: last.openLotCountAfter,
            unitPositions: unitPositions
        )
    }

    private func effectiveUnitLabel(for trade: InvestmentTrade) -> String? {
        trade.unitLabel ?? assets.first(where: { $0.id == trade.assetID })?.defaultUnitLabel
    }

    private func assetName(for assetID: UUID) -> String {
        assets.first(where: { $0.id == assetID })?.name ?? L10n.investment.trade.asset
    }

    private func channelName(for channelID: UUID) -> String {
        channels.first(where: { $0.id == channelID })?.name ?? ""
    }

    private func canUseOrdinaryWallet(_ wallet: LedgerWallet) -> Bool {
        guard let ownerUserID else { return false }
        let walletOwnerMap = MistiaRecordOwnershipStore.ownerMap(
            from: ownershipScopes,
            entity: .wallet
        )
        let fallbackOwnerUserID = sessionStore.activeLocalProfileUserID
            ?? sessionStore.signedInUserID
        guard (walletOwnerMap[wallet.id] ?? fallbackOwnerUserID) == ownerUserID else {
            return false
        }
        if isOwner { return true }
        return familyContextStore.canUseWallet(walletID: wallet.id, ownerUserID: ownerUserID)
    }

    private func archive(_ channel: InvestmentChannel) {
        let hasOpenPosition = assets.contains { asset in
            asset.channelID == channel.id
                && asset.deletedAt == nil
                && position(for: asset).quantity > 0
        }
        guard !hasOpenPosition else {
            showError(L10n.investment.error.closePositionsBeforeArchive)
            return
        }
        channel.isArchived = true
        channel.archivedAt = .now
        channel.updatedAt = .now
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .investmentChannel,
                recordID: channel.id,
                modifiedAt: channel.updatedAt,
                subjectUserIDOverride: channel.ownerUserID
            )
        } catch { showError(error.localizedDescription) }
    }

    private func archive(_ asset: InvestmentAsset) {
        guard position(for: asset).quantity <= 0 else {
            showError(L10n.investment.error.closePositionsBeforeArchive)
            return
        }
        asset.isArchived = true
        asset.archivedAt = .now
        asset.updatedAt = .now
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .investmentAsset,
                recordID: asset.id,
                modifiedAt: asset.updatedAt,
                subjectUserIDOverride: asset.ownerUserID
            )
        } catch { showError(error.localizedDescription) }
    }

    private func restore(_ channel: InvestmentChannel) {
        channel.isArchived = false
        channel.archivedAt = nil
        channel.updatedAt = .now
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .investmentChannel,
                recordID: channel.id,
                modifiedAt: channel.updatedAt,
                subjectUserIDOverride: channel.ownerUserID
            )
        } catch { showError(error.localizedDescription) }
    }

    private func restore(_ asset: InvestmentAsset) {
        asset.isArchived = false
        asset.archivedAt = nil
        asset.updatedAt = .now
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .investmentAsset,
                recordID: asset.id,
                modifiedAt: asset.updatedAt,
                subjectUserIDOverride: asset.ownerUserID
            )
        } catch { showError(error.localizedDescription) }
    }

    @discardableResult
    private func delete(_ asset: InvestmentAsset) -> Bool {
        guard let ownerUserID else { return false }
        do {
            let deletedAsset = try InvestmentPersistenceService.deleteAsset(
                ownerUserID: ownerUserID,
                assetID: asset.id,
                context: modelContext
            )
            sessionStore.recordDelete(
                entity: .investmentAsset,
                recordID: deletedAsset.id,
                modifiedAt: deletedAsset.updatedAt,
                subjectUserIDOverride: ownerUserID
            )
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    private func delete(_ trade: InvestmentTrade) -> Bool {
        guard let ownerUserID else { return false }
        do {
            _ = try InvestmentPersistenceService.deleteTrade(
                ownerUserID: ownerUserID,
                tradeID: trade.id,
                context: modelContext
            )
            sessionStore.recordDelete(
                entity: .investmentTrade,
                recordID: trade.id,
                modifiedAt: trade.updatedAt,
                subjectUserIDOverride: ownerUserID
            )
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

}

private struct InvestmentPeriodControl: View {
    @Binding var period: InvestmentHubPeriod
    @Binding var selectedMonth: Date
    let calendar: Calendar
    let monthSelectionBounds: MistiaMonthSelectionBounds

    var body: some View {
        VStack(spacing: 10) {
            Picker(String(), selection: $period) {
                ForEach(InvestmentHubPeriod.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if period == .month {
                MistiaMonthNavigationControl(
                    selection: $selectedMonth,
                    calendar: calendar,
                    accentColor: MistiaAccent.purple.color,
                    bounds: monthSelectionBounds
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: period)
    }
}

private struct InvestmentPortfolioSummaryCard: View {
    let summary: InvestmentPortfolioSummary
    let currencyCode: String

    private var profitColor: Color {
        if summary.realizedProfitLossMinor > 0 { return Color.green }
        if summary.realizedProfitLossMinor < 0 { return Color.red }
        return Color.secondary
    }

    private var profitIcon: String {
        if summary.realizedProfitLossMinor > 0 { return "arrow.up.right.circle.fill" }
        if summary.realizedProfitLossMinor < 0 { return "arrow.down.right.circle.fill" }
        return "minus.circle.fill"
    }

    private var roiPercentageText: String? {
        guard summary.remainingInventoryCostMinor > 0 else { return nil }
        let roi = (Double(summary.realizedProfitLossMinor) / Double(summary.remainingInventoryCostMinor)) * 100
        guard !roi.isNaN && !roi.isInfinite else { return nil }
        return String(format: "%+.1f%%", roi)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Card 1: Vốn đang đầu tư (Căn giữa)
            VStack(alignment: .center, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MistiaAccent.purple.color)

                    Text(L10n.investment.hub.investedCapital)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(summary.remainingInventoryCostMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Card 2: Lợi nhuận (Căn giữa)
            VStack(alignment: .center, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: profitIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(profitColor)

                    Text(L10n.investment.hub.realizedProfitLoss)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(alignment: .center, spacing: 4) {
                    Text(
                        verbatim: (summary.realizedProfitLossMinor > 0 ? "+" : "")
                            + summary.realizedProfitLossMinor.formattedCurrency(code: currencyCode)
                    )
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(profitColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    if let roi = roiPercentageText {
                        Text(roi)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(profitColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(profitColor.opacity(0.12))
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

private struct InvestmentPrimaryActions: View {
    let canBuy: Bool
    let canSell: Bool
    let onBuy: () -> Void
    let onSell: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            action(
                title: L10n.investment.hub.buy,
                systemImage: "arrow.down.circle.fill",
                tint: .blue,
                isEnabled: canBuy,
                action: onBuy
            )
            action(
                title: L10n.investment.hub.sell,
                systemImage: "arrow.up.circle.fill",
                tint: .green,
                isEnabled: canSell,
                action: onSell
            )
        }
    }

    private func action(
        title: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(!isEnabled)
    }
}

private struct InvestmentProductThumbnail: View {
    @Environment(SessionStore.self) private var sessionStore
    let imagePath: String?
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(10, size * 0.22), style: .continuous))
        .task(id: imagePath) {
            image = nil
            guard let imagePath else { return }
            let session = try? await sessionStore.refreshedSession()
            guard let data = try? await InvestmentProductImageRemoteService().jpegData(
                path: imagePath,
                session: session
            ) else { return }
            image = UIImage(data: data)
        }
    }
}

private struct InvestmentPositionRow: View {
    let imagePath: String?
    let assetName: String
    let detail: String
    let remainingCapitalMinor: Int64
    let currencyCode: String
    let isSettled: Bool
    let showsCostBasis: Bool

    var body: some View {
        HStack(spacing: 12) {
            InvestmentProductThumbnail(imagePath: imagePath, size: 44)
                .saturation(isSettled ? 0 : 1)
                .opacity(isSettled ? 0.62 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(assetName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSettled ? Color.secondary : Color.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if showsCostBasis {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.investment.hub.costBasis)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(remainingCapitalMinor.formattedCurrency(code: currencyCode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSettled ? Color.secondary : Color.primary)
                }
            }
        }
        .padding(14)
        .background(
            isSettled
                ? Color.gray.opacity(0.10)
                : Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isSettled {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.gray.opacity(0.28), lineWidth: 1)
            }
        }
    }
}

private func newestAssetFirst(_ lhs: InvestmentAsset, _ rhs: InvestmentAsset) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
    return MistiaStableUUIDOrdering.precedes(lhs.id, rhs.id)
}

private func formattedInvestmentQuantity(_ quantity: Decimal, unitLabel: String?) -> String {
    let quantityText = InvestmentDecimalCoding.string(from: quantity)
    guard let unitLabel = InvestmentUnitLabel.normalizedDisplay(unitLabel) else {
        return quantityText
    }
    return "\(quantityText) \(unitLabel)"
}

private func oldestTradeFirst(_ lhs: InvestmentTrade, _ rhs: InvestmentTrade) -> Bool {
    if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return MistiaStableUUIDOrdering.precedes(lhs.id, rhs.id)
}

private func newestTradeFirst(_ lhs: InvestmentTrade, _ rhs: InvestmentTrade) -> Bool {
    oldestTradeFirst(rhs, lhs)
}

private struct InvestmentChannelEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    let ownerUserID: UUID
    let channel: InvestmentChannel?
    let primaryCurrencyCode: String
    let canEditExisting: Bool
    let onError: (String) -> Void

    @State private var name = ""

    var body: some View {
        MistiaModalScaffold(
            title: L10n.investment.channel.newTitle,
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (channel != nil && !canEditExisting),
            onSave: save
        ) {
            Form {
                TextField(L10n.investment.channel.namePlaceholder, text: $name)
            }
            .onAppear { name = channel?.name ?? "" }
        }
    }

    private func save() {
        do {
            if let channel {
                channel.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                channel.updatedAt = .now
                try modelContext.save()
                sessionStore.recordUpsert(
                    entity: .investmentChannel,
                    recordID: channel.id,
                    modifiedAt: channel.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            } else {
                let result = try InvestmentPersistenceService.createChannel(
                    ownerUserID: ownerUserID,
                    name: name,
                    iconSymbolName: "chart.line.uptrend.xyaxis",
                    iconColorHex: "#9A67FF",
                    primaryCurrencyCode: primaryCurrencyCode,
                    context: modelContext
                )
                sessionStore.recordUpsert(
                    entity: .wallet,
                    recordID: result.wallet.id,
                    modifiedAt: result.wallet.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
                sessionStore.recordUpsert(
                    entity: .investmentChannel,
                    recordID: result.channel.id,
                    modifiedAt: result.channel.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            }
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct InvestmentAssetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    let ownerUserID: UUID
    let channels: [InvestmentChannel]
    let asset: InvestmentAsset?
    let selectedChannelID: UUID?
    let hasHistory: Bool
    let canEditExisting: Bool
    let onError: (String) -> Void

    @State private var channelID: UUID?
    @State private var name = ""
    @State private var currencyCode = "JPY"
    @State private var defaultUnitLabel = ""
    @State private var draftAssetID = UUID()
    @State private var imageSource: InvestmentAssetImageSource?
    @State private var selectedImage: UIImage?
    @State private var removesExistingImage = false

    var body: some View {
        MistiaModalScaffold(
            title: L10n.investment.asset.newTitle,
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            saveDisabled: channelID == nil
                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || InvestmentUnitLabel.normalizedDisplay(defaultUnitLabel) == nil
                || (asset != nil && !canEditExisting),
            onSave: save
        ) {
            Form {
                Picker(L10n.investment.hub.channels, selection: $channelID) {
                    ForEach(channels) { channel in
                        Text(channel.name).tag(Optional(channel.id))
                    }
                }
                .disabled(asset != nil && hasHistory)
                Section {
                    TextField(L10n.investment.asset.namePlaceholder, text: $name)
                    TextField(L10n.investment.asset.defaultUnitPlaceholder, text: $defaultUnitLabel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker(L10n.investment.asset.currency, selection: $currencyCode) {
                        ForEach(MistiaCurrencySettings.enabledCurrencyCodes(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .disabled(asset != nil && hasHistory)
                }
                Section(L10n.investment.asset.imageOptional) {
                    HStack {
                        Spacer()
                        Group {
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                            } else if !removesExistingImage, let imagePath = asset?.imagePath {
                                InvestmentProductThumbnail(imagePath: imagePath, size: 104)
                            } else {
                                ZStack {
                                    Color(uiColor: .tertiarySystemFill)
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Spacer()
                    }
                    if selectedImage != nil || (!removesExistingImage && asset?.imagePath != nil) {
                        Button(L10n.investment.asset.removeImage, role: .destructive) {
                            selectedImage = nil
                            imageSource = nil
                            removesExistingImage = true
                        }
                    } else {
                        Menu {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    imageSource = .camera
                                } label: {
                                    Label(L10n.investment.asset.takePhoto, systemImage: "camera")
                                }
                            }
                            Button {
                                imageSource = .photoLibrary
                            } label: {
                                Label(L10n.investment.asset.choosePhoto, systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Label(L10n.investment.asset.addImage, systemImage: "photo.badge.plus")
                        }
                    }
                }
            }
            .onAppear { hydrate() }
        }
        .sheet(item: $imageSource) { source in
            InvestmentImagePicker(sourceType: source.uiImagePickerSourceType) { image in
                selectedImage = image
                removesExistingImage = false
            }
            .ignoresSafeArea()
        }
    }

    private func hydrate() {
        channelID = asset?.channelID ?? selectedChannelID ?? channels.first?.id
        name = asset?.name ?? ""
        currencyCode = asset?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
        defaultUnitLabel = asset?.defaultUnitLabel ?? ""
        draftAssetID = asset?.id ?? draftAssetID
    }

    private func save() {
        guard let channelID else { return }
        do {
            let targetAssetID = asset?.id ?? draftAssetID
            var imagePath = asset?.imagePath
            if let selectedImage {
                let normalized = try InvestmentProductImageProcessing.normalizedJPEG(selectedImage)
                imagePath = try InvestmentProductImageStore().stageImage(
                    ownerUserID: ownerUserID,
                    assetID: targetAssetID,
                    jpegData: normalized.fullSize,
                    thumbnailData: normalized.thumbnail,
                    replacing: asset?.imagePath
                )
            } else if removesExistingImage {
                try InvestmentProductImageStore().stageRemoval(
                    assetID: targetAssetID,
                    path: asset?.imagePath
                )
                imagePath = nil
            }
            let savedAsset = try InvestmentPersistenceService.saveAsset(
                ownerUserID: ownerUserID,
                draft: InvestmentAssetDraft(
                    id: targetAssetID,
                    channelID: channelID,
                    name: name,
                    currencyCode: currencyCode,
                    imagePath: imagePath,
                    defaultUnitLabel: defaultUnitLabel,
                    createdAt: asset?.createdAt ?? .now
                ),
                context: modelContext
            )
            sessionStore.recordUpsert(
                entity: .investmentAsset,
                recordID: savedAsset.id,
                modifiedAt: savedAsset.updatedAt,
                subjectUserIDOverride: ownerUserID
            )
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct InvestmentAssetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let assets: [InvestmentAsset]
    let channels: [InvestmentChannel]
    @Binding var selection: UUID?
    @State private var searchText = ""

    var body: some View {
        MistiaModalScaffold(
            title: L10n.investment.trade.chooseAsset,
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            onSave: {}
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.investment.trade.searchAsset, text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(L10n.investment.trade.clearSearch)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                List {
                    ForEach(visibleChannels) { channel in
                        Section(channel.name) {
                            ForEach(filteredAssets(in: channel)) { asset in
                                Button {
                                    selection = asset.id
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        InvestmentProductThumbnail(imagePath: asset.imagePath, size: 44)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(asset.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(channel.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selection == asset.id {
                                            Image(systemName: "checkmark")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(MistiaAccent.purple.color)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var visibleChannels: [InvestmentChannel] {
        channels.filter { !filteredAssets(in: $0).isEmpty }
    }

    private func filteredAssets(in channel: InvestmentChannel) -> [InvestmentAsset] {
        return assets
            .filter { asset in
                guard asset.channelID == channel.id else { return false }
                return InvestmentAssetSearchLogic.matches(
                    productName: asset.name,
                    channelName: channel.name,
                    query: searchText
                )
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

}

private enum InvestmentTradeEditorFocusedField: Hashable {
    case unit
}

private struct InvestmentTradeFundUsagePrompt: Identifiable {
    let id = UUID()
    let preview: InvestmentFundUsagePreview
    let currencyCode: String
}

private struct InvestmentTradeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Query private var investmentWalletConfigurations: [InvestmentWalletConfiguration]

    let ownerUserID: UUID
    let channels: [InvestmentChannel]
    let assets: [InvestmentAsset]
    let trades: [InvestmentTrade]
    let trade: InvestmentTrade?
    let initialKind: InvestmentTradeKind
    let wallets: [LedgerWallet]
    let ledgerTransactions: [LedgerTransaction]
    let canUseOrdinaryWallet: (LedgerWallet) -> Bool
    let canEditExisting: Bool
    let onDelete: (InvestmentTrade) -> Bool
    let onError: (String) -> Void

    @State private var kind: InvestmentTradeKind = .buy
    @State private var assetID: UUID?
    @State private var walletID: UUID?
    @State private var quantity = ""
    @State private var unitLabel = ""
    @State private var grossAmount = ""
    @State private var isTotalLoss = false
    @State private var isPromotionalFreeBuy = false
    @State private var note = ""
    @State private var occurredAt = Date()
    @State private var showsAssetPicker = false
    @State private var showsLinkedWalletPicker = false
    @State private var fundUsagePrompt: InvestmentTradeFundUsagePrompt?
    @State private var confirmedFundUsagePreview: InvestmentFundUsagePreview?
    @State private var draftTradeID = UUID()
    @State private var draftCreatedAt = Date()
    @State private var cachedUnitSuggestions: [TransactionTitleSuggestion] = []
    @State private var suppressUnitSuggestions = false
    @State private var isApplyingUnitSuggestion = false
    @State private var unitSuggestionRefreshTask: Task<Void, Never>?
    @FocusState private var focusedField: InvestmentTradeEditorFocusedField?

    private var selectedAsset: InvestmentAsset? { assets.first { $0.id == assetID } }
    private var accountingCurrencyCode: String {
        systemWallet?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
    }
    private var systemWallet: LedgerWallet? {
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.first { $0.id == id }
    }
    private var availableWallets: [LedgerWallet] {
        let systemID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.filter { wallet in
            guard wallet.deletedAt == nil, !wallet.isArchived, wallet.id != systemID else { return false }
            guard canUseOrdinaryWallet(wallet) else { return false }
            return kind == .buy || wallet.kind != .creditCard
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var linkedWalletID: UUID? {
        investmentWalletConfigurations.first { $0.ownerUserID == ownerUserID }?.linkedWalletID
    }
    private var eligibleLinkedWallets: [LedgerWallet] {
        availableWallets.filter {
            $0.kind != .creditCard
                && MistiaCurrencyLogic.normalizedCode($0.currencyCode)
                    == MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        }
    }
    private var availableQuantity: Decimal {
        guard let selectedAsset else { return 0 }
        return availableQuantity(for: selectedAsset, unitLabel: unitLabel)
    }
    private var hasUnresolvedLegacyUnit: Bool {
        InvestmentUnitLabel.normalizedDisplay(selectedAsset?.defaultUnitLabel) == nil
    }
    private var zeroAmountFormatted: String {
        Int64(0).formattedCurrency(code: selectedAsset?.currencyCode ?? "JPY")
    }

    var body: some View {
        MistiaModalScaffold(
            titleView: {
                Picker(String(), selection: $kind) {
                    Text(L10n.investment.hub.buy).tag(InvestmentTradeKind.buy)
                    Text(L10n.investment.hub.sell).tag(InvestmentTradeKind.sell)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(trade != nil)
            },
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            saveDisabled: !canSave,
            onSave: save
        ) {
            Form {
                if kind == .sell, linkedWalletID == nil {
                    Section {
                        Label(L10n.investment.wallet.sellWithoutLinkedWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button(L10n.investment.wallet.setUpNow) {
                            showsLinkedWalletPicker = true
                        }
                    }
                }
                Button {
                    showsAssetPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Text(L10n.investment.trade.asset)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if let selectedAsset {
                            InvestmentProductThumbnail(imagePath: selectedAsset.imagePath, size: 34)
                            Text(selectedAsset.name)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(L10n.investment.trade.chooseAsset)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            TextField(L10n.investment.trade.quantity, text: $quantity)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: .infinity)

                            Divider()

                            TextField(L10n.investment.trade.unit, text: $unitLabel)
                                .focused($focusedField, equals: .unit)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(maxWidth: .infinity)
                                .onChange(of: focusedField) { _, newValue in
                                    if newValue == .unit {
                                        suppressUnitSuggestions = false
                                    }
                                    scheduleUnitSuggestionsRefresh()
                                }
                                .onChange(of: unitLabel) { _, _ in
                                    if isApplyingUnitSuggestion {
                                        isApplyingUnitSuggestion = false
                                        cachedUnitSuggestions = []
                                    } else {
                                        suppressUnitSuggestions = false
                                        scheduleUnitSuggestionsRefresh()
                                    }
                                }
                        }

                        if shouldShowUnitSuggestions {
                            MistiaHistorySuggestionsPanel(
                                suggestions: cachedUnitSuggestions,
                                onApply: applyUnitSuggestion
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: shouldShowUnitSuggestions)

                    if hasUnresolvedLegacyUnit {
                        Text(L10n.investment.trade.resolveUnitBeforeTrading)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if kind == .sell {
                        Text(
                            L10n.investment.trade.availableQuantity(
                                formattedInvestmentQuantity(
                                    availableQuantity,
                                    unitLabel: InvestmentUnitLabel.normalizedDisplay(unitLabel)
                                )
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle(isOn: $isTotalLoss) {
                            Label(L10n.investment.trade.isTotalLoss(zeroAmountFormatted), systemImage: "minus.circle.fill")
                        }
                        .tint(Color.red)
                    }
                    if kind == .buy {
                        Toggle(isOn: $isPromotionalFreeBuy) {
                            HStack(spacing: 8) {
                                Image(systemName: "gift.circle.fill")
                                    .foregroundStyle(InvestmentPromotionalAppearance.accent(for: colorScheme))
                                Text(L10n.investment.trade.isPromotionalFree)
                            }
                        }
                        .tint(InvestmentPromotionalAppearance.accent(for: colorScheme))
                    }
                    if kind == .sell && isTotalLoss {
                        Text(L10n.investment.trade.totalLossDescription(zeroAmountFormatted))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if kind == .buy && isPromotionalFreeBuy {
                        Text(L10n.investment.trade.promotionalFreeDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        MistiaCurrencyInputField(
                            kind == .buy ? L10n.investment.trade.buyTotal : L10n.investment.trade.sellTotal,
                            text: $grossAmount
                        )
                    }
                    MistiaDatePickerRow(
                        title: L10n.investment.trade.time,
                        selection: $occurredAt,
                        mode: .dateAndTime
                    )
                    TextField(L10n.investment.trade.note, text: $note)
                }
                if kind == .sell || !isPromotionalFreeBuy {
                    Section {
                        Picker(walletPickerTitle, selection: $walletID) {
                            ForEach(availableWallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }
                    }
                }
                if let trade, canEditExisting {
                    MistiaDestructiveActionSection(
                        buttonTitle: L10n.investment.trade.deleteAction,
                        descriptionText: L10n.investment.trade.deleteDescription,
                        popupMessage: L10n.investment.trade.deleteConfirmation,
                        confirmationButtonTitle: L10n.common.delete
                    ) {
                        if onDelete(trade) {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showsLinkedWalletPicker) {
                InvestmentLinkedWalletPickerSheet(
                    wallets: eligibleLinkedWallets,
                    selectedWalletID: linkedWalletID,
                    onSelect: { walletID in
                        do {
                            _ = try InvestmentPersistenceService.setLinkedWallet(
                                ownerUserID: ownerUserID,
                                linkedWalletID: walletID,
                                context: modelContext
                            )
                            sessionStore.recordUpsert(
                                entity: .wallet,
                                recordID: InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID),
                                modifiedAt: .now,
                                subjectUserIDOverride: ownerUserID
                            )
                            showsLinkedWalletPicker = false
                        } catch {
                            onError(error.localizedDescription)
                        }
                    }
                )
            }
            .onAppear { hydrate() }
            .onDisappear {
                unitSuggestionRefreshTask?.cancel()
                unitSuggestionRefreshTask = nil
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .buy {
                    isTotalLoss = false
                } else {
                    isPromotionalFreeBuy = false
                }
                if !availableWallets.contains(where: { $0.id == walletID }) {
                    walletID = availableWallets.first?.id
                }
                if newKind == .sell,
                   !selectableAssets.contains(where: { $0.id == assetID }) {
                    assetID = selectableAssets.first?.id
                }
                if trade == nil, let selectedAsset {
                    unitLabel = preferredUnitLabel(for: selectedAsset)
                }
                scheduleUnitSuggestionsRefresh()
            }
            .onChange(of: assetID) { oldValue, newValue in
                guard oldValue != newValue, trade == nil, let selectedAsset else { return }
                unitLabel = preferredUnitLabel(for: selectedAsset)
                scheduleUnitSuggestionsRefresh()
            }
        }
        .sheet(isPresented: $showsAssetPicker) {
            InvestmentAssetPickerSheet(
                assets: selectableAssets,
                channels: channels,
                selection: $assetID
            )
        }
        .alert(
            L10n.investment.wallet.useFundsTitle,
            isPresented: Binding(get: { fundUsagePrompt != nil }, set: { if !$0 { fundUsagePrompt = nil } }),
            presenting: fundUsagePrompt
        ) { prompt in
            Button(L10n.common.cancel, role: .cancel) { }
            Button(L10n.investment.wallet.useFundsAction) {
                confirmedFundUsagePreview = prompt.preview
                fundUsagePrompt = nil
                save()
            }
        } message: { prompt in
            Text(
                L10n.investment.wallet.useFundsMessage(
                    prompt.preview.investmentToUseMinor.formattedCurrency(code: prompt.currencyCode),
                    prompt.preview.remainingInvestmentMinor.formattedCurrency(code: prompt.currencyCode)
                )
            )
        }
    }

    private var canSave: Bool {
        guard assetID != nil, selectedAsset != nil else { return false }
        guard parsedDecimal(quantity) > 0 else { return false }
        guard InvestmentUnitLabel.normalizedDisplay(unitLabel) != nil,
              !hasUnresolvedLegacyUnit else { return false }
        if kind == .sell {
            guard parsedDecimal(quantity) <= availableQuantity else { return false }
            if isTotalLoss {
                return walletID != nil && (trade == nil || canEditExisting)
            }
        }
        if kind == .buy && isPromotionalFreeBuy {
            return trade == nil || canEditExisting
        }
        guard walletID != nil else { return false }
        guard grossAmount.currencyInputToMinorUnits(currencyCode: selectedAsset?.currencyCode ?? "JPY") > 0 else { return false }
        return trade == nil || canEditExisting
    }

    private func hydrate() {
        kind = trade?.kind ?? initialKind
        draftTradeID = trade?.id ?? draftTradeID
        draftCreatedAt = trade?.createdAt ?? draftCreatedAt
        assetID = trade?.assetID
            ?? (kind == .sell ? selectableAssets.first?.id : assets.first?.id)
        walletID = trade.flatMap { $0.kind == .buy ? $0.fundingWalletID : $0.capitalReturnWalletID }
            ?? availableWallets.first?.id
        quantity = trade.map { InvestmentDecimalCoding.string(from: $0.quantity) } ?? ""
        unitLabel = trade.flatMap { InvestmentUnitLabel.normalizedDisplay($0.unitLabel) }
            ?? selectedAsset.map(preferredUnitLabel(for:))
            ?? ""
        if let trade {
            isTotalLoss = trade.kind == .sell && trade.grossAmountMinor == 0
            isPromotionalFreeBuy = trade.kind == .buy && trade.grossAmountMinor == 0
            grossAmount = MistiaCurrencyInputFormatting.groupedInput(String(trade.grossAmountMinor))
            note = trade.note ?? ""
            occurredAt = trade.occurredAt
        } else {
            isTotalLoss = false
            isPromotionalFreeBuy = false
        }
    }

    private var shouldShowUnitSuggestions: Bool {
        focusedField == .unit
            && !suppressUnitSuggestions
            && !cachedUnitSuggestions.isEmpty
    }

    private func scheduleUnitSuggestionsRefresh() {
        unitSuggestionRefreshTask?.cancel()
        unitSuggestionRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            refreshUnitSuggestionsNow()
        }
    }

    private func refreshUnitSuggestionsNow() {
        guard focusedField == .unit,
              !suppressUnitSuggestions,
              InvestmentUnitLabel.normalizedDisplay(unitLabel) != nil else {
            cachedUnitSuggestions = []
            return
        }

        var records = unitHistoryRecords
        if kind == .sell, let selectedAsset {
            let availableKeys = Set(availableUnitPositions(for: selectedAsset).map(\.unitKey))
            records = records.filter {
                availableKeys.contains(InvestmentUnitLabel.comparisonKey($0.value))
            }
        }
        cachedUnitSuggestions = TransactionLogic.textHistorySuggestions(
            from: records,
            query: unitLabel,
            limit: 5
        )
    }

    private var unitHistoryRecords: [MistiaTextHistoryRecord] {
        let ownerAssetsByID = Dictionary(
            uniqueKeysWithValues: assets
                .filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil }
                .map { ($0.id, $0) }
        )
        var records = trades.compactMap { trade -> MistiaTextHistoryRecord? in
            guard trade.ownerUserID == ownerUserID,
                  trade.deletedAt == nil,
                  let asset = ownerAssetsByID[trade.assetID],
                  let label = InvestmentUnitLabel.normalizedDisplay(
                      trade.unitLabel ?? asset.defaultUnitLabel
                  ) else {
                return nil
            }
            return MistiaTextHistoryRecord(
                id: trade.id,
                value: label,
                occurredAt: trade.occurredAt,
                createdAt: trade.createdAt
            )
        }
        records.append(contentsOf: ownerAssetsByID.values.compactMap { asset in
            guard let label = InvestmentUnitLabel.normalizedDisplay(asset.defaultUnitLabel) else {
                return nil
            }
            return MistiaTextHistoryRecord(
                id: asset.id,
                value: label,
                occurredAt: asset.updatedAt,
                createdAt: asset.createdAt
            )
        })
        return records
    }

    private func applyUnitSuggestion(_ suggestion: TransactionTitleSuggestion) {
        isApplyingUnitSuggestion = true
        suppressUnitSuggestions = true
        unitLabel = suggestion.title
    }

    private func preferredUnitLabel(for asset: InvestmentAsset) -> String {
        let positions = availableUnitPositions(for: asset)
        if let defaultLabel = InvestmentUnitLabel.normalizedDisplay(asset.defaultUnitLabel) {
            if kind == .buy
                || positions.contains(where: {
                    $0.unitKey == InvestmentUnitLabel.comparisonKey(defaultLabel)
                }) {
                return defaultLabel
            }
        }
        return positions
            .sorted {
                ($0.unitLabel ?? "").localizedStandardCompare($1.unitLabel ?? "") == .orderedAscending
            }
            .compactMap(\.unitLabel)
            .first ?? ""
    }

    private var selectableAssets: [InvestmentAsset] {
        guard kind == .sell else { return assets }
        return assets.filter { asset in
            !availableUnitPositions(for: asset).isEmpty || asset.id == trade?.assetID
        }
    }

    private func availableQuantity(for asset: InvestmentAsset, unitLabel: String) -> Decimal {
        let key = InvestmentUnitLabel.comparisonKey(unitLabel)
        return availableUnitPositions(for: asset)
            .first(where: { $0.unitKey == key })?
            .quantity ?? 0
    }

    private func availableUnitPositions(for asset: InvestmentAsset) -> [InvestmentUnitPosition] {
        let assetTrades = trades.filter { $0.assetID == asset.id && $0.deletedAt == nil }
        guard !assetTrades.isEmpty else { return [] }
        let eligible = assetTrades.filter { $0.id != trade?.id }
        return (try? InvestmentAccountingEngine.unitPositions(
            trades: eligible.map {
                InvestmentTradeInput(
                    id: $0.id,
                    kind: $0.kind,
                    quantity: $0.quantity,
                    unitLabel: $0.unitLabel ?? asset.defaultUnitLabel,
                    accountingGrossAmountMinor: $0.accountingGrossAmountMinor,
                    occurredAt: $0.occurredAt,
                    createdAt: $0.createdAt
                )
            }
        )) ?? []
    }

    private func save() {
        guard let asset = selectedAsset else { return }
        let isLoss = kind == .sell && isTotalLoss
        let isPromotional = kind == .buy && isPromotionalFreeBuy
        let isZeroAmount = isLoss || isPromotional
        guard isZeroAmount || walletID != nil else { return }

        let currency = asset.currencyCode
        let grossMinor = isZeroAmount ? 0 : grossAmount.currencyInputToMinorUnits(currencyCode: currency)
        let rates = MistiaCurrencySettings.rates()
        let sourceCode = MistiaCurrencyLogic.normalizedCode(currency)
        let accountingCode = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        let preservesExistingCurrencyPair = trade.map {
            MistiaCurrencyLogic.normalizedCode($0.currencyCode) == sourceCode
                && MistiaCurrencyLogic.normalizedCode($0.accountingCurrencyCode) == accountingCode
        } ?? false
        let exchangeRateDecimalString = isZeroAmount ? nil : (preservesExistingCurrencyPair
            ? trade?.exchangeRateDecimalString
            : rateSnapshot(from: currency, to: accountingCurrencyCode, rates: rates))
        let exchangeRateProvider = isZeroAmount ? nil : (preservesExistingCurrencyPair
            ? trade?.exchangeRateProvider
            : rateProvider(from: currency, to: accountingCurrencyCode, rates: rates))
        let exchangeRateDate = isZeroAmount ? nil : (preservesExistingCurrencyPair
            ? trade?.exchangeRateDate
            : rateDate(from: currency, to: accountingCurrencyCode, rates: rates))

        let accountingGross: Int64
        if isZeroAmount {
            accountingGross = 0
        } else if sourceCode == accountingCode {
            accountingGross = grossMinor
        } else {
            guard let exchangeRateDecimalString,
                  let rate = InvestmentDecimalCoding.decimal(from: exchangeRateDecimalString),
                  let converted = try? InvestmentCurrencyConversion.convertedMinor(
                      grossMinor,
                      rate: rate
                  ) else {
                onError(L10n.investment.error.missingExchangeRate)
                return
            }
            accountingGross = converted
        }

        var usagePreview: InvestmentFundUsagePreview?
        if kind == .buy, !isPromotional,
           let fundingWallet = wallets.first(where: { $0.id == walletID }) {
            guard let fundingAmountMinor = MistiaCurrencyLogic.convertedMinorAmount(
                accountingGross,
                from: accountingCurrencyCode,
                to: fundingWallet.currencyCode,
                rates: rates
            ) else {
                onError(L10n.investment.error.missingExchangeRate)
                return
            }
            let excludedIDs = Set([
                trade?.fundingLedgerTransactionID,
                trade?.capitalReturnLedgerTransactionID,
                trade?.profitLossLedgerTransactionID
            ].compactMap { $0 })
            let balance = TransactionLogic.walletBalanceIndex(
                wallets: [
                    TransactionWalletSnapshot(
                        id: fundingWallet.id,
                        kind: fundingWallet.kind,
                        openingBalanceMinor: fundingWallet.openingBalanceMinor
                    )
                ],
                records: ledgerTransactions.filter { !excludedIDs.contains($0.id) }.map(\.snapshot)
            ).balance(
                for: TransactionWalletSnapshot(
                    id: fundingWallet.id,
                    kind: fundingWallet.kind,
                    openingBalanceMinor: fundingWallet.openingBalanceMinor
                )
            )
            do {
                let preview = try InvestmentPersistenceService.fundUsagePreview(
                    ownerUserID: ownerUserID,
                    wallet: fundingWallet,
                    requestedMinor: fundingAmountMinor,
                    visibleWalletBalanceMinor: balance,
                    context: modelContext
                )
                switch preview.outcome {
                case .insufficientFunds:
                    onError(L10n.investment.error.insufficientFunds)
                    return
                case .requiresConfirmation:
                    guard confirmedFundUsagePreview == preview else {
                        confirmedFundUsagePreview = nil
                        fundUsagePrompt = InvestmentTradeFundUsagePrompt(
                            preview: preview,
                            currencyCode: fundingWallet.currencyCode
                        )
                        return
                    }
                    usagePreview = preview
                case .ordinaryFundsOnly:
                    confirmedFundUsagePreview = nil
                }
            } catch {
                onError(error.localizedDescription)
                return
            }
        }

        let effectiveNote: String
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isLoss {
            effectiveNote = L10n.investment.trade.totalLossBadge(grossMinor.formattedCurrency(code: currency))
        } else if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isPromotional {
            effectiveNote = L10n.investment.trade.promotionalFreeBadge
        } else {
            effectiveNote = note
        }

        let savedTradeID = trade?.id ?? UUID()
        let previousFundingLedgerTransactionID = trade?.fundingLedgerTransactionID
        do {
            var persistenceResult = try InvestmentPersistenceService.saveTrade(
                ownerUserID: ownerUserID,
                draft: InvestmentTradeDraft(
                    id: savedTradeID,
                    channelID: asset.channelID,
                    assetID: asset.id,
                    kind: kind,
                    quantity: parsedDecimal(quantity),
                    unitLabel: unitLabel,
                    grossAmountMinor: grossMinor,
                    currencyCode: currency,
                    accountingGrossAmountMinor: accountingGross,
                    accountingCurrencyCode: accountingCurrencyCode,
                    exchangeRateDecimalString: exchangeRateDecimalString,
                    exchangeRateProvider: exchangeRateProvider,
                    exchangeRateDate: exchangeRateDate,
                    fundingWalletID: isPromotional ? nil : (kind == .buy ? walletID : nil),
                    capitalReturnWalletID: kind == .sell ? walletID : nil,
                    note: effectiveNote,
                    occurredAt: occurredAt,
                    createdAt: trade?.createdAt ?? .now
                ),
                rates: rates,
                context: modelContext
            )
            if let savedTrade = try? modelContext.fetch(FetchDescriptor<InvestmentTrade>()).first(where: { $0.id == savedTradeID }) {
                for transactionID in Set([
                    previousFundingLedgerTransactionID,
                    savedTrade.fundingLedgerTransactionID
                ].compactMap { $0 }) {
                    let cleared = try InvestmentPersistenceService.clearFundUsage(
                        ownerUserID: ownerUserID,
                        transactionID: transactionID,
                        context: modelContext
                    )
                    persistenceResult.walletIDs.formUnion(cleared.walletIDs)
                    persistenceResult.postingIDs.formUnion(cleared.postingIDs)
                    persistenceResult.ledgerTransactionIDs.formUnion(cleared.ledgerTransactionIDs)
                }
                if let usagePreview,
                   let transactionID = savedTrade.fundingLedgerTransactionID,
                   let fundingTransaction = try? modelContext.fetch(FetchDescriptor<LedgerTransaction>())
                    .first(where: { $0.id == transactionID }) {
                    let usageResult = try InvestmentPersistenceService.recordFundUsage(
                        ownerUserID: ownerUserID,
                        transaction: fundingTransaction,
                        preview: usagePreview,
                        context: modelContext
                    )
                    persistenceResult.walletIDs.formUnion(usageResult.walletIDs)
                    persistenceResult.postingIDs.formUnion(usageResult.postingIDs)
                    persistenceResult.ledgerTransactionIDs.formUnion(usageResult.ledgerTransactionIDs)
                    try modelContext.save()
                }
                sessionStore.recordUpsert(
                    entity: .investmentTrade,
                    recordID: savedTrade.id,
                    modifiedAt: savedTrade.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
                for transactionID in persistenceResult.ledgerTransactionIDs {
                    sessionStore.recordUpsert(
                        entity: .transaction,
                        recordID: transactionID,
                        modifiedAt: .now,
                        subjectUserIDOverride: ownerUserID
                    )
                }
                let cashPostingIDs = Set(
                    (try? modelContext.fetch(FetchDescriptor<InvestmentCashPostingMetadata>()))?
                        .filter { persistenceResult.postingIDs.contains($0.id) }
                        .map(\.id) ?? []
                )
                for postingID in cashPostingIDs {
                    sessionStore.recordUpsert(
                        entity: .investmentPosting,
                        recordID: postingID,
                        modifiedAt: .now,
                        subjectUserIDOverride: ownerUserID
                    )
                }
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    private var isZeroAmountMode: Bool {
        (kind == .sell && isTotalLoss) || (kind == .buy && isPromotionalFreeBuy)
    }

    private var walletPickerTitle: String {
        if kind == .buy { return L10n.investment.trade.fundingWallet }
        return isTotalLoss ? L10n.investment.trade.lossWallet : L10n.investment.trade.capitalWallet
    }
}

struct InvestmentWalletDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil }) private var wallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var transactions: [LedgerTransaction]
    @Query private var postings: [InvestmentWalletPosting]
    @Query private var cashPostingMetadata: [InvestmentCashPostingMetadata]
    @Query private var configurations: [InvestmentWalletConfiguration]
    @Query private var trades: [InvestmentTrade]
    @Query private var assets: [InvestmentAsset]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let ownerUserID: UUID

    @State private var showsReconciliation = false
    @State private var reconciliationWalletID: UUID?
    @State private var showsLinkedWalletPicker = false
    @State private var pendingLinkedWalletID: UUID?
    @State private var showsLinkChangeOptions = false
    @State private var alertMessage: String?

    private var systemWalletID: UUID {
        InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
    }

    private var systemWallet: LedgerWallet? { wallets.first { $0.id == systemWalletID } }
    private var accountingCurrencyCode: String { systemWallet?.currencyCode ?? "JPY" }
    private var configuration: InvestmentWalletConfiguration? {
        configurations.first { $0.ownerUserID == ownerUserID }
    }
    private var linkedWallet: LedgerWallet? {
        configuration?.linkedWalletID.flatMap { id in wallets.first { $0.id == id } }
    }
    private var isOwner: Bool {
        ownerUserID == sessionStore.activeLocalProfileUserID || ownerUserID == sessionStore.signedInUserID
    }
    private var canEdit: Bool {
        isOwner || familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .investment)
    }
    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }
    private var eligibleWallets: [LedgerWallet] {
        let fallbackOwner = sessionStore.activeLocalProfileUserID ?? sessionStore.signedInUserID
        return wallets.filter { wallet in
            wallet.id != systemWalletID
                && wallet.kind != .creditCard
                && wallet.kind != .investment
                && !wallet.isArchived
                && wallet.deletedAt == nil
                && MistiaCurrencyLogic.normalizedCode(wallet.currencyCode)
                    == MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
                && (walletOwnerMap[wallet.id] ?? fallbackOwner) == ownerUserID
                && canUseWallet(wallet.id)
        }
        .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }
    private func canUseWallet(_ walletID: UUID) -> Bool {
        isOwner || familyContextStore.canUseWallet(walletID: walletID, ownerUserID: ownerUserID)
    }
    private func canReconcile(_ location: InvestmentWalletCashLocation) -> Bool {
        guard canEdit, let linkedWallet else { return false }
        return location.walletID != linkedWallet.id
            && location.bookedMinor > 0
            && canUseWallet(linkedWallet.id)
            && canUseWallet(location.walletID)
    }
    private var cashMetadataByPostingID: [UUID: InvestmentCashPostingMetadata] {
        Dictionary(uniqueKeysWithValues: cashPostingMetadata.map { ($0.id, $0) })
    }
    private var cashSnapshot: InvestmentCashAllocationSnapshot {
        InvestmentCashAllocationLogic.snapshot(
            postings: postings.compactMap { posting in
                guard posting.ownerUserID == ownerUserID,
                      posting.deletedAt == nil,
                      let bucket = cashMetadataByPostingID[posting.id]?.cashBucket else { return nil }
                return InvestmentCashPostingSnapshot(
                    walletID: posting.walletID,
                    currencyCode: posting.currencyCode,
                    amountMinor: posting.amountMinor,
                    accountingAmountMinor: posting.accountingAmountMinor,
                    accountingCurrencyCode: posting.accountingCurrencyCode,
                    bucket: bucket
                )
            },
            accountingCurrencyCode: accountingCurrencyCode
        )
    }
    private var ownerLocations: [InvestmentWalletCashLocation] {
        cashSnapshot.locations.filter { $0.totalMinor > 0 }
    }
    private var ordinaryWalletLocations: [InvestmentWalletCashLocation] {
        guard let linkedWallet else { return ownerLocations }
        return ownerLocations.filter { $0.walletID != linkedWallet.id }
    }
    private var locationsAwaitingTransfer: [InvestmentWalletCashLocation] {
        ordinaryWalletLocations.filter { $0.bookedMinor > 0 }
    }
    private var balanceIndex: TransactionWalletBalanceIndex {
        TransactionLogic.walletBalanceIndex(
            wallets: wallets.map {
                TransactionWalletSnapshot(id: $0.id, kind: $0.kind, openingBalanceMinor: $0.openingBalanceMinor)
            },
            records: transactions.map(\.snapshot)
        )
    }
    private var saleTimelineTrades: [InvestmentTrade] {
        trades.filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil && $0.kind == .sell }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    private var availableProfitMinor: Int64 {
        max(cashSnapshot.totalMinor, 0)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                overviewCard
                linkedWalletCard
                locationsSection
                timelineSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.investment.wallet.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reconciliationWalletID = nil
                    showsReconciliation = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .disabled(
                    linkedWallet == nil
                        || locationsAwaitingTransfer.isEmpty
                        || locationsAwaitingTransfer.contains { !canReconcile($0) }
                )
                .accessibilityLabel(L10n.investment.wallet.reconcile)
            }
        }
        .sheet(isPresented: $showsReconciliation) {
            InvestmentCashReconciliationSheet(
                ownerUserID: ownerUserID,
                initialWalletID: reconciliationWalletID
            ) { alertMessage = $0 }
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showsLinkedWalletPicker) {
            InvestmentLinkedWalletPickerSheet(
                wallets: eligibleWallets,
                selectedWalletID: configuration?.linkedWalletID,
                onSelect: selectLinkedWallet
            )
            .presentationDragIndicator(.hidden)
        }
        .confirmationDialog(
            L10n.investment.wallet.changeChoiceTitle,
            isPresented: $showsLinkChangeOptions,
            titleVisibility: .visible
        ) {
            Button(L10n.investment.wallet.onlyChangeDefault) { applyPendingLink(moveAll: false) }
            Button(L10n.investment.wallet.changeAndTransferAll) { applyPendingLink(moveAll: true) }
            Button(L10n.common.cancel, role: .cancel) { pendingLinkedWalletID = nil }
        } message: {
            Text(L10n.investment.wallet.changeChoiceMessage)
        }
        .alert(
            L10n.common.error,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text(verbatim: alertMessage ?? "")
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.investment.hub.realizedProfitLoss)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(availableProfitMinor.formattedCurrency(code: accountingCurrencyCode))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(availableProfitMinor > 0 ? Color.green : Color.primary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MistiaAccent.purple.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var linkedWalletCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.investment.wallet.linkedWallet).font(.headline)
                Spacer()
                if canEdit, isOwner {
                    Button(linkedWallet == nil ? L10n.investment.wallet.choose : L10n.investment.wallet.change) {
                        showsLinkedWalletPicker = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if let linkedWallet {
                HStack(spacing: 12) {
                    Image(systemName: linkedWallet.iconSymbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: linkedWallet.iconColorHex))
                        .frame(width: 40, height: 40)
                        .background(Color(hex: linkedWallet.iconColorHex).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(linkedWallet.name).font(.subheadline.weight(.semibold))
                        Text(
                            L10n.investment.wallet.appBalance(
                                balanceIndex.balance(
                                    for: TransactionWalletSnapshot(
                                        id: linkedWallet.id,
                                        kind: linkedWallet.kind,
                                        openingBalanceMinor: linkedWallet.openingBalanceMinor
                                    )
                                ).formattedCurrency(code: linkedWallet.currencyCode)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                let heldInvestment = max(
                    cashSnapshot.locations.first { $0.walletID == linkedWallet.id }?.totalMinor ?? 0,
                    0
                )
                Text(L10n.investment.wallet.investmentPortion(heldInvestment.formattedCurrency(code: accountingCurrencyCode)))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MistiaAccent.lightPurple.color)
            } else {
                ContentUnavailableView(
                    L10n.investment.wallet.notSet,
                    systemImage: "link.badge.plus",
                    description: Text(L10n.investment.wallet.notSetMessage)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.wallet.locations).font(.headline)
            if ordinaryWalletLocations.isEmpty {
                Text(L10n.investment.wallet.noLocations)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(ordinaryWalletLocations) { location in
                    Button {
                        guard canReconcile(location) else { return }
                        reconciliationWalletID = location.walletID
                        showsReconciliation = true
                    } label: {
                        locationRow(location)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canReconcile(location))
                }
            }
        }
    }

    private func locationRow(_ location: InvestmentWalletCashLocation) -> some View {
        let wallet = wallets.first { $0.id == location.walletID }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: wallet?.iconSymbolName ?? "questionmark.circle")
                    .foregroundStyle(wallet.map { Color(hex: $0.iconColorHex) } ?? .secondary)
                Text(wallet?.name ?? L10n.investment.wallet.unidentified).font(.subheadline.weight(.semibold))
                Spacer()
                Text(location.totalMinor.formattedCurrency(code: accountingCurrencyCode))
                    .font(.subheadline.weight(.bold))
            }
            Text(L10n.investment.wallet.heldProfit)
            .font(.caption)
            .foregroundStyle(.secondary)
            if MistiaCurrencyLogic.normalizedCode(location.currencyCode)
                != MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode) {
                Text(
                    L10n.investment.wallet.originalAmountReference(
                        location.originalTotalMinor.formattedCurrency(code: location.currencyCode)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.wallet.cashFlow).font(.headline)
            if saleTimelineTrades.isEmpty {
                Text(L10n.investment.wallet.noCashFlow)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(saleTimelineTrades.prefix(40)) { trade in
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            InvestmentProductThumbnail(
                                imagePath: assets.first(where: { $0.id == trade.assetID })?.imagePath,
                                size: 44
                            )
                            Image(systemName: trade.grossAmountMinor == 0 ? "minus.circle.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(trade.grossAmountMinor == 0 ? Color.red : Color.green)
                                .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assets.first { $0.id == trade.assetID }?.name ?? L10n.investment.hub.sell)
                                .font(.subheadline.weight(.semibold))
                            Text(saleDestinationText(for: trade))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(MistiaDateFormatting.fullDateString(for: trade.occurredAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            if trade.grossAmountMinor == 0 {
                                Text(
                                    L10n.investment.trade.totalLossBadge(
                                        trade.grossAmountMinor.formattedCurrency(code: trade.currencyCode)
                                    )
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.red)
                            } else {
                                Text(verbatim: trade.grossAmountMinor.formattedCurrency(code: trade.currencyCode))
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(verbatim: trade.realizedProfitLossMinor.formattedCurrency(code: trade.accountingCurrencyCode))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(trade.realizedProfitLossMinor >= 0 ? Color.green : Color.red)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func saleDestinationText(for trade: InvestmentTrade) -> String {
        if trade.grossAmountMinor == 0 {
            guard let walletID = trade.capitalReturnWalletID,
                  let wallet = wallets.first(where: { $0.id == walletID }) else {
                return L10n.investment.wallet.liquidationWalletUnknown
            }
            return L10n.investment.wallet.liquidationDeductedFrom(wallet.name)
        }
        guard let walletID = trade.capitalReturnWalletID,
              let wallet = wallets.first(where: { $0.id == walletID }) else {
            return L10n.investment.wallet.saleNoDestination
        }
        return L10n.investment.wallet.saleReceivedBy(wallet.name)
    }

    private func selectLinkedWallet(_ walletID: UUID) {
        showsLinkedWalletPicker = false
        if let oldID = configuration?.linkedWalletID, oldID != walletID {
            pendingLinkedWalletID = walletID
            showsLinkChangeOptions = true
        } else {
            pendingLinkedWalletID = walletID
            applyPendingLink(moveAll: false)
        }
    }

    private func applyPendingLink(moveAll: Bool) {
        guard let walletID = pendingLinkedWalletID else { return }
        do {
            let result = try InvestmentPersistenceService.changeLinkedWallet(
                ownerUserID: ownerUserID,
                linkedWalletID: walletID,
                moveAllBookedCash: moveAll,
                context: modelContext
            )
            sessionStore.recordUpsert(
                entity: .wallet,
                recordID: systemWalletID,
                modifiedAt: .now,
                subjectUserIDOverride: ownerUserID
            )
            for transactionID in result.ledgerTransactionIDs {
                sessionStore.recordUpsert(
                    entity: .transaction,
                    recordID: transactionID,
                    modifiedAt: .now,
                    subjectUserIDOverride: ownerUserID
                )
            }
            for postingID in result.postingIDs {
                sessionStore.recordUpsert(
                    entity: .investmentPosting,
                    recordID: postingID,
                    modifiedAt: .now,
                    subjectUserIDOverride: ownerUserID
                )
            }
        } catch {
            alertMessage = error.localizedDescription
        }
        pendingLinkedWalletID = nil
    }
}

private struct InvestmentLinkedWalletPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let wallets: [LedgerWallet]
    let selectedWalletID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(wallets) { wallet in
                        Button {
                            onSelect(wallet.id)
                        } label: {
                            HStack {
                                Label(wallet.name, systemImage: wallet.iconSymbolName)
                                Spacer()
                                if selectedWalletID == wallet.id { Image(systemName: "checkmark") }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(L10n.investment.wallet.chooseLinkedWallet)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.common.cancel) { dismiss() }
                }
            }
        }
    }
}

private struct InvestmentCashReconciliationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil }) private var wallets: [LedgerWallet]
    @Query private var postings: [InvestmentWalletPosting]
    @Query private var cashPostingMetadata: [InvestmentCashPostingMetadata]
    @Query private var configurations: [InvestmentWalletConfiguration]

    let ownerUserID: UUID
    let initialWalletID: UUID?
    let onError: (String) -> Void

    @State private var amountText = ""
    @State private var confirmedRealTransfer = false

    private var systemWalletID: UUID { InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID) }
    private var currencyCode: String { wallets.first { $0.id == systemWalletID }?.currencyCode ?? "JPY" }
    private var linkedWalletID: UUID? { configurations.first { $0.ownerUserID == ownerUserID }?.linkedWalletID }
    private var cashMetadataByPostingID: [UUID: InvestmentCashPostingMetadata] {
        Dictionary(uniqueKeysWithValues: cashPostingMetadata.map { ($0.id, $0) })
    }
    private var snapshot: InvestmentCashAllocationSnapshot {
        InvestmentCashAllocationLogic.snapshot(
            postings: postings.compactMap { posting in
                guard posting.ownerUserID == ownerUserID, posting.deletedAt == nil,
                      let bucket = cashMetadataByPostingID[posting.id]?.cashBucket else { return nil }
                return InvestmentCashPostingSnapshot(
                    walletID: posting.walletID,
                    currencyCode: posting.currencyCode,
                    amountMinor: posting.amountMinor,
                    accountingAmountMinor: posting.accountingAmountMinor,
                    accountingCurrencyCode: posting.accountingCurrencyCode,
                    bucket: bucket
                )
            },
            accountingCurrencyCode: currencyCode
        )
    }
    private var locations: [InvestmentWalletCashLocation] {
        snapshot.locations.filter { $0.walletID != linkedWalletID && $0.bookedMinor > 0 }
    }
    private var selectedLocation: InvestmentWalletCashLocation? {
        initialWalletID.flatMap { id in locations.first { $0.walletID == id } }
    }
    private var requests: [InvestmentReconciliationRequest] {
        if let selectedLocation {
            let entered = amountText.currencyInputToMinorUnits(currencyCode: currencyCode)
            guard entered > 0 else { return [] }
            return [InvestmentReconciliationRequest(walletID: selectedLocation.walletID, accountingAmountMinor: entered)]
        }
        return locations.map {
            InvestmentReconciliationRequest(walletID: $0.walletID, accountingAmountMinor: $0.bookedMinor)
        }
    }

    var body: some View {
        MistiaModalScaffold(
            title: selectedLocation == nil ? L10n.investment.wallet.reconcileAll : L10n.investment.wallet.reconcile,
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            saveDisabled: requests.isEmpty || !confirmedRealTransfer,
            onSave: save
        ) {
            Form {
                Section(L10n.investment.wallet.realTransfers) {
                    ForEach(selectedLocation.map { [$0] } ?? locations) { location in
                        instructionRow(location)
                    }
                }
                if let selectedLocation {
                    Section {
                        MistiaCurrencyInputField(L10n.investment.wallet.amountToReconcile, text: $amountText)
                    } footer: {
                        Text(L10n.investment.wallet.profitAvailable(selectedLocation.bookedMinor.formattedCurrency(code: currencyCode)))
                    }
                }
                Section {
                    Toggle(L10n.investment.wallet.confirmedRealTransfer, isOn: $confirmedRealTransfer)
                } footer: {
                    Text(L10n.investment.wallet.confirmedRealTransferMessage)
                }
            }
            .onAppear {
                if let selectedLocation {
                    amountText = MistiaCurrencyInputFormatting.groupedInput(String(selectedLocation.bookedMinor))
                }
            }
        }
    }

    private func instructionRow(_ location: InvestmentWalletCashLocation) -> some View {
        let holder = wallets.first { $0.id == location.walletID }?.name ?? L10n.investment.wallet.unidentified
        let linked = wallets.first { $0.id == linkedWalletID }?.name ?? L10n.investment.wallet.linkedWallet
        let transferAmount = selectedLocation?.walletID == location.walletID
            ? amountText.currencyInputToMinorUnits(currencyCode: currencyCode)
            : location.bookedMinor
        return VStack(alignment: .leading, spacing: 5) {
            Text(L10n.investment.wallet.realTransferInstruction(holder, linked))
                .font(.subheadline.weight(.medium))
            Text(transferAmount.formattedCurrency(code: currencyCode))
                .font(.headline)
                .foregroundStyle(MistiaAccent.purple.color)
        }
    }

    private func save() {
        do {
            let result = try InvestmentPersistenceService.reconcileCash(
                ownerUserID: ownerUserID,
                requests: requests,
                context: modelContext
            )
            for transactionID in result.persistence.ledgerTransactionIDs {
                sessionStore.recordUpsert(
                    entity: .transaction,
                    recordID: transactionID,
                    modifiedAt: .now,
                    subjectUserIDOverride: ownerUserID
                )
            }
            for postingID in result.persistence.postingIDs {
                sessionStore.recordUpsert(
                    entity: .investmentPosting,
                    recordID: postingID,
                    modifiedAt: .now,
                    subjectUserIDOverride: ownerUserID
                )
            }
            dismiss()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private enum InvestmentProductImageProcessing {
    struct Result {
        let fullSize: Data
        let thumbnail: Data
    }

    static func normalizedJPEG(_ image: UIImage) throws -> Result {
        let fullImage = resized(image, maximumLongEdge: 1_600)
        var quality: CGFloat = 0.9
        var fullData = fullImage.jpegData(compressionQuality: quality)
        while (fullData?.count ?? .max) > 4_000_000, quality > 0.25 {
            quality -= 0.1
            fullData = fullImage.jpegData(compressionQuality: quality)
        }
        guard let fullData, fullData.count <= 4_000_000 else {
            throw InvestmentProductImageError.imageTooLarge
        }
        let thumbnailImage = resized(image, maximumLongEdge: 240)
        guard let thumbnail = thumbnailImage.jpegData(compressionQuality: 0.78) else {
            throw InvestmentProductImageError.imageTooLarge
        }
        return Result(fullSize: fullData, thumbnail: thumbnail)
    }

    private static func resized(_ image: UIImage, maximumLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maximumLongEdge ? maximumLongEdge / longEdge : 1
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private enum InvestmentProductImageError: LocalizedError {
    case imageTooLarge

    var errorDescription: String? {
        L10n.investment.error.imageTooLarge
    }
}

private enum InvestmentAssetImageSource: String, Identifiable {
    case camera
    case photoLibrary

    var id: String { rawValue }

    var uiImagePickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            .camera
        case .photoLibrary:
            .photoLibrary
        }
    }
}

private struct InvestmentImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: InvestmentImagePicker

        init(parent: InvestmentImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private func parsedDecimal(_ text: String) -> Decimal {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

private func matchingRate(from source: String, to target: String, rates: [MistiaExchangeRate]) -> (rate: MistiaExchangeRate, isInverse: Bool)? {
    let source = MistiaCurrencyLogic.normalizedCode(source)
    let target = MistiaCurrencyLogic.normalizedCode(target)
    guard source != target else { return nil }
    if let rate = rates.first(where: {
        MistiaCurrencyLogic.normalizedCode($0.baseCurrencyCode) == source
            && MistiaCurrencyLogic.normalizedCode($0.quoteCurrencyCode) == target
    }) { return (rate, false) }
    if let rate = rates.first(where: {
        MistiaCurrencyLogic.normalizedCode($0.baseCurrencyCode) == target
            && MistiaCurrencyLogic.normalizedCode($0.quoteCurrencyCode) == source
    }) { return (rate, true) }
    return nil
}

private func rateSnapshot(from source: String, to target: String, rates: [MistiaExchangeRate]) -> String? {
    let source = MistiaCurrencyLogic.normalizedCode(source)
    let target = MistiaCurrencyLogic.normalizedCode(target)
    guard source != target, let match = matchingRate(from: source, to: target, rates: rates) else { return nil }
    if !match.isInverse { return match.rate.rateDecimalString }
    guard let decimal = match.rate.rateDecimal, decimal != 0 else { return nil }
    return InvestmentDecimalCoding.string(from: 1 / decimal)
}

private func rateProvider(from source: String, to target: String, rates: [MistiaExchangeRate]) -> String? {
    matchingRate(from: source, to: target, rates: rates)?.rate.provider
}

private func rateDate(from source: String, to target: String, rates: [MistiaExchangeRate]) -> String? {
    matchingRate(from: source, to: target, rates: rates)?.rate.rateDate
}

private struct InvestmentLotItem: Identifiable {
    let id: UUID
    let occurredAt: Date
    let initialQuantity: Decimal
    var remainingQuantity: Decimal
    let unitLabel: String?
    let unitKey: String
    let grossAmountMinor: Int64
    var remainingCostBasisMinor: Int64
    let currencyCode: String
    let fundingWalletName: String?
    let note: String?

    var unitPriceMinor: Int64 {
        guard initialQuantity > 0 else { return 0 }
        let grossDec = Decimal(grossAmountMinor)
        var unitDec = grossDec / initialQuantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &unitDec, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    enum Status {
        case open
        case partiallySold
        case closed
    }

    var status: Status {
        if remainingQuantity <= 0 {
            return .closed
        } else if remainingQuantity < initialQuantity {
            return .partiallySold
        } else {
            return .open
        }
    }
}

private struct InvestmentAssetLotHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let asset: InvestmentAsset
    let trades: [InvestmentTrade]
    let wallets: [LedgerWallet]

    @State private var filterMode: FilterMode = .openOnly

    private enum FilterMode: String, CaseIterable, Identifiable {
        case openOnly
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openOnly: L10n.investment.lotHistory.openLotsOnly
            case .all: L10n.investment.lotHistory.allLots
            }
        }
    }

    private var allLots: [InvestmentLotItem] {
        let sortedTrades = trades.sorted(by: oldestTradeFirst)
        var lots: [InvestmentLotItem] = []

        for trade in sortedTrades {
            let effectiveUnitLabel = trade.unitLabel ?? asset.defaultUnitLabel
            if trade.kind == .buy {
                let walletName = trade.fundingWalletID.flatMap { wID in
                    wallets.first(where: { $0.id == wID })?.name
                }
                lots.append(
                    InvestmentLotItem(
                        id: trade.id,
                        occurredAt: trade.occurredAt,
                        initialQuantity: trade.quantity,
                        remainingQuantity: trade.quantity,
                        unitLabel: effectiveUnitLabel,
                        unitKey: InvestmentUnitLabel.comparisonKey(effectiveUnitLabel),
                        grossAmountMinor: trade.grossAmountMinor,
                        remainingCostBasisMinor: trade.grossAmountMinor,
                        currencyCode: trade.currencyCode,
                        fundingWalletName: walletName,
                        note: trade.note
                    )
                )
            } else if trade.kind == .sell {
                var quantityToDeduct = trade.quantity
                let saleUnitKey = InvestmentUnitLabel.comparisonKey(effectiveUnitLabel)
                for index in 0..<lots.count {
                    guard quantityToDeduct > 0 else { break }
                    if lots[index].remainingQuantity > 0,
                       lots[index].unitKey == saleUnitKey {
                        let deduct = min(quantityToDeduct, lots[index].remainingQuantity)
                        let costDeducted: Int64
                        if deduct == lots[index].remainingQuantity {
                            costDeducted = lots[index].remainingCostBasisMinor
                        } else if lots[index].initialQuantity > 0 {
                            var proportional = Decimal(lots[index].grossAmountMinor) * deduct / lots[index].initialQuantity
                            var rounded = Decimal()
                            NSDecimalRound(&rounded, &proportional, 0, .plain)
                            costDeducted = NSDecimalNumber(decimal: rounded).int64Value
                        } else {
                            costDeducted = 0
                        }

                        lots[index].remainingQuantity -= deduct
                        lots[index].remainingCostBasisMinor = max(0, lots[index].remainingCostBasisMinor - costDeducted)
                        quantityToDeduct -= deduct
                    }
                }
            }
        }

        return lots.reversed()
    }

    private var visibleLots: [InvestmentLotItem] {
        switch filterMode {
        case .openOnly:
            return allLots.filter { $0.remainingQuantity > 0 }
        case .all:
            return allLots
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(String(), selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if visibleLots.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.investment.lotHistory.empty, systemImage: "tray")
                    }
                } else {
                    List {
                        ForEach(visibleLots) { lot in
                            lotRow(lot)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(asset.name)
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
            }
        }
    }

    @ViewBuilder
    private func lotRow(_ lot: InvestmentLotItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(MistiaDateFormatting.dateTimeString(for: lot.occurredAt))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                statusBadge(lot.status)
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.investment.lotHistory.unitPrice)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(lot.unitPriceMinor.formattedCurrency(code: lot.currencyCode))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.investment.lotHistory.initialCost)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(lot.grossAmountMinor.formattedCurrency(code: lot.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.investment.lotHistory.remainingQuantity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(
                        verbatim: "\(formattedInvestmentQuantity(lot.remainingQuantity, unitLabel: lot.unitLabel)) / \(formattedInvestmentQuantity(lot.initialQuantity, unitLabel: lot.unitLabel))"
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(lot.remainingQuantity > 0 ? Color.primary : Color.secondary)
                }

                if let walletName = lot.fundingWalletName, !walletName.isEmpty {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.investment.trade.fundingWallet)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(walletName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let note = lot.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func statusBadge(_ status: InvestmentLotItem.Status) -> some View {
        switch status {
        case .open:
            Text(L10n.investment.lotHistory.statusOpen)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
        case .partiallySold:
            Text(L10n.investment.lotHistory.statusPartial)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        case .closed:
            Text(L10n.investment.lotHistory.statusClosed)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}
