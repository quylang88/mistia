import Charts
import SwiftData
import SwiftUI

private enum InvestmentHubPeriod: String, CaseIterable, Identifiable {
    case day
    case month
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: L10n.investment.hub.day
        case .month: L10n.investment.hub.month
        case .allTime: L10n.investment.hub.allTime
        }
    }
}

private enum InvestmentHubSheet: Identifiable {
    case channel(UUID?)
    case asset(UUID?)
    case trade(kind: InvestmentTradeKind, id: UUID?)
    case valuation(assetID: UUID, id: UUID?)
    case wallet

    var id: String {
        switch self {
        case .channel(let id): "channel-\(id?.uuidString ?? "new")"
        case .asset(let id): "asset-\(id?.uuidString ?? "new")"
        case .trade(let kind, let id): "trade-\(kind.rawValue)-\(id?.uuidString ?? "new")"
        case .valuation(let assetID, let id): "valuation-\(assetID.uuidString)-\(id?.uuidString ?? "new")"
        case .wallet: "wallet"
        }
    }
}

struct InvestmentHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState: MistiaUIState?
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"

    @Query private var channels: [InvestmentChannel]
    @Query private var assets: [InvestmentAsset]
    @Query private var trades: [InvestmentTrade]
    @Query private var valuations: [InvestmentValuation]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil }) private var wallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var ledgerTransactions: [LedgerTransaction]

    let ownerUserIDOverride: UUID?
    let isModalPresentation: Bool

    @State private var viewID = UUID()
    @State private var selectedChannelID: UUID?
    @State private var period: InvestmentHubPeriod = .month
    @State private var activeSheet: InvestmentHubSheet?
    @State private var errorMessage: String?
    @State private var isRequestingPermission = false

    init(ownerUserIDOverride: UUID? = nil, isModalPresentation: Bool = false) {
        self.ownerUserIDOverride = ownerUserIDOverride
        self.isModalPresentation = isModalPresentation
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
                marketValueMinor: latestValuation(for: asset)?.accountingMarketValueMinor
            )
        }
        let calculations = ownerTrades.map {
            InvestmentTradeCalculation(
                id: $0.id,
                releasedCostBasisMinor: $0.releasedCostBasisMinor,
                realizedProfitLossMinor: $0.realizedProfitLossMinor,
                positionQuantityAfter: $0.positionQuantityAfter,
                positionCostBasisAfterMinor: $0.positionCostBasisAfterMinor
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
        let now = Date()
        switch period {
        case .day:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? now)
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start) ?? now)
        case .allTime:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if canView {
                    hubContent
                } else {
                    privateContent
                }
            }
            .navigationTitle(L10n.investment.title)
            .navigationBarTitleDisplayMode(.inline)
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
                if canView, canCreate {
                    ToolbarItem(placement: .topBarTrailing) {
                        createMenu
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
        }
        .alert(L10n.common.error, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.common.ok) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? L10n.common.unknownError)
        }
        .onChange(of: ownerChannels.map(\.id)) { _, ids in
            if let selectedChannelID, !ids.contains(selectedChannelID) {
                self.selectedChannelID = nil
            }
        }
        .onAppear {
            uiState?.requestQuickCreateHidden(true, id: viewID)
        }
        .onDisappear {
            uiState?.requestQuickCreateHidden(false, id: viewID)
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
                    channelPicker
                    periodPicker
                    summaryGrid
                    realizedChart
                    positionsSection
                    activitySection
                    archivedSection
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

    private var channelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                channelChip(
                    title: L10n.investment.hub.allChannels,
                    systemImage: "square.grid.2x2",
                    channelID: nil
                )
                ForEach(ownerChannels) { channel in
                    channelChip(
                        title: channel.name,
                        systemImage: channel.iconSymbolName,
                        channelID: channel.id
                    )
                    .contextMenu {
                        if canEdit {
                            Button(L10n.management.management.edit) {
                                activeSheet = .channel(channel.id)
                            }
                            Button(L10n.common.archive, role: .destructive) {
                                archive(channel)
                            }
                        } else {
                            Button(L10n.investment.permission.requestEdit) {
                                requestPermission(.edit)
                            }
                        }
                    }
                }
            }
        }
    }

    private func channelChip(title: String, systemImage: String, channelID: UUID?) -> some View {
        let isSelected = selectedChannelID == channelID
        return Button {
            withAnimation(.snappy) { selectedChannelID = channelID }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? MistiaAccent.purple.color : Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var periodPicker: some View {
        Picker(L10n.investment.hub.realizedProfitLoss, selection: $period) {
            ForEach(InvestmentHubPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            InvestmentMetricCard(
                title: L10n.investment.hub.investedCapital,
                value: portfolioSummary.investedCapitalMinor.formattedCurrency(code: accountingCurrencyCode),
                tint: .blue
            )
            InvestmentMetricCard(
                title: L10n.investment.hub.marketValue,
                value: portfolioSummary.marketValueMinor.formattedCurrency(code: accountingCurrencyCode),
                tint: .indigo
            )
            InvestmentMetricCard(
                title: L10n.investment.hub.realizedProfitLoss,
                value: portfolioSummary.realizedProfitLossMinor.formattedCurrency(code: accountingCurrencyCode),
                tint: portfolioSummary.realizedProfitLossMinor >= 0 ? .green : .red
            )
            InvestmentMetricCard(
                title: L10n.investment.hub.unrealizedProfitLoss,
                value: portfolioSummary.unrealizedProfitLossMinor.formattedCurrency(code: accountingCurrencyCode),
                tint: portfolioSummary.unrealizedProfitLossMinor >= 0 ? .green : .red
            )
            Button {
                activeSheet = .wallet
            } label: {
                InvestmentMetricCard(
                    title: L10n.investment.hub.walletBalance,
                    value: systemWalletBalanceMinor.formattedCurrency(code: accountingCurrencyCode),
                    tint: systemWalletBalanceMinor >= 0 ? .purple : .red
                )
            }
            .buttonStyle(.plain)
            .gridCellColumns(2)
        }
    }

    @ViewBuilder
    private var realizedChart: some View {
        let points = chartPoints
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.investment.hub.realizedProfitLoss)
                    .font(.headline)
                Chart(points) { point in
                    BarMark(
                        x: .value(L10n.investment.trade.date, point.date, unit: chartUnit),
                        y: .value(L10n.investment.hub.realizedProfitLoss, point.amountMinor)
                    )
                    .foregroundStyle(point.amountMinor >= 0 ? Color.green.gradient : Color.red.gradient)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 170)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.investment.hub.positions)
                    .font(.headline)
                Spacer()
                if canCreate {
                    Button(L10n.investment.hub.addAsset) { activeSheet = .asset(nil) }
                        .font(.subheadline.weight(.semibold))
                }
            }

            ForEach(ownerAssets) { asset in
                let position = position(for: asset)
                let marketValue = latestValuation(for: asset)?.accountingMarketValueMinor
                    ?? position.costBasisMinor
                Button {
                    if canCreate { activeSheet = .valuation(assetID: asset.id, id: nil) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(MistiaAccent.purple.color)
                            .frame(width: 34, height: 34)
                            .background(MistiaAccent.purple.color.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(InvestmentDecimalCoding.string(from: position.quantity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(marketValue.formattedCurrency(code: accountingCurrencyCode))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(position.costBasisMinor.formattedCurrency(code: accountingCurrencyCode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if canEdit {
                        Button(L10n.management.management.edit) { activeSheet = .asset(asset.id) }
                        if let valuation = latestValuation(for: asset) {
                            Button(L10n.investment.valuation.title) {
                                activeSheet = .valuation(assetID: asset.id, id: valuation.id)
                            }
                            Button(L10n.common.delete, role: .destructive) {
                                delete(valuation)
                            }
                        }
                        Button(L10n.common.archive, role: .destructive) { archive(asset) }
                    } else {
                        Button(L10n.investment.permission.requestEdit) { requestPermission(.edit) }
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.hub.activity)
                .font(.headline)
            ForEach(ownerTrades.sorted(by: newestTradeFirst)) { trade in
                Button {
                    if canEdit { activeSheet = .trade(kind: trade.kind, id: trade.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: trade.kind == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(trade.kind == .buy ? Color.blue : Color.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetName(for: trade.assetID))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(trade.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(trade.grossAmountMinor.formattedCurrency(code: trade.currencyCode))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
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
                        Button(L10n.common.delete, role: .destructive) { delete(trade) }
                    } else {
                        Button(L10n.investment.permission.requestEdit) { requestPermission(.edit) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if canEdit, !archivedOwnerChannels.isEmpty || !archivedOwnerAssets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.management.managementarchiveditems.archivedItems)
                    .font(.headline)
                ForEach(archivedOwnerChannels) { channel in
                    archivedRow(name: channel.name, systemImage: channel.iconSymbolName) {
                        restore(channel)
                    }
                }
                ForEach(archivedOwnerAssets) { asset in
                    let channelIsActive = ownerChannels.contains { $0.id == asset.channelID }
                    archivedRow(name: asset.name, systemImage: "shippingbox.fill") {
                        restore(asset)
                    }
                    .disabled(!channelIsActive)
                }
            }
        }
    }

    private func archivedRow(
        name: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(name, systemImage: systemImage)
                Spacer()
                Text(L10n.management.managementarchiveditems.restore)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var createMenu: some View {
        Menu {
            Button(L10n.investment.hub.addChannel, systemImage: "square.stack.3d.up.badge.a") {
                activeSheet = .channel(nil)
            }
            Button(L10n.investment.hub.addAsset, systemImage: "shippingbox") {
                activeSheet = .asset(nil)
            }
            .disabled(ownerChannels.isEmpty)
            Button(L10n.investment.hub.buy, systemImage: "arrow.down.circle") {
                activeSheet = .trade(kind: .buy, id: nil)
            }
            .disabled(ownerAssets.isEmpty)
            Button(L10n.investment.hub.sell, systemImage: "arrow.up.circle") {
                activeSheet = .trade(kind: .sell, id: nil)
            }
            .disabled(ownerAssets.allSatisfy { position(for: $0).quantity <= 0 })
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(L10n.investment.hub.addChannel)
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
                ) { errorMessage = $0 }
            case .asset(let assetID):
                InvestmentAssetEditorSheet(
                    ownerUserID: ownerUserID,
                    channels: ownerChannels,
                    asset: assets.first { $0.id == assetID },
                    selectedChannelID: selectedChannelID,
                    hasHistory: assetID.map { id in
                        trades.contains { $0.assetID == id }
                            || valuations.contains { $0.assetID == id }
                    } ?? false,
                    canEditExisting: canEdit
                ) { errorMessage = $0 }
            case .trade(let kind, let tradeID):
                InvestmentTradeEditorSheet(
                    ownerUserID: ownerUserID,
                    assets: ownerAssets.isEmpty ? assets.filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil && !$0.isArchived } : ownerAssets,
                    trade: trades.first { $0.id == tradeID },
                    initialKind: kind,
                    wallets: wallets,
                    ledgerTransactions: ledgerTransactions,
                    canUseOrdinaryWallet: canUseOrdinaryWallet,
                    canEditExisting: canEdit
                ) { errorMessage = $0 }
            case .valuation(let assetID, let valuationID):
                if let asset = assets.first(where: { $0.id == assetID }) {
                    InvestmentValuationEditorSheet(
                        ownerUserID: ownerUserID,
                        asset: asset,
                        valuation: valuations.first { $0.id == valuationID },
                        canEditExisting: canEdit
                    ) {
                        errorMessage = $0
                    }
                }
            case .wallet:
                InvestmentWalletDetailView(ownerUserID: ownerUserID)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func permissionButton(scope: MistiaFamilyPermissionScope) -> some View {
        let pending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .investment,
            resourceID: nil,
            scope: scope
        )
        Button(pending ? L10n.investment.permission.pending : permissionTitle(scope)) {
            requestPermission(scope)
        }
        .disabled(pending || isRequestingPermission || ownerUserID == nil)
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

    private func requestPermission(_ scope: MistiaFamilyPermissionScope) {
        guard let ownerUserID, !isRequestingPermission else { return }
        isRequestingPermission = true
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
            if !didRequest {
                errorMessage = familyContextStore.lastErrorMessage ?? L10n.common.unknownError
            }
        }
    }

    private func position(for asset: InvestmentAsset) -> (quantity: Decimal, costBasisMinor: Int64) {
        let assetTrades = trades
            .filter { $0.assetID == asset.id && $0.deletedAt == nil }
            .sorted(by: oldestTradeFirst)
        guard let last = assetTrades.last else {
            return (asset.openingQuantity, asset.openingCostMinor)
        }
        return (last.positionQuantityAfter, last.positionCostBasisAfterMinor)
    }

    private func latestValuation(for asset: InvestmentAsset) -> InvestmentValuation? {
        valuations
            .filter { $0.assetID == asset.id && $0.deletedAt == nil }
            .max { lhs, rhs in
                if lhs.valuedAt != rhs.valuedAt { return lhs.valuedAt < rhs.valuedAt }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func assetName(for assetID: UUID) -> String {
        assets.first(where: { $0.id == assetID })?.name ?? L10n.investment.trade.asset
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
            errorMessage = L10n.investment.error.closePositionsBeforeArchive
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
        } catch { errorMessage = error.localizedDescription }
    }

    private func archive(_ asset: InvestmentAsset) {
        guard position(for: asset).quantity <= 0 else {
            errorMessage = L10n.investment.error.closePositionsBeforeArchive
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
        } catch { errorMessage = error.localizedDescription }
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
        } catch { errorMessage = error.localizedDescription }
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
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ trade: InvestmentTrade) {
        guard let ownerUserID else { return }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ valuation: InvestmentValuation) {
        valuation.deletedAt = .now
        valuation.updatedAt = .now
        do {
            try modelContext.save()
            sessionStore.recordDelete(
                entity: .investmentValuation,
                recordID: valuation.id,
                modifiedAt: valuation.updatedAt,
                subjectUserIDOverride: valuation.ownerUserID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var chartUnit: Calendar.Component {
        switch period {
        case .day: .hour
        case .month: .day
        case .allTime: .month
        }
    }

    private var chartPoints: [InvestmentRealizedChartPoint] {
        var amounts: [Date: Int64] = [:]
        for trade in ownerTrades where trade.kind == .sell && (selectedDateInterval?.contains(trade.occurredAt) ?? true) {
            let bucket: Date
            switch period {
            case .day:
                bucket = calendar.dateInterval(of: .hour, for: trade.occurredAt)?.start ?? trade.occurredAt
            case .month:
                bucket = calendar.startOfDay(for: trade.occurredAt)
            case .allTime:
                bucket = calendar.date(from: calendar.dateComponents([.year, .month], from: trade.occurredAt)) ?? trade.occurredAt
            }
            amounts[bucket, default: 0] += trade.realizedProfitLossMinor
        }
        return amounts.map { InvestmentRealizedChartPoint(date: $0.key, amountMinor: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

private struct InvestmentRealizedChartPoint: Identifiable {
    let date: Date
    let amountMinor: Int64
    var id: Date { date }
}

private struct InvestmentMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
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
        NavigationStack {
            Form {
                TextField(L10n.investment.channel.namePlaceholder, text: $name)
            }
            .navigationTitle(L10n.investment.channel.newTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (channel != nil && !canEditExisting))
                }
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
            dismiss()
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
    @State private var symbol = ""
    @State private var currencyCode = "JPY"
    @State private var openingQuantity = ""
    @State private var openingCost = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.investment.hub.channels, selection: $channelID) {
                    ForEach(channels) { channel in
                        Text(channel.name).tag(Optional(channel.id))
                    }
                }
                .disabled(asset != nil && hasHistory)
                Section {
                    TextField(L10n.investment.asset.namePlaceholder, text: $name)
                    TextField(L10n.investment.asset.symbol, text: $symbol)
                    Picker(L10n.investment.asset.currency, selection: $currencyCode) {
                        ForEach(MistiaCurrencySettings.enabledCurrencyCodes(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .disabled(asset != nil && hasHistory)
                }
                Section {
                    TextField(L10n.investment.asset.openingQuantity, text: $openingQuantity)
                        .keyboardType(.decimalPad)
                    MistiaCurrencyInputField(L10n.investment.asset.openingCost, text: $openingCost)
                }
                .disabled(asset != nil)
            }
            .navigationTitle(L10n.investment.asset.newTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) { save() }
                        .disabled(channelID == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (asset != nil && !canEditExisting))
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func hydrate() {
        channelID = asset?.channelID ?? selectedChannelID ?? channels.first?.id
        name = asset?.name ?? ""
        symbol = asset?.symbol ?? ""
        currencyCode = asset?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
        if let asset {
            openingQuantity = InvestmentDecimalCoding.string(from: asset.openingQuantity)
            openingCost = MistiaCurrencyInputFormatting.groupedInput(String(asset.openingCostMinor))
        }
    }

    private func save() {
        guard let channelID else { return }
        do {
            if let asset {
                asset.channelID = channelID
                asset.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                asset.symbol = trimmedSymbol.isEmpty ? nil : trimmedSymbol
                asset.currencyCode = MistiaCurrencyLogic.normalizedCode(currencyCode)
                asset.updatedAt = .now
                try modelContext.save()
                sessionStore.recordUpsert(
                    entity: .investmentAsset,
                    recordID: asset.id,
                    modifiedAt: asset.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            } else {
                let openingQuantityValue = parsedDecimal(openingQuantity)
                let openingCostValue = openingCost.currencyInputToMinorUnits(currencyCode: currencyCode)
                let accountingCurrencyCode = investmentAccountingCurrency(
                    ownerUserID: ownerUserID,
                    context: modelContext
                )
                guard let accountingOpeningCost = MistiaCurrencyLogic.convertedMinorAmount(
                    openingCostValue,
                    from: currencyCode,
                    to: accountingCurrencyCode,
                    rates: MistiaCurrencySettings.rates()
                ) else {
                    onError(L10n.investment.error.missingExchangeRate)
                    return
                }
                let asset = try InvestmentPersistenceService.createAsset(
                    ownerUserID: ownerUserID,
                    channelID: channelID,
                    name: name,
                    symbol: symbol,
                    currencyCode: currencyCode,
                    openingQuantity: openingQuantityValue,
                    openingCostMinor: accountingOpeningCost,
                    context: modelContext
                )
                sessionStore.recordUpsert(
                    entity: .investmentAsset,
                    recordID: asset.id,
                    modifiedAt: asset.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            }
            dismiss()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct InvestmentTradeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    let ownerUserID: UUID
    let assets: [InvestmentAsset]
    let trade: InvestmentTrade?
    let initialKind: InvestmentTradeKind
    let wallets: [LedgerWallet]
    let ledgerTransactions: [LedgerTransaction]
    let canUseOrdinaryWallet: (LedgerWallet) -> Bool
    let canEditExisting: Bool
    let onError: (String) -> Void

    @State private var kind: InvestmentTradeKind = .buy
    @State private var assetID: UUID?
    @State private var walletID: UUID?
    @State private var quantity = ""
    @State private var grossAmount = ""
    @State private var fee = ""
    @State private var note = ""
    @State private var occurredAt = Date()

    private var selectedAsset: InvestmentAsset? { assets.first { $0.id == assetID } }
    private var accountingCurrencyCode: String {
        systemWallet?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
    }
    private var systemWallet: LedgerWallet? {
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.first { $0.id == id }
    }
    private var systemWalletBalance: Int64 {
        guard let systemWallet else { return 0 }
        let snapshot = TransactionWalletSnapshot(id: systemWallet.id, kind: systemWallet.kind, openingBalanceMinor: systemWallet.openingBalanceMinor)
        return TransactionLogic.walletBalanceIndex(wallets: [snapshot], records: ledgerTransactions.map(\.snapshot)).balance(for: snapshot)
    }
    private var availableWallets: [LedgerWallet] {
        let systemID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.filter { wallet in
            guard wallet.deletedAt == nil, !wallet.isArchived else { return false }
            if wallet.id == systemID {
                return kind == .buy && systemWalletBalance > 0
            }
            guard canUseOrdinaryWallet(wallet) else { return false }
            return kind == .buy || wallet.kind != .creditCard
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var availableQuantity: Decimal {
        guard let selectedAsset else { return 0 }
        let assetTrades = try? InvestmentAccountingEngine.recalculate(
            openingPosition: InvestmentOpeningPosition(
                quantity: selectedAsset.openingQuantity,
                costBasisMinor: selectedAsset.openingCostMinor
            ),
            trades: assetsTrades(selectedAsset).filter { $0.id != trade?.id }.map {
                InvestmentTradeInput(
                    id: $0.id,
                    kind: $0.kind,
                    quantity: $0.quantity,
                    accountingGrossAmountMinor: $0.accountingGrossAmountMinor,
                    accountingFeeMinor: $0.accountingFeeMinor,
                    occurredAt: $0.occurredAt,
                    createdAt: $0.createdAt
                )
            }
        )
        return assetTrades?.last?.positionQuantityAfter ?? selectedAsset.openingQuantity
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.investment.trade.asset, selection: $assetID) {
                    ForEach(assets) { asset in Text(asset.name).tag(Optional(asset.id)) }
                }
                .disabled(trade != nil)
                Picker(L10n.investment.title, selection: $kind) {
                    Text(L10n.investment.hub.buy).tag(InvestmentTradeKind.buy)
                    Text(L10n.investment.hub.sell).tag(InvestmentTradeKind.sell)
                }
                .pickerStyle(.segmented)
                .disabled(trade != nil)
                Section {
                    TextField(L10n.investment.trade.quantity, text: $quantity)
                        .keyboardType(.decimalPad)
                    if kind == .sell {
                        Text(L10n.investment.trade.availableQuantity(InvestmentDecimalCoding.string(from: availableQuantity)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    MistiaCurrencyInputField(L10n.investment.trade.grossAmount, text: $grossAmount)
                    MistiaCurrencyInputField(L10n.investment.trade.fee, text: $fee)
                    DatePicker(L10n.investment.trade.date, selection: $occurredAt)
                    TextField(L10n.investment.trade.note, text: $note)
                }
                Section {
                    Picker(kind == .buy ? L10n.investment.trade.fundingWallet : L10n.investment.trade.capitalWallet, selection: $walletID) {
                        ForEach(availableWallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }
                }
            }
            .navigationTitle(kind == .buy ? L10n.investment.trade.newBuyTitle : L10n.investment.trade.newSellTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.common.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { hydrate() }
            .onChange(of: kind) { _, _ in
                if !availableWallets.contains(where: { $0.id == walletID }) {
                    walletID = availableWallets.first?.id
                }
            }
        }
    }

    private var canSave: Bool {
        guard assetID != nil, walletID != nil, selectedAsset != nil else { return false }
        guard parsedDecimal(quantity) > 0 else { return false }
        guard grossAmount.currencyInputToMinorUnits(currencyCode: selectedAsset?.currencyCode ?? "JPY") > 0 else { return false }
        if kind == .sell, parsedDecimal(quantity) > availableQuantity { return false }
        return trade == nil || canEditExisting
    }

    private func hydrate() {
        kind = trade?.kind ?? initialKind
        assetID = trade?.assetID ?? assets.first?.id
        walletID = trade.flatMap { $0.kind == .buy ? $0.fundingWalletID : $0.capitalReturnWalletID }
            ?? availableWallets.first?.id
        quantity = trade.map { InvestmentDecimalCoding.string(from: $0.quantity) } ?? ""
        if let trade {
            grossAmount = MistiaCurrencyInputFormatting.groupedInput(String(trade.grossAmountMinor))
            fee = MistiaCurrencyInputFormatting.groupedInput(String(trade.feeMinor))
            note = trade.note ?? ""
            occurredAt = trade.occurredAt
        }
    }

    private func assetsTrades(_ asset: InvestmentAsset) -> [InvestmentTrade] {
        guard let context = asset.modelContext else { return [] }
        return (try? context.fetch(FetchDescriptor<InvestmentTrade>()))?
            .filter { $0.assetID == asset.id && $0.deletedAt == nil }
            .sorted(by: oldestTradeFirst) ?? []
    }

    private func save() {
        guard let asset = selectedAsset, let walletID else { return }
        let currency = asset.currencyCode
        let grossMinor = grossAmount.currencyInputToMinorUnits(currencyCode: currency)
        let feeMinor = fee.currencyInputToMinorUnits(currencyCode: currency)
        let rates = MistiaCurrencySettings.rates()
        guard let accountingGross = MistiaCurrencyLogic.convertedMinorAmount(
            grossMinor,
            from: currency,
            to: accountingCurrencyCode,
            rates: rates
        ), let accountingFee = MistiaCurrencyLogic.convertedMinorAmount(
            feeMinor,
            from: currency,
            to: accountingCurrencyCode,
            rates: rates
        ) else {
            onError(L10n.investment.error.missingExchangeRate)
            return
        }

        let savedTradeID = trade?.id ?? UUID()
        do {
            _ = try InvestmentPersistenceService.saveTrade(
                ownerUserID: ownerUserID,
                draft: InvestmentTradeDraft(
                    id: savedTradeID,
                    channelID: asset.channelID,
                    assetID: asset.id,
                    kind: kind,
                    quantity: parsedDecimal(quantity),
                    grossAmountMinor: grossMinor,
                    feeMinor: feeMinor,
                    currencyCode: currency,
                    accountingGrossAmountMinor: accountingGross,
                    accountingFeeMinor: accountingFee,
                    accountingCurrencyCode: accountingCurrencyCode,
                    exchangeRateDecimalString: rateSnapshot(from: currency, to: accountingCurrencyCode, rates: rates),
                    exchangeRateProvider: rateProvider(from: currency, to: accountingCurrencyCode, rates: rates),
                    exchangeRateDate: rateDate(from: currency, to: accountingCurrencyCode, rates: rates),
                    fundingWalletID: kind == .buy ? walletID : nil,
                    capitalReturnWalletID: kind == .sell ? walletID : nil,
                    note: note,
                    occurredAt: occurredAt,
                    createdAt: trade?.createdAt ?? .now
                ),
                rates: rates,
                context: modelContext
            )
            if let savedTrade = try? modelContext.fetch(FetchDescriptor<InvestmentTrade>()).first(where: { $0.id == savedTradeID }) {
                sessionStore.recordUpsert(
                    entity: .investmentTrade,
                    recordID: savedTrade.id,
                    modifiedAt: savedTrade.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            }
            dismiss()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct InvestmentValuationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    let ownerUserID: UUID
    let asset: InvestmentAsset
    let valuation: InvestmentValuation?
    let canEditExisting: Bool
    let onError: (String) -> Void
    @State private var marketValue = ""
    @State private var valuedAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                MistiaCurrencyInputField(L10n.investment.valuation.marketValue, text: $marketValue)
                DatePicker(L10n.investment.trade.date, selection: $valuedAt)
            }
            .navigationTitle(L10n.investment.valuation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.common.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) { save() }
                        .disabled(
                            marketValue.currencyInputToMinorUnits(currencyCode: asset.currencyCode) < 0
                                || (valuation != nil && !canEditExisting)
                        )
                }
            }
            .onAppear {
                guard let valuation else { return }
                marketValue = MistiaCurrencyInputFormatting.groupedInput(
                    String(valuation.marketValueMinor)
                )
                valuedAt = valuation.valuedAt
            }
        }
    }

    private func save() {
        let amount = marketValue.currencyInputToMinorUnits(currencyCode: asset.currencyCode)
        let accountingCurrency = investmentAccountingCurrency(ownerUserID: ownerUserID, context: modelContext)
        let rates = MistiaCurrencySettings.rates()
        guard let accountingAmount = MistiaCurrencyLogic.convertedMinorAmount(
            amount,
            from: asset.currencyCode,
            to: accountingCurrency,
            rates: rates
        ) else {
            onError(L10n.investment.error.missingExchangeRate)
            return
        }
        let now = Date()
        let record = valuation ?? InvestmentValuation(
            ownerUserID: ownerUserID,
            channelID: asset.channelID,
            assetID: asset.id,
            marketValueMinor: amount,
            accountingMarketValueMinor: accountingAmount,
            currencyCode: asset.currencyCode,
            accountingCurrencyCode: accountingCurrency,
            valuedAt: valuedAt,
            createdAt: now,
            updatedAt: now
        )
        if valuation == nil { modelContext.insert(record) }
        record.marketValueMinor = amount
        record.accountingMarketValueMinor = accountingAmount
        record.currencyCode = asset.currencyCode
        record.accountingCurrencyCode = accountingCurrency
        record.exchangeRateDecimalString = rateSnapshot(
            from: asset.currencyCode,
            to: accountingCurrency,
            rates: rates
        )
        record.valuedAt = valuedAt
        record.updatedAt = now
        record.deletedAt = nil
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .investmentValuation,
                recordID: record.id,
                modifiedAt: record.updatedAt,
                subjectUserIDOverride: ownerUserID
            )
            dismiss()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

struct InvestmentWalletDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query private var wallets: [LedgerWallet]
    @Query private var ledgerTransactions: [LedgerTransaction]
    @Query private var postings: [InvestmentWalletPosting]

    let ownerUserID: UUID
    @State private var showsTransfer = false
    @State private var errorMessage: String?

    private var wallet: LedgerWallet? {
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.first { $0.id == id && $0.deletedAt == nil }
    }
    private var balanceMinor: Int64 {
        guard let wallet else { return 0 }
        let snapshot = TransactionWalletSnapshot(id: wallet.id, kind: wallet.kind, openingBalanceMinor: wallet.openingBalanceMinor)
        return TransactionLogic.walletBalanceIndex(wallets: [snapshot], records: ledgerTransactions.filter { $0.deletedAt == nil && !$0.isArchived }.map(\.snapshot)).balance(for: snapshot)
    }
    private var canCreate: Bool {
        ownerUserID == sessionStore.activeLocalProfileUserID
            || ownerUserID == sessionStore.signedInUserID
            || familyContextStore.canCreate(ownerUserID: ownerUserID, resourceType: .investment)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.investment.hub.walletBalance)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(balanceMinor.formattedCurrency(code: wallet?.currencyCode ?? "JPY"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(balanceMinor >= 0 ? Color.primary : Color.red)
                    }
                    .padding(.vertical, 10)
                    Button(L10n.investment.wallet.transferOut) { showsTransfer = true }
                        .disabled(!canCreate || balanceMinor <= 0)
                }
                Section(L10n.investment.hub.activity) {
                    ForEach(walletPostings.sorted { $0.occurredAt > $1.occurredAt }) { posting in
                        HStack {
                            Text(postingTitle(posting.role))
                            Spacer()
                            Text(posting.amountMinor.formattedCurrency(code: posting.currencyCode))
                                .foregroundStyle(posting.amountMinor >= 0 ? Color.green : Color.red)
                        }
                    }
                }
            }
            .navigationTitle(L10n.investment.wallet.detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L10n.common.close) { dismiss() } }
            }
        }
        .sheet(isPresented: $showsTransfer) {
            InvestmentWalletTransferSheet(ownerUserID: ownerUserID) { errorMessage = $0 }
        }
        .alert(L10n.common.error, isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L10n.common.ok) { errorMessage = nil }
        } message: { Text(errorMessage ?? L10n.common.unknownError) }
    }

    private var walletPostings: [InvestmentWalletPosting] {
        guard let wallet else { return [] }
        return postings.filter { $0.ownerUserID == ownerUserID && $0.walletID == wallet.id && $0.deletedAt == nil }
    }

    private func postingTitle(_ role: InvestmentPostingRole) -> String {
        switch role {
        case .funding: L10n.investment.hub.buy
        case .capitalReturn: L10n.investment.hub.sell
        case .realizedProfit: L10n.investment.hub.realizedProfitLoss
        case .transferOut, .transferIn: L10n.investment.wallet.transferOut
        }
    }
}

private struct InvestmentWalletTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query private var wallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let ownerUserID: UUID
    let onError: (String) -> Void
    @State private var destinationWalletID: UUID?
    @State private var sourceAmount = ""

    private var systemWallet: LedgerWallet? {
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.first { $0.id == id }
    }
    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }
    private var destinationWallets: [LedgerWallet] {
        let systemID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        let currentID = sessionStore.activeLocalProfileUserID ?? sessionStore.signedInUserID
        return wallets.filter { wallet in
            guard wallet.id != systemID, wallet.deletedAt == nil, !wallet.isArchived, wallet.kind != .creditCard else { return false }
            guard (walletOwnerMap[wallet.id] ?? currentID) == ownerUserID else { return false }
            return ownerUserID == currentID || familyContextStore.canUseWallet(walletID: wallet.id, ownerUserID: ownerUserID)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.investment.transfer.destination, selection: $destinationWalletID) {
                    ForEach(destinationWallets) { wallet in Text(wallet.name).tag(Optional(wallet.id)) }
                }
                MistiaCurrencyInputField(L10n.investment.transfer.sourceAmount, text: $sourceAmount)
            }
            .navigationTitle(L10n.investment.wallet.transferTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.common.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.common.save) { save() }
                        .disabled(destinationWalletID == nil || sourceAmountMinor <= 0)
                }
            }
            .onAppear { destinationWalletID = destinationWalletID ?? destinationWallets.first?.id }
        }
    }

    private var sourceAmountMinor: Int64 {
        sourceAmount.currencyInputToMinorUnits(currencyCode: systemWallet?.currencyCode ?? "JPY")
    }

    private func save() {
        guard let systemWallet, let destinationWallet = destinationWallets.first(where: { $0.id == destinationWalletID }) else { return }
        let rates = MistiaCurrencySettings.rates()
        guard let destinationAmount = MistiaCurrencyLogic.convertedMinorAmount(
            sourceAmountMinor,
            from: systemWallet.currencyCode,
            to: destinationWallet.currencyCode,
            rates: rates
        ) else {
            onError(L10n.investment.error.missingExchangeRate)
            return
        }
        do {
            let result = try InvestmentPersistenceService.createOutboundTransfer(
                ownerUserID: ownerUserID,
                destinationWalletID: destinationWallet.id,
                sourceAmountMinor: sourceAmountMinor,
                destinationAmountMinor: destinationAmount,
                rates: rates,
                context: modelContext
            )
            for transactionID in result.ledgerTransactionIDs {
                sessionStore.recordUpsert(
                    entity: .transaction,
                    recordID: transactionID,
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

private func parsedDecimal(_ text: String) -> Decimal {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

private func investmentAccountingCurrency(ownerUserID: UUID, context: ModelContext) -> String {
    let walletID = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
    let wallet = try? context.fetch(FetchDescriptor<LedgerWallet>()).first { $0.id == walletID }
    return wallet?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
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
