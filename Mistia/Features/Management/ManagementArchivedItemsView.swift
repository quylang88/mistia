import SwiftData
import SwiftUI

private enum ArchivedItemSelection: Hashable {
    case transaction(UUID)
    case wallet(UUID)
    case category(UUID)
}

private struct ArchivedSyncMutation {
    let entity: MistiaSyncEntity
    let id: UUID
    let updatedAt: Date
    let subjectUserIDOverride: UUID?
}

private struct ArchivedTransactionDescriptor {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let badgeTitle: String
    let badgeTint: Color
    let amountText: String
    let amountTint: Color
}

struct ManagementArchivedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @Query(filter: #Predicate<LedgerTransaction> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedTransactions: [LedgerTransaction]

    @Query(filter: #Predicate<LedgerWallet> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedWallets: [LedgerWallet]

    @Query(filter: #Predicate<TransactionCategory> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedCategories: [TransactionCategory]

    @State private var isSelecting = false
    @State private var selectedItems: Set<ArchivedItemSelection> = []
    @State private var showsDeleteConfirmation = false

    private var availableSelections: Set<ArchivedItemSelection> {
        Set(archivedTransactions.map { .transaction($0.id) })
            .union(archivedWallets.map { .wallet($0.id) })
            .union(archivedCategories.map { .category($0.id) })
    }

    private var hasArchivedItems: Bool {
        !availableSelections.isEmpty
    }

    private var hasSelection: Bool {
        !selectedItems.isEmpty
    }

    private var navigationTitle: String {
        guard isSelecting else {
            return mistiaLocalized(vi: "Mục đã lưu trữ", en: "Archived items", ja: "アーカイブ済みアイテム")
        }

        if selectedItems.isEmpty {
            return mistiaLocalized(vi: "Chọn mục", en: "Select items", ja: "項目を選択")
        }

        return mistiaLocalized(
            vi: "\(selectedItems.count) mục đã chọn",
            en: "\(selectedItems.count) selected",
            ja: "\(selectedItems.count)件を選択"
        )
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: navigationTitle,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { dismiss() },
            contentSpacing: 16,
            contentBottomPadding: isSelecting ? 110 : 150
        ) {
            EmptyView()
        } trailingAccessory: {
            trailingToolbarAccessory
        } content: {
            archivedContent
        }
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                ArchivedBottomActionBar(
                    selectedCount: selectedItems.count,
                    canRestore: hasSelection,
                    canDelete: hasSelection,
                    onRestore: restoreSelectedItems,
                    onDelete: { showsDeleteConfirmation = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            mistiaLocalized(
                vi: "Xóa vĩnh viễn các mục đã chọn?",
                en: "Delete selected items permanently?",
                ja: "選択した項目を完全に削除しますか？"
            ),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                mistiaLocalized(
                    vi: "Xóa vĩnh viễn",
                    en: "Delete permanently",
                    ja: "完全に削除"
                ),
                role: .destructive
            ) {
                deleteSelectedItems()
            }
            Button(mistiaLocalized(vi: "Hủy", en: "Cancel", ja: "キャンセル"), role: .cancel) { }
        } message: {
            Text(
                mistiaLocalized(
                    vi: "Các mục này sẽ bị xóa khỏi lưu trữ và không thể hoàn tác.",
                    en: "These items will be removed from the archive and can't be undone.",
                    ja: "これらの項目はアーカイブから削除され、元に戻せません。"
                )
            )
        }
        .onChange(of: availableSelections, initial: true) { _, newValue in
            selectedItems = selectedItems.intersection(newValue)

            if newValue.isEmpty {
                isSelecting = false
            }
        }
    }

    @ViewBuilder
    private var archivedContent: some View {
        if !hasArchivedItems {
            VStack(spacing: 16) {
                Spacer()
                    .frame(height: 80)

                Image(systemName: "archivebox")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.tertiary)

                Text(mistiaLocalized(vi: "Không có mục lưu trữ", en: "No archived items", ja: "アーカイブなし"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(
                    mistiaLocalized(
                        vi: "Bạn chưa có mục nào được lưu trữ. Các mục được lưu trữ sẽ tự động xoá sau 30 ngày.",
                        en: "You don't have any archived items yet. Archived items are automatically deleted after 30 days.",
                        ja: "アーカイブされたアイテムはまだありません。アーカイブされたアイテムは30日後に自動的に削除されます。"
                    )
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        } else {
            if !archivedTransactions.isEmpty {
                ManagementSection(
                    title: mistiaLocalized(vi: "Giao dịch", en: "Transactions", ja: "取引"),
                    titleColor: sectionLabelColor
                ) {
                    ForEach(archivedTransactions) { transaction in
                        ArchivedTransactionRow(
                            descriptor: descriptor(for: transaction),
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.transaction(transaction.id)),
                            onToggleSelection: { toggleSelection(.transaction(transaction.id)) },
                            onRestore: { restoreSelections([.transaction(transaction.id)]) },
                            onDelete: { deleteSelections([.transaction(transaction.id)]) }
                        )
                    }
                }
            }

            if !archivedWallets.isEmpty {
                ManagementSection(
                    title: mistiaLocalized(vi: "Ví", en: "Wallets", ja: "ウォレット"),
                    titleColor: sectionLabelColor
                ) {
                    ForEach(archivedWallets) { wallet in
                        ArchivedDetailRow(
                            title: wallet.name,
                            subtitle: "\(wallet.kind.title) • \(wallet.currencyCode)",
                            icon: wallet.iconSymbolName,
                            iconTint: Color(hex: wallet.iconColorHex),
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.wallet(wallet.id)),
                            onToggleSelection: { toggleSelection(.wallet(wallet.id)) },
                            onRestore: { restoreSelections([.wallet(wallet.id)]) },
                            onDelete: { deleteSelections([.wallet(wallet.id)]) }
                        )
                    }
                }
            }

            if !archivedCategories.isEmpty {
                ManagementSection(
                    title: mistiaLocalized(vi: "Danh mục", en: "Categories", ja: "カテゴリ"),
                    titleColor: sectionLabelColor
                ) {
                    ForEach(archivedCategories) { category in
                        ArchivedDetailRow(
                            title: category.name,
                            subtitle: categorySubtitle(for: category),
                            icon: category.iconSymbolName,
                            iconTint: Color(hex: category.iconColorHex),
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.category(category.id)),
                            onToggleSelection: { toggleSelection(.category(category.id)) },
                            onRestore: { restoreSelections([.category(category.id)]) },
                            onDelete: { deleteSelections([.category(category.id)]) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trailingToolbarAccessory: some View {
        if isSelecting {
            MistiaHeaderCircleButton(action: exitSelectionMode) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
        } else if hasArchivedItems {
            ArchivedToolbarGlassButton(
                title: mistiaLocalized(vi: "Chọn", en: "Select", ja: "選択"),
                action: enterSelectionMode
            )
        }
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.36, green: 0.37, blue: 0.43)
    }

    private func categorySubtitle(for category: TransactionCategory) -> String {
        if let parentName = category.parentCategory?.localizedDisplayName {
            return "\(category.kind.title) • \(parentName)"
        }

        return category.kind.title
    }

    private func descriptor(for transaction: LedgerTransaction) -> ArchivedTransactionDescriptor {
        let defaultWalletTitle = mistiaLocalized(vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択")
        let defaultCategoryTitle = mistiaLocalized(vi: "Chưa chọn danh mục", en: "No category selected", ja: "カテゴリ未選択")
        let currency = transaction.sourceWallet?.currencyCode ?? transaction.destinationWallet?.currencyCode ?? currencyCode
        let rawAmount = transaction.amountMinor.formattedCurrency(code: currency)
        let title = transactionTitle(for: transaction)

        switch transaction.primaryKind {
        case .expense:
            return ArchivedTransactionDescriptor(
                title: title,
                subtitle: "\(transaction.sourceWallet?.name ?? defaultWalletTitle) • \(transaction.category?.localizedDisplayName ?? defaultCategoryTitle)",
                icon: transaction.category?.iconSymbolName ?? transaction.primaryKind.financeIconToken,
                iconTint: transaction.category.map { Color(hex: $0.iconColorHex) } ?? MistiaAccent.expense.color,
                badgeTitle: transaction.primaryKind.title,
                badgeTint: MistiaAccent.expense.color,
                amountText: "-" + rawAmount,
                amountTint: MistiaAccent.expense.color
            )
        case .income:
            return ArchivedTransactionDescriptor(
                title: title,
                subtitle: "\(transaction.sourceWallet?.name ?? defaultWalletTitle) • \(transaction.category?.localizedDisplayName ?? defaultCategoryTitle)",
                icon: transaction.category?.iconSymbolName ?? transaction.primaryKind.financeIconToken,
                iconTint: transaction.category.map { Color(hex: $0.iconColorHex) } ?? MistiaAccent.income.color,
                badgeTitle: transaction.primaryKind.title,
                badgeTint: MistiaAccent.income.color,
                amountText: "+" + rawAmount,
                amountTint: MistiaAccent.income.color
            )
        case .transfer:
            switch transaction.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                let source = transaction.sourceWallet?.name ?? mistiaLocalized(vi: "Nguồn", en: "Source", ja: "出金元")
                let destination = transaction.destinationWallet?.name ?? mistiaLocalized(vi: "Đích", en: "Destination", ja: "入金先")
                let transferTint = colorScheme == .dark ? .white : MistiaAccent.transfer.color

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: "\(source) → \(destination)",
                    icon: TransactionTransferSubtype.internalTransfer.financeIconToken,
                    iconTint: transferTint,
                    badgeTitle: mistiaLocalized(vi: "Chuyển tiền", en: "Transfer", ja: "振替"),
                    badgeTint: transferTint,
                    amountText: rawAmount,
                    amountTint: transferTint
                )
            case .debt:
                let cashflow = debtCashflow(for: transaction)
                let personName = transaction.counterpartyName ?? mistiaLocalized(vi: "Không rõ tên", en: "Unknown name", ja: "名前未設定")
                let walletName = transaction.sourceWallet?.name ?? defaultWalletTitle
                let debtTint: Color
                let amountText: String

                if cashflow < 0 {
                    debtTint = MistiaAccent.expense.color
                    amountText = "-" + rawAmount
                } else if cashflow > 0 {
                    debtTint = MistiaAccent.income.color
                    amountText = "+" + rawAmount
                } else {
                    debtTint = Color(red: 0.29, green: 0.56, blue: 0.96)
                    amountText = rawAmount
                }

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: "\(personName) • \(transaction.debtIntent?.title ?? mistiaLocalized(vi: "Công nợ", en: "Debt", ja: "貸し借り")) • \(walletName)",
                    icon: transaction.debtIntent?.financeIconToken ?? TransactionTransferSubtype.debt.financeIconToken,
                    iconTint: debtTint,
                    badgeTitle: mistiaLocalized(vi: "Công nợ", en: "Debt", ja: "貸し借り"),
                    badgeTint: Color(red: 0.29, green: 0.56, blue: 0.96),
                    amountText: amountText,
                    amountTint: debtTint
                )
            }
        }
    }

    private func transactionTitle(for transaction: LedgerTransaction) -> String {
        let trimmedTitle = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        switch transaction.primaryKind {
        case .expense:
            return transaction.category?.localizedDisplayName
                ?? mistiaLocalized(vi: "Chi tiêu", en: "Expense", ja: "支出")
        case .income:
            return transaction.category?.localizedDisplayName
                ?? mistiaLocalized(vi: "Thu nhập", en: "Income", ja: "収入")
        case .transfer:
            switch transaction.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                return mistiaLocalized(vi: "Chuyển tiền nội bộ", en: "Internal transfer", ja: "内部振替")
            case .debt:
                return transaction.debtIntent?.title
                    ?? mistiaLocalized(vi: "Giao dịch công nợ", en: "Debt transaction", ja: "貸し借り取引")
            }
        }
    }

    private func debtCashflow(for transaction: LedgerTransaction) -> Int64 {
        switch transaction.debtIntent {
        case .lend, .repay:
            return -transaction.amountMinor
        case .collect, .borrow:
            return transaction.amountMinor
        case nil:
            return 0
        }
    }

    private func enterSelectionMode() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isSelecting = true
        }
    }

    private func exitSelectionMode() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            isSelecting = false
            selectedItems.removeAll()
        }
    }

    private func toggleSelection(_ selection: ArchivedItemSelection) {
        guard isSelecting else { return }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
            if selectedItems.contains(selection) {
                selectedItems.remove(selection)
            } else {
                selectedItems.insert(selection)
            }
        }
    }

    private func restoreSelectedItems() {
        guard hasSelection else { return }
        restoreSelections(Array(selectedItems))
    }

    private func deleteSelectedItems() {
        guard hasSelection else { return }
        deleteSelections(Array(selectedItems))
    }

    private func restoreSelections(_ selections: [ArchivedItemSelection]) {
        guard !selections.isEmpty else { return }

        if applyArchivedMutation(to: selections, action: .restore) {
            exitSelectionMode()
        }
    }

    private func deleteSelections(_ selections: [ArchivedItemSelection]) {
        guard !selections.isEmpty else { return }

        if applyArchivedMutation(to: selections, action: .delete) {
            exitSelectionMode()
        }
    }

    @discardableResult
    private func applyArchivedMutation(
        to selections: [ArchivedItemSelection],
        action: ArchivedMutationAction
    ) -> Bool {
        let now = Date.now
        var mutations: [ArchivedSyncMutation] = []

        do {
            for selection in selections {
                switch selection {
                case .transaction(let id):
                    guard let transaction = archivedTransactions.first(where: { $0.id == id }) else { continue }
                    try prepareTransactionMutation(
                        transaction,
                        action: action,
                        at: now,
                        mutations: &mutations
                    )
                case .wallet(let id):
                    guard let wallet = archivedWallets.first(where: { $0.id == id }) else { continue }
                    prepareWalletMutation(wallet, action: action, at: now, mutations: &mutations)
                case .category(let id):
                    guard let category = archivedCategories.first(where: { $0.id == id }) else { continue }
                    prepareCategoryMutation(category, action: action, at: now, mutations: &mutations)
                }
            }

            try modelContext.save()

            for mutation in mutations {
                switch action {
                case .restore:
                    sessionStore.recordUpsert(
                        entity: mutation.entity,
                        recordID: mutation.id,
                        modifiedAt: mutation.updatedAt,
                        subjectUserIDOverride: mutation.subjectUserIDOverride
                    )
                case .delete:
                    sessionStore.recordDelete(
                        entity: mutation.entity,
                        recordID: mutation.id,
                        modifiedAt: mutation.updatedAt,
                        subjectUserIDOverride: mutation.subjectUserIDOverride
                    )
                }
            }

            return true
        } catch {
            print("Failed to mutate archived selections: \(error)")
            return false
        }
    }

    private func prepareTransactionMutation(
        _ transaction: LedgerTransaction,
        action: ArchivedMutationAction,
        at date: Date,
        mutations: inout [ArchivedSyncMutation]
    ) throws {
        if let actorUserID = sessionStore.signedInUserID {
            try TransactionAuditStore.touch(
                transactionID: transaction.id,
                actorUserID: actorUserID,
                fallbackCreatedByUserID: actorUserID,
                updatedAt: date,
                context: modelContext
            )
        }

        switch action {
        case .restore:
            transaction.isArchived = false
            transaction.archivedAt = nil
            transaction.updatedAt = date
        case .delete:
            transaction.markDeleted(at: date)
        }

        mutations.append(
            ArchivedSyncMutation(
                entity: .transaction,
                id: transaction.id,
                updatedAt: transaction.updatedAt,
                subjectUserIDOverride: transactionOwnerUserID(for: transaction)
            )
        )
    }

    private func prepareWalletMutation(
        _ wallet: LedgerWallet,
        action: ArchivedMutationAction,
        at date: Date,
        mutations: inout [ArchivedSyncMutation]
    ) {
        switch action {
        case .restore:
            wallet.isArchived = false
            wallet.archivedAt = nil
            wallet.updatedAt = date
        case .delete:
            wallet.markDeleted(at: date)
        }

        mutations.append(
            ArchivedSyncMutation(
                entity: .wallet,
                id: wallet.id,
                updatedAt: wallet.updatedAt,
                subjectUserIDOverride: nil
            )
        )
    }

    private func prepareCategoryMutation(
        _ category: TransactionCategory,
        action: ArchivedMutationAction,
        at date: Date,
        mutations: inout [ArchivedSyncMutation]
    ) {
        switch action {
        case .restore:
            category.isArchived = false
            category.archivedAt = nil
            category.updatedAt = date
        case .delete:
            category.markDeleted(at: date)
        }

        mutations.append(
            ArchivedSyncMutation(
                entity: .category,
                id: category.id,
                updatedAt: category.updatedAt,
                subjectUserIDOverride: nil
            )
        )
    }

    private func transactionOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        guard let walletID = transaction.sourceWallet?.id else {
            return nil
        }

        return try? MistiaRecordOwnershipStore.ownerUserID(
            entity: .wallet,
            recordID: walletID,
            in: MistiaDataStack.sharedModelContainer
        )
    }
}

