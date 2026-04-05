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

struct TransactionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]
    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.createdAt)])
    private var storedCategories: [TransactionCategory]
    @Query(filter: #Predicate<LedgerTransaction> { $0.entryStatusRawValue == "posted" && !$0.isArchived })
    private var postedTransactions: [LedgerTransaction]

    let target: TransactionEditorTarget
    var onComplete: (TransactionEditorCompletion) -> Void = { _ in }

    @State private var draft: TransactionFormDraft
    @State private var alertMessage: String?

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
    }
    private func archiveTransaction() {
        guard let transaction = target.transaction else { return }
        transaction.isArchived = true
        transaction.archivedAt = Date()
        transaction.updatedAt = Date()
        
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: transaction.id,
                modifiedAt: transaction.updatedAt
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
                    .foregroundStyle(accentColor)
                }
            }

            Section(mistiaLocalized(vi: "Thông tin chính", en: "Main details", ja: "基本情報")) {
                if draft.primaryKind != .transfer {
                    TextField(
                        draft.primaryKind == .expense
                            ? mistiaLocalized(vi: "Ví dụ: Cà phê sáng", en: "Example: Morning coffee", ja: "例: 朝のコーヒー")
                            : mistiaLocalized(vi: "Ví dụ: Lương tháng 3", en: "Example: March salary", ja: "例: 3月の給料"),
                        text: $bindableDraft.title
                    )
                } else if draft.transferSubtype == .debt {
                    TextField(
                        mistiaLocalized(vi: "Để trống sẽ tự dùng loại công nợ", en: "Leave blank to use the debt type", ja: "空欄の場合は貸し借りの種類が使われます"),
                        text: $bindableDraft.title
                    )
                }

                TextField(mistiaLocalized(vi: "Ví dụ 50000", en: "Example: 50000", ja: "例: 50000"), text: $bindableDraft.amountText)
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
                            Text(wallet.name).tag(Optional(wallet.id))
                        }
                    }

                    Picker(mistiaLocalized(vi: "Danh mục", en: "Category", ja: "カテゴリ"), selection: $draft.categoryID) {
                        Text(mistiaLocalized(vi: "Chọn danh mục", en: "Choose category", ja: "カテゴリを選択")).tag(Optional<UUID>.none)
                        ForEach(availableCategories) { category in
                            Text(category.localizedDisplayName).tag(Optional(category.id))
                        }
                    }
                }
            case .transfer:
                if draft.transferSubtype == .internalTransfer {
                    Section(mistiaLocalized(vi: "Luồng chuyển", en: "Transfer flow", ja: "振替の流れ")) {
                        Picker(mistiaLocalized(vi: "Từ ví", en: "From wallet", ja: "出金元"), selection: $draft.sourceWalletID) {
                            Text(mistiaLocalized(vi: "Chọn nguồn", en: "Choose source", ja: "出金元を選択")).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }

                        Picker(mistiaLocalized(vi: "Đến ví", en: "To wallet", ja: "入金先"), selection: $draft.destinationWalletID) {
                            Text(mistiaLocalized(vi: "Chọn đích", en: "Choose destination", ja: "入金先を選択")).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }
                    }
                } else {
                    Section(mistiaLocalized(vi: "Đối tượng", en: "Counterparty", ja: "相手")) {
                        Picker(mistiaLocalized(vi: "Ví thực hiện", en: "Wallet used", ja: "使用ウォレット"), selection: $draft.sourceWalletID) {
                            Text(mistiaLocalized(vi: "Chọn ví", en: "Choose wallet", ja: "ウォレットを選択")).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }

                        TextField(
                            mistiaLocalized(vi: "Ví dụ: Nguyễn Văn A", en: "Example: Alex Johnson", ja: "例: 山田太郎"),
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
            }
        }
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
        switch draft.primaryKind {
        case .expense:
            Color(red: 0.95, green: 0.43, blue: 0.44)
        case .income:
            .mint
        case .transfer:
            Color(red: 0.29, green: 0.56, blue: 0.96)
        }
    }

    private var availableWallets: [LedgerWallet] {
        let preferredID = target.transaction?.sourceWallet?.id ?? target.transaction?.destinationWallet?.id

        return storedWallets
            .filter { !$0.isArchived || $0.id == preferredID }
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

        return storedCategories
            .filter { ($0.kind == desiredKind) && (!$0.isArchived || $0.id == preferredID) }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
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
            
            let snapshots = postedTransactions.filter { $0.id != target.transaction?.id }.map {
                TransactionRecordSnapshot(
                    id: $0.id,
                    primaryKind: $0.primaryKind,
                    transferSubtype: $0.transferSubtype,
                    debtIntent: $0.debtIntent,
                    entryStatus: $0.entryStatus,
                    title: $0.title,
                    note: $0.note,
                    amountMinor: $0.amountMinor,
                    occurredAt: $0.occurredAt,
                    createdAt: $0.createdAt,
                    sourceWalletID: $0.sourceWallet?.id,
                    sourceWalletKind: $0.sourceWallet?.kind,
                    destinationWalletID: $0.destinationWallet?.id,
                    destinationWalletKind: $0.destinationWallet?.kind,
                    categoryID: $0.category?.id,
                    counterpartyName: $0.counterpartyName,
                    normalizedCounterpartyKey: $0.normalizedCounterpartyKey
                )
            }
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
                
                let snapshots = postedTransactions.filter { $0.id != target.transaction?.id }.map {
                    TransactionRecordSnapshot(
                        id: $0.id,
                        primaryKind: $0.primaryKind,
                        transferSubtype: $0.transferSubtype,
                        debtIntent: $0.debtIntent,
                        entryStatus: $0.entryStatus,
                        title: $0.title,
                        note: $0.note,
                        amountMinor: $0.amountMinor,
                        occurredAt: $0.occurredAt,
                        createdAt: $0.createdAt,
                        sourceWalletID: $0.sourceWallet?.id,
                        sourceWalletKind: $0.sourceWallet?.kind,
                        destinationWalletID: $0.destinationWallet?.id,
                        destinationWalletKind: $0.destinationWallet?.kind,
                        categoryID: $0.category?.id,
                        counterpartyName: $0.counterpartyName,
                        normalizedCounterpartyKey: $0.normalizedCounterpartyKey
                    )
                }
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
                    
                    let snapshots = postedTransactions.filter { $0.id != target.transaction?.id }.map {
                        TransactionRecordSnapshot(
                            id: $0.id,
                            primaryKind: $0.primaryKind,
                            transferSubtype: $0.transferSubtype,
                            debtIntent: $0.debtIntent,
                            entryStatus: $0.entryStatus,
                            title: $0.title,
                            note: $0.note,
                            amountMinor: $0.amountMinor,
                            occurredAt: $0.occurredAt,
                            createdAt: $0.createdAt,
                            sourceWalletID: $0.sourceWallet?.id,
                            sourceWalletKind: $0.sourceWallet?.kind,
                            destinationWalletID: $0.destinationWallet?.id,
                            destinationWalletKind: $0.destinationWallet?.kind,
                            categoryID: $0.category?.id,
                            counterpartyName: $0.counterpartyName,
                            normalizedCounterpartyKey: $0.normalizedCounterpartyKey
                        )
                    }
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

        persist(transaction: transaction, completion: .savedTransaction)
    }

    private func persist(
        transaction: LedgerTransaction,
        completion: TransactionEditorCompletion
    ) {
        do {
            try modelContext.save()
            sessionStore.recordUpsert(
                entity: .transaction,
                recordID: transaction.id,
                modifiedAt: transaction.updatedAt
            )
            onComplete(completion)
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu giao dịch lúc này.", en: "Couldn't save this transaction right now.", ja: "現在この取引を保存できません。") + " \(error.localizedDescription)"
        }
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
