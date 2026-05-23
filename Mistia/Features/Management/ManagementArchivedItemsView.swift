import SwiftData
import SwiftUI

enum MistiaRestoreError: Error {
    case duplicatePayment
}

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
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Environment(MistiaUIState.self) private var uiState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore

    @AppStorage(MistiaAppStorageKey.currencyCode) private var currencyCode = "JPY"

    @Query(filter: #Predicate<LedgerTransaction> { $0.deletedAt == nil && !$0.isArchived })
    private var activeTransactions: [LedgerTransaction]

    @Query(filter: #Predicate<LedgerTransaction> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedTransactions: [LedgerTransaction]

    @Query(filter: #Predicate<LedgerWallet> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedWallets: [LedgerWallet]

    @Query(filter: #Predicate<TransactionCategory> { $0.isArchived == true && $0.deletedAt == nil })
    private var archivedCategories: [TransactionCategory]

    @Query
    private var ownershipScopes: [OwnedRecordScope]

    @State private var isSelecting = false
    @State private var selectedItems: Set<ArchivedItemSelection> = []
    @State private var viewID = UUID()
    @State private var alertMessage: String?

    private var availableSelections: Set<ArchivedItemSelection> {
        Set(ownArchivedTransactions.map { .transaction($0.id) })
            .union(ownArchivedWallets.map { .wallet($0.id) })
            .union(ownArchivedCategories.map { .category($0.id) })
    }

    private var hasArchivedItems: Bool {
        !availableSelections.isEmpty
    }

    private var hasSelection: Bool {
        !selectedItems.isEmpty
    }

    private var navigationTitle: String {
        L10n.management.managementarchiveditems.archivedItems
    }

    private var selfUserID: UUID? {
        sessionStore.activeLocalProfileUserID ?? sessionStore.signedInUserID
    }

    private var transactionOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
    }

    private var walletOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .wallet)
    }

    private var categoryOwnerMap: [UUID: UUID] {
        MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
    }

    private var ownActiveTransactions: [LedgerTransaction] {
        MistiaRecordOwnershipStore.visibleRecords(
            activeTransactions,
            entity: .transaction,
            ownerMap: transactionOwnerMap,
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
    }

    private var ownArchivedTransactions: [LedgerTransaction] {
        MistiaRecordOwnershipStore.visibleRecords(
            archivedTransactions,
            entity: .transaction,
            ownerMap: transactionOwnerMap,
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
    }

    private var ownArchivedWallets: [LedgerWallet] {
        MistiaRecordOwnershipStore.visibleRecords(
            archivedWallets,
            entity: .wallet,
            ownerMap: walletOwnerMap,
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
        )
    }

    private var ownArchivedCategories: [TransactionCategory] {
        MistiaRecordOwnershipStore.visibleRecords(
            archivedCategories,
            entity: .category,
            ownerMap: categoryOwnerMap,
            subjectUserID: selfUserID,
            signedInUserID: sessionStore.signedInUserID
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
            contentBottomPadding: isSelecting ? 96 : 150
        ) {
            EmptyView()
        } trailingAccessory: {
            trailingToolbarAccessory
        } content: {
            archivedContent
        }
        .onChange(of: isSelecting, initial: true) { _, newValue in
            uiState.requestTabBarHidden(newValue, id: viewID)
            NotificationCenter.default.post(
                name: NSNotification.Name("MistiaHideTabBar"),
                object: nil,
                userInfo: ["isHidden": newValue]
            )
        }
        .onDisappear {
            uiState.requestTabBarHidden(false, id: viewID)
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                ArchivedBottomActionBar(
                    selectedCount: selectedItems.count,
                    canRestore: hasSelection,
                    canDelete: hasSelection,
                    onRestore: restoreSelectedItems,
                    onDelete: deleteSelectedItems
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSelecting)
        .alert(
            L10n.management.managementarchiveditems.cannotRestore,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
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

                Text(L10n.management.managementarchiveditems.noArchivedItems)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(
                    L10n.management.managementarchiveditems.youDonTHaveAnyArchivedItems
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        } else {
            if !ownArchivedTransactions.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.transactions,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(ownArchivedTransactions) { transaction in
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

            if !ownArchivedWallets.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.wallets,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(ownArchivedWallets) { wallet in
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

            if !ownArchivedCategories.isEmpty {
                ManagementSection(
                    title: L10n.management.managementarchiveditems.categories,
                    titleColor: sectionLabelColor
                ) {
                    ForEach(ownArchivedCategories) { category in
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
            MistiaHeaderCircleButton(action: enterSelectionMode) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
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
        let defaultWalletTitle = L10n.management.managementarchiveditems.noWalletSelected
        let defaultCategoryTitle = L10n.management.managementarchiveditems.noCategorySelected
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
                let source = transaction.sourceWallet?.name ?? L10n.management.managementarchiveditems.source
                let destination = transaction.destinationWallet?.name ?? L10n.management.managementarchiveditems.destination
                let transferTint = colorScheme == .dark ? .white : MistiaAccent.transfer.color

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: "\(source) → \(destination)",
                    icon: TransactionTransferSubtype.internalTransfer.financeIconToken,
                    iconTint: transferTint,
                    badgeTitle: L10n.management.managementarchiveditems.transfer,
                    badgeTint: transferTint,
                    amountText: rawAmount,
                    amountTint: transferTint
                )
            case .familyTransfer:
                let cashflow = TransactionLogic.cashflowAmount(for: transaction.snapshot)
                let familyTint: Color
                let amountText: String

                if cashflow < 0 {
                    familyTint = MistiaAccent.expense.color
                    amountText = "-" + rawAmount
                } else if cashflow > 0 {
                    familyTint = MistiaAccent.income.color
                    amountText = "+" + rawAmount
                } else {
                    familyTint = colorScheme == .dark ? .white : MistiaAccent.transfer.color
                    amountText = rawAmount
                }

                return ArchivedTransactionDescriptor(
                    title: title,
                    subtitle: transaction.note?.nilIfBlank ?? transaction.sourceWallet?.name ?? defaultWalletTitle,
                    icon: TransactionTransferSubtype.familyTransfer.financeIconToken,
                    iconTint: familyTint,
                    badgeTitle: L10n.shared.corelogic.financeenums.family,
                    badgeTint: familyTint,
                    amountText: amountText,
                    amountTint: familyTint
                )
            case .debt:
                let cashflow = debtCashflow(for: transaction)
                let personName = transaction.counterpartyName ?? L10n.management.managementarchiveditems.unknownName
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
                    subtitle: "\(personName) • \(transaction.debtIntent?.title ?? L10n.management.managementarchiveditems.debt) • \(walletName)",
                    icon: transaction.debtIntent?.financeIconToken ?? TransactionTransferSubtype.debt.financeIconToken,
                    iconTint: debtTint,
                    badgeTitle: L10n.management.managementarchiveditems.debt,
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
                ?? L10n.management.managementarchiveditems.expense
        case .income:
            return transaction.category?.localizedDisplayName
                ?? L10n.management.managementarchiveditems.income
        case .transfer:
            switch transaction.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                return L10n.management.managementarchiveditems.internalTransfer
            case .familyTransfer:
                return L10n.shared.corelogic.financeenums.family
            case .debt:
                return transaction.debtIntent?.title
                    ?? L10n.management.managementarchiveditems.debtTransaction
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
                    guard let transaction = ownArchivedTransactions.first(where: { $0.id == id }) else { continue }
                    try prepareTransactionMutation(
                        transaction,
                        action: action,
                        at: now,
                        mutations: &mutations
                    )
                case .wallet(let id):
                    guard let wallet = ownArchivedWallets.first(where: { $0.id == id }) else { continue }
                    prepareWalletMutation(wallet, action: action, at: now, mutations: &mutations)
                case .category(let id):
                    guard let category = ownArchivedCategories.first(where: { $0.id == id }) else { continue }
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
        if action == .restore && isCreditCardPayment(transaction) {
            let calendar = MistiaCalendar.current
            let isDuplicate = ownActiveTransactions.contains { tx in
                tx.id != transaction.id &&
                tx.destinationWallet?.id == transaction.destinationWallet?.id &&
                calendar.isDate(tx.occurredAt, equalTo: transaction.occurredAt, toGranularity: .month) &&
                TransactionLogic.isCreditCardPayment(tx.snapshot)
            }

            if isDuplicate {
                let monthStr = MistiaDateFormatting.monthYearString(for: transaction.occurredAt, calendar: calendar)
                alertMessage = L10n.management.managementarchiveditems.monthValueAlreadyHasACardPayment(String(describing: monthStr))
                throw MistiaRestoreError.duplicatePayment
            }
        }

        if let actorUserID = sessionStore.activeLocalProfileUserID {
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
                subjectUserIDOverride: walletOwnerUserID(for: wallet)
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
                subjectUserIDOverride: categoryOwnerUserID(for: category)
            )
        )
    }

    private func isCreditCardPayment(_ transaction: LedgerTransaction) -> Bool {
        TransactionLogic.isCreditCardPayment(transaction.snapshot)
    }

    private func transactionOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? transaction.sourceWallet.flatMap(walletOwnerUserID(for:))
            ?? transaction.destinationWallet.flatMap(walletOwnerUserID(for:))
            ?? selfUserID
    }

    private func walletOwnerUserID(for wallet: LedgerWallet) -> UUID? {
        walletOwnerMap[wallet.id] ?? selfUserID
    }

    private func categoryOwnerUserID(for category: TransactionCategory) -> UUID? {
        categoryOwnerMap[category.id] ?? selfUserID
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            EmptyView()
        } trailingContent: {
            HStack(spacing: 12) {
                Text(descriptor.amountText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(descriptor.amountTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelecting)
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
            EmptyView()
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
                            ? MistiaAccent.lightPurple.color
                            : Color.secondary.opacity(0.45)
                    )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelecting)
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

private struct ArchivedBottomActionBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedCount: Int
    let canRestore: Bool
    let canDelete: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(colorScheme == .dark ? 0.3 : 0.5)

            actionRow
                .padding(.horizontal, 20)

            // Bù khoảng trống cho Home Indicator để icon không bị đè
            Spacer(minLength: 0)
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .background {
            (colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.42))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var actionRow: some View {
        HStack(alignment: .center, spacing: 16) {
            ArchivedBottomActionMenu(
                accessibilityTitle: L10n.management.managementarchiveditems.restore,
                systemImage: "arrow.uturn.backward",
                isEnabled: canRestore,
                tint: .primary
            ) {
                Section {
                    Button {
                        onRestore()
                    } label: {
                        Label(
                            L10n.management.managementarchiveditems.restore,
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                } header: {
                    Text(
                        L10n.management.managementarchiveditems.theSelectedItemsWillBeRestoredTo
                    )
                }
            }

            Spacer(minLength: 12)

            Text(selectionText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 12)

            ArchivedBottomActionMenu(
                accessibilityTitle: L10n.common.delete,
                systemImage: "trash",
                isEnabled: canDelete,
                tint: .red
            ) {
                Section {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(
                            L10n.management.managementarchiveditems.deletePermanently,
                            systemImage: "trash"
                        )
                    }
                } header: {
                    Text(
                        L10n.management.managementarchiveditems.theseItemsWillBeRemovedFromThe
                    )
                }
            }
        }
        .frame(height: 49)
    }

    private var barBackground: some View {
        ZStack {
            Rectangle()
                .fill(colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.42))
        }
    }

    private var selectionText: String {
        if selectedCount == 0 {
            return L10n.management.managementarchiveditems.selectItems
        }

        return L10n.management.managementarchiveditems.valueSelected(String(describing: selectedCount))
    }
}

private struct ArchivedBottomActionMenu<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let accessibilityTitle: String
    let systemImage: String
    let isEnabled: Bool
    let tint: Color
    @ViewBuilder let content: Content

    private let visualSize: CGFloat = 36
    private let touchTargetSize: CGFloat = 42

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Menu {
                    content
                } label: {
                    label
                }
                .menuIndicator(.hidden)
                .menuOrder(.fixed)
                .menuStyle(.button)
                .buttonStyle(.glass(nativeGlassStyle))
                .buttonBorderShape(.circle)
            } else {
                Menu {
                    content
                } label: {
                    label
                        .background {
                            ArchivedBottomActionButtonBackground(isEnabled: isEnabled)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(borderColor, lineWidth: 0.8)
                        }
                }
                .menuIndicator(.hidden)
                .menuOrder(.fixed)
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .disabled(!isEnabled)
        .frame(width: touchTargetSize, height: touchTargetSize)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isEnabled)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(.isButton)
        .opacity(isEnabled ? 1 : 0.46)
        .scaleEffect(isEnabled ? 1 : 0.98)
    }

    private var label: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconColor)
            .frame(width: visualSize, height: visualSize)
    }

    private var iconColor: Color {
        isEnabled ? tint : .primary.opacity(0.25)
    }

    private var borderColor: Color {
        .white.opacity(colorScheme == .dark ? 0.14 : 0.20)
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        var style = Glass.regular.tint(
            .white.opacity(colorScheme == .dark ? (isEnabled ? 0.08 : 0.04) : (isEnabled ? 0.14 : 0.08))
        )
        if isEnabled {
            style = style.interactive(true)
        }
        return style
    }
}

private struct ArchivedBottomActionButtonBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let isEnabled: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(nativeGlassStyle, in: .circle)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(fallbackTint)
                    }
            }
        }
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.16), lineWidth: 0.5)
        }
    }

    private var fallbackTint: Color {
        .white.opacity(isEnabled ? (colorScheme == .dark ? 0.08 : 0.14) : (colorScheme == .dark ? 0.04 : 0.08))
    }

    @available(iOS 26.0, *)
    private var nativeGlassStyle: Glass {
        var style = Glass.regular.tint(
            .white.opacity(isEnabled ? (colorScheme == .dark ? 0.10 : 0.16) : (colorScheme == .dark ? 0.05 : 0.10))
        )
        if isEnabled {
            style = style.interactive(true)
        }
        return style
    }
}
