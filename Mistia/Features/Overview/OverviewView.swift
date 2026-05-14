import Charts
import SwiftData
import SwiftUI

private enum OverviewNavigationDestination: String, Identifiable {
    case profile
    case notificationCenter

    var id: String { rawValue }
}

private struct OverviewExpenseDaySelection: Identifiable, Equatable {
    let date: Date

    var id: Date { date }
}

private enum OverviewHeroChartMode: String, CaseIterable, Identifiable {
    case day
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            mistiaLocalized(vi: "Ngày", en: "Day", ja: "日")
        case .category:
            mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ")
        }
    }
}

private struct OverviewPermissionPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
}

struct OverviewView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgets: [BudgetPlan]
    @Query(filter: #Predicate<RecurringBillPlan> { $0.deletedAt == nil })
    private var storedBills: [RecurringBillPlan]
    @Query(filter: #Predicate<InstallmentPlan> { $0.deletedAt == nil })
    private var storedInstallments: [InstallmentPlan]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var storedTransactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]

    private struct StatementTarget: Identifiable, Hashable {
        let wallet: LedgerWallet
        let month: Date?
        var id: String { "\(wallet.id.uuidString)-\(month?.timeIntervalSince1970 ?? 0)" }
    }

    @State private var editorTarget: TransactionEditorTarget?
    @State private var selectedExpenseDay: OverviewExpenseDaySelection?
    @State private var destination: OverviewNavigationDestination?
    @State private var statementTarget: StatementTarget?
    @State private var duePaymentTarget: DuePaymentSheetTarget?
    @State private var permissionPrompt: OverviewPermissionPrompt?

    private var currentMonth: Date {
        PlanningLogic.startOfMonth(for: .now, calendar: calendar)
    }

    private var transactionsByID: [UUID: LedgerTransaction] {
        Dictionary(
            visibleTransactions
                .filter { $0.deletedAt == nil && !$0.isArchived }
                .map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        )
    }

    private var transactionOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
    }

    private var transactionRecords: [TransactionRecordSnapshot] {
        visibleTransactions.map(\.planningRecordSnapshot)
    }

    private var overviewTransactions: [OverviewTransactionSnapshot] {
        visibleTransactions.map(\.overviewSnapshot)
    }

    private var walletSnapshots: [OverviewWalletSnapshot] {
        visibleWallets.compactMap(\.overviewWalletSnapshot)
    }

    private var activeBudgetPlans: [BudgetPlanSnapshot] {
        visibleBudgets
            .filter {
                !$0.isArchived
                    && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == currentMonth
            }
            .map { $0.planningSnapshot(calendar: calendar) }
    }

    private var occurrenceSnapshots: [PlanningDueOccurrenceSnapshot] {
        visibleOccurrences.map(\.planningSnapshot)
    }

    private var planningCreditCardAccounts: [PlanningCreditCardAccountSnapshot] {
        storedWallets.compactMap { $0.planningCreditCardSnapshot(records: transactionRecords) }
    }

    private var creditCardDueItems: [PlanningCreditCardDueSnapshot] {
        PlanningLogic.creditCardDueItems(
            accounts: planningCreditCardAccounts,
            records: transactionRecords,
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var recurringBillDueItems: [PlanningRecurringDueSnapshot] {
        PlanningLogic.recurringBillDueItems(
            bills: visibleBills
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            calendar: calendar
        )
    }

    private var installmentDueItems: [PlanningRecurringDueSnapshot] {
        PlanningLogic.installmentDueItems(
            plans: visibleInstallments
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: currentMonth,
            calendar: calendar
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

    private var visibleTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForFinancial(
            storedTransactions,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleBudgets: [BudgetPlan] {
        FamilyScopedData.visible(
            storedBudgets,
            entity: .budgetPlan,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleBills: [RecurringBillPlan] {
        FamilyScopedData.visible(
            storedBills,
            entity: .recurringBillPlan,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleInstallments: [InstallmentPlan] {
        FamilyScopedData.visible(
            storedInstallments,
            entity: .installmentPlan,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var visibleOccurrences: [DueOccurrenceRecord] {
        FamilyScopedData.visible(
            storedOccurrences,
            entity: .dueOccurrenceRecord,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var dashboardSnapshot: OverviewDashboardSnapshot {
        OverviewLogic.dashboard(
            wallets: walletSnapshots,
            transactionRecords: transactionRecords,
            transactions: overviewTransactions,
            budgets: activeBudgetPlans,
            creditCardDues: creditCardDueItems,
            recurringDues: recurringBillDueItems + installmentDueItems,
            currencyCode: currencyCode,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var postedExpenseTransactionsByDay: [Date: [LedgerTransaction]] {
        Dictionary(
            grouping: visibleTransactions.filter { transaction in
                transaction.deletedAt == nil
                    && !transaction.isArchived
                    && transaction.entryStatus == .posted
                    && TransactionLogic.isExpenseSpending(transaction.planningRecordSnapshot)
            },
            by: { calendar.startOfDay(for: $0.occurredAt) }
        )
        .mapValues { transactions in
            transactions.sorted(by: sortTransactionsByRecency)
        }
    }

    var body: some View {
        let dashboardSnapshot = self.dashboardSnapshot
        let transactionsByID = self.transactionsByID
        let postedExpenseTransactionsByDay = self.postedExpenseTransactionsByDay

        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .standard,
                title: mistiaLocalized(vi: "Tổng quan", en: "Overview", ja: "ホーム"),
                embedsInNavigationStack: false,
                leadingInitials: sessionStore.summary?.initials ?? "MI",
                leadingAvatarURL: sessionStore.summary?.avatarURL,
                trailingSystemImage: nil,
                onLeadingTap: { destination = .profile },
                contentSpacing: 18,
                titleDisplayMode: .large,
                pinnedHeader: { EmptyView() },
                trailingAccessory: {
                    MistiaNotificationBellButton {
                        destination = .notificationCenter
                    }
                }
            ) {
                FamilyContextChipBar()
                OverviewHeroCard(
                    snapshot: dashboardSnapshot.hero,
                    isSheetPresented: selectedExpenseDay != nil,
                    onOpenExpenseDay: { date in
                        openExpenseDay(date, transactionsByDay: postedExpenseTransactionsByDay)
                    }
                )
                if !dashboardSnapshot.budgetAlerts.isEmpty {
                    BudgetFocusSection(rows: dashboardSnapshot.budgetAlerts)
                }
                if !dashboardSnapshot.dueAlerts.isEmpty {
                    UpcomingBillsSection(rows: dashboardSnapshot.dueAlerts) { row in
                        routeDueAlertTap(row)
                    }
                }
                RecentTransactionsSection(rows: dashboardSnapshot.recentTransactions) { row in
                    guard let transaction = transactionsByID[row.id] else { return }
                    presentEditor(for: transaction)
                }
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .profile:
                    ManagementAccountView()
                case .notificationCenter:
                    NotificationCenterView()
                }
            }
            .navigationDestination(item: $statementTarget) { target in
                ManagementCreditCardStatementView(wallet: target.wallet, initialMonth: target.month)
            }
        }
        .sheet(item: $selectedExpenseDay) { selection in
            OverviewDayTransactionsSheet(
                day: selection.date,
                transactions: postedExpenseTransactionsByDay[selection.date] ?? [],
                currencyCode: currencyCode,
                onSelectTransaction: presentEditorFromDaySheet
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $editorTarget) { target in
            TransactionEditorSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $duePaymentTarget) { target in
            DuePaymentSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .alert(item: $permissionPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text(prompt.actionTitle)) {
                    prompt.action()
                },
                secondaryButton: .cancel(Text(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル")))
            )
        }
        .task {
            try? MistiaOverviewDebugFixtures.seedCategoryChartDataIfNeeded(
                modelContext: modelContext,
                sessionStore: sessionStore
            )
        }
    }

    private func openExpenseDay(
        _ date: Date,
        transactionsByDay: [Date: [LedgerTransaction]]
    ) {
        let day = calendar.startOfDay(for: date)

        guard let transactions = transactionsByDay[day], !transactions.isEmpty else {
            return
        }

        selectedExpenseDay = OverviewExpenseDaySelection(date: day)
    }

    private func presentEditor(for transaction: LedgerTransaction) {
        guard canEditTransaction(transaction) else {
            presentTransactionEditPermissionPrompt(transaction)
            return
        }
        editorTarget = TransactionEditorTarget(transaction: transaction)
    }

    private func presentEditorFromDaySheet(_ transaction: LedgerTransaction) {
        selectedExpenseDay = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if canEditTransaction(transaction) {
                editorTarget = TransactionEditorTarget(transaction: transaction)
            } else {
                presentTransactionEditPermissionPrompt(transaction)
            }
        }
    }

    private func transactionOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
    }

    private func canEditTransaction(_ transaction: LedgerTransaction) -> Bool {
        guard let ownerUserID = transactionOwnerUserID(for: transaction) else { return false }
        return ownerUserID == sessionStore.activeLocalProfileUserID
            || familyContextStore.canEdit(ownerUserID: ownerUserID, resourceType: .transaction)
    }

    private func presentTransactionEditPermissionPrompt(_ transaction: LedgerTransaction) {
        guard let ownerUserID = transactionOwnerUserID(for: transaction),
              ownerUserID != sessionStore.activeLocalProfileUserID else { return }
        permissionPrompt = OverviewPermissionPrompt(
            title: mistiaLocalized(vi: "Chưa có quyền chỉnh sửa giao dịch", en: "No transaction edit access", ja: "取引編集権限がありません"),
            message: mistiaLocalized(
                vi: "Bạn chưa có quyền chỉnh sửa giao dịch của thành viên này.",
                en: "You do not have permission to edit this member's transactions.",
                ja: "このメンバーの取引を編集する権限がありません。"
            ),
            actionTitle: mistiaLocalized(vi: "Yêu cầu quyền chỉnh sửa", en: "Request edit access", ja: "編集権限をリクエスト")
        ) {
            sendPermissionRequest(
                resourceType: .transaction,
                resourceID: nil,
                ownerUserID: ownerUserID,
                scope: .edit,
                resourceName: mistiaLocalized(vi: "giao dịch", en: "transactions", ja: "取引")
            )
        }
    }

    private func sendPermissionRequest(
        resourceType: MistiaFamilyNotificationResourceType,
        resourceID: UUID?,
        ownerUserID: UUID,
        scope: MistiaFamilyPermissionScope,
        resourceName: String
    ) {
        Task { @MainActor in
            _ = await familyContextStore.requestPermission(
                resourceType: resourceType,
                resourceID: resourceID,
                ownerUserID: ownerUserID,
                scope: scope,
                resourceName: resourceName,
                sessionStore: sessionStore
            )
        }
    }

    private func sortTransactionsByRecency(_ lhs: LedgerTransaction, _ rhs: LedgerTransaction) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }

        return lhs.createdAt > rhs.createdAt
    }

    private func routeDueAlertTap(_ alert: OverviewDueAlertSnapshot) {
        switch alert.sourceKind {
        case .creditCard:
            if let walletID = alert.sourceID,
               let wallet = storedWallets.first(where: { $0.id == walletID }) {
                let month = PlanningLogic.month(from: alert.dueMonthKey, calendar: calendar) ?? alert.dueDate
                statementTarget = StatementTarget(
                    wallet: wallet,
                    month: PlanningLogic.startOfMonth(for: month, calendar: calendar)
                )
            }
        case .recurringBill, .installment:
            guard let sourceID = alert.sourceID else { return }
            duePaymentTarget = DuePaymentSheetTarget(
                sourceKind: alert.sourceKind,
                sourceID: sourceID,
                dueMonthKey: alert.dueMonthKey,
                dueDate: alert.dueDate,
                requiresAmountInput: alert.requiresAmountInput,
                currencyCode: alert.currencyCode,
                name: alert.name
            )
        }
    }
}

private enum MistiaOverviewDebugFixtures {
    static var startsInCategoryMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MISTIA_OVERVIEW_DEBUG_CATEGORY_MODE"] == "1"
        #else
        false
        #endif
    }

    static var startsInFirstCategoryDrilldown: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MISTIA_OVERVIEW_DEBUG_DRILLDOWN_FIRST"] == "1"
        #else
        false
        #endif
    }

    static func seedCategoryChartDataIfNeeded(
        modelContext: ModelContext,
        sessionStore: SessionStore
    ) throws {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["MISTIA_OVERVIEW_DEBUG_SAMPLE_DATA"] == "1" else {
            return
        }

        let wallet = try sampleWallet(in: modelContext)
        let grocery = try MistiaBootstrap.ensureSystemCategory(.grocery, modelContext: modelContext)
        let dineOut = try MistiaBootstrap.ensureSystemCategory(.dineOut, modelContext: modelContext)
        let rent = try MistiaBootstrap.ensureSystemCategory(.rent, modelContext: modelContext)
        let medicine = try MistiaBootstrap.ensureSystemCategory(.medicine, modelContext: modelContext)
        let calendar = MistiaCalendar.current
        let currentMonth = PlanningLogic.startOfMonth(for: .now, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        let existingTransactionIDs = Set(try modelContext.fetch(FetchDescriptor<LedgerTransaction>()).map(\.id))

        let samples: [(id: UUID, title: String, amountMinor: Int64, occurredAt: Date, category: TransactionCategory)] = [
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!,
                "Debug groceries",
                12_500,
                sampleDate(dayOffset: 3, from: currentMonth, calendar: calendar),
                grocery
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!,
                "Debug dinner",
                8_200,
                sampleDate(dayOffset: 8, from: currentMonth, calendar: calendar),
                dineOut
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E003")!,
                "Debug rent",
                72_000,
                sampleDate(dayOffset: 1, from: currentMonth, calendar: calendar),
                rent
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E004")!,
                "Debug medicine",
                4_600,
                sampleDate(dayOffset: 15, from: currentMonth, calendar: calendar),
                medicine
            ),
            (
                UUID(uuidString: "00000000-0000-0000-0000-00000000E005")!,
                "Debug last month groceries",
                9_400,
                sampleDate(dayOffset: 5, from: previousMonth, calendar: calendar),
                grocery
            )
        ]

        var didInsert = false
        let ownerUserID = sessionStore.activeLocalProfileUserID
        if let ownerUserID {
            try MistiaRecordOwnershipStore.upsert(
                entity: .wallet,
                recordID: wallet.id,
                ownerUserID: ownerUserID,
                context: modelContext
            )
        }

        for sample in samples where !existingTransactionIDs.contains(sample.id) {
            modelContext.insert(
                LedgerTransaction(
                    id: sample.id,
                    primaryKind: .expense,
                    title: sample.title,
                    amountMinor: sample.amountMinor,
                    occurredAt: sample.occurredAt,
                    createdAt: sample.occurredAt,
                    updatedAt: sample.occurredAt,
                    sourceWallet: wallet,
                    category: sample.category
                )
            )
            if let ownerUserID {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction,
                    recordID: sample.id,
                    ownerUserID: ownerUserID,
                    context: modelContext
                )
            }
            didInsert = true
        }

        if didInsert || ownerUserID != nil {
            try modelContext.save()
        }
        #endif
    }

    #if DEBUG
    private static func sampleWallet(in modelContext: ModelContext) throws -> LedgerWallet {
        let walletID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
        if let existing = try modelContext.fetch(FetchDescriptor<LedgerWallet>())
            .first(where: { $0.id == walletID }) {
            return existing
        }

        let wallet = LedgerWallet(
            id: walletID,
            name: "Mistia Demo",
            kind: .cash,
            iconSymbolName: LedgerWalletKind.cash.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.cash.defaultColorHex,
            currencyCode: "JPY",
            openingBalanceMinor: 500_000,
            sortOrder: -1
        )
        modelContext.insert(wallet)
        return wallet
    }

    private static func sampleDate(
        dayOffset: Int,
        from monthStart: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: monthStart) ?? monthStart
    }
    #endif
}

private struct OverviewHeroCard: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedWeekStart: Date
    @State private var selectedCategoryMonth: Date
    @State private var chartMode: OverviewHeroChartMode
    @State private var chartDismissToken: Int = 0
    @State private var categoryChartHeight: CGFloat

    let snapshot: OverviewHeroSnapshot
    let isSheetPresented: Bool
    let onOpenExpenseDay: (Date) -> Void

    init(
        snapshot: OverviewHeroSnapshot,
        isSheetPresented: Bool,
        onOpenExpenseDay: @escaping (Date) -> Void
    ) {
        self.snapshot = snapshot
        self.isSheetPresented = isSheetPresented
        self.onOpenExpenseDay = onOpenExpenseDay
        _selectedWeekStart = State(initialValue: snapshot.currentWeekStart)
        _selectedCategoryMonth = State(
            initialValue: snapshot.categoryMonthPages.last?.monthStart
                ?? PlanningLogic.startOfMonth(for: .now)
        )
        _chartMode = State(initialValue: MistiaOverviewDebugFixtures.startsInCategoryMode ? .category : .day)
        _categoryChartHeight = State(initialValue: MistiaCategorySpendingChartView.estimatedHeight(visibleSliceCount: 3))
    }

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.024) : .white.opacity(0.16)
    }

    private var insetSurface: Color {
        colorScheme == .dark ? .white.opacity(0.035) : .black.opacity(0.03)
    }

    private var activeWeek: OverviewWeekSpendingSnapshot {
        snapshot.weekPages.first(where: { $0.weekStart == selectedWeekStart })
            ?? snapshot.weekPages.last
            ?? OverviewWeekSpendingSnapshot(
                weekStart: snapshot.currentWeekStart,
                weekEnd: snapshot.currentWeekStart,
                title: mistiaLocalized(vi: "Tuần này", en: "This week", ja: "今週"),
                isCurrentWeek: true,
                points: []
            )
    }

    private var activeCategoryMonth: OverviewCategorySpendingMonthSnapshot {
        snapshot.categoryMonthPages.first(where: { $0.monthStart == selectedCategoryMonth })
            ?? snapshot.categoryMonthPages.last
            ?? OverviewCategorySpendingMonthSnapshot(
                monthStart: PlanningLogic.startOfMonth(for: .now, calendar: calendar),
                title: MistiaDateFormatting.monthYearString(for: .now, calendar: calendar),
                currencyCode: snapshot.currencyCode,
                slices: []
            )
    }

    private var chartTitle: String {
        switch chartMode {
        case .day:
            mistiaLocalized(vi: "Chi tiêu theo ngày", en: "Daily spending", ja: "日別支出")
        case .category:
            mistiaLocalized(vi: "Chi tiêu theo danh mục", en: "Spending by category", ja: "カテゴリ別支出")
        }
    }

    private var chartSubtitle: String {
        switch chartMode {
        case .day:
            activeWeek.title
        case .category:
            activeCategoryMonth.title
        }
    }

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: cardTint
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(mistiaLocalized(vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(snapshot.totalAssetBalanceMinor.formattedCurrency(code: snapshot.currencyCode))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissChartSelection() }

                HStack(spacing: 14) {
                    SummaryMetricColumn(
                        title: mistiaLocalized(vi: "Thu tháng này", en: "Income this month", ja: "今月の収入"),
                        value: snapshot.incomeThisMonthMinor.formattedCurrency(code: snapshot.currencyCode),
                        accent: Color(hex: "#2DAA9E")
                    )

                    Divider()
                        .frame(height: 26)

                    SummaryMetricColumn(
                        title: mistiaLocalized(vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出"),
                        value: snapshot.expenseThisMonthMinor.formattedCurrency(code: snapshot.currencyCode),
                        accent: Color(hex: "#F45C7E")
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissChartSelection() }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chartTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(chartSubtitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { dismissChartSelection() }

                    Picker("", selection: $chartMode) {
                        ForEach(OverviewHeroChartMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("overview.hero.chart.mode")

                    if chartMode == .day {
                        TabView(selection: $selectedWeekStart) {
                            ForEach(snapshot.weekPages) { week in
                                OverviewWeekSpendingChart(
                                    week: week,
                                    currencyCode: snapshot.currencyCode,
                                    insetSurface: insetSurface,
                                    isVisible: selectedWeekStart == week.weekStart && !isSheetPresented,
                                    dismissToken: chartDismissToken,
                                    onOpenExpenseDay: onOpenExpenseDay
                                )
                                .tag(week.weekStart)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 154)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        TabView(selection: $selectedCategoryMonth) {
                            ForEach(snapshot.categoryMonthPages) { month in
                                MistiaCategorySpendingChartView(
                                    snapshot: month,
                                    resetKey: "overview-\(month.id)",
                                    startsInFirstDrilldown: MistiaOverviewDebugFixtures.startsInFirstCategoryDrilldown,
                                    accessibilityPrefix: "overview.category",
                                    onPreferredHeightChange: { height in
                                        guard month.monthStart == selectedCategoryMonth else { return }

                                        withAnimation(.snappy(duration: 0.18)) {
                                            categoryChartHeight = height
                                        }
                                    }
                                )
                                .tag(month.monthStart)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: categoryChartHeight)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
        }
        .onChange(of: snapshot.weekPages.map(\.weekStart)) { _, weekStarts in
            if !weekStarts.contains(selectedWeekStart) {
                selectedWeekStart = snapshot.currentWeekStart
            }
        }
        .onChange(of: snapshot.categoryMonthPages.map(\.monthStart)) { _, monthStarts in
            if !monthStarts.contains(selectedCategoryMonth) {
                selectedCategoryMonth = snapshot.categoryMonthPages.last?.monthStart
                    ?? PlanningLogic.startOfMonth(for: .now, calendar: calendar)
            }
        }
        .onChange(of: chartMode) { _, _ in
            dismissChartSelection()
        }
    }

    private func dismissChartSelection() {
        chartDismissToken += 1
    }
}

private struct OverviewWeekSpendingChart: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    let week: OverviewWeekSpendingSnapshot
    let currencyCode: String
    let insetSurface: Color
    let isVisible: Bool
    let dismissToken: Int
    let onOpenExpenseDay: (Date) -> Void

    private var chartMax: Double {
        let highest = Double(week.points.map(\.valueMinor).max() ?? 0)
        return max(highest * 1.2, 1)
    }

    private var selectedPoint: OverviewChartPoint? {
        guard let selectedDate else { return nil }

        return week.points.first { point in
            calendar.isDate(point.date, inSameDayAs: selectedDate)
                && point.valueMinor > 0
        }
    }

    var body: some View {
        Chart(week.points) { point in
                let isSelected = selectedPoint?.id == point.id

                BarMark(
                    x: .value("Ngày", point.date, unit: .day),
                    y: .value("Giá trị", Double(point.valueMinor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(chartColor(for: point.intensity).gradient)
                .opacity(selectedPoint == nil ? 0.92 : (isSelected ? 1 : 0.42))
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: week.points.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(weekdayLabel(for: date))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(Int64(number.rounded()).compactAxisLabel)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... chartMax)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]

                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { event in
                                            guard plotFrame.contains(event.location) else {
                                                clearSelection()
                                                return
                                            }

                                            selectPoint(at: event.location, in: plotFrame)
                                        }
                                )

                            if plotFrame.width > 0 {
                                HStack(spacing: 0) {
                                    ForEach(week.points) { point in
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .allowsHitTesting(point.valueMinor > 0)
                                            .onTapGesture {
                                                guard point.valueMinor > 0 else { return }
                                                
                                                if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: point.date) {
                                                    clearSelection()
                                                } else {
                                                    withAnimation(.snappy) {
                                                        selectedDate = point.date
                                                    }
                                                }
                                            }
                                            .onLongPressGesture(minimumDuration: 0.35) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                clearSelection(animated: false)
                                                onOpenExpenseDay(point.date)
                                            }
                                    }
                                }
                                .frame(width: plotFrame.width, height: plotFrame.height)
                                .position(x: plotFrame.midX, y: plotFrame.midY)
                            }

                            if let selectedPoint,
                               let xPosition = proxy.position(forX: selectedPoint.date) {
                                let anchorX = plotFrame.origin.x + xPosition
                                let barTopY = plotFrame.origin.y + (proxy.position(forY: Double(selectedPoint.valueMinor)) ?? 0)
                                let clampedX = min(
                                    max(anchorX, plotFrame.minX + 36),
                                    plotFrame.maxX - 36
                                )
                                let calloutY = max(plotFrame.minY + 16, barTopY - 20)

                                OverviewChartSelectionCallout(
                                    point: selectedPoint,
                                    currencyCode: currencyCode
                                )
                                .position(x: clampedX, y: calloutY)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
            .frame(height: 122)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(insetSurface)
        }
        .onChange(of: selectedDate) { _, newValue in
            guard let newValue,
                  let nearestPoint = nearestPoint(to: newValue),
                  !calendar.isDate(nearestPoint.date, inSameDayAs: newValue)
            else {
                return
            }

            selectedDate = nearestPoint.date
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                clearSelection(animated: false)
            }
        }
        .onChange(of: dismissToken) { _, _ in
            clearSelection()
        }
    }

    private func chartColor(for intensity: Double) -> Color {
        let clamped = min(max(intensity, 0), 1)
        let start = (red: 0.18, green: 0.67, blue: 0.62)
        let end = (red: 0.96, green: 0.36, blue: 0.49)

        return Color(
            red: start.red + (end.red - start.red) * clamped,
            green: start.green + (end.green - start.green) * clamped,
            blue: start.blue + (end.blue - start.blue) * clamped
        )
    }

    private func weekdayLabel(for date: Date) -> String {
        week.points.first { calendar.isDate($0.date, inSameDayAs: date) }?.label
            ?? MistiaDateFormatting.weekdayLabel(for: date, calendar: calendar)
    }

    private func nearestPoint(to date: Date) -> OverviewChartPoint? {
        week.points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func selectPoint(at location: CGPoint, in plotFrame: CGRect) {
        guard plotFrame.width > 0, !week.points.isEmpty else {
            clearSelection()
            return
        }

        let columnWidth = plotFrame.width / CGFloat(week.points.count)
        let relativeX = min(max(location.x - plotFrame.minX, 0), plotFrame.width - 1)
        let rawIndex = Int(floor(relativeX / max(columnWidth, 1)))
        let index = min(max(rawIndex, 0), week.points.count - 1)
        let point = week.points[index]

        guard point.valueMinor > 0 else {
            clearSelection()
            return
        }

        if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: point.date) {
            clearSelection()
            return
        }

        withAnimation(.snappy) {
            selectedDate = point.date
        }
    }

    private func clearSelection(animated: Bool = true) {
        if animated {
            withAnimation(.snappy) {
                selectedDate = nil
            }
        } else {
            selectedDate = nil
        }
    }
}

private struct OverviewChartSelectionCallout: View {
    @Environment(\.colorScheme) private var colorScheme

    let point: OverviewChartPoint
    let currencyCode: String

    private var calloutLabel: some View {
        Text(point.valueMinor.formattedCurrency(code: currencyCode))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                calloutLabel
                    .glassEffect(.regular.tint(colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.85)), in: .capsule)
            } else {
                calloutLabel
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.06),
                                        lineWidth: 0.5
                                    )
                            }
                    }
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 16, y: 6)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct OverviewDayTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme

    let day: Date
    let transactions: [LedgerTransaction]
    let currencyCode: String
    let onSelectTransaction: (LedgerTransaction) -> Void

    private var totalMinor: Int64 {
        transactions.reduce(into: Int64.zero) { partialResult, transaction in
            partialResult += transaction.amountMinor
        }
    }

    private var groupedBackground: Color {
        Color(UIColor.systemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                groupedBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        MistiaBlockCard(cornerRadius: 24, padding: 18) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(
                                    mistiaLocalized(
                                        vi: "Chi tiêu trong ngày",
                                        en: "Daily expenses",
                                        ja: "その日の支出"
                                    )
                                )
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)

                                Text(MistiaDateFormatting.fullDateString(for: day, calendar: calendar))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 12) {
                                    OverviewDaySummaryMetric(
                                        title: mistiaLocalized(vi: "Tổng chi", en: "Total spent", ja: "合計支出"),
                                        value: totalMinor.formattedCurrency(code: currencyCode),
                                        tint: MistiaAccent.expense.color
                                    )

                                    Divider()
                                        .frame(height: 28)

                                    OverviewDaySummaryMetric(
                                        title: mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引"),
                                        value: "\(transactions.count)",
                                        tint: colorScheme == .dark ? .white : .primary
                                    )
                                }
                            }
                        }

                        MistiaBlockCard(cornerRadius: 22, padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                                    Button {
                                        dismiss()
                                        onSelectTransaction(transaction)
                                    } label: {
                                        OverviewDayTransactionRow(
                                            transaction: transaction,
                                            currencyCode: currencyCode
                                        )
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                                    if index < transactions.count - 1 {
                                        Divider()
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(mistiaLocalized(vi: "Chi tiết ngày", en: "Day details", ja: "日別詳細"))
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
            .toolbarBackground(groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(groupedBackground)
    }
}

private struct OverviewDaySummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewDayTransactionRow: View {
    let transaction: LedgerTransaction
    let currencyCode: String

    private var titleText: String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            return trimmed
        }

        return transaction.category?.localizedDisplayName
            ?? mistiaLocalized(vi: "Chi tiêu", en: "Expense", ja: "支出")
    }

    private var subtitleText: String {
        let timeText = transaction.occurredAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(MistiaAppLanguage.current.locale)
        )
        let walletName = transaction.sourceWallet?.name
            ?? mistiaLocalized(vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択")

        if let categoryName = transaction.category?.localizedDisplayName,
           categoryName != titleText {
            return "\(timeText) • \(walletName) • \(categoryName)"
        }

        return "\(timeText) • \(walletName)"
    }

    private var iconName: String {
        transaction.category?.iconSymbolName ?? transaction.primaryKind.financeIconToken
    }

    private var amountColor: Color {
        MistiaAccent.expense.color
    }

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(icon: iconName, fallbackColor: amountColor, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("-" + transaction.amountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct SummaryMetricColumn: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetFocusSection: View {
    let rows: [OverviewBudgetAlertSnapshot]

    var body: some View {
        OverviewSection(title: mistiaLocalized(vi: "Ngân sách cần chú ý", en: "Budget watchlist", ja: "注意が必要な予算")) {
            if rows.isEmpty {
                OverviewEmptySectionContent(
                    message: mistiaLocalized(
                        vi: "Chưa có danh mục nào vượt quá 50% ngân sách trong tháng này.",
                        en: "No categories have exceeded 50% of their budget this month.",
                        ja: "今月の予算消化が 50% を超えたカテゴリはまだありません。"
                    )
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        BudgetRow(row: row)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                        if index < rows.count - 1 {
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

private struct BudgetRow: View {
    let row: OverviewBudgetAlertSnapshot

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: row.iconSymbolName, tint: row.tint.color)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(row.progressPercentText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(row.tint.color)
                }

                Text("\(row.spentMinor.formattedCurrency(code: row.currencyCode)) / \(row.limitMinor.formattedCurrency(code: row.currencyCode))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                ProgressView(value: min(max(row.progress, 0), 1))
                    .tint(row.tint.color)

                Text(
                    mistiaLocalized(
                        vi: "Còn \(row.daysRemaining) ngày",
                        en: "\(row.daysRemaining) days left",
                        ja: "あと \(row.daysRemaining) 日"
                    )
                )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(row.tint.color)
            }
        }
    }
}

private struct UpcomingBillsSection: View {
    let rows: [OverviewDueAlertSnapshot]
    let onSelect: (OverviewDueAlertSnapshot) -> Void

    var body: some View {
        OverviewSection(title: mistiaLocalized(vi: "Khoản sắp đến hạn", en: "Upcoming due items", ja: "まもなく期限の項目")) {
            if rows.isEmpty {
                OverviewEmptySectionContent(
                    message: mistiaLocalized(
                        vi: "Không có hóa đơn, vay hoặc credit nào đến hạn trong 7 ngày tới.",
                        en: "No bills, loans, or credit payments are due in the next 7 days.",
                        ja: "今後 7 日以内に期限を迎える請求、ローン、カード支払いはありません。"
                    )
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onSelect(row)
                        } label: {
                            DueRow(row: row)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }
}

private struct DueRow: View {
    let row: OverviewDueAlertSnapshot

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: row.iconSymbolName, tint: row.tint.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("\(row.dueDate.overviewDayText) • \(detailText)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.tint == .red ? row.tint.color : .secondary)
            }

            Spacer()

            if let amountMinor = row.amountMinor {
                Text(amountMinor.formattedCurrency(code: row.currencyCode))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(row.tint == .red ? row.tint.color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(mistiaLocalized(vi: "Chưa có số tiền", en: "No amount yet", ja: "金額未入力"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailText: String {
        if row.dayDelta == 0 {
            return mistiaLocalized(vi: "Đến hạn hôm nay", en: "Due today", ja: "本日支払い")
        }

        return mistiaLocalized(
            vi: "Còn \(row.dayDelta) ngày",
            en: "\(row.dayDelta) days left",
            ja: "あと \(row.dayDelta) 日"
        )
    }
}

private struct RecentTransactionsSection: View {
    let rows: [OverviewRecentTransactionSnapshot]
    let onSelect: (OverviewRecentTransactionSnapshot) -> Void

    var body: some View {
        OverviewSection(title: mistiaLocalized(vi: "Giao dịch gần đây", en: "Recent transactions", ja: "最近の取引")) {
            if rows.isEmpty {
                OverviewEmptySectionContent(
                    message: mistiaLocalized(
                        vi: "Chưa có giao dịch nào được ghi nhận gần đây.",
                        en: "No transactions have been recorded recently.",
                        ja: "最近記録された取引はまだありません。"
                    )
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onSelect(row)
                        } label: {
                            RecentTransactionRow(row: row)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }
}

private struct RecentTransactionRow: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    let row: OverviewRecentTransactionSnapshot

    var body: some View {
        HStack(spacing: 12) {
            OverviewIcon(icon: iconName, tint: amountColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(row.timeLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(displayAmount)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var amountColor: Color {
        switch row.cashflowStyle {
        case .income:
            Color(red: 0.18, green: 0.67, blue: 0.62)  // Xanh lục
        case .expense:
            Color(red: 0.96, green: 0.36, blue: 0.49)  // Đỏ hồng
        case .neutral:
            colorScheme == .dark ? .white : Color(red: 0.60, green: 0.60, blue: 0.60)  // Trắng/xám
        }
    }

    private var iconName: String {
        row.categoryIconSymbolName
    }

    private var displayAmount: String {
        let raw = row.amountMinor.formattedCurrency(code: row.currencyCode)

        switch row.cashflowStyle {
        case .income:
            return "+" + raw
        case .expense:
            return "-" + raw
        case .neutral:
            return raw
        }
    }
}

private struct OverviewSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    private let content: Content

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43))

            MistiaBlockCard(
                cornerRadius: 22,
                tint: cardTint,
                padding: 0
            ) {
                content
            }
        }
    }
}

private struct OverviewEmptySectionContent: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
    }
}

private struct OverviewIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: tint, size: 30)
    }
}

private extension Date {
    var overviewDayText: String {
        MistiaDateFormatting.shortDateString(for: self)
    }
}
