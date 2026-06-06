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
    let receiptPersistencePolicy: TransactionReceiptPersistencePolicy

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        self.initialKind = transaction.primaryKind
        self.quickCapture = false
        self.transferPreset = nil
        self.prefill = nil
        self.subjectUserIDOverride = nil
        self.startsReceiptScan = false
        self.receiptInitialSource = nil
        self.receiptPersistencePolicy = .persistLocally
    }

    init(
        initialKind: TransactionPrimaryKind,
        quickCapture: Bool = false,
        transferPreset: TransactionTransferPreset? = nil,
        prefill: TransactionEditorPrefill? = nil,
        subjectUserIDOverride: UUID? = nil,
        startsReceiptScan: Bool = false,
        receiptInitialSource: TransactionReceiptInitialSource? = nil,
        receiptPersistencePolicy: TransactionReceiptPersistencePolicy = .persistLocally
    ) {
        self.transaction = nil
        self.initialKind = initialKind
        self.quickCapture = quickCapture
        self.transferPreset = transferPreset
        self.prefill = prefill
        self.subjectUserIDOverride = subjectUserIDOverride
        self.startsReceiptScan = startsReceiptScan || receiptInitialSource != nil
        self.receiptInitialSource = receiptInitialSource ?? (startsReceiptScan ? .cameraPreferred : nil)
        self.receiptPersistencePolicy = receiptPersistencePolicy
    }
}

enum TransactionEditorCompletion: Equatable {
    case savedDraft
    case savedTransaction
}

private enum TransactionEditorFocusedField: Hashable {
    case title
    case counterparty
}

fileprivate enum BorrowDebtEntryMode: String, CaseIterable, Identifiable {
    case receiveIntoWallet
    case paidFor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receiveIntoWallet:
            L10n.transactions.transactioneditor.borrowReceiveIntoWallet
        case .paidFor:
            L10n.transactions.transactioneditor.borrowPaidFor
        }
    }
}

private struct FamilyTransferDraftPayload {
    let recipientUserID: UUID
    let sourceWalletID: UUID
    let destinationWalletID: UUID
    let amountMinor: Int64
    let destinationAmountMinor: Int64?
    let conversionMode: MistiaCurrencyConversionMode?
    let exchangeRateDecimalString: String?
    let exchangeRateProvider: String?
    let exchangeRateDate: String?
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

private struct CurrencyConversionResolution {
    let isValid: Bool
    let amountMinor: Int64?
    let mode: MistiaCurrencyConversionMode
    let rateDecimalString: String?
    let rateProvider: String?
    let rateDate: String?

    static let sameCurrency = CurrencyConversionResolution(
        isValid: true,
        amountMinor: nil,
        mode: .appRate,
        rateDecimalString: nil,
        rateProvider: nil,
        rateDate: nil
    )
}

private struct TransactionEditorRenderContext {
    let availableWallets: [LedgerWallet]
    let availableDebtWallets: [LedgerWallet]
    let availableSourceWalletsForTransfer: [LedgerWallet]
    let availableDestinationWalletsForTransfer: [LedgerWallet]
    let availableFamilyTransferMembers: [FamilyMember]
    let availableSourceWalletsForFamilyTransfer: [LedgerWallet]
    let availableDestinationWalletsForFamilyTransfer: [LedgerWallet]
    let selectedCategory: TransactionCategory?
    let selectedCategoryLabel: String
    let shouldShowMissingWalletsState: Bool
    let shouldShowConversionSection: Bool
    let shouldShowDestinationAmountInput: Bool
    let walletLabelsByID: [UUID: String]
    let ownerWalletLabelsByID: [UUID: String]
}

struct TransactionEditorSheet: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @AppStorage(MistiaCurrencySettings.StorageKey.primaryCurrencyCode) private var primaryCurrencyCode = "JPY"

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
    @State private var cachedCounterpartySuggestions: [TransactionTitleSuggestion] = []
    @State private var cachedSuggestionRecordSnapshots: [TransactionRecordSnapshot] = []
    @State private var titleSuggestionRefreshTask: Task<Void, Never>?
    @State private var counterpartySuggestionRefreshTask: Task<Void, Never>?
    @State private var suppressTitleSuggestions = false
    @State private var suppressCounterpartySuggestions = false
    @State private var isApplyingTitleSuggestion = false
    @State private var isApplyingCounterpartySuggestion = false
    @State private var isSaving = false
    @State private var receiptDraft: TransactionReceiptDraft?
    @State private var shouldDeleteReceiptOnSave = false
    @State private var receiptImageSource: TransactionReceiptImageSource?
    @State private var receiptPreview: TransactionReceiptPreviewItem?
    @State private var receiptLoadTask: Task<Void, Never>?
    @State private var receiptProcessingTask: Task<Void, Never>?
    @State private var isProcessingReceiptImage = false
    @State private var isAnalyzingReceipt = false
    @State private var receiptAnalysisQuota: ReceiptAnalysisQuota?
    @State private var receiptAnalysisSource: TransactionReceiptAnalysisSource?
    @State private var pendingReceiptAnalysisSource: TransactionReceiptAnalysisSource?
    @State private var didApplyReceiptAnalysisToCurrentDraft = false
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

        let transactionSnapshot = transaction.snapshot
        if (transaction.primaryKind == .expense || TransactionLogic.isCreditCardDebtLending(transactionSnapshot)),
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
            transaction: transactionSnapshot,
            allTransactions: postedTransactions.lazy.map(\.snapshot)
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

    private var isExistingDebtTransaction: Bool {
        guard let transaction = target.transaction else { return false }
        return transaction.primaryKind == .transfer && transaction.transferSubtype == .debt
    }

