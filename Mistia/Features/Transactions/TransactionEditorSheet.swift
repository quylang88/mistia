import SwiftData
import SwiftUI
import UIKit

enum TransactionReceiptInitialSource: String, Equatable {
    case cameraPreferred
    case camera
    case photoLibrary
}

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

struct TransactionEditorPrefill {
    let title: String?
    let amountMinor: Int64?
    let occurredAt: Date?
    let sourceWalletID: UUID?
    let categoryID: UUID?
    let lockedTransferSubtype: TransactionTransferSubtype?
    let lockedDebtIntent: TransactionDebtIntent?
    let receiptImage: UIImage?

    init(
        title: String? = nil,
        amountMinor: Int64? = nil,
        occurredAt: Date? = nil,
        sourceWalletID: UUID? = nil,
        categoryID: UUID? = nil,
        lockedTransferSubtype: TransactionTransferSubtype? = nil,
        lockedDebtIntent: TransactionDebtIntent? = nil,
        receiptImage: UIImage? = nil
    ) {
        self.title = title
        self.amountMinor = amountMinor
        self.occurredAt = occurredAt
        self.sourceWalletID = sourceWalletID
        self.categoryID = categoryID
        self.lockedTransferSubtype = lockedTransferSubtype
        self.lockedDebtIntent = lockedDebtIntent
        self.receiptImage = receiptImage
    }
}

struct TransactionEditorTarget: Identifiable {
    let id = UUID()
    let transaction: LedgerTransaction?
    let initialKind: TransactionPrimaryKind
    let quickCapture: Bool
    let transferPreset: TransactionTransferPreset?
    let prefill: TransactionEditorPrefill?
    let subjectUserIDOverride: UUID?
    let startsReceiptScan: Bool
    let receiptInitialSource: TransactionReceiptInitialSource?

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        self.initialKind = transaction.primaryKind
        self.quickCapture = false
        self.transferPreset = nil
        self.prefill = nil
        self.subjectUserIDOverride = nil
        self.startsReceiptScan = false
        self.receiptInitialSource = nil
    }

    init(
        initialKind: TransactionPrimaryKind,
        quickCapture: Bool = false,
        transferPreset: TransactionTransferPreset? = nil,
        prefill: TransactionEditorPrefill? = nil,
        subjectUserIDOverride: UUID? = nil,
        startsReceiptScan: Bool = false,
        receiptInitialSource: TransactionReceiptInitialSource? = nil
    ) {
        self.transaction = nil
        self.initialKind = initialKind
        self.quickCapture = quickCapture
        self.transferPreset = transferPreset
        self.prefill = prefill
        self.subjectUserIDOverride = subjectUserIDOverride
        self.startsReceiptScan = startsReceiptScan || receiptInitialSource != nil
        self.receiptInitialSource = receiptInitialSource ?? (startsReceiptScan ? .cameraPreferred : nil)
    }
}

enum TransactionEditorCompletion: Equatable {
    case savedDraft
    case savedTransaction
}

private enum TransactionEditorFocusedField: Hashable {
    case title
}

private struct FamilyTransferDraftPayload {
    let recipientUserID: UUID
    let sourceWalletID: UUID
    let destinationWalletID: UUID
    let amountMinor: Int64
    let occurredAt: Date
    let note: String?
}

private struct TransferCreatePermissionPrompt: Identifiable {
    let subtype: TransactionTransferSubtype
    let resourceType: MistiaFamilyNotificationResourceType
    let ownerUserID: UUID
    let memberName: String
    let isPending: Bool

