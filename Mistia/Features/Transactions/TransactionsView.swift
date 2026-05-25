import SwiftData
import SwiftUI

private enum TransactionSegment: String, CaseIterable, Hashable {
    case expense
    case income
    case transfer
    case adjustment

    var title: String {
        switch self {
        case .expense:
            L10n.transactions.transactions.expense2
        case .income:
            L10n.transactions.transactions.income2
        case .transfer:
            L10n.transactions.transactions.transfer
        case .adjustment:
            L10n.transactions.transactions.adjustment
        }
    }

    var tint: Color {
        MistiaAccent.purple.color
    }

    var kind: TransactionPrimaryKind? {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        case .adjustment:
            return nil
        }
    }
}

private enum TransactionsNavigationDestination: String, Identifiable {
    case aiBill

    var id: String { rawValue }
}

private struct TransactionsPermissionPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
}

private struct TransactionsInfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum TransactionsAlertPresentation: Identifiable {
    case info(TransactionsInfoAlert)
    case permission(TransactionsPermissionPrompt)

    var id: UUID {
        switch self {
        case .info(let alert):
            alert.id
        case .permission(let prompt):
            prompt.id
        }
    }

    var title: String {
        switch self {
        case .info(let alert):
            alert.title
        case .permission(let prompt):
            prompt.title
        }
    }

    var message: String {
        switch self {
        case .info(let alert):
            alert.message
        case .permission(let prompt):
            prompt.message
        }
    }
}

private enum TransactionsListPaging {
    static let initialLimit = 60
    static let increment = 40
}

private struct TransactionsListSnapshot {
    let activeTransactionCount: Int
    let visibleRecordCount: Int
    let displayedRecordCount: Int
    let openDebtPositions: [CounterpartyDebtSnapshot]
    let sections: [TransactionSectionSnapshot]
    let transactionsByID: [UUID: LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]

    var hasMoreRows: Bool {
        displayedRecordCount < visibleRecordCount
    }
}

