import SwiftData
import SwiftUI

struct TransactionTransferPreset: Equatable {
    let transferSubtype: TransactionTransferSubtype
    let sourceWalletID: UUID?
    let destinationWalletID: UUID?

    init(
        transferSubtype: TransactionTransferSubtype = .internalTransfer,
        sourceWalletID: UUID? = nil,
        destinationWalletID: UUID? = nil
    ) {
        self.transferSubtype = transferSubtype
        self.sourceWalletID = sourceWalletID
        self.destinationWalletID = destinationWalletID
    }
}

struct TransactionEditorTarget: Identifiable {
    let id = UUID()
    let transaction: LedgerTransaction?
    let initialKind: TransactionPrimaryKind
    let quickCapture: Bool
    let transferPreset: TransactionTransferPreset?
    let subjectUserIDOverride: UUID?

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        self.initialKind = transaction.primaryKind
        self.quickCapture = false
        self.transferPreset = nil
        self.subjectUserIDOverride = nil
    }

    init(
        initialKind: TransactionPrimaryKind,
        quickCapture: Bool = false,
        transferPreset: TransactionTransferPreset? = nil,
        subjectUserIDOverride: UUID? = nil
    ) {
        self.transaction = nil
        self.initialKind = initialKind
        self.quickCapture = quickCapture
        self.transferPreset = transferPreset
        self.subjectUserIDOverride = subjectUserIDOverride
    }
}

enum TransactionEditorCompletion: Equatable {
    case savedDraft
    case savedTransaction
}

private enum TransactionEditorFocusedField: Hashable {
    case title
}

