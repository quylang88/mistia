import SwiftData
import SwiftUI

struct ManagementWalletEditorTarget: Identifiable {
    let id = UUID()
    let wallet: LedgerWallet?
    let defaultKind: LedgerWalletKind
}

struct ManagementCategoryEditorTarget: Identifiable {
    let id = UUID()
    let category: TransactionCategory?
    let defaultKind: TransactionCategoryKind
    let preferredParentCategoryID: UUID?
}

struct ManagementWalletEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query
    private var storedWallets: [LedgerWallet]
    @Query
    private var storedTransactions: [LedgerTransaction]
    @Query
    private var ownershipScopes: [OwnedRecordScope]

    let target: ManagementWalletEditorTarget

    @State private var draft: WalletDraft
    @State private var showsIconPicker = false
    @State private var showsBalanceAdjustment = false
    @State private var showsBankPicker = false
    @State private var alertMessage: String?
    // Edge Case 6: Confirmation for changing payment source wallet with debt
    @State private var showingPaymentSourceChangeConfirmation = false
    @State private var pendingPaymentSourceWalletID: UUID?

    init(target: ManagementWalletEditorTarget) {
        self.target = target
        _draft = State(initialValue: WalletDraft(wallet: target.wallet, defaultKind: target.defaultKind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.management.management.identity) {
                    Button {
                        showsIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: draft.iconSymbolName,
                                color: Color(hex: draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.management.management.icon)
                                    .foregroundStyle(.primary)
                                Text(L10n.management.management.tapToChangeTheWalletIcon)
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

                Section(L10n.management.management.basicDetails) {
                    TextField(L10n.management.management.walletName, text: $draft.name)

                    Picker(L10n.management.management.walletType, selection: $draft.kind) {
                        ForEach(LedgerWalletKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    if target.wallet == nil {
                        if draft.kind == .creditCard {
                            TextField(L10n.management.management.availableCredit, text: $draft.availableCreditText)
                                .keyboardType(.numberPad)
                        } else {
                            TextField(draft.kind.balanceFieldTitle, text: $draft.openingBalanceText)
                                .keyboardType(.numberPad)
                        }
                    } else {
                        LabeledContent(L10n.management.management.currentBalance) {
                            HStack(spacing: 10) {
                                Text(effectiveBalance.formattedCurrency(code: draft.currencyCode))
                                    .foregroundStyle(.secondary)

                                ManagementBalanceEditButton {
                                    showsBalanceAdjustment = true
                                }
                            }
                        }
                    }

                    if canEditWalletCurrency {
                        Picker(L10n.management.management.currency, selection: $draft.currencyCode) {
                            ForEach(MistiaCurrencySettings.enabledCurrencyCodes(), id: \.self) { code in
                                Text(verbatim: code).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        LabeledContent(L10n.management.management.currency) {
                            Text(draft.currencyCode)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if draft.kind == .bank {
                    Section(L10n.management.management.bank) {
                        Button {
                            showsBankPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.management.management.chooseAPopularBank)
                                        .foregroundStyle(.primary)

                                    Text(draft.institutionDisplayName.nilIfBlank ?? L10n.management.management.notSelected)
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

                        TextField(L10n.management.management.orEnterTheBankName, text: $draft.institutionDisplayName)
                            .onChange(of: draft.institutionDisplayName) { _, newValue in
                                handleInstitutionDisplayNameChange(newValue)
                            }
                    }
                }

                if draft.kind == .creditCard {
                    creditCardFormSection
                }

                if target.wallet != nil {
                    Section {
                        MistiaArchiveSection(
                            buttonTitle: L10n.management.management.archiveWallet,
                            descriptionText: L10n.management.management.archivedWalletsWillNoLongerAppearIn,
                            popupMessage: L10n.management.management.thisWalletWillBeArchivedArchivedWallets
                        ) {
                            archiveWallet()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(target.wallet == nil ? L10n.management.walletEditor.newTitle : L10n.management.walletEditor.editTitle)
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
                        save()
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
        .sheet(isPresented: $showsIconPicker) {
            ManagementIconPickerSheet(
                title: L10n.management.management.biUTNgV,
                options: draft.kind == .creditCard ? MistiaFinanceIconRegistry.creditCardOptions : MistiaFinanceIconRegistry.walletOptions,
                selectedIconSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
                draft.iconWasCustomized = true
            }
        }
        .sheet(isPresented: $showsBankPicker) {
            ManagementBankPickerSheet(
                selectedBankKey: draft.institutionPresetKey,
                initialManualName: draft.institutionDisplayName
            ) { selectedBank, manualName in
                draft.institutionPresetKey = selectedBank?.key
                draft.institutionDisplayName = selectedBank?.name ?? manualName
            }
        }
        .alert(
            L10n.management.management.canTSaveYet,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text((alertMessage ?? ""))
        }
        // Edge Case 6: Confirmation dialog for changing payment source wallet with debt
        .alert(
            L10n.management.management.confirmPaymentSourceChange,
            isPresented: $showingPaymentSourceChangeConfirmation
        ) {
            Button(L10n.common.cancel, role: .cancel) {
                pendingPaymentSourceWalletID = nil
            }
            Button(L10n.management.management.continue, role: .destructive) {
                performSave()
            }
        } message: {
            Text(L10n.management.management.thisCreditCardHasOutstandingDebtChanging)
        }
        .onChange(of: draft.kind) { oldValue, newValue in
            draft.handleKindChange(from: oldValue, to: newValue)
        }
        .sheet(isPresented: $showsBalanceAdjustment) {
            if let wallet = target.wallet {
                let creditLimit = wallet.kind == .creditCard ? wallet.creditCardProfile?.creditLimitMinor : nil
                ManagementBalanceAdjustmentSheet(
                    wallet: wallet,
                    currentBalance: effectiveBalance,
                    creditLimit: creditLimit
                )
            }
        }
    }

    private var creditCardFormSection: some View {
        Section(L10n.management.management.creditCard) {
            TextField(L10n.management.management.issuerName, text: $draft.issuerName)

            Picker(L10n.management.management.cardNetwork, selection: $draft.network) {
                ForEach(CreditCardNetwork.allCases) { network in
                    Text(network.title).tag(network)
                }
            }
            .pickerStyle(.menu)

            TextField(L10n.management.management.lastDigits, text: $draft.last4)
                .keyboardType(.numberPad)
                .onChange(of: draft.last4) { _, newValue in
                    draft.last4 = String(newValue.filter(\.isNumber).prefix(4))
                }

            TextField(L10n.management.management.creditLimit, text: $draft.creditLimitText)
                .keyboardType(.numberPad)

            creditCardDayPicker(
                title: L10n.management.management.statementClosingDay,
                days: statementClosingDayOptions,
                selection: $draft.statementClosingDay
            )

            creditCardDayPicker(
                title: L10n.management.management.paymentDay,
                days: paymentDueDayOptions,
                selection: $draft.paymentDueDay
            )

            Picker(L10n.management.management.paymentSource, selection: $draft.paymentSourceWalletID) {
                Text(L10n.management.management.chooseLater).tag(Optional<UUID>.none)

                ForEach(paymentSourceWallets) { wallet in
                    Text(walletPickerAccess.title(for: wallet)).tag(Optional(wallet.id))
                }
            }
            .pickerStyle(.menu)

            TextField(L10n.management.management.notes, text: $draft.notes, axis: .vertical)
                .lineLimit(3...5)
        }
    }

    private func creditCardDayPicker(
        title: String,
        days: [Int],
        selection: Binding<Int>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(days, id: \.self) { day in
                Text(L10n.management.management.dayValue(String(describing: day))).tag(day)
            }
        }
        .pickerStyle(.menu)
    }

    private var statementClosingDayOptions: [Int] {
        Array(1..<draft.paymentDueDay)
    }

    private var paymentDueDayOptions: [Int] {
        Array((draft.statementClosingDay + 1)...31)
    }

    private func handleInstitutionDisplayNameChange(_ newValue: String) {
        let selectedKey = draft.institutionPresetKey
        let selectedBank = ManagementPresetData.japaneseBanks.first { bank in
            bank.key == selectedKey
        }
        if let selectedBank, selectedBank.name != newValue {
            draft.institutionPresetKey = nil
        }
    }

    private var paymentSourceWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([target.wallet?.creditCardProfile?.paymentSourceWallet?.id, draft.paymentSourceWalletID].compactMap { $0 })
        return walletPickerAccess.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            targetOwnerUserID: targetWalletOwnerUserID,
            excludesCreditCards: true,
            excludedWalletID: target.wallet?.id
        )
    }

    private var targetWalletOwnerUserID: UUID? {
        if let wallet = target.wallet {
            return walletPickerAccess.walletOwnerUserID(for: wallet)
        }
        return familyContextStore.selectedSubjectUserID
            ?? walletPickerAccess.currentSelfUserID
    }

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private func save() {
        if draft.kind == .bank, draft.institutionDisplayName.nilIfBlank == nil {
            alertMessage = L10n.management.management.chooseOrEnterABankNameFor
            return
        }

        if draft.kind == .creditCard, draft.statementClosingDay >= draft.paymentDueDay {
            alertMessage = L10n.management.management.statementClosingDayMustBeEarlierThan
            return
        }

        // Edge Case 6: Check for payment source wallet change with outstanding debt
        if draft.kind == .creditCard,
           let existingWallet = target.wallet,
           let existingProfile = existingWallet.creditCardProfile,
           existingProfile.paymentSourceWallet?.id != draft.paymentSourceWalletID {
            
            // Calculate current debt
            let txDescriptor = FetchDescriptor<LedgerTransaction>()
            let allTransactions = (try? modelContext.fetch(txDescriptor)) ?? []
            let records = allTransactions.filter { $0.deletedAt == nil }.map { $0.snapshot }

            let walletSnapshot = TransactionWalletSnapshot(
                id: existingWallet.id,
                kind: existingWallet.kind,
                openingBalanceMinor: existingWallet.openingBalanceMinor
            )
            let currentDebt = TransactionLogic.effectiveBalance(for: walletSnapshot, records: records)

            if currentDebt > 0 {
                // Show confirmation dialog
                pendingPaymentSourceWalletID = draft.paymentSourceWalletID
                showingPaymentSourceChangeConfirmation = true
                return
            }
        }

        performSave()
    }

    private func performSave() {
        let defaultName: String
        switch draft.kind {
        case .bank:
            defaultName = draft.institutionDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .creditCard:
            if let issuer = draft.issuerName.nilIfBlank {
                defaultName = issuer
            } else {
                defaultName = draft.kind.title
            }
        default:
            defaultName = draft.kind.title
        }

        let trimmedName = draft.name.nilIfBlank ?? defaultName

        let now = Date()
        let existingProfileID = target.wallet?.creditCardProfile?.id
        let walletForSync: LedgerWallet

        // For credit cards, calculate debt from available credit
        let currentDebtMinor: Int64
        if draft.kind == .creditCard {
            currentDebtMinor = max(draft.creditLimitMinor - draft.availableCreditMinor, 0)
        } else {
            currentDebtMinor = draft.openingBalanceMinor
        }

        if let existingWallet = target.wallet {
            existingWallet.name = trimmedName
            existingWallet.kind = draft.kind
            existingWallet.iconSymbolName = draft.iconSymbolName
            existingWallet.iconColorHex = draft.iconColorHex
            existingWallet.currencyCode = draft.currencyCode
            existingWallet.openingBalanceMinor = currentDebtMinor
            existingWallet.institutionDisplayName = draft.kind == .bank ? draft.institutionDisplayName.nilIfBlank : nil
            existingWallet.institutionPresetKey = draft.kind == .bank ? draft.institutionPresetKey : nil
            existingWallet.updatedAt = now

            // Apply pending payment source wallet ID if confirmed
            if let pendingID = pendingPaymentSourceWalletID {
                draft.paymentSourceWalletID = pendingID
                pendingPaymentSourceWalletID = nil
            }

            updateCreditCardProfile(for: existingWallet, now: now)
            walletForSync = existingWallet
        } else {
            let newWallet = LedgerWallet(
                name: trimmedName,
                kind: draft.kind,
                iconSymbolName: draft.iconSymbolName,
                iconColorHex: draft.iconColorHex,
                currencyCode: draft.currencyCode,
                openingBalanceMinor: currentDebtMinor,
                institutionDisplayName: draft.kind == .bank ? draft.institutionDisplayName.nilIfBlank : nil,
                institutionPresetKey: draft.kind == .bank ? draft.institutionPresetKey : nil,
                sortOrder: nextSortOrder()
            )

            modelContext.insert(newWallet)
            updateCreditCardProfile(for: newWallet, now: now)
            walletForSync = newWallet
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .wallet,
                recordID: walletForSync.id,
                modifiedAt: walletForSync.updatedAt
            )

            if draft.kind == .creditCard, let profile = walletForSync.creditCardProfile {
                sessionStore.recordUpsert(
                    entity: .creditCardProfile,
                    recordID: profile.id,
                    modifiedAt: profile.updatedAt
                )
            } else if let existingProfileID {
                sessionStore.recordDelete(
                    entity: .creditCardProfile,
                    recordID: existingProfileID,
                    modifiedAt: now
                )
            }
            dismiss()
        } catch {
            alertMessage = L10n.management.management.couldnTSaveThisWalletRightNow + " \(error.localizedDescription)"
        }
    }

    private var effectiveBalance: Int64 {
        guard let wallet = target.wallet else { return 0 }

        let txDescriptor = FetchDescriptor<LedgerTransaction>()
        let allTransactions = (try? modelContext.fetch(txDescriptor)) ?? []
        let records = allTransactions
            .filter { $0.deletedAt == nil }
            .map { $0.snapshot }

        let walletSnapshot = TransactionWalletSnapshot(
            id: wallet.id,
            kind: wallet.kind,
            openingBalanceMinor: wallet.openingBalanceMinor
        )

        let debt = TransactionLogic.effectiveBalance(for: walletSnapshot, records: records)
        
        // For credit cards, show available credit (limit - debt), not debt
        if wallet.kind == .creditCard, let profile = wallet.creditCardProfile {
            return max(profile.creditLimitMinor - debt, 0)
        }
        
        return debt
    }

    private var canEditWalletCurrency: Bool {
        guard let wallet = target.wallet else { return true }
        return !storedTransactions.contains {
            $0.sourceWallet?.id == wallet.id || $0.destinationWallet?.id == wallet.id
        }
    }

    private func updateCreditCardProfile(for wallet: LedgerWallet, now: Date) {
        guard draft.kind == .creditCard else {
            if let profile = wallet.creditCardProfile {
                wallet.creditCardProfile = nil
                profile.wallet = nil
                profile.paymentSourceWallet = nil
                profile.markDeleted(at: now)
            }
            return
        }

        let profile = wallet.creditCardProfile ?? CreditCardProfile()
        profile.wallet = wallet
        profile.issuerName = draft.issuerName.nilIfBlank ?? ""
        profile.network = draft.network
        profile.last4 = draft.last4
        profile.creditLimitMinor = draft.creditLimitMinor
        profile.statementClosingDay = draft.statementClosingDay
        profile.paymentDueDay = draft.paymentDueDay
        profile.notes = draft.notes.nilIfBlank
        profile.paymentSourceWallet = paymentSourceWallets.first(where: { $0.id == draft.paymentSourceWalletID })
        profile.updatedAt = now

        if wallet.creditCardProfile == nil {
            wallet.creditCardProfile = profile
            modelContext.insert(profile)
        }
    }

    private func archiveWallet() {
        guard let wallet = target.wallet else { return }

        // Edge Case 5: Validate cannot archive credit card with outstanding debt
        if wallet.kind == .creditCard {
            let txDescriptor = FetchDescriptor<LedgerTransaction>()
            let allTransactions = (try? modelContext.fetch(txDescriptor)) ?? []
            let records = allTransactions
                .filter { $0.deletedAt == nil }
                .map { $0.snapshot }

            let walletSnapshot = TransactionWalletSnapshot(
                id: wallet.id,
                kind: wallet.kind,
                openingBalanceMinor: wallet.openingBalanceMinor
            )

            let currentDebt = TransactionLogic.effectiveBalance(for: walletSnapshot, records: records)

            if currentDebt > 0 {
                alertMessage = L10n.management.management.cannotArchiveCreditCardWithOutstandingDebt(String(describing: currentDebt.formattedCurrency(code: wallet.currencyCode)))
                return
            }

            // Also check for any unpaid statements in recent months
            let calendar = MistiaCalendar.current
            let currentMonth = PlanningLogic.startOfMonth(for: .now, calendar: calendar)
            let recentMonths = (0...3).compactMap { calendar.date(byAdding: .month, value: -$0, to: currentMonth) }

            for month in recentMonths {
                let hasPayment = allTransactions.contains { tx in
                    tx.destinationWallet?.id == wallet.id
                        && calendar.isDate(tx.occurredAt, equalTo: month, toGranularity: .month)
                        && TransactionLogic.isCreditCardPayment(tx.snapshot)
                }

                let hasExpenses = allTransactions.contains { tx in
                    tx.sourceWallet?.id == wallet.id &&
                    tx.primaryKind == .expense &&
                    calendar.isDate(tx.occurredAt, equalTo: month, toGranularity: .month)
                }

                if hasExpenses && !hasPayment {
                    alertMessage = L10n.management.management.cannotArchiveCreditCardWithUnpaidStatements
                    return
                }
            }
        }

        wallet.isArchived = true
        wallet.archivedAt = .now
        wallet.updatedAt = .now

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .wallet,
                recordID: wallet.id,
                modifiedAt: wallet.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.management.management.couldnTSaveTheArchiveState + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedWallets
            .filter { $0.deletedAt == nil }
            .map(\.sortOrder)
            .max() ?? -1) + 1
    }
}

struct ManagementCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Query
    private var storedCategories: [TransactionCategory]

    let target: ManagementCategoryEditorTarget

    @State private var draft: CategoryDraft
    @State private var showsIconPicker = false
    @State private var showsParentPicker = false
    @State private var alertMessage: String?
    @State private var isSaving = false

    init(target: ManagementCategoryEditorTarget) {
        self.target = target
        _draft = State(initialValue: CategoryDraft(
            category: target.category,
            defaultKind: target.defaultKind,
            preferredParentCategoryID: target.preferredParentCategoryID
        ))
    }

    private var availableParentCategories: [TransactionCategory] {
        MistiaCategoryHierarchy.parentCategories(
            from: storedCategories,
            kind: draft.kind,
            includeArchived: false
        )
        .filter { $0.id != target.category?.id }
    }

    private var selectedParentCategory: TransactionCategory? {
        availableParentCategories.first(where: { $0.id == draft.parentCategoryID })
    }

    private var canEditHierarchyRole: Bool {
        target.category == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.management.management.identity) {
                    Button {
                        showsIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: draft.iconSymbolName,
                                color: Color(hex: draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.management.management.icon)
                                    .foregroundStyle(.primary)
                                Text(L10n.management.management.chooseACoordinatedFinanceIconForThis)
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

                Section(L10n.management.management.details) {
                    TextField(L10n.management.management.categoryName, text: $draft.name)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.management.management.categoryType)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        MistiaNativeSegmentedControl(
                            selection: $draft.kind,
                            options: TransactionCategoryKind.allCases,
                            title: \.title
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.management.management.structure)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        MistiaNativeSegmentedControl(
                            selection: $draft.hierarchyRole,
                            options: TransactionCategoryHierarchyRole.allCases,
                            title: \.title
                        )
                        .disabled(!canEditHierarchyRole)
                        .opacity(canEditHierarchyRole ? 1 : 0.68)
                    }

                    if draft.hierarchyRole == .child {
                        Button {
                            showsParentPicker = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.management.management.parentCategory)
                                        .foregroundStyle(.primary)
                                    Text(
                                        selectedParentCategory?.localizedDisplayName
                                            ?? L10n.management.management.chooseParentCategory
                                    )
                                        .font(.footnote)
                                        .foregroundStyle(selectedParentCategory == nil ? .tertiary : .secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))

                        Toggle(
                            L10n.management.management.favorite,
                            isOn: $draft.isFavorite
                        )
                        .tint(MistiaAccent.purple.color)
                        .toggleStyle(.switch)
                    }
                }

                if target.category != nil {
                    Section {
                        MistiaArchiveSection(
                            buttonTitle: L10n.management.management.archiveCategory,
                            descriptionText: L10n.management.management.archivedCategoriesWillNoLongerAppearIn,
                            popupMessage: L10n.management.management.thisCategoryWillBeArchivedArchivedCategories
                        ) {
                            archiveCategory()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(target.category == nil ? L10n.management.categoryEditor.newTitle : L10n.management.categoryEditor.editTitle)
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
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(red: 0.88, green: 0.78, blue: 1.0))
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 1.0))
                                .frame(width: 30, height: 30)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
                    .disabled(isSaving)
                }
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            ManagementIconPickerSheet(
                title: L10n.management.management.biUTNgDanhMC,
                options: MistiaFinanceIconRegistry.activeCategoryOptions(for: draft.kind),
                selectedIconSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
                draft.iconWasCustomized = true
            }
        }
        .sheet(isPresented: $showsParentPicker) {
            ManagementParentCategoryPickerSheet(
                selectedParentCategoryID: draft.parentCategoryID,
                parents: availableParentCategories
            ) { category in
                draft.parentCategoryID = category.id
            }
        }
        .alert(
            L10n.management.management.canTSaveYet,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text((alertMessage ?? ""))
        }
        .onChange(of: draft.kind) { oldValue, newValue in
            draft.handleKindChange(from: oldValue, to: newValue)
            if selectedParentCategory?.kind != newValue {
                draft.parentCategoryID = nil
            }
        }
        .onChange(of: draft.hierarchyRole) { _, newValue in
            if newValue == .parent {
                draft.parentCategoryID = nil
                draft.isFavorite = false
            }
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = L10n.management.management.enterACategoryNameBeforeSaving
            return
        }

        if draft.hierarchyRole == .child && selectedParentCategory == nil {
            alertMessage = L10n.management.management.chooseAParentCategoryForThisChild
            return
        }

        isSaving = true
        defer { isSaving = false }

        let now = Date()
        let selectedParentCategory = draft.hierarchyRole == .child ? selectedParentCategory : nil
        let sourceLanguage = MistiaAppLanguage.current
        let fallbackName = CategoryNameTranslations.fallback(
            inputName: trimmedName,
            sourceLanguage: sourceLanguage,
            existingCategory: target.category
        )
        let categoryForSync: TransactionCategory

        if let category = target.category {
            let previousKind = category.kind
            let previousParentID = category.parentCategory?.id
            let previousRole = category.hierarchyRole
            category.name = fallbackName.name
            category.nameEnglish = fallbackName.nameEnglish
            category.nameJapanese = fallbackName.nameJapanese
            category.pendingTranslationSourceName = trimmedName
            category.pendingTranslationSourceLanguageRawValue = sourceLanguage.rawValue
            category.kind = draft.kind
            category.iconSymbolName = draft.iconSymbolName
            category.iconColorHex = draft.iconColorHex
            category.parentCategory = selectedParentCategory
            category.hierarchyRole = draft.hierarchyRole
            category.isFavorite = draft.hierarchyRole == .child ? draft.isFavorite : false
            category.updatedAt = now

            if previousKind != draft.kind || previousParentID != selectedParentCategory?.id || previousRole != draft.hierarchyRole {
                category.sortOrder = nextSortOrder(
                    for: draft.kind,
                    parentID: selectedParentCategory?.id,
                    excluding: category
                )
            }
            categoryForSync = category
        } else {
            let category = TransactionCategory(
                name: fallbackName.name,
                nameEnglish: fallbackName.nameEnglish,
                nameJapanese: fallbackName.nameJapanese,
                pendingTranslationSourceName: trimmedName,
                pendingTranslationSourceLanguageRawValue: sourceLanguage.rawValue,
                kind: draft.kind,
                iconSymbolName: draft.iconSymbolName,
                iconColorHex: draft.iconColorHex,
                isFavorite: draft.hierarchyRole == .child ? draft.isFavorite : false,
                parentCategory: selectedParentCategory,
                hierarchyRole: draft.hierarchyRole,
                isSystem: false,
                cloudSyncEnabled: true,
                sortOrder: nextSortOrder(
                    for: draft.kind,
                    parentID: selectedParentCategory?.id,
                    excluding: nil
                )
            )
            modelContext.insert(category)
            categoryForSync = category
        }

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .category,
                recordID: categoryForSync.id,
                modifiedAt: categoryForSync.updatedAt
            )
            scheduleCategoryNameTranslation(
                inputName: trimmedName,
                sourceLanguage: sourceLanguage,
                fallbackName: fallbackName,
                categoryID: categoryForSync.id,
                savedUpdatedAt: categoryForSync.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.management.management.couldnTSaveThisCategoryRightNow + " \(error.localizedDescription)"
        }
    }

    @MainActor
    private func scheduleCategoryNameTranslation(
        inputName: String,
        sourceLanguage: MistiaAppLanguage,
        fallbackName: CategoryNameTranslations,
        categoryID: UUID,
        savedUpdatedAt: Date
    ) {
        Task { @MainActor in
            guard let translatedName = await remoteTranslatedCategoryName(
                for: inputName,
                sourceLanguage: sourceLanguage,
                fallbackName: fallbackName
            ), translatedName != fallbackName else {
                return
            }

            var descriptor = FetchDescriptor<TransactionCategory>(
                predicate: #Predicate { category in
                    category.id == categoryID
                }
            )
            descriptor.fetchLimit = 1

            guard let category = try? modelContext.fetch(descriptor).first,
                  abs(category.updatedAt.timeIntervalSince(savedUpdatedAt)) < 0.001
            else {
                return
            }

            let now = Date()
            category.name = translatedName.name
            category.nameEnglish = translatedName.nameEnglish
            category.nameJapanese = translatedName.nameJapanese
            category.pendingTranslationSourceName = nil
            category.pendingTranslationSourceLanguageRawValue = nil
            category.updatedAt = now

            do {
                try modelContext.save()
                sessionStore.recordUpsert(
                    entity: .category,
                    recordID: categoryID,
                    modifiedAt: now
                )
            } catch {
                // The category is already saved locally; translation can be retried on the next edit.
            }
        }
    }

    @MainActor
    private func remoteTranslatedCategoryName(
        for inputName: String,
        sourceLanguage: MistiaAppLanguage,
        fallbackName: CategoryNameTranslations
    ) async -> CategoryNameTranslations? {
        let session = try? await sessionStore.refreshedSession()
        return await CategoryNameTranslationResolver().translateCategoryName(
            inputName: inputName,
            sourceLanguage: sourceLanguage,
            fallbackName: fallbackName,
            session: session
        )
    }

    private func archiveCategory() {
        guard let category = target.category else { return }

        let hasActiveChildren = storedCategories.contains { candidate in
            candidate.deletedAt == nil
                && !candidate.isArchived
                && candidate.parentCategory?.id == category.id
        }
        if category.isParentCategory && hasActiveChildren {
            alertMessage = L10n.management.management.thisParentCategoryStillHasActiveChild
            return
        }

        category.isArchived = true
        category.archivedAt = .now
        category.updatedAt = .now

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .category,
                recordID: category.id,
                modifiedAt: category.updatedAt
            )
            dismiss()
        } catch {
            alertMessage = L10n.management.management.couldnTSaveTheArchiveState + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder(
        for kind: TransactionCategoryKind,
        parentID: UUID?,
        excluding category: TransactionCategory?
    ) -> Int {
        let maxSort = storedCategories
            .filter {
                $0.deletedAt == nil
                    && !$0.isArchived
                    && $0.kind == kind
                    && $0.parentCategory?.id == parentID
                    && $0.id != category?.id
            }
            .map(\.sortOrder)
            .max() ?? -1

        return maxSort + 1
    }
}

