import SwiftData
import SwiftUI

struct TransactionEditorTarget: Identifiable {
    let id = UUID()
    let transaction: LedgerTransaction?
    let initialKind: TransactionPrimaryKind
    let quickCapture: Bool

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        self.initialKind = transaction.primaryKind
        self.quickCapture = false
    }

    init(initialKind: TransactionPrimaryKind, quickCapture: Bool = false) {
        self.transaction = nil
        self.initialKind = initialKind
        self.quickCapture = quickCapture
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
    @State private var suppressTitleSuggestions = false
    @State private var isApplyingTitleSuggestion = false
    @FocusState private var focusedField: TransactionEditorFocusedField?

    init(
        target: TransactionEditorTarget,
        onComplete: @escaping (TransactionEditorCompletion) -> Void = { _ in }
    ) {
        self.target = target
        self.onComplete = onComplete
        _draft = State(initialValue: TransactionFormDraft(target: target))
    }

    var body: some View {
        NavigationStack {
            Form {
                if target.quickCapture && target.transaction == nil {
                    quickCaptureContent
                } else {
                    fullEditorContent
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(navigationTitle)
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
                    if !isAdjustment {
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

            if shouldShowWalletPermissionRequestState {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mistiaLocalized(
                            vi: "Bạn đang xem ví gia đình nhưng chưa có quyền sử dụng.",
                            en: "You can view this family wallet, but you do not have use access yet.",
                            ja: "この家族ウォレットは表示できますが、まだ使用権限がありません。"
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        Button {
                            requestWalletUsePermission()
                        } label: {
                            Label(
                                mistiaLocalized(vi: "Yêu cầu quyền sử dụng", en: "Request use access", ja: "使用権限をリクエスト"),
                                systemImage: "person.badge.key.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(MistiaAccent.purple.color)
                    }
                    .padding(.vertical, 4)
                }
            } else if shouldShowMissingWalletsState {
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
                            }
                            .onChange(of: bindableDraft.title) { _, _ in
                                if isApplyingTitleSuggestion {
                                    isApplyingTitleSuggestion = false
                                } else {
                                    suppressTitleSuggestions = false
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
        let operableTargetUserIDs = effectiveOperableTargetUserIDs

        return storedWallets
            .filter {
                guard let ownerUserID = walletOwnerUserID(for: $0) else {
                    return preferredWalletIDs.contains($0.id)
                }
                return operableTargetUserIDs.contains(ownerUserID) || preferredWalletIDs.contains($0.id)
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

    private var lockedViewableWallets: [LedgerWallet] {
        let operableTargetUserIDs = effectiveOperableTargetUserIDs
        let viewableTargetUserIDs = effectiveViewableTargetUserIDs

        return storedWallets
            .filter {
                guard let ownerUserID = walletOwnerUserID(for: $0) else {
                    return false
                }
                return viewableTargetUserIDs.contains(ownerUserID)
                    && !operableTargetUserIDs.contains(ownerUserID)
                    && $0.deletedAt == nil
                    && !$0.isArchived
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var availableCategories: [TransactionCategory] {
        let desiredKind: TransactionCategoryKind = draft.primaryKind == .income ? .income : .expense
        let preferredID = target.transaction?.category?.id
        let allowedOwnerUserIDs = effectiveCategoryOwnerUserIDs

        return storedCategories
            .filter {
                guard let ownerUserID = categoryOwnerUserID(for: $0) else {
                    return false
                }
                return ($0.kind == desiredKind)
                    && $0.isChildCategory
                    && !$0.isBalanceAdjustmentSystemCategory
                    && allowedOwnerUserIDs.contains(ownerUserID)
                    && (($0.deletedAt == nil && !$0.isArchived) || $0.id == preferredID)
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
        guard titleFieldPlaceholder != nil else {
            return []
        }

        return TransactionLogic.titleSuggestions(
            from: visiblePostedTransactions.map(\.snapshot),
            query: draft.title,
            primaryKind: draft.primaryKind,
            transferSubtype: draft.primaryKind == .transfer ? draft.transferSubtype : nil,
            excludingTransactionID: target.transaction?.id,
            limit: 5
        )
    }

    private var shouldShowTitleSuggestions: Bool {
        focusedField == .title && !suppressTitleSuggestions && !titleSuggestions.isEmpty
    }

    private var categorySections: [TransactionCategoryGroupSection] {
        let desiredKind: TransactionCategoryKind = draft.primaryKind == .income ? .income : .expense
        let preferredID = target.transaction?.category?.id
        let allowedOwnerUserIDs = effectiveCategoryOwnerUserIDs
        let relevantCategories = storedCategories.filter { category in
            guard let ownerUserID = categoryOwnerUserID(for: category) else {
                return false
            }

            return !category.isBalanceAdjustmentSystemCategory
                && category.kind == desiredKind
                && allowedOwnerUserIDs.contains(ownerUserID)
                && category.deletedAt == nil
                && (!category.isArchived || category.id == preferredID || category.parentCategory?.id == target.transaction?.category?.parentCategory?.id)
        }

        return MistiaCategoryHierarchy.groupedSections(
            from: relevantCategories,
            kind: desiredKind,
            includeArchived: true,
            includeEmptyParents: false
        )
    }

    private var favoriteCategories: [TransactionCategory] {
        let desiredKind: TransactionCategoryKind = draft.primaryKind == .income ? .income : .expense
        return MistiaCategoryPickerSupport.favoriteCategories(
            from: storedCategories.filter {
                guard let ownerUserID = categoryOwnerUserID(for: $0) else { return false }
                return !$0.isBalanceAdjustmentSystemCategory && effectiveCategoryOwnerUserIDs.contains(ownerUserID)
            },
            kind: desiredKind
        )
    }

    private var recentCategories: [TransactionCategory] {
        let desiredKind: TransactionCategoryKind = draft.primaryKind == .income ? .income : .expense
        return MistiaCategoryPickerSupport.recentCategories(
            from: postedTransactions,
            categories: storedCategories.filter {
                guard let ownerUserID = categoryOwnerUserID(for: $0) else { return false }
                return !$0.isBalanceAdjustmentSystemCategory && effectiveCategoryOwnerUserIDs.contains(ownerUserID)
            },
            kind: desiredKind
        )
    }

    private var selectedSourceWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == draft.sourceWalletID })
    }

    private var selectedDestinationWallet: LedgerWallet? {
        availableWallets.first(where: { $0.id == draft.destinationWalletID })
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
        !target.quickCapture && availableWallets.isEmpty && lockedViewableWallets.isEmpty
    }

    private var shouldShowWalletPermissionRequestState: Bool {
        !target.quickCapture
            && familyContextStore.isViewingOtherMemberContext
            && !lockedViewableWallets.isEmpty
    }

    private var saveButtonTitle: String {
        if target.quickCapture && target.transaction == nil {
            return mistiaLocalized(vi: "Lưu nháp", en: "Save draft", ja: "下書きを保存")
        }

        return mistiaLocalized(vi: "Lưu", en: "Save", ja: "保存")
    }

    private func save() {
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
            
            if currentBalance - amountMinor < 0 {
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
            }
            onComplete(completion)
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu giao dịch lúc này.", en: "Couldn't save this transaction right now.", ja: "現在この取引を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private var effectiveOperableTargetUserIDs: Set<UUID> {
        let operable = familyContextStore.operableTargetUserIDs
        if operable.isEmpty, let activeLocalProfileUserID = sessionStore.activeLocalProfileUserID {
            return [activeLocalProfileUserID]
        }
        return operable
    }

    private var effectiveViewableTargetUserIDs: Set<UUID> {
        let viewable = familyContextStore.viewableTargetUserIDs
        if viewable.isEmpty, let activeLocalProfileUserID = sessionStore.activeLocalProfileUserID {
            return [activeLocalProfileUserID]
        }
        return viewable
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var categoryOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
    }

    private var effectiveCategoryOwnerUserIDs: Set<UUID> {
        if let selectedSourceWallet,
           let ownerUserID = walletOwnerUserID(for: selectedSourceWallet) {
            return [ownerUserID]
        }
        return effectiveOperableTargetUserIDs
    }

    private func walletOwnerUserID(for wallet: LedgerWallet?) -> UUID? {
        guard let wallet else { return nil }
        return walletOwnerMap[wallet.id] ?? sessionStore.activeLocalProfileUserID
    }

    private func walletOwnerUserID(for walletID: UUID?) -> UUID? {
        guard let walletID else { return nil }
        return walletOwnerMap[walletID] ?? sessionStore.activeLocalProfileUserID
    }

    private func categoryOwnerUserID(for category: TransactionCategory) -> UUID? {
        categoryOwnerMap[category.id] ?? sessionStore.activeLocalProfileUserID
    }

    private func walletPickerTitle(for wallet: LedgerWallet) -> String {
        guard let ownerName = familyContextStore.displayName(for: walletOwnerUserID(for: wallet)),
              familyContextStore.family != nil else {
            return wallet.name
        }
        return "\(wallet.name) • \(ownerName)"
    }

    private func requestWalletUsePermission() {
        guard let wallet = lockedViewableWallets.first,
              let ownerUserID = walletOwnerUserID(for: wallet) else {
            return
        }
        let walletID = wallet.id
        let walletName = wallet.name

        Task { @MainActor in
            let didSend = await familyContextStore.requestPermission(
                resourceType: .wallet,
                resourceID: walletID,
                ownerUserID: ownerUserID,
                scope: .use,
                resourceName: walletName,
                sessionStore: sessionStore
            )
            alertMessage = didSend
                ? mistiaLocalized(
                    vi: "Đã gửi yêu cầu quyền sử dụng.",
                    en: "Use access request sent.",
                    ja: "使用権限のリクエストを送信しました。"
                )
                : (familyContextStore.lastErrorMessage ?? mistiaLocalized(
                    vi: "Không thể gửi yêu cầu lúc này.",
                    en: "Couldn't send the request right now.",
                    ja: "現在リクエストを送信できません。"
                ))
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
            self.primaryKind = target.initialKind
            self.transferSubtype = target.initialKind == .transfer ? .internalTransfer : nil
            self.debtIntent = target.initialKind == .transfer ? .lend : nil
            self.title = ""
            self.amountText = ""
            self.note = ""
            self.occurredAt = .now
            self.sourceWalletID = nil
            self.destinationWalletID = nil
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
