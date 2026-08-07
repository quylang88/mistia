import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AIBillAnalysisView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(MistiaUIState.self) private var uiState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(FamilyContextStore.self) private var familyContextStore
    @Query(filter: #Predicate<LedgerWallet> { $0.deletedAt == nil && !$0.isArchived })
    private var storedWallets: [LedgerWallet]
    @Query(filter: #Predicate<TransactionCategory> { $0.deletedAt == nil && !$0.isArchived })
    private var storedCategories: [TransactionCategory]
    @Query private var ownershipScopes: [OwnedRecordScope]
    @AppStorage(MistiaAppStorageKey.appLanguage) private var appLanguageRawValue = ""

    @State private var mode: BillItemTransactionMode = .expense
    @State private var bills: [AIBillDraft] = []
    @State private var selectedQuantities: [BillItemSelectionID: Int] = [:]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var cameraSource: AIBillCameraSource?
    @State private var alert: AIBillAlert?
    @State private var editorTarget: TransactionEditorTarget?
    @State private var categoryPickerTarget: AIBillCategoryPickerTarget?
    @State private var pendingTransactionAllocations: [BillItemSelectionID: BillItemQuantityAllocation] = [:]
    @State private var pendingTransactionGroupID: UUID?
    @State private var isLoadingPhotos = false
    @State private var isAnalyzing = false
    @State private var imageProcessingTask: Task<Void, Never>?
    @State private var hideRequestID = UUID()
    @State private var renderContextCache: AIBillRenderContextCache?

    private let imageLimit = 5

    private static let billFileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        let renderContextKey = renderContextCacheKey
        let renderContext = renderContextKey.map(cachedRenderContext)

        MistiaPinnedTopBarScaffold(
            tone: .modal,
            title: L10n.transactions.aibill.aiBill,
            embedsInNavigationStack: false,
            showsLeadingAvatar: false,
            leadingSystemImage: "chevron.left",
            trailingSystemImage: nil,
            hidesSystemBackButton: true,
            onLeadingTap: { requestDismiss() },
            contentSpacing: 16,
            contentBottomPadding: shouldShowAnalyzeButton ? 120 : 60
        ) {
            VStack(spacing: 16) {
                actionSection
                modeSection
                if bills.isEmpty {
                    emptyState
                } else if let renderContext {
                    ForEach(bills) { bill in
                        billCard(bill, renderContext: renderContext)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomAnalyzeSection
        }
        .mistiaUnsavedChangesDismissGuard(configuration: dismissGuardConfiguration)
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            imageProcessingTask = Task { await loadPhotoItems(newItems) }
        }
        .onChange(of: mode) { _, _ in
            normalizeSelection()
        }
        .sheet(item: $cameraSource) { source in
            AIBillCameraPicker(sourceType: source.sourceType) { image in
                appendImage(image)
            }
        }
        .sheet(item: $editorTarget, onDismiss: {
            // Clear pending state if the editor was dismissed without saving
            if !pendingTransactionAllocations.isEmpty {
                pendingTransactionAllocations = [:]
                pendingTransactionGroupID = nil
            }
        }) { target in
            TransactionEditorSheet(target: target) { completion in
                if completion == .savedTransaction {
                    markPendingItemsCreated()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $categoryPickerTarget) { target in
            let context = makeCategoryPickerContext()
            MistiaCategoryPickerSheet(
                title: L10n.transactions.transactioneditor.chooseCategory,
                selectedCategoryID: categoryID(for: target),
                sections: context.sections,
                recentCategories: [],
                favoriteCategories: context.favoriteCategories,
                initialMode: .all,
                allowsParentSelectionInAll: false,
                allModeSubtitle: { category in
                    category.parentCategory?.localizedDisplayName
                },
                quickModeSubtitle: { category in
                    category.parentCategory?.localizedDisplayName
                }
            ) { category in
                updateItemCategory(itemID: target.itemID, billID: target.billID, categoryID: category.id)
                categoryPickerTarget = nil
            }
        }
        .alert(item: $alert) { alert in
            switch alert.kind {
            case .discard:
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .destructive(Text(L10n.transactions.aibill.discardAnalysis)) {
                        dismiss()
                    },
                    secondaryButton: .cancel(Text(L10n.transactions.aibill.stayHere))
                )
            case .message:
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(L10n.common.ok))
                )
            }
        }
        .onAppear {
            uiState.requestQuickCreateHidden(true, id: hideRequestID)
        }
        .onDisappear {
            uiState.requestQuickCreateHidden(false, id: hideRequestID)
            imageProcessingTask?.cancel()
            imageProcessingTask = nil
            isLoadingPhotos = false
        }
        .task(id: renderContextKey) {
            guard let renderContextKey, let renderContext else {
                renderContextCache = nil
                return
            }
            refreshRenderContextCache(for: renderContextKey, context: renderContext)
        }
    }

    private var appLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }

    private var modeSection: some View {
        MistiaNativeSegmentedControl(
            selection: $mode,
            options: BillItemTransactionMode.allCases,
            title: modeTitle
        )
        .padding(.horizontal, 4)
    }

    private var hasPendingAnalyzableBills: Bool {
        bills.contains { $0.result == nil && !$0.isMultipleBillImage }
    }

    private var shouldShowAnalyzeButton: Bool {
        (isAnalyzing && !bills.isEmpty) || (!bills.isEmpty && hasPendingAnalyzableBills)
    }

    private var dismissGuardConfiguration: MistiaDismissGuardConfiguration {
        MistiaDismissGuardConfiguration(
            mode: .creating,
            hasUnsavedChanges: hasTransientAnalysis
        )
    }

    private var actionControlForeground: Color {
        colorScheme == .dark ? MistiaAccent.lightPurple.color : MistiaAccent.purple.color
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: max(1, imageLimit - bills.count),
                matching: .images
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 15, weight: .bold))
                    Text(bills.isEmpty ? L10n.transactions.aibill.addBills : "\(L10n.transactions.aibill.addBills) (\(bills.count)/\(imageLimit))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(actionControlForeground)
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(actionControlForeground)
            .disabled(bills.count >= imageLimit || isAnalyzing || isLoadingPhotos)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    guard bills.count < imageLimit else {
                        showTooManyImagesAlert()
                        return
                    }
                    cameraSource = .camera
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(actionControlForeground)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(actionControlForeground)
                .disabled(isAnalyzing || isLoadingPhotos)
                .accessibilityLabel(L10n.transactions.transactioneditor.takePhoto)
            }
        }
    }

    @ViewBuilder
    private var bottomAnalyzeSection: some View {
        if shouldShowAnalyzeButton {
            MistiaProminentActionButton(
                title: isAnalyzing ? L10n.transactions.aibill.analyzing : L10n.transactions.aibill.analyze,
                iconSystemName: isAnalyzing ? nil : "sparkles",
                accent: MistiaAccent.purple.color,
                isLoading: isAnalyzing,
                isDisabled: !hasPendingAnalyzableBills,
                action: analyzeBills
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        MistiaEmptyStateContent(
            title: L10n.transactions.aibill.noBillsTitle,
            message: L10n.transactions.aibill.noBillsMessage,
            buttonTitle: nil,
            symbols: ["doc.viewfinder", "sparkles", "list.bullet.rectangle"]
        )
        .padding(.top, 40)
    }

    private func billCard(_ bill: AIBillDraft, renderContext: AIBillRenderContext) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(uiImage: bill.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(bill.result?.merchantName ?? L10n.transactions.aibill.billValue(String(describing: billIndexTitle(for: bill))))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let totalMinor = bill.result?.totalMinor {
                        Text(totalMinor.formattedCurrency(code: bill.currencyCode))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(billFileSizeText(for: bill.imageData.count))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 14) {
                    if bill.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if bill.result == nil, !isAnalyzing, !bill.isAnalyzing {
                        Button(role: .destructive) {
                            removeBill(bill.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.transactions.transactioneditor.removeImage)
                    }
                }
            }

            if let message = bill.failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }

            if bill.result != nil, !bill.isMultipleBillImage {
                Divider()
                    .opacity(0.6)
                walletRow(for: bill, renderContext: renderContext)

                if !bill.lockedGroups.isEmpty {
                    Divider()
                        .opacity(0.6)
                    lockedGroupList(for: bill)
                }

                Divider()
                    .opacity(0.6)
                itemList(for: bill, renderContext: renderContext)

                if !selectedCandidates(for: bill, snapshot: renderContext.selectionSnapshot).isEmpty {
                    Divider()
                        .opacity(0.6)
                    billSelectionSummary(for: bill, renderContext: renderContext)
                }
            }
        }
        .padding(16)
        .background {
            MistiaRoundedGlassBackground(
                cornerRadius: 20,
                tint: Color(UIColor.secondarySystemGroupedBackground)
            )
        }
    }

    private func walletRow(for bill: AIBillDraft, renderContext: AIBillRenderContext) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MistiaAccent.purple.color)

            Text(L10n.transactions.aibill.walletForBill)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Picker(L10n.transactions.aibill.walletForBill, selection: bindingForBillWallet(bill.id)) {
                Text(L10n.transactions.transactioneditor.chooseWallet).tag(Optional<UUID>.none)
                ForEach(renderContext.availableWallets) { wallet in
                    Text(renderContext.walletLabelsByID[wallet.id] ?? wallet.name).tag(Optional(wallet.id))
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private func itemList(for bill: AIBillDraft, renderContext: AIBillRenderContext) -> some View {
        VStack(spacing: 0) {
            ForEach(bill.result?.items ?? []) { item in
                itemRow(item, bill: bill, renderContext: renderContext)
                if item.id != bill.result?.items.last?.id {
                    Divider()
                        .padding(.leading, 36)
                        .opacity(0.5)
                }
            }
        }
    }

    private func itemRow(_ item: BillItemAnalysisItem, bill: AIBillDraft, renderContext: AIBillRenderContext) -> some View {
        let candidateID = BillItemSelectionID(billID: bill.id, itemID: item.lineID)
        let candidate = renderContext.selectionSnapshot.candidatesByID[candidateID]
            ?? fallbackSelectionCandidate(for: item, bill: bill)
        let isSelected = candidate.selectedQuantity > 0
        let canSelect = renderContext.selectableIDs.contains(candidate.id) || isSelected

        return HStack(alignment: .center, spacing: 12) {
            Button {
                toggleSelection(candidate)
            } label: {
                Image(systemName: itemIconName(isSelected: isSelected, isCreated: candidate.isCreated, isLocked: candidate.isLocked))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(itemIconColor(isSelected: isSelected, isCreated: candidate.isCreated, isLocked: candidate.isLocked, canSelect: canSelect))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canSelect && !isSelected)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.originalName)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(candidate.isCreated || candidate.isLocked ? .secondary : .primary)
                        .lineLimit(2)

                    quantityControl(for: candidate)
                }
                if let translatedName = item.translatedName {
                    Text(translatedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.lineType == .discount {
                    HStack(spacing: 8) {
                        Text(L10n.transactions.aibill.discountLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if item.finalAmountMinor < 0 {
                            Button(L10n.transactions.aibill.allocateDiscount) {
                                allocateDiscount(itemID: item.lineID, billID: bill.id)
                            }
                            .font(.caption.weight(.bold))
                            .disabled(candidate.isCreated || candidate.isLocked)
                        }
                    }
                } else {
                    let isCategoryEditable = mode != .lend && !candidate.isCreated && !candidate.isLocked
                    Button {
                        categoryPickerTarget = AIBillCategoryPickerTarget(billID: bill.id, itemID: item.lineID)
                    } label: {
                        categoryBadgeTag(
                            title: categoryLabel(for: item.categoryID, renderContext: renderContext),
                            isMissing: item.categoryID == nil,
                            isEditable: isCategoryEditable
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isCategoryEditable)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                itemAmountColumn(item, currencyCode: bill.currencyCode, representedAmountMinor: candidate.amountMinor)
                if candidate.isCreated {
                    Text(L10n.transactions.aibill.created)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if candidate.isLocked {
                    Text(L10n.transactions.aibill.locked)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if item.lineType == .discount, item.finalAmountMinor == 0 {
                    Text(L10n.transactions.aibill.allocated)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(canSelect || isSelected ? 1 : 0.45)
    }

    private func categoryBadgeTag(title: String, isMissing: Bool, isEditable: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isMissing ? "exclamationmark.triangle.fill" : "tag.fill")
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if isEditable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(isMissing ? Color.red : (isEditable ? MistiaAccent.purple.color : Color.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isMissing
                ? Color.red.opacity(0.1)
                : (isEditable ? MistiaAccent.purple.color.opacity(0.1) : Color(UIColor.tertiarySystemGroupedBackground)),
            in: Capsule()
        )
    }

    @ViewBuilder
    private func quantityControl(for candidate: BillItemSelectionCandidate) -> some View {
        let displayedQuantity = candidate.selectedQuantity > 0 ? candidate.selectedQuantity : candidate.availableQuantity
        if candidate.lineType == .purchase, displayedQuantity > 1 {
            if candidate.availableQuantity >= 2, !candidate.isCreated, !candidate.isLocked {
                Menu {
                    ForEach(1...candidate.availableQuantity, id: \.self) { quantity in
                        Button {
                            selectQuantity(quantity, for: candidate)
                        } label: {
                            HStack {
                                Text(verbatim: "x\(quantity)")
                                if candidate.selectedQuantity == quantity {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    quantityBadge(displayedQuantity, isSelected: candidate.selectedQuantity > 0)
                }
                .menuOrder(.fixed)
            } else {
                quantityBadge(displayedQuantity, isSelected: false)
            }
        }
    }

    private func quantityBadge(_ quantity: Int, isSelected: Bool) -> some View {
        let selectedForeground = colorScheme == .dark ? Color.white : MistiaAccent.purple.color
        let selectedBackground = colorScheme == .dark
            ? MistiaAccent.purple.color.opacity(0.58)
            : MistiaAccent.purple.color.opacity(0.14)
        let selectedStroke = colorScheme == .dark
            ? MistiaAccent.lightPurple.color.opacity(0.72)
            : MistiaAccent.purple.color.opacity(0.2)

        return Text(verbatim: "x\(quantity)")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(isSelected ? selectedForeground : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isSelected
                    ? selectedBackground
                    : Color(UIColor.tertiarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? selectedStroke : .clear, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func itemAmountColumn(
        _ item: BillItemAnalysisItem,
        currencyCode: String,
        representedAmountMinor: Int64? = nil
    ) -> some View {
        let finalAmountMinor = representedAmountMinor ?? item.finalAmountMinor
        let isPartialAmount = representedAmountMinor != nil && representedAmountMinor != item.finalAmountMinor
        if item.lineType == .purchase {
            if !isPartialAmount,
               item.showsDiscountBreakdown,
               let originalAmountMinor = item.originalAmountMinor {
                Text(originalAmountMinor.formattedCurrency(code: currencyCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            } else if !isPartialAmount, let unitAmountMinor = item.quantityUnitAmountMinor {
                Text(unitAmountMinor.formattedCurrency(code: currencyCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isPartialAmount, item.discountAmountMinor > 0 {
                Text(verbatim: "-\(item.discountAmountMinor.formattedCurrency(code: currencyCode))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
            Text(finalAmountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 14, weight: .bold, design: .rounded))
        } else {
            Text(finalAmountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(finalAmountMinor < 0 ? .red : .secondary)
        }
    }

    private func lockedGroupList(for bill: AIBillDraft) -> some View {
        VStack(spacing: 8) {
            ForEach(bill.lockedGroups) { group in
                lockedGroupRow(group, bill: bill)
            }
        }
    }

    private func lockedGroupRow(_ group: BillItemLockedGroup, bill: AIBillDraft) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.transactions.aibill.lockedGroupValue(group.amountMinor.formattedCurrency(code: bill.currencyCode)))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Text(modeTitle(group.mode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                cancelLockedGroup(group.id, billID: bill.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(UIColor.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                createTransaction(from: group, bill: bill)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(L10n.transactions.aibill.createTransaction)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MistiaAccent.purple.color, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func billSelectionSummary(for bill: AIBillDraft, renderContext: AIBillRenderContext) -> some View {
        let selectedAmount = selectedAmountMinor(for: bill, snapshot: renderContext.selectionSnapshot)
        let remainingAmount = remainingAmountMinor(
            for: bill,
            includingCurrentSelection: true,
            snapshot: renderContext.selectionSnapshot
        )

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.transactions.aibill.selectedAmountValue(selectedAmount.formattedCurrency(code: bill.currencyCode)))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.transactions.aibill.remainingAmountValue(remainingAmount.formattedCurrency(code: bill.currencyCode)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                confirmSelectionGroup(for: bill)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(L10n.common.ok)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(selectedAmount > 0 ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selectedAmount > 0 ? MistiaAccent.purple.color : Color(UIColor.tertiarySystemFill),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedAmount <= 0)
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var selectedCandidates: [BillItemSelectionCandidate] {
        currentSelectionSnapshot.selectedCandidates
    }

    private func selectedCandidates(for bill: AIBillDraft) -> [BillItemSelectionCandidate] {
        selectedCandidates(for: bill, snapshot: currentSelectionSnapshot)
    }

    private func selectedCandidates(
        for bill: AIBillDraft,
        snapshot: BillItemSelectionSnapshot
    ) -> [BillItemSelectionCandidate] {
        snapshot.selectedCandidatesByBillID[bill.id] ?? []
    }

    private var allSelectionCandidates: [BillItemSelectionCandidate] {
        currentSelectionSnapshot.allCandidates
    }

    private func allSelectionCandidates(for bill: AIBillDraft) -> [BillItemSelectionCandidate] {
        currentSelectionSnapshot.candidatesByBillID[bill.id] ?? []
    }

    private var availableWallets: [LedgerWallet] {
        walletPickerAccess.availableWallets(
            from: storedWallets,
            targetOwnerUserID: quickCreateSubjectUserID
        )
    }

    private var availableExpenseCategories: [TransactionCategory] {
        scopedExpenseCategories(includesParents: false)
    }

    private func scopedExpenseCategories(includesParents: Bool) -> [TransactionCategory] {
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        return storedCategories
            .filter { category in
                guard category.kind == .expense,
                      !category.isBalanceAdjustmentSystemCategory else {
                    return false
                }
                if includesParents {
                    guard category.isParentCategory || category.isChildCategory else {
                        return false
                    }
                } else if !category.isChildCategory {
                    return false
                }
                let ownerUserID = categoryOwnerMap[category.id] ?? sessionStore.activeLocalProfileUserID
                return ownerUserID == quickCreateSubjectUserID
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var quickCreateSubjectUserID: UUID? {
        if familyContextStore.isViewingOtherMemberContext {
            return familyContextStore.selectedSubjectUserID
        }
        return walletPickerAccess.currentSelfUserID
    }

    private var receiptPersistencePolicy: TransactionReceiptPersistencePolicy {
        TransactionReceiptPersistencePolicy.policy(
            ownerUserID: quickCreateSubjectUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID
        )
    }

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private var currentSelectionSnapshot: BillItemSelectionSnapshot {
        BillItemSelectionSnapshot(
            bills: billSelectionSnapshots,
            selectedQuantities: selectedQuantities
        )
    }

    private var billSelectionSnapshots: [BillItemSelectionBillSnapshot] {
        bills.map { bill in
            BillItemSelectionBillSnapshot(
                billID: bill.id,
                walletID: bill.walletID,
                merchantName: bill.result?.merchantName,
                occurredAt: bill.result?.occurredAt,
                items: bill.result?.items ?? [],
                createdAllocations: bill.createdAllocations,
                lockedGroups: bill.lockedGroups
            )
        }
    }

    private var renderContextCacheKey: AIBillRenderContextCacheKey? {
        guard !bills.isEmpty else { return nil }
        let access = walletPickerAccess
        return AIBillRenderContextCacheKey(
            mode: mode,
            bills: billSelectionSnapshots,
            selectedQuantities: selectedQuantities,
            quickCreateSubjectUserID: quickCreateSubjectUserID,
            currentSelfUserID: access.currentSelfUserID,
            activeLocalProfileUserID: sessionStore.activeLocalProfileUserID,
            signedInUserID: sessionStore.signedInUserID,
            selectedSubjectUserID: familyContextStore.selectedSubjectUserID,
            familyAccessSignature: familyAccessSignature,
            walletSignature: MistiaCollectionChangeSignature.make(
                storedWallets,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            categorySignature: MistiaCollectionChangeSignature.make(
                storedCategories,
                updatedAt: \.updatedAt,
                deletedAt: \.deletedAt,
                isArchived: \.isArchived,
                remoteVersion: \.remoteVersion
            ),
            ownershipSignature: MistiaCollectionChangeSignature.make(
                ownershipScopes,
                updatedAt: \.updatedAt,
                deletedAt: { _ in nil }
            )
        )
    }

    private var familyAccessSignature: Int {
        var hasher = Hasher()
        hasher.combine(familyContextStore.family?.id)
        hasher.combine(familyContextStore.activeContext.scope)
        hasher.combine(familyContextStore.currentMembership?.id)
        hasher.combine(familyContextStore.currentMembership?.updatedAt.timeIntervalSince1970)
        hasher.combine(familyContextStore.members.count)
        for member in familyContextStore.members {
            hasher.combine(member.membershipID)
            hasher.combine(member.userID)
            hasher.combine(member.displayName)
            hasher.combine(member.role.rawValue)
            hasher.combine(member.hasSyncedCloudData)
        }
        hasher.combine(familyContextStore.permissionGrants.count)
        for grant in familyContextStore.permissionGrants {
            hasher.combine(grant.id)
            hasher.combine(grant.granteeUserID)
            hasher.combine(grant.ownerUserID)
            hasher.combine(grant.resourceTypeRawValue)
            hasher.combine(grant.resourceID)
            hasher.combine(grant.permissionScopeRawValue)
            hasher.combine(grant.updatedAt.timeIntervalSince1970)
            hasher.combine(grant.revokedAt?.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    private func cachedRenderContext(for key: AIBillRenderContextCacheKey) -> AIBillRenderContext {
        if let renderContextCache, renderContextCache.key == key {
            return renderContextCache.context
        }

        return makeRenderContext()
    }

    private func refreshRenderContextCache(
        for key: AIBillRenderContextCacheKey,
        context: AIBillRenderContext
    ) {
        renderContextCache = AIBillRenderContextCache(
            key: key,
            context: context
        )
    }

    private func makeRenderContext() -> AIBillRenderContext {
        let access = walletPickerAccess
        let wallets = access.availableWallets(
            from: storedWallets,
            targetOwnerUserID: quickCreateSubjectUserID
        )
        let categories = scopedExpenseCategories(includesParents: false)
        let categoryLabelsByID = Dictionary(uniqueKeysWithValues: categories.map { category in
            (category.id, categoryLabel(for: category))
        })
        let walletLabelsByID = Dictionary(uniqueKeysWithValues: wallets.map { wallet in
            (wallet.id, access.title(for: wallet))
        })
        let selectionSnapshot = currentSelectionSnapshot

        return AIBillRenderContext(
            selectionSnapshot: selectionSnapshot,
            selectableIDs: selectionSnapshot.selectableIDs(mode: mode),
            availableWallets: wallets,
            availableExpenseCategories: categories,
            categoryLabelsByID: categoryLabelsByID,
            walletLabelsByID: walletLabelsByID
        )
    }

    private func makeCategoryPickerContext() -> AIBillCategoryPickerContext {
        let categories = scopedExpenseCategories(includesParents: true)
        return AIBillCategoryPickerContext(
            sections: MistiaCategoryHierarchy.groupedSections(
                from: categories,
                kind: .expense,
                includeArchived: false,
                includeEmptyParents: false
            ),
            favoriteCategories: MistiaCategoryPickerSupport.favoriteCategories(
                from: categories,
                kind: .expense
            )
        )
    }

    private func fallbackSelectionCandidate(for item: BillItemAnalysisItem, bill: AIBillDraft) -> BillItemSelectionCandidate {
        BillItemSelectionCandidate(
            id: BillItemSelectionID(billID: bill.id, itemID: item.lineID),
            walletID: bill.walletID,
            categoryID: item.categoryID,
            lineType: item.lineType,
            amountMinor: item.transactionAmountMinor,
            totalQuantity: item.quantity ?? 1,
            availableQuantity: item.quantity ?? 1,
            selectedQuantity: selectedQuantities[BillItemSelectionID(billID: bill.id, itemID: item.lineID)] ?? 0,
            merchantName: bill.result?.merchantName,
            occurredAt: bill.result?.occurredAt,
            isCreated: bill.createdAllocations[item.lineID] != nil,
            isLocked: lockedItemIDs(for: bill).contains(BillItemSelectionID(billID: bill.id, itemID: item.lineID))
        )
    }

    private func modeTitle(_ mode: BillItemTransactionMode) -> String {
        switch mode {
        case .expense:
            TransactionPrimaryKind.expense.title
        case .lend:
            TransactionDebtIntent.lend.title
        }
    }

    private func billIndexTitle(for bill: AIBillDraft) -> String {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return "1" }
        return String(index + 1)
    }

    private func billFileSizeText(for byteCount: Int) -> String {
        Self.billFileSizeFormatter.string(fromByteCount: Int64(byteCount))
    }

    private func walletPickerTitle(for wallet: LedgerWallet) -> String {
        walletPickerAccess.title(for: wallet)
    }

    private func categoryLabel(for categoryID: UUID?, renderContext: AIBillRenderContext) -> String {
        guard let categoryID,
              let label = renderContext.categoryLabelsByID[categoryID] else {
            return L10n.transactions.transactioneditor.chooseCategory
        }
        return label
    }

    private func categoryLabel(for category: TransactionCategory) -> String {
        let parentName = category.parentCategory?.localizedDisplayName ?? category.branchDisplayName
        return "\(parentName) / \(category.localizedDisplayName)"
    }

    private func itemIconName(isSelected: Bool, isCreated: Bool, isLocked: Bool) -> String {
        if isCreated {
            return "checkmark.seal.fill"
        }
        if isLocked {
            return "lock.circle.fill"
        }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private func itemIconColor(isSelected: Bool, isCreated: Bool, isLocked: Bool, canSelect: Bool) -> Color {
        if isCreated || isLocked {
            return .secondary
        }
        if isSelected {
            return MistiaAccent.purple.color
        }
        return canSelect ? .secondary : Color.secondary.opacity(0.45)
    }

    private func bindingForBillWallet(_ billID: UUID) -> Binding<UUID?> {
        Binding(
            get: {
                bills.first(where: { $0.id == billID })?.walletID
            },
            set: { newValue in
                guard let index = bills.firstIndex(where: { $0.id == billID }) else { return }
                bills[index].walletID = newValue
                normalizeSelection()
            }
        )
    }

    private func categoryID(for target: AIBillCategoryPickerTarget) -> UUID? {
        guard let bill = bills.first(where: { $0.id == target.billID }) else { return nil }
        return bill.result?.items.first(where: { $0.lineID == target.itemID })?.categoryID
    }

    private func updateItemCategory(itemID: String, billID: UUID, categoryID: UUID?) {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }),
              let itemIndex = bills[billIndex].result?.items.firstIndex(where: { $0.lineID == itemID }) else {
            return
        }
        bills[billIndex].result?.items[itemIndex].categoryID = categoryID
        normalizeSelection()
    }

    private func allocateDiscount(itemID: String, billID: UUID) {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }),
              var result = bills[billIndex].result,
              let items = BillItemDiscountAllocator.allocatingDiscount(itemID: itemID, in: result.items) else {
            return
        }
        result.items = items
        bills[billIndex].result = result
        selectedQuantities.removeValue(forKey: BillItemSelectionID(billID: billID, itemID: itemID))
        normalizeSelection()
    }

    private func removeBill(_ billID: UUID) {
        bills.removeAll { $0.id == billID }
        selectedQuantities = selectedQuantities.filter { $0.key.billID != billID }
        pendingTransactionAllocations = pendingTransactionAllocations.filter { $0.key.billID != billID }
        if let activePendingGroupID = pendingTransactionGroupID,
           !bills.contains(where: { bill in
               bill.lockedGroups.contains { $0.id == activePendingGroupID }
           }) {
            pendingTransactionGroupID = nil
        }
        normalizeSelection()
    }

    private func toggleSelection(_ candidate: BillItemSelectionCandidate) {
        let snapshot = currentSelectionSnapshot
        if (snapshot.selectedQuantities[candidate.id] ?? 0) > 0 {
            selectedQuantities.removeValue(forKey: candidate.id)
            return
        }

        guard snapshot.selectableIDs(mode: mode).contains(candidate.id) else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.noSelectableItems
            )
            return
        }

        selectedQuantities[candidate.id] = max(1, candidate.availableQuantity)
        normalizeSelection()
    }

    private func selectQuantity(_ quantity: Int, for candidate: BillItemSelectionCandidate) {
        let snapshot = currentSelectionSnapshot
        guard snapshot.selectableIDs(mode: mode).contains(candidate.id) || (snapshot.selectedQuantities[candidate.id] ?? 0) > 0 else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.noSelectableItems
            )
            return
        }
        selectedQuantities[candidate.id] = min(max(1, quantity), candidate.availableQuantity)
        normalizeSelection()
    }

    private func normalizeSelection() {
        selectedQuantities = BillItemSelectionLogic.normalizedSelection(
            selectedQuantities,
            candidates: currentSelectionSnapshot.allCandidates,
            mode: mode
        )
    }

    private func confirmSelectionGroup(for bill: AIBillDraft) {
        let candidates = selectedCandidates(for: bill)
        guard let group = BillItemSelectionLogic.lockedGroup(for: candidates, mode: mode) else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.noSelectableItems
            )
            return
        }
        guard let billIndex = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        bills[billIndex].lockedGroups.append(group)
        for itemID in group.itemIDs {
            selectedQuantities.removeValue(forKey: itemID)
        }
        normalizeSelection()
    }

    private func cancelLockedGroup(_ groupID: UUID, billID: UUID) {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }) else { return }
        bills[billIndex].lockedGroups.removeAll { $0.id == groupID }
        normalizeSelection()
    }

    private func selectedAmountMinor(for bill: AIBillDraft, snapshot: BillItemSelectionSnapshot) -> Int64 {
        selectedCandidates(for: bill, snapshot: snapshot).reduce(Int64.zero) { $0 + $1.amountMinor }
    }

    private func remainingAmountMinor(
        for bill: AIBillDraft,
        includingCurrentSelection: Bool,
        snapshot: BillItemSelectionSnapshot
    ) -> Int64 {
        billTotalMinor(for: bill)
            - createdAmountMinor(for: bill)
            - bill.lockedGroups.reduce(Int64.zero) { $0 + $1.amountMinor }
            - (includingCurrentSelection ? selectedAmountMinor(for: bill, snapshot: snapshot) : 0)
    }

    private func billTotalMinor(for bill: AIBillDraft) -> Int64 {
        if let totalMinor = bill.result?.totalMinor {
            return totalMinor
        }
        return (bill.result?.items ?? []).reduce(Int64.zero) { $0 + $1.transactionAmountMinor }
    }

    private func createdAmountMinor(for bill: AIBillDraft) -> Int64 {
        bill.createdAllocations.values.reduce(Int64.zero) { $0 + $1.amountMinor }
    }

    private func lockedItemIDs(for bill: AIBillDraft) -> Set<BillItemSelectionID> {
        BillItemSelectionLogic.lockedItemIDs(in: bill.lockedGroups)
    }

    private func requestDismiss() {
        if hasTransientAnalysis {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.resultsWillBeLost,
                kind: .discard
            )
        } else {
            dismiss()
        }
    }

    private var hasTransientAnalysis: Bool {
        isLoadingPhotos || isAnalyzing || !bills.isEmpty || bills.contains { bill in
            bill.result != nil || bill.failureMessage != nil || bill.isMultipleBillImage || bill.isAnalyzing
        }
    }

    private func appendImage(_ image: UIImage) {
        guard bills.count < imageLimit else {
            showTooManyImagesAlert()
            return
        }

        isLoadingPhotos = true
        imageProcessingTask = Task { @MainActor in
            defer {
                isLoadingPhotos = false
                imageProcessingTask = nil
            }

            let draft = await Task.detached(priority: .userInitiated) {
                AIBillImageProcessor.makeDraft(from: image)
            }.value

            guard !Task.isCancelled else { return }
            guard let draft else {
                alert = AIBillAlert(
                    title: L10n.transactions.aibill.aiBill,
                    message: L10n.transactions.transactioneditor.couldnTProcessThisReceiptImage
                )
                return
            }

            bills.append(draft)
        }
    }

    @MainActor
    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer {
            isLoadingPhotos = false
            photoItems = []
        }

        for item in items {
            guard !Task.isCancelled else { return }
            guard bills.count < imageLimit else {
                showTooManyImagesAlert()
                return
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }

            let draft = await Task.detached(priority: .userInitiated) {
                AIBillImageProcessor.makeDraft(from: data)
            }.value

            guard !Task.isCancelled else { return }
            guard let draft else {
                continue
            }

            bills.append(draft)
        }
    }

    private func showTooManyImagesAlert() {
        alert = AIBillAlert(
            title: L10n.transactions.aibill.aiBill,
            message: L10n.transactions.aibill.tooManyImages(String(describing: imageLimit))
        )
    }

    private func analyzeBills() {
        guard !isAnalyzing else { return }
        guard sessionStore.canPerformRemoteActions else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.transactioneditor.receiptAINeedsSignInAndNetwork
            )
            return
        }
        guard !availableWallets.isEmpty, !availableExpenseCategories.isEmpty else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.transactioneditor.youNeedAvailableCategoriesBeforeAICan
            )
            return
        }

        isAnalyzing = true
        Task { @MainActor in
            defer { isAnalyzing = false }
            do {
                let session = try await sessionStore.prepareRemoteSession()
                let service = BillItemAnalysisService()
                for billID in bills.map(\.id) {
                    guard let index = bills.firstIndex(where: { $0.id == billID }),
                          bills[index].result == nil,
                          !bills[index].isMultipleBillImage else {
                        continue
                    }
                    bills[index].isAnalyzing = true
                    bills[index].failureMessage = nil
                    do {
                        let payload = await analysisPayload(for: bills[index])
                        let result = try await service.analyzeBillItems(
                            payload: payload,
                            session: session
                        )
                        applyAnalysisResult(result, to: billID)
                    } catch {
                        if case let ReceiptAnalysisServiceError.dailyLimitReached(quota) = error {
                            bills[index].quota = quota
                        }
                        bills[index].failureMessage = analysisErrorMessage(for: error)
                    }
                    if let currentIndex = bills.firstIndex(where: { $0.id == billID }) {
                        bills[currentIndex].isAnalyzing = false
                    }
                }
            } catch {
                alert = AIBillAlert(
                    title: L10n.transactions.aibill.aiBill,
                    message: analysisErrorMessage(for: error)
                )
            }
        }
    }

    private func analysisPayload(for bill: AIBillDraft) async -> BillItemAnalysisRequestPayload {
        let categories = availableExpenseCategories.map { category in
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
        let currencyCode = availableWallets.first?.currencyCode ?? "JPY"
        let imageData = bill.imageData
        let contentType = bill.contentType
        let localeIdentifier = appLanguage.localeIdentifier
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        let targetLanguageCode = appLanguage.rawValue

        let imageBase64 = await Task.detached(priority: .userInitiated) {
            imageData.base64EncodedString()
        }.value

        return BillItemAnalysisRequestPayload(
            imageBase64: imageBase64,
            mimeType: contentType,
            localeIdentifier: localeIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
            currencyCode: currencyCode,
            targetLanguageCode: targetLanguageCode,
            categories: categories,
            wallets: wallets
        )
    }

    private func applyAnalysisResult(_ result: BillItemAnalysisResult, to billID: UUID) {
        guard let index = bills.firstIndex(where: { $0.id == billID }) else { return }
        let validated = result.validated(
            categoryIDs: Set(availableExpenseCategories.map(\.id)),
            walletIDs: Set(availableWallets.map(\.id))
        )
        bills[index].quota = validated.quota

        if validated.multipleBillsDetected {
            bills[index].isMultipleBillImage = true
            bills[index].failureMessage = L10n.transactions.aibill.imageContainsMultipleBills
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.imageContainsMultipleBills
            )
            return
        }

        bills[index].result = validated
        bills[index].walletID = validated.walletID
        normalizeSelection()
    }

    private func analysisErrorMessage(for error: Error) -> String {
        if case let ReceiptAnalysisServiceError.dailyLimitReached(quota) = error {
            return ReceiptAnalysisService.limitReachedMessage(for: quota, language: appLanguage)
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return L10n.shared.sync.receiptanalysis.requestTimedOutCheckNetwork(language: appLanguage)
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return L10n.shared.sync.receiptanalysis.unstableNetworkTryAgain(language: appLanguage)
            default:
                break
            }
        }

        if let serviceError = error as? SupabaseServiceError {
            switch serviceError {
            case .serverMessage(let message):
                let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedMessage.isEmpty
                    ? L10n.shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow(language: appLanguage)
                    : trimmedMessage
            case .configurationMissing, .invalidURL, .invalidResponse:
                return L10n.shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow(language: appLanguage)
            default:
                return L10n.shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow(language: appLanguage)
            }
        }

        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription, !message.isEmpty {
            return message
        }

        return L10n.shared.sync.receiptanalysis.couldnTAnalyzeThisReceiptRightNow(language: appLanguage)
    }

    private func createTransaction(from group: BillItemLockedGroup, bill: AIBillDraft) {
        let candidates = allSelectionCandidates(for: bill).compactMap { candidate -> BillItemSelectionCandidate? in
            guard let allocation = group.itemAllocations[candidate.id] else { return nil }
            return candidate.representing(allocation)
        }
        guard let draft = BillItemSelectionLogic.transactionDraft(
            for: candidates,
            mode: group.mode,
            fallbackDate: Date()
        ) else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.noSelectableItems
            )
            return
        }

        pendingTransactionAllocations = group.itemAllocations
        pendingTransactionGroupID = group.id
        let receiptImage = draft.receiptAttachmentBillID.flatMap { billID in
            bills.first(where: { $0.id == billID })?.image
        }
        let transferPreset = draft.primaryKind == .transfer
            ? TransactionTransferPreset(
                transferSubtype: draft.transferSubtype ?? .debt,
                sourceWalletID: draft.walletID
            )
            : nil

        editorTarget = TransactionEditorTarget(
            initialKind: draft.primaryKind,
            transferPreset: transferPreset,
            prefill: TransactionEditorPrefill(
                title: draft.title,
                amountMinor: draft.amountMinor,
                occurredAt: draft.occurredAt,
                sourceWalletID: draft.walletID,
                categoryID: draft.categoryID,
                lockedTransferSubtype: draft.transferSubtype,
                lockedDebtIntent: draft.debtIntent,
                receiptImage: receiptImage
            ),
            subjectUserIDOverride: quickCreateSubjectUserID,
            receiptPersistencePolicy: receiptPersistencePolicy
        )
    }

    private func markPendingItemsCreated() {
        for (id, allocation) in pendingTransactionAllocations {
            guard let billIndex = bills.firstIndex(where: { $0.id == id.billID }) else { continue }
            let existing = bills[billIndex].createdAllocations[id.itemID] ?? BillItemQuantityAllocation(quantity: 0, amountMinor: 0)
            bills[billIndex].createdAllocations[id.itemID] = BillItemQuantityAllocation(
                quantity: existing.quantity + allocation.quantity,
                amountMinor: existing.amountMinor + allocation.amountMinor
            )
        }
        if let pendingTransactionGroupID {
            for index in bills.indices {
                bills[index].lockedGroups.removeAll { $0.id == pendingTransactionGroupID }
            }
        }
        for id in pendingTransactionAllocations.keys {
            selectedQuantities.removeValue(forKey: id)
        }
        pendingTransactionAllocations = [:]
        pendingTransactionGroupID = nil
        normalizeSelection()
    }

}

struct AIBillDraft: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    let imageData: Data
    let contentType: String
    var result: BillItemAnalysisResult?
    var walletID: UUID?
    var quota: ReceiptAnalysisQuota?
    var isAnalyzing = false
    var isMultipleBillImage = false
    var failureMessage: String?
    var createdAllocations: [String: BillItemQuantityAllocation] = [:]
    var lockedGroups: [BillItemLockedGroup] = []

    var image: UIImage? {
        UIImage(data: imageData)
    }

    var currencyCode: String {
        result?.currencyCode ?? "JPY"
    }
}

struct AIBillRenderContextCacheKey: Hashable {
    private let modeRawValue: String
    private let bills: [BillSignature]
    private let selectedQuantities: [SelectionQuantitySignature]
    private let quickCreateSubjectUserID: UUID?
    private let currentSelfUserID: UUID?
    private let activeLocalProfileUserID: UUID?
    private let signedInUserID: UUID?
    private let selectedSubjectUserID: UUID?
    private let familyAccessSignature: Int
    private let walletSignature: MistiaCollectionChangeSignature
    private let categorySignature: MistiaCollectionChangeSignature
    private let ownershipSignature: MistiaCollectionChangeSignature

    init(
        mode: BillItemTransactionMode,
        bills: [BillItemSelectionBillSnapshot],
        selectedQuantities: [BillItemSelectionID: Int],
        quickCreateSubjectUserID: UUID?,
        currentSelfUserID: UUID?,
        activeLocalProfileUserID: UUID?,
        signedInUserID: UUID?,
        selectedSubjectUserID: UUID?,
        familyAccessSignature: Int,
        walletSignature: MistiaCollectionChangeSignature,
        categorySignature: MistiaCollectionChangeSignature,
        ownershipSignature: MistiaCollectionChangeSignature
    ) {
        self.modeRawValue = mode.rawValue
        self.bills = Self.billSignatures(from: bills)
        self.selectedQuantities = Self.selectionQuantitySignatures(from: selectedQuantities)
        self.quickCreateSubjectUserID = quickCreateSubjectUserID
        self.currentSelfUserID = currentSelfUserID
        self.activeLocalProfileUserID = activeLocalProfileUserID
        self.signedInUserID = signedInUserID
        self.selectedSubjectUserID = selectedSubjectUserID
        self.familyAccessSignature = familyAccessSignature
        self.walletSignature = walletSignature
        self.categorySignature = categorySignature
        self.ownershipSignature = ownershipSignature
    }

    private static func billSignatures(
        from bills: [BillItemSelectionBillSnapshot]
    ) -> [BillSignature] {
        var signatures: [BillSignature] = []
        signatures.reserveCapacity(bills.count)

        for bill in bills {
            var itemSignatures: [ItemSignature] = []
            itemSignatures.reserveCapacity(bill.items.count)
            for item in bill.items {
                itemSignatures.append(
                    ItemSignature(
                        lineID: item.lineID,
                        lineTypeRawValue: item.lineType.rawValue,
                        quantity: item.quantity,
                        finalAmountMinor: item.finalAmountMinor,
                        categoryID: item.categoryID
                    )
                )
            }

            var createdAllocationSignatures: [AllocationSignature] = []
            createdAllocationSignatures.reserveCapacity(bill.createdAllocations.count)
            for (itemID, allocation) in bill.createdAllocations {
                createdAllocationSignatures.append(
                    AllocationSignature(
                        itemID: itemID,
                        quantity: allocation.quantity,
                        amountMinor: allocation.amountMinor
                    )
                )
            }
            createdAllocationSignatures.sort { $0.itemID < $1.itemID }

            var lockedGroupSignatures: [LockedGroupSignature] = []
            lockedGroupSignatures.reserveCapacity(bill.lockedGroups.count)
            for group in bill.lockedGroups {
                var allocationSignatures: [LockedGroupAllocationSignature] = []
                allocationSignatures.reserveCapacity(group.itemAllocations.count)
                for (id, allocation) in group.itemAllocations {
                    allocationSignatures.append(
                        LockedGroupAllocationSignature(
                            billID: id.billID,
                            itemID: id.itemID,
                            quantity: allocation.quantity,
                            amountMinor: allocation.amountMinor
                        )
                    )
                }
                allocationSignatures.sort {
                    if $0.billID != $1.billID {
                        return $0.billID.uuidString < $1.billID.uuidString
                    }
                    return $0.itemID < $1.itemID
                }
                lockedGroupSignatures.append(
                    LockedGroupSignature(
                        id: group.id,
                        modeRawValue: group.mode.rawValue,
                        amountMinor: group.amountMinor,
                        itemAllocations: allocationSignatures
                    )
                )
            }
            lockedGroupSignatures.sort {
                if $0.id != $1.id {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.amountMinor < $1.amountMinor
            }

            signatures.append(
                BillSignature(
                    billID: bill.billID,
                    walletID: bill.walletID,
                    merchantName: bill.merchantName,
                    occurredAt: bill.occurredAt?.timeIntervalSince1970,
                    items: itemSignatures,
                    createdAllocations: createdAllocationSignatures,
                    lockedGroups: lockedGroupSignatures
                )
            )
        }

        return signatures
    }

    private static func selectionQuantitySignatures(
        from selectedQuantities: [BillItemSelectionID: Int]
    ) -> [SelectionQuantitySignature] {
        var signatures: [SelectionQuantitySignature] = []
        signatures.reserveCapacity(selectedQuantities.count)
        for (id, quantity) in selectedQuantities {
            signatures.append(
                SelectionQuantitySignature(
                    billID: id.billID,
                    itemID: id.itemID,
                    quantity: quantity
                )
            )
        }
        signatures.sort {
            if $0.billID != $1.billID {
                return $0.billID.uuidString < $1.billID.uuidString
            }
            return $0.itemID < $1.itemID
        }
        return signatures
    }

    private nonisolated struct BillSignature: Hashable {
        let billID: UUID
        let walletID: UUID?
        let merchantName: String?
        let occurredAt: TimeInterval?
        let items: [ItemSignature]
        let createdAllocations: [AllocationSignature]
        let lockedGroups: [LockedGroupSignature]
    }

    private nonisolated struct ItemSignature: Hashable {
        let lineID: String
        let lineTypeRawValue: String
        let quantity: Int?
        let finalAmountMinor: Int64
        let categoryID: UUID?
    }

    private nonisolated struct AllocationSignature: Hashable {
        let itemID: String
        let quantity: Int
        let amountMinor: Int64
    }

    private nonisolated struct LockedGroupSignature: Hashable {
        let id: UUID
        let modeRawValue: String
        let amountMinor: Int64
        let itemAllocations: [LockedGroupAllocationSignature]
    }

    private nonisolated struct LockedGroupAllocationSignature: Hashable {
        let billID: UUID
        let itemID: String
        let quantity: Int
        let amountMinor: Int64
    }

    private nonisolated struct SelectionQuantitySignature: Hashable {
        let billID: UUID
        let itemID: String
        let quantity: Int
    }
}

private struct AIBillRenderContextCache {
    let key: AIBillRenderContextCacheKey
    let context: AIBillRenderContext
}

private struct AIBillRenderContext {
    let selectionSnapshot: BillItemSelectionSnapshot
    let selectableIDs: Set<BillItemSelectionID>
    let availableWallets: [LedgerWallet]
    let availableExpenseCategories: [TransactionCategory]
    let categoryLabelsByID: [UUID: String]
    let walletLabelsByID: [UUID: String]
}

private struct AIBillCategoryPickerContext {
    let sections: [TransactionCategoryGroupSection]
    let favoriteCategories: [TransactionCategory]
}

private struct AIBillCategoryPickerTarget: Identifiable {
    let billID: UUID
    let itemID: String

    var id: String {
        "\(billID.uuidString)-\(itemID)"
    }
}

private enum AIBillAlertKind {
    case message
    case discard
}

private struct AIBillAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var kind: AIBillAlertKind = .message
}

private enum AIBillCameraSource: Identifiable {
    case camera

    var id: String { "camera" }

    var sourceType: UIImagePickerController.SourceType {
        .camera
    }
}

nonisolated enum AIBillImageProcessor {
    private static let maxAnalysisImageBytes = 3_800_000
    private static let maxAnalysisImageDimension: CGFloat = 1_800
    private static let minAnalysisImageDimension: CGFloat = 900

    static func makeDraft(from data: Data) -> AIBillDraft? {
        guard let image = UIImage(data: data) else { return nil }
        return makeDraft(from: image)
    }

    static func makeDraft(from image: UIImage) -> AIBillDraft? {
        let normalized = scaledImage(image, maxDimension: maxAnalysisImageDimension)
        guard let imageData = compressedJPEGData(for: normalized),
              let thumbnail = thumbnail(from: normalized) else {
            return nil
        }

        return AIBillDraft(
            thumbnail: thumbnail,
            imageData: imageData,
            contentType: "image/jpeg"
        )
    }

    private static func compressedJPEGData(for image: UIImage) -> Data? {
        var candidateImage = image
        var candidateMaxDimension = max(image.size.width, image.size.height)
        var bestData: Data?

        while candidateMaxDimension >= minAnalysisImageDimension {
            var data: Data?
            autoreleasepool {
                data = qualityAdjustedJPEGData(for: candidateImage)
            }
            if let data, data.count <= maxAnalysisImageBytes {
                return data
            }
            if let data, bestData == nil || data.count < (bestData?.count ?? .max) {
                bestData = data
            }

            candidateMaxDimension *= 0.86
            autoreleasepool {
                candidateImage = scaledImage(image, maxDimension: candidateMaxDimension)
            }
        }

        if let bestData, bestData.count <= maxAnalysisImageBytes {
            return bestData
        }
        return nil
    }

    private static func qualityAdjustedJPEGData(for image: UIImage) -> Data? {
        var quality: CGFloat = 0.82
        var data = image.jpegData(compressionQuality: quality)

        while let current = data, current.count > maxAnalysisImageBytes, quality > 0.42 {
            quality -= 0.08
            autoreleasepool {
                data = image.jpegData(compressionQuality: quality)
            }
        }

        return data
    }

    private static func scaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > 0 else { return image }

        let scale = min(1, maxDimension / largestSide)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func thumbnail(from image: UIImage) -> UIImage? {
        let targetSize = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))

            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

private struct AIBillCameraPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: AIBillCameraPicker

        init(parent: AIBillCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
