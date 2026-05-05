import SwiftData
import SwiftUI

private enum PlanningMode: String, CaseIterable, Identifiable {
    case budget
    case goals
    case due

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budget:
            mistiaLocalized(vi: "Ngân sách", en: "Budget", ja: "予算")
        case .goals:
            mistiaLocalized(vi: "Mục tiêu", en: "Goals", ja: "目標")
        case .due:
            mistiaLocalized(vi: "Đến hạn", en: "Due", ja: "支払予定")
        }
    }

    var icon: String {
        switch self {
        case .budget:
            "banknote.fill"
        case .goals:
            "target"
        case .due:
            "calendar.badge.clock"
        }
    }
}

private enum PlanningDueMode: String, CaseIterable, Identifiable {
    case creditCards
    case bills
    case installments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creditCards:
            mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit cards", ja: "クレジットカード")
        case .bills:
            mistiaLocalized(vi: "Hóa đơn", en: "Bills", ja: "請求書")
        case .installments:
            mistiaLocalized(vi: "Trả góp / vay", en: "Installments / loans", ja: "分割払い・借入")
        }
    }
}

private let planningAccentPurple = Color(red: 0.43, green: 0.23, blue: 0.76)

private enum PlanningNavigationDestination: Identifiable, Equatable, Hashable {
    case profile
    case creditCardStatement(LedgerWallet)

    var id: String {
        switch self {
        case .profile: return "profile"
        case .creditCardStatement(let wallet): return "creditCardStatement-\(wallet.id)"
        }
    }

