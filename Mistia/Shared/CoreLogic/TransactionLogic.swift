import Foundation

struct TransactionWalletSnapshot: Equatable, Identifiable {
    let id: UUID
    let kind: LedgerWalletKind
    let openingBalanceMinor: Int64
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
    let occurredAt: Date
    let createdAt: Date
    let sourceWalletID: UUID?
    let sourceWalletKind: LedgerWalletKind?
    let destinationWalletID: UUID?
    let destinationWalletKind: LedgerWalletKind?
    let categoryID: UUID?
    let counterpartyName: String?
    let normalizedCounterpartyKey: String?
}

struct TransactionFilterState: Equatable {
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

struct CounterpartyDebtSnapshot: Equatable, Identifiable {
    let id: String
    let displayName: String
    let netMinor: Int64

    var isReceivable: Bool {
        netMinor > 0
    }
}

enum TransactionLogic {
    static func normalizeCounterpartyName(_ name: String?) -> String? {
        guard let normalized = name?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty
        else {
            return nil
        }

        return normalized.lowercased()
    }

    static func visibleRecords(
        from records: [TransactionRecordSnapshot],
        selectedKind: TransactionPrimaryKind?,
        filters: TransactionFilterState,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [TransactionRecordSnapshot] {
        records
            .filter { record in
                guard selectedKind == nil || record.primaryKind == selectedKind else {
                    return false
                }

                return matches(record, filters: filters, referenceDate: referenceDate, calendar: calendar)
            }
            .sorted(by: recordSort)
    }

    static func summary(for records: [TransactionRecordSnapshot]) -> TransactionSummarySnapshot {
        let posted = records.filter { $0.entryStatus == .posted }
        let expenseMinor = posted
            .filter { $0.primaryKind == .expense }
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
        calendar: Calendar = .current
    ) -> [TransactionSectionSnapshot] {
        var builtSections: [TransactionSectionSnapshot] = []

        let drafts = records
            .filter { $0.entryStatus == .draft }
            .sorted(by: recordSort)

        if !drafts.isEmpty {
            builtSections.append(
                TransactionSectionSnapshot(
                    id: "drafts",
                    title: "Cần hoàn thiện",
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

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy"

        for day in sortedDays {
            let title: String

            if calendar.isDate(day, inSameDayAs: referenceDate) {
                title = "Hôm nay"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                      calendar.isDate(day, inSameDayAs: yesterday) {
                title = "Hôm qua"
            } else {
                title = formatter.string(from: day)
            }

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
                    ?? "Không rõ tên",
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

    static func effectiveBalance(
        for wallet: TransactionWalletSnapshot,
        records: [TransactionRecordSnapshot]
    ) -> Int64 {
        records
            .filter { $0.entryStatus == .posted }
            .reduce(wallet.openingBalanceMinor) { partialResult, record in
                partialResult + balanceDelta(for: wallet, record: record)
            }
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

        if let categoryID = filters.categoryID, record.categoryID != categoryID {
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
        case .cash, .payPay, .bank:
            -amount
        }
    }

    private static func incomingDelta(for kind: LedgerWalletKind, amount: Int64) -> Int64 {
        switch kind {
        case .creditCard:
            -amount
        case .cash, .payPay, .bank:
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
}
