import SwiftData
import SwiftUI

private enum TransactionSegment: String, CaseIterable, Hashable {
    case expense
    case income
    case transfer

    var title: String {
        switch self {
        case .expense:
            "Chi tiêu"
        case .income:
            "Thu nhập"
        case .transfer:
            "Chuyển tiền"
        }
    }

    var tint: Color {
        switch self {
        case .expense:
            Color(red: 0.97, green: 0.43, blue: 0.46)
        case .income:
            .mint
        case .transfer:
            Color(red: 0.29, green: 0.56, blue: 0.96)
        }
    }

    var kind: TransactionPrimaryKind {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        }
    }
}

struct TransactionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\LedgerTransaction.occurredAt, order: .reverse), SortDescriptor(\LedgerTransaction.createdAt, order: .reverse)])
    private var storedTransactions: [LedgerTransaction]
    @Query(sort: [SortDescriptor(\LedgerAccount.sortOrder), SortDescriptor(\LedgerAccount.createdAt)])
    private var storedAccounts: [LedgerAccount]
    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.createdAt)])
    private var storedCategories: [TransactionCategory]

    @State private var selectedSegment: TransactionSegment? = nil
    @State private var editorTarget: TransactionEditorTarget?
    @State private var filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var activeAccounts: [LedgerAccount] {
        storedAccounts
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    private var transactionsByID: [UUID: LedgerTransaction] {
        Dictionary(uniqueKeysWithValues: storedTransactions.map { ($0.id, $0) })
    }

    private var snapshotRecords: [TransactionRecordSnapshot] {
        storedTransactions.map { $0.snapshot }
    }

    private var effectiveFilters: TransactionFilterState {
        var effective = filterState
        effective.searchText = searchText
        return effective
    }

    private var visibleRecords: [TransactionRecordSnapshot] {
        TransactionLogic.visibleRecords(
            from: snapshotRecords,
            selectedKind: selectedSegment?.kind,
            filters: effectiveFilters
        )
    }

    private var summary: TransactionSummarySnapshot {
        TransactionLogic.summary(for: visibleRecords)
    }

    private var sections: [TransactionSectionSnapshot] {
        TransactionLogic.sections(from: visibleRecords)
    }

    private var openDebtPositions: [CounterpartyDebtSnapshot] {
        let debtRecords = snapshotRecords.filter { record in
            guard record.primaryKind == .transfer, record.transferSubtype == .debt else {
                return false
            }

            if let accountID = filterState.accountID {
                return record.sourceAccountID == accountID || record.destinationAccountID == accountID
            }

            return true
        }

        return TransactionLogic.openDebtPositions(from: debtRecords)
    }

    private var activeFilterCount: Int {
        var count = 0

        if selectedSegment != nil { count += 1 }
        if filterState.timeScope != .allTime { count += 1 }
        if filterState.accountID != nil { count += 1 }
        if filterState.categoryID != nil { count += 1 }
        if filterState.transferSubtype != nil { count += 1 }
        if filterState.minAmountMinor != nil || filterState.maxAmountMinor != nil { count += 1 }

        return count
    }

    var body: some View {
        MistiaPinnedTopBarScaffold(
            tone: .standard,
            title: "Giao dịch",
            trailingSystemImage: nil,
            contentSpacing: 18,
            contentBottomPadding: 150,
            pinnedHeader: {
                unifiedFilterRow
                    .zIndex(99)
            }
        ) {
            if !openDebtPositions.isEmpty {
                outstandingDebtSection
            }
            transactionsContent
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            prompt: "Tìm tên giao dịch..."
        )
        .searchToolbarBehavior(.minimize)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .sheet(item: $editorTarget) { target in
            TransactionEditorSheet(target: target)
                .presentationDetents(target.quickCapture ? [.medium, .large] : [.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            try? MistiaBootstrap.seedDefaultCategoriesIfNeeded(modelContext: modelContext)
        }
        .environment(\.locale, Locale(identifier: "vi_VN"))
    }

    private var unifiedFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 10) {
                        filterChipsHStack
                    }
                } else {
                    filterChipsHStack
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func filterMenu<Content: View>(
        isActive: Bool,
        @ViewBuilder label: () -> Content,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let menu = Menu {
            content()
        } label: {
            label()
        }
        .buttonBorderShape(.capsule)
        .tint(Color(red: 0.53, green: 0.33, blue: 0.86))

        if isActive {
            menu.buttonStyle(.glassProminent)
                .zIndex(99)
        } else {
            menu.buttonStyle(.glass)
                .zIndex(0)
        }
    }

    private var filterChipsHStack: some View {
        HStack(spacing: 8) {
            if activeFilterCount > 0 {
                Button {
                    withAnimation(.snappy) {
                        selectedSegment = nil
                        filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
                    }
                } label: {
                    TransactionToolbarChip(
                        title: "\(activeFilterCount)",
                        isActive: true,
                        trailingIcon: "xmark"
                    )
                }
                .buttonBorderShape(.capsule)
                .tint(Color(red: 0.53, green: 0.33, blue: 0.86))
                .buttonStyle(.glassProminent)
                .zIndex(99)
            }

            filterMenu(isActive: selectedSegment != nil) {
                TransactionToolbarChip(
                    title: selectedSegment?.title ?? "Phân loại",
                    isActive: selectedSegment != nil,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                Button("Tất cả") {
                    withAnimation(.snappy) {
                        selectedSegment = nil
                    }
                }
                ForEach(TransactionSegment.allCases, id: \.self) { segment in
                    Button(segment.title) {
                        withAnimation(.snappy) {
                            selectedSegment = segment
                        }
                    }
                }
            }

            filterMenu(isActive: filterState.timeScope != .allTime) {
                TransactionToolbarChip(
                    title: filterState.timeScope == .allTime ? "Thời gian" : filterState.timeScope.title,
                    isActive: filterState.timeScope != .allTime,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                ForEach(TransactionTimeScope.allCases, id: \.self) { scope in
                    Button(scope.title) {
                        withAnimation(.snappy) {
                            filterState.timeScope = scope
                        }
                    }
                }
            }

            filterMenu(isActive: filterState.accountID != nil) {
                let title = activeAccounts.first { $0.id == filterState.accountID }?.name ?? "Tài khoản"
                TransactionToolbarChip(
                    title: title,
                    isActive: filterState.accountID != nil,
                    trailingIcon: "chevron.up.chevron.down"
                )
            } content: {
                Button("Tất cả") {
                    withAnimation(.snappy) {
                        filterState.accountID = nil
                    }
                }
                ForEach(activeAccounts, id: \.id) { account in
                    Button(account.name) {
                        withAnimation(.snappy) {
                            filterState.accountID = account.id
                        }
                    }
                }
            }

            if selectedSegment?.kind != .transfer {
                filterMenu(isActive: filterState.categoryID != nil) {
                    let title = storedCategories.first { $0.id == filterState.categoryID }?.name ?? "Danh mục"
                    TransactionToolbarChip(
                        title: title,
                        isActive: filterState.categoryID != nil,
                        trailingIcon: "chevron.up.chevron.down"
                    )
                } content: {
                    Button("Tất cả") {
                        withAnimation(.snappy) {
                            filterState.categoryID = nil
                        }
                    }
                    let relevantCategories = storedCategories.filter { cat in
                        if let kind = selectedSegment?.kind {
                            return (kind == .expense && cat.kind == .expense) || (kind == .income && cat.kind == .income)
                        }
                        return true
                    }
                    ForEach(relevantCategories, id: \.id) { category in
                        Button(category.name) {
                            withAnimation(.snappy) {
                                filterState.categoryID = category.id
                            }
                        }
                    }
                }
            }
        }
    }

    private var outstandingDebtSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Công nợ đang mở")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(openDebtPositions) { position in
                        OutstandingDebtChip(position: position)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var transactionsContent: some View {
        if storedTransactions.isEmpty {
            TransactionsPlaceholderCard(
                title: "Chưa có giao dịch nào",
                message: "Khi bạn thêm chi tiêu, thu nhập, chuyển tiền hoặc ghi nhanh từ nút plus, lịch sử sẽ xuất hiện ở đây."
            )
        } else if sections.isEmpty {
            TransactionsPlaceholderCard(
                title: "Không có kết quả phù hợp",
                message: "Thử đổi thời gian, tài khoản, bộ lọc hoặc từ khóa tìm kiếm để xem thêm giao dịch."
            )
        } else {
            ForEach(sections) { section in
                TransactionSectionCard(
                    section: section,
                    transactionsByID: transactionsByID
                ) { transaction in
                    editorTarget = TransactionEditorTarget(transaction: transaction)
                }
            }
        }
    }
}

private struct TransactionLiveSummaryCard: View {
    let summary: TransactionSummarySnapshot

    var body: some View {
        MistiaGlassCard(
            cornerRadius: 24,
            tint: Color.white.opacity(0.12)
        ) {
            HStack(alignment: .top, spacing: 14) {
                TransactionSummaryMetric(
                    title: "Chi",
                    value: summary.expenseMinor.formattedCurrency(code: "JPY"),
                    tint: Color(red: 0.97, green: 0.43, blue: 0.46)
                )

                Spacer(minLength: 4)

                TransactionSummaryMetric(
                    title: "Thu",
                    value: summary.incomeMinor.formattedCurrency(code: "JPY"),
                    tint: .mint
                )

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(summary.totalCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(summary.draftCount == 0 ? "Giao dịch" : "\(summary.draftCount) nháp")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TransactionSummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct TransactionSectionCard: View {
    let section: TransactionSectionSnapshot
    let transactionsByID: [UUID: LedgerTransaction]
    let onSelect: (LedgerTransaction) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(section.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(section.rows.count) mục")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            MistiaGlassCard(
                cornerRadius: 22,
                tint: Color.white.opacity(0.10),
                padding: 0
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if let transaction = transactionsByID[row.id] {
                            Button {
                                onSelect(transaction)
                            } label: {
                                TransactionRow(record: row, transaction: transaction)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(MistiaPressableButtonStyle(cornerRadius: 18))
                        }

                        if index < section.rows.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    let record: TransactionRecordSnapshot
    let transaction: LedgerTransaction

    private var icon: String {
        switch record.primaryKind {
        case .expense, .income:
            transaction.category?.iconSymbolName ?? record.primaryKind.systemImage
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                "arrow.left.arrow.right"
            case .debt:
                "person.2.wave.2.fill"
            case nil:
                "arrow.left.arrow.right"
            }
        }
    }

    private var iconColor: Color {
        switch record.primaryKind {
        case .expense:
            transaction.category?.iconColor ?? Color(red: 0.97, green: 0.43, blue: 0.46)
        case .income:
            transaction.category?.iconColor ?? .mint
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                Color(red: 0.29, green: 0.56, blue: 0.96)
            case .debt:
                cashflowColor
            case nil:
                .secondary
            }
        }
    }

    private var title: String {
        if let trimmed = record.title.nilIfBlank {
            return trimmed
        }

        switch record.primaryKind {
        case .expense:
            return transaction.category?.name ?? "Chi tiêu cần hoàn thiện"
        case .income:
            return transaction.category?.name ?? "Thu nhập cần hoàn thiện"
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                return "Chuyển tiền nội bộ"
            case .debt:
                return record.debtIntent?.title ?? "Công nợ"
            case nil:
                return "Chuyển tiền cần hoàn thiện"
            }
        }
    }

    private var subtitle: String {
        if record.entryStatus == .draft {
            return "Bản nháp • Chạm để hoàn thiện"
        }

        switch record.primaryKind {
        case .expense, .income:
            let account = transaction.sourceAccount?.name ?? "Chưa chọn tài khoản"
            let category = transaction.category?.name ?? "Chưa chọn danh mục"
            return "\(account) • \(category)"
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                let source = transaction.sourceAccount?.name ?? "Nguồn"
                let destination = transaction.destinationAccount?.name ?? "Đích"
                return "\(source) → \(destination)"
            case .debt:
                let account = transaction.sourceAccount?.name ?? "Chưa chọn tài khoản"
                let person = transaction.counterpartyName ?? "Không rõ tên"
                let intent = record.debtIntent?.title ?? "Công nợ"
                return "\(person) • \(intent) • \(account)"
            case nil:
                return "Chuyển tiền"
            }
        }
    }

    private var cashflowColor: Color {
        let amount = TransactionLogic.cashflowAmount(for: record)
        if amount > 0 {
            return .mint
        }
        if amount < 0 {
            return Color(red: 0.97, green: 0.43, blue: 0.46)
        }
        return Color(red: 0.29, green: 0.56, blue: 0.96)
    }

    private var displayAmount: String {
        let raw = record.amountMinor.formattedCurrency(code: "JPY")

        switch record.primaryKind {
        case .expense:
            return "-" + raw
        case .income:
            return "+" + raw
        case .transfer:
            let cashflow = TransactionLogic.cashflowAmount(for: record)
            if cashflow > 0 {
                return "+" + raw
            }
            if cashflow < 0 {
                return "-" + raw
            }
            return raw
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            TransactionIconTile(icon: icon, tint: iconColor)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if record.primaryKind == .transfer, let subtype = record.transferSubtype {
                        TransactionMiniBadge(
                            title: subtype.title,
                            tint: subtype == .debt
                                ? Color(red: 0.29, green: 0.56, blue: 0.96)
                                : Color(red: 0.36, green: 0.37, blue: 0.43)
                        )
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(displayAmount)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(cashflowColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }
}

private struct TransactionIconTile: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.14))

            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 34, height: 34)
    }
}

private struct TransactionMiniBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                MistiaCapsuleGlassBackground(tint: tint.opacity(0.12))
            }
    }
}


private struct TransactionToolbarChip: View {
    let title: String
    let isActive: Bool
    let trailingIcon: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .animation(nil, value: title)
        .animation(nil, value: isActive)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

private struct OutstandingDebtChip: View {
    let position: CounterpartyDebtSnapshot

    private var tint: Color {
        position.isReceivable
            ? Color(red: 0.23, green: 0.73, blue: 0.61)
            : Color(red: 0.96, green: 0.46, blue: 0.41)
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 22, tint: tint.opacity(0.14), padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(position.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(position.isReceivable ? "Đang nợ bạn" : "Bạn đang nợ")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(abs(position.netMinor).formattedCurrency(code: "JPY"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

private struct TransactionsPlaceholderCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let symbols = ["banknote.fill", "wallet.pass.fill", "building.columns.fill", "creditcard.fill"]
    let accent = Color(red: 0.43, green: 0.23, blue: 0.76)

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.45, blue: 0.98) : accent
    }

    private var symbolBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.10
    }

    var body: some View {
        MistiaGlassCard(cornerRadius: 24, tint: Color.white.opacity(0.10)) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                        ZStack {
                            Circle()
                                .fill(accent.opacity(symbolBackgroundOpacity + Double(index) * 0.025))

                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(buttonForeground)
                        }
                        .frame(width: 34, height: 34)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

private extension LedgerTransaction {
    var snapshot: TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: title,
            note: note,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            createdAt: createdAt,
            sourceAccountID: sourceAccount?.id,
            sourceAccountKind: sourceAccount?.kind,
            destinationAccountID: destinationAccount?.id,
            destinationAccountKind: destinationAccount?.kind,
            categoryID: category?.id,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
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

private extension Int64 {
    var positiveOrNil: Int64? {
        self > 0 ? self : nil
    }
}