    static func == (lhs: PlanningNavigationDestination, rhs: PlanningNavigationDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PlanningView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
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
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil })
    private var storedTransactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @State private var selectedMode: PlanningMode = .budget
    @State private var selectedDueMode: PlanningDueMode = .creditCards
    @State private var selectedMonth = PlanningLogic.startOfMonth(for: .now)
    @State private var isMonthPickerPresented = false
    @State private var budgetEditorTarget: PlanningBudgetEditorTarget?
    @State private var goalEditorTarget: PlanningGoalEditorTarget?
    @State private var billEditorTarget: PlanningBillEditorTarget?
    @State private var installmentEditorTarget: PlanningInstallmentEditorTarget?
    @State private var creditCardEditorTarget: PlanningCreditCardEditorTarget?
    @State private var duePaymentTarget: DuePaymentSheetTarget?
    @State private var destination: PlanningNavigationDestination?

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.022) : .white.opacity(0.14)
    }

    private var transactionSnapshots: [TransactionRecordSnapshot] {
        visibleTransactions.map(\.planningRecordSnapshot)
    }

    private var occurrenceSnapshots: [PlanningDueOccurrenceSnapshot] {
        visibleOccurrences.map(\.planningSnapshot)
    }

    private var activeBudgetPlans: [BudgetPlanSnapshot] {
        visibleBudgets
            .filter { !$0.isArchived && PlanningLogic.startOfMonth(for: $0.monthAnchor, calendar: calendar) == selectedMonth }
            .map { $0.planningSnapshot(calendar: calendar) }
    }

    private var budgetRows: [PlanningBudgetBranchRowSnapshot] {
        PlanningLogic.budgetBranchRows(
            plans: activeBudgetPlans,
            records: transactionSnapshots,
            selectedMonth: selectedMonth,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var budgetSummary: PlanningBudgetSummarySnapshot {
        PlanningLogic.budgetSummary(from: budgetRows)
    }

    private var activeGoals: [SavingsGoalSnapshot] {
        visibleGoals
            .filter { !$0.isArchived }
            .map(\.planningSnapshot)
    }

    private var goalRows: [PlanningGoalRowSnapshot] {
        PlanningLogic.goalRows(
            goals: activeGoals,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
    }

    private var goalSummary: PlanningGoalSummarySnapshot {
        PlanningLogic.goalSummary(from: goalRows)
    }

    private var creditCardAccounts: [PlanningCreditCardAccountSnapshot] {
        visibleWallets.compactMap { $0.planningCreditCardSnapshot(records: transactionSnapshots) }
    }

    private var creditCardDueItems: [PlanningCreditCardDueSnapshot] {
        PlanningLogic.creditCardDueItems(
            accounts: creditCardAccounts,
            records: transactionSnapshots,
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var creditCardStatementDueItems: [PlanningCreditCardStatementSnapshot] {
        PlanningLogic.creditCardStatementsDue(
            in: selectedMonth,
            accounts: creditCardAccounts,
            records: transactionSnapshots,
            occurrences: occurrenceSnapshots,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private var recurringBillDueItems: [PlanningRecurringDueSnapshot] {
        PlanningLogic.recurringBillDueItems(
            bills: storedBills
                .filter { visibleBillIDs.contains($0.id) }
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
    }

    private var installmentDueItems: [PlanningRecurringDueSnapshot] {
        PlanningLogic.installmentDueItems(
            plans: storedInstallments
                .filter { visibleInstallmentIDs.contains($0.id) }
                .filter { !$0.isArchived }
                .map(\.planningSnapshot),
            occurrences: occurrenceSnapshots,
            selectedMonth: selectedMonth,
            calendar: calendar
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

    private var visibleGoals: [SavingsGoal] {
        FamilyScopedData.visible(
            storedGoals,
            entity: .savingsGoal,
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

    private var visibleBillIDs: Set<UUID> {
        Set(visibleBills.map(\.id))
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

    private var visibleInstallmentIDs: Set<UUID> {
        Set(visibleInstallments.map(\.id))
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

    private var visibleTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForFinancial(
            storedTransactions,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var dueSummary: PlanningDueSummarySnapshot {
        PlanningLogic.dueSummary(
            creditStatements: creditCardStatementDueItems,
            recurring: recurringBillDueItems + installmentDueItems,
            selectedMonth: selectedMonth,
            referenceDate: .now,
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            MistiaPinnedTopBarScaffold(
                tone: .standard,
                title: mistiaLocalized(vi: "Kế hoạch", en: "Planning", ja: "プラン"),
                embedsInNavigationStack: false,
                leadingInitials: sessionStore.summary?.initials ?? "MI",
                leadingAvatarURL: sessionStore.summary?.avatarURL,
                trailingSystemImage: "calendar",
                onLeadingTap: { destination = .profile },
                onTrailingTap: { isMonthPickerPresented = true },
                contentSpacing: 18,
                titleDisplayMode: .large,
                pinnedHeader: {
                    VStack(alignment: .leading, spacing: 8) {
                        FamilyContextChipBar()
                            .padding(.horizontal, 18)
                        PlanningModePicker(selection: $selectedMode)
                    }
                }
            ) {
                switch selectedMode {
                case .budget:
                    BudgetTabContent(
                        summary: budgetSummary,
                        currencyCode: currencyCode,
                        rows: budgetRows,
                        referenceDate: .now,
                        onAdd: {
                            budgetEditorTarget = PlanningBudgetEditorTarget(
                                budget: nil,
                                selectedMonth: selectedMonth,
                                preferredParentCategoryID: nil
                            )
                        },
                        onEditPrimary: { row in
                            guard let budgetID = row.primaryBudgetID else { return }
                            let budget = storedBudgets.first(where: { $0.id == budgetID })
                            budgetEditorTarget = PlanningBudgetEditorTarget(
                                budget: budget,
                                selectedMonth: selectedMonth,
                                preferredParentCategoryID: row.parentCategoryID
                            )
                        },
                        onEditChild: { row in
                            let budget = storedBudgets.first(where: { $0.id == row.id })
                            budgetEditorTarget = PlanningBudgetEditorTarget(
                                budget: budget,
                                selectedMonth: selectedMonth,
                                preferredParentCategoryID: nil
                            )
                        }
                    )
                case .goals:
                    GoalsTabContent(
                        summary: goalSummary,
                        currencyCode: currencyCode,
                        rows: goalRows,
                        onAdd: {
                            goalEditorTarget = PlanningGoalEditorTarget(goal: nil)
                        },
                        onEdit: { row in
                            goalEditorTarget = PlanningGoalEditorTarget(
                                goal: storedGoals.first(where: { $0.id == row.id })
                            )
                        }
                    )
                case .due:
                    DueTabContent(
                        selectedMode: $selectedDueMode,
                        summary: dueSummary,
                        currencyCode: currencyCode,
                        creditCards: creditCardAccounts,
                        bills: recurringBillDueItems,
                        installments: installmentDueItems,
                        referenceDate: .now,
                        onAddCreditCard: {
                            creditCardEditorTarget = PlanningCreditCardEditorTarget(
                                wallet: nil,
                                dueItem: nil,
                                selectedMonth: selectedMonth
                            )
                        },
                        onEditCreditCard: { item in
                            creditCardEditorTarget = PlanningCreditCardEditorTarget(
                                wallet: storedWallets.first(where: { $0.id == item.walletID }),
                                dueItem: nil,
                                selectedMonth: selectedMonth
                            )
                        },
                        onAddBill: {
                            billEditorTarget = PlanningBillEditorTarget(
                                plan: nil,
                                dueItem: nil,
                                selectedMonth: selectedMonth
                            )
                        },
                        onEditBill: { item in
                            billEditorTarget = PlanningBillEditorTarget(
                                plan: storedBills.first(where: { $0.id == item.sourceID }),
                                dueItem: item,
                                selectedMonth: selectedMonth
                            )
                        },
                        onAddInstallment: {
                            installmentEditorTarget = PlanningInstallmentEditorTarget(
                                plan: nil,
                                dueItem: nil,
                                selectedMonth: selectedMonth
                            )
                        },
                        onEditInstallment: { item in
                            installmentEditorTarget = PlanningInstallmentEditorTarget(
                                plan: storedInstallments.first(where: { $0.id == item.sourceID }),
                                dueItem: item,
                                selectedMonth: selectedMonth
                            )
                        },
                        onPayBill: { item in
                            duePaymentTarget = DuePaymentSheetTarget(
                                sourceKind: .recurringBill,
                                sourceID: item.sourceID,
                                dueMonthKey: PlanningLogic.monthKey(for: selectedMonth),
                                dueDate: item.dueDate,
                                requiresAmountInput: item.amountMinor == nil,
                                currencyCode: item.currencyCode,
                                name: item.name
                            )
                        }
                    )
                }
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .profile:
                    ManagementAccountView()
                case .creditCardStatement(let wallet):
                    ManagementCreditCardStatementView(wallet: wallet)
                }
            }
        }
        .sheet(item: $budgetEditorTarget) { target in
            PlanningBudgetEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $goalEditorTarget) { target in
            PlanningGoalEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $billEditorTarget) { target in
            PlanningBillEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $installmentEditorTarget) { target in
            PlanningInstallmentEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $creditCardEditorTarget) { target in
            PlanningCreditCardEditorSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $duePaymentTarget) { target in
            DuePaymentSheet(target: target)
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $isMonthPickerPresented) {
            PlanningMonthPickerSheet(selection: $selectedMonth, calendar: calendar)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .task {
            try? MistiaBootstrap.seedDefaultCategoriesIfNeeded(
                modelContext: modelContext,
                sessionStore: sessionStore
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MistiaOpenCreditCardStatementFromPlanning"))) { notification in
            if let walletID = notification.object as? UUID,
               let wallet = storedWallets.first(where: { $0.id == walletID }) {
                destination = .creditCardStatement(wallet)
            }
        }
    }
}

private struct BudgetTabContent: View {
    let summary: PlanningBudgetSummarySnapshot
    let currencyCode: String
    let rows: [PlanningBudgetBranchRowSnapshot]
    let referenceDate: Date
    let onAdd: () -> Void
    let onEditPrimary: (PlanningBudgetBranchRowSnapshot) -> Void
    let onEditChild: (PlanningBudgetRowSnapshot) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PlanningBudgetSummaryCard(summary: summary, currencyCode: currencyCode)

            if rows.isEmpty {
                PlanningEmptyStateCard(
                    title: mistiaLocalized(vi: "Chưa có ngân sách nào", en: "No budgets yet", ja: "予算はまだありません"),
                    message: mistiaLocalized(
                        vi: "Tạo ngân sách theo từng danh mục để theo dõi số tiền đã dùng và số ngày còn lại trong tháng.",
                        en: "Create category budgets to track what you've spent and how many days are left in the month.",
                        ja: "カテゴリごとに予算を作成すると、使った金額と月末までの残り日数を追跡できます。"
                    ),
                    buttonTitle: mistiaLocalized(vi: "Thêm ngân sách", en: "Add budget", ja: "予算を追加"),
                    accent: planningAccentPurple,
                    symbols: ["banknote.fill", "chart.bar.fill", "bolt.fill", "plus"]
                ) {
                    onAdd()
                }
            } else {
                PlanningListCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        PlanningBudgetBranchCard(
                            row: row,
                            referenceDate: referenceDate,
                            onEditPrimary: { onEditPrimary(row) },
                            onEditChild: onEditChild
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }

                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 0)

                    PlanningFooterAddButton(title: mistiaLocalized(vi: "Thêm ngân sách", en: "Add budget", ja: "予算を追加")) {
                        onAdd()
                    }
                }
            }
        }
    }
}

private struct GoalsTabContent: View {
    let summary: PlanningGoalSummarySnapshot
    let currencyCode: String
    let rows: [PlanningGoalRowSnapshot]
    let onAdd: () -> Void
    let onEdit: (PlanningGoalRowSnapshot) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PlanningGoalSummaryCard(summary: summary, currencyCode: currencyCode)

            if rows.isEmpty {
                PlanningEmptyStateCard(
                    title: mistiaLocalized(vi: "Chưa có mục tiêu nào", en: "No goals yet", ja: "目標はまだありません"),
                    message: mistiaLocalized(
                        vi: "Thêm quỹ khẩn cấp, du lịch hay món đồ lớn để theo dõi số tiền cần tích lũy mỗi tháng.",
                        en: "Add an emergency fund, trip, or big purchase to track how much you need to save each month.",
                        ja: "緊急資金や旅行、大きな買い物の目標を追加して、毎月どれだけ貯める必要があるか確認できます。"
                    ),
                    buttonTitle: mistiaLocalized(vi: "Thêm mục tiêu", en: "Add goal", ja: "目標を追加"),
                    accent: planningAccentPurple,
                    symbols: ["target", "sparkles", "flag.fill", "plus"]
                ) {
                    onAdd()
                }
            } else {
                PlanningListCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onEdit(row)
                        } label: {
                            PlanningGoalRowView(row: row)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                        }
                    }

                    Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)

                    PlanningFooterAddButton(title: mistiaLocalized(vi: "Thêm mục tiêu", en: "Add goal", ja: "目標を追加")) {
                        onAdd()
                    }
                }
            }
        }
    }
}

private struct DueTabContent: View {
    @Binding var selectedMode: PlanningDueMode

    let summary: PlanningDueSummarySnapshot
    let currencyCode: String
    let creditCards: [PlanningCreditCardAccountSnapshot]
    let bills: [PlanningRecurringDueSnapshot]
    let installments: [PlanningRecurringDueSnapshot]
    let referenceDate: Date
    let onAddCreditCard: () -> Void
    let onEditCreditCard: (PlanningCreditCardAccountSnapshot) -> Void
    let onAddBill: () -> Void
    let onEditBill: (PlanningRecurringDueSnapshot) -> Void
    let onAddInstallment: () -> Void
    let onEditInstallment: (PlanningRecurringDueSnapshot) -> Void
    let onPayBill: (PlanningRecurringDueSnapshot) -> Void

    var body: some View {
        VStack(spacing: 16) {
            PlanningDueSummaryCard(summary: summary, currencyCode: currencyCode)
            PlanningDueModePicker(selection: $selectedMode)

            switch selectedMode {
            case .creditCards:
                CreditCardsSection(
                    items: creditCards,
                    referenceDate: referenceDate,
                    onAdd: onAddCreditCard,
                    onEdit: onEditCreditCard
                )
            case .bills:
                DueRowsSection(
                    emptyTitle: mistiaLocalized(vi: "Chưa có hóa đơn nào", en: "No bills yet", ja: "請求はまだありません"),
                    emptyMessage: mistiaLocalized(
                        vi: "Thêm tiền Internet, điện nước hoặc hóa đơn định kỳ để lên lịch đến hạn.",
                        en: "Add internet, utilities, or recurring bills to schedule upcoming due dates.",
                        ja: "ネット料金や光熱費、定期請求を追加して支払予定を管理できます。"
                    ),
                    emptySymbols: ["wifi", "bolt.fill", "phone.fill", "plus"],
                    accent: planningAccentPurple,
                    items: bills,
                    addTitle: mistiaLocalized(vi: "Thêm hóa đơn", en: "Add bill", ja: "請求を追加"),
                    referenceDate: referenceDate,
                    onAdd: onAddBill,
                    onEdit: onEditBill,
                    onPay: onPayBill
                )
            case .installments:
                DueRowsSection(
                    emptyTitle: mistiaLocalized(vi: "Chưa có khoản trả góp / vay", en: "No installments or loans yet", ja: "分割払い・借入はまだありません"),
                    emptyMessage: mistiaLocalized(
                        vi: "Thêm các khoản cần trả theo kỳ và tạo giao dịch khi thanh toán trước.",
                        en: "Add installment or loan payments and create transactions when you pay early.",
                        ja: "分割払いやローンを追加すると、繰上げ支払い時に取引も作成できます。"
                    ),
                    emptySymbols: ["creditcard.and.123", "building.columns.fill", "banknote.fill", "plus"],
                    accent: planningAccentPurple,
                    items: installments,
                    addTitle: mistiaLocalized(vi: "Thêm trả góp / vay", en: "Add installment / loan", ja: "分割払い・借入を追加"),
                    referenceDate: referenceDate,
                    onAdd: onAddInstallment,
                    onEdit: onEditInstallment
                )
            }
        }
    }
}

private struct CreditCardsSection: View {
    let items: [PlanningCreditCardAccountSnapshot]
    let referenceDate: Date
    let onAdd: () -> Void
    let onEdit: (PlanningCreditCardAccountSnapshot) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10)]

    var body: some View {
        if items.isEmpty {
            PlanningEmptyStateCard(
                title: mistiaLocalized(vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません"),
                message: mistiaLocalized(
                    vi: "Liên kết hoặc thêm thẻ ngay tại đây để hiển thị credit card và theo dõi ngày thanh toán.",
                    en: "Link or add cards here to show your credit cards and track payment dates.",
                    ja: "ここでカードを追加または連携すると、クレジットカードと支払日を管理できます。"
                ),
                buttonTitle: mistiaLocalized(vi: "Thêm credit card", en: "Add credit card", ja: "カードを追加"),
                accent: planningAccentPurple,
                symbols: ["creditcard.fill", "wave.3.right.circle.fill", "building.columns.fill", "plus"]
            ) {
                onAdd()
            }
        } else {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        PlanningCreditCardCard(
                            item: item,
                            onOpenStatement: {
                                NotificationCenter.default.post(name: NSNotification.Name("MistiaOpenCreditCardStatementFromPlanning"), object: item.walletID)
                            }
                        )
                        .onTapGesture {
                            onEdit(item)
                        }
                    }
                }

                PlanningFooterAddButton(title: mistiaLocalized(vi: "Thêm credit card", en: "Add credit card", ja: "カードを追加")) {
                    onAdd()
                }
            }
        }
    }
}

private struct DueRowsSection: View {
    let emptyTitle: String
    let emptyMessage: String
    let emptySymbols: [String]
    let accent: Color
    let items: [PlanningRecurringDueSnapshot]
    let addTitle: String
    let referenceDate: Date
    let onAdd: () -> Void
    let onEdit: (PlanningRecurringDueSnapshot) -> Void
    var onPay: ((PlanningRecurringDueSnapshot) -> Void)? = nil

    var body: some View {
        if items.isEmpty {
            PlanningEmptyStateCard(
                title: emptyTitle,
                message: emptyMessage,
                buttonTitle: addTitle,
                accent: accent,
                symbols: emptySymbols
            ) {
                onAdd()
            }
        } else {
            PlanningListCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PlanningDueRow(
                        item: item,
                        referenceDate: referenceDate,
                        onTap: { onEdit(item) },
                        onPay: {
                            onPay?(item)
                        }
                    )
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)

                    if index < items.count - 1 {
                        Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)
                    }
                }

                Divider()
                                .padding(.leading, 52)
                                .padding(.trailing, 0)

                PlanningFooterAddButton(title: addTitle) {
                    onAdd()
                }
            }
        }
    }
}