    var id: String {
        "\(resourceType.rawValue):\(ownerUserID.uuidString.lowercased()):\(isPending)"
    }
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
    }, sort: \LedgerTransaction.occurredAt, order: .reverse)
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
    @State private var receiptDraft: TransactionReceiptDraft?
    @State private var shouldDeleteReceiptOnSave = false
    @State private var receiptImageSource: TransactionReceiptImageSource?
    @State private var receiptPreview: TransactionReceiptPreviewItem?
    @State private var receiptLoadTask: Task<Void, Never>?
    @State private var isAnalyzingReceipt = false
    @State private var receiptAnalysisQuota: ReceiptAnalysisQuota?
    @State private var didLoadReceiptDraft = false
    @State private var didAutoPresentReceiptScanner = false
    @State private var didApplyReceiptPrefill = false
    @State private var showsFamilyTransferConfirmation = false
    @State private var transferPermissionPrompt: TransferCreatePermissionPrompt?
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

    private var isFamilyTransferCreation: Bool {
        target.transaction == nil
            && draft.primaryKind == .transfer
            && draft.transferSubtype == .familyTransfer
    }

    private var isFamilyTransferDetail: Bool {
        target.transaction?.transferSubtype == .familyTransfer
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

                            Text(L10n.transactions.transactioneditor.thisTransactionIsPartOfAPaid)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
                if isFamilyTransferDetail {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.doc.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(MistiaAccent.purple.color)
                                .padding(8)
                                .background(MistiaAccent.purple.color.opacity(0.1))
                                .clipShape(Circle())

                            Text(L10n.transactions.transactioneditor.familyTransferReadOnlyNotice)
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
            .disabled(isLockedByStatement || isFamilyTransferDetail || isSaving)
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
                    if !isAdjustment && !isLockedByStatement && !isFamilyTransferDetail {
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
            L10n.transactions.transactioneditor.confirmFamilyTransferTitle,
            isPresented: $showsFamilyTransferConfirmation
        ) {
            Button(L10n.common.cancel, role: .cancel) { }
            Button(L10n.transactions.transactioneditor.confirmFamilyTransferAction, role: .destructive) {
                saveConfirmedFamilyTransfer()
            }
        } message: {
            Text(L10n.transactions.transactioneditor.confirmFamilyTransferMessage)
        }
        .alert(
            transferPermissionPrompt?.isPending == true
                ? L10n.transactions.transactioneditor.permissionRequestPendingTitle
                : L10n.transactions.transactioneditor.requestTransferPermissionTitle,
            isPresented: Binding(
                get: { transferPermissionPrompt != nil },
                set: { if !$0 { transferPermissionPrompt = nil } }
            ),
            presenting: transferPermissionPrompt
        ) { prompt in
            Button(L10n.common.cancel, role: .cancel) { }
            if prompt.isPending {
                Button(L10n.transactions.transactioneditor.refreshPermissionStatus) {
                    refreshTransferPermissionPrompt()
                }
            } else {
                Button(L10n.transactions.transactioneditor.sendPermissionRequest) {
                    requestTransferCreatePermission(prompt)
                }
            }
        } message: { prompt in
            Text(transferPermissionMessage(for: prompt))
        }
        .alert(
            L10n.transactions.transactioneditor.canTSaveYet,
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(L10n.common.ok, role: .cancel) { }
        } message: {
            Text((alertMessage ?? ""))
        }
        .sheet(isPresented: $showsCategoryPicker) {
            MistiaCategoryPickerSheet(
                title: L10n.transactions.transactioneditor.chooseCategory,
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
        .sheet(item: $receiptImageSource) { source in
            TransactionReceiptImagePicker(sourceType: source.uiImagePickerSourceType) { image in
                handlePickedReceiptImage(image)
            }
        }
        .sheet(item: $receiptPreview) { preview in
            NavigationStack {
                ZStack {
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()

                    Image(uiImage: preview.image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                .navigationTitle(L10n.transactions.transactioneditor.receiptImage)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            receiptPreview = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
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
            normalizeTransferDraftForSubtype()
        }
        .onChange(of: draft.familyRecipientUserID) { _, _ in
            clearMismatchedWalletsForCurrentSubject()
        }
        .onChange(of: familyContextStore.selectedSubjectUserID) { _, _ in
            clearMismatchedWalletsForCurrentSubject()
            clearMismatchedCategoryForSelectedWallet()
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                loadReceiptDraftIfNeeded()
                applyReceiptPrefillIfNeeded()
                scheduleTitleSuggestionsRefresh()
                presentInitialReceiptScannerIfNeeded()
            }
        }
        .onDisappear {
            titleSuggestionRefreshTask?.cancel()
            titleSuggestionRefreshTask = nil
            receiptLoadTask?.cancel()
            receiptLoadTask = nil
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
            alertMessage = L10n.transactions.transactioneditor.couldnTSaveTheArchiveState + " \(error.localizedDescription)"
        }
    }

    private var quickCaptureContent: some View {
        @Bindable var bindableDraft = draft

        return Group {
            Section(L10n.transactions.transactioneditor.transactionType) {
                Picker(L10n.transactions.transactioneditor.transactionType, selection: $bindableDraft.primaryKind) {
                    ForEach(TransactionPrimaryKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(L10n.transactions.transactioneditor.amount) {
                TextField(L10n.transactions.transactioneditor.amount, text: $bindableDraft.amountText)
                    .keyboardType(.numberPad)
            }

            Section {
                Text(L10n.transactions.transactioneditor.quickCaptureOnlySavesTheTransactionType)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
    private var fullEditorContent: some View {
        @Bindable var bindableDraft = draft

        return Group {
            if draft.primaryKind == .transfer {
                Section(L10n.transactions.transactioneditor.transferType) {
                    MistiaNativeSegmentedControl(
                        selection: Binding(
                            get: { bindableDraft.transferSubtype ?? .internalTransfer },
                            set: { subtype in
                                guard isTransferSubtypeEnabled(subtype) else { return }
                                if let prompt = transferPermissionPrompt(for: subtype) {
                                    transferPermissionPrompt = prompt
                                    return
                                }
                                bindableDraft.transferSubtype = subtype
                            }
                        ),
                        options: transferSubtypeOptions,
                        title: { $0.title },
                        isEnabled: isTransferSubtypeEnabled
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if canShowFamilyTransferMode && !sessionStore.canPerformRemoteActions {
                        Text(L10n.transactions.transactioneditor.familyTransferNeedsNetwork)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                }
            }

            if draft.primaryKind == .transfer, draft.transferSubtype == .debt {
                Section(L10n.transactions.transactioneditor.debtType) {
                    Picker(L10n.transactions.transactioneditor.debtType, selection: Binding(
                        get: { bindableDraft.debtIntent ?? .lend },
                        set: { bindableDraft.debtIntent = $0 }
                    )) {
                        ForEach(debtIntentOptions, id: \.self) { intent in
                            Text(intent.title).tag(intent)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(target.prefill?.lockedDebtIntent != nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if shouldShowMissingWalletsState {
                Section {
                    Text(L10n.transactions.transactioneditor.youNeedToAddAtLeastOne)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section(L10n.transactions.transactioneditor.mainDetails) {
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

                TextField(L10n.transactions.transactioneditor.amount, text: $bindableDraft.amountText)
                    .keyboardType(.numberPad)

                MistiaDatePickerRow(
                    title: L10n.transactions.transactioneditor.dateTime,
                    selection: $bindableDraft.occurredAt,
                    mode: .dateAndTime
                )
            }

            switch draft.primaryKind {
            case .expense, .income:
                Section(L10n.transactions.transactioneditor.fundingSource) {
                    Picker(L10n.transactions.transactioneditor.wallet, selection: $draft.sourceWalletID) {
                        Text(L10n.transactions.transactioneditor.chooseWallet).tag(Optional<UUID>.none)
                        ForEach(availableWallets) { wallet in
                            Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showsCategoryPicker = true
                    } label: {
                        HStack {
                            Text(L10n.transactions.transactioneditor.category)
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
                    Section(L10n.transactions.transactioneditor.transferFlow) {
                        Picker(L10n.transactions.transactioneditor.fromWallet, selection: $draft.sourceWalletID) {
                            Text(L10n.transactions.transactioneditor.chooseSource).tag(Optional<UUID>.none)
                            ForEach(availableSourceWalletsForTransfer) { wallet in
                                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(L10n.transactions.transactioneditor.toWallet, selection: $draft.destinationWalletID) {
                            Text(L10n.transactions.transactioneditor.chooseDestination).tag(Optional<UUID>.none)
                            ForEach(availableDestinationWalletsForTransfer) { wallet in
                                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else if draft.transferSubtype == .familyTransfer, !isFamilyTransferDetail {
                    Section(L10n.shared.corelogic.financeenums.family) {
                        Picker(L10n.transactions.transactioneditor.familyMember, selection: $draft.familyRecipientUserID) {
                            Text(L10n.transactions.transactioneditor.chooseFamilyMember).tag(Optional<UUID>.none)
                            ForEach(availableFamilyTransferMembers) { member in
                                Text(member.displayName).tag(Optional(member.userID))
                            }
                        }
                        .pickerStyle(.menu)

                        if draft.familyRecipientUserID != nil {
                            Picker(L10n.transactions.transactioneditor.fromWallet, selection: $draft.sourceWalletID) {
                                Text(L10n.transactions.transactioneditor.chooseSource).tag(Optional<UUID>.none)
                                ForEach(availableSourceWalletsForFamilyTransfer) { wallet in
                                    Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                                }
                            }
                            .pickerStyle(.menu)

                            Picker(L10n.transactions.transactioneditor.toWallet, selection: $draft.destinationWalletID) {
                                Text(L10n.transactions.transactioneditor.chooseDestination).tag(Optional<UUID>.none)
                                ForEach(availableDestinationWalletsForFamilyTransfer) { wallet in
                                    Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if draft.familyRecipientUserID != nil && availableDestinationWalletsForFamilyTransfer.isEmpty {
                            Text(L10n.transactions.transactioneditor.noUsableWalletsForThisMember)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section(L10n.transactions.transactioneditor.counterparty) {
                        Picker(L10n.transactions.transactioneditor.walletUsed, selection: $draft.sourceWalletID) {
                            Text(L10n.transactions.transactioneditor.chooseWallet).tag(Optional<UUID>.none)
                            ForEach(availableWallets) { wallet in
                                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)

                        TextField(
                            L10n.transactions.transactioneditor.counterpartyName,
                            text: $bindableDraft.counterpartyName
                        )
                    }
                }
            }

            if shouldShowNotesSection {
                Section(L10n.transactions.transactioneditor.notes) {
                    TextField(L10n.transactions.transactioneditor.addANoteIfNeeded, text: $bindableDraft.note, axis: .vertical)
                        .lineLimit(3...5)
                }
            }

            if shouldShowReceiptSection {
                receiptSection
            }

            if let transaction = target.transaction, !transaction.isArchived, !isFamilyTransferDetail {
                Section {
                    MistiaArchiveSection(
                        buttonTitle: L10n.transactions.transactioneditor.archiveTransaction,
                        descriptionText: L10n.transactions.transactioneditor.archivedTransactionsWillNoLongerAppearIn,
                        popupMessage: L10n.transactions.transactioneditor.thisTransactionWillBeArchivedArchivedTransactions
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
        if isFamilyTransferDetail {
            return L10n.shared.corelogic.financeenums.family
        }

        if target.transaction == nil {
            return target.quickCapture
                ? L10n.transactions.transactioneditor.quickCapture
                : target.initialKind.title
        }

        return L10n.transactions.transactioneditor.editTransaction
    }

    private var headerTitle: String {
        if target.quickCapture && target.transaction == nil {
            return L10n.transactions.transactioneditor.saveFastFinishLater
        }

        if let transaction = target.transaction, transaction.entryStatus == .draft {
            return L10n.transactions.transactioneditor.completeTheDraft
        }

        return L10n.transactions.transactioneditor.localFirstTransaction
    }

    private var headerSubtitle: String {
        if target.quickCapture && target.transaction == nil {
            return L10n.transactions.transactioneditor.justEnterTheAmountAndTransactionType
        }

        return L10n.transactions.transactioneditor.dataIsSavedDirectlyOnThisDevice
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

    private var canShowFamilyTransferMode: Bool {
        familyContextStore.family != nil
            && familyContextStore.members.count >= 2
            && currentSelfUserID != nil
    }

    private var transferSubtypeOptions: [TransactionTransferSubtype] {
        if let lockedTransferSubtype = target.prefill?.lockedTransferSubtype {
            return [lockedTransferSubtype]
        }

        return TransactionTransferSubtype.editorOptions(
            isFamilyEligible: canShowFamilyTransferMode,
            includesFamilyTransfer: draft.transferSubtype == .familyTransfer || isFamilyTransferDetail
        )
    }

    private func isTransferSubtypeEnabled(_ subtype: TransactionTransferSubtype) -> Bool {
        if let lockedTransferSubtype = target.prefill?.lockedTransferSubtype {
            return subtype == lockedTransferSubtype
        }

        return TransactionTransferSubtype.isEditorOptionEnabled(
            subtype,
            canPerformRemoteActions: sessionStore.canPerformRemoteActions,
            isFamilyTransferDetail: isFamilyTransferDetail
        )
    }

    private func transferPermissionPrompt(for subtype: TransactionTransferSubtype) -> TransferCreatePermissionPrompt? {
        guard familyContextStore.isViewingOtherMemberContext,
              let ownerUserID = familyContextStore.selectedSubjectUserID,
              let resourceType = transferCreatePermissionResourceType(for: subtype),
              !familyContextStore.canCreate(ownerUserID: ownerUserID, resourceType: resourceType) else {
            return nil
        }

        return TransferCreatePermissionPrompt(
            subtype: subtype,
            resourceType: resourceType,
            ownerUserID: ownerUserID,
            memberName: familyContextStore.viewedMember?.displayName
                ?? familyContextStore.displayName(for: ownerUserID)
                ?? L10n.shared.family.familycontext.aFamilyMember,
            isPending: familyContextStore.hasPendingPermissionRequest(
                ownerUserID: ownerUserID,
                resourceType: resourceType,
                resourceID: nil,
                scope: .create
            )
        )
    }

    private func transferCreatePermissionResourceType(
        for subtype: TransactionTransferSubtype
    ) -> MistiaFamilyNotificationResourceType? {
        switch subtype {
        case .familyTransfer:
            return .familyTransfer
        case .debt:
            return .debt
        case .internalTransfer:
            return nil
        }
    }

    private func transferPermissionMessage(for prompt: TransferCreatePermissionPrompt) -> String {
        if prompt.isPending {
            return L10n.transactions.transactioneditor.transferPermissionPendingMessage(
                prompt.subtype.title,
                prompt.memberName
            )
        }

        switch prompt.subtype {
        case .familyTransfer:
            return L10n.transactions.transactioneditor.requestFamilyTransferPermissionMessage(prompt.memberName)
        case .debt:
            return L10n.transactions.transactioneditor.requestDebtPermissionMessage(prompt.memberName)
        case .internalTransfer:
            return ""
        }
    }

    private func refreshTransferPermissionPrompt() {
        guard let prompt = transferPermissionPrompt else { return }
        transferPermissionPrompt = nil
        Task { @MainActor in
            await familyContextStore.refreshLatest(
                sessionStore: sessionStore,
                source: .userInitiated
            )
            if transferPermissionPrompt(for: prompt.subtype) == nil {
                draft.transferSubtype = prompt.subtype
            }
        }
    }

    private func requestTransferCreatePermission(_ prompt: TransferCreatePermissionPrompt) {
        transferPermissionPrompt = nil
        Task { @MainActor in
            let didSend = await familyContextStore.requestPermission(
                resourceType: prompt.resourceType,
                resourceID: nil,
                ownerUserID: prompt.ownerUserID,
                scope: .create,
                resourceName: prompt.subtype.title,
                sessionStore: sessionStore
            )
            if didSend {
                alertMessage = L10n.transactions.transactions.requestSent
            } else if let message = familyContextStore.lastErrorMessage {
                alertMessage = message
            }
        }
    }

    private var debtIntentOptions: [TransactionDebtIntent] {
        if let lockedDebtIntent = target.prefill?.lockedDebtIntent {
            return [lockedDebtIntent]
        }

        return TransactionDebtIntent.allCases
    }
    
    private var availableSourceWalletsForTransfer: [LedgerWallet] {
        // Credit cards cannot be source wallet for transfers (cannot send money)
        availableWallets.filter { $0.kind != .creditCard }
    }
    
    private var availableDestinationWalletsForTransfer: [LedgerWallet] {
        // All wallets can receive transfers (including credit cards for payment)
        availableWallets
    }

    private var availableFamilyTransferMembers: [FamilyMember] {
        guard let currentSelfUserID else { return [] }
        return familyContextStore.members
            .filter { $0.userID != currentSelfUserID }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private var availableSourceWalletsForFamilyTransfer: [LedgerWallet] {
        guard let currentSelfUserID else { return [] }
        return storedWallets
            .filter { wallet in
                walletOwnerUserID(for: wallet) == currentSelfUserID
                    && wallet.kind != .creditCard
                    && wallet.deletedAt == nil
                    && !wallet.isArchived
            }
            .sorted(by: walletSort)
    }

    private var availableDestinationWalletsForFamilyTransfer: [LedgerWallet] {
        guard let recipientUserID = draft.familyRecipientUserID else { return [] }
        return storedWallets
            .filter { wallet in
                walletOwnerUserID(for: wallet) == recipientUserID
                    && wallet.deletedAt == nil
                    && !wallet.isArchived
                    && familyContextStore.canUseWallet(walletID: wallet.id, ownerUserID: recipientUserID)
            }
            .sorted(by: walletSort)
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
                ? L10n.transactions.transactioneditor.expenseName
                : L10n.transactions.transactioneditor.incomeName
        }

        if draft.transferSubtype == .debt {
            return L10n.transactions.transactioneditor.transactionNameOptional
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
              !suppressTitleSuggestions,
              draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            cachedTitleSuggestions = []
            return
        }

        cachedTitleSuggestions = TransactionLogic.titleSuggestions(
            from: visiblePostedTransactions.prefix(500).map(\.snapshot),
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
            return L10n.transactions.transactioneditor.chooseCategory
        }

        let parentName = selectedCategory.parentCategory?.localizedDisplayName ?? selectedCategory.branchDisplayName
        return "\(parentName) / \(selectedCategory.localizedDisplayName)"
    }

    private var shouldShowReceiptSection: Bool {
        draft.primaryKind == .expense || draft.primaryKind == .income
    }

    private var shouldShowNotesSection: Bool {
        true
    }

    private var receiptSection: some View {
        Section(L10n.transactions.transactioneditor.image) {
            if let receiptDraft {
                HStack(spacing: 12) {
                    Button {
                        receiptPreview = TransactionReceiptPreviewItem(image: receiptDraft.previewImage)
                    } label: {
                        HStack(spacing: 12) {
                            Image(uiImage: receiptDraft.thumbnailImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.transactions.transactioneditor.receiptImage)
                                    .foregroundStyle(.primary)

                                Text(receiptFileSizeText(for: receiptDraft.imageData.count))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(role: .destructive) {
                        removeReceiptDraft()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.transactions.transactioneditor.removeImage)
                }

                if isAnalyzingReceipt {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.transactions.transactioneditor.analyzingReceipt)
                            .foregroundStyle(.secondary)
                    }
                }

                if let receiptAnalysisQuota {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.medium")
                            .foregroundStyle(.secondary)
                        Text(receiptQuotaStatusText(for: receiptAnalysisQuota))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

            } else {
                Menu {
                    receiptImageSourceMenuButtons()
                } label: {
                    Label(
                        L10n.transactions.transactioneditor.addReceiptImage,
                        systemImage: "camera"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func receiptImageSourceMenuButtons() -> some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button {
                receiptImageSource = .camera
            } label: {
                Label(
                    L10n.transactions.transactioneditor.takePhoto,
                    systemImage: "camera"
                )
            }
        }

        Button {
            receiptImageSource = .photoLibrary
        } label: {
            Label(
                L10n.transactions.transactioneditor.chooseFromPhotos,
                systemImage: "photo"
            )
        }
    }

    private func receiptFileSizeText(for byteCount: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteCount))
    }

    private var shouldShowMissingWalletsState: Bool {
        !target.quickCapture && availableWallets.isEmpty
    }

    private var saveButtonTitle: String {
        if target.quickCapture && target.transaction == nil {
            return L10n.transactions.transactioneditor.saveDraft
        }

        return L10n.common.save
    }

    private func save() {
        guard !isSaving else { return }
        guard !isFamilyTransferDetail else { return }
        if draft.primaryKind == .transfer {
            let subtype = draft.transferSubtype ?? .internalTransfer
            if let prompt = transferPermissionPrompt(for: subtype) {
                transferPermissionPrompt = prompt
                return
            }
        }
        if isFamilyTransferCreation {
            requestFamilyTransferConfirmation()
            return
        }
        if target.quickCapture && target.transaction == nil {
            saveQuickCapture()
        } else {
            saveFullTransaction()
        }
    }

    private func requestFamilyTransferConfirmation() {
        guard validateFamilyTransferDraft() != nil else { return }
        showsFamilyTransferConfirmation = true
    }

    private func validateFamilyTransferDraft() -> FamilyTransferDraftPayload? {
        guard sessionStore.canPerformRemoteActions else {
            alertMessage = L10n.transactions.transactioneditor.familyTransferNeedsNetwork
            return nil
        }

        guard canShowFamilyTransferMode else {
            alertMessage = L10n.shared.family.familycontext.familyDataHasNotLoadedYetSync
            return nil
        }

        guard let amountMinor = draft.amountMinor, amountMinor > 0 else {
            alertMessage = L10n.transactions.transactioneditor.enterAnAmountGreaterThan
            return nil
        }

        guard let recipientUserID = draft.familyRecipientUserID,
              availableFamilyTransferMembers.contains(where: { $0.userID == recipientUserID }) else {
            alertMessage = L10n.transactions.transactioneditor.chooseFamilyMember
            return nil
        }

        guard let sourceWalletID = draft.sourceWalletID,
              let sourceWallet = availableSourceWalletsForFamilyTransfer.first(where: { $0.id == sourceWalletID }) else {
            alertMessage = L10n.transactions.transactioneditor.chooseTheSourceWallet
            return nil
        }

        guard let destinationWalletID = draft.destinationWalletID,
              availableDestinationWalletsForFamilyTransfer.contains(where: { $0.id == destinationWalletID }) else {
            alertMessage = L10n.transactions.transactioneditor.chooseTheDestinationWallet
            return nil
        }

        let validationRecordSnapshots = postedTransactions
            .filter { $0.id != target.transaction?.id }
            .map(\.snapshot)
        let validationBalanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: storedWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: validationRecordSnapshots
        )
        let sourceSnapshot = TransactionWalletSnapshot(
            id: sourceWallet.id,
            kind: sourceWallet.kind,
            openingBalanceMinor: sourceWallet.openingBalanceMinor
        )
        if validationBalanceIndex.balance(for: sourceSnapshot) - amountMinor < 0 {
            alertMessage = L10n.transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction
            return nil
        }

        return FamilyTransferDraftPayload(
            recipientUserID: recipientUserID,
            sourceWalletID: sourceWalletID,
            destinationWalletID: destinationWalletID,
            amountMinor: amountMinor,
            occurredAt: draft.occurredAt,
            note: draft.note.nilIfBlank
        )
    }

    private func saveConfirmedFamilyTransfer() {
        guard let payload = validateFamilyTransferDraft() else { return }
        isSaving = true
        Task { @MainActor in
            let didCreate = await familyContextStore.createFamilyTransfer(
                recipientUserID: payload.recipientUserID,
                sourceWalletID: payload.sourceWalletID,
                destinationWalletID: payload.destinationWalletID,
                amountMinor: payload.amountMinor,
                occurredAt: payload.occurredAt,
                note: payload.note,
                sessionStore: sessionStore
            )
            isSaving = false
            guard didCreate else {
                let detail = familyContextStore.lastErrorMessage?.nilIfBlank
                alertMessage = [
                    L10n.transactions.transactioneditor.couldnTCreateFamilyTransfer,
                    detail
                ]
                .compactMap { $0 }
                .joined(separator: " ")
                return
            }
            onComplete(.savedTransaction)
            dismiss()
        }
    }

    private func saveQuickCapture() {
        guard let amountMinor = draft.amountMinor, amountMinor > 0 else {
            alertMessage = L10n.transactions.transactioneditor.enterAnAmountGreaterThanTo
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

    private func loadReceiptDraftIfNeeded() {
        guard !didLoadReceiptDraft else { return }
        didLoadReceiptDraft = true

        guard let transaction = target.transaction else { return }

        do {
            let store = TransactionReceiptImageStore()
            guard let receipt = try store.receipt(for: transaction.id, context: modelContext) else { return }
            let imageURL = store.url(forFileName: receipt.imageFileName)
            let thumbnailURL = store.url(forFileName: receipt.thumbnailFileName)
            let contentType = receipt.contentType

            receiptLoadTask?.cancel()
            receiptLoadTask = Task { @MainActor in
                let dataResult = await Task.detached(priority: .utility) {
                    do {
                        return Result<(Data, Data), Error>.success((
                            try Data(contentsOf: imageURL),
                            try Data(contentsOf: thumbnailURL)
                        ))
                    } catch {
                        return Result<(Data, Data), Error>.failure(error)
                    }
                }.value

                guard !Task.isCancelled else { return }
                receiptLoadTask = nil

                switch dataResult {
                case .success(let payload):
                    let (imageData, thumbnailData) = payload
                    guard
                        let previewImage = UIImage(data: imageData),
                        let thumbnailImage = UIImage(data: thumbnailData)
                    else {
                        return
                    }

                    receiptDraft = TransactionReceiptDraft(
                        imageData: imageData,
                        thumbnailData: thumbnailData,
                        contentType: contentType,
                        previewImage: previewImage,
                        thumbnailImage: thumbnailImage,
                        isChanged: false
                    )
                    shouldDeleteReceiptOnSave = false
                case .failure(let error):
                    alertMessage = L10n.transactions.transactioneditor.couldnTLoadTheSavedReceiptImage + " \(error.localizedDescription)"
                }
            }
        } catch {
            alertMessage = L10n.transactions.transactioneditor.couldnTLoadTheSavedReceiptImage + " \(error.localizedDescription)"
        }
    }

    private func presentInitialReceiptScannerIfNeeded() {
        guard target.startsReceiptScan,
              let receiptInitialSource = target.receiptInitialSource,
              target.transaction == nil,
              !didAutoPresentReceiptScanner else {
            return
        }

        didAutoPresentReceiptScanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch receiptInitialSource {
            case .cameraPreferred:
                receiptImageSource = UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? .camera
                    : .photoLibrary
            case .camera:
                receiptImageSource = UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? .camera
                    : .photoLibrary
            case .photoLibrary:
                receiptImageSource = .photoLibrary
            }
        }
    }

    private func applyReceiptPrefillIfNeeded() {
        guard !didApplyReceiptPrefill,
              target.transaction == nil,
              receiptDraft == nil,
              let receiptImage = target.prefill?.receiptImage else {
            return
        }

        didApplyReceiptPrefill = true
        guard let draft = TransactionReceiptImageProcessor.makeDraft(from: receiptImage) else {
            return
        }

        receiptDraft = draft
        receiptAnalysisQuota = nil
        shouldDeleteReceiptOnSave = false
    }

    private func handlePickedReceiptImage(_ image: UIImage) {
        guard let draft = TransactionReceiptImageProcessor.makeDraft(from: image) else {
            alertMessage = L10n.transactions.transactioneditor.couldnTProcessThisReceiptImage
            return
        }

        receiptDraft = draft
        receiptAnalysisQuota = nil
        shouldDeleteReceiptOnSave = false
        analyzeCurrentReceiptDraft()
    }

    private func removeReceiptDraft() {
        receiptDraft = nil
        receiptAnalysisQuota = nil
        shouldDeleteReceiptOnSave = target.transaction != nil
    }

    private func analyzeCurrentReceiptDraft() {
        guard !isAnalyzingReceipt, let receiptDraft else { return }

        guard sessionStore.canPerformRemoteActions else {
            alertMessage = L10n.transactions.transactioneditor.receiptAINeedsSignInAndNetwork
            return
        }

        guard !availableCategories.isEmpty else {
            alertMessage = L10n.transactions.transactioneditor.youNeedAvailableCategoriesBeforeAICan
            return
        }

        isAnalyzingReceipt = true
        Task { @MainActor in
            defer { isAnalyzingReceipt = false }

            do {
                let session = try await sessionStore.prepareRemoteSession()
                let payload = receiptAnalysisPayload(for: receiptDraft)
                let result = try await ReceiptAnalysisService().analyzeReceipt(
                    payload: payload,
                    session: session
                )
                receiptAnalysisQuota = result.quota
                applyReceiptAnalysisResult(result)
            } catch {
                if case let ReceiptAnalysisServiceError.dailyLimitReached(quota) = error {
                    receiptAnalysisQuota = quota
                }
                alertMessage = receiptAnalysisErrorMessage(for: error)
            }
        }
    }

    private func receiptAnalysisPayload(for receiptDraft: TransactionReceiptDraft) -> ReceiptAnalysisRequestPayload {
        let categories = availableCategories.map { category in
            ReceiptAnalysisCategoryCandidate(
                id: category.id,
                name: category.localizedDisplayName,
                parentName: category.parentCategory?.localizedDisplayName,
                kindRawValue: category.kind.rawValue
            )
        }
        let wallets = availableWallets.map { wallet in
            ReceiptAnalysisWalletCandidate(
                id: wallet.id,
                name: wallet.name,
                kindRawValue: wallet.kind.rawValue,
                currencyCode: wallet.currencyCode,
                institutionDisplayName: wallet.institutionDisplayName
            )
        }
        let currencyCode = selectedSourceWallet?.currencyCode
            ?? availableWallets.first?.currencyCode
            ?? "JPY"

        return ReceiptAnalysisRequestPayload(
            imageBase64: receiptDraft.imageData.base64EncodedString(),
            mimeType: receiptDraft.contentType,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            currencyCode: currencyCode,
            categories: categories,
            wallets: wallets
        )
    }

    private func applyReceiptAnalysisResult(_ result: ReceiptAnalysisResult) {
        let validated = result.validated(
            categoryIDs: Set(availableCategories.map(\.id)),
            walletIDs: Set(availableWallets.map(\.id))
        )

        if let merchantName = validated.merchantName?.nilIfBlank {
            draft.title = merchantName
            suppressTitleSuggestions = true
            cachedTitleSuggestions = []
        }

        if let totalMinor = validated.totalMinor, totalMinor > 0 {
            draft.amountText = "\(totalMinor)"
        }

        if let occurredAt = validated.occurredAt {
            draft.occurredAt = occurredAt
        }

        if let walletID = validated.walletID,
           availableWallets.contains(where: { $0.id == walletID }) {
            draft.sourceWalletID = walletID
        }

        clearMismatchedCategoryForSelectedWallet()

        if let categoryID = validated.categoryID,
           let category = storedCategories.first(where: { $0.id == categoryID }),
           shouldShowCategory(category),
           category.isChildCategory,
           category.kind == selectedCategoryKind {
            draft.categoryID = categoryID
        }
    }

    private func receiptAnalysisErrorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription?.nilIfBlank {
            return message
        }

        let detail = error.localizedDescription
        return L10n.transactions.transactioneditor.couldnTAnalyzeThisReceiptRightNow + " \(detail)"
    }

    private func receiptQuotaStatusText(for quota: ReceiptAnalysisQuota) -> String {
        if quota.limitCount <= 0 {
            return L10n.transactions.transactioneditor.receiptAIIsTemporarilyDisabledToday
        }

        return L10n.transactions.transactioneditor.usedValueValueReceiptScansToday(String(describing: quota.usedCount), String(describing: quota.limitCount))
    }

    private func saveFullTransaction() {
        guard let amountMinor = draft.amountMinor, amountMinor > 0 else {
            alertMessage = L10n.transactions.transactioneditor.enterAnAmountGreaterThan
            return
        }

        if draft.primaryKind != .transfer, draft.title.nilIfBlank == nil {
            alertMessage = L10n.transactions.transactioneditor.enterATransactionNameBeforeSaving
            return
        }

        guard !availableWallets.isEmpty else {
            alertMessage = L10n.transactions.transactioneditor.youDonTHaveAnyWalletsAvailable
            return
        }

        // Credit cards cannot receive income transactions
        if draft.primaryKind == .income,
           let sourceWallet = selectedSourceWallet,
           sourceWallet.kind == .creditCard {
            alertMessage = L10n.transactions.transactioneditor.creditCardsCannotReceiveIncomePleaseSelect
            return
        }
        
        // Credit cards cannot be source wallet for transfers
        if draft.primaryKind == .transfer,
           draft.transferSubtype == .internalTransfer,
           let sourceWallet = selectedSourceWallet,
           sourceWallet.kind == .creditCard {
            alertMessage = L10n.transactions.transactioneditor.creditCardsCannotSendMoneyViaTransfer
            return
        }

        let validationRecordSnapshots = postedTransactions
            .filter { $0.id != target.transaction?.id }
            .map(\.snapshot)
        let validationBalanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: storedWallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: validationRecordSnapshots
        )

        switch draft.primaryKind {
        case .expense:
            guard let sourceWallet = selectedSourceWallet else {
                alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
                return
            }

            let snapshot = TransactionWalletSnapshot(
                id: sourceWallet.id,
                kind: sourceWallet.kind,
                openingBalanceMinor: sourceWallet.openingBalanceMinor
            )

            let currentBalance = validationBalanceIndex.balance(for: snapshot)

            // For credit cards, check available credit (limit - debt), not debt itself
            if sourceWallet.kind == .creditCard {
                if let paidStatement = paidCreditCardStatement(
                    for: sourceWallet,
                    occurredAt: draft.occurredAt,
                    transactionRecords: validationRecordSnapshots,
                    balanceIndex: validationBalanceIndex
                ) {
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
                    alertMessage = L10n.transactions.transactioneditor.theAmountExceedsTheAvailableCreditOn
                    return
                }
            } else if currentBalance - amountMinor < 0 {
                alertMessage = L10n.transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction
                return
            }

        case .transfer:
            switch draft.transferSubtype ?? .internalTransfer {
            case .internalTransfer:
                guard let sourceWallet = selectedSourceWallet else {
                    alertMessage = L10n.transactions.transactioneditor.chooseTheSourceWallet
                    return
                }
                
                let snapshot = TransactionWalletSnapshot(
                    id: sourceWallet.id,
                    kind: sourceWallet.kind,
                    openingBalanceMinor: sourceWallet.openingBalanceMinor
                )
                
                let currentBalance = validationBalanceIndex.balance(for: snapshot)
                
                if currentBalance - amountMinor < 0 {
                    alertMessage = L10n.transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction
                    return
                }

            case .debt:
                if draft.debtIntent == .lend || draft.debtIntent == .repay {
                    guard let sourceWallet = selectedSourceWallet else {
                        alertMessage = L10n.transactions.transactioneditor.chooseTheWalletUsedForThisDebt
                        return
                    }

                    let snapshot = TransactionWalletSnapshot(
                        id: sourceWallet.id,
                        kind: sourceWallet.kind,
                        openingBalanceMinor: sourceWallet.openingBalanceMinor
                    )
                    
                    let currentBalance = validationBalanceIndex.balance(for: snapshot)
                    
                    if currentBalance - amountMinor < 0 {
                        alertMessage = L10n.transactions.transactioneditor.insufficientWalletBalanceToPerformTheTransaction
                        return
                    }
                }
            case .familyTransfer:
                alertMessage = L10n.transactions.transactioneditor.couldnTCreateFamilyTransfer
                return
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
                alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
                return
            }

            guard let category = selectedCategory else {
                alertMessage = L10n.transactions.transactioneditor.chooseACategoryForThisTransaction
                return
            }

            guard category.isChildCategory else {
                alertMessage = L10n.transactions.transactioneditor.expensesAndIncomeMustUseAChild
                return
            }

            let walletOwnerUserID = walletOwnerUserID(for: sourceWallet)
            guard categoryOwnerUserID(for: category) == walletOwnerUserID else {
                alertMessage = L10n.transactions.transactioneditor.familyWalletsMustUseACategoryFrom
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
                    alertMessage = L10n.transactions.transactioneditor.chooseTheSourceWallet
                    return
                }

                guard let destinationWallet = selectedDestinationWallet else {
                    alertMessage = L10n.transactions.transactioneditor.chooseTheDestinationWallet
                    return
                }

                guard sourceWallet.id != destinationWallet.id else {
                    alertMessage = L10n.transactions.transactioneditor.sourceAndDestinationWalletsMustBeDifferent
                    return
                }

                transaction.title = draft.title.nilIfBlank ?? L10n.transactions.transactioneditor.internalTransfer
                transaction.sourceWallet = sourceWallet
                transaction.destinationWallet = destinationWallet
                transaction.category = nil
                transaction.transferSubtype = .internalTransfer
                transaction.debtIntent = nil
                transaction.counterpartyName = nil
                transaction.normalizedCounterpartyKey = nil
            case .familyTransfer:
                alertMessage = L10n.transactions.transactioneditor.couldnTCreateFamilyTransfer
                return
            case .debt:
                guard let sourceWallet = selectedSourceWallet else {
                    alertMessage = L10n.transactions.transactioneditor.chooseTheWalletUsedForThisDebt
                    return
                }

                guard let debtIntent = draft.debtIntent else {
                    alertMessage = L10n.transactions.transactioneditor.chooseADebtType
                    return
                }

                guard let counterpartyName = draft.counterpartyName.nilIfBlank,
                      let normalizedCounterpartyKey = TransactionLogic.normalizeCounterpartyName(counterpartyName)
                else {
                    alertMessage = L10n.transactions.transactioneditor.enterTheCounterpartyName
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

        do {
            try persistReceiptDraftIfNeeded(for: transaction)
        } catch {
            alertMessage = L10n.transactions.transactioneditor.couldnTSaveTheReceiptImage + " \(error.localizedDescription)"
            return
        }

        let canonicalOwnerUserID = walletOwnerUserID(for: transaction.sourceWallet)
        persist(
            transaction: transaction,
            completion: .savedTransaction,
            subjectUserIDOverride: canonicalOwnerUserID
        )
    }

    private func persistReceiptDraftIfNeeded(for transaction: LedgerTransaction) throws {
        guard shouldShowReceiptSection else { return }

        let store = TransactionReceiptImageStore()
        if let receiptDraft {
            guard receiptDraft.isChanged else { return }
            _ = try store.replaceReceipt(
                for: transaction.id,
                imageData: receiptDraft.imageData,
                thumbnailData: receiptDraft.thumbnailData,
                contentType: receiptDraft.contentType,
                context: modelContext,
                saveContext: false
            )
        } else if shouldDeleteReceiptOnSave {
            try store.deleteReceipt(
                for: transaction.id,
                context: modelContext,
                saveContext: false
            )
        }
    }

    private var transactionRecordSnapshots: [TransactionRecordSnapshot] {
        postedTransactions.map(\.planningRecordSnapshot)
    }

    private var dueOccurrenceSnapshots: [PlanningDueOccurrenceSnapshot] {
        storedDueOccurrences.map(\.planningSnapshot)
    }

    private func paidCreditCardStatement(
        for wallet: LedgerWallet,
        occurredAt: Date,
        transactionRecords: [TransactionRecordSnapshot]? = nil,
        balanceIndex: TransactionWalletBalanceIndex? = nil
    ) -> PlanningCreditCardStatementSnapshot? {
        let records = transactionRecords ?? transactionRecordSnapshots
        let resolvedBalanceIndex = balanceIndex ?? TransactionLogic.walletBalanceIndex(
            wallets: [
                TransactionWalletSnapshot(
                    id: wallet.id,
                    kind: wallet.kind,
                    openingBalanceMinor: wallet.openingBalanceMinor
                )
            ],
            records: records
        )

        guard let account = wallet.planningCreditCardSnapshot(balanceIndex: resolvedBalanceIndex) else {
            return nil
        }

        return PlanningLogic.paidCreditCardStatementForExpense(
            account: account,
            records: records,
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
        return L10n.transactions.transactioneditor.theValueStatementForThisCardHas(String(describing: statementMonth))
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
            alertMessage = L10n.transactions.transactioneditor.couldnTSaveThisTransactionRightNow + " \(error.localizedDescription)"
        }
    }

    private func familyCloudPushFailedMessage() -> String {
        let detail = sessionStore.lastErrorMessage?.nilIfBlank
        let base = L10n.transactions.transactioneditor.theTransactionWasSavedOnThisDevice
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

    private func walletSort(_ lhs: LedgerWallet, _ rhs: LedgerWallet) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func clearMismatchedCategoryForSelectedWallet() {
        guard let category = storedCategories.first(where: { $0.id == draft.categoryID }),
              !shouldShowCategory(category) else {
            return
        }
        draft.categoryID = nil
    }

    private func clearMismatchedWalletsForCurrentSubject() {
        let availableSourceWalletIDs: Set<UUID>
        let availableDestinationWalletIDs: Set<UUID>

        if draft.primaryKind == .transfer,
           draft.transferSubtype == .familyTransfer,
           !isFamilyTransferDetail {
            if draft.familyRecipientUserID == nil {
                availableSourceWalletIDs = []
                availableDestinationWalletIDs = []
            } else {
                availableSourceWalletIDs = Set(availableSourceWalletsForFamilyTransfer.map(\.id))
                availableDestinationWalletIDs = Set(availableDestinationWalletsForFamilyTransfer.map(\.id))
            }
        } else if draft.primaryKind == .transfer,
                  draft.transferSubtype == .internalTransfer {
            availableSourceWalletIDs = Set(availableSourceWalletsForTransfer.map(\.id))
            availableDestinationWalletIDs = Set(availableDestinationWalletsForTransfer.map(\.id))
        } else {
            let availableWalletIDs = Set(availableWallets.map(\.id))
            availableSourceWalletIDs = availableWalletIDs
            availableDestinationWalletIDs = availableWalletIDs
        }

        if let sourceWalletID = draft.sourceWalletID,
           !availableSourceWalletIDs.contains(sourceWalletID) {
            draft.sourceWalletID = nil
            draft.categoryID = nil
        }
        if let destinationWalletID = draft.destinationWalletID,
           !availableDestinationWalletIDs.contains(destinationWalletID) {
            draft.destinationWalletID = nil
        }
    }

    private func normalizeTransferDraftForSubtype() {
        guard draft.primaryKind == .transfer else {
            draft.familyRecipientUserID = nil
            return
        }

        switch draft.transferSubtype ?? .internalTransfer {
        case .internalTransfer:
            draft.debtIntent = nil
            draft.familyRecipientUserID = nil
        case .familyTransfer:
            draft.debtIntent = nil
            draft.counterpartyName = ""
        case .debt:
            draft.destinationWalletID = nil
            draft.familyRecipientUserID = nil
            if draft.debtIntent == nil {
                draft.debtIntent = .lend
            }
        }

        clearMismatchedWalletsForCurrentSubject()
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

private enum TransactionReceiptImageSource: String, Identifiable {
    case camera
    case photoLibrary

    var id: String { rawValue }

    var uiImagePickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            .camera
        case .photoLibrary:
            .photoLibrary
        }
    }
}

private struct TransactionReceiptDraft {
    let imageData: Data
    let thumbnailData: Data
    let contentType: String
    let previewImage: UIImage
    let thumbnailImage: UIImage
    let isChanged: Bool
}

private struct TransactionReceiptPreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum TransactionReceiptImageProcessor {
    static func makeDraft(from image: UIImage) -> TransactionReceiptDraft? {
        let previewImage = scaledImage(image, maxDimension: 1_800)
        let thumbnailImage = scaledImage(image, maxDimension: 240)

        guard
            let imageData = compressedJPEGData(for: previewImage),
            let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.68)
        else {
            return nil
        }

        return TransactionReceiptDraft(
            imageData: imageData,
            thumbnailData: thumbnailData,
            contentType: "image/jpeg",
            previewImage: previewImage,
            thumbnailImage: thumbnailImage,
            isChanged: true
        )
    }

    private static func compressedJPEGData(for image: UIImage) -> Data? {
        var quality: CGFloat = 0.74
        var data = image.jpegData(compressionQuality: quality)

        while let current = data, current.count > 3_800_000, quality > 0.42 {
            quality -= 0.08
            data = image.jpegData(compressionQuality: quality)
        }

        return data
    }

    private static func scaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestDimension = max(size.width, size.height)
        guard largestDimension > 0 else { return image }

        let scale = min(1, maxDimension / largestDimension)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: rendererFormat).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct TransactionReceiptImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let dismiss: DismissAction
        private let onImagePicked: (UIImage) -> Void

        init(dismiss: DismissAction, onImagePicked: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            dismiss()
            if let image {
                onImagePicked(image)
            }
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
    var familyRecipientUserID: UUID? = nil
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
            self.familyRecipientUserID = nil
            self.counterpartyName = transaction.counterpartyName ?? ""
        } else {
            let transferPreset = target.initialKind == .transfer ? target.transferPreset : nil
            let prefill = target.prefill
            self.primaryKind = target.initialKind
            self.transferSubtype = target.initialKind == .transfer
                ? (prefill?.lockedTransferSubtype ?? transferPreset?.transferSubtype ?? .internalTransfer)
                : nil
            self.debtIntent = target.initialKind == .transfer
                ? (prefill?.lockedDebtIntent ?? .lend)
                : nil
            self.title = prefill?.title ?? ""
            self.amountText = prefill?.amountMinor.map(String.init) ?? ""
            self.note = ""
            self.occurredAt = prefill?.occurredAt ?? .now
            self.sourceWalletID = prefill?.sourceWalletID ?? transferPreset?.sourceWalletID
            self.destinationWalletID = transferPreset?.destinationWalletID
            self.categoryID = prefill?.categoryID
            self.familyRecipientUserID = nil
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