struct TransactionsView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived }, sort: \LedgerTransaction.occurredAt, order: .reverse)
    private var storedTransactions: [LedgerTransaction]
    @Query private var storedWallets: [LedgerWallet]
    @Query private var storedCategories: [TransactionCategory]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @Query private var transactionAuditRecords: [TransactionAuditRecord]

    @State private var selectedSegment: TransactionSegment? = nil
    @State private var editorTarget: TransactionEditorTarget?
    @State private var filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearchPresented = false
    @State private var shareItem: TransactionShareItem?
    @State private var exportErrorMessage: String?
    @State private var destination: TransactionsNavigationDestination?
    @State private var permissionPrompt: TransactionsPermissionPrompt?
    @State private var infoAlert: TransactionsInfoAlert?
    @State private var visibleTransactionLimit = TransactionsListPaging.initialLimit

    private var activeTransactions: [LedgerTransaction] {
        visibleTransactions
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.createdAt > $1.createdAt
            }
    }

    private var activeWallets: [LedgerWallet] {
        visibleWallets
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var activeAlert: TransactionsAlertPresentation? {
        if let permissionPrompt {
            return .permission(permissionPrompt)
        }
        if let infoAlert {
            return .info(infoAlert)
        }
        return nil
    }

    private var activeCategorySections: [TransactionCategoryGroupSection] {
        switch selectedSegment?.kind {
        case .expense:
            return MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .expense,
                includeArchived: false,
                includeEmptyParents: false
            )
        case .income:
            return MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .income,
                includeArchived: false,
                includeEmptyParents: false
            )
        case .transfer:
            return []
        case nil:
            return MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .expense,
                includeArchived: false,
                includeEmptyParents: false
            ) + MistiaCategoryHierarchy.groupedSections(
                from: visibleCategories,
                kind: .income,
                includeArchived: false,
                includeEmptyParents: false
            )
        }
    }

    private var activeCategories: [TransactionCategory] {
        activeCategorySections.map(\.parent) + activeCategorySections.flatMap(\.children)
    }

    private var visibleTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForHistory(
            storedTransactions,
            audits: transactionAuditRecords,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
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

    private var transactionAuditMap: [UUID: TransactionAuditRecord] {
        TransactionAuditStore.auditMap(from: transactionAuditRecords)
    }

    private var transactionListSnapshot: TransactionsListSnapshot {
        let activeTransactions = self.activeTransactions
        let records = activeTransactions.map(\.snapshot)
        let page = TransactionLogic.visibleRecordsPage(
            from: records,
            selectedKind: selectedSegment?.kind,
            filters: effectiveFilters,
            limit: visibleTransactionLimit,
            assumesSortedByRecency: true,
            calendar: calendar
        )
        let displayedRecords = page.displayedRecords
        let displayedRecordIDs = Set(displayedRecords.map(\.id))
        let openDebtPositions = TransactionLogic.openDebtPositions(
            from: debtRecords(from: records)
        )

        return TransactionsListSnapshot(
            activeTransactionCount: activeTransactions.count,
            visibleRecordCount: page.totalCount,
            displayedRecordCount: displayedRecords.count,
            openDebtPositions: openDebtPositions,
            sections: TransactionLogic.sections(from: displayedRecords, calendar: calendar),
            transactionsByID: Dictionary(
                activeTransactions
                    .filter { displayedRecordIDs.contains($0.id) }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
            ),
            transactionAuditMap: transactionAuditMap,
            walletOwnerMap: walletOwnerMap,
            transactionOwnerMap: transactionOwnerMap
        )
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var transactionOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
    }

    private var snapshotRecords: [TransactionRecordSnapshot] {
        activeTransactions.map { $0.snapshot }
    }

    private var transactionRecords: [TransactionRecordSnapshot] {
        activeTransactions.map(\.planningRecordSnapshot)
    }

    private var overviewTransactions: [OverviewTransactionSnapshot] {
        activeTransactions.map(\.overviewSnapshot)
    }

    private var walletSnapshots: [OverviewWalletSnapshot] {
        activeWallets.compactMap(\.overviewWalletSnapshot)
    }

    private var statementCreditCardAccounts: [OverviewCreditCardStatementAccountSnapshot] {
        let filteredWallets: [LedgerWallet]
        if let walletID = filterState.walletID {
            filteredWallets = activeWallets.filter { $0.id == walletID }
        } else {
            filteredWallets = activeWallets
        }
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: activeWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionRecords
        )
        return filteredWallets.compactMap { $0.overviewCreditCardStatementAccountSnapshot(balanceIndex: balanceIndex) }
    }

    private var statementPeriod: DateInterval {
        let now = Date.now
        switch filterState.timeScope {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .yesterday:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: start, end: today)
        case .thisMonth:
            let monthStart = PlanningLogic.startOfMonth(for: now, calendar: calendar)
            let monthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? now
            return DateInterval(start: monthStart, end: min(now, monthEnd))
        case .allTime:
            // Default: max 3 recent calendar months
            let currentMonthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? now
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -2, to: PlanningLogic.startOfMonth(for: now, calendar: calendar)) ?? now
            return DateInterval(start: threeMonthsAgo, end: min(now, currentMonthEnd))
        }
    }

    private var statementFilteredTransactions: [OverviewTransactionSnapshot] {
        overviewTransactions.filter { transaction in
            if let walletID = filterState.walletID {
                guard transaction.sourceWalletID == walletID || transaction.destinationWalletID == walletID else {
                    return false
                }
            }

            if let categoryID = filterState.categoryID {
                guard transaction.categoryID == categoryID else {
                    return false
                }
            }

            if let kind = selectedSegment?.kind {
                guard transaction.primaryKind == kind else {
                    return false
                }
            }

            return true
        }
    }

    private var monthlyStatement: TransactionSummaryStatementSnapshot {
        TransactionLogic.monthlyStatement(
            wallets: walletSnapshots,
            transactionRecords: transactionRecords,
            transactions: statementFilteredTransactions,
            statementPeriod: statementPeriod,
            currencyCode: currencyCode,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var creditCardStatement: TransactionCreditCardStatementSnapshot {
        TransactionLogic.creditCardStatement(
            accounts: statementCreditCardAccounts,
            transactions: statementFilteredTransactions,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var effectiveFilters: TransactionFilterState {
        var effective = filterState
        effective.searchText = debouncedSearchText
        effective.isAdjustmentOnly = selectedSegment == .adjustment
        return effective
    }

    private func debtRecords(from records: [TransactionRecordSnapshot]) -> [TransactionRecordSnapshot] {
        records.filter { record in
            guard record.primaryKind == .transfer, record.transferSubtype == .debt else {
                return false
            }

            if let walletID = filterState.walletID {
                return record.sourceWalletID == walletID || record.destinationWalletID == walletID
            }

            return true
        }
    }

    private var hasAdjustments: Bool {
        snapshotRecords.contains { TransactionLogic.isAdjustment($0) }
    }

    private var activeFilterCount: Int {
        var count = 0

        if selectedSegment != nil { count += 1 }
        if filterState.timeScope != .allTime { count += 1 }
        if filterState.walletID != nil { count += 1 }
        if filterState.categoryID != nil { count += 1 }
        if filterState.transferSubtype != nil { count += 1 }
        if filterState.minAmountMinor != nil || filterState.maxAmountMinor != nil { count += 1 }

        return count
    }

    private var activeFilterTint: Color {
        colorScheme == .dark
            ? Color(red: 0.53, green: 0.33, blue: 0.86)
            : MistiaAccent.purple.color
    }

    private var inactiveFilterTint: Color {
        Color(UIColor.secondarySystemGroupedBackground)
    }

    private var activeFilterBadgeTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.53, green: 0.33, blue: 0.86)
            : MistiaAccent.purple.color
    }

    var body: some View {
        let listSnapshot = transactionListSnapshot

        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .standard,
                title: L10n.transactions.transactions.transactions,
                embedsInNavigationStack: false,
                showsLeadingAvatar: false,
                leadingSystemImage: "doc.viewfinder",
                trailingSystemImage: nil,
                onLeadingTap: { destination = .aiBill },
                contentSpacing: 18,
                contentBottomPadding: 150,
                titleDisplayMode: .large,
                pinnedHeader: {
                    VStack(alignment: .leading, spacing: 8) {
                        FamilyContextChipBar()
                            .padding(.horizontal, 18)
                        unifiedFilterRow
                    }
                        .zIndex(99)
                },
                trailingAccessory: {
                    transactionsStatementMenuButton
                    .padding(.trailing, -12)
                }
            ) {
                if !listSnapshot.openDebtPositions.isEmpty {
                    outstandingDebtSection(listSnapshot.openDebtPositions)
                }
                transactionsContent(listSnapshot)
            }
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                prompt: L10n.transactions.transactions.searchTransactionName
            )
            .searchToolbarBehavior(.minimize)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationDestination(item: $destination) { route in
                switch route {
                case .aiBill:
                    AIBillAnalysisView()
                }
            }
        }
        .sheet(item: $shareItem) { item in
            TransactionShareSheet(url: item.url)
        }
        .sheet(item: $editorTarget) { target in
            TransactionEditorSheet(target: target)
                .presentationDetents(target.quickCapture ? [.medium, .large] : [.large])
                .presentationDragIndicator(.hidden)
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        permissionPrompt = nil
                        infoAlert = nil
                    }
                }
            ),
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .info:
                Button(L10n.common.ok) {}
            case .permission(let prompt):
                Button(prompt.actionTitle) {
                    prompt.action()
                }
                Button(L10n.common.cancel, role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .alert(
            L10n.transactions.transactions.couldnTExportStatement,
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.transactions.transactions.close, role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text((exportErrorMessage ?? ""))
        }
        .onChange(of: selectedSegment) { _, _ in
            resetTransactionPage()
        }
        .onChange(of: filterState) { _, _ in
            resetTransactionPage()
        }
        .onChange(of: searchText) { _, newValue in
            scheduleSearchDebounce(newValue)
        }
        .onChange(of: familyContextStore.selectedSubjectUserID) { _, _ in
            resetTransactionPage()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
    }

    private var transactionsStatementMenuButton: some View {
        MistiaHeaderCircleMenu(label: {
            ZStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 15, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.72))
            }
        }) {
            Button(action: { exportStatement(.monthlySummary) }) {
                Label(
                    L10n.transactions.transactions.summaryStatement,
                    systemImage: "doc.text.image"
                )
            }

            Button(action: { exportStatement(.creditCard) }) {
                Label(
                    L10n.transactions.transactions.creditCardStatement,
                    systemImage: "creditcard.and.123"
                )
            }
        }
        .accessibilityLabel(L10n.transactions.transactions.statement)
    }

    private func exportStatement(_ kind: TransactionStatementKind) {
        do {
            let document: TransactionStatementDocument

            switch kind {
            case .monthlySummary:
                document = TransactionLogic.renderMonthlyStatement(monthlyStatement)
            case .creditCard:
                document = TransactionLogic.renderCreditCardStatement(creditCardStatement)
            }

            let url = try TransactionStatementExportSupport.write(document: document)
            shareItem = TransactionShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private var unifiedFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 10) {
                        filterChipsHStack
                    }
                } else {
                    filterChipsHStack
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func filterMenu<Content: View>(
        isActive: Bool,
        @ViewBuilder label: () -> Content,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let menu = Menu {
            content()
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .buttonBorderShape(.capsule)
        .tint(isActive ? activeFilterTint : inactiveFilterTint)

        if isActive {
            menu.buttonStyle(.glassProminent)
                .zIndex(99)
        } else {
            menu.buttonStyle(.glass)
                .zIndex(0)
        }
    }

    private var filterChipsHStack: some View {
        HStack(spacing: 8) {
            if activeFilterCount > 0 {
                filterMenu(isActive: true) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        
                        Text(verbatim: "\(activeFilterCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(activeFilterBadgeTextColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Circle().fill(.white))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                } content: {
                    Text(
                        L10n.transactions.transactions.valueActiveFilters(String(describing: activeFilterCount))
                    )
                    
                    Button(role: .destructive) {
                        withAnimation(.snappy) {
                            selectedSegment = nil
                            filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
                        }
                    } label: {
                        Text(L10n.transactions.transactions.clearAllFilters)
                    }
                }
            }

            filterMenu(isActive: selectedSegment != nil) {
                TransactionToolbarChip(
                    title: selectedSegment?.title ?? L10n.transactions.transactions.type,
                    isActive: selectedSegment != nil,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                Button(L10n.transactions.transactions.all) {
                    withAnimation(.snappy) {
                        selectedSegment = nil
                    }
                }
                ForEach(TransactionSegment.allCases, id: \.self) { segment in
                    if segment != .adjustment || hasAdjustments {
                        Button(segment.title) {
                            withAnimation(.snappy) {
                                selectedSegment = segment
                            }
                        }
                    }
                }
            }

            filterMenu(isActive: filterState.timeScope != .allTime) {
                TransactionToolbarChip(
                    title: filterState.timeScope == .allTime ? L10n.transactions.transactions.time : filterState.timeScope.title,
                    isActive: filterState.timeScope != .allTime,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                ForEach(TransactionTimeScope.allCases, id: \.self) { scope in
                    Button(scope.title) {
                        withAnimation(.snappy) {
                            filterState.timeScope = scope
                        }
                    }
                }
            }

            filterMenu(isActive: filterState.walletID != nil) {
                let title = activeWallets.first { $0.id == filterState.walletID }?.name ?? L10n.transactions.transactions.wallet
                TransactionToolbarChip(
                    title: title,
                    isActive: filterState.walletID != nil,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                Button(L10n.transactions.transactions.all) {
                    withAnimation(.snappy) {
                        filterState.walletID = nil
                    }
                }
                ForEach(activeWallets, id: \.id) { wallet in
                    Button(wallet.name) {
                        withAnimation(.snappy) {
                            filterState.walletID = wallet.id
                        }
                    }
                }
            }

            if selectedSegment?.kind != .transfer && selectedSegment != .adjustment {
                filterMenu(isActive: filterState.categoryID != nil) {
                    let title = activeCategories.first { $0.id == filterState.categoryID }?.localizedDisplayName
                        ?? L10n.transactions.transactions.category
                    TransactionToolbarChip(
                        title: title,
                        isActive: filterState.categoryID != nil,
                        trailingIcon: "chevron.up.chevron.down"
                    )
                } content: {
                    Button(L10n.transactions.transactions.all) {
                        withAnimation(.snappy) {
                            filterState.categoryID = nil
                        }
                    }
                    ForEach(activeCategorySections) { section in
                        Menu {
                            Section() {
                                Button(L10n.transactions.transactions.all) {
                                    withAnimation(.snappy) {
                                        filterState.categoryID = section.parent.id
                                    }
                                }
                                ForEach(section.children) { category in
                                    Button(category.localizedDisplayName) {
                                        withAnimation(.snappy) {
                                            filterState.categoryID = category.id
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(section.parent.localizedDisplayName)
                        }
                    }
                }
            }
        }
    }

    private func outstandingDebtSection(_ positions: [CounterpartyDebtSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.transactions.transactions.openDebts)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(positions) { position in
                        OutstandingDebtChip(position: position)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func transactionsContent(_ snapshot: TransactionsListSnapshot) -> some View {
        if snapshot.activeTransactionCount == 0 {
            TransactionsPlaceholderCard(
                title: L10n.transactions.transactions.noTransactionsYet,
                message: L10n.transactions.transactions.whenYouAddAnExpenseIncomeTransfer
            )
        } else if snapshot.sections.isEmpty {
            TransactionsPlaceholderCard(
                title: L10n.transactions.transactions.noMatchingResults,
                message: L10n.transactions.transactions.tryAdjustingTheTimeRangeWalletFilters
            )
        } else {
            ForEach(snapshot.sections) { section in
                TransactionSectionCard(
                    section: section,
                    transactionsByID: snapshot.transactionsByID,
                    transactionAuditMap: snapshot.transactionAuditMap,
                    walletOwnerMap: snapshot.walletOwnerMap,
                    transactionOwnerMap: snapshot.transactionOwnerMap
                ) { transaction in
                    openTransactionEditorIfAllowed(transaction)
                }
            }

            if snapshot.hasMoreRows {
                TransactionListPagingSentinel()
                    .onAppear {
                        loadMoreTransactionsIfNeeded(totalVisibleCount: snapshot.visibleRecordCount)
                    }
            }
        }
    }

    private func resetTransactionPage() {
        guard visibleTransactionLimit != TransactionsListPaging.initialLimit else { return }
        visibleTransactionLimit = TransactionsListPaging.initialLimit
    }

    private func loadMoreTransactionsIfNeeded(totalVisibleCount: Int) {
        guard visibleTransactionLimit < totalVisibleCount else { return }
        visibleTransactionLimit = min(
            visibleTransactionLimit + TransactionsListPaging.increment,
            totalVisibleCount
        )
    }

    private func scheduleSearchDebounce(_ value: String) {
        searchDebounceTask?.cancel()

        if value.isEmpty {
            debouncedSearchText = ""
            resetTransactionPage()
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            debouncedSearchText = value
            resetTransactionPage()
        }
    }

    private func openTransactionEditorIfAllowed(_ transaction: LedgerTransaction) {
        if transaction.primaryKind == .transfer,
           transaction.transferSubtype == .familyTransfer {
            editorTarget = TransactionEditorTarget(transaction: transaction)
            return
        }

        guard let ownerUserID = transactionOwnerUserID(for: transaction) else {
            editorTarget = TransactionEditorTarget(transaction: transaction)
            return
        }
        guard ownerUserID != sessionStore.activeLocalProfileUserID else {
            editorTarget = TransactionEditorTarget(transaction: transaction)
            return
        }
        guard familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .transaction) else {
            presentTransactionEditPermissionPrompt(transaction, ownerUserID: ownerUserID)
            return
        }
        editorTarget = TransactionEditorTarget(transaction: transaction)
    }

    private func transactionOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? ownerUserID(forWalletID: transaction.sourceWallet?.id)
            ?? ownerUserID(forWalletID: transaction.destinationWallet?.id)
            ?? familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
    }

    private func ownerUserID(forWalletID walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID]
    }

    private func presentTransactionEditPermissionPrompt(_ transaction: LedgerTransaction, ownerUserID: UUID) {
        let resourceName = transaction.title.nilIfBlank
            ?? L10n.transactions.transactions.transaction
        let isPending = familyContextStore.hasPendingPermissionRequest(
            ownerUserID: ownerUserID,
            resourceType: .transaction,
            resourceID: nil,
            scope: .edit
        )
        permissionPrompt = TransactionsPermissionPrompt(
            title: L10n.transactions.transactions.noTransactionEditAccess,
            message: L10n.transactions.transactions.youDoNotHavePermissionToEdit,
            actionTitle: isPending
                ? L10n.transactions.transactions.editRequestSent
                : L10n.transactions.transactions.requestEditAccess
        ) {
            Task { @MainActor in
                if isPending {
                    let isApproved = await familyContextStore.refreshPermissionGrant(
                        ownerUserID: ownerUserID,
                        resourceType: .transaction,
                        resourceID: nil,
                        scope: .edit,
                        sessionStore: sessionStore
                    )
                    if isApproved {
                        permissionPrompt = nil
                        editorTarget = TransactionEditorTarget(transaction: transaction)
                    }
                    return
                }

                let didSend = await familyContextStore.requestPermission(
                    resourceType: .transaction,
                    resourceID: nil,
                    ownerUserID: ownerUserID,
                    scope: .edit,
                    resourceName: resourceName,
                    sessionStore: sessionStore
                )
                permissionPrompt = nil
                try? await Task.sleep(nanoseconds: 150_000_000)
                infoAlert = TransactionsInfoAlert(
                    title: didSend
                        ? L10n.transactions.transactions.requestSent
                        : L10n.transactions.transactions.couldnTSend,
                    message: didSend
                        ? L10n.transactions.transactions.thePermissionRequestWasSentToThe
                        : (familyContextStore.lastErrorMessage ?? L10n.transactions.transactions.couldnTSendTheRequestRightNow)
                )
            }
        }
    }
}

private struct TransactionLiveSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: TransactionSummarySnapshot

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(
            cornerRadius: 24,
            tint: cardTint,
            padding: 18
        ) {
            HStack(alignment: .top, spacing: 14) {
                TransactionSummaryMetric(
                    title: L10n.transactions.transactions.expense,
                    value: summary.expenseMinor.formattedCurrency(code: "JPY"),
                    tint: MistiaAccent.expense.color
                )

                Spacer(minLength: 4)

                TransactionSummaryMetric(
                    title: L10n.transactions.transactions.income,
                    value: summary.incomeMinor.formattedCurrency(code: "JPY"),
                    tint: MistiaAccent.income.color
                )

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(verbatim: "\(summary.totalCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(
                        summary.draftCount == 0
                            ? L10n.transactions.transactions.transactions
                            : L10n.transactions.transactions.valueDrafts(String(describing: summary.draftCount))
                    )
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TransactionListPagingSentinel: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .accessibilityLabel(L10n.transactions.transactions.loadingMoreTransactions)
    }
}

private struct TransactionSummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct TransactionSectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FamilyContextStore.self) private var familyContextStore
    let section: TransactionSectionSnapshot
    let transactionsByID: [UUID: LedgerTransaction]
    let transactionAuditMap: [UUID: TransactionAuditRecord]
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let onSelect: (LedgerTransaction) -> Void

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(section.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text(
                    L10n.transactions.transactions.valueItems(String(describing: section.rows.count))
                )
                    .lineLimit(1)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            MistiaBlockCard(
                cornerRadius: 22,
                tint: cardTint,
                padding: 0
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if let transaction = transactionsByID[row.id] {
                            Button {
                                onSelect(transaction)
                            } label: {
                                TransactionRow(
                                    record: row,
                                    transaction: transaction,
                                    auditRecord: transactionAuditMap[transaction.id],
                                    walletOwnerMap: walletOwnerMap,
                                    transactionOwnerMap: transactionOwnerMap,
                                    familyContextStore: familyContextStore
                                )
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                        }

                        if index < section.rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    @Environment(\.colorScheme) private var 
    colorScheme: ColorScheme

    let record: TransactionRecordSnapshot
    let transaction: LedgerTransaction
    let auditRecord: TransactionAuditRecord?
    let walletOwnerMap: [UUID: UUID]
    let transactionOwnerMap: [UUID: UUID]
    let familyContextStore: FamilyContextStore

    private var icon: String {
        switch record.primaryKind {
        case .expense, .income:
            transaction.category?.iconSymbolName ?? record.primaryKind.financeIconToken
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                TransactionTransferSubtype.internalTransfer.financeIconToken
            case .familyTransfer:
                TransactionTransferSubtype.familyTransfer.financeIconToken
            case .debt:
                TransactionTransferSubtype.debt.financeIconToken
            case nil:
                record.primaryKind.financeIconToken
            }
        }
    }

    private var iconColor: Color {
        MistiaAccent.purple.color
    }

    private var title: String {
        if let trimmed = record.title.nilIfBlank {
            return trimmed
        }

        switch record.primaryKind {
        case .expense:
            return transaction.category?.localizedDisplayName
                ?? L10n.transactions.transactions.expenseNeedsDetails
        case .income:
            return transaction.category?.localizedDisplayName
                ?? L10n.transactions.transactions.incomeNeedsDetails
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                return L10n.transactions.transactions.internalTransfer
            case .familyTransfer:
                return L10n.shared.corelogic.financeenums.family
            case .debt:
                return record.debtIntent?.title ?? L10n.transactions.transactions.debt
            case nil:
                return L10n.transactions.transactions.transferNeedsDetails
            }
        }
    }

    private var subtitle: String {
        if record.entryStatus == .draft {
            return L10n.transactions.transactions.draftTapToComplete
        }

        switch record.primaryKind {
        case .expense, .income:
            let wallet = transaction.sourceWallet?.name ?? L10n.transactions.transactions.noWalletSelected
            let category = transaction.category?.localizedDisplayName ?? L10n.transactions.transactions.noCategorySelected
            return "\(wallet) • \(category)"
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                let source = transaction.sourceWallet?.name ?? L10n.transactions.transactions.source
                let destination = transaction.destinationWallet?.name ?? L10n.transactions.transactions.destination
                return "\(source) → \(destination)"
            case .familyTransfer:
                if let note = record.note?.nilIfBlank {
                    return note
                }
                let source = transaction.sourceWallet?.name ?? L10n.transactions.transactions.source
                if let destination = transaction.destinationWallet?.name {
                    return "\(source) → \(destination)"
                }
                return source
            case .debt:
                let wallet = transaction.sourceWallet?.name ?? L10n.transactions.transactions.noWalletSelected
                let person = transaction.counterpartyName ?? L10n.transactions.transactions.unknownName
                let intent = record.debtIntent?.title ?? L10n.transactions.transactions.debt
                return "\(person) • \(intent) • \(wallet)"
            case nil:
                return L10n.transactions.transactions.transfer
            }
        }
    }

    private var auditSubtitle: String? {
        let canonicalOwnerUserID = transactionOwnerMap[transaction.id] ?? ownerUserID(for: transaction.sourceWallet?.id)
        let createdByUserID = auditRecord?.createdByUserID ?? canonicalOwnerUserID

        var parts: [String] = []

        if let createdByUserID,
           createdByUserID != canonicalOwnerUserID {
            let createdByName = familyContextStore.displayName(for: createdByUserID)
                ?? L10n.transactions.transactions.aFamilyMember
            return L10n.transactions.transactions.createdByValue(String(describing: createdByName))
        }

        if let sourceWallet = transaction.sourceWallet,
           let sourceOwnerUserID = ownerUserID(for: sourceWallet.id),
           sourceOwnerUserID != createdByUserID,
           let ownerName = familyContextStore.displayName(for: sourceOwnerUserID) {
            parts.append("\(sourceWallet.name) • \(ownerName)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var cashflowColor: Color {
        if TransactionLogic.isCreditCardPayment(record) {
            return .white
        }

        switch record.primaryKind {
        case .expense:
            return MistiaAccent.expense.color
        case .income:
            return MistiaAccent.income.color
        case .transfer:
            if record.transferSubtype == .familyTransfer {
                let cashflow = TransactionLogic.cashflowAmount(for: record)
                if cashflow > 0 {
                    return MistiaAccent.income.color
                }
                if cashflow < 0 {
                    return MistiaAccent.expense.color
                }
            }
            return colorScheme == .dark ? .white : MistiaAccent.transfer.color
        }
    }

    private var displayAmount: String {
        let raw = record.amountMinor.formattedCurrency(code: "JPY")

        if TransactionLogic.isCreditCardPayment(record) {
            return raw
        }

        switch record.primaryKind {
        case .expense:
            return "-" + raw
        case .income:
            return "+" + raw
        case .transfer:
            let cashflow = TransactionLogic.cashflowAmount(for: record)
            if cashflow > 0 {
                return "+" + raw
            }
            if cashflow < 0 {
                return "-" + raw
            }
            return raw
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            TransactionIconTile(icon: icon, tint: iconColor)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if record.primaryKind == .transfer, let subtype = record.transferSubtype,
                       subtype == .debt {
                        TransactionMiniBadge(
                            title: subtype.title,
                            tint: Color(red: 0.29, green: 0.56, blue: 0.96)
                        )
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let auditSubtitle {
                    Text(auditSubtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text(displayAmount)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(cashflowColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }

    private func ownerUserID(for walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID]
    }
}

private struct TransactionIconTile: View {
    let icon: String
    let tint: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: tint, size: 34)
    }
}

private struct TransactionMiniBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                MistiaCapsuleGlassBackground(tint: tint.opacity(0.12))
            }
    }
}


private struct TransactionToolbarChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isActive: Bool
    let trailingIcon: String?

    private var foregroundColor: Color {
        if isActive {
            return .white
        }

        if colorScheme == .dark {
            return Color.white.opacity(0.92)
        }

        return Color.black.opacity(0.74)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
            
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(foregroundColor)
        .animation(nil, value: title)
        .animation(nil, value: isActive)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}

private struct OutstandingDebtChip: View {
    let position: CounterpartyDebtSnapshot

    private var tint: Color {
        position.isReceivable
            ? MistiaAccent.income.color
            : MistiaAccent.expense.color
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 22, tint: tint.opacity(0.14), padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(position.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(
                    position.isReceivable
                        ? L10n.transactions.transactions.theyOweYou
                        : L10n.transactions.transactions.youOwe
                )
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(abs(position.netMinor).formattedCurrency(code: "JPY"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

private struct TransactionsPlaceholderCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let symbols = ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
    let accent = MistiaAccent.purple.color

    private var buttonForeground: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : accent
    }

    private var symbolBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.10
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 14) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                        ZStack {
                            Circle()
                                .fill(accent.opacity(symbolBackgroundOpacity + Double(index) * 0.025))

                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(buttonForeground)
                        }
                        .frame(width: 34, height: 34)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func currencyInputToMinorUnits(currencyCode: String) -> Int64 {
        let sanitized = replacingOccurrences(
            of: "[^0-9-]",
            with: "",
            options: .regularExpression
        )

        guard let value = Int64(sanitized) else { return 0 }

        if currencyCode.uppercased() == "JPY" {
            return value
        }

        return value
    }
}

private extension Int64 {
    var positiveOrNil: Int64? {
        self > 0 ? self : nil
    }
}