private struct PlanningModePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Binding var selection: PlanningMode

    private var accent: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlanningMode.allCases) { mode in
                Button {
                    withAnimation(.snappy) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12.5, weight: .bold))
                        Text(mode.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selection == mode ? activeForeground : idleForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selection == mode {
                            Capsule()
                                .fill(Color.clear)
                                .background {
                                    if #available(iOS 26, *) {
                                        Capsule()
                                            .fill(.clear)
                                            .glassEffect(
                                                Glass.regular
                                                    .tint(activeTint)
                                                    .interactive(true),
                                                in: .capsule
                                            )
                                    } else {
                                        Capsule()
                                            .fill(.regularMaterial)
                                    }
                                }
                        } else {
                            Capsule()
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                        }
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.20), lineWidth: 0.8)
                    }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 24, tint: accent))
            }
        }
        .id(locale.identifier)
        .padding(.horizontal, 18)
        .padding(.vertical, 2)
        .padding(.bottom, 10)
        .background(MistiaBackgroundView(tone: .standard).opacity(0.001))
    }

    private var activeForeground: Color {
        .white
    }

    private var idleForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.94, blue: 0.97)
            : Color.black.opacity(0.76)
    }

    private var activeTint: Color {
        colorScheme == .dark
            ? Color(red: 0.34, green: 0.18, blue: 0.60)
            : accent.opacity(0.98)
    }

    private var idleTint: Color {
        colorScheme == .dark
            ? Color(red: 0.24, green: 0.24, blue: 0.27)
            : Color.black.opacity(0.06)
    }
}

