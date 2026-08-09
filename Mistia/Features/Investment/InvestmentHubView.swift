import SwiftData
import SwiftUI

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
    @State private var selectedMonth = Date()
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

    private var monthSelectionBounds: MistiaMonthSelectionBounds {
        let relevantDates = ownerTrades.map(\.occurredAt) + [Date()]
        return MistiaMonthSelectionBounds(
            minimumMonth: relevantDates.min() ?? selectedMonth,
            maximumMonth: relevantDates.max() ?? selectedMonth,
            calendar: calendar
        )
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
                if canView {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if canCreate {
                            Button {
                                activeSheet = ownerChannels.isEmpty ? .channel(nil) : .asset(nil)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(
                                ownerChannels.isEmpty
                                    ? L10n.investment.hub.addChannel
                                    : L10n.investment.hub.addAsset
                            )
                        }
                        managementMenu
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
                    periodControl
                    summaryCard
                    primaryActions
                    positionsSection
                    activitySection
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
            canBuy: canCreate && !ownerAssets.isEmpty,
            canSell: canCreate && ownerAssets.contains { position(for: $0).quantity > 0 },
            onBuy: { activeSheet = .trade(kind: .buy, id: nil) },
            onSell: { activeSheet = .trade(kind: .sell, id: nil) }
        )
    }

    private var managementMenu: some View {
        Menu {
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

            if canCreate {
                Button(L10n.investment.hub.addChannel, systemImage: "square.stack.3d.up.badge.a") {
                    activeSheet = .channel(nil)
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
                activeSheet = .wallet
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
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L10n.management.management.manage)
    }

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.hub.positions)
                .font(.headline)

            ForEach(ownerAssets) { asset in
                let position = position(for: asset)
                let snapshot = InvestmentAssetPositionSnapshot(
                    id: asset.id,
                    channelID: asset.channelID,
                    quantity: position.quantity,
                    remainingCostBasisMinor: position.costBasisMinor,
                    marketValueMinor: latestValuation(for: asset)?.accountingMarketValueMinor
                )
                let detail = positionDetail(for: snapshot)
                Button {
                    if canCreate { activeSheet = .valuation(assetID: asset.id, id: nil) }
                } label: {
                    InvestmentPositionRow(
                        assetName: asset.name,
                        detail: detail,
                        remainingCapitalMinor: snapshot.remainingCostBasisMinor,
                        marketValueMinor: snapshot.marketValueMinor,
                        currencyCode: accountingCurrencyCode
                    )
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

    private func positionDetail(for snapshot: InvestmentAssetPositionSnapshot) -> String {
        let quantity = InvestmentDecimalCoding.string(from: snapshot.quantity)
        guard let average = snapshot.averageUnitCostMinor else {
            return L10n.investment.hub.quantityOnly(quantity)
        }
        return L10n.investment.hub.positionDetails(
            quantity,
            average.formattedCurrency(code: accountingCurrencyCode)
        )
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.investment.hub.activity)
                .font(.headline)
            if visibleTrades.isEmpty {
                Text(L10n.investment.hub.noActivityForPeriod)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            ForEach(visibleTrades.sorted(by: newestTradeFirst)) { trade in
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
                            Text(
                                L10n.investment.hub.activityDetails(
                                    InvestmentDecimalCoding.string(from: trade.quantity),
                                    trade.occurredAt.formatted(date: .abbreviated, time: .omitted)
                                )
                            )
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
            return (0, 0)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.investment.hub.investedCapital)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary.investedCapitalMinor.formattedCurrency(code: currencyCode))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(alignment: .top, spacing: 20) {
                metric(
                    title: L10n.investment.hub.marketValue,
                    amount: summary.marketValueMinor,
                    tint: .primary
                )
                metric(
                    title: L10n.investment.hub.unrealizedProfitLoss,
                    amount: summary.unrealizedProfitLossMinor,
                    tint: profitColor(summary.unrealizedProfitLossMinor)
                )
            }

            if summary.realizedProfitLossMinor != 0 {
                Divider()
                HStack {
                    Text(L10n.investment.hub.realizedProfitLoss)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.realizedProfitLossMinor.formattedCurrency(code: currencyCode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(profitColor(summary.realizedProfitLossMinor))
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metric(title: String, amount: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(amount.formattedCurrency(code: currencyCode))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profitColor(_ amount: Int64) -> Color {
        if amount > 0 { return .green }
        if amount < 0 { return .red }
        return .primary
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

private struct InvestmentPositionRow: View {
    let assetName: String
    let detail: String
    let remainingCapitalMinor: Int64
    let marketValueMinor: Int64?
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assetName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(remainingCapitalMinor.formattedCurrency(code: currencyCode))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                if let marketValueMinor {
                    Text(marketValueMinor.formattedCurrency(code: currencyCode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    @State private var currencyCode = "JPY"

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
                    Picker(L10n.investment.asset.currency, selection: $currencyCode) {
                        ForEach(MistiaCurrencySettings.enabledCurrencyCodes(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .disabled(asset != nil && hasHistory)
                }
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
        currencyCode = asset?.currencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
    }

    private func save() {
        guard let channelID else { return }
        do {
            if let asset {
                asset.channelID = channelID
                asset.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                let asset = try InvestmentPersistenceService.createAsset(
                    ownerUserID: ownerUserID,
                    channelID: channelID,
                    name: name,
                    currencyCode: currencyCode,
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
            trades: assetsTrades(selectedAsset).filter { $0.id != trade?.id }.map {
                InvestmentTradeInput(
                    id: $0.id,
                    kind: $0.kind,
                    quantity: $0.quantity,
                    accountingGrossAmountMinor: $0.accountingGrossAmountMinor,
                    occurredAt: $0.occurredAt,
                    createdAt: $0.createdAt
                )
            }
        )
        return assetTrades?.last?.positionQuantityAfter ?? 0
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
        let rates = MistiaCurrencySettings.rates()
        let sourceCode = MistiaCurrencyLogic.normalizedCode(currency)
        let accountingCode = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        let exchangeRateDecimalString = trade?.exchangeRateDecimalString
            ?? rateSnapshot(from: currency, to: accountingCurrencyCode, rates: rates)

        let accountingGross: Int64
        if sourceCode == accountingCode {
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
                    currencyCode: currency,
                    accountingGrossAmountMinor: accountingGross,
                    accountingCurrencyCode: accountingCurrencyCode,
                    exchangeRateDecimalString: exchangeRateDecimalString,
                    exchangeRateProvider: trade?.exchangeRateProvider
                        ?? rateProvider(from: currency, to: accountingCurrencyCode, rates: rates),
                    exchangeRateDate: trade?.exchangeRateDate
                        ?? rateDate(from: currency, to: accountingCurrencyCode, rates: rates),
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
