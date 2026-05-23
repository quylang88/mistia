import Foundation

struct TransactionWalletSnapshot: Equatable, Identifiable {
    let id: UUID
    let kind: LedgerWalletKind
    let openingBalanceMinor: Int64
}

nonisolated struct TransactionWalletBalanceIndex: Equatable {
    private let balancesByWalletID: [UUID: Int64]

    init(balancesByWalletID: [UUID: Int64]) {
        self.balancesByWalletID = balancesByWalletID
    }

    func balance(for wallet: TransactionWalletSnapshot) -> Int64 {
        balancesByWalletID[wallet.id] ?? wallet.openingBalanceMinor
    }

    func balance(for walletID: UUID, default defaultBalance: Int64 = 0) -> Int64 {
        balancesByWalletID[walletID] ?? defaultBalance
    }
}

struct TransactionRecordSnapshot: Equatable, Identifiable {
    let id: UUID
    let primaryKind: TransactionPrimaryKind
    let transferSubtype: TransactionTransferSubtype?
    let debtIntent: TransactionDebtIntent?
    let entryStatus: TransactionEntryStatus
    let title: String
    let note: String?
    let amountMinor: Int64
    let isArchived: Bool
    let occurredAt: Date
    let createdAt: Date
    let sourceWalletID: UUID?
    let sourceWalletKind: LedgerWalletKind?
    let destinationWalletID: UUID?
    let destinationWalletKind: LedgerWalletKind?
    let categoryID: UUID?
    let categoryParentID: UUID?
    let counterpartyName: String?
    let normalizedCounterpartyKey: String?

    init(
        id: UUID,
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype?,
        debtIntent: TransactionDebtIntent?,
        entryStatus: TransactionEntryStatus,
        title: String,
        note: String?,
        amountMinor: Int64,
        isArchived: Bool = false,
        occurredAt: Date,
        createdAt: Date,
        sourceWalletID: UUID?,
        sourceWalletKind: LedgerWalletKind?,
        destinationWalletID: UUID?,
        destinationWalletKind: LedgerWalletKind?,
        categoryID: UUID?,
        categoryParentID: UUID? = nil,
        counterpartyName: String?,
        normalizedCounterpartyKey: String?
    ) {
        self.id = id
        self.primaryKind = primaryKind
        self.transferSubtype = transferSubtype
        self.debtIntent = debtIntent
        self.entryStatus = entryStatus
        self.title = title
        self.note = note
        self.amountMinor = amountMinor
        self.isArchived = isArchived
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.sourceWalletID = sourceWalletID
        self.sourceWalletKind = sourceWalletKind
        self.destinationWalletID = destinationWalletID
        self.destinationWalletKind = destinationWalletKind
        self.categoryID = categoryID
        self.categoryParentID = categoryParentID
        self.counterpartyName = counterpartyName
        self.normalizedCounterpartyKey = normalizedCounterpartyKey
    }
}

struct TransactionFilterState: Equatable {
    var isAdjustmentOnly: Bool = false
    var timeScope: TransactionTimeScope = .thisMonth
    var walletID: UUID?
    var categoryID: UUID?
    var transferSubtype: TransactionTransferSubtype?
    var statusScope: TransactionStatusScope = .all
    var minAmountMinor: Int64?
    var maxAmountMinor: Int64?
    var searchText = ""
}

struct TransactionSummarySnapshot: Equatable {
    let expenseMinor: Int64
    let incomeMinor: Int64
    let totalCount: Int
    let draftCount: Int
}

struct TransactionSectionSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let rows: [TransactionRecordSnapshot]
    let isDraftSection: Bool
}

struct TransactionVisibleRecordsPage: Equatable {
    let totalCount: Int
    let displayedRecords: [TransactionRecordSnapshot]
}

struct CounterpartyDebtSnapshot: Equatable, Identifiable {
    let id: String
    let displayName: String
    let netMinor: Int64

    var isReceivable: Bool {
        netMinor > 0
    }
}

struct TransactionTitleSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
}