private struct PlanningDueModePicker: View {
    @Binding var selection: PlanningDueMode

    private var accent: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    var body: some View {
        MistiaNativeSegmentedControl(
            selection: $selection,
            options: PlanningDueMode.allCases,
            title: \.title,
            accent: accent
        )
    }
}

private struct PlanningBudgetSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PlanningBudgetSummarySnapshot
    let currencyCode: String

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mistiaLocalized(vi: "Tổng ngân sách tháng", en: "Monthly budget total", ja: "月間予算合計"))
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(summary.totalBudgetMinor.formattedCurrency(code: currencyCode))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        PlanningStatusBadge(title: summary.health.title, color: summaryColor)
                    }

                    Spacer(minLength: 12)

                    PlanningSemiGauge(
                        progress: summary.progress,
                        text: summary.progress.percentText,
                        tint: summaryColor
                    )
                }

                HStack(spacing: 14) {
                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Đã dùng", en: "Spent", ja: "使用済み"),
                        value: summary.spentMinor.formattedCurrency(code: currencyCode),
                        tint: MistiaAccent.coral.color
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Còn lại", en: "Remaining", ja: "残り"),
                        value: summary.remainingMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#2DAA9E")
                    )
                }
            }
        }
    }

    private var summaryColor: Color {
        switch summary.health {
        case .stable:
            Color(hex: "#2DAA9E")
        case .caution:
            Color(hex: "#F59B3F")
        case .exceeded:
            Color(hex: "#F45C7E")
        }
    }

}

