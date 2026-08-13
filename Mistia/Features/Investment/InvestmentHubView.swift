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

private enum InvestmentHubSheet: Identifiable {
    case channel(UUID?)
    case asset(UUID?)
    case trade(kind: InvestmentTradeKind, id: UUID?)
    case wallet
    case lotHistory(InvestmentAsset)

    var id: String {
        switch self {
        case .channel(let id): "channel-\(id?.uuidString ?? "new")"
        case .asset(let id): "asset-\(id?.uuidString ?? "new")"
        case .trade(let kind, let id): "trade-\(kind.rawValue)-\(id?.uuidString ?? "new")"
        case .wallet: "wallet"
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
    @State private var activeAlert: InvestmentHubAlert?
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
            canBuy: !canCreate || canStartBuyTrade,
            canSell: !canCreate || canStartSellTrade,
            onBuy: { openNewTrade(kind: .buy) },
            onSell: { openNewTrade(kind: .sell) }
        )
    }

    private var canStartBuyTrade: Bool {
        !ownerAssets.isEmpty
    }

    private var canStartSellTrade: Bool {
        ownerAssets.contains { position(for: $0).quantity > 0 }
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
            Image(systemName: "slider.horizontal.3")
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
                    openLotCount: position.openLotCount
                )
                let detail = positionDetail(for: snapshot)
                Button {
                    openAsset(asset)
                } label: {
                    InvestmentPositionRow(
                        imagePath: asset.imagePath,
                        assetName: asset.name,
                        detail: detail,
                        remainingCapitalMinor: snapshot.remainingCostBasisMinor,
                        currencyCode: accountingCurrencyCode
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

    private func positionDetail(for snapshot: InvestmentAssetPositionSnapshot) -> String {
        let quantity = InvestmentDecimalCoding.string(from: snapshot.quantity)
        guard snapshot.quantity > 0 else {
            return L10n.investment.hub.outOfStock
        }
        return L10n.investment.hub.positionDetails(
            quantity,
            String(snapshot.openLotCount)
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
                    openTrade(trade)
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            InvestmentProductThumbnail(
                                imagePath: assets.first(where: { $0.id == trade.assetID })?.imagePath,
                                size: 44
                            )
                            Image(systemName: trade.kind == .buy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(trade.kind == .buy ? Color.blue : Color.green)
                                .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetName(for: trade.assetID))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(
                                L10n.investment.hub.activityDetails(
                                    InvestmentDecimalCoding.string(from: trade.quantity),
                                    MistiaDateFormatting.fullDateString(for: trade.occurredAt)
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
            case .wallet:
                if canEdit {
                    InvestmentWalletTransferSheet(ownerUserID: ownerUserID) { showError($0) }
                }
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
        guard canEdit else {
            presentPermissionPrompt(scope: .edit) {
                activeSheet = .wallet
            }
            return
        }
        activeSheet = .wallet
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

    private func position(for asset: InvestmentAsset) -> (quantity: Decimal, costBasisMinor: Int64, openLotCount: Int) {
        let assetTrades = trades
            .filter { $0.assetID == asset.id && $0.deletedAt == nil }
            .sorted(by: oldestTradeFirst)
        guard !assetTrades.isEmpty else {
            return (0, 0, 0)
        }
        let inputs = assetTrades.map {
            InvestmentTradeInput(
                id: $0.id,
                kind: $0.kind,
                quantity: $0.quantity,
                accountingGrossAmountMinor: $0.accountingGrossAmountMinor,
                occurredAt: $0.occurredAt,
                createdAt: $0.createdAt
            )
        }
        guard let last = try? InvestmentAccountingEngine.recalculate(trades: inputs).last else {
            let persisted = assetTrades.last
            return (persisted?.positionQuantityAfter ?? 0, persisted?.positionCostBasisAfterMinor ?? 0, 0)
        }
        return (last.positionQuantityAfter, last.positionCostBasisAfterMinor, last.openLotCountAfter)
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
                    Text((summary.realizedProfitLossMinor > 0 ? "+" : "") + summary.realizedProfitLossMinor.formattedCurrency(code: currencyCode))
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

    var body: some View {
        HStack(spacing: 12) {
            InvestmentProductThumbnail(imagePath: imagePath, size: 44)
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
                Text(L10n.investment.hub.costBasis)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(remainingCapitalMinor.formattedCurrency(code: currencyCode))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
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
    @State private var draftAssetID = UUID()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var removesExistingImage = false
    @State private var showsCamera = false

    var body: some View {
        MistiaModalScaffold(
            title: L10n.investment.asset.newTitle,
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            saveDisabled: channelID == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (asset != nil && !canEditExisting),
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
                    Menu {
                        Button {
                            showsCamera = true
                        } label: {
                            Label(L10n.investment.asset.takePhoto, systemImage: "camera")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(L10n.investment.asset.choosePhoto, systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label(
                            selectedImage == nil && asset?.imagePath == nil
                                ? L10n.investment.asset.addImage
                                : L10n.investment.asset.replaceImage,
                            systemImage: "photo.badge.plus"
                        )
                    }
                    if selectedImage != nil || (!removesExistingImage && asset?.imagePath != nil) {
                        Button(L10n.investment.asset.removeImage, role: .destructive) {
                            selectedImage = nil
                            selectedPhotoItem = nil
                            removesExistingImage = true
                        }
                    }
                }
            }
            .onAppear { hydrate() }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    selectedImage = image
                    removesExistingImage = false
                }
            }
        }
        .sheet(isPresented: $showsCamera) {
            InvestmentCameraPicker { image in
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
        draftAssetID = asset?.id ?? draftAssetID
    }

    private func save() {
        guard let channelID else { return }
        do {
            let targetAssetID = asset?.id ?? draftAssetID
            var imagePath = asset?.imagePath
            if let selectedImage {
                let normalized = try InvestmentProductImageProcessing.normalizedJPEG(selectedImage)
                imagePath = try InvestmentProductImageStore().stageReplacement(
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
            if let asset {
                asset.channelID = channelID
                asset.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                asset.currencyCode = MistiaCurrencyLogic.normalizedCode(currencyCode)
                asset.imagePath = imagePath
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
                    id: targetAssetID,
                    ownerUserID: ownerUserID,
                    channelID: channelID,
                    name: name,
                    currencyCode: currencyCode,
                    imagePath: imagePath,
                    context: modelContext
                )
                sessionStore.recordUpsert(
                    entity: .investmentAsset,
                    recordID: asset.id,
                    modifiedAt: asset.updatedAt,
                    subjectUserIDOverride: ownerUserID
                )
            }
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

private struct InvestmentTradeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore

    let ownerUserID: UUID
    let channels: [InvestmentChannel]
    let assets: [InvestmentAsset]
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
    @State private var grossAmount = ""
    @State private var note = ""
    @State private var occurredAt = Date()
    @State private var showsAssetPicker = false
    @State private var draftTradeID = UUID()
    @State private var draftCreatedAt = Date()

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
        return availableQuantity(for: selectedAsset)
    }

    var body: some View {
        MistiaModalScaffold(
            titleView: {
                Picker("", selection: $kind) {
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
                    TextField(L10n.investment.trade.quantity, text: $quantity)
                        .keyboardType(.decimalPad)
                    if kind == .sell {
                        Text(L10n.investment.trade.availableQuantity(InvestmentDecimalCoding.string(from: availableQuantity)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    MistiaCurrencyInputField(
                        kind == .buy ? L10n.investment.trade.buyTotal : L10n.investment.trade.sellTotal,
                        text: $grossAmount
                    )
                    MistiaDatePickerRow(
                        title: L10n.investment.trade.time,
                        selection: $occurredAt,
                        mode: .dateAndTime
                    )
                    TextField(L10n.investment.trade.note, text: $note)
                }
                Section {
                    Picker(kind == .buy ? L10n.investment.trade.fundingWallet : L10n.investment.trade.capitalWallet, selection: $walletID) {
                        ForEach(availableWallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
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
            .onAppear { hydrate() }
            .onChange(of: kind) { _, _ in
                if !availableWallets.contains(where: { $0.id == walletID }) {
                    walletID = availableWallets.first?.id
                }
                if kind == .sell,
                   !selectableAssets.contains(where: { $0.id == assetID }) {
                    assetID = selectableAssets.first?.id
                }
            }
        }
        .sheet(isPresented: $showsAssetPicker) {
            InvestmentAssetPickerSheet(
                assets: selectableAssets,
                channels: channels,
                selection: $assetID
            )
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
        draftTradeID = trade?.id ?? draftTradeID
        draftCreatedAt = trade?.createdAt ?? draftCreatedAt
        assetID = trade?.assetID
            ?? (kind == .sell ? selectableAssets.first?.id : assets.first?.id)
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

    private var selectableAssets: [InvestmentAsset] {
        guard kind == .sell else { return assets }
        return assets.filter { asset in
            availableQuantity(for: asset) > 0 || asset.id == trade?.assetID
        }
    }

    private func availableQuantity(for asset: InvestmentAsset) -> Decimal {
        let prospectiveID = trade?.id ?? draftTradeID
        let prospectiveCreatedAt = trade?.createdAt ?? draftCreatedAt
        let eligible = assetsTrades(asset).filter { candidate in
            guard candidate.id != trade?.id else { return false }
            if candidate.occurredAt != occurredAt { return candidate.occurredAt < occurredAt }
            if candidate.createdAt != prospectiveCreatedAt { return candidate.createdAt < prospectiveCreatedAt }
            return MistiaStableUUIDOrdering.precedes(candidate.id, prospectiveID)
        }
        let calculations = try? InvestmentAccountingEngine.recalculate(
            trades: eligible.map {
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
        return calculations?.last?.positionQuantityAfter ?? 0
    }

    private func save() {
        guard let asset = selectedAsset, let walletID else { return }
        let currency = asset.currencyCode
        let grossMinor = grossAmount.currencyInputToMinorUnits(currencyCode: currency)
        let rates = MistiaCurrencySettings.rates()
        let sourceCode = MistiaCurrencyLogic.normalizedCode(currency)
        let accountingCode = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        let preservesExistingCurrencyPair = trade.map {
            MistiaCurrencyLogic.normalizedCode($0.currencyCode) == sourceCode
                && MistiaCurrencyLogic.normalizedCode($0.accountingCurrencyCode) == accountingCode
        } ?? false
        let exchangeRateDecimalString = preservesExistingCurrencyPair
            ? trade?.exchangeRateDecimalString
            : rateSnapshot(from: currency, to: accountingCurrencyCode, rates: rates)
        let exchangeRateProvider = preservesExistingCurrencyPair
            ? trade?.exchangeRateProvider
            : rateProvider(from: currency, to: accountingCurrencyCode, rates: rates)
        let exchangeRateDate = preservesExistingCurrencyPair
            ? trade?.exchangeRateDate
            : rateDate(from: currency, to: accountingCurrencyCode, rates: rates)

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
                    exchangeRateProvider: exchangeRateProvider,
                    exchangeRateDate: exchangeRateDate,
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
        } catch {
            onError(error.localizedDescription)
        }
    }
}

struct InvestmentWalletTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil }) private var wallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var ledgerTransactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let ownerUserID: UUID
    let onError: (String) -> Void
    @State private var destinationWalletID: UUID?
    @State private var sourceAmount = ""

    private var systemWallet: LedgerWallet? {
        let id = InvestmentSystemWalletIdentity.walletID(ownerUserID: ownerUserID)
        return wallets.first { $0.id == id }
    }
    private var investmentBalanceMinor: Int64 {
        guard let systemWallet else { return 0 }
        let snapshot = TransactionWalletSnapshot(
            id: systemWallet.id,
            kind: systemWallet.kind,
            openingBalanceMinor: systemWallet.openingBalanceMinor
        )
        return TransactionLogic.walletBalanceIndex(
            wallets: [snapshot],
            records: ledgerTransactions.map(\.snapshot)
        ).balance(for: snapshot)
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
    private var currencyCode: String { systemWallet?.currencyCode ?? "JPY" }
    private var sourceAmountMinor: Int64 {
        sourceAmount.currencyInputToMinorUnits(currencyCode: currencyCode)
    }
    private var isBalanceEmpty: Bool { investmentBalanceMinor <= 0 }
    private var isSaveDisabled: Bool {
        isBalanceEmpty || destinationWalletID == nil || sourceAmountMinor <= 0 || sourceAmountMinor > investmentBalanceMinor
    }

    var body: some View {
        MistiaModalScaffold(
            title: L10n.investment.wallet.transferTitle,
            accent: MistiaAccent.purple.color,
            contentStyle: .form,
            saveDisabled: isSaveDisabled,
            onSave: save
        ) {
            Form {
                Picker(L10n.investment.transfer.destination, selection: $destinationWalletID) {
                    ForEach(destinationWallets) { wallet in Text(wallet.name).tag(Optional(wallet.id)) }
                }
                Section {
                    MistiaCurrencyInputField(L10n.investment.transfer.sourceAmount, text: $sourceAmount)
                        .disabled(isBalanceEmpty)
                    if isBalanceEmpty {
                        Text(L10n.investment.wallet.insufficientBalance)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text(
                            L10n.investment.wallet.availableBalance(
                                investmentBalanceMinor.formattedCurrency(code: currencyCode)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear { destinationWalletID = destinationWalletID ?? destinationWallets.first?.id }
            .onChange(of: sourceAmount) { _, newValue in
                guard !isBalanceEmpty else { return }
                let entered = newValue.currencyInputToMinorUnits(currencyCode: currencyCode)
                if entered > investmentBalanceMinor {
                    sourceAmount = MistiaCurrencyInputFormatting.groupedInput(String(investmentBalanceMinor))
                }
            }
        }
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

private struct InvestmentCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: InvestmentCameraPicker

        init(parent: InvestmentCameraPicker) {
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
                        grossAmountMinor: trade.grossAmountMinor,
                        remainingCostBasisMinor: trade.grossAmountMinor,
                        currencyCode: trade.currencyCode,
                        fundingWalletName: walletName,
                        note: trade.note
                    )
                )
            } else if trade.kind == .sell {
                var quantityToDeduct = trade.quantity
                for index in 0..<lots.count {
                    guard quantityToDeduct > 0 else { break }
                    if lots[index].remainingQuantity > 0 {
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
                Picker("", selection: $filterMode) {
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
                    Text("\(InvestmentDecimalCoding.string(from: lot.remainingQuantity)) / \(InvestmentDecimalCoding.string(from: lot.initialQuantity))")
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
