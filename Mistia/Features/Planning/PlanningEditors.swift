import SwiftData
import SwiftUI

struct PlanningBudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<BudgetPlan> { $0.deletedAt == nil })
    private var storedBudgets: [BudgetPlan]
    @Query(filter: #Predicate<LedgerTransaction> {
        $0.entryStatusRawValue == "posted" && !$0.isArchived && $0.deletedAt == nil
    })
    private var postedTransactions: [LedgerTransaction]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: PlanningBudgetEditorTarget

    @State private var draft: PlanningBudgetDraft
    @State private var dismissBaselineDraft: PlanningBudgetDraft
    @State private var alertMessage: String?
    @State private var showsFamilySpendingConfirmation = false
    @State private var isRefreshingFamilySpending = false
    @State private var showsCategoryPicker = false

    init(target: PlanningBudgetEditorTarget) {
        self.target = target
        let initialDraft = PlanningBudgetDraft(budget: target.budget)
        _draft = State(initialValue: initialDraft)
        _dismissBaselineDraft = State(initialValue: initialDraft)
    }

    private var categorySections: [TransactionCategoryGroupSection] {
        let preferredCategoryID = target.budget?.category?.id
        let preferredParentID = target.budget?.category?.parentCategory?.id
        let relevantCategories = visibleStoredCategories.filter { category in
            category.kind == .expense
                && category.deletedAt == nil
                && (!category.isArchived || category.id == preferredCategoryID || category.id == preferredParentID)
        }

        let sections = MistiaCategoryHierarchy.groupedSections(
            from: relevantCategories,
            kind: .expense,
            includeArchived: true,
            includeEmptyParents: true
        )

        guard let preferredParentCategoryID = target.preferredParentCategoryID else {
            return sections
        }

        return sections.sorted { lhs, rhs in
            if lhs.parent.id == preferredParentCategoryID { return true }
            if rhs.parent.id == preferredParentCategoryID { return false }
            return MistiaCategoryHierarchy.categorySort(lhs: lhs.parent, rhs: rhs.parent)
        }
    }

    private var availableCategories: [TransactionCategory] {
        categorySections.flatMap { section in
            [section.parent] + section.children
        }
    }

    private var favoriteBudgetCategories: [TransactionCategory] {
        let allowedCategoryIDs = Set(availableCategories.map(\.id))
        return MistiaCategoryPickerSupport.favoriteCategories(
            from: visibleStoredCategories,
            kind: .expense
        )
        .filter { allowedCategoryIDs.contains($0.id) }
    }

    private var recentBudgetCategories: [TransactionCategory] {
        let allowedCategoryIDs = Set(availableCategories.map(\.id))
        return MistiaCategoryPickerSupport.recentCategories(
            from: postedTransactions,
            categories: visibleStoredCategories,
            kind: .expense
        )
        .filter { allowedCategoryIDs.contains($0.id) }
    }

    private var selectedCategory: TransactionCategory? {
        availableCategories.first(where: { $0.id == draft.categoryID })
    }

    private var activeCurrencyCode: String {
        target.budget?.currencyCode ?? currencyCode
    }

    private var targetMonthAnchor: Date {
        PlanningLogic.startOfMonth(for: target.selectedMonth)
    }

    private var currentMonthAnchor: Date {
        PlanningLogic.startOfMonth(for: .now)
    }

    private var isPastBudgetRecord: Bool {
        target.budget != nil && targetMonthAnchor < currentMonthAnchor
    }

    private var isCurrentBudgetRecord: Bool {
        target.budget != nil && targetMonthAnchor == currentMonthAnchor
    }

    private var isEditingCarriedForwardBudgetRecord: Bool {
        guard let budget = target.budget else { return false }
        return PlanningLogic.startOfMonth(for: budget.monthAnchor) < targetMonthAnchor
    }

    private var shouldShowFamilySpendingToggle: Bool {
        familyContextStore.family != nil && familyContextStore.members.count >= 2
    }

    private var isFamilySpendingToggleDisabled: Bool {
        isPastBudgetRecord
            || draft.includesFamilySpending
            || selectedCategory == nil
            || !sessionStore.canPerformRemoteActions
            || isRefreshingFamilySpending
    }

    private var familySpendingBinding: Binding<Bool> {
        Binding(
            get: { draft.includesFamilySpending },
            set: { newValue in
                guard newValue else { return }
                guard !draft.includesFamilySpending else { return }
                showsFamilySpendingConfirmation = true
            }
        )
    }

    private var targetOwnerUserID: UUID? {
        if let budget = target.budget,
           let ownerUserID = budgetOwnerMap[budget.id] {
            return ownerUserID
        }

        return familyContextStore.selectedSubjectUserID
            ?? sessionStore.activeLocalProfileUserID
    }

    private var categoryOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
    }

    private var budgetOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .budgetPlan)
    }

    private var visibleStoredCategories: [TransactionCategory] {
        PlanningBudgetEditorScope.visibleCategories(
            storedCategories,
            categoryOwnerMap: categoryOwnerMap,
            targetOwnerUserID: targetOwnerUserID,
            signedInUserID: sessionStore.activeLocalProfileUserID
        )
    }

    private var visibleStoredBudgets: [BudgetPlan] {
        PlanningBudgetEditorScope.visibleBudgets(
            storedBudgets,
            budgetOwnerMap: budgetOwnerMap,
            targetOwnerUserID: targetOwnerUserID,
            signedInUserID: sessionStore.activeLocalProfileUserID
        )
    }

    private var activeBudgetSnapshots: [BudgetPlanSnapshot] {
        visibleStoredBudgets
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .map { $0.planningSnapshot() }
    }

    private var familyBudgetSpendingCategoryScopes: [PlanningFamilyBudgetSpendingCategoryScope] {
        storedCategories
            .filter { $0.deletedAt == nil && !$0.isArchived }
            .map(\.planningFamilyBudgetSpendingScope)
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: target.budget == nil ? .creating : .editing,
            hasUnsavedChanges: !isPastBudgetRecord && draft != dismissBaselineDraft
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.planning.planning.budget) {
                    Button {
                        showsCategoryPicker = true
                    } label: {
                        HStack {
                            Text(L10n.planning.planning.category)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedCategoryLabel)
                                .foregroundStyle(selectedCategory == nil ? .tertiary : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                    .disabled(isPastBudgetRecord)

                    MistiaCurrencyInputField(L10n.planning.planning.budgetAmount, text: $draft.limitText)
                        .disabled(isPastBudgetRecord)

                    LabeledContent(L10n.planning.planning.cycle) {
                        Text(L10n.planning.planning.monthly)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(L10n.planning.planning.rollover, isOn: $draft.rolloverEnabled)
                        .tint(MistiaAccent.purple.color)
                        .toggleStyle(.switch)
                        .disabled(isPastBudgetRecord)

                    if shouldShowFamilySpendingToggle {
                        Toggle(L10n.planning.planning.includeFamilySpending, isOn: familySpendingBinding)
                            .tint(MistiaAccent.purple.color)
                            .toggleStyle(.switch)
                            .disabled(isFamilySpendingToggleDisabled)
                    }
                }

                if target.budget != nil && !isEditingCarriedForwardBudgetRecord {
                    if isPastBudgetRecord {
                        MistiaDestructiveActionSection(
                            buttonTitle: L10n.planning.planning.archiveBudget,
                            descriptionText: L10n.planning.planning.archivedBudgetsWillNoLongerAppearIn,
                            popupMessage: L10n.planning.planning.thisBudgetWillBeArchivedArchivedBudgets,
                            confirmationButtonTitle: L10n.common.archive
                        ) {
                            archiveBudget()
                        }
                    } else {
                        MistiaDestructiveActionSection(
                            buttonTitle: L10n.planning.planning.deleteBudget,
                            popupMessage: deleteBudgetMessage,
                            confirmationButtonTitle: L10n.common.delete
                        ) {
                            deleteBudget()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .dismissKeyboardOnTap()
            .navigationTitle(target.budget == nil ? L10n.planning.planning.ngNSChMI : L10n.planning.planning.sANgNSCh)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save,
                    dismissGuardConfiguration: dismissGuardConfiguration,
                    canSave: !isPastBudgetRecord
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .planningAlert(message: $alertMessage)
        .onAppear {
            syncFamilySpendingDraftWithSelectedCategory()
            dismissBaselineDraft = draft
        }
        .sheet(isPresented: $showsCategoryPicker) {
            MistiaCategoryPickerSheet(
                title: L10n.planning.planning.chooseCategory,
                selectedCategoryID: draft.categoryID,
                sections: categorySections,
                recentCategories: recentBudgetCategories,
                favoriteCategories: favoriteBudgetCategories,
                allowsParentSelectionInAll: true,
                allModeSubtitle: { category in
                    category.isParentCategory
                        ? L10n.planning.planning.parentBudget
                        : L10n.planning.planning.childBudget
                },
                quickModeSubtitle: { category in
                    category.parentCategory?.localizedDisplayName
                }
            ) { category in
                draft.categoryID = category.id
                syncFamilySpendingDraft(with: category)
            }
        }
        .alert(
            L10n.planning.planning.enableFamilyBudgetDataTitle,
            isPresented: $showsFamilySpendingConfirmation
        ) {
            Button(L10n.planning.planning.enableFamilyBudgetDataConfirm, role: .destructive) {
                Task { await confirmFamilySpendingEnable() }
            }

            Button(L10n.planning.planning.enableFamilyBudgetDataCancel, role: .cancel) { }
        } message: {
            Text(L10n.planning.planning.enableFamilyBudgetDataMessage)
        }
    }

    private func save() {
        guard !isPastBudgetRecord else {
            alertMessage = L10n.planning.planning.pastBudgetReadOnlyReference
            return
        }

        guard let category = selectedCategory
        else {
            alertMessage = L10n.planning.planning.chooseACategoryBeforeSaving
            return
        }

        let limitMinor = draft.limitText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        guard limitMinor > 0 else {
            alertMessage = L10n.planning.planning.enterABudgetAmountGreaterThan
            return
        }

        let monthAnchor = targetMonthAnchor
        let branchScopeCategory = branchScopeCategory(for: category)
        let enablesFamilySpending = draft.includesFamilySpending
            || familySpendingEnabled(for: category)
        let hasDuplicate = visibleStoredBudgets.contains(where: { budget in
            guard !budget.isArchived else { return false }
            guard budget.id != target.budget?.id else { return false }
            guard PlanningLogic.startOfMonth(for: budget.monthAnchor) == monthAnchor else { return false }
            return budget.category?.id == category.id
        })

        guard !hasDuplicate else {
            alertMessage = L10n.planning.planning.thisCategoryAlreadyHasABudgetIn
            return
        }

        let allocationValidation = PlanningLogic.validateBudgetAllocation(
            categoryID: category.id,
            branchCategoryID: category.branchCategoryID,
            categoryIsParent: category.isParentCategory,
            categoryIsChild: category.isChildCategory,
            limitMinor: limitMinor,
            monthAnchor: monthAnchor,
            plans: activeBudgetSnapshots,
            editingBudgetID: target.budget?.id
        )
        guard allocationValidation == .valid else {
            alertMessage = allocationValidationMessage(allocationValidation)
            return
        }

        let now = Date()
        let budgetForSync: BudgetPlan
        if let budget = target.budget, !isEditingCarriedForwardBudgetRecord {
            budget.category = category
            budget.limitMinor = limitMinor
            budget.rolloverEnabled = draft.rolloverEnabled
            budget.monthAnchor = monthAnchor
            budget.includesFamilySpending = enablesFamilySpending
            budget.refreshCategorySnapshot()
            budget.updatedAt = now
            budgetForSync = budget
        } else {
            let budget = BudgetPlan(
                category: category,
                includesFamilySpending: enablesFamilySpending,
                monthAnchor: monthAnchor,
                limitMinor: limitMinor,
                rolloverEnabled: draft.rolloverEnabled,
                currencyCode: activeCurrencyCode,
                createdAt: now,
                updatedAt: now
            )
            budget.refreshCategorySnapshot()
            modelContext.insert(budget)
            budgetForSync = budget
        }

        let familyScopeUpdates = applyFamilyScopeIfNeeded(
            branchCategoryID: category.branchCategoryID,
            branchScopeCategory: branchScopeCategory,
            monthAnchor: monthAnchor,
            enablesFamilySpending: enablesFamilySpending,
            now: now,
            savedBudget: budgetForSync
        )

        let autoCreatedParentBudget = autoCreateParentBudgetIfNeeded(
            for: category,
            savedBudget: budgetForSync,
            monthAnchor: monthAnchor,
            includesFamilySpending: enablesFamilySpending,
            now: now
        )

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .budgetPlan,
                recordID: budgetForSync.id,
                modifiedAt: budgetForSync.updatedAt
            )
            if let autoCreatedParentBudget {
                sessionStore.recordUpsert(
                    entity: .budgetPlan,
                    recordID: autoCreatedParentBudget.id,
                    modifiedAt: autoCreatedParentBudget.updatedAt
                )
            }
            for budget in familyScopeUpdates {
                sessionStore.recordUpsert(
                    entity: .budgetPlan,
                    recordID: budget.id,
                    modifiedAt: budget.updatedAt
                )
            }
            if enablesFamilySpending, let branchScopeCategory {
                sessionStore.recordUpsert(
                    entity: .category,
                    recordID: branchScopeCategory.id,
                    modifiedAt: branchScopeCategory.updatedAt
                )
            }
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTSaveThisBudgetRightNow + " \(error.localizedDescription)"
        }
    }

    private func autoCreateParentBudgetIfNeeded(
        for category: TransactionCategory,
        savedBudget: BudgetPlan,
        monthAnchor: Date,
        includesFamilySpending: Bool,
        now: Date
    ) -> BudgetPlan? {
        guard category.isChildCategory else { return nil }

        let branchCategoryID = category.branchCategoryID
        guard activeParentBudget(for: branchCategoryID, monthAnchor: monthAnchor, excluding: savedBudget.id) == nil else {
            return nil
        }

        let childBudgets = activeChildBudgets(
            for: branchCategoryID,
            monthAnchor: monthAnchor,
            including: savedBudget
        )
        guard childBudgets.count >= 2 else { return nil }
        guard let parentCategory = category.parentCategory ?? visibleStoredCategories.first(where: { $0.id == branchCategoryID && $0.isParentCategory }) else {
            return nil
        }

        let totalLimitMinor = childBudgets.reduce(into: Int64.zero) { partial, budget in
            partial += budget.limitMinor
        }
        let parentBudget = BudgetPlan(
            category: parentCategory,
            includesFamilySpending: includesFamilySpending,
            monthAnchor: monthAnchor,
            limitMinor: totalLimitMinor,
            rolloverEnabled: false,
            currencyCode: activeCurrencyCode,
            createdAt: now,
            updatedAt: now
        )
        parentBudget.refreshCategorySnapshot()
        modelContext.insert(parentBudget)
        return parentBudget
    }

    private func activeParentBudget(
        for branchCategoryID: UUID,
        monthAnchor: Date,
        excluding budgetID: UUID
    ) -> BudgetPlan? {
        visibleStoredBudgets.first { budget in
            guard budget.id != budgetID else { return false }
            guard budget.deletedAt == nil && !budget.isArchived else { return false }
            guard PlanningLogic.startOfMonth(for: budget.monthAnchor) == monthAnchor else { return false }
            return budget.category?.id == branchCategoryID && budget.category?.isParentCategory == true
        }
    }

    private func activeChildBudgets(
        for branchCategoryID: UUID,
        monthAnchor: Date,
        including savedBudget: BudgetPlan
    ) -> [BudgetPlan] {
        var budgets = visibleStoredBudgets.filter { budget in
            guard budget.id != savedBudget.id else { return false }
            guard budget.deletedAt == nil && !budget.isArchived else { return false }
            guard PlanningLogic.startOfMonth(for: budget.monthAnchor) == monthAnchor else { return false }
            guard let category = budget.category else { return false }
            return category.isChildCategory && category.branchCategoryID == branchCategoryID
        }

        if savedBudget.deletedAt == nil,
           !savedBudget.isArchived,
           PlanningLogic.startOfMonth(for: savedBudget.monthAnchor) == monthAnchor,
           let savedCategory = savedBudget.category,
           savedCategory.isChildCategory,
           savedCategory.branchCategoryID == branchCategoryID {
            budgets.append(savedBudget)
        }

        return budgets
    }

    private func branchScopeCategory(for category: TransactionCategory) -> TransactionCategory? {
        if category.isParentCategory {
            return category
        }
        return category.parentCategory
            ?? visibleStoredCategories.first { $0.id == category.branchCategoryID && $0.isParentCategory }
            ?? category
    }

    private func syncFamilySpendingDraftWithSelectedCategory() {
        guard let selectedCategory else { return }
        syncFamilySpendingDraft(with: selectedCategory)
    }

    private func syncFamilySpendingDraft(with category: TransactionCategory) {
        guard !draft.includesFamilySpending else { return }
        draft.includesFamilySpending = familySpendingEnabled(for: category)
    }

    private func familySpendingEnabled(for category: TransactionCategory) -> Bool {
        PlanningLogic.familySpendingEnabled(
            categoryName: category.localizedDisplayName,
            branchCategoryName: branchScopeCategory(for: category)?.localizedDisplayName ?? category.localizedDisplayName,
            categoryScopes: familyBudgetSpendingCategoryScopes
        )
    }

    private func applyFamilyScopeIfNeeded(
        branchCategoryID: UUID,
        branchScopeCategory: TransactionCategory?,
        monthAnchor: Date,
        enablesFamilySpending: Bool,
        now: Date,
        savedBudget: BudgetPlan
    ) -> [BudgetPlan] {
        guard enablesFamilySpending else { return [] }

        branchScopeCategory?.familyBudgetSpendingEnabled = true
        branchScopeCategory?.updatedAt = now

        var updatedBudgets: [BudgetPlan] = []
        for budget in visibleStoredBudgets {
            guard budget.id != savedBudget.id,
                  budget.deletedAt == nil,
                  !budget.isArchived,
                  PlanningLogic.startOfMonth(for: budget.monthAnchor) == monthAnchor,
                  budget.category?.branchCategoryID == branchCategoryID,
                  !budget.includesFamilySpending
            else {
                continue
            }
            budget.includesFamilySpending = true
            budget.refreshCategorySnapshot()
            budget.updatedAt = now
            updatedBudgets.append(budget)
        }

        return updatedBudgets
    }

    @MainActor
    private func confirmFamilySpendingEnable() async {
        guard selectedCategory != nil else {
            alertMessage = L10n.planning.planning.chooseACategoryBeforeSaving
            return
        }
        guard sessionStore.canPerformRemoteActions else {
            alertMessage = L10n.planning.planning.familyBudgetDataNeedsInternet
            return
        }

        isRefreshingFamilySpending = true
        let refreshed = await familyContextStore.refresh(sessionStore: sessionStore)
        isRefreshingFamilySpending = false

        guard refreshed,
              familyContextStore.family != nil,
              familyContextStore.members.count >= 2
        else {
            alertMessage = L10n.planning.planning.familyBudgetDataRefreshFailed
            return
        }

        draft.includesFamilySpending = true
    }

    private func allocationValidationMessage(
        _ result: PlanningBudgetAllocationValidationResult
    ) -> String {
        switch result {
        case .valid:
            return ""
        case .childBudgetsExceedParent(let childTotalMinor, let parentLimitMinor):
            return L10n.planning.planning.childBudgetsTotalValueAboveTheParent(String(describing: childTotalMinor.formattedCurrency(code: activeCurrencyCode)), String(describing: parentLimitMinor.formattedCurrency(code: activeCurrencyCode)))
        case .parentLimitBelowChildren(let childTotalMinor, let parentLimitMinor):
            return L10n.planning.planning.parentBudgetValueMustBeAtLeast(String(describing: parentLimitMinor.formattedCurrency(code: activeCurrencyCode)), String(describing: childTotalMinor.formattedCurrency(code: activeCurrencyCode)))
        }
    }

    private func deleteBudget() {
        guard let budget = target.budget else { return }

        let now = Date()
        let branchCategory = budget.category.flatMap(branchScopeCategory(for:))
        let branchCategoryID = budget.category?.branchCategoryID
        budget.markDeleted(at: now)
        let shouldResetFamilyScope = isCurrentBudgetRecord
            && shouldResetFamilyScopeAfterDeletingBudget(
                deletedBudget: budget,
                branchCategoryID: branchCategoryID,
                monthAnchor: targetMonthAnchor
            )
        if shouldResetFamilyScope {
            branchCategory?.familyBudgetSpendingEnabled = false
            branchCategory?.updatedAt = now
        }

        do {
            try modelContext.save()
            sessionStore.recordDelete(
                entity: .budgetPlan,
                recordID: budget.id,
                modifiedAt: now
            )
            if shouldResetFamilyScope, let branchCategory {
                sessionStore.recordUpsert(
                    entity: .category,
                    recordID: branchCategory.id,
                    modifiedAt: now
                )
            }
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTDeleteThisBudgetRightNow + " \(error.localizedDescription)"
        }
    }

    private func archiveBudget() {
        guard let budget = target.budget else { return }

        let now = Date()
        budget.isArchived = true
        budget.updatedAt = now

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .budgetPlan,
                recordID: budget.id,
                modifiedAt: now
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTArchiveThisBudgetRightNow + " \(error.localizedDescription)"
        }
    }

    private func shouldResetFamilyScopeAfterDeletingBudget(
        deletedBudget: BudgetPlan,
        branchCategoryID: UUID?,
        monthAnchor: Date
    ) -> Bool {
        guard let branchCategoryID else { return false }
        return visibleStoredBudgets.contains { budget in
            guard budget.id != deletedBudget.id,
                  budget.deletedAt == nil,
                  !budget.isArchived,
                  PlanningLogic.startOfMonth(for: budget.monthAnchor) == monthAnchor,
                  budget.category?.branchCategoryID == branchCategoryID
            else {
                return false
            }
            return true
        } == false
    }

    private var selectedCategoryLabel: String {
        if let snapshotLabel = target.budget?.localizedCategoryPathSnapshot() {
            return snapshotLabel
        }

        guard let selectedCategory else {
            return L10n.planning.planning.chooseCategory
        }

        if selectedCategory.isParentCategory {
            return selectedCategory.localizedDisplayName
        }

        let parentName = selectedCategory.parentCategory?.localizedDisplayName ?? selectedCategory.branchDisplayName
        return "\(parentName) / \(selectedCategory.localizedDisplayName)"
    }

    private var deleteBudgetMessage: String {
        isCurrentBudgetRecord
            ? L10n.planning.planning.deleteCurrentBudgetMessage
            : L10n.planning.planning.deleteBudgetMessage
    }
}

private struct PlanningBillCategoryPickerSheet: View {
    let selectedCategoryID: UUID?
    let categories: [TransactionCategory]
    let onSelect: (TransactionCategory) -> Void

    private var pickerCategories: [TransactionCategory] {
        var quickPickCategories = MistiaCategoryPickerSupport.billQuickPickCategories(from: categories)

        if let selectedCategoryID,
           let selectedCategory = categories.first(where: { $0.id == selectedCategoryID }),
           quickPickCategories.contains(where: { $0.id == selectedCategory.id }) == false {
            quickPickCategories.insert(selectedCategory, at: 0)
        }

        return quickPickCategories
    }

    private var pickerOptions: [MistiaFinancePickerOption] {
        pickerCategories.map { category in
            MistiaFinancePickerOption(
                token: category.iconSymbolName,
                title: category.localizedDisplayName,
                group: .planning,
                defaultColorHex: category.iconColorHex
            )
        }
    }

    private var selectedToken: String {
        pickerCategories.first(where: { $0.id == selectedCategoryID })?.iconSymbolName
            ?? pickerOptions.first?.token
            ?? "mistia.plan.bill"
    }

    var body: some View {
        MistiaFinanceIconPickerSheet(
            title: L10n.planning.planning.paymentCategory,
            options: pickerOptions,
            selectedToken: selectedToken
        ) { token, _ in
            guard let category = pickerCategories.first(where: { $0.iconSymbolName == token }) else {
                return
            }
            onSelect(category)
        }
    }
}

struct PlanningGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil })
    private var storedGoals: [SavingsGoal]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: PlanningGoalEditorTarget

    @State private var draft: PlanningGoalDraft
    private let initialDraft: PlanningGoalDraft
    @State private var alertMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsIconPicker = false

    init(target: PlanningGoalEditorTarget) {
        self.target = target
        let initialDraft = PlanningGoalDraft(goal: target.goal)
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    private var availableWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([target.goal?.linkedWallet?.id, draft.linkedWalletID].compactMap { $0 })
        return paymentWalletAccess.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            ownerUserID: goalOwnerUserID,
            excludesCreditCards: false
        )
    }

    private var goalOwnerUserID: UUID? {
        if let goal = target.goal,
           let ownerUserID = goalOwnerMap[goal.id] {
            return ownerUserID
        }
        return familyContextStore.selectedSubjectUserID
            ?? paymentWalletAccess.currentSelfUserID
    }

    private var goalOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .savingsGoal)
    }

    private var paymentWalletAccess: PlanningPaymentWalletAccess {
        PlanningPaymentWalletAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeCurrencyCode: String {
        target.goal?.currencyCode ?? currencyCode
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: target.goal == nil ? .creating : .editing,
            hasUnsavedChanges: draft != initialDraft
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.planning.planning.identity) {
                    PlanningIconPickerButton(
                        title: L10n.planning.planning.iconMCTiU,
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(L10n.planning.planning.goal) {
                    TextField(L10n.planning.planning.goalName, text: $draft.name)
                    MistiaCurrencyInputField(L10n.planning.planning.targetAmount, text: $draft.targetText)
                    MistiaCurrencyInputField(L10n.planning.planning.currentAmount, text: $draft.currentText)
                    MistiaDatePickerRow(
                        title: L10n.planning.planning.targetDate,
                        selection: $draft.targetDate,
                        mode: .date
                    )

                    Picker(L10n.planning.planning.linkedWallet, selection: $draft.linkedWalletID) {
                        Text(L10n.planning.planning.notLinked).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(paymentWalletAccess.title(for: wallet)).tag(Optional(wallet.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if target.goal != nil {
                    Section {
                        Button(L10n.planning.planning.deleteGoal, role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .dismissKeyboardOnTap()
            .navigationTitle(target.goal == nil ? L10n.planning.planning.mCTiUMI : L10n.planning.planning.sAMCTiU)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save,
                    dismissGuardConfiguration: dismissGuardConfiguration
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: L10n.planning.planning.iconMCTiU,
                options: MistiaFinanceIconRegistry.goalOptions,
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            L10n.planning.planning.deleteThisGoal,
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.common.delete, role: .destructive) {
                deleteGoal()
            }

            Button(L10n.common.cancel, role: .cancel) { }
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = L10n.planning.planning.enterAGoalNameBeforeSaving
            return
        }

        let targetMinor = draft.targetText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        guard targetMinor > 0 else {
            alertMessage = L10n.planning.planning.enterATargetAmountGreaterThan
            return
        }

        let currentMinor = draft.currentText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        let linkedWallet = storedWallets.first(where: { $0.id == draft.linkedWalletID })
        let now = Date()
        let goalForSync: SavingsGoal

        if let goal = target.goal {
            goal.name = trimmedName
            goal.iconSymbolName = draft.iconSymbolName
            goal.targetMinor = targetMinor
            goal.currentSavedMinor = currentMinor
            goal.targetDate = draft.targetDate
            goal.linkedWallet = linkedWallet
            goal.updatedAt = now
            goalForSync = goal
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
            goalForSync = goal
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .savingsGoal,
                recordID: goalForSync.id,
                modifiedAt: goalForSync.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTSaveThisGoalRightNow + " \(error.localizedDescription)"
        }
    }

    private func deleteGoal() {
        guard let goal = target.goal else { return }
        let now = Date()
        goal.markDeleted(at: now)

        do {
            try modelContext.save()
            sessionStore.recordDelete(
                entity: .savingsGoal,
                recordID: goal.id,
                modifiedAt: now
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTDeleteThisGoalRightNow + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedGoals.filter { !$0.isArchived }.map(\.sortOrder).max() ?? -1) + 1
    }
}

private struct PlanningPaymentWalletAccess {
    private let access: MistiaWalletPickerAccess

    init(
        sessionStore: SessionStore,
        familyContextStore: FamilyContextStore,
        ownershipScopes: [OwnedRecordScope]
    ) {
        self.access = MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    var currentSelfUserID: UUID? {
        access.currentSelfUserID
    }

    func availableWallets(
        from wallets: [LedgerWallet],
        preferredWalletIDs: Set<UUID>,
        ownerUserID: UUID?,
        excludesCreditCards: Bool,
        excludedWalletID: UUID? = nil
    ) -> [LedgerWallet] {
        access.availableWallets(
            from: wallets,
            preferredWalletIDs: preferredWalletIDs,
            targetOwnerUserID: ownerUserID,
            excludesCreditCards: excludesCreditCards,
            excludedWalletID: excludedWalletID
        )
    }

    func title(for wallet: LedgerWallet) -> String {
        access.title(for: wallet)
    }

    func walletOwnerUserID(for wallet: LedgerWallet) -> UUID? {
        access.walletOwnerUserID(for: wallet)
    }

    func walletOwnerUserID(for walletID: UUID?) -> UUID? {
        access.walletOwnerUserID(for: walletID)
    }
}

struct PlanningBillEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil })
    private var storedCategories: [TransactionCategory]
    @Query
    private var storedWallets: [LedgerWallet]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: PlanningBillEditorTarget

    @State private var draft: PlanningBillDraft
    private let initialDraft: PlanningBillDraft
    @State private var alertMessage: String?
    @State private var showsCategoryPicker = false
    @State private var showsPauseConfirmation = false
    @State private var showsResumeConfirmation = false

    init(target: PlanningBillEditorTarget) {
        self.target = target
        var initialDraft = PlanningBillDraft(plan: target.plan)
        if target.plan == nil {
            let today = MistiaCalendar.current.startOfDay(for: Date())
            initialDraft.paymentStartDate = today
            initialDraft.dueDate = today
            initialDraft.autoPayDate = today
        }
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    private var availableWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([
            target.plan?.paymentWallet?.id,
            draft.paymentWalletID
        ].compactMap { $0 })
        return paymentWalletAccess.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            ownerUserID: billOwnerUserID,
            excludesCreditCards: false
        )
    }

    private var billOwnerUserID: UUID? {
        if let plan = target.plan,
           let ownerUserID = billOwnerMap[plan.id] {
            return ownerUserID
        }
        return familyContextStore.selectedSubjectUserID
            ?? paymentWalletAccess.currentSelfUserID
    }

    private var billOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .recurringBillPlan)
    }

    private var paymentWalletAccess: PlanningPaymentWalletAccess {
        PlanningPaymentWalletAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeCurrencyCode: String {
        target.plan?.currencyCode ?? target.dueItem?.currencyCode ?? currencyCode
    }

    private var resumeActionColor: Color {
        colorScheme == .dark ? MistiaAccent.cyan.color : MistiaAccent.teal.color
    }

    private var selectedCategory: TransactionCategory? {
        if let categoryID = draft.categoryID {
            return storedCategories.first(where: { $0.id == categoryID })
        }

        if let planCategoryID = target.plan?.category?.id {
            return storedCategories.first(where: { $0.id == planCategoryID })
        }

        return storedCategories.first { category in
            category.kind == .expense
                && category.isChildCategory
                && category.iconSymbolName == draft.iconSymbolName
        }
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: target.plan == nil ? .creating : .editing,
            hasUnsavedChanges: draft != initialDraft
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.planning.planning.bill) {
                    Button {
                        showsCategoryPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            PlanningEditorIconPreview(
                                symbolName: selectedCategory?.iconSymbolName ?? draft.iconSymbolName,
                                color: Color(hex: selectedCategory?.iconColorHex ?? draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.planning.planning.paymentCategory)
                                    .foregroundStyle(.primary)
                                Text(selectedCategoryLabel)
                                    .font(.footnote)
                                    .foregroundStyle(selectedCategory == nil ? .tertiary : .secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))

                    TextField(L10n.planning.planning.billName, text: $draft.name)
                    MistiaCurrencyInputField(L10n.planning.planning.amountOptional, text: $draft.amountText)

                    Picker(L10n.planning.planning.billType, selection: $draft.scheduleKind) {
                        ForEach(PlanningBillScheduleKind.allCases) { kind in
                            Text(kind.editorTitle).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    billWindowFields
                    autoPayFields

                    Picker(L10n.planning.planning.paymentWallet, selection: $draft.paymentWalletID) {
                        Text(L10n.planning.planning.chooseWallet).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(paymentWalletAccess.title(for: wallet)).tag(Optional(wallet.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let plan = target.plan,
                   plan.scheduleKind == .recurring,
                   draft.scheduleKind == .recurring {
                    if plan.isPaused {
                        Section {
                            Button {
                                showsResumeConfirmation = true
                            } label: {
                                Text(L10n.planning.planning.resumeBill)
                                    .font(.body)
                                    .foregroundStyle(resumeActionColor)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                "",
                                isPresented: $showsResumeConfirmation,
                                titleVisibility: .hidden
                            ) {
                                Button(L10n.planning.planning.resumeBill) {
                                    resumePlan()
                                }
                                Button(L10n.common.cancel, role: .cancel) { }
                            } message: {
                                Text(L10n.planning.planning.resumeBillMessage)
                            }
                        }
                    } else {
                        Section {
                            Button {
                                showsPauseConfirmation = true
                            } label: {
                                Text(L10n.planning.planning.pauseBill)
                                    .font(.body)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                "",
                                isPresented: $showsPauseConfirmation,
                                titleVisibility: .hidden
                            ) {
                                Button(L10n.planning.planning.pauseBillAction, role: .destructive) {
                                    pausePlan()
                                }
                                Button(L10n.common.cancel, role: .cancel) { }
                            } message: {
                                Text(L10n.planning.planning.pauseBillMessage)
                            }
                        }
                    }
                }

                if target.plan != nil {
                    MistiaDestructiveActionSection(
                        buttonTitle: L10n.planning.planning.archiveBill,
                        descriptionText: L10n.planning.planning.archivedBillsWillNoLongerAppearIn,
                        popupMessage: L10n.planning.planning.thisBillWillBeArchivedArchivedBills,
                        confirmationButtonTitle: L10n.common.archive
                    ) {
                        archivePlan()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .dismissKeyboardOnTap()
            .navigationTitle(target.plan == nil ? L10n.planning.planning.hANMI : L10n.planning.planning.sAHAN)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save,
                    dismissGuardConfiguration: dismissGuardConfiguration
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .sheet(isPresented: $showsCategoryPicker) {
            PlanningBillCategoryPickerSheet(
                selectedCategoryID: selectedCategory?.id,
                categories: storedCategories
            ) { category in
                draft.categoryID = category.id
                draft.iconSymbolName = category.iconSymbolName
                draft.iconColorHex = category.iconColorHex
            }
        }
            .planningAlert(message: $alertMessage)
            .onChange(of: draft.scheduleKind) { _, _ in
                normalizeAutoPayDraft()
            }
            .onChange(of: draft.paymentStartDay) { _, _ in
                normalizeAutoPayDraft()
            }
            .onChange(of: draft.dueDay) { _, _ in
                normalizeAutoPayDraft()
            }
            .onChange(of: draft.hasDeadline) { _, _ in
                normalizeAutoPayDraft()
            }
            .onChange(of: draft.paymentStartDate) { oldValue, _ in
                normalizeOneTimePaymentStartChange(from: oldValue)
            }
            .onChange(of: draft.dueDate) { _, _ in
                normalizeAutoPayDraft()
            }
    }

    @ViewBuilder
    private var billWindowFields: some View {
        switch draft.scheduleKind {
        case .recurring:
            Picker(L10n.planning.planning.paymentDay, selection: $draft.paymentStartDay) {
                ForEach(1...31, id: \.self) { day in
                    Text(L10n.planning.planning.dayValue(String(describing: day))).tag(day)
                }
            }
            .pickerStyle(.menu)

            if target.plan == nil {
                Picker(L10n.planning.planning.startCounting, selection: $draft.firstScheduledMonthChoice) {
                    ForEach(PlanningBillFirstScheduledMonthChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle(L10n.planning.planning.hasDeadline, isOn: $draft.hasDeadline)
                .tint(MistiaAccent.purple.color)
                .toggleStyle(.switch)

            if draft.hasDeadline {
                Picker(L10n.planning.planning.deadline, selection: $draft.dueDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text(L10n.planning.planning.dayValue(String(describing: day))).tag(day)
                    }
                }
                .pickerStyle(.menu)
            }

            Stepper(
                L10n.planning.planning.frequencyEveryValueMonthS(String(describing: draft.frequencyMonths)),
                value: $draft.frequencyMonths,
                in: 1...12
            )

        case .oneTime:
            MistiaDatePickerRow(
                title: L10n.planning.planning.paymentDate,
                selection: $draft.paymentStartDate,
                mode: .date
            )

            Toggle(L10n.planning.planning.hasDeadline, isOn: $draft.hasDeadline)
                .tint(MistiaAccent.purple.color)
                .toggleStyle(.switch)

            if draft.hasDeadline {
                MistiaDatePickerRow(
                    title: L10n.planning.planning.deadline,
                    selection: $draft.dueDate,
                    mode: .date
                )
            }
        }
    }

    @ViewBuilder
    private var autoPayFields: some View {
        Toggle(L10n.planning.planning.autoPay, isOn: $draft.autoPayEnabled)
            .tint(MistiaAccent.purple.color)
            .toggleStyle(.switch)

        if draft.autoPayEnabled {
            switch draft.scheduleKind {
            case .recurring:
                Picker(L10n.planning.planning.autoPayDay, selection: $draft.autoPayDay) {
                    ForEach(draft.recurringAutoPayDayOptions, id: \.self) { day in
                        Text(recurringAutoPayDayLabel(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
            case .oneTime:
                MistiaDatePickerRow(
                    title: L10n.planning.planning.autoPayDate,
                    selection: $draft.autoPayDate,
                    mode: .date,
                    selectableRange: .closed(draft.oneTimePaymentWindow)
                )
            }
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = L10n.planning.planning.enterABillNameBeforeSaving
            return
        }

        guard let selectedCategory else {
            alertMessage = L10n.planning.planning.chooseAnExpenseChildCategoryForThis
            return
        }

        guard let wallet = storedWallets.first(where: { $0.id == draft.paymentWalletID }) else {
            alertMessage = L10n.planning.planning.chooseAPaymentWalletForThisBill
            return
        }

        if draft.scheduleKind == .oneTime,
           draft.hasDeadline,
           calendar.startOfDay(for: draft.dueDate) < calendar.startOfDay(for: draft.paymentStartDate) {
            alertMessage = L10n.planning.planning.deadlineCannotBeBeforeThePaymentDate
            return
        }

        let amountMinor = draft.amountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        let normalized = normalizedBillSchedule()
        let now = Date()
        let planForSync: RecurringBillPlan

        if let plan = target.plan {
            let existingIsPaused = plan.isPaused
            let existingPausedAt = plan.pausedAt
            let existingResumeStartMonth = plan.resumeStartMonth
            plan.name = trimmedName
            plan.iconSymbolName = selectedCategory.iconSymbolName
            plan.category = selectedCategory
            plan.amountMinor = amountMinor
            plan.dueDay = normalized.dueDay
            plan.scheduleKind = draft.scheduleKind
            plan.paymentStartDay = normalized.paymentStartDay
            plan.paymentStartDate = normalized.paymentStartDate
            plan.firstScheduledMonth = normalized.firstScheduledMonth
            plan.hasExplicitDueDate = normalized.hasExplicitDueDate
            plan.dueDate = normalized.dueDate
            plan.autoPayEnabled = normalized.autoPayEnabled
            plan.autoPayDay = normalized.autoPayDay
            plan.autoPayDate = normalized.autoPayDate
            plan.frequencyMonths = normalized.frequencyMonths
            if draft.scheduleKind == .recurring {
                plan.isPaused = existingIsPaused
                plan.pausedAt = existingPausedAt
                plan.resumeStartMonth = existingResumeStartMonth
            } else {
                plan.isPaused = false
                plan.pausedAt = nil
                plan.resumeStartMonth = nil
            }
            plan.paymentWallet = wallet
            plan.updatedAt = now
            planForSync = plan
        } else {
            let plan = RecurringBillPlan(
                name: trimmedName,
                iconSymbolName: selectedCategory.iconSymbolName,
                category: selectedCategory,
                amountMinor: amountMinor,
                dueDay: normalized.dueDay,
                scheduleKind: draft.scheduleKind,
                paymentStartDay: normalized.paymentStartDay,
                paymentStartDate: normalized.paymentStartDate,
                firstScheduledMonth: normalized.firstScheduledMonth,
                hasExplicitDueDate: normalized.hasExplicitDueDate,
                dueDate: normalized.dueDate,
                autoPayEnabled: normalized.autoPayEnabled,
                autoPayDay: normalized.autoPayDay,
                autoPayDate: normalized.autoPayDate,
                frequencyMonths: normalized.frequencyMonths,
                paymentWallet: wallet,
                currencyCode: activeCurrencyCode,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(plan)
            planForSync = plan
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .recurringBillPlan,
                recordID: planForSync.id,
                modifiedAt: planForSync.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTSaveThisBillRightNow + " \(error.localizedDescription)"
        }
    }

    private func normalizedBillSchedule() -> (
        dueDay: Int,
        paymentStartDay: Int,
        paymentStartDate: Date?,
        firstScheduledMonth: Date?,
        hasExplicitDueDate: Bool,
        dueDate: Date?,
        autoPayEnabled: Bool,
        autoPayDay: Int?,
        autoPayDate: Date?,
        frequencyMonths: Int
    ) {
        switch draft.scheduleKind {
        case .recurring:
            let hasExplicitDueDate = draft.hasDeadline && draft.dueDay != draft.paymentStartDay
            let dueDay = hasExplicitDueDate ? draft.dueDay : draft.paymentStartDay
            let autoPayDay = draft.autoPayEnabled
                ? (draft.recurringAutoPayDayOptions.contains(draft.autoPayDay) ? draft.autoPayDay : draft.paymentStartDay)
                : nil
            return (
                dueDay,
                draft.paymentStartDay,
                nil,
                target.plan == nil ? firstScheduledMonth(for: draft.firstScheduledMonthChoice) : target.plan?.firstScheduledMonth,
                hasExplicitDueDate,
                nil,
                draft.autoPayEnabled,
                autoPayDay,
                nil,
                draft.frequencyMonths
            )

        case .oneTime:
            let paymentStartDate = calendar.startOfDay(for: draft.paymentStartDate)
            let rawDueDate = calendar.startOfDay(for: draft.dueDate)
            let hasExplicitDueDate = draft.hasDeadline && rawDueDate != paymentStartDate && rawDueDate >= paymentStartDate
            let dueDate = hasExplicitDueDate ? rawDueDate : nil
            let effectiveDueDate = dueDate ?? paymentStartDate
            let autoPayDate = draft.autoPayEnabled
                ? PlanningBillDraft.clampedDate(
                    calendar.startOfDay(for: draft.autoPayDate),
                    start: paymentStartDate,
                    end: effectiveDueDate
                )
                : nil
            return (
                calendar.component(.day, from: effectiveDueDate),
                calendar.component(.day, from: paymentStartDate),
                paymentStartDate,
                nil,
                hasExplicitDueDate,
                dueDate,
                draft.autoPayEnabled,
                nil,
                autoPayDate,
                1
            )
        }
    }

    private func recurringAutoPayDayLabel(_ day: Int) -> String {
        guard draft.hasDeadline, draft.dueDay < draft.paymentStartDay, day < draft.paymentStartDay else {
            return L10n.planning.planning.dayValue(String(describing: day))
        }
        return L10n.planning.planning.dayValueNextMonth(String(describing: day))
    }

    private func firstScheduledMonth(
        for choice: PlanningBillFirstScheduledMonthChoice
    ) -> Date {
        let currentMonth = PlanningLogic.startOfMonth(for: Date(), calendar: calendar)
        switch choice {
        case .currentMonth:
            return currentMonth
        case .nextMonth:
            return calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        }
    }

    private func normalizeAutoPayDraft() {
        switch draft.scheduleKind {
        case .recurring:
            if !draft.recurringAutoPayDayOptions.contains(draft.autoPayDay) {
                draft.autoPayDay = draft.paymentStartDay
            }
        case .oneTime:
            let window = draft.oneTimePaymentWindow
            draft.autoPayDate = PlanningBillDraft.clampedDate(draft.autoPayDate, start: window.lowerBound, end: window.upperBound)
        }
    }

    private func normalizeOneTimePaymentStartChange(from oldValue: Date) {
        guard draft.scheduleKind == .oneTime else {
            normalizeAutoPayDraft()
            return
        }

        let oldStart = calendar.startOfDay(for: oldValue)
        let newStart = calendar.startOfDay(for: draft.paymentStartDate)
        let currentDue = calendar.startOfDay(for: draft.dueDate)
        if !draft.hasDeadline || currentDue == oldStart || currentDue < newStart {
            draft.dueDate = newStart
        }

        let currentAutoPay = calendar.startOfDay(for: draft.autoPayDate)
        if !draft.autoPayEnabled || currentAutoPay == oldStart || currentAutoPay < newStart {
            draft.autoPayDate = newStart
        }

        normalizeAutoPayDraft()
    }

    private func pausePlan() {
        guard let plan = target.plan, plan.scheduleKind == .recurring else { return }
        let now = Date()

        do {
            try PlanningBillPauseActions.pause(
                plan,
                modelContext: modelContext,
                sessionStore: sessionStore,
                referenceDate: now
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTPauseThisBillRightNow + " \(error.localizedDescription)"
        }
    }

    private func resumePlan() {
        guard let plan = target.plan, plan.scheduleKind == .recurring else { return }
        let now = Date()

        do {
            try PlanningBillPauseActions.resume(
                plan,
                modelContext: modelContext,
                sessionStore: sessionStore,
                referenceDate: now,
                calendar: calendar
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTResumeThisBillRightNow + " \(error.localizedDescription)"
        }
    }

    private func archivePlan() {
        guard let plan = target.plan else { return }
        let now = Date()
        plan.isArchived = true
        plan.updatedAt = now

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .recurringBillPlan,
                recordID: plan.id,
                modifiedAt: now
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTArchiveThisBillRightNow + " \(error.localizedDescription)"
        }
    }

    private var selectedCategoryLabel: String {
        guard let selectedCategory else {
            return L10n.planning.planning.chooseChildCategory
        }

        let parentName = selectedCategory.parentCategory?.localizedDisplayName ?? selectedCategory.branchDisplayName
        return "\(parentName) / \(selectedCategory.localizedDisplayName)"
    }
}

struct PlanningInstallmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: PlanningInstallmentEditorTarget

    @State private var draft: PlanningInstallmentDraft
    private let initialDraft: PlanningInstallmentDraft
    @State private var paymentAmountText: String
    private let initialPaymentAmountText: String
    @State private var alertMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsIconPicker = false

    init(target: PlanningInstallmentEditorTarget) {
        self.target = target
        let initialDraft = PlanningInstallmentDraft(plan: target.plan)
        self.initialDraft = initialDraft
        let initialPaymentAmountText = target.dueItem?.amountMinor.map(String.init) ?? initialDraft.amountText
        self.initialPaymentAmountText = initialPaymentAmountText
        _draft = State(initialValue: initialDraft)
        _paymentAmountText = State(initialValue: initialPaymentAmountText)
    }

    private var availableWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([
            target.plan?.paymentWallet?.id,
            draft.paymentWalletID
        ].compactMap { $0 })
        return paymentWalletAccess.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            ownerUserID: installmentOwnerUserID,
            excludesCreditCards: true
        )
    }

    private var installmentOwnerUserID: UUID? {
        if let plan = target.plan,
           let ownerUserID = installmentOwnerMap[plan.id] {
            return ownerUserID
        }
        return familyContextStore.selectedSubjectUserID
            ?? paymentWalletAccess.currentSelfUserID
    }

    private var installmentOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .installmentPlan)
    }

    private var paymentWalletAccess: PlanningPaymentWalletAccess {
        PlanningPaymentWalletAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeCurrencyCode: String {
        target.plan?.currencyCode ?? target.dueItem?.currencyCode ?? currencyCode
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: target.plan == nil ? .creating : .editing,
            hasUnsavedChanges: draft != initialDraft || paymentAmountText != initialPaymentAmountText
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.planning.planning.identity) {
                    PlanningIconPickerButton(
                        title: L10n.planning.planning.iconKhoNTrGPVay,
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(L10n.planning.planning.installmentLoan) {
                    TextField(L10n.planning.planning.name, text: $draft.name)
                    MistiaCurrencyInputField(L10n.planning.planning.amountPerCycle, text: $draft.amountText)
                    Picker(L10n.planning.planning.dueDay, selection: $draft.dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(L10n.planning.planning.dayValue(String(describing: day))).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    Stepper(
                        L10n.planning.planning.frequencyEveryValueMonthS(String(describing: draft.frequencyMonths)),
                        value: $draft.frequencyMonths,
                        in: 1...12
                    )
                    TextField(L10n.planning.planning.totalCyclesOptional, text: $draft.totalCyclesText)
                        .keyboardType(.numberPad)
                    Picker(L10n.planning.planning.paymentWallet, selection: $draft.paymentWalletID) {
                        Text(L10n.planning.planning.chooseWallet).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(paymentWalletAccess.title(for: wallet)).tag(Optional(wallet.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let dueItem = target.dueItem, dueItem.status == .pending {
                    Section {
                        MistiaCurrencyInputField(L10n.planning.planning.paymentAmount, text: $paymentAmountText)

                        Button(L10n.planning.planning.payEarly) {
                            payEarly()
                        }
                    } header: {
                        Text(L10n.planning.planning.earlyPayment)
                    } footer: {
                        Text(L10n.planning.planning.thisPaymentWillBeRecordedAsA)
                    }
                }

                if target.plan != nil {
                    Section {
                        Button(L10n.planning.planning.deleteThisItem2, role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .dismissKeyboardOnTap()
            .navigationTitle(target.plan == nil ? L10n.planning.planning.khoNMI : L10n.planning.planning.sAKhoN)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save,
                    dismissGuardConfiguration: dismissGuardConfiguration
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: L10n.planning.planning.iconKhoNTrGPVay,
                options: MistiaFinanceIconRegistry.installmentOptions,
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
        .confirmationDialog(
            L10n.planning.planning.deleteThisItem,
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.common.delete, role: .destructive) {
                deletePlan()
            }

            Button(L10n.common.cancel, role: .cancel) { }
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = L10n.planning.planning.enterANameBeforeSaving
            return
        }

        let amountMinor = draft.amountText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
        guard amountMinor > 0 else {
            alertMessage = L10n.planning.planning.enterAnAmountPerCycleGreaterThan
            return
        }

        guard let wallet = storedWallets.first(where: { $0.id == draft.paymentWalletID }) else {
            alertMessage = L10n.planning.planning.chooseAPaymentWalletForThisItem
            return
        }

        let totalCycles = draft.totalCyclesText.nilIfBlank.flatMap(Int.init)
        let now = Date()
        let planForSync: InstallmentPlan

        if let plan = target.plan {
            plan.name = trimmedName
            plan.iconSymbolName = draft.iconSymbolName
            plan.amountPerCycleMinor = amountMinor
            plan.dueDay = draft.dueDay
            plan.totalCycles = totalCycles
            plan.frequencyMonths = draft.frequencyMonths
            plan.paymentWallet = wallet
            plan.updatedAt = now
            planForSync = plan
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
            planForSync = plan
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .installmentPlan,
                recordID: planForSync.id,
                modifiedAt: planForSync.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTSaveThisItemRightNow + " \(error.localizedDescription)"
        }
    }

    private func payEarly() {
        guard let dueItem = target.dueItem else { return }

        do {
            let draft = try PlanningLogic.makePaymentDraft(
                for: dueItem,
                overrideAmountMinor: paymentAmountText.nilIfBlank?.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)
            )
            let savedPayment = try PlanningPersistenceSupport.saveDuePayment(
                draft: draft,
                sourceKind: .installment,
                sourceID: dueItem.sourceID,
                selectedMonth: target.selectedMonth,
                scheduledDate: dueItem.dueDate,
                wallets: storedWallets,
                occurrences: Array(storedOccurrences),
                modelContext: modelContext,
                actorUserID: sessionStore.activeLocalProfileUserID
            )
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: savedPayment.transaction.id,
                modifiedAt: savedPayment.transaction.updatedAt,
                subjectUserIDOverride: savedPayment.subjectUserID
            )
            sessionStore.recordUpsert(
                entity: .dueOccurrenceRecord,
                recordID: savedPayment.occurrenceID,
                modifiedAt: savedPayment.transaction.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func deletePlan() {
        guard let plan = target.plan else { return }
        let now = Date()
        let fallbackSubjectUserID = sessionStore.activeLocalProfileUserID ?? MistiaSyncDeviceIdentity.current()
        let occurrenceMutations = storedOccurrences
            .filter { $0.sourceKind == .installment && $0.sourceID == plan.id }
            .map {
                MistiaSyncMutation(
                    entity: .dueOccurrenceRecord,
                    recordID: $0.id,
                    subjectUserID: fallbackSubjectUserID,
                    kind: .delete,
                    modifiedAt: now
                )
            }
        PlanningPersistenceSupport.deleteOccurrences(
            sourceKind: .installment,
            sourceID: plan.id,
            occurrences: Array(storedOccurrences),
            modelContext: modelContext
        )
        plan.markDeleted(at: now)

        do {
            try modelContext.save()
            sessionStore.recordMutations(
                occurrenceMutations + [
                    MistiaSyncMutation(
                        entity: .installmentPlan,
                        recordID: plan.id,
                        subjectUserID: fallbackSubjectUserID,
                        kind: .delete,
                        modifiedAt: now
                    )
                ]
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTDeleteThisItemRightNow + " \(error.localizedDescription)"
        }
    }
}

struct PlanningCreditCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"
    @Query
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedOccurrences: [DueOccurrenceRecord]
    @Query private var ownershipScopes: [OwnedRecordScope]

    let target: PlanningCreditCardEditorTarget

    @State private var draft: PlanningCreditCardDraft
    private let initialDraft: PlanningCreditCardDraft
    @State private var alertMessage: String?
    @State private var showsIconPicker = false

    init(target: PlanningCreditCardEditorTarget) {
        self.target = target
        let initialDraft = PlanningCreditCardDraft(wallet: target.wallet)
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    private var availablePaymentWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([draft.paymentSourceWalletID].compactMap { $0 })
        return paymentWalletAccess.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            ownerUserID: cardOwnerUserID,
            excludesCreditCards: true,
            excludedWalletID: target.wallet?.id
        )
    }

    private var cardOwnerUserID: UUID? {
        if let wallet = target.wallet {
            return paymentWalletAccess.walletOwnerUserID(for: wallet)
                ?? wallet.creditCardProfile.flatMap { creditCardProfileOwnerMap[$0.id] }
                ?? paymentWalletAccess.currentSelfUserID
        }
        return familyContextStore.selectedSubjectUserID
            ?? paymentWalletAccess.currentSelfUserID
    }

    private var creditCardProfileOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .creditCardProfile)
    }

    private var paymentWalletAccess: PlanningPaymentWalletAccess {
        PlanningPaymentWalletAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var activeCurrencyCode: String {
        target.wallet?.currencyCode ?? target.dueItem?.currencyCode ?? currencyCode
    }

    private var statementClosingDayOptions: [Int] {
        Array(1..<draft.paymentDueDay)
    }

    private var paymentDueDayOptions: [Int] {
        Array((draft.statementClosingDay + 1)...31)
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: target.wallet == nil ? .creating : .editing,
            hasUnsavedChanges: draft != initialDraft
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.planning.planning.identity) {
                    PlanningIconPickerButton(
                        title: L10n.planning.planning.biUTNgTh,
                        symbolName: draft.iconSymbolName,
                        colorHex: draft.iconColorHex
                    ) {
                        showsIconPicker = true
                    }
                }

                Section(L10n.planning.planning.cardDetails) {
                    TextField(L10n.planning.planning.cardName, text: $draft.name)
                    TextField(L10n.planning.planning.issuerName, text: $draft.issuerName)
                    Picker(L10n.planning.planning.cardNetwork, selection: $draft.network) {
                        ForEach(CreditCardNetwork.allCases) { network in
                            Text(network.title).tag(network)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField(L10n.planning.planning.lastDigits, text: $draft.last4)
                        .keyboardType(.numberPad)
                        .onChange(of: draft.last4) { _, newValue in
                            draft.last4 = String(newValue.filter(\.isNumber).prefix(4))
                        }
                    MistiaCurrencyInputField(L10n.planning.planning.creditLimit, text: $draft.creditLimitText)
                    Picker(L10n.planning.planning.dueDay, selection: $draft.paymentDueDay) {
                        ForEach(paymentDueDayOptions, id: \.self) { day in
                            Text(L10n.planning.planning.dayValue(String(describing: day))).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(L10n.planning.planning.statementClosingDay, selection: $draft.statementClosingDay) {
                        ForEach(statementClosingDayOptions, id: \.self) { day in
                            Text(L10n.planning.planning.dayValue(String(describing: day))).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle(L10n.planning.planning.autoPay, isOn: $draft.autoPayEnabled)
                        .tint(MistiaAccent.purple.color)
                        .toggleStyle(.switch)
                    Picker(L10n.planning.planning.paymentWallet, selection: $draft.paymentSourceWalletID) {
                        Text(L10n.planning.planning.chooseWallet).tag(Optional<UUID>.none)
                        ForEach(availablePaymentWallets) { wallet in
                            Text(paymentWalletAccess.title(for: wallet)).tag(Optional(wallet.id))
                        }
                    }
                    .pickerStyle(.menu)
                    TextField(L10n.planning.planning.notes, text: $draft.notes, axis: .vertical)
                        .lineLimit(3...5)
                }


                if target.wallet != nil {
                    MistiaDestructiveActionSection(
                        buttonTitle: L10n.planning.planning.archiveCard,
                        descriptionText: L10n.planning.planning.archivedCardsWillNoLongerAppearIn,
                        popupMessage: L10n.planning.planning.thisCardWillBeArchivedArchivedCards,
                        confirmationButtonTitle: L10n.common.archive
                    ) {
                        archiveWallet()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .dismissKeyboardOnTap()
            .navigationTitle(target.wallet == nil ? L10n.planning.planning.thMI : L10n.planning.planning.sATh)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlanningEditorToolbar(
                    onClose: { dismiss() },
                    onSave: save,
                    dismissGuardConfiguration: dismissGuardConfiguration
                )
            }
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .sheet(isPresented: $showsIconPicker) {
            PlanningIconPickerSheet(
                title: L10n.planning.planning.biUTNgTh,
                options: MistiaFinanceIconRegistry.creditCardOptions,
                selectedSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
            }
        }
        .planningAlert(message: $alertMessage)
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = L10n.planning.planning.enterACardNameBeforeSaving
            return
        }

        guard draft.statementClosingDay < draft.paymentDueDay else {
            alertMessage = L10n.planning.planning.statementClosingDayMustBeEarlierThan
            return
        }

        let creditLimitMinor = draft.creditLimitText.currencyInputToMinorUnits(currencyCode: activeCurrencyCode)

        let now = Date()
        let walletForSync: LedgerWallet

        if let wallet = target.wallet {
            wallet.name = trimmedName
            wallet.iconSymbolName = draft.iconSymbolName
            wallet.iconColorHex = draft.iconColorHex
            wallet.updatedAt = now
            updateProfile(for: wallet, creditLimitMinor: creditLimitMinor, now: now)
            walletForSync = wallet
        } else {
            let wallet = LedgerWallet(
                name: trimmedName,
                kind: .creditCard,
                iconSymbolName: draft.iconSymbolName,
                iconColorHex: draft.iconColorHex,
                currencyCode: activeCurrencyCode,
                sortOrder: nextSortOrder(),
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(wallet)
            updateProfile(for: wallet, creditLimitMinor: creditLimitMinor, now: now)
            walletForSync = wallet
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .wallet,
                recordID: walletForSync.id,
                modifiedAt: walletForSync.updatedAt
            )
            if let profile = walletForSync.creditCardProfile {
                sessionStore.recordUpsert(
                    entity: .creditCardProfile,
                    recordID: profile.id,
                    modifiedAt: profile.updatedAt
                )
            }
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTSaveThisCardRightNow + " \(error.localizedDescription)"
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
        profile.autoPayEnabled = draft.autoPayEnabled
        profile.paymentSourceWallet = storedWallets.first(where: { $0.id == draft.paymentSourceWalletID })
        profile.updatedAt = now

        if wallet.creditCardProfile == nil {
            wallet.creditCardProfile = profile
            modelContext.insert(profile)
        }
    }


    private func archiveWallet() {
        guard let wallet = target.wallet else { return }
        let now = Date()
        let fallbackSubjectUserID = sessionStore.activeLocalProfileUserID ?? MistiaSyncDeviceIdentity.current()
        wallet.isArchived = true
        wallet.archivedAt = now
        wallet.updatedAt = now
        let occurrenceMutations = storedOccurrences
            .filter { $0.sourceKind == .creditCard && $0.sourceID == wallet.id }
            .map {
                MistiaSyncMutation(
                    entity: .dueOccurrenceRecord,
                    recordID: $0.id,
                    subjectUserID: fallbackSubjectUserID,
                    kind: .delete,
                    modifiedAt: now
                )
            }
        PlanningPersistenceSupport.deleteOccurrences(
            sourceKind: .creditCard,
            sourceID: wallet.id,
            occurrences: Array(storedOccurrences),
            modelContext: modelContext
        )

        do {
            try modelContext.save()
            sessionStore.recordMutations(
                occurrenceMutations + [
                    MistiaSyncMutation(
                        entity: .wallet,
                        recordID: wallet.id,
                        subjectUserID: fallbackSubjectUserID,
                        kind: .upsert,
                        modifiedAt: wallet.updatedAt
                    )
                ]
            )
            dismiss()
        } catch {
            alertMessage = L10n.planning.planning.couldnTSaveTheArchiveStateFor + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedWallets.filter { !$0.isArchived }.map(\.sortOrder).max() ?? -1) + 1
    }
}

private struct PlanningEditorToolbar: ToolbarContent {
    let onClose: () -> Void
    let onSave: () -> Void
    var dismissGuardConfiguration: MistiaDismissGuardConfiguration?
    var canSave: Bool = true

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let dismissGuardConfiguration {
                MistiaGuardedDismissButton(configuration: dismissGuardConfiguration)
            } else {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onSave()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSave ? Color(red: 0.88, green: 0.78, blue: 1.0) : .secondary)
                    .frame(width: 30, height: 30)
            }
            .disabled(!canSave)
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
                    Text(L10n.planning.planning.chMIIcon)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
    }
}

private struct PlanningIconPickerSheet: View {
    let title: String
    let options: [MistiaFinancePickerOption]
    let onSave: (String, String) -> Void

    let selectedSymbolName: String
    let selectedColorHex: String

    init(
        title: String,
        options: [MistiaFinancePickerOption],
        selectedSymbolName: String,
        selectedColorHex: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.options = options
        self.onSave = onSave
        self.selectedSymbolName = selectedSymbolName
        self.selectedColorHex = selectedColorHex
    }

    var body: some View {
        MistiaFinanceIconPickerSheet(
            title: title,
            options: options,
            selectedToken: selectedSymbolName,
            onSave: onSave
        )
    }
}

private struct PlanningEditorIconPreview: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        MistiaFinanceIconView(icon: symbolName, fallbackColor: color, size: size)
    }
}

private struct PlanningBudgetDraft: Equatable {
    var categoryID: UUID?
    var limitText: String
    var rolloverEnabled: Bool
    var includesFamilySpending: Bool

    init(budget: BudgetPlan?) {
        categoryID = budget?.category?.id
        limitText = budget.map { String($0.limitMinor) } ?? ""
        rolloverEnabled = budget?.rolloverEnabled ?? false
        includesFamilySpending = budget?.includesFamilySpending ?? false
    }
}

private struct PlanningGoalDraft: Equatable {
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
        iconSymbolName = goal?.iconSymbolName ?? "mistia.goal.savings"
        iconColorHex = MistiaFinanceIconRegistry.defaultColorHex(for: iconSymbolName)
        linkedWalletID = goal?.linkedWallet?.id
    }
}

private struct PlanningBillDraft: Equatable {
    var name: String
    var amountText: String
    var scheduleKind: PlanningBillScheduleKind
    var paymentStartDay: Int
    var paymentStartDate: Date
    var firstScheduledMonthChoice: PlanningBillFirstScheduledMonthChoice
    var hasDeadline: Bool
    var dueDay: Int
    var dueDate: Date
    var autoPayEnabled: Bool
    var autoPayDay: Int
    var autoPayDate: Date
    var frequencyMonths: Int
    var paymentWalletID: UUID?
    var categoryID: UUID?
    var iconSymbolName: String
    var iconColorHex: String

    init(plan: RecurringBillPlan?) {
        name = plan?.name ?? ""
        amountText = plan?.amountMinor.map(String.init) ?? ""
        scheduleKind = plan?.scheduleKind ?? .recurring
        paymentStartDay = plan?.resolvedPaymentStartDay ?? plan?.dueDay ?? 10
        paymentStartDate = plan?.paymentStartDate ?? .now
        firstScheduledMonthChoice = .currentMonth
        hasDeadline = plan?.resolvedHasExplicitDueDate ?? false
        dueDay = plan?.dueDay ?? paymentStartDay
        dueDate = plan?.dueDate ?? plan?.paymentStartDate ?? .now
        autoPayEnabled = plan?.autoPayEnabled ?? false
        autoPayDay = plan?.autoPayDay ?? paymentStartDay
        autoPayDate = plan?.autoPayDate ?? plan?.paymentStartDate ?? .now
        frequencyMonths = max(plan?.frequencyMonths ?? 1, 1)
        paymentWalletID = plan?.paymentWallet?.id
        categoryID = plan?.category?.id
        iconSymbolName = plan?.category?.iconSymbolName ?? plan?.iconSymbolName ?? "mistia.plan.bill"
        iconColorHex = MistiaFinanceIconRegistry.defaultColorHex(for: iconSymbolName)
    }

    var recurringAutoPayDayOptions: [Int] {
        guard hasDeadline, dueDay != paymentStartDay else {
            return [paymentStartDay]
        }

        if dueDay > paymentStartDay {
            return Array(paymentStartDay...dueDay)
        }

        return Array(paymentStartDay...31) + Array(1...dueDay)
    }

    var oneTimePaymentWindow: ClosedRange<Date> {
        let start = MistiaCalendar.current.startOfDay(for: paymentStartDate)
        let rawDue = MistiaCalendar.current.startOfDay(for: dueDate)
        let end = hasDeadline && rawDue >= start ? rawDue : start
        return start...end
    }

    static func clampedDate(_ date: Date, start: Date, end: Date) -> Date {
        if date < start { return start }
        if date > end { return end }
        return date
    }
}

private enum PlanningBillFirstScheduledMonthChoice: String, CaseIterable, Identifiable {
    case currentMonth
    case nextMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentMonth:
            L10n.planning.planning.currentMonth
        case .nextMonth:
            L10n.planning.planning.nextMonth
        }
    }
}

private extension PlanningBillScheduleKind {
    var editorTitle: String {
        switch self {
        case .recurring:
            L10n.planning.planning.recurring
        case .oneTime:
            L10n.planning.planning.oneTime
        }
    }
}

private struct PlanningInstallmentDraft: Equatable {
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
        iconSymbolName = plan?.iconSymbolName ?? "mistia.plan.installment"
        iconColorHex = MistiaFinanceIconRegistry.defaultColorHex(for: iconSymbolName)
    }
}

private struct PlanningCreditCardDraft: Equatable {
    static let defaultPaymentDueDay = 26
    static let defaultStatementClosingDay = 10

    var name: String
    var iconSymbolName: String
    var iconColorHex: String
    var issuerName: String
    var network: CreditCardNetwork
    var last4: String
    var creditLimitText: String
    var paymentDueDay: Int
    var statementClosingDay: Int
    var autoPayEnabled: Bool
    var paymentSourceWalletID: UUID?
    var notes: String

    init(wallet: LedgerWallet?) {
        let profile = wallet?.creditCardProfile
        let normalizedBillingDays = Self.normalizedBillingDays(
            statementClosingDay: profile?.statementClosingDay,
            paymentDueDay: profile?.paymentDueDay
        )
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
        creditLimitText = profile.map { String($0.creditLimitMinor) } ?? ""
        paymentDueDay = normalizedBillingDays.paymentDueDay
        statementClosingDay = normalizedBillingDays.statementClosingDay
        autoPayEnabled = profile?.autoPayEnabled ?? false
        paymentSourceWalletID = profile?.paymentSourceWallet?.id
        notes = profile?.notes ?? ""
    }

    private static func normalizedBillingDays(
        statementClosingDay: Int?,
        paymentDueDay: Int?
    ) -> (statementClosingDay: Int, paymentDueDay: Int) {
        let closingDay = statementClosingDay ?? defaultStatementClosingDay
        let dueDay = paymentDueDay ?? defaultPaymentDueDay

        guard (1..<dueDay).contains(closingDay), (2...31).contains(dueDay) else {
            return (defaultStatementClosingDay, defaultPaymentDueDay)
        }

        return (closingDay, dueDay)
    }
}

private extension View {
    func planningAlert(message: Binding<String?>) -> some View {
        alert(
            L10n.planning.planning.canTCompleteYet,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text((message.wrappedValue ?? ""))
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