private struct PlanningGoalSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PlanningGoalSummarySnapshot
    let currencyCode: String

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text(mistiaLocalized(vi: "Mục tiêu đang hoạt động", en: "Active goals", ja: "進行中の目標"))
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(
                    mistiaLocalized(
                        vi: "\(summary.activeCount) mục tiêu",
                        en: "\(summary.activeCount) goals",
                        ja: "\(summary.activeCount) 件の目標"
                    )
                )
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                HStack(spacing: 14) {
                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Đã tích lũy", en: "Saved", ja: "積み立て済み"),
                        value: summary.totalSavedMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#2DAA9E")
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Gần đạt nhất", en: "Closest to goal", ja: "達成まであと少し"),
                        value: summary.nearestGoalName ?? mistiaLocalized(vi: "Chưa có", en: "None yet", ja: "まだありません"),
                        tint: Color(hex: "#5B7BFF")
                    )
                }
            }
        }
    }
}

private struct PlanningDueSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PlanningDueSummarySnapshot
    let currencyCode: String

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(cornerRadius: 24, tint: cardTint, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                Text(mistiaLocalized(vi: "Tóm tắt", en: "Summary", ja: "概要"))
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Sắp đến hạn", en: "Upcoming", ja: "まもなく期限"),
                        value: "\(summary.upcomingCount)",
                        tint: Color(hex: "#5B7BFF")
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Tổng cần trả", en: "Total due", ja: "支払合計"),
                        value: summary.totalDueMinor.formattedCurrency(code: currencyCode),
                        tint: Color(hex: "#F59B3F")
                    )

                    Divider()
                        .frame(height: 30)

                    PlanningMetricColumn(
                        title: mistiaLocalized(vi: "Quá hạn", en: "Overdue", ja: "延滞"),
                        value: "\(summary.overdueCount)",
                        tint: Color(hex: "#F45C7E")
                    )
                }
            }
        }
    }
}

