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

    @Query(sort: [SortDescriptor(\LedgerAccount.sortOrder), SortDescriptor(\LedgerAccount.createdAt)])
    private var storedWallets: [LedgerAccount]
    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.createdAt)])
    private var storedCategories: [TransactionCategory]

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
            ZStack {
                MistiaBackgroundView(tone: .standard)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if target.quickCapture && target.transaction == nil {
                            quickCaptureContent
                        } else {
                            fullEditorContent
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
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
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.18))
                                .stroke(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.3), lineWidth: 1)
                                .frame(width: 30, height: 30)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(red: 0.75, green: 0.55, blue: 1.0))
                        }
                    }
                }
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
    }

    private var quickCaptureContent: some View {
        @Bindable var bindableDraft = draft

        return VStack(spacing: 16) {
            TransactionEditorCard(title: "Loại giao dịch") {
                TransactionChoiceChipRow(
                    values: TransactionPrimaryKind.allCases,
                    selection: $bindableDraft.primaryKind
                ) { kind in
                    Text(kind.title)
                }
            }

            TransactionEditorCard(title: "Số tiền") {
                TransactionEditorTextField(
                    title: "Số tiền",
                    text: $bindableDraft.amountText,
                    placeholder: "Ví dụ 120000"
                )
                .keyboardType(.numberPad)
            }

            TransactionHintCard(
                icon: "square.and.pencil",
                tint: accentColor,
                message: "Ghi nhanh chỉ lưu loại giao dịch và số tiền. Hãy hoàn thiện chi tiết ở tab Giao dịch."
            )
        }
    }

    private var fullEditorContent: some View {
        @Bindable var bindableDraft = draft

        return VStack(spacing: 16) {
            if draft.primaryKind == .transfer {
                TransactionEditorCard(title: "Kiểu chuyển tiền") {
                    TransactionChoiceChipRow(
                        values: TransactionTransferSubtype.allCases,
                        selection: Binding(
                            get: { bindableDraft.transferSubtype ?? .internalTransfer },
                            set: { bindableDraft.transferSubtype = $0 }
                        )
                    ) { subtype in
                        Text(subtype.title)
                    }
                }
            }

            if draft.primaryKind == .transfer, draft.transferSubtype == .debt {
                TransactionEditorCard(title: "Loại công nợ") {
                    TransactionChoiceChipRow(
                        values: TransactionDebtIntent.allCases,
                        selection: Binding(
                            get: { bindableDraft.debtIntent ?? .lend },
                            set: { bindableDraft.debtIntent = $0 }
                        )
                    ) { intent in
                        Text(intent.title)
                    }
                }
            }

            if shouldShowMissingWalletsState {
                TransactionHintCard(
                    icon: "wallet.pass",
                    tint: accentColor,
                    message: "Bạn cần thêm ít nhất một ví trong tab Quản lý trước khi ghi nhận giao dịch hoàn chỉnh."
                )
            }

            TransactionEditorCard(title: "Thông tin chính") {
                if draft.primaryKind != .transfer {
                    TransactionEditorTextField(
                        title: "Tên giao dịch",
                        text: $bindableDraft.title,
                        placeholder: draft.primaryKind == .expense ? "Ví dụ: Cà phê sáng" : "Ví dụ: Lương tháng 3"
                    )
                } else if draft.transferSubtype == .debt {
                    TransactionEditorTextField(
                        title: "Tên giao dịch",
                        text: $bindableDraft.title,
                        placeholder: "Để trống sẽ tự dùng loại công nợ"
                    )
                }

                TransactionEditorTextField(
                    title: "Số tiền",
                    text: $bindableDraft.amountText,
                    placeholder: "Ví dụ 50000"
                )
                .keyboardType(.numberPad)

                DatePicker("Thời gian", selection: $bindableDraft.occurredAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "vi_VN"))
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            switch draft.primaryKind {
            case .expense, .income:
                TransactionEditorCard(title: "Nguồn tiền") {
                    TransactionSelectionMenuRow(
                        title: "Ví",
                        value: selectedSourceWallet?.name ?? "Chọn ví",
                        systemImage: "wallet.pass"
                    ) {
                        ForEach(availableWallets) { wallet in
                            Button(wallet.name) {
                                draft.sourceWalletID = wallet.id
                            }
                        }
                    }

                    TransactionSelectionMenuRow(
                        title: "Danh mục",
                        value: selectedCategory?.name ?? "Chọn danh mục",
                        systemImage: "square.grid.2x2"
                    ) {
                        ForEach(availableCategories) { category in
                            Button(category.name) {
                                draft.categoryID = category.id
                            }
                        }
                    }
                }
            case .transfer:
                if draft.transferSubtype == .internalTransfer {
                    TransactionEditorCard(title: "Luồng chuyển") {
                        TransactionSelectionMenuRow(
                            title: "Từ ví",
                            value: selectedSourceWallet?.name ?? "Chọn nguồn",
                            systemImage: "arrow.up.right.circle"
                        ) {
                            ForEach(availableWallets) { wallet in
                                Button(wallet.name) {
                                    draft.sourceWalletID = wallet.id
                                }
                            }
                        }

                        TransactionSelectionMenuRow(
                            title: "Đến ví",
                            value: selectedDestinationWallet?.name ?? "Chọn đích",
                            systemImage: "arrow.down.left.circle"
                        ) {
                            ForEach(availableWallets) { wallet in
                                Button(wallet.name) {
                                    draft.destinationWalletID = wallet.id
                                }
                            }
                        }
                    }
                } else {
                    TransactionEditorCard(title: "Đối tượng") {
                        TransactionSelectionMenuRow(
                            title: "Ví thực hiện",
                            value: selectedSourceWallet?.name ?? "Chọn ví",
                            systemImage: "wallet.pass"
                        ) {
                            ForEach(availableWallets) { wallet in
                                Button(wallet.name) {
                                    draft.sourceWalletID = wallet.id
                                }
                            }
                        }

                        TransactionEditorTextField(
                            title: "Tên người liên quan",
                            text: $bindableDraft.counterpartyName,
                            placeholder: "Ví dụ: Nguyễn Văn A"
                        )
                    }
                }
            }

            TransactionEditorCard(title: "Ghi chú") {
                TextField("Thêm ghi chú nếu cần", text: $bindableDraft.note, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
        }
    }

    private var navigationTitle: String {
        if target.transaction == nil {
            return target.quickCapture ? "Ghi nhanh" : target.initialKind.title
        }

        return "Sửa giao dịch"
    }

    private var headerTitle: String {
        if target.quickCapture && target.transaction == nil {
            return "Lưu nhanh rồi hoàn thiện sau"
        }

        if let transaction = target.transaction, transaction.entryStatus == .draft {
            return "Hoàn thiện bản nháp"
        }

        return "Giao dịch local-first"
    }

    private var headerSubtitle: String {
        if target.quickCapture && target.transaction == nil {
            return "Chỉ cần số tiền và loại giao dịch. Phần còn lại sẽ xuất hiện trong lịch sử để bạn bổ sung sau."
        }

        return "Dữ liệu sẽ được lưu ngay trên thiết bị và phản ánh trực tiếp vào tab Giao dịch."
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

    private var availableWallets: [LedgerAccount] {
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

    private var selectedSourceWallet: LedgerAccount? {
        availableWallets.first(where: { $0.id == draft.sourceWalletID })
    }

    private var selectedDestinationWallet: LedgerAccount? {
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
            return "Lưu nháp"
        }

        return "Lưu"
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
            alertMessage = "Nhập số tiền lớn hơn 0 để lưu ghi nhanh."
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

        persist(completion: .savedDraft)
    }

    private func saveFullTransaction() {
        guard let amountMinor = draft.amountMinor, amountMinor > 0 else {
            alertMessage = "Nhập số tiền lớn hơn 0."
            return
        }

        if draft.primaryKind != .transfer, draft.title.nilIfBlank == nil {
            alertMessage = "Nhập tên giao dịch để lưu."
            return
        }

        guard !availableWallets.isEmpty else {
            alertMessage = "Bạn chưa có ví nào để gắn vào giao dịch."
            return
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
                alertMessage = "Chọn ví cho giao dịch này."
                return
            }

            guard let category = selectedCategory else {
                alertMessage = "Chọn danh mục cho giao dịch này."
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
                    alertMessage = "Chọn ví nguồn."
                    return
                }

                guard let destinationWallet = selectedDestinationWallet else {
                    alertMessage = "Chọn ví đích."
                    return
                }

                guard sourceWallet.id != destinationWallet.id else {
                    alertMessage = "Ví nguồn và đích phải khác nhau."
                    return
                }

                transaction.title = draft.title.nilIfBlank ?? "Chuyển tiền nội bộ"
                transaction.sourceWallet = sourceWallet
                transaction.destinationWallet = destinationWallet
                transaction.category = nil
                transaction.transferSubtype = .internalTransfer
                transaction.debtIntent = nil
                transaction.counterpartyName = nil
                transaction.normalizedCounterpartyKey = nil
            case .debt:
                guard let sourceWallet = selectedSourceWallet else {
                    alertMessage = "Chọn ví thực hiện giao dịch công nợ."
                    return
                }

                guard let debtIntent = draft.debtIntent else {
                    alertMessage = "Chọn loại công nợ."
                    return
                }

                guard let counterpartyName = draft.counterpartyName.nilIfBlank,
                      let normalizedCounterpartyKey = TransactionLogic.normalizeCounterpartyName(counterpartyName)
                else {
                    alertMessage = "Nhập tên người liên quan."
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

        persist(completion: .savedTransaction)
    }

    private func persist(completion: TransactionEditorCompletion) {
        do {
            try modelContext.save()
            onComplete(completion)
            dismiss()
        } catch {
            alertMessage = "Không thể lưu giao dịch lúc này. \(error.localizedDescription)"
        }
    }
}

private struct TransactionEditorHeaderCard: View {
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 28,
            tint: accent.opacity(0.18)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        MistiaCircleGlassBackground(tint: accent.opacity(0.22), interactive: false)

                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(subtitle)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TransactionEditorCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: Color.white.opacity(0.10)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                content
            }
        }
    }
}