private enum ArchivedMutationAction {
    case restore
    case delete
}

private struct ArchivedTransactionRow: View {
    let descriptor: ArchivedTransactionDescriptor
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ArchivedBaseRow(
            title: descriptor.title,
            subtitle: descriptor.subtitle,
            icon: descriptor.icon,
            iconTint: descriptor.iconTint,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onToggleSelection: onToggleSelection
        ) {
            ArchivedTypeBadge(title: descriptor.badgeTitle, tint: descriptor.badgeTint)
        } trailingContent: {
            HStack(spacing: 12) {
                Text(descriptor.amountText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(descriptor.amountTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !isSelecting {
                    ArchivedItemActionMenu(onRestore: onRestore, onDelete: onDelete)
                }
            }
        }
    }
}

private struct ArchivedDetailRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ArchivedBaseRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconTint: iconTint,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onToggleSelection: onToggleSelection
        ) {
            EmptyView()
        } trailingContent: {
            if !isSelecting {
                ArchivedItemActionMenu(onRestore: onRestore, onDelete: onDelete)
            }
        }
    }
}

private struct ArchivedBaseRow<TitleAccessory: View, TrailingContent: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    @ViewBuilder let titleAccessory: TitleAccessory
    @ViewBuilder let trailingContent: TrailingContent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            MistiaFinanceIconView(icon: icon, fallbackColor: iconTint, size: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    titleAccessory
                }

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            trailingContent

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? MistiaAccent.purple.color
                            : Color.secondary.opacity(0.45)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            colorScheme == .dark
                ? Color(UIColor.secondarySystemGroupedBackground)
                : .white.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if isSelecting {
                onToggleSelection()
            }
        }
    }
}