private struct PlanningBudgetBranchCard: View {
    let row: PlanningBudgetBranchRowSnapshot
    let referenceDate: Date
    let onEditPrimary: () -> Void
    let onEditChild: (PlanningBudgetRowSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            primarySection

            if !row.childRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    childHeader
                    childRows
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var primarySection: some View {
        if row.primaryBudgetID != nil {
            Button(action: onEditPrimary) {
                primaryContent
            }
            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
        } else {
            primaryContent
        }
    }

    private var primaryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: row.iconSymbolName, color: toneColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(row.spentMinor.formattedCurrency(code: row.currencyCode)) / \(row.limitMinor.formattedCurrency(code: row.currencyCode))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text(row.progress.percentText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(toneColor)
            }

            PlanningProgressBar(progress: row.progressClamped, tint: toneColor)

            Text(daysText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var childHeader: some View {
        HStack(spacing: 8) {
            Text(
                mistiaLocalized(
                    vi: "Ngân sách con",
                    en: "Child budgets",
                    ja: "子カテゴリ予算"
                )
            )
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var childRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(row.childRows.enumerated()), id: \.element.id) { index, childRow in
                Button {
                    onEditChild(childRow)
                } label: {
                    PlanningBudgetRowView(row: childRow, referenceDate: referenceDate)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        }
                }
                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))

                if index < row.childRows.count - 1 {
                    Divider()
                        .padding(.leading, 48)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private var toneColor: Color {
        switch row.tone {
        case .calm:
            Color(hex: "#2DAA9E")
        case .warning:
            Color(hex: "#F59B3F")
        case .critical:
            Color(hex: "#F45C7E")
        }
    }

    private var daysText: String {
        if row.isPastMonth {
            return mistiaLocalized(vi: "Tháng đã kết thúc", en: "Month ended", ja: "月が終了しました")
        }

        return mistiaLocalized(
            vi: "Còn \(row.daysRemaining) ngày",
            en: "\(row.daysRemaining) days left",
            ja: "あと \(row.daysRemaining) 日"
        )
    }
}

private struct PlanningBudgetRowView: View {
    let row: PlanningBudgetRowSnapshot
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: row.iconSymbolName, color: toneColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(row.spentMinor.formattedCurrency(code: row.currencyCode)) / \(row.limitMinor.formattedCurrency(code: row.currencyCode))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text(row.progress.percentText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(toneColor)
            }

            PlanningProgressBar(progress: row.progressClamped, tint: toneColor)

            Text(daysText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var toneColor: Color {
        switch row.tone {
        case .calm:
            Color(hex: "#2DAA9E")
        case .warning:
            Color(hex: "#F59B3F")
        case .critical:
            Color(hex: "#F45C7E")
        }
    }

    private var daysText: String {
        if row.isPastMonth {
            return mistiaLocalized(vi: "Tháng đã kết thúc", en: "Month ended", ja: "月が終了しました")
        }

        return mistiaLocalized(
            vi: "Còn \(row.daysRemaining) ngày",
            en: "\(row.daysRemaining) days left",
            ja: "あと \(row.daysRemaining) 日"
        )
    }
}

private struct PlanningGoalRowView: View {
    let row: PlanningGoalRowSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: row.iconSymbolName, color: Color(hex: "#2DAA9E"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(row.currentSavedMinor.formattedCurrency(code: row.currencyCode)) / \(row.targetMinor.formattedCurrency(code: row.currencyCode))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            PlanningProgressBar(progress: row.progressClamped, tint: Color(hex: "#2DAA9E"))

            HStack {
                Text(row.targetDate.shortDisplayText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    mistiaLocalized(
                        vi: "Cần thêm \(row.monthlyRequiredMinor.formattedCurrency(code: row.currencyCode))/tháng",
                        en: "Need \(row.monthlyRequiredMinor.formattedCurrency(code: row.currencyCode))/month",
                        ja: "毎月あと \(row.monthlyRequiredMinor.formattedCurrency(code: row.currencyCode)) 必要"
                    )
                )
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#5B7BFF"))
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct PlanningDueRow: View {
    let item: PlanningRecurringDueSnapshot
    let referenceDate: Date
    let onTap: () -> Void
    let onPay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PlanningIconTile(icon: item.iconSymbolName, color: tone.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(amountText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                if showsPayButton {
                    PlanningDueActionButton(title: mistiaLocalized(vi: "Thanh toán", en: "Pay", ja: "支払う")) {
                        onPay()
                    }
                } else {
                    PlanningStatusBadge(title: statusText, color: tone.color)
                }
            }

            HStack {
                Text(item.dueDate.shortDisplayText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(dueDetailText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(tone.color)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var tone: PlanningDueRowTone {
        item.tone(referenceDate: referenceDate)
    }

    private var amountText: String {
        if let amount = item.amountMinor {
            return amount.formattedCurrency(code: item.currencyCode)
        }
        return mistiaLocalized(vi: "Chưa nhập số tiền", en: "No amount yet", ja: "金額未入力")
    }

    private var statusText: String {
        switch item.status {
        case .paid:
            mistiaLocalized(vi: "Đã thanh toán", en: "Paid", ja: "支払い済み")
        case .pending:
            switch item.sourceKind {
            case .recurringBill:
                mistiaLocalized(vi: "Sắp đến hạn", en: "Upcoming", ja: "まもなく")
            case .installment:
                mistiaLocalized(vi: "Trả góp / vay", en: "Installment / loan", ja: "分割払い・借入")
            case .creditCard:
                mistiaLocalized(vi: "Đến hạn", en: "Due", ja: "支払予定")
            }
        }
    }

    private var showsPayButton: Bool {
        item.sourceKind == .recurringBill && item.status != .paid
    }

    private var dueDetailText: String {
        if item.status == .paid {
            return mistiaLocalized(vi: "Hoàn tất", en: "Completed", ja: "完了")
        }

        let dayDelta = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: referenceDate),
            to: Calendar.current.startOfDay(for: item.dueDate)
        ).day ?? 0

        if dayDelta < 0 {
            return mistiaLocalized(
                vi: "Quá hạn \(-dayDelta) ngày",
                en: "Overdue by \(-dayDelta) days",
                ja: "\(-dayDelta) 日延滞"
            )
        }
        if dayDelta == 0 {
            return mistiaLocalized(vi: "Đến hạn hôm nay", en: "Due today", ja: "本日支払い")
        }
        return mistiaLocalized(
            vi: "Còn \(dayDelta) ngày",
            en: "\(dayDelta) days left",
            ja: "あと \(dayDelta) 日"
        )
    }
}

private struct PlanningDueActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let action: () -> Void

    private var accent: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    label
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(accent)
            } else {
                Button(action: action) {
                    label
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            MistiaCapsuleGlassBackground(
                                tint: accent.opacity(colorScheme == .dark ? 0.18 : 0.12),
                                interactive: true
                            )
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
    }
}

private struct PlanningCreditCardCard: View {
    let item: PlanningCreditCardAccountSnapshot
    let onOpenStatement: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issuerTitle.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                        Text(item.network.title.uppercased())
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    Text(maskedLast4)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer(minLength: 14)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.walletName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(mistiaLocalized(vi: "Khả dụng", en: "Available", ja: "利用可能"))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))

                    Text(item.availableCreditMinor.formattedCurrency(code: item.currencyCode))
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(paymentSourceText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                HStack(alignment: .bottom, spacing: 12) {
                    HStack(spacing: 10) {
                        statementMiniLabel(
                            title: mistiaLocalized(vi: "Chốt", en: "Close", ja: "締め"),
                            value: "\(item.statementClosingDay)"
                        )
                        statementMiniLabel(
                            title: mistiaLocalized(vi: "Hạn", en: "Due", ja: "支払"),
                            value: "\(item.dueDay)"
                        )
                    }

                    Spacer(minLength: 10)

                    Button(action: onOpenStatement) {
                        Label(
                            mistiaLocalized(vi: "Sao kê", en: "Statement", ja: "明細"),
                            systemImage: "doc.text"
                        )
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                }
        }
    }

    private var maskedLast4: String {
        "•••• \(item.last4)"
    }

    private var issuerTitle: String {
        let trimmed = item.issuerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? item.network.title : trimmed
    }

    private var paymentSourceText: String {
        if let name = item.paymentSourceWalletName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return mistiaLocalized(vi: "Ví liên kết: \(name)", en: "Linked wallet: \(name)", ja: "連携ウォレット: \(name)")
        }
        return mistiaLocalized(vi: "Chưa chọn ví liên kết", en: "No linked wallet", ja: "連携ウォレット未設定")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#151922"),
                        Color(hex: "#3A2B78"),
                        Color(hex: "#2DAA9E").opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .frame(width: 92, height: 52)
                    .rotationEffect(.degrees(-10))
                    .offset(x: 18, y: 16)
            }
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 34)
                    .blur(radius: 18)
                    .offset(y: 14)
            }
    }

    private func statementMiniLabel(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 13.5, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(0.13), in: Capsule())
    }
}

