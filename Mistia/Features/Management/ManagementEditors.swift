import SwiftData
import SwiftUI

struct ManagementAccountEditorTarget: Identifiable {
    let id = UUID()
    let account: LedgerAccount?
    let defaultKind: LedgerAccountKind
}

struct ManagementCategoryEditorTarget: Identifiable {
    let id = UUID()
    let category: TransactionCategory?
    let defaultKind: TransactionCategoryKind
}

struct ManagementAccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LedgerAccount.sortOrder), SortDescriptor(\LedgerAccount.createdAt)])
    private var storedAccounts: [LedgerAccount]

    let target: ManagementAccountEditorTarget

    @State private var draft: AccountDraft
    @State private var showsIconPicker = false
    @State private var showsBankPicker = false
    @State private var showsArchiveConfirmation = false
    @State private var alertMessage: String?

    init(target: ManagementAccountEditorTarget) {
        self.target = target
        _draft = State(initialValue: AccountDraft(account: target.account, defaultKind: target.defaultKind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nhận diện") {
                    Button {
                        showsIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: draft.iconSymbolName,
                                color: Color(hex: draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Biểu tượng & màu")
                                    .foregroundStyle(.primary)
                                Text("Chạm để tùy chỉnh icon")
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

                Section("Thông tin cơ bản") {
                    TextField("Tên tài khoản", text: $draft.name)

                    Picker("Loại tài khoản", selection: $draft.kind) {
                        ForEach(LedgerAccountKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField(draft.kind.balanceFieldTitle, text: $draft.openingBalanceText)
                        .keyboardType(.numberPad)

                    LabeledContent("Tiền tệ") {
                        Text(draft.currencyCode)
                            .foregroundStyle(.secondary)
                    }
                }

                if draft.kind == .bank {
                    Section("Ngân hàng") {
                        Button {
                            showsBankPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Chọn ngân hàng phổ biến")
                                        .foregroundStyle(.primary)

                                    Text(draft.institutionDisplayName.nilIfBlank ?? "Chưa chọn")
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

                        TextField("Hoặc nhập tên ngân hàng", text: $draft.institutionDisplayName)
                            .onChange(of: draft.institutionDisplayName) { _, newValue in
                                if let selectedBank = ManagementPresetData.japaneseBanks.first(where: { $0.key == draft.institutionPresetKey }),
                                   selectedBank.name != newValue {
                                    draft.institutionPresetKey = nil
                                }
                            }
                    }
                }

                if draft.kind == .creditCard {
                    Section("Credit card") {
                        TextField("Tên đơn vị phát hành", text: $draft.issuerName)

                        Picker("Mạng thẻ", selection: $draft.network) {
                            ForEach(CreditCardNetwork.allCases) { network in
                                Text(network.title).tag(network)
                            }
                        }

                        TextField("4 số cuối", text: $draft.last4)
                            .keyboardType(.numberPad)
                            .onChange(of: draft.last4) { _, newValue in
                                draft.last4 = String(newValue.filter(\.isNumber).prefix(4))
                            }

                        TextField("Hạn mức tín dụng", text: $draft.creditLimitText)
                            .keyboardType(.numberPad)

                        Picker("Ngày chốt sao kê", selection: $draft.statementClosingDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("Ngày \(day)").tag(day)
                            }
                        }

                        Picker("Ngày thanh toán", selection: $draft.paymentDueDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("Ngày \(day)").tag(day)
                            }
                        }

                        Picker("Nguồn thanh toán", selection: $draft.paymentSourceAccountID) {
                            Text("Chọn sau").tag(Optional<UUID>.none)

                            ForEach(paymentSourceAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }

                        TextField("Ghi chú", text: $draft.notes, axis: .vertical)
                            .lineLimit(3...5)
                    }
                }

                if target.account != nil {
                    Section {
                        Button("Lưu trữ tài khoản", role: .destructive) {
                            showsArchiveConfirmation = true
                        }
                    } footer: {
                        Text("Tài khoản lưu trữ sẽ được ẩn khỏi màn hình quản lý.")
                    }
                }
            }
            .navigationTitle(target.account == nil ? "Tài khoản mới" : "Sửa tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hủy") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            ManagementIconPickerSheet(
                title: "Biểu tượng tài khoản",
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
            "Chưa thể lưu",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Lưu trữ tài khoản này?",
            isPresented: $showsArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Lưu trữ", role: .destructive) {
                archiveAccount()
            }

            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Bạn vẫn có thể khôi phục sau khi nối thêm màn hình archive.")
        }
        .onChange(of: draft.kind) { oldValue, newValue in
            draft.handleKindChange(from: oldValue, to: newValue)
        }
    }

    private var paymentSourceAccounts: [LedgerAccount] {
        storedAccounts
            .filter { account in
                !account.isArchived
                    && account.kind != .creditCard
                    && account.id != target.account?.id
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
            alertMessage = "Nhập tên tài khoản trước khi lưu."
            return
        }

        if draft.kind == .bank, draft.institutionDisplayName.nilIfBlank == nil {
            alertMessage = "Chọn hoặc nhập tên ngân hàng cho tài khoản này."
            return
        }

        let now = Date()

        if let existingAccount = target.account {
            existingAccount.name = trimmedName
            existingAccount.kind = draft.kind
            existingAccount.iconSymbolName = draft.iconSymbolName
            existingAccount.iconColorHex = draft.iconColorHex
            existingAccount.currencyCode = draft.currencyCode
            existingAccount.openingBalanceMinor = draft.openingBalanceMinor
            existingAccount.institutionDisplayName = draft.kind == .bank ? draft.institutionDisplayName.nilIfBlank : nil
            existingAccount.institutionPresetKey = draft.kind == .bank ? draft.institutionPresetKey : nil
            existingAccount.updatedAt = now

            updateCreditCardProfile(for: existingAccount, now: now)
        } else {
            let newAccount = LedgerAccount(
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

            modelContext.insert(newAccount)
            updateCreditCardProfile(for: newAccount, now: now)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = "Không thể lưu tài khoản lúc này. \(error.localizedDescription)"
        }
    }

    private func updateCreditCardProfile(for account: LedgerAccount, now: Date) {
        guard draft.kind == .creditCard else {
            if let profile = account.creditCardProfile {
                account.creditCardProfile = nil
                modelContext.delete(profile)
            }
            return
        }

        let profile = account.creditCardProfile ?? CreditCardProfile()
        profile.account = account
        profile.issuerName = draft.issuerName.nilIfBlank ?? ""
        profile.network = draft.network
        profile.last4 = draft.last4
        profile.creditLimitMinor = draft.creditLimitMinor
        profile.statementClosingDay = draft.statementClosingDay
        profile.paymentDueDay = draft.paymentDueDay
        profile.notes = draft.notes.nilIfBlank
        profile.paymentSourceAccount = paymentSourceAccounts.first(where: { $0.id == draft.paymentSourceAccountID })
        profile.updatedAt = now

        if account.creditCardProfile == nil {
            account.creditCardProfile = profile
            modelContext.insert(profile)
        }
    }

    private func archiveAccount() {
        guard let account = target.account else { return }

        account.isArchived = true
        account.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = "Không thể lưu trạng thái lưu trữ. \(error.localizedDescription)"
        }
    }

    private func nextSortOrder() -> Int {
        (storedAccounts.map(\.sortOrder).max() ?? -1) + 1
    }
}

struct ManagementCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                Section("Nhận diện") {
                    Button {
                        showsIconPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ManagementEditorIconPreview(
                                symbolName: draft.iconSymbolName,
                                color: Color(hex: draft.iconColorHex)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Biểu tượng & màu")
                                    .foregroundStyle(.primary)
                                Text("Đổi icon và màu cho danh mục")
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

                Section("Thông tin") {
                    TextField("Tên danh mục", text: $draft.name)

                    Picker("Loại danh mục", selection: $draft.kind) {
                        ForEach(TransactionCategoryKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if target.category != nil {
                    Section {
                        Button("Lưu trữ danh mục", role: .destructive) {
                            showsArchiveConfirmation = true
                        }
                    } footer: {
                        Text("Danh mục lưu trữ sẽ không còn hiện trong tab quản lý.")
                    }
                }
            }
            .navigationTitle(target.category == nil ? "Danh mục mới" : "Sửa danh mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hủy") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showsIconPicker) {
            ManagementIconPickerSheet(
                title: "Biểu tượng danh mục",
                selectedIconSymbolName: draft.iconSymbolName,
                selectedColorHex: draft.iconColorHex
            ) { symbolName, colorHex in
                draft.iconSymbolName = symbolName
                draft.iconColorHex = colorHex
                draft.iconWasCustomized = true
            }
        }
        .alert(
            "Chưa thể lưu",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Lưu trữ danh mục này?",
            isPresented: $showsArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Lưu trữ", role: .destructive) {
                archiveCategory()
            }

            Button("Hủy", role: .cancel) { }
        }
        .onChange(of: draft.kind) { oldValue, newValue in
            draft.handleKindChange(from: oldValue, to: newValue)
        }
    }

    private func save() {
        guard let trimmedName = draft.name.nilIfBlank else {
            alertMessage = "Nhập tên danh mục trước khi lưu."
            return
        }

        let now = Date()

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
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = "Không thể lưu danh mục lúc này. \(error.localizedDescription)"
        }
    }

    private func archiveCategory() {
        guard let category = target.category else { return }

        category.isArchived = true
        category.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = "Không thể lưu trạng thái lưu trữ. \(error.localizedDescription)"
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
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (String, String) -> Void

    @State private var selectedIconSymbolName: String
    @State private var selectedColor: Color

    init(
        title: String,
        selectedIconSymbolName: String,
        selectedColorHex: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _selectedIconSymbolName = State(initialValue: selectedIconSymbolName)
        _selectedColor = State(initialValue: Color(hex: selectedColorHex))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        ManagementEditorIconPreview(
                            symbolName: selectedIconSymbolName,
                            color: selectedColor,
                            size: 58
                        )

                        Text("Preview icon")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Màu icon")
                            .font(.headline)

                        ColorPicker("Chọn màu", selection: $selectedColor, supportsOpacity: false)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Biểu tượng gợi ý")
                            .font(.headline)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(ManagementPresetData.iconSymbols, id: \.self) { symbol in
                                Button {
                                    selectedIconSymbolName = symbol
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selectedColor.opacity(selectedIconSymbolName == symbol ? 0.22 : 0.08))

                                        Image(systemName: symbol)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(selectedColor)
                                    }
                                    .frame(height: 54)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                selectedIconSymbolName == symbol
                                                    ? selectedColor.opacity(0.62)
                                                    : Color.secondary.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hủy") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        onSave(selectedIconSymbolName, selectedColor.hexString)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
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
                Section("Ngân hàng phổ biến tại Nhật") {
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

                Section("Không thấy trong danh sách?") {
                    TextField("Nhập thủ công tên ngân hàng", text: $manualName)

                    Button("Dùng tên này") {
                        onSelect(nil, manualName.nilIfBlank ?? "")
                        dismiss()
                    }
                    .disabled(manualName.nilIfBlank == nil)
                }
            }
            .searchable(text: $searchText, prompt: "Tìm ngân hàng")
            .navigationTitle("Chọn ngân hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
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

private struct AccountDraft {
    var name: String
    var kind: LedgerAccountKind
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
    var paymentSourceAccountID: UUID?
    var iconWasCustomized: Bool

    init(account: LedgerAccount?, defaultKind: LedgerAccountKind) {
        if let account {
            let profile = account.creditCardProfile
            let matchesDefaultIcon = account.iconSymbolName == account.kind.defaultIconSymbolName
                && account.iconColorHex.caseInsensitiveCompare(account.kind.defaultColorHex) == .orderedSame

            self.name = account.name
            self.kind = account.kind
            self.iconSymbolName = account.iconSymbolName
            self.iconColorHex = account.iconColorHex
            self.currencyCode = account.currencyCode
            self.openingBalanceText = "\(account.openingBalanceMinor)"
            self.institutionDisplayName = account.institutionDisplayName ?? ""
            self.institutionPresetKey = account.institutionPresetKey
            self.issuerName = profile?.issuerName ?? ""
            self.network = profile?.network ?? .visa
            self.last4 = profile?.last4 ?? ""
            self.creditLimitText = profile.map { "\($0.creditLimitMinor)" } ?? ""
            self.statementClosingDay = profile?.statementClosingDay ?? 25
            self.paymentDueDay = profile?.paymentDueDay ?? 10
            self.notes = profile?.notes ?? ""
            self.paymentSourceAccountID = profile?.paymentSourceAccount?.id
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
            self.paymentSourceAccountID = nil
            self.iconWasCustomized = false
        }
    }

    var openingBalanceMinor: Int64 {
        openingBalanceText.currencyInputToMinorUnits(currencyCode: currencyCode)
    }

    var creditLimitMinor: Int64 {
        creditLimitText.currencyInputToMinorUnits(currencyCode: currencyCode)
    }

    mutating func handleKindChange(from oldValue: LedgerAccountKind, to newValue: LedgerAccountKind) {
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
            paymentSourceAccountID = nil
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
            let matchesDefaultIcon = category.iconSymbolName == category.kind.defaultIconSymbolName
                && category.iconColorHex.caseInsensitiveCompare(category.kind.defaultColorHex) == .orderedSame

            self.name = category.name
            self.kind = category.kind
            self.iconSymbolName = category.iconSymbolName
            self.iconColorHex = category.iconColorHex
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