nonisolated enum TransactionLogic {
    static func normalizeCounterpartyName(_ name: String?) -> String? {
        guard let trimmed = name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }

        let folded = trimmed
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: MistiaAppLanguage.current.locale
            )

        var normalized = ""
        var lastCharacterWasSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
                lastCharacterWasSeparator = false
            } else {
                guard !normalized.isEmpty, !lastCharacterWasSeparator else {
                    continue
                }
                normalized.append(" ")
                lastCharacterWasSeparator = true
            }
        }

        let collapsed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else {
            return nil
        }

        return collapsed.lowercased()
    }

    static func isAdjustment(_ record: TransactionRecordSnapshot) -> Bool {
        record.categoryID == MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID ||
        record.categoryID == MistiaSystemCategoryIdentity.balanceAdjustmentIncomeID
    }

    static func isInstallmentPayment(_ record: TransactionRecordSnapshot) -> Bool {
        record.categoryID == MistiaSystemCategoryIdentity.canonicalID(for: .loanRepayment)
    }

    static func isCreditCardPayment(_ record: TransactionRecordSnapshot) -> Bool {
        let titleLooksLikeCardPayment = isCreditCardPaymentTitle(record.title)
        if record.primaryKind == .transfer {
            guard record.transferSubtype == .internalTransfer else { return false }
            return record.destinationWalletKind == .creditCard
                || (record.destinationWalletID != nil && titleLooksLikeCardPayment)
        }

        return record.primaryKind == .expense
            && record.sourceWalletKind != .creditCard
            && titleLooksLikeCardPayment
    }

    static func isExpenseSpending(_ record: TransactionRecordSnapshot) -> Bool {
        record.primaryKind == .expense
            && !isAdjustment(record)
            && !isCreditCardPayment(record)
            && !isInstallmentPayment(record)
    }

    static func isCreditCardPaymentTitle(_ title: String) -> Bool {
        title.localizedStandardContains("thanh toán thẻ") ||
            title.localizedStandardContains("thanh toan the") ||
            title.localizedStandardContains("card payment") ||
            title.localizedStandardContains("カード支払い")
    }

    static func visibleRecords(
        from records: [TransactionRecordSnapshot],
        selectedKind: TransactionPrimaryKind?,
        filters: TransactionFilterState,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [TransactionRecordSnapshot] {
        records
            .filter {
                matchesVisibleRecord(
                    $0,
                    selectedKind: selectedKind,
                    filters: filters,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
            .sorted(by: recordSort)
    }

    static func visibleRecordsPage(
        from records: [TransactionRecordSnapshot],
        selectedKind: TransactionPrimaryKind?,
        filters: TransactionFilterState,
        limit: Int,
        assumesSortedByRecency: Bool = false,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> TransactionVisibleRecordsPage {
        let source = assumesSortedByRecency ? records : records.sorted(by: recordSort)
        let limit = max(limit, 0)
        var totalCount = 0
        var displayedRecords: [TransactionRecordSnapshot] = []
        displayedRecords.reserveCapacity(min(limit, source.count))

        for record in source where matchesVisibleRecord(
            record,
            selectedKind: selectedKind,
            filters: filters,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
            totalCount += 1
            if displayedRecords.count < limit {
                displayedRecords.append(record)
            }
        }

        return TransactionVisibleRecordsPage(
            totalCount: totalCount,
            displayedRecords: displayedRecords
        )
    }

    static func summary(for records: [TransactionRecordSnapshot]) -> TransactionSummarySnapshot {
        let posted = records.filter { $0.entryStatus == .posted }
        let expenseMinor = posted
            .filter(isExpenseSpending)
            .reduce(into: Int64.zero) { partialResult, record in
                partialResult += record.amountMinor
            }
        let incomeMinor = posted
            .filter { $0.primaryKind == .income }
            .reduce(into: Int64.zero) { partialResult, record in
                partialResult += record.amountMinor
            }

        return TransactionSummarySnapshot(
            expenseMinor: expenseMinor,
            incomeMinor: incomeMinor,
            totalCount: records.count,
            draftCount: records.filter { $0.entryStatus == .draft }.count
        )
    }

    static func sections(
        from records: [TransactionRecordSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [TransactionSectionSnapshot] {
        var builtSections: [TransactionSectionSnapshot] = []

        let drafts = records
            .filter { $0.entryStatus == .draft }
            .sorted(by: recordSort)

        if !drafts.isEmpty {
            builtSections.append(
                TransactionSectionSnapshot(
                    id: "drafts",
                    title: L10n.shared.corelogic.transaction.needsCompletion,
                    rows: drafts,
                    isDraftSection: true
                )
            )
        }

        let posted = records
            .filter { $0.entryStatus == .posted }
            .sorted(by: recordSort)

        let groups = Dictionary(grouping: posted) { calendar.startOfDay(for: $0.occurredAt) }
        let sortedDays = groups.keys.sorted(by: >)

        let language = MistiaAppLanguage.current

        for day in sortedDays {
            let startOfReference = calendar.startOfDay(for: referenceDate)
            let startOfDay = calendar.startOfDay(for: day)
            let dayDelta = calendar.dateComponents([.day], from: startOfDay, to: startOfReference).day ?? 0
            let title = MistiaDateFormatting.relativeDayLabel(for: dayDelta, language: language)
                ?? MistiaDateFormatting.fullDateString(for: day, language: language, calendar: calendar)

            builtSections.append(
                TransactionSectionSnapshot(
                    id: "day-\(day.timeIntervalSince1970)",
                    title: title,
                    rows: groups[day, default: []].sorted(by: recordSort),
                    isDraftSection: false
                )
            )
        }

        return builtSections
    }

    static func openDebtPositions(
        from records: [TransactionRecordSnapshot]
    ) -> [CounterpartyDebtSnapshot] {
        let grouped = Dictionary(grouping: records) { $0.normalizedCounterpartyKey ?? UUID().uuidString }
        return grouped.compactMap { key, groupedRecords in
            guard let first = groupedRecords.first,
                  let normalizedKey = first.normalizedCounterpartyKey,
                  !normalizedKey.isEmpty
            else {
                return nil
            }

            let total = groupedRecords
                .filter { $0.entryStatus == .posted && $0.primaryKind == .transfer && $0.transferSubtype == .debt }
                .reduce(into: Int64.zero) { partialResult, record in
                    switch record.debtIntent {
                    case .lend:
                        partialResult += record.amountMinor
                    case .collect:
                        partialResult -= record.amountMinor
                    case .borrow:
                        partialResult -= record.amountMinor
                    case .repay:
                        partialResult += record.amountMinor
                    case nil:
                        break
                    }
                }

            guard total != 0 else { return nil }

            return CounterpartyDebtSnapshot(
                id: normalizedKey,
                displayName: groupedRecords
                    .compactMap(\.counterpartyName)
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? L10n.shared.corelogic.transaction.unknownName,
                netMinor: total
            )
        }
        .sorted {
            if abs($0.netMinor) != abs($1.netMinor) {
                return abs($0.netMinor) > abs($1.netMinor)
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func titleSuggestions(
        from records: [TransactionRecordSnapshot],
        query: String,
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        excludingTransactionID: UUID? = nil,
        limit: Int = 5
    ) -> [TransactionTitleSuggestion] {
        guard limit > 0,
              let normalizedQuery = normalizeCounterpartyName(query),
              !normalizedQuery.isEmpty
        else {
            return []
        }

        let groupedMatches = Dictionary(grouping: records) { record in
            titleSuggestionGroupingKey(record.title) ?? record.id.uuidString
        }

        let rankedSuggestions: [
            (
                suggestion: TransactionTitleSuggestion,
                matchRank: Int,
                latestOccurredAt: Date,
                latestCreatedAt: Date,
                usageCount: Int
            )
        ] = groupedMatches.compactMap { entry in
            let normalizedTitle = entry.key
            let groupedRecords = entry.value
            let matchingRecords = groupedRecords.filter { record in
                guard record.id != excludingTransactionID,
                      record.entryStatus == .posted,
                      matchesTitleSuggestionScope(
                        record,
                        primaryKind: primaryKind,
                        transferSubtype: transferSubtype
                      ),
                      !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return false
                }

                return true
            }

            guard let representative = matchingRecords.sorted(by: recordSort).first,
                  let representativeKey = normalizeCounterpartyName(representative.title),
                  let matchRank = titleSuggestionMatchRank(
                    query: normalizedQuery,
                    normalizedTitle: representativeKey
                  )
            else {
                return nil
            }

            return (
                suggestion: TransactionTitleSuggestion(
                    id: normalizedTitle,
                    title: representative.title.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                matchRank: matchRank,
                latestOccurredAt: representative.occurredAt,
                latestCreatedAt: representative.createdAt,
                usageCount: matchingRecords.count
            )
        }

        return rankedSuggestions
            .sorted { lhs, rhs in
                if lhs.matchRank != rhs.matchRank {
                    return lhs.matchRank < rhs.matchRank
                }

                if lhs.latestOccurredAt != rhs.latestOccurredAt {
                    return lhs.latestOccurredAt > rhs.latestOccurredAt
                }

                if lhs.latestCreatedAt != rhs.latestCreatedAt {
                    return lhs.latestCreatedAt > rhs.latestCreatedAt
                }

                if lhs.usageCount != rhs.usageCount {
                    return lhs.usageCount > rhs.usageCount
                }

                return lhs.suggestion.title.localizedCaseInsensitiveCompare(rhs.suggestion.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0.suggestion }
    }

    static func effectiveBalance(
        for wallet: TransactionWalletSnapshot,
        records: [TransactionRecordSnapshot]
    ) -> Int64 {
        records
            .filter { $0.entryStatus == .posted && !$0.isArchived }
            .reduce(wallet.openingBalanceMinor) { partialResult, record in
                partialResult + balanceDelta(for: wallet, record: record)
            }
    }

    static func walletBalanceIndex(
        wallets: [TransactionWalletSnapshot],
        records: [TransactionRecordSnapshot]
    ) -> TransactionWalletBalanceIndex {
        var balancesByWalletID: [UUID: Int64] = [:]
        var kindByWalletID: [UUID: LedgerWalletKind] = [:]

        for wallet in wallets {
            balancesByWalletID[wallet.id] = wallet.openingBalanceMinor
            kindByWalletID[wallet.id] = wallet.kind
        }

        func applyDelta(
            walletID: UUID?,
            explicitKind: LedgerWalletKind?,
            amount: Int64,
            delta: (LedgerWalletKind, Int64) -> Int64
        ) {
            guard let walletID,
                  let walletKind = explicitKind ?? kindByWalletID[walletID] else {
                return
            }

            balancesByWalletID[walletID, default: 0] += delta(walletKind, amount)
        }

        for record in records where record.entryStatus == .posted && !record.isArchived {
            switch record.primaryKind {
            case .expense:
                applyDelta(
                    walletID: record.sourceWalletID,
                    explicitKind: record.sourceWalletKind,
                    amount: record.amountMinor,
                    delta: { kind, amount in outgoingDelta(for: kind, amount: amount) }
                )
            case .income:
                applyDelta(
                    walletID: record.sourceWalletID,
                    explicitKind: record.sourceWalletKind,
                    amount: record.amountMinor,
                    delta: { kind, amount in incomingDelta(for: kind, amount: amount) }
                )
            case .transfer:
                switch record.transferSubtype {
                case .internalTransfer:
                    applyDelta(
                        walletID: record.sourceWalletID,
                        explicitKind: record.sourceWalletKind,
                        amount: record.amountMinor,
                        delta: { kind, amount in outgoingDelta(for: kind, amount: amount) }
                    )
                    applyDelta(
                        walletID: record.destinationWalletID,
                        explicitKind: record.destinationWalletKind,
                        amount: record.amountMinor,
                        delta: { kind, amount in incomingDelta(for: kind, amount: amount) }
                    )
                case .familyTransfer:
                    let isIncoming = record.destinationWalletID == nil
                    applyDelta(
                        walletID: record.sourceWalletID,
                        explicitKind: record.sourceWalletKind,
                        amount: record.amountMinor,
                        delta: isIncoming
                            ? { kind, amount in incomingDelta(for: kind, amount: amount) }
                            : { kind, amount in outgoingDelta(for: kind, amount: amount) }
                    )
                case .debt:
                    switch record.debtIntent {
                    case .lend, .repay:
                        applyDelta(
                            walletID: record.sourceWalletID,
                            explicitKind: record.sourceWalletKind,
                            amount: record.amountMinor,
                            delta: { kind, amount in outgoingDelta(for: kind, amount: amount) }
                        )
                    case .collect, .borrow:
                        applyDelta(
                            walletID: record.sourceWalletID,
                            explicitKind: record.sourceWalletKind,
                            amount: record.amountMinor,
                            delta: { kind, amount in incomingDelta(for: kind, amount: amount) }
                        )
                    case nil:
                        break
                    }
                case nil:
                    break
                }
            }
        }

        return TransactionWalletBalanceIndex(balancesByWalletID: balancesByWalletID)
    }

    static func cashflowAmount(for record: TransactionRecordSnapshot) -> Int64 {
        switch record.primaryKind {
        case .expense:
            -record.amountMinor
        case .income:
            record.amountMinor
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                0
            case .familyTransfer:
                record.destinationWalletID == nil ? record.amountMinor : -record.amountMinor
            case .debt:
                switch record.debtIntent {
                case .lend, .repay:
                    -record.amountMinor
                case .collect, .borrow:
                    record.amountMinor
                case nil:
                    0
                }
            case nil:
                0
            }
        }
    }

    static func isTransactionComplete(_ record: TransactionRecordSnapshot) -> Bool {
        guard record.amountMinor > 0 else { return false }

        switch record.primaryKind {
        case .expense:
            return !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && record.sourceWalletID != nil
                && record.categoryID != nil
        case .income:
            return !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && record.sourceWalletID != nil
                && record.categoryID != nil
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                return record.sourceWalletID != nil
                    && record.destinationWalletID != nil
                    && record.sourceWalletID != record.destinationWalletID
            case .familyTransfer:
                return record.sourceWalletID != nil
            case .debt:
                return record.sourceWalletID != nil
                    && record.debtIntent != nil
                    && record.normalizedCounterpartyKey != nil
            case nil:
                return false
            }
        }
    }

    private static func matches(
        _ record: TransactionRecordSnapshot,
        filters: TransactionFilterState,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard matchesTime(record, scope: filters.timeScope, referenceDate: referenceDate, calendar: calendar) else {
            return false
        }

        if let walletID = filters.walletID,
           record.sourceWalletID != walletID && record.destinationWalletID != walletID {
            return false
        }

        if let categoryID = filters.categoryID, record.categoryID != categoryID && record.categoryParentID != categoryID {
            return false
        }

        if let transferSubtype = filters.transferSubtype,
           record.transferSubtype != transferSubtype {
            return false
        }

        switch filters.statusScope {
        case .all:
            break
        case .postedOnly:
            guard record.entryStatus == .posted else { return false }
        case .draftOnly:
            guard record.entryStatus == .draft else { return false }
        }

        if let minAmountMinor = filters.minAmountMinor, record.amountMinor < minAmountMinor {
            return false
        }

        if let maxAmountMinor = filters.maxAmountMinor, record.amountMinor > maxAmountMinor {
            return false
        }

        guard let query = normalizeCounterpartyName(filters.searchText), !query.isEmpty else {
            return true
        }

        let searchableFields = [
            normalizeCounterpartyName(record.title),
            normalizeCounterpartyName(record.counterpartyName),
            normalizeCounterpartyName(record.note)
        ]

        return searchableFields.contains { field in
            guard let field else { return false }
            return field.contains(query)
        }
    }

    private static func matchesVisibleRecord(
        _ record: TransactionRecordSnapshot,
        selectedKind: TransactionPrimaryKind?,
        filters: TransactionFilterState,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        if filters.isAdjustmentOnly {
            guard isAdjustment(record) else { return false }
        } else if selectedKind != nil, isAdjustment(record) {
            return false
        }

        guard selectedKind == nil || record.primaryKind == selectedKind else {
            return false
        }

        return matches(record, filters: filters, referenceDate: referenceDate, calendar: calendar)
    }

    private static func matchesTime(
        _ record: TransactionRecordSnapshot,
        scope: TransactionTimeScope,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        switch scope {
        case .allTime:
            return true
        case .thisMonth:
            guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
                return true
            }
            return monthInterval.contains(record.occurredAt)
        case .yesterday:
            guard let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) else {
                return false
            }
            return calendar.isDate(record.occurredAt, inSameDayAs: yesterdayDate)
        case .today:
            return calendar.isDate(record.occurredAt, inSameDayAs: referenceDate)
        }
    }

    private static func matchesTitleSuggestionScope(
        _ record: TransactionRecordSnapshot,
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype?
    ) -> Bool {
        guard record.primaryKind == primaryKind else {
            return false
        }

        guard primaryKind == .transfer else {
            return true
        }

        return record.transferSubtype == transferSubtype
    }

    private static func titleSuggestionMatchRank(
        query: String,
        normalizedTitle: String
    ) -> Int? {
        let condensedQuery = query.replacingOccurrences(of: " ", with: "")
        let condensedTitle = normalizedTitle.replacingOccurrences(of: " ", with: "")

        if normalizedTitle.hasPrefix(query) || condensedTitle.hasPrefix(condensedQuery) {
            return 0
        }

        if normalizedTitle.contains(" \(query)") {
            return 1
        }

        if normalizedTitle.contains(query) || condensedTitle.contains(condensedQuery) {
            return 2
        }

        return nil
    }

    private static func titleSuggestionGroupingKey(_ title: String?) -> String? {
        normalizeCounterpartyName(title)?
            .replacingOccurrences(of: " ", with: "")
    }

    private static func balanceDelta(
        for wallet: TransactionWalletSnapshot,
        record: TransactionRecordSnapshot
    ) -> Int64 {
        switch record.primaryKind {
        case .expense:
            guard record.sourceWalletID == wallet.id else { return 0 }
            return outgoingDelta(for: wallet.kind, amount: record.amountMinor)
        case .income:
            guard record.sourceWalletID == wallet.id else { return 0 }
            return incomingDelta(for: wallet.kind, amount: record.amountMinor)
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                var delta: Int64 = 0

                if record.sourceWalletID == wallet.id {
                    delta += outgoingDelta(for: wallet.kind, amount: record.amountMinor)
                }

                if record.destinationWalletID == wallet.id {
                    delta += incomingDelta(for: wallet.kind, amount: record.amountMinor)
                }

                return delta
            case .familyTransfer:
                guard record.sourceWalletID == wallet.id else { return 0 }
                return record.destinationWalletID == nil
                    ? incomingDelta(for: wallet.kind, amount: record.amountMinor)
                    : outgoingDelta(for: wallet.kind, amount: record.amountMinor)
            case .debt:
                guard record.sourceWalletID == wallet.id else { return 0 }

                switch record.debtIntent {
                case .lend, .repay:
                    return outgoingDelta(for: wallet.kind, amount: record.amountMinor)
                case .collect, .borrow:
                    return incomingDelta(for: wallet.kind, amount: record.amountMinor)
                case nil:
                    return 0
                }
            case nil:
                return 0
            }
        }
    }

    private static func outgoingDelta(for kind: LedgerWalletKind, amount: Int64) -> Int64 {
        switch kind {
        case .creditCard:
            amount
        case .cash, .payPay, .bank, .eWallet, .prepaid, .investment, .crypto, .other:
            -amount
        }
    }

    private static func incomingDelta(for kind: LedgerWalletKind, amount: Int64) -> Int64 {
        switch kind {
        case .creditCard:
            -amount
        case .cash, .payPay, .bank, .eWallet, .prepaid, .investment, .crypto, .other:
            amount
        }
    }

    nonisolated private static func recordSort(lhs: TransactionRecordSnapshot, rhs: TransactionRecordSnapshot) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }

    static func isLockedByPaidStatement(
        transaction: TransactionRecordSnapshot,
        allTransactions: [TransactionRecordSnapshot],
        calendar: Calendar = MistiaCalendar.current
    ) -> Bool {
        // Only expenses and internal transfers can be locked by a statement
        guard transaction.primaryKind == .expense || transaction.primaryKind == .transfer else {
            return false
        }
        
        // Find the relevant credit card wallet ID
        let creditCardWalletID: UUID?
        if transaction.primaryKind == .expense {
            // For expenses, the source wallet must be a credit card
            guard transaction.sourceWalletKind == .creditCard else { return false }
            creditCardWalletID = transaction.sourceWalletID
        } else {
            // For transfers, the destination wallet must be a credit card
            // and it must be an internal transfer (likely a payment)
            guard transaction.destinationWalletKind == .creditCard,
                  transaction.transferSubtype == .internalTransfer else { return false }
            creditCardWalletID = transaction.destinationWalletID
        }
        
        guard let walletID = creditCardWalletID else { return false }
        
        return allTransactions.contains { tx in
            tx.destinationWalletID == walletID &&
            tx.primaryKind == .transfer &&
            tx.transferSubtype == .internalTransfer &&
            tx.entryStatus == .posted &&
            !tx.isArchived &&
            isCreditCardPaymentTitle(tx.title) &&
            (
                paidStatementMonth(for: tx, calendar: calendar)
                    .map { calendar.isDate($0, equalTo: transaction.occurredAt, toGranularity: .month) }
                    ?? false
            )
        }
    }

    private static func paidStatementMonth(
        for payment: TransactionRecordSnapshot,
        calendar: Calendar
    ) -> Date? {
        explicitStatementMonth(in: payment.title, calendar: calendar)
            ?? calendar.dateInterval(of: .month, for: payment.occurredAt)?.start
    }

    private static func explicitStatementMonth(
        in title: String,
        calendar: Calendar
    ) -> Date? {
        let foldedTitle = title.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        if let captures = capturedGroups(matching: #"(?:thang|month)?\s*(\d{1,2})\s*/\s*(\d{4})"#, in: foldedTitle),
           let month = Int(captures[0]),
           let year = Int(captures[1]) {
            return statementMonth(month: month, year: year, calendar: calendar)
        }

        if let captures = capturedGroups(matching: #"thang\s*(\d{1,2})\s*(?:nam)?\s*(\d{4})"#, in: foldedTitle),
           let month = Int(captures[0]),
           let year = Int(captures[1]) {
            return statementMonth(month: month, year: year, calendar: calendar)
        }

        if let captures = capturedGroups(matching: #"(\d{4})\s*年\s*(\d{1,2})\s*月"#, in: title),
           let year = Int(captures[0]),
           let month = Int(captures[1]) {
            return statementMonth(month: month, year: year, calendar: calendar)
        }

        if let captures = capturedGroups(
            matching: #"\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|october|oct|november|nov|december|dec)\s+(\d{4})\b"#,
            in: foldedTitle
        ),
           let month = englishMonthNumber(captures[0]),
           let year = Int(captures[1]) {
            return statementMonth(month: month, year: year, calendar: calendar)
        }

        return nil
    }

    private static func capturedGroups(
        matching pattern: String,
        in text: String
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: fullRange),
              match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func statementMonth(
        month: Int,
        year: Int,
        calendar: Calendar
    ) -> Date? {
        guard (1...12).contains(month), (1900...9999).contains(year) else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components) else {
            return nil
        }
        return calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private static func englishMonthNumber(_ month: String) -> Int? {
        switch month {
        case "january", "jan":
            return 1
        case "february", "feb":
            return 2
        case "march", "mar":
            return 3
        case "april", "apr":
            return 4
        case "may":
            return 5
        case "june", "jun":
            return 6
        case "july", "jul":
            return 7
        case "august", "aug":
            return 8
        case "september", "sep":
            return 9
        case "october", "oct":
            return 10
        case "november", "nov":
            return 11
        case "december", "dec":
            return 12
        default:
            return nil
        }
    }
}

extension LedgerTransaction {
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
            isArchived: isArchived,
            occurredAt: occurredAt,
            createdAt: createdAt,
            sourceWalletID: sourceWallet?.id,
            sourceWalletKind: sourceWallet?.kind,
            destinationWalletID: destinationWallet?.id,
            destinationWalletKind: destinationWallet?.kind,
            categoryID: category?.id,
            categoryParentID: category?.parentCategory?.id,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
    }
}