struct TransactionEditorSheet: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore

    @Query
    private var storedWallets: [LedgerWallet]
    @Query
    private var storedCategories: [TransactionCategory]
    @Query
    private var ownershipScopes: [OwnedRecordScope]
    @Query
    private var transactionAuditRecords: [TransactionAuditRecord]
    @Query(filter: #Predicate<LedgerTransaction> {
        $0.entryStatusRawValue == "posted" && !$0.isArchived && $0.deletedAt == nil
    })
    private var postedTransactions: [LedgerTransaction]
    @Query(filter: #Predicate<DueOccurrenceRecord> { $0.deletedAt == nil })
    private var storedDueOccurrences: [DueOccurrenceRecord]

    let target: TransactionEditorTarget
    var onComplete: (TransactionEditorCompletion) -> Void = { _ in }

    @State private var draft: TransactionFormDraft
    @State private var alertMessage: String?
    private var isAdjustment: Bool {
        if let transaction = target.transaction {
            return transaction.category?.id == MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID ||
                   transaction.category?.id == MistiaSystemCategoryIdentity.balanceAdjustmentIncomeID
        }
        return false
    }
    @State private var showsCategoryPicker = false
    @State private var cachedTitleSuggestions: [TransactionTitleSuggestion] = []
    @State private var titleSuggestionRefreshTask: Task<Void, Never>?
    @State private var suppressTitleSuggestions = false
    @State private var isApplyingTitleSuggestion = false
    @State private var isSaving = false
    @FocusState private var focusedField: TransactionEditorFocusedField?

    init(
        target: TransactionEditorTarget,
        onComplete: @escaping (TransactionEditorCompletion) -> Void = { _ in }
    ) {
        self.target = target
        self.onComplete = onComplete
        _draft = State(initialValue: TransactionFormDraft(target: target))
    }

    private var isLockedByStatement: Bool {
        guard let transaction = target.transaction else { return false }
        if isLinkedToPaidCreditCardStatement(transaction) {
            return true
        }

        if transaction.primaryKind == .expense,
           let sourceWallet = transaction.sourceWallet,
           sourceWallet.kind == .creditCard {
            if paidCreditCardStatement(for: sourceWallet, occurredAt: transaction.occurredAt) != nil {
                return true
            }

            if hasCreditCardStatementOccurrences(for: sourceWallet.id) {
                return false
            }
        }

        return TransactionLogic.isLockedByPaidStatement(
            transaction: transaction.snapshot,
            allTransactions: postedTransactions.map { $0.snapshot }
        )
    }

    var body: some View {
        let isLockedByStatement = self.isLockedByStatement

        NavigationStack {
            Form {
                if isLockedByStatement {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                                .padding(8)
                                .background(.orange.opacity(0.1))
                                .clipShape(Circle())

                            Text(mistiaLocalized(
                                vi: "Giao dịch này thuộc sao kê đã thanh toán nên không thể sửa đổi hoặc lưu trữ.",
                                en: "This transaction is part of a paid statement and cannot be modified or archived.",
                                ja: "この取引は支払い済みの明細に含まれているため、変更やアーカイブはできません。"
                            ))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }

                if target.quickCapture && target.transaction == nil {
                    quickCaptureContent
                } else {
                    fullEditorContent
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isLockedByStatement || isSaving)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !isAdjustment && !isLockedByStatement {
                        Button {
                            save()
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
        }
        .alert(
            mistiaLocalized(vi: "Chưa thể lưu", en: "Can't save yet", ja: "まだ保存できません"),
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(mistiaLocalized(vi: "OK", en: "OK", ja: "OK"), role: .cancel) { }
        } message: {
            Text(mistiaCatalog(alertMessage ?? ""))
        }
        .sheet(isPresented: $showsCategoryPicker) {
            MistiaCategoryPickerSheet(
                title: mistiaLocalized(vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択"),
                selectedCategoryID: draft.categoryID,
                sections: categorySections,
                recentCategories: recentCategories,
                favoriteCategories: favoriteCategories,
                allowsParentSelectionInAll: false,
                allModeSubtitle: { category in
                    category.parentCategory?.localizedDisplayName
                },
                quickModeSubtitle: { category in
                    category.parentCategory?.localizedDisplayName
                }
            ) { category in
                draft.categoryID = category.id
            }
        }
        .onChange(of: draft.sourceWalletID) { _, _ in
            clearMismatchedCategoryForSelectedWallet()
        }
        .onChange(of: draft.primaryKind) { _, _ in
            scheduleTitleSuggestionsRefresh()
            clearMismatchedCategoryForSelectedWallet()
        }
        .onChange(of: draft.transferSubtype) { _, _ in
            scheduleTitleSuggestionsRefresh()
        }
        .onChange(of: familyContextStore.selectedSubjectUserID) { _, _ in
            clearMismatchedWalletsForCurrentSubject()
            clearMismatchedCategoryForSelectedWallet()
        }
        .onAppear {
            scheduleTitleSuggestionsRefresh()
        }
        .onDisappear {
            titleSuggestionRefreshTask?.cancel()
            titleSuggestionRefreshTask = nil
        }
    }
    private func archiveTransaction() {
        guard let transaction = target.transaction else { return }
        transaction.isArchived = true
        transaction.archivedAt = Date()
        transaction.updatedAt = Date()
        
        do {
            if let actorUserID = sessionStore.activeLocalProfileUserID {
                try TransactionAuditStore.touch(
                    transactionID: transaction.id,
                    actorUserID: actorUserID,
                    fallbackCreatedByUserID: actorUserID,
                    updatedAt: transaction.updatedAt,
                    context: modelContext
                )
            }
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: transaction.id,
                modifiedAt: transaction.updatedAt,
                subjectUserIDOverride: walletOwnerUserID(for: transaction.sourceWallet)
            )
            onComplete(.savedTransaction)
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private var quickCaptureContent: some View {
        @Bindable var bindableDraft = draft

        return Group {
            Section(mistiaLocalized(vi: "Loại giao dịch", en: "Transaction type", ja: "取引タイプ")) {
                Picker(mistiaLocalized(vi: "Loại giao dịch", en: "Transaction type", ja: "取引タイプ"), selection: $bindableDraft.primaryKind) {
                    ForEach(TransactionPrimaryKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額")) {
                TextField(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額"), text: $bindableDraft.amountText)
                    .keyboardType(.numberPad)
            }

            Section {
                Text(mistiaLocalized(
                    vi: "Ghi nhanh chỉ lưu loại giao dịch và số tiền. Hãy hoàn thiện chi tiết ở tab Giao dịch.",
                    en: "Quick capture only saves the transaction type and amount. Complete the rest in the Transactions tab.",
                    ja: "クイック記録では取引タイプと金額だけを保存します。残りの詳細は取引タブで仕上げてください。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
    private var fullEditorContent: some View {
        @Bindable var bindableDraft = draft

        return Group {
            if draft.primaryKind == .transfer {
                Section(mistiaLocalized(vi: "Kiểu chuyển tiền", en: "Transfer type", ja: "振替タイプ")) {
                    Picker(mistiaLocalized(vi: "Kiểu chuyển tiền", en: "Transfer type", ja: "振替タイプ"), selection: Binding(
                        get: { bindableDraft.transferSubtype ?? .internalTransfer },
                        set: { bindableDraft.transferSubtype = $0 }
                    )) {
                        ForEach(TransactionTransferSubtype.allCases, id: \.self) { subtype in
                            Text(subtype.title).tag(subtype)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if draft.primaryKind == .transfer, draft.transferSubtype == .debt {
                Section(mistiaLocalized(vi: "Loại công nợ", en: "Debt type", ja: "貸し借りの種類")) {
                    Picker(mistiaLocalized(vi: "Loại công nợ", en: "Debt type", ja: "貸し借りの種類"), selection: Binding(
                        get: { bindableDraft.debtIntent ?? .lend },
                        set: { bindableDraft.debtIntent = $0 }
                    )) {
                        ForEach(TransactionDebtIntent.allCases, id: \.self) { intent in
                            Text(intent.title).tag(intent)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if shouldShowMissingWalletsState {
                Section {
                    Text(mistiaLocalized(
                        vi: "Bạn cần thêm ít nhất một ví trong tab Quản lý trước khi ghi nhận giao dịch hoàn chỉnh.",
                        en: "You need to add at least one wallet in the Manage tab before saving a full transaction.",
                        ja: "取引を完全に記録する前に、管理タブで少なくとも 1 つのウォレットを追加してください。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section(mistiaLocalized(vi: "Thông tin chính", en: "Main details", ja: "基本情報")) {
                if let titleFieldPlaceholder {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(titleFieldPlaceholder, text: $bindableDraft.title)
                            .focused($focusedField, equals: .title)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .onChange(of: focusedField) { _, newValue in
                                if newValue == .title {
                                    suppressTitleSuggestions = false
                                }
                                scheduleTitleSuggestionsRefresh()
                            }
                            .onChange(of: bindableDraft.title) { _, _ in
                                if isApplyingTitleSuggestion {
                                    isApplyingTitleSuggestion = false
                                    cachedTitleSuggestions = []
                                } else {
                                    suppressTitleSuggestions = false
                                    scheduleTitleSuggestionsRefresh()
                                }
                            }

                        if shouldShowTitleSuggestions {
                            titleSuggestionsPanel
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: shouldShowTitleSuggestions)
                }

                TextField(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額"), text: $bindableDraft.amountText)
                    .keyboardType(.numberPad)

                DatePicker(mistiaLocalized(vi: "Thời gian", en: "Date & time", ja: "日時"), selection: $bindableDraft.occurredAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }

            switch draft.primaryKind {
            case .expense, .income:
                Section(mistiaLocalized(vi: "Nguồn tiền", en: "Funding source", ja: "支払い元")) {
                    Picker(mistiaLocalized(vi: "Ví", en: "Wallet", ja: "ウォレット"), selection: $draft.sourceWalletID) {
                        Text(mistiaLocalized(vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択")).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showsCategoryPicker = true
                    } label: {
                        HStack {
                            Text(mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ"))
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

                }
            case .transfer:
                if draft.transferSubtype == .internalTransfer {
                    Section(mistiaLocalized(vi: "Luồng chuyển", en: "Transfer flow", ja: "振替の流れ")) {
                        Picker(mistiaLocalized(vi: "Từ ví", en: "From wallet", ja: "出金元"), selection: $draft.sourceWalletID) {
                            Text(mistiaLocalized(vi: "Chọn nguồn", en: "Choose source", ja: "出金元を選択")).tag(Optional<UUID>.none)
                            ForEach(availableSourceWalletsForTransfer) { wallet in
                                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(mistiaLocalized(vi: "Đến ví", en: "To wallet", ja: "入金先"), selection: $draft.destinationWalletID) {
                            Text(mistiaLocalized(vi: "Chọn đích", en: "Choose destination", ja: "入金先を選択")).tag(Optional<UUID>.none)
                            ForEach(availableDestinationWalletsForTransfer) { wallet in
                                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else {
                    Section(mistiaLocalized(vi: "Đối tượng", en: "Counterparty", ja: "相手")) {
                        Picker(mistiaLocalized(vi: "Ví thực hiện", en: "Wallet used", ja: "使用ウォレット"), selection: $draft.sourceWalletID) {
                            Text(mistiaLocalized(vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択")).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)

                        TextField(
                            mistiaLocalized(vi: "Tên người liên quan", en: "Counterparty name", ja: "相手の名前"),
                            text: $bindableDraft.counterpartyName
                        )
                    }
                }
            }

            Section(mistiaLocalized(vi: "Ghi chú", en: "Notes", ja: "メモ")) {
                TextField(mistiaLocalized(vi: "Thêm ghi chú nếu cần", en: "Add a note if needed", ja: "必要ならメモを追加"), text: $bindableDraft.note, axis: .vertical)
                    .lineLimit(3...5)
            }

            if let transaction = target.transaction, !transaction.isArchived {
                Section {
                    MistiaArchiveSection(
                        buttonTitle: mistiaLocalized(vi: "Lưu trữ giao dịch", en: "Archive transaction", ja: "取引をアーカイブ"),
                        descriptionText: mistiaLocalized(vi: "Giao dịch lưu trữ sẽ không còn hiện trong danh sách. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived transactions will no longer appear in the list. They will be automatically deleted permanently after 30 days.", ja: "アーカイブした取引はリストに表示されなくなります。これらは30日後に自動的に永久削除されます。"),
                        popupMessage: mistiaLocalized(vi: "Giao dịch này sẽ bị lưu trữ. Các giao dịch đã lưu trữ sẽ nằm trong \"Mục đã lưu trữ\" và được giữ lại trong 30 ngày.", en: "This transaction will be archived. Archived transactions will remain in \"Archived items\" for 30 days.", ja: "この取引はアーカイブされます。アーカイブされた取引は「アーカイブ済みアイテム」に30日間保持されます。")
                    ) {
                        archiveTransaction()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                .disabled(isAdjustment)
                .opacity(isAdjustment ? 0.6 : 1.0)
            }
        }
        .disabled(isAdjustment)
    }
    private var navigationTitle: String {
        if target.transaction == nil {
            return target.quickCapture
                ? mistiaLocalized(vi: "Ghi nhanh", en: "Quick capture", ja: "クイック記録")
                : target.initialKind.title
        }

        return mistiaLocalized(vi: "Sửa giao dịch", en: "Edit transaction", ja: "取引を編集")
    }

    private var headerTitle: String {
        if target.quickCapture && target.transaction == nil {
            return mistiaLocalized(vi: "Lưu nhanh rồi hoàn thiện sau", en: "Save fast, finish later", ja: "すばやく保存して後で仕上げる")
        }

        if let transaction = target.transaction, transaction.entryStatus == .draft {
            return mistiaLocalized(vi: "Hoàn thiện bản nháp", en: "Complete the draft", ja: "下書きを完成させる")
        }

        return mistiaLocalized(vi: "Giao dịch local-first", en: "Local-first transaction", ja: "ローカルファーストの取引")
    }

    private var headerSubtitle: String {
        if target.quickCapture && target.transaction == nil {
            return mistiaLocalized(
                vi: "Chỉ cần số tiền và loại giao dịch. Phần còn lại sẽ xuất hiện trong lịch sử để bạn bổ sung sau.",
                en: "Just enter the amount and transaction type. The rest will appear in history for you to complete later.",
                ja: "金額と取引タイプだけ入力してください。残りの内容は履歴に表示され、あとで追記できます。"
            )
        }

        return mistiaLocalized(
            vi: "Dữ liệu sẽ được lưu ngay trên thiết bị và phản ánh trực tiếp vào tab Giao dịch.",
            en: "Data is saved directly on this device and reflected immediately in the Transactions tab.",
            ja: "データはこの端末にすぐ保存され、取引タブへ即時反映されます。"
        )
    }

    private var accentColor: Color {
        Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private var availableWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([
            target.transaction?.sourceWallet?.id,
            target.transaction?.destinationWallet?.id
        ].compactMap { $0 })
        let allowedOwnerUserIDs = target.transaction == nil
            ? newTransactionWalletOwnerUserIDs
            : nil
        return storedWallets
            .filter { wallet in
                guard let ownerUserID = walletOwnerUserID(for: wallet) else {
                    return preferredWalletIDs.contains(wallet.id)
                }
                if let allowedOwnerUserIDs, !allowedOwnerUserIDs.contains(ownerUserID) {
                    return preferredWalletIDs.contains(wallet.id)
                }
                if ownerUserID == sessionStore.activeLocalProfileUserID {
                    return true
                }
                return familyContextStore.canUseWallet(walletID: wallet.id, ownerUserID: ownerUserID)
                    || preferredWalletIDs.contains(wallet.id)
            }
            .filter { ($0.deletedAt == nil && !$0.isArchived) || preferredWalletIDs.contains($0.id) }
            .filter { wallet in
                // Credit cards cannot be used for income transactions
                if draft.primaryKind == .income && wallet.kind == .creditCard {
                    return preferredWalletIDs.contains(wallet.id)
                }
                return true
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var availableWalletsForIncome: [LedgerWallet] {
        availableWallets.filter { $0.kind != .creditCard }
    }
    
    private var availableSourceWalletsForTransfer: [LedgerWallet] {
        // Credit cards cannot be source wallet for transfers (cannot send money)
        availableWallets.filter { $0.kind != .creditCard }
    }
    
    private var availableDestinationWalletsForTransfer: [LedgerWallet] {
        // All wallets can receive transfers (including credit cards for payment)
        availableWallets
    }

    private var availableCategories: [TransactionCategory] {
        let preferredID = target.transaction?.category?.id
        let ownerUserIDs = categoryPickerOwnerUserIDs
        let categoryOwnerMap = self.categoryOwnerMap
        let currentSelfUserID = self.currentSelfUserID

        return storedCategories
            .filter { category in
                guard let ownerUserID = categoryOwnerMap[category.id] ?? currentSelfUserID,
                      ownerUserIDs.contains(ownerUserID) else {
                    return false
                }
                return category.kind == selectedCategoryKind
                    && category.isChildCategory
                    && !category.isBalanceAdjustmentSystemCategory
                    && ((category.deletedAt == nil && !category.isArchived) || category.id == preferredID)
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var visiblePostedTransactions: [LedgerTransaction] {
        FamilyScopedData.visibleTransactionsForHistory(
            postedTransactions,
            audits: transactionAuditRecords,
            scopes: ownershipScopes,
            familyContextStore: familyContextStore,
            sessionStore: sessionStore
        )
    }

    private var titleFieldPlaceholder: String? {
        if draft.primaryKind != .transfer {
            return draft.primaryKind == .expense
                ? mistiaLocalized(vi: "Tên khoản chi", en: "Expense name", ja: "支出名")
                : mistiaLocalized(vi: "Tên khoản thu", en: "Income name", ja: "収入名")
        }

        if draft.transferSubtype == .debt {
            return mistiaLocalized(
                vi: "Tên giao dịch (không bắt buộc)",
                en: "Transaction name (optional)",
                ja: "取引名（任意）"
            )
        }

        return nil
    }

    private var titleSuggestions: [TransactionTitleSuggestion] {
        cachedTitleSuggestions
    }

    private var shouldShowTitleSuggestions: Bool {
        focusedField == .title && !suppressTitleSuggestions && !cachedTitleSuggestions.isEmpty
    }

    private func scheduleTitleSuggestionsRefresh() {
        titleSuggestionRefreshTask?.cancel()
        titleSuggestionRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            refreshTitleSuggestionsNow()
        }
    }

    private func refreshTitleSuggestionsNow() {
        guard titleFieldPlaceholder != nil,
              focusedField == .title,
              !suppressTitleSuggestions else {
            cachedTitleSuggestions = []
            return
        }

        cachedTitleSuggestions = TransactionLogic.titleSuggestions(
            from: visiblePostedTransactions.map(\.snapshot),
            query: draft.title,
            primaryKind: draft.primaryKind,
            transferSubtype: draft.primaryKind == .transfer ? draft.transferSubtype : nil,
            excludingTransactionID: target.transaction?.id,
            limit: 5
        )
    }

    private var categorySections: [TransactionCategoryGroupSection] {
        let preferredID = target.transaction?.category?.id
        let ownerUserIDs = categoryPickerOwnerUserIDs
        let categoryOwnerMap = self.categoryOwnerMap
        let currentSelfUserID = self.currentSelfUserID
        let relevantCategories = storedCategories.filter { category in
            guard let ownerUserID = categoryOwnerMap[category.id] ?? currentSelfUserID,
                  ownerUserIDs.contains(ownerUserID) else {
                return false
            }
            return !category.isBalanceAdjustmentSystemCategory
                && category.kind == selectedCategoryKind
                && category.deletedAt == nil
                && (!category.isArchived || category.id == preferredID || category.parentCategory?.id == target.transaction?.category?.parentCategory?.id)
        }

        return MistiaCategoryHierarchy.groupedSections(
            from: relevantCategories,
            kind: selectedCategoryKind,
            includeArchived: true,
            includeEmptyParents: false
        )
    }

    private var favoriteCategories: [TransactionCategory] {
        let ownerUserIDs = categoryPickerOwnerUserIDs
        let categoryOwnerMap = self.categoryOwnerMap
        let currentSelfUserID = self.currentSelfUserID
        return MistiaCategoryPickerSupport.favoriteCategories(
            from: storedCategories.filter { category in
                guard let ownerUserID = categoryOwnerMap[category.id] ?? currentSelfUserID else {
                    return false
                }
                return !category.isBalanceAdjustmentSystemCategory
                    && ownerUserIDs.contains(ownerUserID)
            },
            kind: selectedCategoryKind
        )
    }

    private var recentCategories: [TransactionCategory] {
        let ownerUserIDs = recentCategoryOwnerUserIDs
        let categoryOwnerMap = self.categoryOwnerMap
        let transactionOwnerMap = self.transactionOwnerMap
        let walletOwnerMap = self.walletOwnerMap
        let currentSelfUserID = self.currentSelfUserID

        func ownerUserIDForWallet(_ wallet: LedgerWallet?) -> UUID? {
            guard let wallet else { return nil }
            return walletOwnerMap[wallet.id] ?? currentSelfUserID
        }

        return MistiaCategoryPickerSupport.recentCategories(
            from: postedTransactions.filter { transaction in
                let ownerUserID = transactionOwnerMap[transaction.id]
                    ?? ownerUserIDForWallet(transaction.sourceWallet)
                    ?? ownerUserIDForWallet(transaction.destinationWallet)
                    ?? currentSelfUserID
                guard let ownerUserID else { return false }
                return ownerUserIDs.contains(ownerUserID)
            },
            categories: storedCategories.filter { category in
                guard let ownerUserID = categoryOwnerMap[category.id] ?? currentSelfUserID else {
                    return false
                }
                return !category.isBalanceAdjustmentSystemCategory
                    && ownerUserIDs.contains(ownerUserID)
            },
            kind: selectedCategoryKind
        )
    }

    private var selectedCategoryKind: TransactionCategoryKind {
        draft.primaryKind == .income ? .income : .expense
    }

    private var selectedSourceWallet: LedgerWallet? {
        storedWallets.first(where: { $0.id == draft.sourceWalletID })
    }

    private var selectedDestinationWallet: LedgerWallet? {
        storedWallets.first(where: { $0.id == draft.destinationWalletID })
    }

    private var selectedCategory: TransactionCategory? {
        availableCategories.first(where: { $0.id == draft.categoryID })
    }

    private var selectedCategoryLabel: String {
        guard let selectedCategory else {
            return mistiaLocalized(vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択")
        }

        let parentName = selectedCategory.parentCategory?.localizedDisplayName ?? selectedCategory.branchDisplayName
        return "\(parentName) / \(selectedCategory.localizedDisplayName)"
    }

    private var shouldShowMissingWalletsState: Bool {
        !target.quickCapture && availableWallets.isEmpty
    }

    private var saveButtonTitle: String {
        if target.quickCapture && target.transaction == nil {
            return mistiaLocalized(vi: "Lưu nháp", en: "Save draft", ja: "下書きを保存")
        }

        return mistiaLocalized(vi: "Lưu", en: "Save", ja: "保存")
    }

    private func save() {
        guard !isSaving else { return }
        if target.quickCapture && target.transaction == nil {
            saveQuickCapture()
        } else {
            saveFullTransaction()
        }
    }

    private func saveQuickCapture() {
        guard let amountMinor = draft.amountMinor, amountMinor > 0 else {
            alertMessage = mistiaLocalized(vi: "Nhập số tiền lớn hơn 0 để lưu ghi nhanh.", en: "Enter an amount greater than 0 to save the quick capture.", ja: "クイック記録を保存するには 0 より大きい金額を入力してください。")
            return
        }

        let transaction = target.transaction ?? LedgerTransaction(
            primaryKind: draft.primaryKind,
            entryStatus: .draft,
            amountMinor: amountMinor,
            occurredAt: draft.occurredAt
        )
        let now = Date()

        transaction.primaryKind = draft.primaryKind
        transaction.transferSubtype = nil
        transaction.debtIntent = nil
        transaction.entryStatus = .draft
        transaction.title = ""
        transaction.note = nil
        transaction.amountMinor = amountMinor
        transaction.occurredAt = draft.occurredAt
        transaction.updatedAt = now
        transaction.sourceWallet = nil
        transaction.destinationWallet = nil
        transaction.category = nil
        transaction.counterpartyName = nil
        transaction.normalizedCounterpartyKey = nil

        if target.transaction == nil {
            modelContext.insert(transaction)
        }

        persist(transaction: transaction, completion: .savedDraft)
    }

    private func saveFullTransaction() {
        guard let amountMinor = draft.amountMinor, amountMinor > 0 else {
            alertMessage = mistiaLocalized(vi: "Nhập số tiền lớn hơn 0.", en: "Enter an amount greater than 0.", ja: "0 より大きい金額を入力してください。")
            return
        }

        if draft.primaryKind != .transfer, draft.title.nilIfBlank == nil {
            alertMessage = mistiaLocalized(vi: "Nhập tên giao dịch để lưu.", en: "Enter a transaction name before saving.", ja: "保存する前に取引名を入力してください。")
            return
        }

        guard !availableWallets.isEmpty else {
            alertMessage = mistiaLocalized(vi: "Bạn chưa có ví nào để gắn vào giao dịch.", en: "You don't have any wallets available for this transaction.", ja: "この取引に使えるウォレットがまだありません。")
            return
        }

        // Credit cards cannot receive income transactions
        if draft.primaryKind == .income,
           let sourceWallet = selectedSourceWallet,
           sourceWallet.kind == .creditCard {
            alertMessage = mistiaLocalized(vi: "Thẻ tín dụng không thể ghi nhận thu nhập. Hãy chọn ví tiền mặt, ngân hàng hoặc ví điện tử.", en: "Credit cards cannot receive income. Please select a cash, bank, or e-wallet instead.", ja: "クレジットカードは収入を記録できません。現金、銀行、または電子マネーを選択してください。")
            return
        }
        
        // Credit cards cannot be source wallet for transfers
        if draft.primaryKind == .transfer,
           draft.transferSubtype == .internalTransfer,
           let sourceWallet = selectedSourceWallet,
           sourceWallet.kind == .creditCard {
            alertMessage = mistiaLocalized(vi: "Thẻ tín dụng không thể chuyển tiền đi. Chỉ có thể nhận tiền để trả nợ.", en: "Credit cards cannot send money via transfer. They can only receive payments for debt repayment.", ja: "クレジットカードは振替で送金できません。返済の受け取りのみ可能です。")
            return
        }

        switch draft.primaryKind {
        case .expense:
            guard let sourceWallet = selectedSourceWallet else {
                alertMessage = mistiaLocalized(vi: "Chọn ví cho giao dịch này.", en: "Choose a wallet for this transaction.", ja: "この取引のウォレットを選択してください。")
                return
            }

            let snapshot = TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            )

            let snapshots = postedTransactions.filter { $0.id != target.transaction?.id }.map { $0.snapshot }
            let currentBalance = TransactionLogic.effectiveBalance(for: snapshot, records: snapshots)

            // For credit cards, check available credit (limit - debt), not debt itself
            if sourceWallet.kind == .creditCard {
                if let paidStatement = paidCreditCardStatement(for: sourceWallet, occurredAt: draft.occurredAt) {
                    alertMessage = paidStatementExpenseAlertMessage(for: paidStatement)
                    return
                }

                let availableCredit: Int64
                if let profile = sourceWallet.creditCardProfile {
                    availableCredit = max(profile.creditLimitMinor - currentBalance, 0)
                } else {
                    availableCredit = 0
                }
                if amountMinor > availableCredit {
                    alertMessage = mistiaLocalized(vi: "Số tiền vượt quá hạn mức khả dụng của thẻ.", en: "The amount exceeds the available credit on the card.", ja: "金額がカードの利用可能額を超えています。")
                    return
                }
            } else if currentBalance - amountMinor < 0 {
                alertMessage = mistiaLocalized(vi: "Số dư ví không đủ để thực hiện giao dịch.", en: "Insufficient wallet balance to perform the transaction.", ja: "取引を実行するためのウォレット残高が不足しています。")
                return
            }

        case .transfer:
            switch draft.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                guard let sourceWallet = selectedSourceWallet else {
                    alertMessage = mistiaLocalized(vi: "Chọn ví nguồn.", en: "Choose the source wallet.", ja: "出金元ウォレットを選択してください。")
                    return
                }
                
                let snapshot = TransactionWalletSnapshot(
                    id: sourceWallet.id,
                    kind: sourceWallet.kind,
                    openingBalanceMinor: sourceWallet.openingBalanceMinor
                )
                
                let snapshots = postedTransactions.filter { $0.id != target.transaction?.id }.map { $0.snapshot }
                let currentBalance = TransactionLogic.effectiveBalance(for: snapshot, records: snapshots)
                
                if currentBalance - amountMinor < 0 {
                    alertMessage = mistiaLocalized(vi: "Số dư ví không đủ để thực hiện giao dịch.", en: "Insufficient wallet balance to perform the transaction.", ja: "取引を実行するためのウォレット残高が不足しています。")
                    return
                }

            case .debt:
                if draft.debtIntent == .lend || draft.debtIntent == .repay {
                    guard let sourceWallet = selectedSourceWallet else {
                        alertMessage = mistiaLocalized(vi: "Chọn ví thực hiện giao dịch công nợ.", en: "Choose the wallet used for this debt transaction.", ja: "この貸し借り取引で使うウォレットを選択してください。")
                        return
                    }

                    let snapshot = TransactionWalletSnapshot(
                        id: sourceWallet.id,
                        kind: sourceWallet.kind,
                        openingBalanceMinor: sourceWallet.openingBalanceMinor
                    )
                    
                    let snapshots = postedTransactions.filter { $0.id != target.transaction?.id }.map { $0.snapshot }
                    let currentBalance = TransactionLogic.effectiveBalance(for: snapshot, records: snapshots)
                    
                    if currentBalance - amountMinor < 0 {
                        alertMessage = mistiaLocalized(vi: "Số dư ví không đủ để thực hiện giao dịch.", en: "Insufficient wallet balance to perform the transaction.", ja: "取引を実行するためのウォレット残高が不足しています。")
                        return
                    }
                }
            }
        default:
            break
        }

        let transaction = target.transaction ?? LedgerTransaction(
            primaryKind: draft.primaryKind,
            amountMinor: amountMinor,
            occurredAt: draft.occurredAt
        )
        let now = Date()

        transaction.primaryKind = draft.primaryKind
        transaction.entryStatus = .posted
        transaction.amountMinor = amountMinor
        transaction.occurredAt = draft.occurredAt
        transaction.note = draft.note.nilIfBlank
        transaction.updatedAt = now

        switch draft.primaryKind {
        case .expense, .income:
            guard let sourceWallet = selectedSourceWallet else {
                alertMessage = mistiaLocalized(vi: "Chọn ví cho giao dịch này.", en: "Choose a wallet for this transaction.", ja: "この取引のウォレットを選択してください。")
                return
            }

            guard let category = selectedCategory else {
                alertMessage = mistiaLocalized(vi: "Chọn danh mục cho giao dịch này.", en: "Choose a category for this transaction.", ja: "この取引のカテゴリを選択してください。")
                return
            }

            guard category.isChildCategory else {
                alertMessage = mistiaLocalized(
                    vi: "Chi tiêu và thu nhập phải dùng danh mục con.",
                    en: "Expenses and income must use a child category.",
                    ja: "支出と収入は子カテゴリを使う必要があります。"
                )
                return
            }

            let walletOwnerUserID = walletOwnerUserID(for: sourceWallet)
            guard categoryOwnerUserID(for: category) == walletOwnerUserID else {
                alertMessage = mistiaLocalized(
                    vi: "Ví gia đình phải dùng danh mục đã có trên cloud của chủ ví.",
                    en: "Family wallets must use a category from the wallet owner's cloud catalog.",
                    ja: "家族ウォレットでは、ウォレット所有者のクラウドカテゴリを使う必要があります。"
                )
                return
            }

            transaction.title = draft.title.nilIfBlank ?? ""
            transaction.sourceWallet = sourceWallet
            transaction.destinationWallet = nil
            transaction.category = category
            transaction.transferSubtype = nil
            transaction.debtIntent = nil
            transaction.counterpartyName = nil
            transaction.normalizedCounterpartyKey = nil
        case .transfer:
            switch draft.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                guard let sourceWallet = selectedSourceWallet else {
                    alertMessage = mistiaLocalized(vi: "Chọn ví nguồn.", en: "Choose the source wallet.", ja: "出金元ウォレットを選択してください。")
                    return
                }

                guard let destinationWallet = selectedDestinationWallet else {
                    alertMessage = mistiaLocalized(vi: "Chọn ví đích.", en: "Choose the destination wallet.", ja: "入金先ウォレットを選択してください。")
                    return
                }

                guard sourceWallet.id != destinationWallet.id else {
                    alertMessage = mistiaLocalized(vi: "Ví nguồn và đích phải khác nhau.", en: "Source and destination wallets must be different.", ja: "出金元と入金先のウォレットは別である必要があります。")
                    return
                }

                transaction.title = draft.title.nilIfBlank ?? mistiaLocalized(vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替")
                transaction.sourceWallet = sourceWallet
                transaction.destinationWallet = destinationWallet
                transaction.category = nil
                transaction.transferSubtype = .internalTransfer
                transaction.debtIntent = nil
                transaction.counterpartyName = nil
                transaction.normalizedCounterpartyKey = nil
            case .debt:
                guard let sourceWallet = selectedSourceWallet else {
                    alertMessage = mistiaLocalized(vi: "Chọn ví thực hiện giao dịch công nợ.", en: "Choose the wallet used for this debt transaction.", ja: "この貸し借り取引で使うウォレットを選択してください。")
                    return
                }

                guard let debtIntent = draft.debtIntent else {
                    alertMessage = mistiaLocalized(vi: "Chọn loại công nợ.", en: "Choose a debt type.", ja: "貸し借りの種類を選択してください。")
                    return
                }

                guard let counterpartyName = draft.counterpartyName.nilIfBlank,
                      let normalizedCounterpartyKey = TransactionLogic.normalizeCounterpartyName(counterpartyName)
                else {
                    alertMessage = mistiaLocalized(vi: "Nhập tên người liên quan.", en: "Enter the counterparty name.", ja: "相手の名前を入力してください。")
                    return
                }

                transaction.title = draft.title.nilIfBlank ?? debtIntent.title
                transaction.sourceWallet = sourceWallet
                transaction.destinationWallet = nil
                transaction.category = nil
                transaction.transferSubtype = .debt
                transaction.debtIntent = debtIntent
                transaction.counterpartyName = counterpartyName
                transaction.normalizedCounterpartyKey = normalizedCounterpartyKey
            }
        }

        if target.transaction == nil {
            modelContext.insert(transaction)
        }

        let canonicalOwnerUserID = walletOwnerUserID(for: transaction.sourceWallet)
        persist(
            transaction: transaction,
            completion: .savedTransaction,
            subjectUserIDOverride: canonicalOwnerUserID
        )
    }

    private var transactionRecordSnapshots: [TransactionRecordSnapshot] {
        postedTransactions.map(\.planningRecordSnapshot)
    }

    private var dueOccurrenceSnapshots: [PlanningDueOccurrenceSnapshot] {
        storedDueOccurrences.map(\.planningSnapshot)
    }

    private func paidCreditCardStatement(
        for wallet: LedgerWallet,
        occurredAt: Date
    ) -> PlanningCreditCardStatementSnapshot? {
        guard let account = wallet.planningCreditCardSnapshot(records: transactionRecordSnapshots) else {
            return nil
        }

        return PlanningLogic.paidCreditCardStatementForExpense(
            account: account,
            records: transactionRecordSnapshots,
            occurrences: dueOccurrenceSnapshots,
            occurredAt: occurredAt,
            referenceDate: .now,
            calendar: calendar
        )
    }

    private func isLinkedToPaidCreditCardStatement(_ transaction: LedgerTransaction) -> Bool {
        storedDueOccurrences.contains { occurrence in
            occurrence.sourceKind == .creditCard &&
                occurrence.status == .paid &&
                occurrence.linkedTransactionID == transaction.id
        }
    }

    private func hasCreditCardStatementOccurrences(for walletID: UUID) -> Bool {
        storedDueOccurrences.contains { occurrence in
            occurrence.sourceKind == .creditCard &&
                occurrence.sourceID == walletID
        }
    }

    private func paidStatementExpenseAlertMessage(
        for statement: PlanningCreditCardStatementSnapshot
    ) -> String {
        let statementMonth = MistiaDateFormatting.statementMonthYearString(
            for: statement.statementMonth,
            calendar: calendar
        )
        return mistiaLocalized(
            vi: "Sao kê \(statementMonth) của thẻ này đã thanh toán xong. Không thể thêm chi tiêu mới vào kỳ đã đóng.",
            en: "The \(statementMonth) statement for this card has already been paid. You can't add a new expense to a closed cycle.",
            ja: "このカードの \(statementMonth) 明細は支払い済みです。締め済みの期間に新しい支出は追加できません。"
        )
    }

    private func persist(
        transaction: LedgerTransaction,
        completion: TransactionEditorCompletion,
        subjectUserIDOverride: UUID? = nil
    ) {
        do {
            let actorUserID = sessionStore.activeLocalProfileUserID ?? subjectUserIDOverride
            let now = transaction.updatedAt
            if let actorUserID {
                let createdByUserID = try TransactionAuditStore.fetch(
                    transactionID: transaction.id,
                    context: modelContext
                )?.createdByUserID ?? actorUserID
                try TransactionAuditStore.upsert(
                    transactionID: transaction.id,
                    createdByUserID: createdByUserID,
                    lastModifiedByUserID: actorUserID,
                    updatedAt: now,
                    context: modelContext
                )
            }

            if let subjectUserIDOverride {
                try MistiaRecordOwnershipStore.upsert(
                    entity: .transaction,
                    recordID: transaction.id,
                    ownerUserID: subjectUserIDOverride,
                    updatedAt: now,
                    context: modelContext
                )
            }

            try modelContext.save()
            if let subjectUserIDOverride {
                sessionStore.recordUpsert(
                    entity: .transaction,
                    recordID: transaction.id,
                    modifiedAt: transaction.updatedAt,
                    subjectUserIDOverride: subjectUserIDOverride
                )
                if subjectUserIDOverride != sessionStore.activeLocalProfileUserID {
                    isSaving = true
                    Task { @MainActor in
                        let didSync = await sessionStore.pushQueuedFamilyOwnerChangesNow()
                        isSaving = false
                        guard didSync else {
                            alertMessage = familyCloudPushFailedMessage()
                            return
                        }
                        onComplete(completion)
                        dismiss()
                    }
                    return
                }
            }
            onComplete(completion)
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu giao dịch lúc này.", en: "Couldn't save this transaction right now.", ja: "現在この取引を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func familyCloudPushFailedMessage() -> String {
        let detail = sessionStore.lastErrorMessage?.nilIfBlank
        let base = mistiaLocalized(
            vi: "Giao dịch đã lưu trên máy này nhưng chưa đẩy được lên cloud của chủ ví.",
            en: "The transaction was saved on this device but couldn't be pushed to the wallet owner's cloud yet.",
            ja: "この端末には保存されましたが、ウォレット所有者のクラウドにはまだ送信できませんでした。"
        )
        guard let detail else { return base }
        return "\(base) \(detail)"
    }

    private var effectiveOperableTargetUserIDs: Set<UUID> {
        if target.transaction == nil {
            return newTransactionWalletOwnerUserIDs
        }
        let operable = familyContextStore.operableTargetUserIDs
        if operable.isEmpty, let currentSelfUserID {
            return [currentSelfUserID]
        }
        return operable
    }

    private var newTransactionWalletOwnerUserIDs: Set<UUID> {
        guard let subjectUserID = target.subjectUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? currentSelfUserID else {
            return []
        }
        return [subjectUserID]
    }

    private var effectiveViewableTargetUserIDs: Set<UUID> {
        let viewable = familyContextStore.viewableTargetUserIDs
        if viewable.isEmpty, let currentSelfUserID {
            return [currentSelfUserID]
        }
        return viewable
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var categoryOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
    }

    private var transactionOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
    }

    private var currentSelfUserID: UUID? {
        sessionStore.activeLocalProfileUserID
            ?? familyContextStore.currentUserID
            ?? sessionStore.signedInUserID
    }

    private var effectiveCategoryOwnerUserIDs: Set<UUID> {
        if let selectedSourceWallet,
           let ownerUserID = walletOwnerUserID(for: selectedSourceWallet) {
            return [ownerUserID]
        }
        if let transaction = target.transaction,
           let ownerUserID = transactionOwnerUserID(for: transaction) {
            return [ownerUserID]
        }
        if let subjectUserID = target.subjectUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? currentSelfUserID {
            return [subjectUserID]
        }
        return effectiveOperableTargetUserIDs
    }

    private var categoryPickerOwnerUserIDs: Set<UUID> {
        if let selectedSourceWallet,
           let ownerUserID = walletOwnerUserID(for: selectedSourceWallet) {
            return [ownerUserID]
        }
        return effectiveCategoryOwnerUserIDs
    }

    private var recentCategoryOwnerUserIDs: Set<UUID> {
        if let selectedSourceWallet,
           let ownerUserID = walletOwnerUserID(for: selectedSourceWallet) {
            return [ownerUserID]
        }
        if let transaction = target.transaction,
           let ownerUserID = transactionOwnerUserID(for: transaction) {
            return [ownerUserID]
        }
        if let subjectUserID = target.subjectUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? currentSelfUserID {
            return [subjectUserID]
        }
        return []
    }

    private func walletOwnerUserID(for wallet: LedgerWallet?) -> UUID? {
        guard let wallet else { return nil }
        return walletOwnerMap[wallet.id]
            ?? walletUseGrantOwnerUserID(for: wallet.id)
            ?? currentSelfUserID
    }

    private func walletOwnerUserID(for walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID]
            ?? walletUseGrantOwnerUserID(for: walletID)
            ?? currentSelfUserID
    }

    private func walletUseGrantOwnerUserID(for walletID: UUID) -> UUID? {
        guard let currentSelfUserID else { return nil }
        return familyContextStore.permissionGrants.first {
            $0.revokedAt == nil
                && $0.granteeUserID == currentSelfUserID
                && $0.resourceType == .wallet
                && $0.permissionScope == .use
                && $0.resourceID == walletID
        }?.ownerUserID
    }

    private func categoryOwnerUserID(for category: TransactionCategory) -> UUID? {
        categoryOwnerMap[category.id] ?? currentSelfUserID
    }

    private func transactionOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? walletOwnerUserID(for: transaction.sourceWallet)
            ?? walletOwnerUserID(for: transaction.destinationWallet)
            ?? currentSelfUserID
    }

    private func shouldShowCategory(_ category: TransactionCategory) -> Bool {
        categoryMatchesOwnerScope(category, ownerUserIDs: categoryPickerOwnerUserIDs)
    }

    private func categoryMatchesOwnerScope(
        _ category: TransactionCategory,
        ownerUserIDs: Set<UUID>
    ) -> Bool {
        guard let ownerUserID = categoryOwnerUserID(for: category) else { return false }
        return ownerUserIDs.contains(ownerUserID)
    }

    private func isActiveSystemDefaultCategory(rawSystemKey: String?) -> Bool {
        guard let descriptor = MistiaSystemCategoryIdentity.descriptor(for: rawSystemKey) else {
            return false
        }
        return descriptor.sortOrder != nil && !descriptor.startsArchived
    }

    private func categoriesMatchForOwnerUse(
        selected: TransactionCategory,
        candidate: TransactionCategory
    ) -> Bool {
        if selected.isSystem || candidate.isSystem {
            guard let selectedSystemKey = selected.systemKey,
                  let candidateSystemKey = candidate.systemKey else { return false }
            return selectedSystemKey == candidateSystemKey
                || selected.id == candidate.id
        }

        return selected.kind == candidate.kind
            && selected.hierarchyRole == candidate.hierarchyRole
            && normalizedCategoryName(selected.name) == normalizedCategoryName(candidate.name)
            && normalizedParentMatch(selected.parentCategory, candidate.parentCategory)
    }

    private func normalizedParentMatch(
        _ lhs: TransactionCategory?,
        _ rhs: TransactionCategory?
    ) -> Bool {
        if lhs?.id == rhs?.id {
            return true
        }
        if let lhsSystemKey = lhs?.systemKey,
           let rhsSystemKey = rhs?.systemKey {
            return lhsSystemKey == rhsSystemKey
        }
        return normalizedCategoryName(lhs?.name ?? "") == normalizedCategoryName(rhs?.name ?? "")
    }

    private func normalizedCategoryName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func walletPickerTitle(for wallet: LedgerWallet) -> String {
        guard let ownerName = familyContextStore.displayName(for: walletOwnerUserID(for: wallet)),
              familyContextStore.family != nil else {
            return wallet.name
        }
        return "\(wallet.name) • \(ownerName)"
    }

    private func clearMismatchedCategoryForSelectedWallet() {
        guard let category = storedCategories.first(where: { $0.id == draft.categoryID }),
              !shouldShowCategory(category) else {
            return
        }
        draft.categoryID = nil
    }

    private func clearMismatchedWalletsForCurrentSubject() {
        let availableWalletIDs = Set(availableWallets.map(\.id))
        if let sourceWalletID = draft.sourceWalletID,
           !availableWalletIDs.contains(sourceWalletID) {
            draft.sourceWalletID = nil
            draft.categoryID = nil
        }
        if let destinationWalletID = draft.destinationWalletID,
           !availableWalletIDs.contains(destinationWalletID) {
            draft.destinationWalletID = nil
        }
    }

    private func applyTitleSuggestion(_ suggestion: TransactionTitleSuggestion) {
        isApplyingTitleSuggestion = true
        suppressTitleSuggestions = true
        draft.title = suggestion.title
    }

    private var titleSuggestionsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(titleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    applyTitleSuggestion(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(suggestion.title)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < titleSuggestions.count - 1 {
                    Divider()
                        .padding(.leading, 39)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        Glass.regular
                            .tint(colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.12))
                            .interactive(true),
                        in: .rect(cornerRadius: 18)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.06),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.12) : .black.opacity(0.05),
            radius: 10,
            y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

@Observable final class TransactionFormDraft {
    var primaryKind: TransactionPrimaryKind = .expense
    var transferSubtype: TransactionTransferSubtype? = nil
    var debtIntent: TransactionDebtIntent? = nil
    var title: String = ""
    var amountText: String = ""
    var note: String = ""
    var occurredAt: Date = .now
    var sourceWalletID: UUID? = nil
    var destinationWalletID: UUID? = nil
    var categoryID: UUID? = nil
    var counterpartyName: String = ""

    init(target: TransactionEditorTarget) {
        if let transaction = target.transaction {
            self.primaryKind = transaction.primaryKind
            self.transferSubtype = transaction.transferSubtype
            self.debtIntent = transaction.debtIntent
            self.title = transaction.title
            self.amountText = "\(transaction.amountMinor)"
            self.note = transaction.note ?? ""
            self.occurredAt = transaction.occurredAt
            self.sourceWalletID = transaction.sourceWallet?.id
            self.destinationWalletID = transaction.destinationWallet?.id
            self.categoryID = transaction.category?.id
            self.counterpartyName = transaction.counterpartyName ?? ""
        } else {
            let transferPreset = target.initialKind == .transfer ? target.transferPreset : nil
            self.primaryKind = target.initialKind
            self.transferSubtype = target.initialKind == .transfer
                ? (transferPreset?.transferSubtype ?? .internalTransfer)
                : nil
            self.debtIntent = target.initialKind == .transfer ? .lend : nil
            self.title = ""
            self.amountText = ""
            self.note = ""
            self.occurredAt = .now
            self.sourceWalletID = transferPreset?.sourceWalletID
            self.destinationWalletID = transferPreset?.destinationWalletID
            self.categoryID = nil
            self.counterpartyName = ""
        }
    }

    var amountMinor: Int64? {
        let parsed = amountText.currencyInputToMinorUnits(currencyCode: "JPY")
        return parsed > 0 ? parsed : nil
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
