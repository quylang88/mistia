import re

with open("Mistia/Features/Transactions/TransactionEditorSheet.swift", "r") as f:
    text = f.read()

# Replace the ZStack... ScrollView... VStack with just Form {
new_body = """    var body: some View {
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
    }"""

pattern_body = re.compile(r'    var body: some View \{.*?(?=\n    private func archiveTransaction)', re.DOTALL)
text = pattern_body.sub(new_body, text)

# Now rewrite quickCaptureContent
new_quick = """    private var quickCaptureContent: some View {
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
    }"""
pattern_quick = re.compile(r'    private var quickCaptureContent: some View \{.*?(?=\n    private var fullEditorContent)', re.DOTALL)
text = pattern_quick.sub(new_quick, text)

new_full = """    private var fullEditorContent: some View {
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
    }"""

pattern_full = re.compile(r'    private var fullEditorContent: some View \{.*?(?=\n    private var navigationTitle: String \{)', re.DOTALL)
text = pattern_full.sub(new_full, text)

# Remove the private helper structs at the bottom of the file like TransactionEditorHeaderCard, TransactionEditorCard, etc.
# These will not be used anymore.
remove_pattern = re.compile(r'private struct TransactionEditorHeaderCard: View \{.*?(?=@Observable final class TransactionFormDraft \{)', re.DOTALL)
text = remove_pattern.sub('', text)

with open("Mistia/Features/Transactions/TransactionEditorSheet.swift", "w") as f:
    f.write(text)
