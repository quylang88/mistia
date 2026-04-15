import Charts
import SwiftData
import SwiftUI

private let overviewAccentPurple = Color(red: 0.43, green: 0.23, blue: 0.76)

struct OverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
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

    @State private var shareItem: OverviewShareItem?
    @State private var exportErrorMessage: String?

    private var currentMonth: Date {
        PlanningLogic.startOfMonth(for: .now, calendar: calendar)
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

    private var statementCreditCardAccounts: [OverviewCreditCardStatementAccountSnapshot] {
        storedWallets.compactMap { $0.overviewCreditCardStatementAccountSnapshot(records: transactionRecords) }
    }

    private var creditCardDueItems: [PlanningCreditCardDueSnapshot] {
        PlanningLogic.creditCardDueItems(
            accounts: planningCreditCardAccounts,
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

    private var monthlyStatement: OverviewMonthlyStatementSnapshot {
        OverviewLogic.monthlyStatement(
            wallets: walletSnapshots,
            transactionRecords: transactionRecords,
            transactions: overviewTransactions,
            currencyCode: currencyCode,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var creditCardStatement: OverviewCreditCardStatementSnapshot {
        OverviewLogic.creditCardStatement(
            accounts: statementCreditCardAccounts,
            transactions: overviewTransactions,
            referenceDate: .now,
            calendar: calendar
        )
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: mistiaLocalized(vi: "Tổng quan", en: "Overview", ja: "ホーム"),
            leadingInitials: sessionStore.summary?.initials ?? "MI",
            leadingAvatarURL: sessionStore.summary?.avatarURL,
            contentSpacing: 18,
            titleDisplayMode: .large
        ) {
            FamilyContextChipBar()
            OverviewHeroCard(
                snapshot: dashboardSnapshot.hero,
                onExportMonthly: { exportStatement(.monthlySummary) },
                onExportCreditCard: { exportStatement(.creditCard) }
            )
            if !dashboardSnapshot.budgetAlerts.isEmpty {
                BudgetFocusSection(rows: dashboardSnapshot.budgetAlerts)
            }
            if !dashboardSnapshot.dueAlerts.isEmpty {
                UpcomingBillsSection(rows: dashboardSnapshot.dueAlerts)
            }
            RecentTransactionsSection(rows: dashboardSnapshot.recentTransactions)
        }
        .sheet(item: $shareItem) { item in
            OverviewShareSheet(url: item.url)
        }
        .alert(
            mistiaLocalized(vi: "Không thể xuất sao kê", en: "Couldn't export statement", ja: "明細を出力できませんでした"),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる"), role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(mistiaCatalog(exportErrorMessage ?? ""))
        }
        .task {
            try? MistiaBootstrap.seedDefaultCategoriesIfNeeded(
                modelContext: modelContext,
                sessionStore: sessionStore
            )
        }
    }

    private func exportStatement(_ kind: OverviewStatementKind) {
        do {
            let document: OverviewStatementDocument

            switch kind {
            case .monthlySummary:
                document = OverviewLogic.renderMonthlyStatement(monthlyStatement)
            case .creditCard:
                document = OverviewLogic.renderCreditCardStatement(creditCardStatement)
            }

            let url = try OverviewStatementExportSupport.write(document: document)
            shareItem = OverviewShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

private struct OverviewHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedWeekStart: Date

    let snapshot: OverviewHeroSnapshot
    let onExportMonthly: () -> Void
    let onExportCreditCard: () -> Void

    init(
        snapshot: OverviewHeroSnapshot,
        onExportMonthly: @escaping () -> Void,
        onExportCreditCard: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.onExportMonthly = onExportMonthly
        self.onExportCreditCard = onExportCreditCard
        _selectedWeekStart = State(initialValue: snapshot.currentWeekStart)
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

                    OverviewStatementMenuButton(
                        onExportMonthly: onExportMonthly,
                        onExportCreditCard: onExportCreditCard
                    )
                }

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

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(mistiaLocalized(vi: "Chi tiêu theo ngày", en: "Daily spending", ja: "日別支出"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(activeWeek.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    TabView(selection: $selectedWeekStart) {
                        ForEach(snapshot.weekPages) { week in
                            OverviewWeekSpendingChart(
                                week: week,
                                insetSurface: insetSurface
                            )
                            .tag(week.weekStart)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 154)
                }
            }
        }
        .onChange(of: snapshot.weekPages.map(\.weekStart)) { _, weekStarts in
            if !weekStarts.contains(selectedWeekStart) {
                selectedWeekStart = snapshot.currentWeekStart
            }
        }
    }
}

private struct OverviewStatementMenuButton: View {
    let onExportMonthly: () -> Void
    let onExportCreditCard: () -> Void

    var body: some View {
        Menu {
            Button(action: onExportMonthly) {
                Label(mistiaLocalized(vi: "Sao kê tổng hợp tháng", en: "Monthly summary statement", ja: "月次サマリー明細"), systemImage: "doc.text.image")
            }

            Button(action: onExportCreditCard) {
                Label(mistiaLocalized(vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細"), systemImage: "creditcard.and.123")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))

                Text(mistiaLocalized(vi: "Sao kê", en: "Statement", ja: "明細"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(overviewAccentPurple)
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }
}

private struct OverviewWeekSpendingChart: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPointIndex: Int?
    @State private var showDetailSheet = false

    let week: OverviewWeekSpendingSnapshot
    let insetSurface: Color

    private var chartMax: Double {
        let highest = Double(week.points.map(\.valueMinor).max() ?? 0)
        return max(highest * 1.2, 1)
    }

    var body: some View {
        ZStack {
            // Chart with gestures
            Chart(week.points) { point in
                BarMark(
                    x: .value("Ngày", point.label),
                    y: .value("Giá trị", Double(point.valueMinor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(chartColor(for: point.intensity).gradient)
                .opacity(0.92)
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: week.points.map(\.label)) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
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
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    let columnWidth = width / CGFloat(week.points.count)

                    ZStack(alignment: .topLeading) {
                        // Gesture rectangles
                        ForEach(Array(week.points.enumerated()), id: \.offset) { index, _ in
                            ZStack {
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                
                                // Tooltip for this column
                                if selectedPointIndex == index, !showDetailSheet {
                                    VStack(spacing: 8) {
                                        Text(week.points[index].label)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)

                                        Text(week.points[index].valueMinor.formattedCurrency(code: "JPY"))
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(12)
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(8)
                                    .shadow(radius: 4)
                                    .offset(y: -50)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .frame(width: columnWidth, height: height)
                            .offset(x: CGFloat(index) * columnWidth)
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    selectedPointIndex = index
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.3) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.snappy) {
                                    selectedPointIndex = index
                                }
                                showDetailSheet = true
                            }
                        }
                    }
                }
            )            }        .frame(height: 122)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(insetSurface)
        }
        .sheet(isPresented: $showDetailSheet) {
            if let index = selectedPointIndex, index < week.points.count {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mistiaLocalized(vi: "Giao dịch ngày", en: "Transactions on", ja: "取引日"))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(week.points[index].label)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Text(week.points[index].valueMinor.formattedCurrency(code: "JPY"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.96, green: 0.36, blue: 0.49))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Divider()
                        .padding(.horizontal, 16)

                    VStack(spacing: 12) {
                        Text(mistiaLocalized(vi: "Danh sách giao dịch sẽ được hiển thị tại đây", en: "Transaction list will be displayed here", ja: "取引リストがここに表示されます"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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
                        DueRow(row: row)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

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
                        RecentTransactionRow(row: row)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

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