private struct ArchivedItemActionMenu: View {
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button(mistiaLocalized(vi: "Khôi phục", en: "Restore", ja: "復元")) {
                onRestore()
            }
            Button(
                mistiaLocalized(vi: "Xóa vĩnh viễn", en: "Delete permanently", ja: "完全に削除"),
                role: .destructive
            ) {
                onDelete()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ArchivedTypeBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(tint.opacity(0.14))
            }
    }
}

private struct ArchivedBottomActionBar: View {
    let selectedCount: Int
    let canRestore: Bool
    let canDelete: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(canRestore ? MistiaAccent.purple.color : .secondary.opacity(0.5))
            }
            .disabled(!canRestore)
            .frame(width: 44, height: 44)

            Spacer()

            Text(selectionText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(canDelete ? .red : .secondary.opacity(0.5))
            }
            .disabled(!canDelete)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 34) // Standard TabBar height area
        .background(.ultraThinMaterial)
    }

    private var selectionText: String {
        if selectedCount == 0 {
            return mistiaLocalized(vi: "Chọn mục", en: "Select items", ja: "項目を選択")
        }

        return mistiaLocalized(
            vi: "Đã chọn \(selectedCount) mục",
            en: "\(selectedCount) selected",
            ja: "\(selectedCount)件を選択"
        )
    }
}


private struct ArchivedToolbarGlassButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(title)
    }
}