private struct ManagementIconPickerSheet: View {
    let title: String
    let options: [MistiaFinancePickerOption]
    let onSave: (String, String) -> Void

    let selectedIconSymbolName: String
    let selectedColorHex: String

    init(
        title: String,
        options: [MistiaFinancePickerOption],
        selectedIconSymbolName: String,
        selectedColorHex: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.options = options
        self.onSave = onSave
        self.selectedIconSymbolName = selectedIconSymbolName
        self.selectedColorHex = selectedColorHex
    }

    var body: some View {
        MistiaFinanceIconPickerSheet(
            title: title,
            options: options,
            selectedToken: selectedIconSymbolName,
            onSave: onSave
        )
    }
}

private struct ManagementBankPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedBankKey: String?
    let onSelect: (JapaneseBankPreset?, String) -> Void

    @State private var searchText = ""
    @State private var manualName: String

    init(
        selectedBankKey: String?,
        initialManualName: String,
        onSelect: @escaping (JapaneseBankPreset?, String) -> Void
    ) {
        self.selectedBankKey = selectedBankKey
        self.onSelect = onSelect
        _manualName = State(initialValue: initialManualName)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.management.management.popularBanksInJapan) {
                    ForEach(filteredBanks) { bank in
                        Button {
                            onSelect(bank, bank.name)
                            dismiss()
                        } label: {
                            HStack {
                                Text(bank.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if selectedBankKey == bank.key {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section(L10n.management.management.donTSeeItHere) {
                    TextField(L10n.management.management.enterBankNameManually, text: $manualName)

                    Button(L10n.management.management.useThisName) {
                        onSelect(nil, manualName.nilIfBlank ?? "")
                        dismiss()
                    }
                    .disabled(manualName.nilIfBlank == nil)
                }
            }
            .searchable(text: $searchText, prompt: L10n.management.management.searchBanks)
            .navigationTitle(L10n.management.management.chooseBank)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.management.management.close) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredBanks: [JapaneseBankPreset] {
        guard let searchTerm = searchText.nilIfBlank?.localizedLowercase else {
            return ManagementPresetData.japaneseBanks
        }

        return ManagementPresetData.japaneseBanks.filter { bank in
            bank.name.localizedLowercase.contains(searchTerm)
        }
    }
}

private struct ManagementParentCategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedParentCategoryID: UUID?
    let parents: [TransactionCategory]
    let onSelect: (TransactionCategory) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(parents) { category in
                    Button {
                        onSelect(category)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: category.iconSymbolName,
                                color: category.iconColor,
                                size: 34
                            )

                            Text(category.localizedDisplayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if category.id == selectedParentCategoryID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.management.management.parentCategory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.management.management.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ManagementEditorIconPreview: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        MistiaFinanceIconView(icon: symbolName, fallbackColor: color, size: size)
    }
}

private struct ManagementBalanceEditButton: View {
    @Environment(\.colorScheme) private var colorScheme
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
        .accessibilityLabel(L10n.management.management.editBalance)
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "pencil")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))

            Text(L10n.management.management.edit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct WalletDraft {
    static let defaultStatementClosingDay = 10
    static let defaultPaymentDueDay = 26

    var name: String
    var kind: LedgerWalletKind
    var iconSymbolName: String
    var iconColorHex: String
    var currencyCode: String
    var openingBalanceText: String
    var availableCreditText: String
    var institutionDisplayName: String
    var institutionPresetKey: String?
    var issuerName: String
    var network: CreditCardNetwork
    var last4: String
    var creditLimitText: String
    var statementClosingDay: Int
    var paymentDueDay: Int
    var notes: String
    var paymentSourceWalletID: UUID?
    var iconWasCustomized: Bool

    init(wallet: LedgerWallet?, defaultKind: LedgerWalletKind) {
        if let wallet {
            let profile = wallet.creditCardProfile
            let normalizedBillingDays = Self.normalizedBillingDays(
                statementClosingDay: profile?.statementClosingDay,
                paymentDueDay: profile?.paymentDueDay
            )
            let matchesDefaultIcon = wallet.kind.matchesDefaultIconAppearance(
                symbolName: wallet.iconSymbolName,
                colorHex: wallet.iconColorHex
            )
            
            let currentDebtMinor = wallet.openingBalanceMinor
            let creditLimitMinor = profile?.creditLimitMinor ?? 0
            let availableCreditMinor = max(creditLimitMinor - currentDebtMinor, 0)

            self.name = wallet.name
            self.kind = wallet.kind
            self.iconSymbolName = wallet.iconSymbolName
            self.iconColorHex = wallet.kind.migratedLegacyDefaultColorHex(
                for: wallet.iconColorHex,
                symbolName: wallet.iconSymbolName
            ) ?? MistiaIconColorPalette.normalizedHex(wallet.iconColorHex)
            self.currencyCode = wallet.currencyCode
            self.openingBalanceText = "\(wallet.openingBalanceMinor)"
            self.availableCreditText = "\(availableCreditMinor)"
            self.institutionDisplayName = wallet.institutionDisplayName ?? ""
            self.institutionPresetKey = wallet.institutionPresetKey
            self.issuerName = profile?.issuerName ?? ""
            self.network = profile?.network ?? .visa
            self.last4 = profile?.last4 ?? ""
            self.creditLimitText = profile.map { "\($0.creditLimitMinor)" } ?? ""
            self.statementClosingDay = normalizedBillingDays.statementClosingDay
            self.paymentDueDay = normalizedBillingDays.paymentDueDay
            self.notes = profile?.notes ?? ""
            self.paymentSourceWalletID = profile?.paymentSourceWallet?.id
            self.iconWasCustomized = !matchesDefaultIcon
        } else {
            self.name = ""
            self.kind = defaultKind
            self.iconSymbolName = defaultKind.defaultIconSymbolName
            self.iconColorHex = defaultKind.defaultColorHex
            self.currencyCode = "JPY"
            self.openingBalanceText = ""
            self.availableCreditText = ""
            self.institutionDisplayName = ""
            self.institutionPresetKey = nil
            self.issuerName = ""
            self.network = .visa
            self.last4 = ""
            self.creditLimitText = ""
            self.statementClosingDay = Self.defaultStatementClosingDay
            self.paymentDueDay = Self.defaultPaymentDueDay
            self.notes = ""
            self.paymentSourceWalletID = nil
            self.iconWasCustomized = false
        }
    }

    var openingBalanceMinor: Int64 {
        openingBalanceText.currencyInputToMinorUnits(currencyCode: currencyCode)
    }
    
    var availableCreditMinor: Int64 {
        availableCreditText.currencyInputToMinorUnits(currencyCode: currencyCode)
    }

    var creditLimitMinor: Int64 {
        creditLimitText.currencyInputToMinorUnits(currencyCode: currencyCode)
    }

    mutating func handleKindChange(from oldValue: LedgerWalletKind, to newValue: LedgerWalletKind) {
        guard oldValue != newValue else { return }

        if !iconWasCustomized {
            iconSymbolName = newValue.defaultIconSymbolName
            iconColorHex = newValue.defaultColorHex
        }

        if newValue != .bank {
            institutionDisplayName = ""
            institutionPresetKey = nil
        }

        if newValue != .creditCard {
            issuerName = ""
            last4 = ""
            creditLimitText = ""
            paymentSourceWalletID = nil
            notes = ""
            network = .visa
            statementClosingDay = Self.defaultStatementClosingDay
            paymentDueDay = Self.defaultPaymentDueDay
        }
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

private struct CategoryDraft {
    var name: String
    var kind: TransactionCategoryKind
    var hierarchyRole: TransactionCategoryHierarchyRole
    var parentCategoryID: UUID?
    var isFavorite: Bool
    var iconSymbolName: String
    var iconColorHex: String
    var iconWasCustomized: Bool

    init(
        category: TransactionCategory?,
        defaultKind: TransactionCategoryKind,
        preferredParentCategoryID: UUID?
    ) {
        if let category {
            let matchesDefaultIcon = category.kind.matchesDefaultIconAppearance(
                symbolName: category.iconSymbolName,
                colorHex: category.iconColorHex
            )

            self.name = category.localizedDisplayName
            self.kind = category.kind
            self.hierarchyRole = category.hierarchyRole
            self.parentCategoryID = category.parentCategory?.id
            self.isFavorite = category.isFavorite
            self.iconSymbolName = category.iconSymbolName
            self.iconColorHex = category.kind.migratedLegacyDefaultColorHex(
                for: category.iconColorHex,
                symbolName: category.iconSymbolName
            ) ?? MistiaIconColorPalette.normalizedHex(category.iconColorHex)
            self.iconWasCustomized = !matchesDefaultIcon
        } else {
            self.name = ""
            self.kind = defaultKind
            self.hierarchyRole = preferredParentCategoryID == nil ? .parent : .child
            self.parentCategoryID = preferredParentCategoryID
            self.isFavorite = false
            self.iconSymbolName = defaultKind.defaultIconSymbolName
            self.iconColorHex = defaultKind.defaultColorHex
            self.iconWasCustomized = false
        }
    }

    mutating func handleKindChange(from oldValue: TransactionCategoryKind, to newValue: TransactionCategoryKind) {
        guard oldValue != newValue else { return }

        if !iconWasCustomized {
            iconSymbolName = newValue.defaultIconSymbolName
            iconColorHex = newValue.defaultColorHex
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


struct ManagementBalanceAdjustmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Query private var storedCategories: [TransactionCategory]
    @Query private var storedWallets: [LedgerWallet]

    let wallet: LedgerWallet
    let currentBalance: Int64
    let creditLimit: Int64?

    @State private var newBalanceText: String = ""
    @State private var reason: String = ""
    @State private var showsConfirmation = false

    init(wallet: LedgerWallet, currentBalance: Int64, creditLimit: Int64? = nil) {
        self.wallet = wallet
        self.currentBalance = currentBalance
        self.creditLimit = creditLimit
        _newBalanceText = State(initialValue: "\(currentBalance)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(wallet.kind == .creditCard ? L10n.management.balanceEditor.availableCreditTitle : L10n.management.balanceEditor.actualBalanceTitle) {
                    TextField(wallet.kind == .creditCard ? L10n.management.balanceEditor.availableCreditPlaceholder : L10n.management.balanceEditor.currentBalancePlaceholder, text: $newBalanceText)
                        .keyboardType(.numberPad)
                }

                Section(L10n.management.management.adjustmentReason) {
                    TextField(L10n.management.management.eGAuditError, text: $reason, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(L10n.management.management.balanceAdjustment2)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.common.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.common.save) {
                        showsConfirmation = true
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(L10n.management.management.notice, isPresented: $showsConfirmation) {
                Button(L10n.common.cancel, role: .cancel) { }
                Button(L10n.management.management.agree) {
                    save()
                }
            } message: {
                Text(L10n.management.management.thisAdjustmentCannotBeUndoneAreYou)
            }
        }
    }

    private func save() {
        let newBalance = newBalanceText.currencyInputToMinorUnits(currencyCode: wallet.currencyCode)
        
        // For credit cards, convert available credit to debt
        let targetBalance: Int64
        if wallet.kind == .creditCard, let limit = creditLimit {
            targetBalance = max(limit - newBalance, 0)
        } else {
            targetBalance = newBalance
        }
        
        let diff = targetBalance - currentBalance
        guard diff != 0 else {
            dismiss()
            return
        }

        let isIncome = wallet.kind == .creditCard ? diff < 0 : diff > 0
        let absDiff = abs(diff)

        let categoryID = isIncome ? MistiaSystemCategoryIdentity.balanceAdjustmentIncomeID : MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID
        let category = storedCategories.first(where: { $0.id == categoryID })

        let transaction = LedgerTransaction(
            primaryKind: isIncome ? .income : .expense,
            title: L10n.management.management.balanceAdjustment,
            note: reason,
            amountMinor: absDiff,
            occurredAt: .now,
            sourceWallet: wallet,
            category: category
        )

        modelContext.insert(transaction)

        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: transaction.id,
                modifiedAt: transaction.updatedAt
            )
            dismiss()
        } catch {
            // Error handling could be improved
        }
    }
}