private struct PlanningListCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(
            cornerRadius: 22,
            tint: cardTint,
            padding: 0
        ) {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct PlanningFooterAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        MistiaFooterAddButton(title: title, accent: planningAccentPurple, action: action)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }
}

private struct PlanningEmptyStateCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let message: String
    let buttonTitle: String
    let accent: Color
    let symbols: [String]
    let action: () -> Void

    private var cardTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .white.opacity(0.12)
    }

    var body: some View {
        MistiaBlockCard(
            cornerRadius: 24,
            tint: cardTint,
            padding: 0
        ) {
            MistiaEmptyStateContent(
                title: title,
                message: message,
                buttonTitle: buttonTitle,
                accent: accent,
                symbols: symbols,
                action: action
            )
        }
    }
}

private struct PlanningProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                let clamped = min(max(progress, 0), 1)

                Capsule()
                    .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))

                Capsule()
                    .fill(tint.opacity(colorScheme == .dark ? 0.94 : 0.82))
                    .frame(width: max(proxy.size.width * clamped, progress > 0 ? 18 : 0))
            }
        }
        .frame(height: 10)
    }
}

private struct PlanningSemiGauge: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let text: String
    let tint: Color

    private let lineWidth: CGFloat = 13

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                PlanningSemiGaugeArc(progress: 1)
                    .stroke(
                        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                PlanningSemiGaugeArc(progress: min(max(progress, 0), 1))
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .shadow(color: progress >= 1 ? gaugeColor.opacity(0.24) : .clear, radius: 4, y: 2)

                VStack(spacing: 2) {
                    Text(text)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(gaugeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if progress > 1 {
                        Text(mistiaLocalized(vi: "vượt", en: "over", ja: "超過"))
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(gaugeColor)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(width: 126, height: 72)

            if progress > 1 {
                Text("+\(Int(((progress - 1) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(gaugeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(gaugeColor.opacity(0.12), in: Capsule())
            }
        }
    }

    private var gaugeColor: Color {
        progress >= 1 ? Color(hex: "#F45C7E") : tint
    }
}

private struct PlanningSemiGaugeArc: Shape {
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

private struct PlanningMetricColumn: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanningStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct PlanningIconTile: View {
    let icon: String
    let color: Color

    var body: some View {
        MistiaFinanceIconView(icon: icon, fallbackColor: color, size: 32)
    }
}

private struct PlanningMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date

    let calendar: Calendar

    @State private var draftMonth: Int
    @State private var draftYear: Int

    init(selection: Binding<Date>, calendar: Calendar) {
        _selection = selection
        self.calendar = calendar
        let initialDate = selection.wrappedValue
        _draftMonth = State(initialValue: calendar.component(.month, from: initialDate))
        _draftYear = State(initialValue: calendar.component(.year, from: initialDate))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Picker(mistiaLocalized(vi: "Tháng", en: "Month", ja: "月"), selection: $draftMonth) {
                        ForEach(allowedMonths, id: \.self) { month in
                            Text(
                                mistiaLocalized(
                                    vi: "Tháng \(month)",
                                    en: "Month \(month)",
                                    ja: "\(month)月"
                                )
                            )
                            .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker(mistiaLocalized(vi: "Năm", en: "Year", ja: "年"), selection: $draftYear) {
                        ForEach(yearOptions, id: \.self) { year in
                            Text(
                                mistiaLocalized(
                                    vi: "Năm \(year)",
                                    en: "Year \(year)",
                                    ja: "\(year)年"
                                )
                            )
                            .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .onChange(of: draftYear) { _, _ in
                        validateDraft()
                    }
                }
                .frame(height: 220)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .navigationTitle(mistiaLocalized(vi: "Chọn tháng", en: "Choose month", ja: "月を選択"))
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
                        applySelection()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(planningAccentPurple)
                }
            }
        }
    }

    private var allowedMonths: [Int] {
        let currentYear = calendar.component(.year, from: .now)
        if draftYear < currentYear {
            return Array(1...12)
        } else {
            let currentMonth = calendar.component(.month, from: .now)
            return Array(1...currentMonth)
        }
    }

    private var yearOptions: [Int] {
        let currentYear = calendar.component(.year, from: .now)
        let lowerBound = currentYear - 10
        let upperBound = currentYear
        return Array(lowerBound...upperBound)
    }

    private func validateDraft() {
        let currentYear = calendar.component(.year, from: .now)
        let currentMonth = calendar.component(.month, from: .now)
        
        if draftYear == currentYear && draftMonth > currentMonth {
            draftMonth = currentMonth
        }
    }

    private func applySelection() {
        guard let date = calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: 1)) else {
            return
        }

        let startOfTarget = PlanningLogic.startOfMonth(for: date, calendar: calendar)
        let startOfCurrent = PlanningLogic.startOfMonth(for: .now, calendar: calendar)

        if startOfTarget > startOfCurrent {
            selection = startOfCurrent
        } else {
            selection = startOfTarget
        }

        dismiss()
    }
}

private extension Date {
    func monthDisplayText(calendar: Calendar) -> String {
        MistiaDateFormatting.monthYearString(for: self, calendar: calendar)
    }

    var shortDisplayText: String {
        MistiaDateFormatting.shortDateString(for: self)
    }
}

private extension Double {
    var percentText: String {
        "\(Int((self * 100).rounded()))%"
    }
}