private struct TransactionEditorTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    MistiaRoundedGlassBackground(
                        cornerRadius: 16,
                        tint: .white.opacity(0.08),
                        interactive: true
                    )
                }
        }
    }
}

private struct TransactionSelectionMenuRow<MenuContent: View>: View {
    let title: String
    let value: String
    let systemImage: String
    @ViewBuilder let menuContent: MenuContent

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                MistiaRoundedGlassBackground(
                    cornerRadius: 18,
                    tint: .white.opacity(0.08),
                    interactive: true
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TransactionHintCard: View {
    let icon: String
    let tint: Color
    let message: String

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint.opacity(0.12)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TransactionChoiceChipRow<Value: CaseIterable & Hashable, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let values: Value.AllCases
    @Binding var selection: Value
    @ViewBuilder let label: (Value) -> Content

    private func tintForValue(_ value: Value) -> Color {
        if let kind = value as? TransactionPrimaryKind {
            switch kind {
            case .expense:
                return Color(red: 0.95, green: 0.43, blue: 0.44)
            case .income:
                return .mint
            case .transfer:
                return Color(red: 0.29, green: 0.56, blue: 0.96)
            }
        }
        return Color(red: 0.43, green: 0.23, blue: 0.76)
    }

    private func activeForeground(_ value: Value) -> Color {
        colorScheme == .dark ? .white.opacity(0.97) : tintForValue(value)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(values), id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        label(value)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(selection == value ? activeForeground(value) : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                MistiaCapsuleGlassBackground(
                                    tint: selection == value 
                                        ? (colorScheme == .dark ? tintForValue(value).opacity(0.42) : tintForValue(value).opacity(0.16)) 
                                        : (colorScheme == .dark ? .white.opacity(0.045) : .white.opacity(0.18)),
                                    interactive: true
                                )
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        selection == value
                                            ? tintForValue(value).opacity(colorScheme == .dark ? 0.48 : 0.14)
                                            : .clear,
                                        lineWidth: 0.9
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
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
