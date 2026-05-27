import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AIBillAnalysisView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
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
    @State private var selectedIDs: Set<BillItemSelectionID> = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var cameraSource: AIBillCameraSource?
    @State private var alert: AIBillAlert?
    @State private var editorTarget: TransactionEditorTarget?
    @State private var pendingTransactionItemIDs: Set<BillItemSelectionID> = []
    @State private var pendingTransactionGroupID: UUID?
    @State private var isLoadingPhotos = false
    @State private var isAnalyzing = false

    private let imageLimit = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                modeSection
                actionSection
                if bills.isEmpty {
                    emptyState
                } else {
                    ForEach(bills) { bill in
                        billCard(bill)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.transactions.aibill.aiBill)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadPhotoItems(newItems) }
        }
        .onChange(of: mode) { _, _ in
            normalizeSelection()
        }
        .sheet(item: $cameraSource) { source in
            AIBillCameraPicker(sourceType: source.sourceType) { image in
                appendImage(image)
            }
        }
        .sheet(item: $editorTarget) { target in
            TransactionEditorSheet(target: target) { completion in
                if completion == .savedTransaction {
                    markPendingItemsCreated()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
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
    }

    private var appLanguage: MistiaAppLanguage {
        MistiaAppLanguage.resolve(storedRawValue: appLanguageRawValue)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MistiaNativeSegmentedControl(
                selection: $mode,
                options: BillItemTransactionMode.allCases,
                title: modeTitle
            )
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: max(1, imageLimit - bills.count),
                    matching: .images
                ) {
                    Label(L10n.transactions.aibill.addBills, systemImage: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzing || isLoadingPhotos)
                }
            }

            Button {
                analyzeBills()
            } label: {
                HStack(spacing: 8) {
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? L10n.transactions.aibill.analyzing : L10n.transactions.aibill.analyze)
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(MistiaAccent.purple.color)
            .disabled(isAnalyzing || bills.isEmpty || bills.allSatisfy { $0.result != nil || $0.isMultipleBillImage })

            Text(L10n.transactions.aibill.chooseUpToValueBills(String(describing: imageLimit)))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
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

    private func billCard(_ bill: AIBillDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(uiImage: bill.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(bill.result?.merchantName ?? L10n.transactions.aibill.billValue(String(describing: billIndexTitle(for: bill))))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if let totalMinor = bill.result?.totalMinor {
                        Text(totalMinor.formattedCurrency(code: bill.currencyCode))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusText(for: bill))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if bill.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message = bill.failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if bill.result != nil, !bill.isMultipleBillImage {
                walletPicker(for: bill)
                lockedGroupList(for: bill)
                itemList(for: bill)
                if !selectedCandidates(for: bill).isEmpty {
                    billSelectionSummary(for: bill)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    private func walletPicker(for bill: AIBillDraft) -> some View {
        Picker(L10n.transactions.aibill.walletForBill, selection: bindingForBillWallet(bill.id)) {
            Text(L10n.transactions.transactioneditor.chooseWallet).tag(Optional<UUID>.none)
            ForEach(availableWallets) { wallet in
                Text(walletPickerTitle(for: wallet)).tag(Optional(wallet.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func itemList(for bill: AIBillDraft) -> some View {
        VStack(spacing: 0) {
            ForEach(bill.result?.items ?? []) { item in
                itemRow(item, bill: bill)
                if item.id != bill.result?.items.last?.id {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
    }

    private func itemRow(_ item: BillItemAnalysisItem, bill: AIBillDraft) -> some View {
        let candidate = selectionCandidate(for: item, bill: bill)
        let isSelected = selectedIDs.contains(candidate.id)
        let selectedForBill = selectedCandidates(for: bill)
        let canSelect = canSelectCandidate(candidate, selectedInBill: selectedForBill) || isSelected

        return HStack(alignment: .top, spacing: 10) {
            Button {
                toggleSelection(candidate)
            } label: {
                Image(systemName: itemIconName(isSelected: isSelected, isCreated: candidate.isCreated, isLocked: candidate.isLocked))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(itemIconColor(isSelected: isSelected, isCreated: candidate.isCreated, isLocked: candidate.isLocked, canSelect: canSelect))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canSelect && !isSelected)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.originalName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(candidate.isCreated || candidate.isLocked ? .secondary : .primary)
                if let translatedName = item.translatedName {
                    Text(translatedName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if item.lineType == .discount {
                    HStack(spacing: 8) {
                        Text(L10n.transactions.aibill.discountLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if item.finalAmountMinor < 0 {
                            Button(L10n.transactions.aibill.allocateDiscount) {
                                allocateDiscount(itemID: item.lineID, billID: bill.id)
                            }
                            .font(.footnote.weight(.semibold))
                            .disabled(candidate.isCreated || candidate.isLocked)
                        }
                    }
                } else {
                    Menu {
                        ForEach(availableExpenseCategories) { category in
                            Button(categoryLabel(for: category)) {
                                updateItemCategory(itemID: item.lineID, billID: bill.id, categoryID: category.id)
                            }
                        }
                    } label: {
                        Text(categoryLabel(for: item.categoryID))
                            .font(.footnote)
                            .foregroundStyle(item.categoryID == nil ? .red : .secondary)
                    }
                    .disabled(mode == .lend || candidate.isCreated || candidate.isLocked)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                itemAmountColumn(item, currencyCode: bill.currencyCode)
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
        .padding(.vertical, 10)
        .opacity(canSelect || isSelected ? 1 : 0.45)
    }

    @ViewBuilder
    private func itemAmountColumn(_ item: BillItemAnalysisItem, currencyCode: String) -> some View {
        if item.lineType == .purchase {
            if let originalAmountMinor = item.originalAmountMinor,
               originalAmountMinor != item.finalAmountMinor {
                Text(originalAmountMinor.formattedCurrency(code: currencyCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            if item.discountAmountMinor > 0 {
                Text(verbatim: "-\(item.discountAmountMinor.formattedCurrency(code: currencyCode))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
            Text(item.finalAmountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 14, weight: .bold, design: .rounded))
        } else {
            Text(item.finalAmountMinor.formattedCurrency(code: currencyCode))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(item.finalAmountMinor < 0 ? .red : .secondary)
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MistiaAccent.purple.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.transactions.aibill.lockedGroupValue(group.amountMinor.formattedCurrency(code: bill.currencyCode)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(modeTitle(group.mode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.common.cancel) {
                cancelLockedGroup(group.id, billID: bill.id)
            }
            .font(.caption.weight(.semibold))
            Button(L10n.transactions.aibill.createTransaction) {
                createTransaction(from: group, bill: bill)
            }
            .font(.caption.weight(.bold))
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MistiaAccent.purple.color.opacity(colorScheme == .dark ? 0.18 : 0.09))
        }
    }

    private func billSelectionSummary(for bill: AIBillDraft) -> some View {
        let selectedAmount = selectedAmountMinor(for: bill)
        let remainingAmount = remainingAmountMinor(for: bill, includingCurrentSelection: true)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.transactions.aibill.selectedAmountValue(selectedAmount.formattedCurrency(code: bill.currencyCode)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(L10n.transactions.aibill.remainingAmountValue(remainingAmount.formattedCurrency(code: bill.currencyCode)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.common.ok) {
                confirmSelectionGroup(for: bill)
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(MistiaAccent.purple.color)
            .disabled(selectedAmount <= 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
        }
    }

    private var selectedCandidates: [BillItemSelectionCandidate] {
        allSelectionCandidates.filter { selectedIDs.contains($0.id) }
    }

    private func selectedCandidates(for bill: AIBillDraft) -> [BillItemSelectionCandidate] {
        allSelectionCandidates(for: bill).filter { selectedIDs.contains($0.id) }
    }

    private var allSelectionCandidates: [BillItemSelectionCandidate] {
        bills.flatMap { bill in
            allSelectionCandidates(for: bill)
        }
    }

    private func allSelectionCandidates(for bill: AIBillDraft) -> [BillItemSelectionCandidate] {
        (bill.result?.items ?? []).map { selectionCandidate(for: $0, bill: bill) }
    }

    private var availableWallets: [LedgerWallet] {
        walletPickerAccess.availableWallets(
            from: storedWallets,
            targetOwnerUserID: quickCreateSubjectUserID
        )
    }

    private var availableExpenseCategories: [TransactionCategory] {
        let categoryOwnerMap = MistiaRecordOwnershipStore.ownerMap(from: ownershipScopes, entity: .category)
        return storedCategories
            .filter { category in
                guard category.kind == .expense,
                      category.isChildCategory,
                      !category.isBalanceAdjustmentSystemCategory else {
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

    private var walletPickerAccess: MistiaWalletPickerAccess {
        MistiaWalletPickerAccess(
            sessionStore: sessionStore,
            familyContextStore: familyContextStore,
            ownershipScopes: ownershipScopes
        )
    }

    private func selectionCandidate(for item: BillItemAnalysisItem, bill: AIBillDraft) -> BillItemSelectionCandidate {
        BillItemSelectionCandidate(
            id: BillItemSelectionID(billID: bill.id, itemID: item.lineID),
            walletID: bill.walletID,
            categoryID: item.categoryID,
            lineType: item.lineType,
            amountMinor: item.transactionAmountMinor,
            merchantName: bill.result?.merchantName,
            occurredAt: bill.result?.occurredAt,
            isCreated: bill.createdItemIDs.contains(item.lineID),
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

    private func statusText(for bill: AIBillDraft) -> String {
        if bill.isAnalyzing {
            return L10n.transactions.aibill.analyzing
        }
        if bill.failureMessage != nil {
            return L10n.transactions.aibill.couldnTAnalyzeBill
        }
        return L10n.transactions.aibill.analyze
    }

    private func billIndexTitle(for bill: AIBillDraft) -> String {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return "1" }
        return String(index + 1)
    }

    private func walletPickerTitle(for wallet: LedgerWallet) -> String {
        walletPickerAccess.title(for: wallet)
    }

    private func categoryLabel(for categoryID: UUID?) -> String {
        guard let categoryID,
              let category = availableExpenseCategories.first(where: { $0.id == categoryID }) else {
            return L10n.transactions.transactioneditor.chooseCategory
        }
        return categoryLabel(for: category)
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
        selectedIDs.remove(BillItemSelectionID(billID: billID, itemID: itemID))
        normalizeSelection()
    }

    private func toggleSelection(_ candidate: BillItemSelectionCandidate) {
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
            return
        }

        guard selectedIDs.allSatisfy({ $0.billID == candidate.id.billID }),
              BillItemSelectionLogic.canSelect(candidate, selected: selectedCandidates, mode: mode) else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.aibill.noSelectableItems
            )
            return
        }

        selectedIDs.insert(candidate.id)
    }

    private func normalizeSelection() {
        selectedIDs = BillItemSelectionLogic.normalizedSelection(
            selectedIDs,
            candidates: allSelectionCandidates,
            mode: mode
        )
    }

    private func canSelectCandidate(
        _ candidate: BillItemSelectionCandidate,
        selectedInBill: [BillItemSelectionCandidate]
    ) -> Bool {
        guard selectedIDs.allSatisfy({ $0.billID == candidate.id.billID }) else {
            return false
        }
        return BillItemSelectionLogic.canSelect(candidate, selected: selectedInBill, mode: mode)
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
        selectedIDs.subtract(group.itemIDs)
        normalizeSelection()
    }

    private func cancelLockedGroup(_ groupID: UUID, billID: UUID) {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }) else { return }
        bills[billIndex].lockedGroups.removeAll { $0.id == groupID }
        normalizeSelection()
    }

    private func selectedAmountMinor(for bill: AIBillDraft) -> Int64 {
        selectedCandidates(for: bill).reduce(Int64.zero) { $0 + $1.amountMinor }
    }

    private func remainingAmountMinor(for bill: AIBillDraft, includingCurrentSelection: Bool) -> Int64 {
        billTotalMinor(for: bill)
            - createdAmountMinor(for: bill)
            - bill.lockedGroups.reduce(Int64.zero) { $0 + $1.amountMinor }
            - (includingCurrentSelection ? selectedAmountMinor(for: bill) : 0)
    }

    private func billTotalMinor(for bill: AIBillDraft) -> Int64 {
        if let totalMinor = bill.result?.totalMinor {
            return totalMinor
        }
        return (bill.result?.items ?? []).reduce(Int64.zero) { $0 + $1.transactionAmountMinor }
    }

    private func createdAmountMinor(for bill: AIBillDraft) -> Int64 {
        (bill.result?.items ?? [])
            .filter { bill.createdItemIDs.contains($0.lineID) }
            .reduce(Int64.zero) { $0 + $1.transactionAmountMinor }
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
        bills.contains { bill in
            bill.result != nil || bill.failureMessage != nil || bill.isMultipleBillImage
        }
    }

    private func appendImage(_ image: UIImage) {
        guard bills.count < imageLimit else {
            showTooManyImagesAlert()
            return
        }
        guard let draft = AIBillImageProcessor.makeDraft(from: image) else {
            alert = AIBillAlert(
                title: L10n.transactions.aibill.aiBill,
                message: L10n.transactions.transactioneditor.couldnTProcessThisReceiptImage
            )
            return
        }
        bills.append(draft)
    }

    @MainActor
    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer {
            isLoadingPhotos = false
            photoItems = []
        }

        for item in items {
            guard bills.count < imageLimit else {
                showTooManyImagesAlert()
                return
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                continue
            }
            appendImage(image)
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
                        let result = try await service.analyzeBillItems(
                            payload: analysisPayload(for: bills[index]),
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

    private func analysisPayload(for bill: AIBillDraft) -> BillItemAnalysisRequestPayload {
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

        return BillItemAnalysisRequestPayload(
            imageBase64: bill.imageData.base64EncodedString(),
            mimeType: bill.contentType,
            localeIdentifier: appLanguage.localeIdentifier,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            currencyCode: currencyCode,
            targetLanguageCode: appLanguage.rawValue,
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
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription, !message.isEmpty {
            return message
        }
        return L10n.transactions.aibill.couldnTAnalyzeBill + " \(error.localizedDescription)"
    }

    private func createTransaction(from group: BillItemLockedGroup, bill: AIBillDraft) {
        let candidates = allSelectionCandidates(for: bill).filter { group.itemIDs.contains($0.id) }
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

        pendingTransactionItemIDs = Set(candidates.map(\.id))
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
            subjectUserIDOverride: quickCreateSubjectUserID
        )
    }

    private func markPendingItemsCreated() {
        for id in pendingTransactionItemIDs {
            guard let billIndex = bills.firstIndex(where: { $0.id == id.billID }) else { continue }
            bills[billIndex].createdItemIDs.insert(id.itemID)
        }
        if let pendingTransactionGroupID {
            for index in bills.indices {
                bills[index].lockedGroups.removeAll { $0.id == pendingTransactionGroupID }
            }
        }
        selectedIDs.subtract(pendingTransactionItemIDs)
        pendingTransactionItemIDs = []
        pendingTransactionGroupID = nil
        normalizeSelection()
    }

}

private struct AIBillDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let thumbnail: UIImage
    let imageData: Data
    let contentType: String
    var result: BillItemAnalysisResult?
    var walletID: UUID?
    var quota: ReceiptAnalysisQuota?
    var isAnalyzing = false
    var isMultipleBillImage = false
    var failureMessage: String?
    var createdItemIDs: Set<String> = []
    var lockedGroups: [BillItemLockedGroup] = []

    var currencyCode: String {
        result?.currencyCode ?? "JPY"
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

private enum AIBillImageProcessor {
    static func makeDraft(from image: UIImage) -> AIBillDraft? {
        let normalized = normalizedImage(image)
        guard let imageData = normalized.jpegData(compressionQuality: 0.82),
              let thumbnail = thumbnail(from: normalized) else {
            return nil
        }

        return AIBillDraft(
            image: normalized,
            thumbnail: thumbnail,
            imageData: imageData,
            contentType: "image/jpeg"
        )
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1800
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
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