    var body: some View {
        let isLockedByStatement = self.isLockedByStatement
        let isReadOnlyDetail = isLockedByStatement || isFamilyTransferDetail
        let areEditorControlsDisabled = isReadOnlyDetail || isSaving || isProcessingReceiptImage
        let renderContext = makeRenderContext()

        NavigationStack {
            Form {
                if isLockedByStatement {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "creditcard.circle.fill")
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
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "#65DDB8"))
                                .padding(8)
                                .background(Color(hex: "#65DDB8").opacity(0.12))
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
                        .disabled(isSaving || isProcessingReceiptImage)
                } else {
                    fullEditorContent(renderContext: renderContext)
                        .disabled(areEditorControlsDisabled)
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
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !isAdjustment && !isLockedByStatement && !isFamilyTransferDetail {
                        Button {
                            save()
                        } label: {
                            if isSaving || isProcessingReceiptImage {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(MistiaAccent.checkmarkPurple.color)
                                    .frame(width: 30, height: 30)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(MistiaAccent.checkmarkPurple.color)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(Color(red: 0.43, green: 0.23, blue: 0.76))
                        .disabled(isSaving || isProcessingReceiptImage)
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
            scheduleCounterpartySuggestionsRefresh()
            normalizeTransferDraftForSubtype()
        }
        .onChange(of: draft.familyRecipientUserID) { _, _ in
            clearMismatchedWalletsForCurrentSubject()
        }
        .onChange(of: familyContextStore.selectedSubjectUserID) { _, _ in
            refreshSuggestionRecordSnapshots()
            clearMismatchedWalletsForCurrentSubject()
            clearMismatchedCategoryForSelectedWallet()
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                refreshSuggestionRecordSnapshots()
                loadReceiptDraftIfNeeded()
                applyReceiptPrefillIfNeeded()
                scheduleTitleSuggestionsRefresh()
                scheduleCounterpartySuggestionsRefresh()
                presentInitialReceiptScannerIfNeeded()
            }
        }
        .onDisappear {
            titleSuggestionRefreshTask?.cancel()
            titleSuggestionRefreshTask = nil
            counterpartySuggestionRefreshTask?.cancel()
            counterpartySuggestionRefreshTask = nil
            receiptLoadTask?.cancel()
            receiptLoadTask = nil
            receiptProcessingTask?.cancel()
            receiptProcessingTask = nil
            isProcessingReceiptImage = false
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
    private func fullEditorContent(renderContext: TransactionEditorRenderContext) -> some View {
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
                        set: {
                            bindableDraft.debtIntent = $0
                            if $0 != .borrow {
                                bindableDraft.borrowDebtEntryMode = .receiveIntoWallet
                                bindableDraft.paidForCountsAsExpense = false
                            }
                            clearMismatchedWalletsForCurrentSubject()
                        }
                    )) {
                        ForEach(debtIntentOptions, id: \.self) { intent in
                            Text(intent.title).tag(intent)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(target.prefill?.lockedDebtIntent != nil || isExistingDebtTransaction)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if draft.debtIntent == .borrow {
                        MistiaNativeSegmentedControl(
                            selection: Binding(
                                get: { bindableDraft.borrowDebtEntryMode },
                                set: { mode in
                                    bindableDraft.borrowDebtEntryMode = mode
                                    if mode == .paidFor {
                                        bindableDraft.sourceWalletID = nil
                                    } else {
                                        bindableDraft.paidForCountsAsExpense = false
                                        bindableDraft.categoryID = nil
                                    }
                                    clearMismatchedWalletsForCurrentSubject()
                                }
                            ),
                            options: BorrowDebtEntryMode.allCases,
                            title: { $0.title }
                        )
                        .disabled(isExistingDebtTransaction)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }

            if renderContext.shouldShowMissingWalletsState {
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

            if renderContext.shouldShowConversionSection {
                Section(L10n.transactions.transactioneditor.conversion) {
                    Picker(L10n.transactions.transactioneditor.conversion, selection: $bindableDraft.conversionModeRawValue) {
                        Text(L10n.transactions.transactioneditor.useAppRate).tag(MistiaCurrencyConversionMode.appRate.rawValue)
                        Text(L10n.transactions.transactioneditor.enterManually).tag(MistiaCurrencyConversionMode.manual.rawValue)
                    }
                    .pickerStyle(.segmented)

                    if selectedConversionMode == .manual {
                        if renderContext.shouldShowDestinationAmountInput {
                            TextField(L10n.transactions.transactioneditor.destinationAmount, text: $bindableDraft.destinationAmountText)
                                .keyboardType(.numberPad)
                        } else {
                            TextField(L10n.transactions.transactioneditor.convertedAmount, text: $bindableDraft.reportingAmountText)
                                .keyboardType(.numberPad)
                        }
                    }
                }
            }

            switch draft.primaryKind {
            case .expense, .income:
                Section(L10n.transactions.transactioneditor.fundingSource) {
                    Picker(L10n.transactions.transactioneditor.wallet, selection: $draft.sourceWalletID) {
                        Text(L10n.transactions.transactioneditor.chooseWallet).tag(Optional<UUID>.none)
                        ForEach(renderContext.availableWallets) { wallet in
                            Text(walletPickerTitle(for: wallet, in: renderContext)).tag(Optional(wallet.id))
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
                            Text(renderContext.selectedCategoryLabel)
                                .foregroundStyle(renderContext.selectedCategory == nil ? .tertiary : .secondary)
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
                            ForEach(renderContext.availableSourceWalletsForTransfer) { wallet in
                                Text(walletPickerTitle(for: wallet, in: renderContext)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(L10n.transactions.transactioneditor.toWallet, selection: $draft.destinationWalletID) {
                            Text(L10n.transactions.transactioneditor.chooseDestination).tag(Optional<UUID>.none)
                            ForEach(renderContext.availableDestinationWalletsForTransfer) { wallet in
                                Text(walletPickerTitle(for: wallet, in: renderContext)).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else if draft.transferSubtype == .familyTransfer, !isFamilyTransferDetail {
                    Section(L10n.shared.corelogic.financeenums.family) {
                        Picker(L10n.transactions.transactioneditor.familyMember, selection: $draft.familyRecipientUserID) {
                            Text(L10n.transactions.transactioneditor.chooseFamilyMember).tag(Optional<UUID>.none)
                            ForEach(renderContext.availableFamilyTransferMembers) { member in
                                Text(member.displayName).tag(Optional(member.userID))
                            }
                        }
                        .pickerStyle(.menu)

                        if draft.familyRecipientUserID != nil {
                            Picker(L10n.transactions.transactioneditor.fromWallet, selection: $draft.sourceWalletID) {
                                Text(L10n.transactions.transactioneditor.chooseSource).tag(Optional<UUID>.none)
                                ForEach(renderContext.availableSourceWalletsForFamilyTransfer) { wallet in
                                    Text(walletPickerTitle(for: wallet, in: renderContext, labelMode: .alwaysShowsOwner)).tag(Optional(wallet.id))
                                }
                            }
                            .pickerStyle(.menu)

                            Picker(L10n.transactions.transactioneditor.toWallet, selection: $draft.destinationWalletID) {
                                Text(L10n.transactions.transactioneditor.chooseDestination).tag(Optional<UUID>.none)
                                ForEach(renderContext.availableDestinationWalletsForFamilyTransfer) { wallet in
                                    Text(walletPickerTitle(for: wallet, in: renderContext, labelMode: .alwaysShowsOwner)).tag(Optional(wallet.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if draft.familyRecipientUserID != nil && renderContext.availableDestinationWalletsForFamilyTransfer.isEmpty {
                            Text(L10n.transactions.transactioneditor.noUsableWalletsForThisMember)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section(L10n.transactions.transactioneditor.counterparty) {
                        if draft.debtIntent == .borrow,
                           draft.borrowDebtEntryMode == .paidFor {
                            Picker(L10n.transactions.transactioneditor.currency, selection: $draft.paidForCurrencyCode) {
                                ForEach(MistiaCurrencySettings.enabledCurrencyCodes(), id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .pickerStyle(.menu)

                            Toggle(L10n.transactions.transactioneditor.countAsExpense, isOn: Binding(
                                get: { bindableDraft.paidForCountsAsExpense },
                                set: { isOn in
                                    bindableDraft.paidForCountsAsExpense = isOn
                                    if !isOn {
                                        bindableDraft.categoryID = nil
                                    }
                                }
                            ))

                            if draft.paidForCountsAsExpense {
                                Button {
                                    showsCategoryPicker = true
                                } label: {
                                    HStack {
                                        Text(L10n.transactions.transactioneditor.category)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(renderContext.selectedCategoryLabel)
                                            .foregroundStyle(renderContext.selectedCategory == nil ? .tertiary : .secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 20))
                            }
                        } else {
                            Picker(L10n.transactions.transactioneditor.walletUsed, selection: $draft.sourceWalletID) {
                                Text(L10n.transactions.transactioneditor.chooseWallet).tag(Optional<UUID>.none)
                                ForEach(renderContext.availableDebtWallets) { wallet in
                                    Text(walletPickerTitle(for: wallet, in: renderContext)).tag(Optional(wallet.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }

                    TextField(
                        L10n.transactions.transactioneditor.counterpartyName,
                        text: $bindableDraft.counterpartyName
                    )
                    .focused($focusedField, equals: .counterparty)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: focusedField) { _, newValue in
                        if newValue == .counterparty {
                            suppressCounterpartySuggestions = false
                        }
                        scheduleCounterpartySuggestionsRefresh()
                    }
                    .onChange(of: bindableDraft.counterpartyName) { _, _ in
                        if isApplyingCounterpartySuggestion {
                            isApplyingCounterpartySuggestion = false
                            cachedCounterpartySuggestions = []
                        } else {
                            suppressCounterpartySuggestions = false
                            scheduleCounterpartySuggestionsRefresh()
                        }
                    }

                    if shouldShowCounterpartySuggestions {
                        counterpartySuggestionsPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
                MistiaDestructiveActionSection(
                    buttonTitle: L10n.transactions.transactioneditor.archiveTransaction,
                    descriptionText: L10n.transactions.transactioneditor.archivedTransactionsWillNoLongerAppearIn,
                    popupMessage: L10n.transactions.transactioneditor.thisTransactionWillBeArchivedArchivedTransactions,
                    confirmationButtonTitle: L10n.common.archive
                ) {
                    archiveTransaction()
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

    private func makeRenderContext() -> TransactionEditorRenderContext {
        let access = walletPickerAccess
        let currentSelfUserID = access.currentSelfUserID
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        let transactionOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .transaction)
        let selectedSourceWallet = storedWallets.first(where: { $0.id == draft.sourceWalletID })
        let selectedDestinationWallet = storedWallets.first(where: { $0.id == draft.destinationWalletID })

        func ownerUserID(for wallet: LedgerWallet?) -> UUID? {
            guard let wallet else { return nil }
            return access.walletOwnerUserID(for: wallet)
        }

        func ownerUserID(for transaction: LedgerTransaction) -> UUID? {
            transactionOwnerMap[transaction.id]
                ?? ownerUserID(for: transaction.sourceWallet)
                ?? ownerUserID(for: transaction.destinationWallet)
                ?? currentSelfUserID
        }

        let activeWalletOwnerUserID: UUID?
        if let transaction = target.transaction {
            activeWalletOwnerUserID = ownerUserID(for: transaction)
        } else {
            activeWalletOwnerUserID = target.subjectUserIDOverride
                ?? familyContextStore.selectedSubjectUserID
                ?? currentSelfUserID
        }

        let preferredWalletIDs = Set([
            target.transaction?.sourceWallet?.id,
            target.transaction?.destinationWallet?.id
        ].compactMap { $0 })
        let availableWallets = access.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            targetOwnerUserID: activeWalletOwnerUserID,
            excludesCreditCards: draft.primaryKind == .income
        )
        let availableDebtWallets = availableWallets.filter { wallet in
            wallet.kind != .creditCard || TransactionLogic.debtIntentAllowsCreditCardWallet(draft.debtIntent)
        }
        let availableSourceWalletsForTransfer = availableWallets.filter { $0.kind != .creditCard }
        let availableDestinationWalletsForTransfer = availableWallets
        let availableFamilyTransferMembers: [FamilyMember]
        if let currentSelfUserID {
            availableFamilyTransferMembers = familyContextStore.members
                .filter { $0.userID != currentSelfUserID }
                .sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
        } else {
            availableFamilyTransferMembers = []
        }
        let availableSourceWalletsForFamilyTransfer = currentSelfUserID.map { userID in
            access.availableWallets(
                from: storedWallets,
                targetOwnerUserID: userID,
                excludesCreditCards: true
            )
        } ?? []
        let availableDestinationWalletsForFamilyTransfer = draft.familyRecipientUserID.map { recipientUserID in
            access.availableWallets(
                from: storedWallets,
                targetOwnerUserID: recipientUserID
            )
        } ?? []

        let selectedWalletOwnerUserID = ownerUserID(for: selectedSourceWallet)
        let effectiveCategoryOwnerUserIDs: Set<UUID>
        if let selectedWalletOwnerUserID {
            effectiveCategoryOwnerUserIDs = [selectedWalletOwnerUserID]
        } else if let transaction = target.transaction,
                  let ownerUserID = ownerUserID(for: transaction) {
            effectiveCategoryOwnerUserIDs = [ownerUserID]
        } else if let subjectUserID = target.subjectUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? currentSelfUserID {
            effectiveCategoryOwnerUserIDs = [subjectUserID]
        } else if target.transaction == nil {
            effectiveCategoryOwnerUserIDs = []
        } else {
            let operable = familyContextStore.operableTargetUserIDs
            effectiveCategoryOwnerUserIDs = operable.isEmpty
                ? currentSelfUserID.map { Set([$0]) } ?? []
                : operable
        }
        let categoryOwnerUserIDs = selectedWalletOwnerUserID.map { Set([$0]) } ?? effectiveCategoryOwnerUserIDs

        let availableCategories = storedCategories
            .filter { category in
                guard let ownerUserID = categoryOwnerMap[category.id] ?? currentSelfUserID,
                      categoryOwnerUserIDs.contains(ownerUserID) else {
                    return false
                }
                return category.kind == selectedCategoryKind
                    && category.isChildCategory
                    && !category.isBalanceAdjustmentSystemCategory
                    && ((category.deletedAt == nil && !category.isArchived) || category.id == target.transaction?.category?.id)
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
        let selectedCategory = availableCategories.first(where: { $0.id == draft.categoryID })
        let selectedCategoryLabel: String
        if let selectedCategory {
            let parentName = selectedCategory.parentCategory?.localizedDisplayName ?? selectedCategory.branchDisplayName
            selectedCategoryLabel = "\(parentName) / \(selectedCategory.localizedDisplayName)"
        } else {
            selectedCategoryLabel = L10n.transactions.transactioneditor.chooseCategory
        }

        let sourceCurrencyCode = selectedSourceWallet?.currencyCode ?? "JPY"
        let destinationCurrencyCode = selectedDestinationWallet?.currencyCode
        let shouldShowTransferConversionSection = draft.primaryKind == .transfer
            && (draft.transferSubtype == .internalTransfer || draft.transferSubtype == .familyTransfer)
            && destinationCurrencyCode != nil
            && MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode) != MistiaCurrencyLogic.normalizedCode(destinationCurrencyCode ?? sourceCurrencyCode)
        let shouldShowDestinationAmountInput = shouldShowTransferConversionSection && selectedConversionMode == .manual
        let shouldShowConversionSection = if draft.primaryKind == .expense || draft.primaryKind == .income {
            MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode) != MistiaCurrencyLogic.normalizedCode(primaryCurrencyCode)
        } else {
            shouldShowTransferConversionSection
        }
        let hasNoAvailableWallets: Bool
        if draft.primaryKind == .transfer,
           draft.transferSubtype == .debt,
           draft.debtIntent == .borrow,
           draft.borrowDebtEntryMode == .paidFor {
            hasNoAvailableWallets = false
        } else if draft.primaryKind == .transfer, draft.transferSubtype == .debt {
            hasNoAvailableWallets = availableDebtWallets.isEmpty
        } else {
            hasNoAvailableWallets = availableWallets.isEmpty
        }
        let shouldShowMissingWalletsState = !target.quickCapture && hasNoAvailableWallets

        var walletsByID: [UUID: LedgerWallet] = [:]
        for wallet in availableWallets
            + availableSourceWalletsForTransfer
            + availableDestinationWalletsForTransfer
            + availableSourceWalletsForFamilyTransfer
            + availableDestinationWalletsForFamilyTransfer {
            walletsByID[wallet.id] = wallet
        }

        let walletLabelsByID = Dictionary(uniqueKeysWithValues: walletsByID.values.map { wallet in
            (wallet.id, access.title(for: wallet))
        })
        let ownerWalletLabelsByID = Dictionary(uniqueKeysWithValues: walletsByID.values.map { wallet in
            (wallet.id, access.title(for: wallet, labelMode: .alwaysShowsOwner))
        })

        return TransactionEditorRenderContext(
            availableWallets: availableWallets,
            availableDebtWallets: availableDebtWallets,
            availableSourceWalletsForTransfer: availableSourceWalletsForTransfer,
            availableDestinationWalletsForTransfer: availableDestinationWalletsForTransfer,
            availableFamilyTransferMembers: availableFamilyTransferMembers,
            availableSourceWalletsForFamilyTransfer: availableSourceWalletsForFamilyTransfer,
            availableDestinationWalletsForFamilyTransfer: availableDestinationWalletsForFamilyTransfer,
            selectedCategory: selectedCategory,
            selectedCategoryLabel: selectedCategoryLabel,
            shouldShowMissingWalletsState: shouldShowMissingWalletsState,
            shouldShowConversionSection: shouldShowConversionSection,
            shouldShowDestinationAmountInput: shouldShowDestinationAmountInput,
            walletLabelsByID: walletLabelsByID,
            ownerWalletLabelsByID: ownerWalletLabelsByID
        )
    }

    private var availableWallets: [LedgerWallet] {
        let preferredWalletIDs = Set([
            target.transaction?.sourceWallet?.id,
            target.transaction?.destinationWallet?.id
        ].compactMap { $0 })
        return walletPickerAccess.availableWallets(
            from: storedWallets,
            preferredWalletIDs: preferredWalletIDs,
            targetOwnerUserID: activeWalletPickerOwnerUserID,
            excludesCreditCards: draft.primaryKind == .income
        )
    }

    private var availableWalletsForIncome: [LedgerWallet] {
        availableWallets.filter { $0.kind != .creditCard }
    }

    private var availableWalletsForDebtIntent: [LedgerWallet] {
        availableWallets.filter { wallet in
            wallet.kind != .creditCard || TransactionLogic.debtIntentAllowsCreditCardWallet(draft.debtIntent)
        }
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
        if isExistingDebtTransaction {
            return [.debt]
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
        if isExistingDebtTransaction {
            return subtype == .debt
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
            await familyContextStore.refreshFamilyMetadata(sessionStore: sessionStore)
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
        if isExistingDebtTransaction, let existingDebtIntent = target.transaction?.debtIntent {
            return [existingDebtIntent]
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
        return walletPickerAccess.availableWallets(
            from: storedWallets,
            targetOwnerUserID: currentSelfUserID,
            excludesCreditCards: true
        )
    }

    private var availableDestinationWalletsForFamilyTransfer: [LedgerWallet] {
        guard let recipientUserID = draft.familyRecipientUserID else { return [] }
        return walletPickerAccess.availableWallets(
            from: storedWallets,
            targetOwnerUserID: recipientUserID
        )
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

    private var counterpartySuggestions: [TransactionTitleSuggestion] {
        cachedCounterpartySuggestions
    }

    private var shouldShowTitleSuggestions: Bool {
        focusedField == .title && !suppressTitleSuggestions && !cachedTitleSuggestions.isEmpty
    }

    private var shouldShowCounterpartySuggestions: Bool {
        focusedField == .counterparty
            && draft.primaryKind == .transfer
            && draft.transferSubtype == .debt
            && !suppressCounterpartySuggestions
            && !cachedCounterpartySuggestions.isEmpty
    }

    private func scheduleTitleSuggestionsRefresh() {
        titleSuggestionRefreshTask?.cancel()
        titleSuggestionRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            refreshTitleSuggestionsNow()
        }
    }

    private func refreshSuggestionRecordSnapshots() {
        cachedSuggestionRecordSnapshots = Array(
            visiblePostedTransactions
                .prefix(500)
                .map(\.snapshot)
        )
    }

    private func refreshTitleSuggestionsNow() {
        guard titleFieldPlaceholder != nil,
              focusedField == .title,
              !suppressTitleSuggestions,
              draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            cachedTitleSuggestions = []
            return
        }
        if cachedSuggestionRecordSnapshots.isEmpty {
            refreshSuggestionRecordSnapshots()
        }

        cachedTitleSuggestions = TransactionLogic.titleSuggestions(
            from: cachedSuggestionRecordSnapshots,
            query: draft.title,
            primaryKind: draft.primaryKind,
            transferSubtype: draft.primaryKind == .transfer ? draft.transferSubtype : nil,
            excludingTransactionID: target.transaction?.id,
            limit: 5
        )
    }

    private func scheduleCounterpartySuggestionsRefresh() {
        counterpartySuggestionRefreshTask?.cancel()
        counterpartySuggestionRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            refreshCounterpartySuggestionsNow()
        }
    }

    private func refreshCounterpartySuggestionsNow() {
        guard focusedField == .counterparty,
              draft.primaryKind == .transfer,
              draft.transferSubtype == .debt,
              !suppressCounterpartySuggestions,
              draft.counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            cachedCounterpartySuggestions = []
            return
        }
        if cachedSuggestionRecordSnapshots.isEmpty {
            refreshSuggestionRecordSnapshots()
        }

        cachedCounterpartySuggestions = TransactionLogic.counterpartySuggestions(
            from: cachedSuggestionRecordSnapshots,
            query: draft.counterpartyName,
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

    private var isPaidForBorrowDraft: Bool {
        draft.primaryKind == .transfer
            && draft.transferSubtype == .debt
            && draft.debtIntent == .borrow
            && draft.borrowDebtEntryMode == .paidFor
    }

    private var paidForCurrencyCode: String {
        MistiaCurrencyLogic.normalizedCode(draft.paidForCurrencyCode)
    }

    private var selectedConversionMode: MistiaCurrencyConversionMode {
        MistiaCurrencyConversionMode(rawValue: draft.conversionModeRawValue) ?? .appRate
    }

    private var sourceCurrencyCodeForDraft: String {
        if isPaidForBorrowDraft {
            return paidForCurrencyCode
        }
        return selectedSourceWallet?.currencyCode ?? "JPY"
    }

    private var destinationCurrencyCodeForDraft: String? {
        selectedDestinationWallet?.currencyCode
    }

    private var shouldShowTransferConversionSection: Bool {
        guard draft.primaryKind == .transfer,
              draft.transferSubtype == .internalTransfer || draft.transferSubtype == .familyTransfer,
              let destinationCurrencyCodeForDraft
        else {
            return false
        }
        return MistiaCurrencyLogic.normalizedCode(sourceCurrencyCodeForDraft) != MistiaCurrencyLogic.normalizedCode(destinationCurrencyCodeForDraft)
    }

    private var shouldShowDestinationAmountInput: Bool {
        shouldShowTransferConversionSection && selectedConversionMode == .manual
    }

    private var shouldShowConversionSection: Bool {
        if draft.primaryKind == .expense || draft.primaryKind == .income {
            return MistiaCurrencyLogic.normalizedCode(sourceCurrencyCodeForDraft) != MistiaCurrencyLogic.normalizedCode(primaryCurrencyCode)
        }

        return shouldShowTransferConversionSection
    }

    private var selectedCategoryLabel: String {
        guard let selectedCategory else {
            return L10n.transactions.transactioneditor.chooseCategory
        }

        let parentName = selectedCategory.parentCategory?.localizedDisplayName ?? selectedCategory.branchDisplayName
        return "\(parentName) / \(selectedCategory.localizedDisplayName)"
    }

    private var shouldShowReceiptSection: Bool {
        isReceiptFeatureAvailable && (draft.primaryKind == .expense || draft.primaryKind == .income)
    }

    private var isReceiptFeatureAvailable: Bool {
        true
    }

    private var effectiveReceiptPersistencePolicy: TransactionReceiptPersistencePolicy {
        if let transaction = target.transaction {
            return TransactionReceiptPersistencePolicy.policy(
                ownerUserID: receiptOwnerUserID(for: transaction),
                activeLocalProfileUserID: sessionStore.activeLocalProfileUserID
            )
        }

        return target.receiptPersistencePolicy
    }

    private var shouldPersistReceiptImage: Bool {
        effectiveReceiptPersistencePolicy.canPersistReceiptImage
    }

    private var shouldDeleteStoredReceiptOnSave: Bool {
        effectiveReceiptPersistencePolicy.deletesStoredReceiptOnSave
    }

    private var receiptAnalysisControlState: TransactionReceiptAnalysisControlState {
        TransactionReceiptAnalysisControlState.state(
            for: receiptAnalysisSource,
            hasReceiptDraft: receiptDraft != nil,
            hasAppliedAnalysis: didApplyReceiptAnalysisToCurrentDraft,
            isAnalyzing: isAnalyzingReceipt
        )
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

                    HStack(spacing: 14) {
                        if receiptAnalysisControlState != .hidden {
                            Button {
                                analyzeCurrentReceiptDraft()
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(receiptAnalysisControlState == .enabled ? Color.orange : .secondary)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.borderless)
                            .disabled(receiptAnalysisControlState != .enabled)
                            .accessibilityLabel(L10n.transactions.aibill.analyze)
                        }

                        Button(role: .destructive) {
                            removeReceiptDraft()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.transactions.transactioneditor.removeImage)
                    }
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
                presentReceiptImageSource(.camera, analysisSource: .modalPicker)
            } label: {
                Label(
                    L10n.transactions.transactioneditor.takePhoto,
                    systemImage: "camera"
                )
            }
        }

        Button {
            presentReceiptImageSource(.photoLibrary, analysisSource: .modalPicker)
        } label: {
            Label(
                L10n.transactions.transactioneditor.chooseFromPhotos,
                systemImage: "photo"
            )
        }
    }

    private func presentReceiptImageSource(
        _ source: TransactionReceiptImageSource,
        analysisSource: TransactionReceiptAnalysisSource
    ) {
        pendingReceiptAnalysisSource = analysisSource
        receiptImageSource = source
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

        let destinationAmount = resolvedDestinationAmount(
            amountMinor: amountMinor,
            sourceCurrencyCode: sourceWallet.currencyCode,
            destinationCurrencyCode: selectedDestinationWallet?.currencyCode ?? sourceWallet.currencyCode
        )
        guard destinationAmount.isValid else { return nil }

        return FamilyTransferDraftPayload(
            recipientUserID: recipientUserID,
            sourceWalletID: sourceWalletID,
            destinationWalletID: destinationWalletID,
            amountMinor: amountMinor,
            destinationAmountMinor: destinationAmount.amountMinor,
            conversionMode: destinationAmount.amountMinor == nil ? nil : destinationAmount.mode,
            exchangeRateDecimalString: destinationAmount.rateDecimalString,
            exchangeRateProvider: destinationAmount.rateProvider,
            exchangeRateDate: destinationAmount.rateDate,
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
                destinationAmountMinor: payload.destinationAmountMinor,
                conversionMode: payload.conversionMode,
                exchangeRateDecimalString: payload.exchangeRateDecimalString,
                exchangeRateProvider: payload.exchangeRateProvider,
                exchangeRateDate: payload.exchangeRateDate,
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

        guard isReceiptFeatureAvailable, shouldPersistReceiptImage else { return }
        guard let transaction = target.transaction else { return }

        do {
            let store = TransactionReceiptImageStore()
            guard let receipt = try store.receipt(for: transaction.id, context: modelContext) else { return }
            let imageURL = store.url(forFileName: receipt.imageFileName)
            let thumbnailURL = store.url(forFileName: receipt.thumbnailFileName)
            let contentType = receipt.contentType

            receiptLoadTask?.cancel()
            receiptLoadTask = Task { @MainActor in
                let draftResult = await Task.detached(priority: .utility) {
                    do {
                        let imageData = try Data(contentsOf: imageURL)
                        let thumbnailData = try Data(contentsOf: thumbnailURL)
                        guard let draft = TransactionReceiptImageProcessor.makeDraft(
                            imageData: imageData,
                            thumbnailData: thumbnailData,
                            contentType: contentType,
                            isChanged: false
                        ) else {
                            return Result<TransactionReceiptDraft, Error>.failure(CocoaError(.fileReadCorruptFile))
                        }
                        return Result<TransactionReceiptDraft, Error>.success(draft)
                    } catch {
                        return Result<TransactionReceiptDraft, Error>.failure(error)
                    }
                }.value

                guard !Task.isCancelled else { return }
                receiptLoadTask = nil

                switch draftResult {
                case .success(let draft):
                    receiptDraft = draft
                    receiptAnalysisSource = .prefill
                    didApplyReceiptAnalysisToCurrentDraft = false
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
              isReceiptFeatureAvailable,
              let receiptInitialSource = target.receiptInitialSource,
              target.transaction == nil,
              !didAutoPresentReceiptScanner else {
            return
        }

        didAutoPresentReceiptScanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let source: TransactionReceiptImageSource
            switch receiptInitialSource {
            case .cameraPreferred:
                source = UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? .camera
                    : .photoLibrary
            case .camera:
                source = UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? .camera
                    : .photoLibrary
            case .photoLibrary:
                source = .photoLibrary
            }
            presentReceiptImageSource(source, analysisSource: .initialScanner)
        }
    }

    private func applyReceiptPrefillIfNeeded() {
        guard !didApplyReceiptPrefill,
              isReceiptFeatureAvailable,
              target.transaction == nil,
              receiptDraft == nil,
              let receiptImage = target.prefill?.receiptImage else {
            return
        }

        didApplyReceiptPrefill = true
        processReceiptImage(receiptImage, analysisSource: .prefill)
    }

    private func handlePickedReceiptImage(_ image: UIImage) {
        guard isReceiptFeatureAvailable else { return }
        let analysisSource = pendingReceiptAnalysisSource ?? .modalPicker
        pendingReceiptAnalysisSource = nil
        processReceiptImage(image, analysisSource: analysisSource)
    }

    private func processReceiptImage(_ image: UIImage, analysisSource: TransactionReceiptAnalysisSource) {
        guard isReceiptFeatureAvailable else { return }
        receiptProcessingTask?.cancel()
        isProcessingReceiptImage = true
        receiptProcessingTask = Task { @MainActor in
            let draft = await Task.detached(priority: .userInitiated) {
                TransactionReceiptImageProcessor.makeDraft(from: image)
            }.value

            guard !Task.isCancelled else { return }
            receiptProcessingTask = nil
            isProcessingReceiptImage = false

            guard let draft else {
                alertMessage = L10n.transactions.transactioneditor.couldnTProcessThisReceiptImage
                return
            }

            applyProcessedReceiptDraft(draft, analysisSource: analysisSource)
        }
    }

    private func applyProcessedReceiptDraft(
        _ draft: TransactionReceiptDraft,
        analysisSource: TransactionReceiptAnalysisSource
    ) {
        receiptDraft = draft
        receiptAnalysisSource = analysisSource
        receiptAnalysisQuota = nil
        didApplyReceiptAnalysisToCurrentDraft = false
        shouldDeleteReceiptOnSave = false
        if analysisSource.shouldAnalyzeImmediately {
            analyzeCurrentReceiptDraft()
        }
    }

    private func removeReceiptDraft() {
        receiptDraft = nil
        receiptAnalysisQuota = nil
        receiptAnalysisSource = nil
        pendingReceiptAnalysisSource = nil
        didApplyReceiptAnalysisToCurrentDraft = false
        shouldDeleteReceiptOnSave = target.transaction != nil && shouldPersistReceiptImage
    }

    private func analyzeCurrentReceiptDraft() {
        guard isReceiptFeatureAvailable,
              !isAnalyzingReceipt,
              !didApplyReceiptAnalysisToCurrentDraft,
              let receiptDraft else { return }

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
                let payload = await receiptAnalysisPayload(for: receiptDraft)
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

    private func receiptAnalysisPayload(for receiptDraft: TransactionReceiptDraft) async -> ReceiptAnalysisRequestPayload {
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
        let imageData = receiptDraft.imageData
        let contentType = receiptDraft.contentType
        let localeIdentifier = Locale.current.identifier
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier

        let imageBase64 = await Task.detached(priority: .userInitiated) {
            imageData.base64EncodedString()
        }.value

        return ReceiptAnalysisRequestPayload(
            imageBase64: imageBase64,
            mimeType: contentType,
            localeIdentifier: localeIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
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

        didApplyReceiptAnalysisToCurrentDraft = true
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

    private func resolvedReportingAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String
    ) -> CurrencyConversionResolution {
        guard MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode) != MistiaCurrencyLogic.normalizedCode(primaryCurrencyCode) else {
            return .sameCurrency
        }

        if selectedConversionMode == .manual {
            let parsed = draft.reportingAmountText.currencyInputToMinorUnits(currencyCode: primaryCurrencyCode)
            guard parsed > 0 else {
                alertMessage = L10n.transactions.transactioneditor.enterTheConvertedAmountOrRefreshRates
                return CurrencyConversionResolution(isValid: false, amountMinor: nil, mode: .manual, rateDecimalString: nil, rateProvider: nil, rateDate: nil)
            }
            return CurrencyConversionResolution(isValid: true, amountMinor: parsed, mode: .manual, rateDecimalString: nil, rateProvider: "manual", rateDate: nil)
        }

        let rates = MistiaCurrencySettings.rates()
        guard let converted = MistiaCurrencyLogic.convertedMinorAmount(
            amountMinor,
            from: sourceCurrencyCode,
            to: primaryCurrencyCode,
            rates: rates
        ) else {
            alertMessage = L10n.transactions.transactioneditor.enterTheConvertedAmountOrRefreshRates
            return CurrencyConversionResolution(isValid: false, amountMinor: nil, mode: .appRate, rateDecimalString: nil, rateProvider: nil, rateDate: nil)
        }

        let rate = matchingRate(from: sourceCurrencyCode, to: primaryCurrencyCode, rates: rates)
        return CurrencyConversionResolution(
            isValid: true,
            amountMinor: converted,
            mode: .appRate,
            rateDecimalString: rate?.rateDecimalString,
            rateProvider: rate?.provider,
            rateDate: rate?.rateDate
        )
    }

    private func resolvedDestinationAmount(
        amountMinor: Int64,
        sourceCurrencyCode: String,
        destinationCurrencyCode: String
    ) -> CurrencyConversionResolution {
        guard MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode) != MistiaCurrencyLogic.normalizedCode(destinationCurrencyCode) else {
            return .sameCurrency
        }

        if selectedConversionMode == .manual {
            let manuallyEnteredDestination = draft.destinationAmountText.currencyInputToMinorUnits(currencyCode: destinationCurrencyCode)
            guard manuallyEnteredDestination > 0 else {
                alertMessage = L10n.transactions.transactioneditor.enterTheConvertedAmountOrRefreshRates
                return CurrencyConversionResolution(isValid: false, amountMinor: nil, mode: .manual, rateDecimalString: nil, rateProvider: nil, rateDate: nil)
            }

            return CurrencyConversionResolution(
                isValid: true,
                amountMinor: manuallyEnteredDestination,
                mode: .manual,
                rateDecimalString: nil,
                rateProvider: "manual",
                rateDate: nil
            )
        }

        let rates = MistiaCurrencySettings.rates()
        guard let converted = MistiaCurrencyLogic.convertedMinorAmount(
            amountMinor,
            from: sourceCurrencyCode,
            to: destinationCurrencyCode,
            rates: rates
        ) else {
            alertMessage = L10n.transactions.transactioneditor.enterTheConvertedAmountOrRefreshRates
            return CurrencyConversionResolution(isValid: false, amountMinor: nil, mode: .appRate, rateDecimalString: nil, rateProvider: nil, rateDate: nil)
        }

        let rate = matchingRate(from: sourceCurrencyCode, to: destinationCurrencyCode, rates: rates)
        return CurrencyConversionResolution(
            isValid: true,
            amountMinor: converted,
            mode: .appRate,
            rateDecimalString: rate?.rateDecimalString,
            rateProvider: rate?.provider,
            rateDate: rate?.rateDate
        )
    }

    private func matchingRate(
        from sourceCurrencyCode: String,
        to targetCurrencyCode: String,
        rates: [MistiaExchangeRate]
    ) -> MistiaExchangeRate? {
        let source = MistiaCurrencyLogic.normalizedCode(sourceCurrencyCode)
        let target = MistiaCurrencyLogic.normalizedCode(targetCurrencyCode)
        return rates.first {
            (MistiaCurrencyLogic.normalizedCode($0.baseCurrencyCode) == source
                && MistiaCurrencyLogic.normalizedCode($0.quoteCurrencyCode) == target)
            || (MistiaCurrencyLogic.normalizedCode($0.baseCurrencyCode) == target
                && MistiaCurrencyLogic.normalizedCode($0.quoteCurrencyCode) == source)
        }
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

        guard !availableWallets.isEmpty || isPaidForBorrowDraft else {
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

        if draft.primaryKind == .transfer,
           draft.transferSubtype == .debt,
           let sourceWallet = selectedSourceWallet,
           sourceWallet.kind == .creditCard,
           !TransactionLogic.debtIntentAllowsCreditCardWallet(draft.debtIntent) {
            alertMessage = L10n.transactions.transactioneditor.chooseAWalletForThisTransaction
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
                guard draft.debtIntent != nil else {
                    alertMessage = L10n.transactions.transactioneditor.chooseADebtType
                    return
                }

                guard TransactionLogic.normalizeCounterpartyName(draft.counterpartyName) != nil else {
                    alertMessage = L10n.transactions.transactioneditor.enterTheCounterpartyName
                    return
                }

                if isPaidForBorrowDraft {
                    if draft.paidForCountsAsExpense, selectedCategory == nil {
                        alertMessage = L10n.transactions.transactioneditor.chooseACategoryForThisTransaction
                        return
                    }
                } else if draft.debtIntent == .lend || draft.debtIntent == .repay {
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

            let reportingAmount = resolvedReportingAmount(
                amountMinor: amountMinor,
                sourceCurrencyCode: sourceWallet.currencyCode
            )
            guard reportingAmount.isValid else { return }

            transaction.title = draft.title.nilIfBlank ?? ""
            transaction.sourceWallet = sourceWallet
            transaction.destinationWallet = nil
            transaction.category = category
            transaction.transferSubtype = nil
            transaction.debtIntent = nil
            transaction.counterpartyName = nil
            transaction.normalizedCounterpartyKey = nil
            transaction.sourceCurrencyCode = sourceWallet.currencyCode
            transaction.destinationCurrencyCode = nil
            transaction.destinationAmountMinor = nil
            transaction.reportingCurrencyCode = reportingAmount.amountMinor == nil ? nil : primaryCurrencyCode
            transaction.reportingAmountMinor = reportingAmount.amountMinor
            transaction.conversionModeRawValue = reportingAmount.amountMinor == nil ? nil : selectedConversionMode.rawValue
            transaction.exchangeRateDecimalString = reportingAmount.rateDecimalString
            transaction.exchangeRateProvider = reportingAmount.rateProvider
            transaction.exchangeRateDate = reportingAmount.rateDate
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

                let destinationAmount = resolvedDestinationAmount(
                    amountMinor: amountMinor,
                    sourceCurrencyCode: sourceWallet.currencyCode,
                    destinationCurrencyCode: destinationWallet.currencyCode
                )
                guard destinationAmount.isValid else { return }

                transaction.title = draft.title.nilIfBlank ?? L10n.transactions.transactioneditor.internalTransfer
                transaction.sourceWallet = sourceWallet
                transaction.destinationWallet = destinationWallet
                transaction.category = nil
                transaction.transferSubtype = .internalTransfer
                transaction.debtIntent = nil
                transaction.counterpartyName = nil
                transaction.normalizedCounterpartyKey = nil
                transaction.sourceCurrencyCode = sourceWallet.currencyCode
                transaction.destinationCurrencyCode = destinationWallet.currencyCode
                transaction.destinationAmountMinor = destinationAmount.amountMinor
                transaction.reportingCurrencyCode = nil
                transaction.reportingAmountMinor = nil
                transaction.conversionModeRawValue = destinationAmount.amountMinor == nil ? nil : destinationAmount.mode.rawValue
                transaction.exchangeRateDecimalString = destinationAmount.rateDecimalString
                transaction.exchangeRateProvider = destinationAmount.rateProvider
                transaction.exchangeRateDate = destinationAmount.rateDate
            case .familyTransfer:
                alertMessage = L10n.transactions.transactioneditor.couldnTCreateFamilyTransfer
                return
            case .debt:
                guard let debtIntent = draft.debtIntent else {
                    alertMessage = L10n.transactions.transactioneditor.chooseADebtType
                    return
                }

                let isPaidForBorrow = debtIntent == .borrow && draft.borrowDebtEntryMode == .paidFor
                let sourceWallet: LedgerWallet?
                if isPaidForBorrow {
                    sourceWallet = nil
                } else {
                    guard let selectedSourceWallet else {
                        alertMessage = L10n.transactions.transactioneditor.chooseTheWalletUsedForThisDebt
                        return
                    }
                    sourceWallet = selectedSourceWallet
                }

                guard let counterpartyName = draft.counterpartyName.nilIfBlank,
                      let normalizedCounterpartyKey = TransactionLogic.normalizeCounterpartyName(counterpartyName)
                else {
                    alertMessage = L10n.transactions.transactioneditor.enterTheCounterpartyName
                    return
                }

                let category: TransactionCategory?
                if isPaidForBorrow && draft.paidForCountsAsExpense {
                    guard let selectedCategory else {
                        alertMessage = L10n.transactions.transactioneditor.chooseACategoryForThisTransaction
                        return
                    }
                    category = selectedCategory
                } else {
                    category = nil
                }

                transaction.title = draft.title.nilIfBlank ?? debtIntent.title
                transaction.sourceWallet = sourceWallet
                transaction.destinationWallet = nil
                transaction.category = category
                transaction.transferSubtype = .debt
                transaction.debtIntent = debtIntent
                transaction.counterpartyName = counterpartyName
                transaction.normalizedCounterpartyKey = normalizedCounterpartyKey
                transaction.sourceCurrencyCode = isPaidForBorrow ? paidForCurrencyCode : sourceWallet?.currencyCode
                transaction.destinationCurrencyCode = nil
                transaction.destinationAmountMinor = nil
                transaction.reportingCurrencyCode = nil
                transaction.reportingAmountMinor = nil
                transaction.conversionModeRawValue = nil
                transaction.exchangeRateDecimalString = nil
                transaction.exchangeRateProvider = nil
                transaction.exchangeRateDate = nil
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

        let canonicalOwnerUserID = persistenceOwnerUserID(for: transaction)
        persist(
            transaction: transaction,
            completion: .savedTransaction,
            subjectUserIDOverride: canonicalOwnerUserID
        )
    }

    private func persistReceiptDraftIfNeeded(for transaction: LedgerTransaction) throws {
        guard shouldShowReceiptSection else { return }

        let store = TransactionReceiptImageStore()
        guard shouldPersistReceiptImage else {
            if shouldDeleteStoredReceiptOnSave {
                try store.deleteReceipt(
                    for: transaction.id,
                    context: modelContext,
                    saveContext: false
                )
            }
            return
        }

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
                    Task { @MainActor in
                        _ = await sessionStore.pushQueuedFamilyOwnerChangesNow()
                    }
                }
            }
            onComplete(completion)
            dismiss()
        } catch {
            alertMessage = L10n.transactions.transactioneditor.couldnTSaveThisTransactionRightNow + " \(error.localizedDescription)"
        }
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

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var currentSelfUserID: UUID? {
        walletPickerAccess.currentSelfUserID
    }

    private var activeWalletPickerOwnerUserID: UUID? {
        if let transaction = target.transaction {
            return transactionOwnerUserID(for: transaction)
        }
        return target.subjectUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? currentSelfUserID
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
        return walletPickerAccess.walletOwnerUserID(for: wallet)
    }

    private func walletOwnerUserID(for walletID: UUID?) -> UUID? {
        walletPickerAccess.walletOwnerUserID(for: walletID)
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

    private func persistenceOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? walletOwnerUserID(for: transaction.sourceWallet)
            ?? walletOwnerUserID(for: transaction.destinationWallet)
            ?? target.subjectUserIDOverride
            ?? familyContextStore.selectedSubjectUserID
            ?? currentSelfUserID
    }

    private func receiptOwnerUserID(for transaction: LedgerTransaction) -> UUID? {
        transactionOwnerMap[transaction.id]
            ?? walletOwnerUserID(for: transaction.sourceWallet)
            ?? walletOwnerUserID(for: transaction.destinationWallet)
            ?? familyContextStore.selectedSubjectUserID
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

    private func walletPickerTitle(
        for wallet: LedgerWallet,
        labelMode: MistiaWalletPickerLabelMode = .contextual
    ) -> String {
        walletPickerAccess.title(for: wallet, labelMode: labelMode)
    }

    private func walletPickerTitle(
        for wallet: LedgerWallet,
        in context: TransactionEditorRenderContext,
        labelMode: MistiaWalletPickerLabelMode = .contextual
    ) -> String {
        switch labelMode {
        case .contextual:
            return context.walletLabelsByID[wallet.id] ?? wallet.name
        case .alwaysShowsOwner:
            return context.ownerWalletLabelsByID[wallet.id] ?? context.walletLabelsByID[wallet.id] ?? wallet.name
        }
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
        } else if draft.primaryKind == .transfer,
                  draft.transferSubtype == .debt {
            let availableDebtWalletIDs = Set(availableWalletsForDebtIntent.map(\.id))
            availableSourceWalletIDs = availableDebtWalletIDs
            availableDestinationWalletIDs = []
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

    private func applyCounterpartySuggestion(_ suggestion: TransactionTitleSuggestion) {
        isApplyingCounterpartySuggestion = true
        suppressCounterpartySuggestions = true
        draft.counterpartyName = suggestion.title
    }

    private var titleSuggestionsPanel: some View {
        suggestionsPanel(titleSuggestions) { suggestion in
            applyTitleSuggestion(suggestion)
        }
    }

    private var counterpartySuggestionsPanel: some View {
        suggestionsPanel(counterpartySuggestions) { suggestion in
            applyCounterpartySuggestion(suggestion)
        }
    }

    private func suggestionsPanel(
        _ suggestions: [TransactionTitleSuggestion],
        onApply: @escaping (TransactionTitleSuggestion) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onApply(suggestion)
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

                if index < suggestions.count - 1 {
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

private nonisolated enum TransactionReceiptImageProcessor {
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

    static func makeDraft(
        imageData: Data,
        thumbnailData: Data,
        contentType: String,
        isChanged: Bool
    ) -> TransactionReceiptDraft? {
        guard
            let previewImage = UIImage(data: imageData),
            let thumbnailImage = UIImage(data: thumbnailData)
        else {
            return nil
        }

        return TransactionReceiptDraft(
            imageData: imageData,
            thumbnailData: thumbnailData,
            contentType: contentType,
            previewImage: previewImage,
            thumbnailImage: thumbnailImage,
            isChanged: isChanged
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
    fileprivate var borrowDebtEntryMode: BorrowDebtEntryMode = .receiveIntoWallet
    var paidForCurrencyCode: String = "JPY"
    var paidForCountsAsExpense: Bool = false
    var title: String = ""
    var amountText: String = ""
    var destinationAmountText: String = ""
    var reportingAmountText: String = ""
    var conversionModeRawValue: String = MistiaCurrencyConversionMode.appRate.rawValue
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
            self.borrowDebtEntryMode = transaction.debtIntent == .borrow && transaction.sourceWallet == nil
                ? .paidFor
                : .receiveIntoWallet
            self.paidForCurrencyCode = MistiaCurrencyLogic.normalizedCode(
                transaction.sourceCurrencyCode ?? MistiaCurrencySettings.primaryCurrencyCode()
            )
            self.paidForCountsAsExpense = transaction.debtIntent == .borrow
                && transaction.sourceWallet == nil
                && transaction.category != nil
            self.title = transaction.title
            self.amountText = "\(transaction.amountMinor)"
            self.destinationAmountText = transaction.destinationAmountMinor.map(String.init) ?? ""
            self.reportingAmountText = transaction.reportingAmountMinor.map(String.init) ?? ""
            self.conversionModeRawValue = transaction.conversionModeRawValue ?? MistiaCurrencyConversionMode.appRate.rawValue
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
            self.borrowDebtEntryMode = .receiveIntoWallet
            self.paidForCurrencyCode = MistiaCurrencySettings.primaryCurrencyCode()
            self.paidForCountsAsExpense = false
            self.title = prefill?.title ?? ""
            self.amountText = prefill?.amountMinor.map(String.init) ?? ""
            self.destinationAmountText = ""
            self.reportingAmountText = ""
            self.conversionModeRawValue = MistiaCurrencyConversionMode.appRate.rawValue
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
