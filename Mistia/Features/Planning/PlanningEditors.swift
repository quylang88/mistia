import SwiftData
import SwiftUI

struct PlanningBudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.createdAt)])
    private var storedCategories: [TransactionCategory]
    @Query(sort: [SortDescriptor(\BudgetPlan.monthAnchor), SortDescriptor(\BudgetPlan.createdAt)])
    private var storedBudgets: [BudgetPlan]

    let target: PlanningBudgetEditorTarget

    @State private var draft: PlanningBudgetDraft
    @State private var alertMessage: String?
    @State private var showsDeleteConfirmation = false

    init(target: PlanningBudgetEditorTarget) {
        self.target = target
        _draft = State(initialValue: PlanningBudgetDraft(budget: target.budget))
    }

    private var availableCategories: [TransactionCategory] {
        storedCategories
            .filter { $0.kind == .expense && !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var activeCurrencyCode: String {
        target.budget?.currencyCode ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Ngân sách", en: "Budget", ja: "予算")) {
                    Picker(mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ"), selection: $draft.categoryID) {
                        Text(mistiaLocalized(vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択")).tag(Optional<UUID>.none)
                        ForEach(availableCategories) { category in
                            Text(category.localizedDisplayName).tag(Optional(category.id))
                        }
                    }

                    TextField(mistiaLocalized(vi: "Số tiền ngân sách", en: "Budget amount", ja: "予算金額"), text: $draft.limitText)
                        .keyboardType(.numberPad)

                    LabeledContent(mistiaLocalized(vi: "Chu kỳ", en: "Cycle", ja: "周期")) {
                        Text(mistiaLocalized(vi: "Theo tháng", en: "Monthly", ja: "毎月"))
                            .foregroundStyle(.secondary)
                    }

                    Toggle(mistiaLocalized(vi: "Rollover", en: "Rollover", ja: "繰り越し"), isOn: $draft.rolloverEnabled)
                }

                if target.budget != nil {
                    Section {
                        Button(mistiaLocalized(vi: "Xóa ngân sách", en: "Delete budget", ja: "予算を削除"), role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(mistiaCatalog(target.budget == nil ? "Ngân sách mới" : "Sửa ngân sách"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save
                )
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            mistiaLocalized(vi: "Xóa ngân sách này?", en: "Delete this budget?", ja: "この予算を削除しますか？"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Xóa", en: "Delete", ja: "削除"), role: .destructive) {
                deleteBudget()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(mistiaLocalized(vi: "Ngân sách của danh mục này trong tháng đang xem sẽ bị xóa.", en: "The budget for this category in the current month will be deleted.", ja: "現在表示中の月にあるこのカテゴリの予算が削除されます。"))
        }
    }

    private func save() {
        guard let categoryID = draft.categoryID,
              let category = storedCategories.first(where: { $0.id == categoryID })
        else {
            alertMessage = mistiaLocalized(vi: "Chọn danh mục trước khi lưu.", en: "Choose a category before saving.", ja: "保存する前にカテゴリを選択してください。")
            return
        }

        let limitMinor = draft.limitText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        guard limitMinor > 0 else {
            alertMessage = mistiaLocalized(vi: "Nhập số tiền ngân sách lớn hơn 0.", en: "Enter a budget amount greater than 0.", ja: "0 より大きい予算金額を入力してください。")
            return
        }

        let monthAnchor = PlanningLogic.startOfMonth(for: target.selectedMonth)
        let hasDuplicate = storedBudgets.contains(where: { budget in
            guard !budget.isArchived else { return false }
            guard budget.id != target.budget?.id else { return false }
            guard PlanningLogic.startOfMonth(for: budget.monthAnchor) == monthAnchor else { return false }
            return budget.category?.id == categoryID
        })

        guard !hasDuplicate else {
            alertMessage = mistiaLocalized(vi: "Danh mục này đã có ngân sách trong tháng đang xem.", en: "This category already has a budget in the selected month.", ja: "このカテゴリには表示中の月ですでに予算があります。")
            return
        }

        let now = Date()
        if let budget = target.budget {
            budget.category = category
            budget.limitMinor = limitMinor
            budget.rolloverEnabled = draft.rolloverEnabled
            budget.monthAnchor = monthAnchor
            budget.updatedAt = now
        } else {
            let budget = BudgetPlan(
                category: category,
                monthAnchor: monthAnchor,
                limitMinor: limitMinor,
                rolloverEnabled: draft.rolloverEnabled,
                currencyCode: activeCurrencyCode,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(budget)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu ngân sách lúc này.", en: "Couldn't save this budget right now.", ja: "現在この予算を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func deleteBudget() {
        guard let budget = target.budget else { return }
        modelContext.delete(budget)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể xóa ngân sách lúc này.", en: "Couldn't delete this budget right now.", ja: "現在この予算を削除できません。") + " \(error.localizedDescription)"
        }
    }
}

struct PlanningGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]
    @Query(sort: [SortDescriptor(\SavingsGoal.sortOrder), SortDescriptor(\SavingsGoal.createdAt)])
    private var storedGoals: [SavingsGoal]

    let target: PlanningGoalEditorTarget

    @State private var draft: PlanningGoalDraft
    @State private var alertMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsIconPicker = false

    init(target: PlanningGoalEditorTarget) {
        self.target = target
        _draft = State(initialValue: PlanningGoalDraft(goal: target.goal))
    }

    private var availableWallets: [LedgerWallet] {
        storedWallets
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var activeCurrencyCode: String {
        target.goal?.currencyCode ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Nhận diện", en: "Identity", ja: "識別情報")) {
                    PlanningIconPickerButton(
                        title: mistiaCatalog("Icon mục tiêu"),
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(mistiaLocalized(vi: "Mục tiêu", en: "Goal", ja: "目標")) {
                    TextField(mistiaLocalized(vi: "Tên mục tiêu", en: "Goal name", ja: "目標名"), text: $draft.name)
                    TextField(mistiaLocalized(vi: "Số tiền mục tiêu", en: "Target amount", ja: "目標金額"), text: $draft.targetText)
                        .keyboardType(.numberPad)
                    TextField(mistiaLocalized(vi: "Số tiền hiện tại", en: "Current amount", ja: "現在額"), text: $draft.currentText)
                        .keyboardType(.numberPad)
                    DatePicker(mistiaLocalized(vi: "Ngày mục tiêu", en: "Target date", ja: "目標日"), selection: $draft.targetDate, displayedComponents: [.date])

                    Picker(mistiaLocalized(vi: "Ví liên kết", en: "Linked wallet", ja: "連携ウォレット"), selection: $draft.linkedWalletID) {
                        Text(mistiaLocalized(vi: "Không liên kết", en: "Not linked", ja: "未連携")).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }
                }

                if target.goal != nil {
                    Section {
                        Button(mistiaLocalized(vi: "Xóa mục tiêu", en: "Delete goal", ja: "目標を削除"), role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(mistiaCatalog(target.goal == nil ? "Mục tiêu mới" : "Sửa mục tiêu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save
                )
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: mistiaCatalog("Icon mục tiêu"),
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            mistiaLocalized(vi: "Xóa mục tiêu này?", en: "Delete this goal?", ja: "この目標を削除しますか？"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Xóa", en: "Delete", ja: "削除"), role: .destructive) {
                deleteGoal()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = mistiaLocalized(vi: "Nhập tên mục tiêu trước khi lưu.", en: "Enter a goal name before saving.", ja: "保存する前に目標名を入力してください。")
            return
        }

        let targetMinor = draft.targetText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        guard targetMinor > 0 else {
            alertMessage = mistiaLocalized(vi: "Nhập số tiền mục tiêu lớn hơn 0.", en: "Enter a target amount greater than 0.", ja: "0 より大きい目標金額を入力してください。")
            return
        }

        let currentMinor = draft.currentText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        let linkedWallet = storedWallets.first(where: { $0.id == draft.linkedWalletID })
        let now = Date()

        if let goal = target.goal {
            goal.name = trimmedName
            goal.iconSymbolName = draft.iconSymbolName
            goal.targetMinor = targetMinor
            goal.currentSavedMinor = currentMinor
            goal.targetDate = draft.targetDate
            goal.linkedWallet = linkedWallet
            goal.updatedAt = now
        } else {
            let goal = SavingsGoal(
                name: trimmedName,
                iconSymbolName: draft.iconSymbolName,
                targetMinor: targetMinor,
                currentSavedMinor: currentMinor,
                targetDate: draft.targetDate,
                linkedWallet: linkedWallet,
                currencyCode: activeCurrencyCode,
                sortOrder: nextSortOrder(),
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(goal)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu mục tiêu lúc này.", en: "Couldn't save this goal right now.", ja: "現在この目標を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func deleteGoal() {
        guard let goal = target.goal else { return }
        modelContext.delete(goal)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể xóa mục tiêu lúc này.", en: "Couldn't delete this goal right now.", ja: "現在この目標を削除できません。") + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedGoals.filter { !$0.isArchived }.map(\.sortOrder).max() ?? -1) + 1
    }
}

struct PlanningBillEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]
    @Query(sort: [SortDescriptor(\DueOccurrenceRecord.updatedAt, order: .reverse), SortDescriptor(\DueOccurrenceRecord.createdAt, order: .reverse)])
    private var storedOccurrences: [DueOccurrenceRecord]

    let target: PlanningBillEditorTarget

    @State private var draft: PlanningBillDraft
    @State private var paymentAmountText: String
    @State private var alertMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsIconPicker = false

    init(target: PlanningBillEditorTarget) {
        self.target = target
        let initialDraft = PlanningBillDraft(plan: target.plan)
        _draft = State(initialValue: initialDraft)
        _paymentAmountText = State(initialValue: target.dueItem?.amountMinor.map(String.init) ?? initialDraft.amountText)
    }

    private var availableWallets: [LedgerWallet] {
        storedWallets
            .filter { !$0.isArchived && $0.kind != .creditCard }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var activeCurrencyCode: String {
        target.plan?.currencyCode ?? target.dueItem?.currencyCode ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Nhận diện", en: "Identity", ja: "識別情報")) {
                    PlanningIconPickerButton(
                        title: mistiaCatalog("Icon hóa đơn"),
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(mistiaLocalized(vi: "Hóa đơn định kỳ", en: "Recurring bill", ja: "定期請求")) {
                    TextField(mistiaLocalized(vi: "Tên hóa đơn", en: "Bill name", ja: "請求名"), text: $draft.name)
                    TextField(mistiaLocalized(vi: "Số tiền (có thể để trống)", en: "Amount (optional)", ja: "金額（任意）"), text: $draft.amountText)
                        .keyboardType(.numberPad)
                    Picker(mistiaLocalized(vi: "Ngày đến hạn", en: "Due day", ja: "支払日"), selection: $draft.dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(mistiaLocalized(vi: "Ngày \(day)", en: "Day \(day)", ja: "\(day) 日")).tag(day)
                        }
                    }
                    Stepper(
                        mistiaLocalized(
                            vi: "Tần suất: \(draft.frequencyMonths) tháng",
                            en: "Frequency: every \(draft.frequencyMonths) month(s)",
                            ja: "頻度: \(draft.frequencyMonths) か月ごと"
                        ),
                        value: $draft.frequencyMonths,
                        in: 1...12
                    )
                    Picker(mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット"), selection: $draft.paymentWalletID) {
                        Text(mistiaLocalized(vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択")).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }
                }

                if let dueItem = target.dueItem, dueItem.status == .pending {
                    Section {
                        TextField(mistiaLocalized(vi: "Số tiền thanh toán", en: "Payment amount", ja: "支払い金額"), text: $paymentAmountText)
                            .keyboardType(.numberPad)

                        Button(mistiaLocalized(vi: "Thanh toán trước", en: "Pay early", ja: "先に支払う")) {
                            payEarly()
                        }
                    } header: {
                        Text(mistiaLocalized(vi: "Thanh toán trước", en: "Early payment", ja: "前倒し支払い"))
                    } footer: {
                        Text(mistiaLocalized(vi: "Thanh toán ngay sẽ tạo giao dịch chi tiêu thật ở tab Giao dịch.", en: "Paying now will create a real expense transaction in the Transactions tab.", ja: "今すぐ支払うと、取引タブに実際の支出取引が作成されます。"))
                    }
                }

                if target.plan != nil {
                    Section {
                        Button(mistiaLocalized(vi: "Xóa hóa đơn", en: "Delete bill", ja: "請求を削除"), role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(mistiaCatalog(target.plan == nil ? "Hóa đơn mới" : "Sửa hóa đơn"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save
                )
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: mistiaCatalog("Icon hóa đơn"),
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            mistiaLocalized(vi: "Xóa hóa đơn này?", en: "Delete this bill?", ja: "この請求を削除しますか？"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Xóa", en: "Delete", ja: "削除"), role: .destructive) {
                deletePlan()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = mistiaLocalized(vi: "Nhập tên hóa đơn trước khi lưu.", en: "Enter a bill name before saving.", ja: "保存する前に請求名を入力してください。")
            return
        }

        guard let wallet = storedWallets.first(where: { $0.id == draft.paymentWalletID }) else {
            alertMessage = mistiaLocalized(vi: "Chọn ví thanh toán cho hóa đơn.", en: "Choose a payment wallet for this bill.", ja: "この請求の支払いウォレットを選択してください。")
            return
        }

        let amountMinor = draft.amountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        let now = Date()

        if let plan = target.plan {
            plan.name = trimmedName
            plan.iconSymbolName = draft.iconSymbolName
            plan.amountMinor = amountMinor
            plan.dueDay = draft.dueDay
            plan.frequencyMonths = draft.frequencyMonths
            plan.paymentWallet = wallet
            plan.updatedAt = now
        } else {
            let plan = RecurringBillPlan(
                name: trimmedName,
                iconSymbolName: draft.iconSymbolName,
                amountMinor: amountMinor,
                dueDay: draft.dueDay,
                frequencyMonths: draft.frequencyMonths,
                paymentWallet: wallet,
                currencyCode: activeCurrencyCode,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(plan)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu hóa đơn lúc này.", en: "Couldn't save this bill right now.", ja: "現在この請求を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func payEarly() {
        guard let dueItem = target.dueItem else { return }

        do {
            let draft = try PlanningLogic.makePaymentDraft(
                for: dueItem,
                overrideAmountMinor: paymentAmountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
            )
            _ = try PlanningPersistenceSupport.saveDuePayment(
                draft: draft,
                sourceKind: .recurringBill,
                sourceID: dueItem.sourceID,
                selectedMonth: target.selectedMonth,
                scheduledDate: dueItem.dueDate,
                wallets: storedWallets,
                occurrences: Array(storedOccurrences),
                modelContext: modelContext
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deletePlan() {
        guard let plan = target.plan else { return }
        PlanningPersistenceSupport.deleteOccurrences(
            sourceKind: .recurringBill,
            sourceID: plan.id,
            occurrences: Array(storedOccurrences),
            modelContext: modelContext
        )
        modelContext.delete(plan)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể xóa hóa đơn lúc này.", en: "Couldn't delete this bill right now.", ja: "現在この請求を削除できません。") + " \(error.localizedDescription)"
        }
    }
}

struct PlanningInstallmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]
    @Query(sort: [SortDescriptor(\DueOccurrenceRecord.updatedAt, order: .reverse), SortDescriptor(\DueOccurrenceRecord.createdAt, order: .reverse)])
    private var storedOccurrences: [DueOccurrenceRecord]

    let target: PlanningInstallmentEditorTarget

    @State private var draft: PlanningInstallmentDraft
    @State private var paymentAmountText: String
    @State private var alertMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsIconPicker = false

    init(target: PlanningInstallmentEditorTarget) {
        self.target = target
        let initialDraft = PlanningInstallmentDraft(plan: target.plan)
        _draft = State(initialValue: initialDraft)
        _paymentAmountText = State(initialValue: target.dueItem?.amountMinor.map(String.init) ?? initialDraft.amountText)
    }

    private var availableWallets: [LedgerWallet] {
        storedWallets
            .filter { !$0.isArchived && $0.kind != .creditCard }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var activeCurrencyCode: String {
        target.plan?.currencyCode ?? target.dueItem?.currencyCode ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Nhận diện", en: "Identity", ja: "識別情報")) {
                    PlanningIconPickerButton(
                        title: mistiaCatalog("Icon khoản trả góp / vay"),
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(mistiaLocalized(vi: "Khoản trả góp / vay", en: "Installment / loan", ja: "分割払い・借入")) {
                    TextField(mistiaLocalized(vi: "Tên khoản", en: "Name", ja: "名称"), text: $draft.name)
                    TextField(mistiaLocalized(vi: "Số tiền mỗi kỳ", en: "Amount per cycle", ja: "各回の金額"), text: $draft.amountText)
                        .keyboardType(.numberPad)
                    Picker(mistiaLocalized(vi: "Ngày đến hạn", en: "Due day", ja: "支払日"), selection: $draft.dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(mistiaLocalized(vi: "Ngày \(day)", en: "Day \(day)", ja: "\(day) 日")).tag(day)
                        }
                    }
                    Stepper(
                        mistiaLocalized(
                            vi: "Tần suất: \(draft.frequencyMonths) tháng",
                            en: "Frequency: every \(draft.frequencyMonths) month(s)",
                            ja: "頻度: \(draft.frequencyMonths) か月ごと"
                        ),
                        value: $draft.frequencyMonths,
                        in: 1...12
                    )
                    TextField(mistiaLocalized(vi: "Tổng số kỳ (không bắt buộc)", en: "Total cycles (optional)", ja: "支払い回数（任意）"), text: $draft.totalCyclesText)
                        .keyboardType(.numberPad)
                    Picker(mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット"), selection: $draft.paymentWalletID) {
                        Text(mistiaLocalized(vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択")).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }
                }

                if let dueItem = target.dueItem, dueItem.status == .pending {
                    Section {
                        TextField(mistiaLocalized(vi: "Số tiền thanh toán", en: "Payment amount", ja: "支払い金額"), text: $paymentAmountText)
                            .keyboardType(.numberPad)

                        Button(mistiaLocalized(vi: "Thanh toán trước", en: "Pay early", ja: "先に支払う")) {
                            payEarly()
                        }
                    } header: {
                        Text(mistiaLocalized(vi: "Thanh toán trước", en: "Early payment", ja: "前倒し支払い"))
                    } footer: {
                        Text(mistiaLocalized(vi: "Khoản này sẽ được ghi nhận thành giao dịch chi tiêu thật.", en: "This payment will be recorded as a real expense transaction.", ja: "この支払いは実際の支出取引として記録されます。"))
                    }
                }

                if target.plan != nil {
                    Section {
                        Button(mistiaLocalized(vi: "Xóa khoản này", en: "Delete this item", ja: "この項目を削除"), role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(mistiaCatalog(target.plan == nil ? "Khoản mới" : "Sửa khoản"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save
                )
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: mistiaCatalog("Icon khoản trả góp / vay"),
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            mistiaLocalized(vi: "Xóa khoản này?", en: "Delete this item?", ja: "この項目を削除しますか？"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Xóa", en: "Delete", ja: "削除"), role: .destructive) {
                deletePlan()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = mistiaLocalized(vi: "Nhập tên khoản trước khi lưu.", en: "Enter a name before saving.", ja: "保存する前に名前を入力してください。")
            return
        }

        let amountMinor = draft.amountText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        guard amountMinor > 0 else {
            alertMessage = mistiaLocalized(vi: "Nhập số tiền mỗi kỳ lớn hơn 0.", en: "Enter an amount per cycle greater than 0.", ja: "各回の金額は 0 より大きくしてください。")
            return
        }

        guard let wallet = storedWallets.first(where: { $0.id == draft.paymentWalletID }) else {
            alertMessage = mistiaLocalized(vi: "Chọn ví thanh toán cho khoản này.", en: "Choose a payment wallet for this item.", ja: "この項目の支払いウォレットを選択してください。")
            return
        }

        let totalCycles = draft.totalCyclesText.nilIfBlank.flatMap(Int.init)
        let now = Date()

        if let plan = target.plan {
            plan.name = trimmedName
            plan.iconSymbolName = draft.iconSymbolName
            plan.amountPerCycleMinor = amountMinor
            plan.dueDay = draft.dueDay
            plan.totalCycles = totalCycles
            plan.frequencyMonths = draft.frequencyMonths
            plan.paymentWallet = wallet
            plan.updatedAt = now
        } else {
            let plan = InstallmentPlan(
                name: trimmedName,
                iconSymbolName: draft.iconSymbolName,
                amountPerCycleMinor: amountMinor,
                dueDay: draft.dueDay,
                totalCycles: totalCycles,
                frequencyMonths: draft.frequencyMonths,
                paymentWallet: wallet,
                currencyCode: activeCurrencyCode,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(plan)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu khoản này lúc này.", en: "Couldn't save this item right now.", ja: "現在この項目を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func payEarly() {
        guard let dueItem = target.dueItem else { return }

        do {
            let draft = try PlanningLogic.makePaymentDraft(
                for: dueItem,
                overrideAmountMinor: paymentAmountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
            )
            _ = try PlanningPersistenceSupport.saveDuePayment(
                draft: draft,
                sourceKind: .installment,
                sourceID: dueItem.sourceID,
                selectedMonth: target.selectedMonth,
                scheduledDate: dueItem.dueDate,
                wallets: storedWallets,
                occurrences: Array(storedOccurrences),
                modelContext: modelContext
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deletePlan() {
        guard let plan = target.plan else { return }
        PlanningPersistenceSupport.deleteOccurrences(
            sourceKind: .installment,
            sourceID: plan.id,
            occurrences: Array(storedOccurrences),
            modelContext: modelContext
        )
        modelContext.delete(plan)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể xóa khoản này lúc này.", en: "Couldn't delete this item right now.", ja: "現在この項目を削除できません。") + " \(error.localizedDescription)"
        }
    }
}

struct PlanningCreditCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]
    @Query(sort: [SortDescriptor(\DueOccurrenceRecord.updatedAt, order: .reverse), SortDescriptor(\DueOccurrenceRecord.createdAt, order: .reverse)])
    private var storedOccurrences: [DueOccurrenceRecord]

    let target: PlanningCreditCardEditorTarget

    @State private var draft: PlanningCreditCardDraft
    @State private var paymentAmountText: String
    @State private var alertMessage: String?
    @State private var showsArchiveConfirmation = false
    @State private var showsIconPicker = false

    init(target: PlanningCreditCardEditorTarget) {
        self.target = target
        let initialDraft = PlanningCreditCardDraft(wallet: target.wallet)
        _draft = State(initialValue: initialDraft)
        _paymentAmountText = State(initialValue: target.dueItem.map { String($0.amountMinor) } ?? initialDraft.currentDebtText)
    }

    private var availablePaymentWallets: [LedgerWallet] {
        storedWallets
            .filter { wallet in
                !wallet.isArchived
                    && wallet.kind != .creditCard
                    && wallet.id != target.wallet?.id
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var activeCurrencyCode: String {
        target.wallet?.currencyCode ?? target.dueItem?.currencyCode ?? currencyCode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Nhận diện", en: "Identity", ja: "識別情報")) {
                    PlanningIconPickerButton(
                        title: mistiaCatalog("Biểu tượng thẻ"),
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(mistiaLocalized(vi: "Thông tin thẻ", en: "Card details", ja: "カード情報")) {
                    TextField(mistiaLocalized(vi: "Tên thẻ", en: "Card name", ja: "カード名"), text: $draft.name)
                    TextField(mistiaLocalized(vi: "Tên đơn vị phát hành", en: "Issuer name", ja: "発行会社名"), text: $draft.issuerName)
                    Picker(mistiaLocalized(vi: "Mạng thẻ", en: "Card network", ja: "カードブランド"), selection: $draft.network) {
                        ForEach(CreditCardNetwork.allCases) { network in
                            Text(network.title).tag(network)
                        }
                    }
                    TextField(mistiaLocalized(vi: "4 số cuối", en: "Last 4 digits", ja: "下4桁"), text: $draft.last4)
                        .keyboardType(.numberPad)
                        .onChange(of: draft.last4) { _, newValue in
                            draft.last4 = String(newValue.filter(\.isNumber).prefix(4))
                        }
                    TextField(mistiaLocalized(vi: "Dư nợ hiện tại", en: "Current balance", ja: "現在の残高"), text: $draft.currentDebtText)
                        .keyboardType(.numberPad)
                    TextField(mistiaLocalized(vi: "Hạn mức", en: "Credit limit", ja: "利用限度額"), text: $draft.creditLimitText)
                        .keyboardType(.numberPad)
                    Picker(mistiaLocalized(vi: "Ngày đến hạn", en: "Due day", ja: "支払日"), selection: $draft.paymentDueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(mistiaLocalized(vi: "Ngày \(day)", en: "Day \(day)", ja: "\(day) 日")).tag(day)
                        }
                    }
                    Picker(mistiaLocalized(vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日"), selection: $draft.statementClosingDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(mistiaLocalized(vi: "Ngày \(day)", en: "Day \(day)", ja: "\(day) 日")).tag(day)
                        }
                    }
                    Picker(mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払いウォレット"), selection: $draft.paymentSourceWalletID) {
                        Text(mistiaLocalized(vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択")).tag(Optional<UUID>.none)
                        ForEach(availablePaymentWallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }
                    TextField(mistiaLocalized(vi: "Ghi chú", en: "Notes", ja: "メモ"), text: $draft.notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                if target.wallet != nil, let dueItem = currentDueSnapshot, dueItem.status == .pending {
                    Section {
                        TextField(mistiaLocalized(vi: "Số tiền thanh toán", en: "Payment amount", ja: "支払い金額"), text: $paymentAmountText)
                            .keyboardType(.numberPad)
                        Button(mistiaLocalized(vi: "Thanh toán trước", en: "Pay early", ja: "先に支払う")) {
                            payEarly(with: dueItem)
                        }
                    } header: {
                        Text(mistiaLocalized(vi: "Thanh toán trước", en: "Early payment", ja: "前倒し支払い"))
                    } footer: {
                        Text(mistiaLocalized(vi: "Khoản thanh toán sẽ được ghi nhận thành giao dịch chuyển tiền sang thẻ tín dụng.", en: "This payment will be recorded as a transfer transaction to the credit card.", ja: "この支払いはクレジットカードへの振替取引として記録されます。"))
                    }
                }

                if target.wallet != nil {
                    Section {
                        Button(mistiaLocalized(vi: "Lưu trữ thẻ", en: "Archive card", ja: "カードをアーカイブ"), role: .destructive) {
                            showsArchiveConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(mistiaCatalog(target.wallet == nil ? "Thẻ mới" : "Sửa thẻ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save
                )
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: mistiaCatalog("Biểu tượng thẻ"),
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            mistiaLocalized(vi: "Lưu trữ thẻ này?", en: "Archive this card?", ja: "このカードをアーカイブしますか？"),
            isPresented: $showsArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Lưu trữ", en: "Archive", ja: "アーカイブ"), role: .destructive) {
                archiveWallet()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        }
    }

    private var currentDueSnapshot: PlanningCreditCardDueSnapshot? {
        guard let wallet = target.wallet else { return nil }

        return PlanningCreditCardDueSnapshot(
            id: wallet.id,
            walletID: wallet.id,
            walletName: draft.name.nilIfBlank ?? wallet.name,
            network: draft.network,
            last4: draft.last4,
            amountMinor: max(
                paymentAmountText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode),
                draft.currentDebtText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
            ),
            dueDate: target.dueItem?.dueDate ?? PlanningLogic.scheduledDate(dueDay: draft.paymentDueDay, selectedMonth: target.selectedMonth),
            paymentSourceWalletID: draft.paymentSourceWalletID,
            currencyCode: wallet.currencyCode,
            status: target.dueItem?.status ?? .pending,
            linkedTransactionID: target.dueItem?.linkedTransactionID
        )
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = mistiaLocalized(vi: "Nhập tên thẻ trước khi lưu.", en: "Enter a card name before saving.", ja: "保存する前にカード名を入力してください。")
            return
        }

        let currentDebtMinor = draft.currentDebtText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        let creditLimitMinor = draft.creditLimitText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        let now = Date()

        if let wallet = target.wallet {
            wallet.name = trimmedName
            wallet.iconSymbolName = draft.iconSymbolName
            wallet.iconColorHex = draft.iconColorHex
            wallet.openingBalanceMinor = currentDebtMinor
            wallet.updatedAt = now
            updateProfile(for: wallet, creditLimitMinor: creditLimitMinor, now: now)
        } else {
            let wallet = LedgerWallet(
                name: trimmedName,
                kind: .creditCard,
                iconSymbolName: draft.iconSymbolName,
                iconColorHex: draft.iconColorHex,
                currencyCode: activeCurrencyCode,
                openingBalanceMinor: currentDebtMinor,
                sortOrder: nextSortOrder(),
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(wallet)
            updateProfile(for: wallet, creditLimitMinor: creditLimitMinor, now: now)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu thẻ lúc này.", en: "Couldn't save this card right now.", ja: "現在このカードを保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func updateProfile(for wallet: LedgerWallet, creditLimitMinor: Int64, now: Date) {
        let profile = wallet.creditCardProfile ?? CreditCardProfile()
        profile.wallet = wallet
        profile.issuerName = draft.issuerName.nilIfBlank ?? ""
        profile.network = draft.network
        profile.last4 = draft.last4
        profile.creditLimitMinor = creditLimitMinor
        profile.statementClosingDay = draft.statementClosingDay
        profile.paymentDueDay = draft.paymentDueDay
        profile.notes = draft.notes.nilIfBlank
        profile.paymentSourceWallet = storedWallets.first(where: { $0.id == draft.paymentSourceWalletID })
        profile.updatedAt = now

        if wallet.creditCardProfile == nil {
            wallet.creditCardProfile = profile
            modelContext.insert(profile)
        }
    }

    private func payEarly(with dueItem: PlanningCreditCardDueSnapshot) {
        do {
            let amountOverride = paymentAmountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
            let effectiveDueItem = PlanningCreditCardDueSnapshot(
                id: dueItem.id,
                walletID: dueItem.walletID,
                walletName: dueItem.walletName,
                network: dueItem.network,
                last4: dueItem.last4,
                amountMinor: amountOverride ?? dueItem.amountMinor,
                dueDate: dueItem.dueDate,
                paymentSourceWalletID: draft.paymentSourceWalletID,
                currencyCode: dueItem.currencyCode,
                status: dueItem.status,
                linkedTransactionID: dueItem.linkedTransactionID
            )
            let paymentDraft = try PlanningLogic.makePaymentDraft(
                for: effectiveDueItem,
                overrideAmountMinor: amountOverride
            )
            _ = try PlanningPersistenceSupport.saveDuePayment(
                draft: paymentDraft,
                sourceKind: .creditCard,
                sourceID: dueItem.walletID,
                selectedMonth: target.selectedMonth,
                scheduledDate: dueItem.dueDate,
                wallets: storedWallets,
                occurrences: Array(storedOccurrences),
                modelContext: modelContext
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func archiveWallet() {
        guard let wallet = target.wallet else { return }
        wallet.isArchived = true
        wallet.updatedAt = .now
        PlanningPersistenceSupport.deleteOccurrences(
            sourceKind: .creditCard,
            sourceID: wallet.id,
            occurrences: Array(storedOccurrences),
            modelContext: modelContext
        )

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu trạng thái lưu trữ của thẻ.", en: "Couldn't save the archive state for this card.", ja: "このカードのアーカイブ状態を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedWallets.filter { !$0.isArchived }.map(\.sortOrder).max() ?? -1) + 1
    }
}

private struct PlanningEditorToolbar: ToolbarContent {
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onSave()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
        }
    }
}

private struct PlanningIconPickerButton: View {
    let title: String
    let symbolName: String
    let colorHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PlanningEditorIconPreview(
                    symbolName: symbolName,
                    color: Color(hex: colorHex)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(mistiaCatalog("Chạm để đổi icon"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PlanningIconPickerSheet: View {
    let title: String
    let onSave: (String, String) -> Void

    let selectedSymbolName: String
    let selectedColorHex: String

    init(
        title: String,
        selectedSymbolName: String,
        selectedColorHex: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.selectedSymbolName = selectedSymbolName
        self.selectedColorHex = selectedColorHex
    }

    var body: some View {
        MistiaIconPickerSheet(
            title: title,
            selectedSymbolName: selectedSymbolName,
            selectedColorHex: selectedColorHex,
            onSave: onSave
        )
    }
}

private struct PlanningEditorIconPreview: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(color.opacity(0.16))

            Image(systemName: symbolName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

private struct PlanningBudgetDraft {
    var categoryID: UUID?
    var limitText: String
    var rolloverEnabled: Bool

    init(budget: BudgetPlan?) {
        categoryID = budget?.category?.id
        limitText = budget.map { String($0.limitMinor) } ?? ""
        rolloverEnabled = budget?.rolloverEnabled ?? false
    }
}

private struct PlanningGoalDraft {
    var name: String
    var targetText: String
    var currentText: String
    var targetDate: Date
    var iconSymbolName: String
    var iconColorHex: String
    var linkedWalletID: UUID?

    init(goal: SavingsGoal?) {
        name = goal?.name ?? ""
        targetText = goal.map { String($0.targetMinor) } ?? ""
        currentText = goal.map { String($0.currentSavedMinor) } ?? ""
        targetDate = goal?.targetDate ?? .now
        iconSymbolName = goal?.iconSymbolName ?? "target"
        iconColorHex = "#5B7BFF"
        linkedWalletID = goal?.linkedWallet?.id
    }
}

private struct PlanningBillDraft {
    var name: String
    var amountText: String
    var dueDay: Int
    var frequencyMonths: Int
    var paymentWalletID: UUID?
    var iconSymbolName: String
    var iconColorHex: String

    init(plan: RecurringBillPlan?) {
        name = plan?.name ?? ""
        amountText = plan?.amountMinor.map(String.init) ?? ""
        dueDay = plan?.dueDay ?? 10
        frequencyMonths = max(plan?.frequencyMonths ?? 1, 1)
        paymentWalletID = plan?.paymentWallet?.id
        iconSymbolName = plan?.iconSymbolName ?? "bolt.fill"
        iconColorHex = "#FF9F1C"
    }
}

private struct PlanningInstallmentDraft {
    var name: String
    var amountText: String
    var dueDay: Int
    var frequencyMonths: Int
    var totalCyclesText: String
    var paymentWalletID: UUID?
    var iconSymbolName: String
    var iconColorHex: String

    init(plan: InstallmentPlan?) {
        name = plan?.name ?? ""
        amountText = plan.map { String($0.amountPerCycleMinor) } ?? ""
        dueDay = plan?.dueDay ?? 15
        frequencyMonths = max(plan?.frequencyMonths ?? 1, 1)
        totalCyclesText = plan?.totalCycles.map(String.init) ?? ""
        paymentWalletID = plan?.paymentWallet?.id
        iconSymbolName = plan?.iconSymbolName ?? "creditcard.and.123"
        iconColorHex = "#8A8A8E"
    }
}

private struct PlanningCreditCardDraft {
    var name: String
    var iconSymbolName: String
    var iconColorHex: String
    var issuerName: String
    var network: CreditCardNetwork
    var last4: String
    var currentDebtText: String
    var creditLimitText: String
    var paymentDueDay: Int
    var statementClosingDay: Int
    var paymentSourceWalletID: UUID?
    var notes: String

    init(wallet: LedgerWallet?) {
        let profile = wallet?.creditCardProfile
        name = wallet?.name ?? ""
        iconSymbolName = wallet?.iconSymbolName ?? LedgerWalletKind.creditCard.defaultIconSymbolName
        if let wallet {
            iconColorHex = wallet.kind.migratedLegacyDefaultColorHex(
                for: wallet.iconColorHex,
                symbolName: wallet.iconSymbolName
            ) ?? MistiaIconColorPalette.normalizedHex(wallet.iconColorHex)
        } else {
            iconColorHex = LedgerWalletKind.creditCard.defaultColorHex
        }
        issuerName = profile?.issuerName ?? ""
        network = profile?.network ?? .visa
        last4 = profile?.last4 ?? ""
        currentDebtText = wallet.map { String($0.openingBalanceMinor) } ?? ""
        creditLimitText = profile.map { String($0.creditLimitMinor) } ?? ""
        paymentDueDay = profile?.paymentDueDay ?? 10
        statementClosingDay = profile?.statementClosingDay ?? 25
        paymentSourceWalletID = profile?.paymentSourceWallet?.id
        notes = profile?.notes ?? ""
    }
}

private extension View {
    func planningAlert(message: Binding<String?>) -> some View {
        alert(
            mistiaLocalized(vi: "Chưa thể thực hiện", en: "Can't complete yet", ja: "まだ実行できません"),
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button(mistiaLocalized(vi: "OK", en: "OK", ja: "OK"), role: .cancel) { }
        } message: {
            Text(mistiaCatalog(message.wrappedValue ?? ""))
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
