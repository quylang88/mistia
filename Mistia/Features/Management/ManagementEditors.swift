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
}

struct ManagementWalletEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Query(sort: [SortDescriptor(\LedgerWallet.sortOrder), SortDescriptor(\LedgerWallet.createdAt)])
    private var storedWallets: [LedgerWallet]

    let target: ManagementWalletEditorTarget

    @State private var draft: WalletDraft
    @State private var showsIconPicker = false
    @State private var showsBankPicker = false
    @State private var showsArchiveConfirmation = false
    @State private var alertMessage: String?

    init(target: ManagementWalletEditorTarget) {
        self.target = target
        _draft = State(initialValue: WalletDraft(wallet: target.wallet, defaultKind: target.defaultKind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Nhận diện", en: "Identity", ja: "識別情報")) {
                    Button {
                        showsIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: draft.iconSymbolName,
                                color: Color(hex: draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mistiaLocalized(vi: "Biểu tượng & màu", en: "Icon & color", ja: "アイコンと色"))
                                    .foregroundStyle(.primary)
                                Text(mistiaLocalized(vi: "Chạm để tùy chỉnh icon", en: "Tap to customize the icon", ja: "タップしてアイコンを変更"))
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

                Section(mistiaLocalized(vi: "Thông tin cơ bản", en: "Basic details", ja: "基本情報")) {
                    TextField(mistiaLocalized(vi: "Tên ví", en: "Wallet name", ja: "ウォレット名"), text: $draft.name)

                    Picker(mistiaLocalized(vi: "Loại ví", en: "Wallet type", ja: "ウォレット種別"), selection: $draft.kind) {
                        ForEach(LedgerWalletKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField(draft.kind.balanceFieldTitle, text: $draft.openingBalanceText)
                        .keyboardType(.numberPad)

                    LabeledContent(mistiaLocalized(vi: "Tiền tệ", en: "Currency", ja: "通貨")) {
                        Text(draft.currencyCode)
                            .foregroundStyle(.secondary)
                    }
                }

                if draft.kind == .bank {
                    Section(mistiaLocalized(vi: "Ngân hàng", en: "Bank", ja: "銀行")) {
                        Button {
                            showsBankPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mistiaLocalized(vi: "Chọn ngân hàng phổ biến", en: "Choose a popular bank", ja: "よく使われる銀行を選択"))
                                        .foregroundStyle(.primary)

                                    Text(draft.institutionDisplayName.nilIfBlank ?? mistiaLocalized(vi: "Chưa chọn", en: "Not selected", ja: "未選択"))
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

                        TextField(mistiaLocalized(vi: "Hoặc nhập tên ngân hàng", en: "Or enter the bank name", ja: "または銀行名を入力"), text: $draft.institutionDisplayName)
                            .onChange(of: draft.institutionDisplayName) { _, newValue in
                                if let selectedBank = ManagementPresetData.japaneseBanks.first(where: { $0.key == draft.institutionPresetKey }),
                                   selectedBank.name != newValue {
                                    draft.institutionPresetKey = nil
                                }
                            }
                    }
                }

                if draft.kind == .creditCard {
                    Section(mistiaLocalized(vi: "Credit card", en: "Credit card", ja: "クレジットカード")) {
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

                        TextField(mistiaLocalized(vi: "Hạn mức tín dụng", en: "Credit limit", ja: "利用限度額"), text: $draft.creditLimitText)
                            .keyboardType(.numberPad)

                        Picker(mistiaLocalized(vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日"), selection: $draft.statementClosingDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text(mistiaLocalized(vi: "Ngày \(day)", en: "Day \(day)", ja: "\(day) 日")).tag(day)
                            }
                        }

                        Picker(mistiaLocalized(vi: "Ngày thanh toán", en: "Payment day", ja: "支払日"), selection: $draft.paymentDueDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text(mistiaLocalized(vi: "Ngày \(day)", en: "Day \(day)", ja: "\(day) 日")).tag(day)
                            }
                        }

                        Picker(mistiaLocalized(vi: "Nguồn thanh toán", en: "Payment source", ja: "支払い元"), selection: $draft.paymentSourceWalletID) {
                            Text(mistiaLocalized(vi: "Chọn sau", en: "Choose later", ja: "あとで選択")).tag(Optional<UUID>.none)

                            ForEach(paymentSourceWallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }

                        TextField(mistiaLocalized(vi: "Ghi chú", en: "Notes", ja: "メモ"), text: $draft.notes, axis: .vertical)
                            .lineLimit(3...5)
                    }
                }

                if target.wallet != nil {
                    Section {
                        MistiaArchiveSection(
                            buttonTitle: mistiaLocalized(vi: "Lưu trữ ví", en: "Archive wallet", ja: "ウォレットをアーカイブ"),
                            descriptionText: mistiaLocalized(vi: "Ví lưu trữ sẽ không còn hiện trong tab quản lý. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived wallets will no longer appear in the manage tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたウォレットは管理タブに表示されなくなります。これらは30日後に自動的に永久削除されます。")
                        ) {
                            showsArchiveConfirmation = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(mistiaLocalized(vi: target.wallet == nil ? "Ví mới" : "Sửa ví", en: target.wallet == nil ? "New wallet" : "Edit wallet", ja: target.wallet == nil ? "新しいウォレット" : "ウォレットを編集"))
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
                title: mistiaCatalog("Biểu tượng ví"),
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
        .confirmationDialog(
            mistiaLocalized(vi: "Lưu trữ ví này?", en: "Archive this wallet?", ja: "このウォレットをアーカイブしますか？"),
            isPresented: $showsArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Lưu trữ", en: "Archive", ja: "アーカイブ"), role: .destructive) {
                archiveWallet()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(mistiaLocalized(vi: "Bạn vẫn có thể khôi phục sau khi nối thêm màn hình archive.", en: "You can restore it later after the archive screen is added.", ja: "アーカイブ画面が追加された後で復元できます。"))
        }
        .onChange(of: draft.kind) { oldValue, newValue in
            draft.handleKindChange(from: oldValue, to: newValue)
        }
    }

    private var paymentSourceWallets: [LedgerWallet] {
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

    private func save() {
        let trimmedName = draft.name.nilIfBlank
        guard let trimmedName else {
            alertMessage = mistiaLocalized(vi: "Nhập tên ví trước khi lưu.", en: "Enter a wallet name before saving.", ja: "保存する前にウォレット名を入力してください。")
            return
        }

        if draft.kind == .bank, draft.institutionDisplayName.nilIfBlank == nil {
            alertMessage = mistiaLocalized(vi: "Chọn hoặc nhập tên ngân hàng cho ví này.", en: "Choose or enter a bank name for this wallet.", ja: "このウォレットの銀行名を選択または入力してください。")
            return
        }

        let now = Date()
        let existingProfileID = target.wallet?.creditCardProfile?.id
        let walletForSync: LedgerWallet

        if let existingWallet = target.wallet {
            existingWallet.name = trimmedName
            existingWallet.kind = draft.kind
            existingWallet.iconSymbolName = draft.iconSymbolName
            existingWallet.iconColorHex = draft.iconColorHex
            existingWallet.currencyCode = draft.currencyCode
            existingWallet.openingBalanceMinor = draft.openingBalanceMinor
            existingWallet.institutionDisplayName = draft.kind == .bank ? draft.institutionDisplayName.nilIfBlank : nil
            existingWallet.institutionPresetKey = draft.kind == .bank ? draft.institutionPresetKey : nil
            existingWallet.updatedAt = now

            updateCreditCardProfile(for: existingWallet, now: now)
            walletForSync = existingWallet
        } else {
            let newWallet = LedgerWallet(
                name: trimmedName,
                kind: draft.kind,
                iconSymbolName: draft.iconSymbolName,
                iconColorHex: draft.iconColorHex,
                currencyCode: draft.currencyCode,
                openingBalanceMinor: draft.openingBalanceMinor,
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
            alertMessage = mistiaLocalized(vi: "Không thể lưu ví lúc này.", en: "Couldn't save this wallet right now.", ja: "現在このウォレットを保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func updateCreditCardProfile(for wallet: LedgerWallet, now: Date) {
        guard draft.kind == .creditCard else {
            if let profile = wallet.creditCardProfile {
                wallet.creditCardProfile = nil
                modelContext.delete(profile)
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
            alertMessage = mistiaLocalized(vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedWallets.map(\.sortOrder).max() ?? -1) + 1
    }
}

struct ManagementCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var sessionStore
    @Query(sort: [SortDescriptor(\TransactionCategory.createdAt), SortDescriptor(\TransactionCategory.sortOrder)])
    private var storedCategories: [TransactionCategory]

    let target: ManagementCategoryEditorTarget

    @State private var draft: CategoryDraft
    @State private var showsIconPicker = false
    @State private var showsArchiveConfirmation = false
    @State private var alertMessage: String?

    init(target: ManagementCategoryEditorTarget) {
        self.target = target
        _draft = State(initialValue: CategoryDraft(category: target.category, defaultKind: target.defaultKind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mistiaLocalized(vi: "Nhận diện", en: "Identity", ja: "識別情報")) {
                    Button {
                        showsIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: draft.iconSymbolName,
                                color: Color(hex: draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mistiaLocalized(vi: "Biểu tượng & màu", en: "Icon & color", ja: "アイコンと色"))
                                    .foregroundStyle(.primary)
                                Text(mistiaLocalized(vi: "Đổi icon và màu cho danh mục", en: "Change the icon and color for this category", ja: "カテゴリのアイコンと色を変更"))
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

                Section(mistiaLocalized(vi: "Thông tin", en: "Details", ja: "詳細")) {
                    TextField(mistiaLocalized(vi: "Tên danh mục", en: "Category name", ja: "カテゴリ名"), text: $draft.name)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(mistiaLocalized(vi: "Loại danh mục", en: "Category type", ja: "カテゴリ種別"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        MistiaNativeSegmentedControl(
                            selection: $draft.kind,
                            options: TransactionCategoryKind.allCases,
                            title: \.title,
                            accent: Color(red: 0.43, green: 0.23, blue: 0.76)
                        )
                    }
                }

                if target.category != nil {
                    Section {
                        MistiaArchiveSection(
                            buttonTitle: mistiaLocalized(vi: "Lưu trữ danh mục", en: "Archive category", ja: "カテゴリをアーカイブ"),
                            descriptionText: mistiaLocalized(vi: "Danh mục lưu trữ sẽ không còn hiện trong tab quản lý. Mục này sẽ được tự động xóa vĩnh viễn sau 30 ngày.", en: "Archived categories will no longer appear in the manage tab. They will be automatically deleted permanently after 30 days.", ja: "アーカイブしたカテゴリは管理タブに表示されなくなります。これらは30日後に自動的に永久削除されます。")
                        ) {
                            showsArchiveConfirmation = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(mistiaLocalized(vi: target.category == nil ? "Danh mục mới" : "Sửa danh mục", en: target.category == nil ? "New category" : "Edit category", ja: target.category == nil ? "新しいカテゴリ" : "カテゴリを編集"))
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
                title: mistiaCatalog("Biểu tượng danh mục"),
                selectedIconSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
                draft.iconWasCustomized = true
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
        .confirmationDialog(
            mistiaLocalized(vi: "Lưu trữ danh mục này?", en: "Archive this category?", ja: "このカテゴリをアーカイブしますか？"),
            isPresented: $showsArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(mistiaLocalized(vi: "Lưu trữ", en: "Archive", ja: "アーカイブ"), role: .destructive) {
                archiveCategory()
            }

            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        }
        .onChange(of: draft.kind) { oldValue, newValue in
            draft.handleKindChange(from: oldValue, to: newValue)
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = mistiaLocalized(vi: "Nhập tên danh mục trước khi lưu.", en: "Enter a category name before saving.", ja: "保存する前にカテゴリ名を入力してください。")
            return
        }

        let now = Date()
        let categoryForSync: TransactionCategory

        if let category = target.category {
            let previousKind = category.kind
            category.name = trimmedName
            category.kind = draft.kind
            category.iconSymbolName = draft.iconSymbolName
            category.iconColorHex = draft.iconColorHex
            category.updatedAt = now

            if previousKind != draft.kind {
                category.sortOrder = nextSortOrder(for: draft.kind, excluding: category)
            }
            categoryForSync = category
        } else {
            let category = TransactionCategory(
                name: trimmedName,
                kind: draft.kind,
                iconSymbolName: draft.iconSymbolName,
                iconColorHex: draft.iconColorHex,
                isSystem: false,
                sortOrder: nextSortOrder(for: draft.kind, excluding: nil)
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
            dismiss()
        } catch {
            alertMessage = mistiaLocalized(vi: "Không thể lưu danh mục lúc này.", en: "Couldn't save this category right now.", ja: "現在このカテゴリを保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func archiveCategory() {
        guard let category = target.category else { return }

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
            alertMessage = mistiaLocalized(vi: "Không thể lưu trạng thái lưu trữ.", en: "Couldn't save the archive state.", ja: "アーカイブ状態を保存できません。") + " \(error.localizedDescription)"
        }
    }

    private func nextSortOrder(for kind: TransactionCategoryKind, excluding category: TransactionCategory?) -> Int {
        let maxSort = storedCategories
            .filter { !$0.isArchived && $0.kind == kind && $0.id != category?.id }
            .map(\.sortOrder)
            .max() ?? -1

        return maxSort + 1
    }
}

private struct ManagementIconPickerSheet: View {
    let title: String
    let onSave: (String, String) -> Void

    let selectedIconSymbolName: String
    let selectedColorHex: String

    init(
        title: String,
        selectedIconSymbolName: String,
        selectedColorHex: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.selectedIconSymbolName = selectedIconSymbolName
        self.selectedColorHex = selectedColorHex
    }

    var body: some View {
        MistiaIconPickerSheet(
            title: title,
            selectedSymbolName: selectedIconSymbolName,
            selectedColorHex: selectedColorHex,
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
                Section(mistiaLocalized(vi: "Ngân hàng phổ biến tại Nhật", en: "Popular banks in Japan", ja: "日本でよく使われる銀行")) {
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

                Section(mistiaLocalized(vi: "Không thấy trong danh sách?", en: "Don't see it here?", ja: "一覧にありませんか？")) {
                    TextField(mistiaLocalized(vi: "Nhập thủ công tên ngân hàng", en: "Enter bank name manually", ja: "銀行名を手入力"), text: $manualName)

                    Button(mistiaLocalized(vi: "Dùng tên này", en: "Use this name", ja: "この名前を使う")) {
                        onSelect(nil, manualName.nilIfBlank ?? "")
                        dismiss()
                    }
                    .disabled(manualName.nilIfBlank == nil)
                }
            }
            .searchable(text: $searchText, prompt: mistiaLocalized(vi: "Tìm ngân hàng", en: "Search banks", ja: "銀行を検索"))
            .navigationTitle(mistiaLocalized(vi: "Chọn ngân hàng", en: "Choose bank", ja: "銀行を選択"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(mistiaLocalized(vi: "Đóng", en: "Close", ja: "閉じる")) {
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

private struct ManagementEditorIconPreview: View {
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

private struct WalletDraft {
    var name: String
    var kind: LedgerWalletKind
    var iconSymbolName: String
    var iconColorHex: String
    var currencyCode: String
    var openingBalanceText: String
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
            let matchesDefaultIcon = wallet.kind.matchesDefaultIconAppearance(
                symbolName: wallet.iconSymbolName,
                colorHex: wallet.iconColorHex
            )

            self.name = wallet.name
            self.kind = wallet.kind
            self.iconSymbolName = wallet.iconSymbolName
            self.iconColorHex = wallet.kind.migratedLegacyDefaultColorHex(
                for: wallet.iconColorHex,
                symbolName: wallet.iconSymbolName
            ) ?? MistiaIconColorPalette.normalizedHex(wallet.iconColorHex)
            self.currencyCode = wallet.currencyCode
            self.openingBalanceText = "\(wallet.openingBalanceMinor)"
            self.institutionDisplayName = wallet.institutionDisplayName ?? ""
            self.institutionPresetKey = wallet.institutionPresetKey
            self.issuerName = profile?.issuerName ?? ""
            self.network = profile?.network ?? .visa
            self.last4 = profile?.last4 ?? ""
            self.creditLimitText = profile.map { "\($0.creditLimitMinor)" } ?? ""
            self.statementClosingDay = profile?.statementClosingDay ?? 25
            self.paymentDueDay = profile?.paymentDueDay ?? 10
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
            self.institutionDisplayName = ""
            self.institutionPresetKey = nil
            self.issuerName = ""
            self.network = .visa
            self.last4 = ""
            self.creditLimitText = ""
            self.statementClosingDay = 25
            self.paymentDueDay = 10
            self.notes = ""
            self.paymentSourceWalletID = nil
            self.iconWasCustomized = false
        }
    }

    var openingBalanceMinor: Int64 {
        openingBalanceText.currencyInputToMinorUnits(currencyCode: currencyCode)
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
            statementClosingDay = 25
            paymentDueDay = 10
        }
    }
}

private struct CategoryDraft {
    var name: String
    var kind: TransactionCategoryKind
    var iconSymbolName: String
    var iconColorHex: String
    var iconWasCustomized: Bool

    init(category: TransactionCategory?, defaultKind: TransactionCategoryKind) {
        if let category {
            let matchesDefaultIcon = category.kind.matchesDefaultIconAppearance(
                symbolName: category.iconSymbolName,
                colorHex: category.iconColorHex
            )

            self.name = category.name
            self.kind = category.kind
            self.iconSymbolName = category.iconSymbolName
            self.iconColorHex = category.kind.migratedLegacyDefaultColorHex(
                for: category.iconColorHex,
                symbolName: category.iconSymbolName
            ) ?? MistiaIconColorPalette.normalizedHex(category.iconColorHex)
            self.iconWasCustomized = !matchesDefaultIcon
        } else {
            self.name = ""
            self.kind = defaultKind
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
