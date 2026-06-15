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

nonisolated struct TransactionRecordSnapshot: Equatable, Identifiable {
    let id: UUID
    let primaryKind: TransactionPrimaryKind
    let transferSubtype: TransactionTransferSubtype?
    let debtIntent: TransactionDebtIntent?
    let entryStatus: TransactionEntryStatus
    let title: String
    let note: String?
    let amountMinor: Int64
    let settlementGroupID: UUID?
    let settlementObligationID: UUID?
    let settlementRole: SettlementTransactionRole?
    let reportingExpenseMinor: Int64?
    let reportingIncomeMinor: Int64?
    let sourceCurrencyCode: String?
    let destinationCurrencyCode: String?
    let destinationAmountMinor: Int64?
    let reportingCurrencyCode: String?
    let reportingAmountMinor: Int64?
    let conversionModeRawValue: String?
    let exchangeRateDecimalString: String?
    let exchangeRateProvider: String?
    let exchangeRateDate: String?
    let isArchived: Bool
    let occurredAt: Date
    let createdAt: Date
    let sourceWalletID: UUID?
    let sourceWalletKind: LedgerWalletKind?
    let destinationWalletID: UUID?
    let destinationWalletKind: LedgerWalletKind?
    let categoryID: UUID?
    let categoryName: String?
    let categoryParentID: UUID?
    let categoryParentName: String?
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
        settlementGroupID: UUID? = nil,
        settlementObligationID: UUID? = nil,
        settlementRole: SettlementTransactionRole? = nil,
        reportingExpenseMinor: Int64? = nil,
        reportingIncomeMinor: Int64? = nil,
        sourceCurrencyCode: String? = nil,
        destinationCurrencyCode: String? = nil,
        destinationAmountMinor: Int64? = nil,
        reportingCurrencyCode: String? = nil,
        reportingAmountMinor: Int64? = nil,
        conversionModeRawValue: String? = nil,
        exchangeRateDecimalString: String? = nil,
        exchangeRateProvider: String? = nil,
        exchangeRateDate: String? = nil,
        isArchived: Bool = false,
        occurredAt: Date,
        createdAt: Date,
        sourceWalletID: UUID?,
        sourceWalletKind: LedgerWalletKind?,
        destinationWalletID: UUID?,
        destinationWalletKind: LedgerWalletKind?,
        categoryID: UUID?,
        categoryName: String? = nil,
        categoryParentID: UUID? = nil,
        categoryParentName: String? = nil,
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
        self.settlementGroupID = settlementGroupID
        self.settlementObligationID = settlementObligationID
        self.settlementRole = settlementRole
        self.reportingExpenseMinor = reportingExpenseMinor
        self.reportingIncomeMinor = reportingIncomeMinor
        self.sourceCurrencyCode = sourceCurrencyCode
        self.destinationCurrencyCode = destinationCurrencyCode
        self.destinationAmountMinor = destinationAmountMinor
        self.reportingCurrencyCode = reportingCurrencyCode
        self.reportingAmountMinor = reportingAmountMinor
        self.conversionModeRawValue = conversionModeRawValue
        self.exchangeRateDecimalString = exchangeRateDecimalString
        self.exchangeRateProvider = exchangeRateProvider
        self.exchangeRateDate = exchangeRateDate
        self.isArchived = isArchived
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.sourceWalletID = sourceWalletID
        self.sourceWalletKind = sourceWalletKind
        self.destinationWalletID = destinationWalletID
        self.destinationWalletKind = destinationWalletKind
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryParentID = categoryParentID
        self.categoryParentName = categoryParentName
        self.counterpartyName = counterpartyName
        self.normalizedCounterpartyKey = normalizedCounterpartyKey
    }
}

nonisolated enum TransactionReceiptPersistencePolicy: Equatable {
    case persistLocally
    case ephemeral

    var canPersistReceiptImage: Bool {
        self == .persistLocally
    }

    var deletesStoredReceiptOnSave: Bool {
        self == .ephemeral
    }

    static func policy(
        ownerUserID: UUID?,
        activeLocalProfileUserID: UUID?
    ) -> TransactionReceiptPersistencePolicy {
        guard let ownerUserID,
              let activeLocalProfileUserID,
              ownerUserID != activeLocalProfileUserID
        else {
            return .persistLocally
        }

        return .ephemeral
    }
}

nonisolated enum TransactionReceiptAnalysisSource: Equatable {
    case initialScanner
    case modalPicker
    case prefill

    var shouldAnalyzeImmediately: Bool {
        self == .initialScanner
    }

    var usesManualAnalyzeButton: Bool {
        self == .modalPicker
    }
}

nonisolated enum TransactionReceiptAnalysisControlState: Equatable {
    case hidden
    case enabled
    case disabled

    static func state(
        for source: TransactionReceiptAnalysisSource?,
        hasReceiptDraft: Bool,
        hasAppliedAnalysis: Bool,
        isAnalyzing: Bool
    ) -> TransactionReceiptAnalysisControlState {
        guard hasReceiptDraft,
              source?.usesManualAnalyzeButton == true else {
            return .hidden
        }

        return hasAppliedAnalysis || isAnalyzing ? .disabled : .enabled
    }
}

struct TransactionFilterState: Equatable {
    var isAdjustmentOnly: Bool = false
    var isEventOnly: Bool = false
    var timeScope: TransactionTimeScope = .thisMonth
    var walletID: UUID?
    var categoryID: UUID?
    var transferSubtype: TransactionTransferSubtype?
    var counterpartyDebtKey: String?
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

nonisolated struct CounterpartyDebtSnapshot: Equatable, Identifiable {
    let id: String
    let displayName: String
    let normalizedCounterpartyKey: String
    let netMinor: Int64
    let currencyCode: String
    let preferredWalletID: UUID?
    let relatedRecords: [TransactionRecordSnapshot]

    init(
        id: String,
        displayName: String,
        normalizedCounterpartyKey: String = "",
        netMinor: Int64,
        currencyCode: String,
        preferredWalletID: UUID?,
        relatedRecords: [TransactionRecordSnapshot] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedCounterpartyKey = normalizedCounterpartyKey
        self.netMinor = netMinor
        self.currencyCode = currencyCode
        self.preferredWalletID = preferredWalletID
        self.relatedRecords = relatedRecords
    }

    var isReceivable: Bool {
        netMinor > 0
    }
}

struct TransactionTitleSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
}

nonisolated enum TransactionCrossCurrencyTransferDestinationDisplayStyle: Equatable {
    case exactDestination
    case approximateDestination
}

nonisolated struct TransactionCrossCurrencyTransferDestinationDisplay: Equatable {
    let amountMinor: Int64
    let currencyCode: String
    let style: TransactionCrossCurrencyTransferDestinationDisplayStyle
}

nonisolated struct SettlementResaleReceiptAllocation: Equatable {
    let expenseOffsetMinor: Int64
    let incomeMinor: Int64
    let settledMinor: Int64
    let remainingReceivableMinor: Int64
}

nonisolated struct SettlementDebtReportingOverride: Equatable {
    let expenseMinor: Int64
    let incomeMinor: Int64
}

nonisolated struct SettlementDebtPaymentAllocation: Equatable {
    let settlementGroupID: UUID?
    let settlementRole: SettlementTransactionRole?
    let amountMinor: Int64
    let reportingExpenseMinor: Int64
    let reportingIncomeMinor: Int64
}

nonisolated struct SettlementExpenseReportingAllocation: Equatable {
    let transactionID: UUID
    let reportingExpenseMinor: Int64
}

nonisolated struct SettlementGroupRecordSnapshot: Equatable, Identifiable {
    let id: UUID
    let kind: SettlementKind
    let status: SettlementStatus
    let title: String
    let currencyCode: String
    let occurredAt: Date
    let totalMinor: Int64
    let expectedMinor: Int64
    let settledMinor: Int64
    let note: String?
    let updatedAt: Date
    let isArchived: Bool
    let archivedAt: Date?

    init(
        id: UUID,
        kind: SettlementKind,
        status: SettlementStatus,
        title: String,
        currencyCode: String,
        occurredAt: Date,
        totalMinor: Int64,
        expectedMinor: Int64,
        settledMinor: Int64,
        note: String?,
        updatedAt: Date,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.currencyCode = currencyCode
        self.occurredAt = occurredAt
        self.totalMinor = totalMinor
        self.expectedMinor = expectedMinor
        self.settledMinor = settledMinor
        self.note = note
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }
}

nonisolated struct SettlementParticipantRecordSnapshot: Equatable, Identifiable {
    let id: UUID
    let groupID: UUID
    let displayName: String
    let normalizedKey: String?
    let memberUserID: UUID?
    let isSelf: Bool
    let sortOrder: Int
    let updatedAt: Date

    init(
        id: UUID,
        groupID: UUID,
        displayName: String,
        normalizedKey: String? = nil,
        memberUserID: UUID? = nil,
        isSelf: Bool,
        sortOrder: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.groupID = groupID
        self.displayName = displayName
        self.normalizedKey = normalizedKey
        self.memberUserID = memberUserID
        self.isSelf = isSelf
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}

nonisolated struct PreparingSettlementEventSnapshot: Equatable, Identifiable {
    let id: UUID
    let title: String
    let currencyCode: String
    let totalPaidMinor: Int64
    let billCount: Int
    let participantNames: [String]
    let note: String?
    let occurredAt: Date
    let lastUpdatedAt: Date
}

nonisolated struct SettlementParticipantInput: Equatable, Identifiable {
    let id: UUID
    let name: String
    let paidMinor: Int64

    init(
        id: UUID = UUID(),
        name: String,
        paidMinor: Int64
    ) {
        self.id = id
        self.name = name
        self.paidMinor = max(paidMinor, 0)
    }
}

nonisolated struct SettlementParticipantResult: Equatable, Identifiable {
    let id: UUID
    let name: String
    let paidMinor: Int64
    let shareMinor: Int64
    let netMinor: Int64
}

nonisolated struct SettlementSuggestionID: Equatable, Hashable {
    let payerID: UUID
    let receiverID: UUID
}

nonisolated struct SettlementSuggestion: Equatable, Identifiable {
    let payerID: UUID
    let receiverID: UUID
    let amountMinor: Int64

    var id: SettlementSuggestionID {
        SettlementSuggestionID(payerID: payerID, receiverID: receiverID)
    }
}

nonisolated struct SettlementSharedExpenseResult: Equatable {
    let totalPaidMinor: Int64
    let participants: [SettlementParticipantResult]
    let suggestions: [SettlementSuggestion]
}

nonisolated enum SettlementLogic {
    static func canSavePreparingEvent(
        title: String,
        participantNames: [String]
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty
    }

    static func preparingEventSnapshots(
        groups: [SettlementGroupRecordSnapshot],
        participants: [SettlementParticipantRecordSnapshot],
        records: [TransactionRecordSnapshot]
    ) -> [PreparingSettlementEventSnapshot] {
        let participantsByGroupID = Dictionary(grouping: participants) { $0.groupID }
        let recordsByGroupID = Dictionary(
            grouping: records.filter(isSharedExpenseEventBill)
        ) { record in
            record.settlementGroupID ?? UUID()
        }

        return groups
            .filter { $0.kind == .sharedExpense && $0.status != .settled && !$0.isArchived }
            .map { group in
                let groupParticipants = participantsByGroupID[group.id] ?? []
                let visibleParticipantNames = groupParticipants
                    .filter { !$0.isSelf }
                    .sorted(by: participantSort)
                    .map(\.displayName)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let billRecords = recordsByGroupID[group.id] ?? []
                let totalPaid = billRecords.reduce(Int64.zero) { total, record in
                    total + max(record.amountMinor, 0)
                }
                let latestRecordDate = billRecords.map(\.occurredAt).max()
                let latestParticipantDate = groupParticipants.map(\.updatedAt).max()
                let lastUpdatedAt = [
                    group.updatedAt,
                    latestRecordDate,
                    latestParticipantDate
                ]
                    .compactMap { $0 }
                    .max() ?? group.updatedAt

                return PreparingSettlementEventSnapshot(
                    id: group.id,
                    title: group.title,
                    currencyCode: group.currencyCode,
                    totalPaidMinor: totalPaid,
                    billCount: billRecords.count,
                    participantNames: visibleParticipantNames,
                    note: group.note,
                    occurredAt: group.occurredAt,
                    lastUpdatedAt: lastUpdatedAt
                )
            }
            .sorted {
                if $0.lastUpdatedAt != $1.lastUpdatedAt {
                    return $0.lastUpdatedAt > $1.lastUpdatedAt
                }
                return $0.occurredAt > $1.occurredAt
            }
    }

    static func allEventSnapshots(
        groups: [SettlementGroupRecordSnapshot],
        participants: [SettlementParticipantRecordSnapshot],
        records: [TransactionRecordSnapshot]
    ) -> [PreparingSettlementEventSnapshot] {
        let participantsByGroupID = Dictionary(grouping: participants) { $0.groupID }
        let recordsByGroupID = Dictionary(
            grouping: records.filter(isSharedExpenseEventBill)
        ) { record in
            record.settlementGroupID ?? UUID()
        }

        return groups
            .filter { $0.kind == .sharedExpense && (!$0.isArchived || $0.status == .settled) }
            .map { group in
                let groupParticipants = participantsByGroupID[group.id] ?? []
                let visibleParticipantNames = groupParticipants
                    .filter { !$0.isSelf }
                    .sorted(by: participantSort)
                    .map(\.displayName)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let billRecords = recordsByGroupID[group.id] ?? []
                let totalPaid = billRecords.reduce(Int64.zero) { total, record in
                    total + max(record.amountMinor, 0)
                }
                let latestRecordDate = billRecords.map(\.occurredAt).max()
                let latestParticipantDate = groupParticipants.map(\.updatedAt).max()
                let lastUpdatedAt = [
                    group.updatedAt,
                    latestRecordDate,
                    latestParticipantDate
                ]
                    .compactMap { $0 }
                    .max() ?? group.updatedAt

                return PreparingSettlementEventSnapshot(
                    id: group.id,
                    title: group.title,
                    currencyCode: group.currencyCode,
                    totalPaidMinor: totalPaid,
                    billCount: billRecords.count,
                    participantNames: visibleParticipantNames,
                    note: group.note,
                    occurredAt: group.occurredAt,
                    lastUpdatedAt: lastUpdatedAt
                )
            }
    }

    static func completedEventSnapshots(
        allEvents: [PreparingSettlementEventSnapshot],
        preparingEvents: [PreparingSettlementEventSnapshot]
    ) -> [PreparingSettlementEventSnapshot] {
        let preparingEventIDs = Set(preparingEvents.map(\.id))
        return allEvents.filter { !preparingEventIDs.contains($0.id) }
    }

    static func participantSuggestionRecords(
        from records: [TransactionRecordSnapshot],
        transactionOwnerMap: [UUID: UUID],
        walletOwnerMap: [UUID: UUID] = [:],
        currentUserID: UUID?,
        limit: Int = 500
    ) -> [TransactionRecordSnapshot] {
        guard limit > 0 else { return [] }

        var scopedRecords: [TransactionRecordSnapshot] = []
        scopedRecords.reserveCapacity(min(records.count, limit))
        for record in records {
            if let currentUserID {
                let ownerUserID = transactionOwnerMap[record.id]
                    ?? ownerUserID(forWalletID: record.sourceWalletID, ownerMap: walletOwnerMap)
                    ?? ownerUserID(forWalletID: record.destinationWalletID, ownerMap: walletOwnerMap)
                    ?? currentUserID
                guard ownerUserID == currentUserID else { continue }
            }
            scopedRecords.append(record)
            if scopedRecords.count == limit {
                break
            }
        }
        return scopedRecords
    }

    private static func ownerUserID(
        forWalletID walletID: UUID?,
        ownerMap: [UUID: UUID]
    ) -> UUID? {
        guard let walletID else { return nil }
        return ownerMap[walletID]
    }

    static func sharedExpenseInputsForFinalization(
        selfParticipant: SettlementParticipantRecordSnapshot,
        participants: [SettlementParticipantRecordSnapshot],
        records: [TransactionRecordSnapshot]
    ) -> [SettlementParticipantInput] {
        let groupID = selfParticipant.groupID
        let selfPaidMinor = records
            .filter { $0.settlementGroupID == groupID && isSharedExpenseEventBill($0) }
            .reduce(Int64.zero) { total, record in
                total + max(record.amountMinor, 0)
            }

        let selfInput = SettlementParticipantInput(
            id: selfParticipant.id,
            name: selfParticipant.displayName,
            paidMinor: selfPaidMinor
        )
        let otherInputs = participants
            .filter { $0.groupID == groupID && !$0.isSelf }
            .sorted(by: participantSort)
            .map {
                SettlementParticipantInput(
                    id: $0.id,
                    name: $0.displayName,
                    paidMinor: 0
                )
            }

        return [selfInput] + otherInputs
    }

    private static func isSharedExpenseEventBill(
        _ record: TransactionRecordSnapshot
    ) -> Bool {
        record.settlementGroupID != nil
            && record.settlementRole == .sharedExpensePaid
            && record.entryStatus == .posted
            && !record.isArchived
    }

    private static func participantSort(
        lhs: SettlementParticipantRecordSnapshot,
        rhs: SettlementParticipantRecordSnapshot
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    static func resaleReceiptAllocation(
        costMinor: Int64,
        saleMinor: Int64,
        priorReceiptMinor: Int64,
        paymentMinor: Int64
    ) -> SettlementResaleReceiptAllocation {
        let cost = max(costMinor, 0)
        let sale = max(saleMinor, 0)
        let prior = min(max(priorReceiptMinor, 0), sale)
        let payment = min(max(paymentMinor, 0), max(sale - prior, 0))
        let settled = prior + payment
        let costRecoveredBeforePayment = min(prior, cost)
        let costRecoveredAfterPayment = min(settled, cost)
        let expenseOffset = max(costRecoveredAfterPayment - costRecoveredBeforePayment, 0)
        let income = max(payment - expenseOffset, 0)

        return SettlementResaleReceiptAllocation(
            expenseOffsetMinor: expenseOffset,
            incomeMinor: income,
            settledMinor: settled,
            remainingReceivableMinor: max(sale - settled, 0)
        )
    }

    static func sharedExpenseDebtReportingOverride(
        settlementIntent: TransactionDebtIntent,
        amountMinor: Int64
    ) -> SettlementDebtReportingOverride {
        switch settlementIntent {
        case .collect, .repay, .lend, .borrow:
            return SettlementDebtReportingOverride(expenseMinor: 0, incomeMinor: 0)
        }
    }

    static func sharedExpensePaidReportingAllocations(
        records: [TransactionRecordSnapshot],
        selfShareMinor: Int64
    ) -> [SettlementExpenseReportingAllocation] {
        let eventBills = records
            .filter(isSharedExpenseEventBill)
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        let totalPaidMinor = eventBills.reduce(Int64.zero) { total, record in
            total + max(record.amountMinor, 0)
        }
        let targetExpenseMinor = max(selfShareMinor, 0)
        guard totalPaidMinor > 0, !eventBills.isEmpty else { return [] }

        var allocatedMinor = Int64.zero
        return eventBills.enumerated().map { index, record in
            let amountMinor = max(record.amountMinor, 0)
            let reportingExpenseMinor: Int64
            if index == eventBills.count - 1 {
                reportingExpenseMinor = targetExpenseMinor - allocatedMinor
            } else {
                reportingExpenseMinor = amountMinor * targetExpenseMinor / totalPaidMinor
                allocatedMinor += reportingExpenseMinor
            }
            return SettlementExpenseReportingAllocation(
                transactionID: record.id,
                reportingExpenseMinor: reportingExpenseMinor
            )
        }
    }

    static func sharedExpenseDebtPaymentAllocations(
        from records: [TransactionRecordSnapshot],
        settlementIntent: TransactionDebtIntent,
        paymentMinor: Int64
    ) -> [SettlementDebtPaymentAllocation] {
        let payment = max(paymentMinor, 0)
        guard payment > 0 else { return [] }
        guard settlementIntent == .collect || settlementIntent == .repay else {
            return [
                SettlementDebtPaymentAllocation(
                    settlementGroupID: nil,
                    settlementRole: nil,
                    amountMinor: payment,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                )
            ]
        }

        let principalIntent: TransactionDebtIntent = settlementIntent == .collect ? .lend : .borrow
        let paymentIntent: TransactionDebtIntent = settlementIntent
        let groupedEventRecords = Dictionary(
            grouping: records.filter { record in
                record.settlementGroupID != nil
                    && record.transferSubtype == .debt
                    && (record.debtIntent == principalIntent || record.debtIntent == paymentIntent)
            }
        ) { record in
            record.settlementGroupID ?? UUID()
        }

        let eventOpenAmounts: [(groupID: UUID, amount: Int64, occurredAt: Date)] = groupedEventRecords.compactMap { groupID, groupedRecords in
            let principal = groupedRecords.reduce(Int64.zero) { total, record in
                record.debtIntent == principalIntent ? total + max(record.amountMinor, 0) : total
            }
            let settled = groupedRecords.reduce(Int64.zero) { total, record in
                record.debtIntent == paymentIntent ? total + max(record.amountMinor, 0) : total
            }
            let open = max(principal - settled, 0)
            guard open > 0 else { return nil }
            let firstOccurredAt = groupedRecords.map(\.occurredAt).min() ?? .distantFuture
            return (groupID: groupID, amount: open, occurredAt: firstOccurredAt)
        }
        .sorted {
            if $0.occurredAt != $1.occurredAt {
                return $0.occurredAt < $1.occurredAt
            }
            return $0.groupID.uuidString < $1.groupID.uuidString
        }

        var remaining = payment
        var allocations: [SettlementDebtPaymentAllocation] = []
        for eventOpenAmount in eventOpenAmounts where remaining > 0 {
            let allocated = min(eventOpenAmount.amount, remaining)
            let override = sharedExpenseDebtReportingOverride(
                settlementIntent: settlementIntent,
                amountMinor: allocated
            )
            allocations.append(
                SettlementDebtPaymentAllocation(
                    settlementGroupID: eventOpenAmount.groupID,
                    settlementRole: settlementIntent == .collect ? .sharedExpenseReceipt : .sharedExpensePayment,
                    amountMinor: allocated,
                    reportingExpenseMinor: override.expenseMinor,
                    reportingIncomeMinor: override.incomeMinor
                )
            )
            remaining -= allocated
        }

        if settlementIntent == .collect,
           remaining > 0,
           let resaleAllocation = resaleDebtPaymentAllocation(
            from: records,
            paymentMinor: remaining
           ) {
            allocations.append(resaleAllocation)
            remaining -= resaleAllocation.amountMinor
        }

        if remaining > 0 {
            allocations.append(
                SettlementDebtPaymentAllocation(
                    settlementGroupID: nil,
                    settlementRole: nil,
                    amountMinor: remaining,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                )
            )
        }

        return allocations
    }

    private static func resaleDebtPaymentAllocation(
        from records: [TransactionRecordSnapshot],
        paymentMinor: Int64
    ) -> SettlementDebtPaymentAllocation? {
        var remainingPayment = max(paymentMinor, 0)
        guard remainingPayment > 0 else { return nil }

        var priorReceiptMinor = records.reduce(Int64.zero) { total, record in
            guard record.transferSubtype == .debt,
                  record.debtIntent == .collect,
                  record.settlementRole == .resaleReceipt
            else {
                return total
            }
            return total + max(record.amountMinor, 0)
        }

        var allocatedMinor = Int64.zero
        var expenseOffsetMinor = Int64.zero
        var incomeMinor = Int64.zero
        let principalRecords = records
            .filter(TransactionLogic.isResaleReceivableDebtPrincipal)
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        for principal in principalRecords where remainingPayment > 0 {
            let saleMinor = max(principal.amountMinor, 0)
            guard saleMinor > 0 else { continue }
            let consumedPrior = min(priorReceiptMinor, saleMinor)
            priorReceiptMinor -= consumedPrior
            let openMinor = max(saleMinor - consumedPrior, 0)
            guard openMinor > 0 else { continue }

            let payment = min(openMinor, remainingPayment)
            let allocation = resaleReceiptAllocation(
                costMinor: TransactionLogic.resaleReceivablePurchaseCostMinor(for: principal),
                saleMinor: saleMinor,
                priorReceiptMinor: consumedPrior,
                paymentMinor: payment
            )
            allocatedMinor += payment
            expenseOffsetMinor += allocation.expenseOffsetMinor
            incomeMinor += allocation.incomeMinor
            remainingPayment -= payment
        }

        guard allocatedMinor > 0 else { return nil }
        return SettlementDebtPaymentAllocation(
            settlementGroupID: nil,
            settlementRole: .resaleReceipt,
            amountMinor: allocatedMinor,
            reportingExpenseMinor: -expenseOffsetMinor,
            reportingIncomeMinor: incomeMinor
        )
    }

    static func sharedExpenseSettlement(
        participants: [SettlementParticipantInput],
        organizerID: UUID
    ) -> SettlementSharedExpenseResult {
        let totalPaid = participants.reduce(into: Int64.zero) { partial, participant in
            partial += participant.paidMinor
        }
        guard !participants.isEmpty else {
            return SettlementSharedExpenseResult(totalPaidMinor: 0, participants: [], suggestions: [])
        }

        let equalShare = totalPaid / Int64(participants.count)
        let remainder = totalPaid % Int64(participants.count)
        let results = participants.map { participant in
            let share = equalShare + (participant.id == organizerID ? remainder : 0)
            return SettlementParticipantResult(
                id: participant.id,
                name: participant.name,
                paidMinor: participant.paidMinor,
                shareMinor: share,
                netMinor: participant.paidMinor - share
            )
        }

        let suggestions = settlementSuggestions(from: results)
        return SettlementSharedExpenseResult(
            totalPaidMinor: totalPaid,
            participants: results,
            suggestions: suggestions
        )
    }

    static func applyingDebtAmountOverrides(
        to suggestions: [SettlementSuggestion],
        overridesBySuggestionID: [SettlementSuggestionID: Int64]
    ) -> [SettlementSuggestion] {
        suggestions.map { suggestion in
            guard let override = overridesBySuggestionID[suggestion.id],
                  override > 0 else {
                return suggestion
            }

            return SettlementSuggestion(
                payerID: suggestion.payerID,
                receiverID: suggestion.receiverID,
                amountMinor: override
            )
        }
    }

    private static func settlementSuggestions(
        from participants: [SettlementParticipantResult]
    ) -> [SettlementSuggestion] {
        var payers = participants
            .filter { $0.netMinor < 0 }
            .map { (id: $0.id, amount: -$0.netMinor) }
        var receivers = participants
            .filter { $0.netMinor > 0 }
            .map { (id: $0.id, amount: $0.netMinor) }
        var suggestions: [SettlementSuggestion] = []
        var payerIndex = 0
        var receiverIndex = 0

        while payerIndex < payers.count, receiverIndex < receivers.count {
            let amount = min(payers[payerIndex].amount, receivers[receiverIndex].amount)
            if amount > 0 {
                suggestions.append(
                    SettlementSuggestion(
                        payerID: payers[payerIndex].id,
                        receiverID: receivers[receiverIndex].id,
                        amountMinor: amount
                    )
                )
            }
            payers[payerIndex].amount -= amount
            receivers[receiverIndex].amount -= amount
            if payers[payerIndex].amount == 0 {
                payerIndex += 1
            }
            if receivers[receiverIndex].amount == 0 {
                receiverIndex += 1
            }
        }

        return suggestions
    }
}

nonisolated enum TransactionLogic {
    static func crossCurrencyTransferDestinationDisplay(
        for record: TransactionRecordSnapshot
    ) -> TransactionCrossCurrencyTransferDestinationDisplay? {
        guard record.primaryKind == .transfer,
              record.transferSubtype == .internalTransfer || record.transferSubtype == .familyTransfer,
              let destinationAmountMinor = record.destinationAmountMinor,
              let destinationCurrencyCode = record.destinationCurrencyCode
        else {
            return nil
        }

        let sourceCurrencyCode = MistiaCurrencyLogic.normalizedCode(record.sourceCurrencyCode)
        let normalizedDestinationCurrencyCode = MistiaCurrencyLogic.normalizedCode(destinationCurrencyCode)
        guard sourceCurrencyCode != normalizedDestinationCurrencyCode else {
            return nil
        }

        let conversionMode = MistiaCurrencyConversionMode(rawValue: record.conversionModeRawValue ?? "")
        return TransactionCrossCurrencyTransferDestinationDisplay(
            amountMinor: destinationAmountMinor,
            currencyCode: normalizedDestinationCurrencyCode,
            style: conversionMode == .manual ? .exactDestination : .approximateDestination
        )
    }

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

    static func debtIntentAllowsCreditCardWallet(_ intent: TransactionDebtIntent?) -> Bool {
        intent == .lend
    }

    static func isCreditCardDebtLending(_ record: TransactionRecordSnapshot) -> Bool {
        record.primaryKind == .transfer
            && record.transferSubtype == .debt
            && record.debtIntent == .lend
            && record.sourceWalletKind == .creditCard
    }

    static func isCreditCardStatementCharge(_ record: TransactionRecordSnapshot) -> Bool {
        isExpenseSpending(record) || isCreditCardDebtLending(record)
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
        if isPaidForExpenseDebt(record) {
            return true
        }

        return record.primaryKind == .expense
            && !isAdjustment(record)
            && !isCreditCardPayment(record)
            && !isInstallmentPayment(record)
    }

    static func reportedExpenseAmount(for record: TransactionRecordSnapshot) -> Int64 {
        if let reportingExpenseMinor = record.reportingExpenseMinor {
            return reportingExpenseMinor
        }
        return isExpenseSpending(record) ? record.amountMinor : 0
    }

    static func reportedIncomeAmount(for record: TransactionRecordSnapshot) -> Int64 {
        if let reportingIncomeMinor = record.reportingIncomeMinor {
            return reportingIncomeMinor
        }
        return record.primaryKind == .income ? record.amountMinor : 0
    }

    static func isPaidForDebt(_ record: TransactionRecordSnapshot) -> Bool {
        record.primaryKind == .transfer
            && record.transferSubtype == .debt
            && record.debtIntent == .borrow
            && record.sourceWalletID == nil
    }

    static func isSharedExpenseDebtPrincipal(_ record: TransactionRecordSnapshot) -> Bool {
        record.primaryKind == .transfer
            && record.transferSubtype == .debt
            && (record.settlementRole == .sharedExpenseReceivable || record.settlementRole == .sharedExpensePayable)
    }

    static func isEventGeneratedSharedExpenseDebtPrincipal(_ record: TransactionRecordSnapshot) -> Bool {
        record.settlementGroupID != nil
            && isSharedExpenseDebtPrincipal(record)
    }

    static func isResaleReceivableDebtPrincipal(_ record: TransactionRecordSnapshot) -> Bool {
        record.primaryKind == .transfer
            && record.transferSubtype == .debt
            && record.debtIntent == .lend
            && record.settlementRole == .resaleReceivable
    }

    static func resaleReceivablePurchaseCostMinor(for record: TransactionRecordSnapshot) -> Int64 {
        guard isResaleReceivableDebtPrincipal(record) else {
            return max(record.amountMinor, 0)
        }
        return max(record.reportingExpenseMinor ?? 0, 0)
    }

    static func isPaidForExpenseDebt(_ record: TransactionRecordSnapshot) -> Bool {
        isPaidForDebt(record)
            && record.categoryID != nil
            && !isAdjustment(record)
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
        var expenseMinor = Int64.zero
        var incomeMinor = Int64.zero
        var draftCount = 0

        for record in records {
            switch record.entryStatus {
            case .draft:
                draftCount += 1
            case .posted:
                expenseMinor += reportedExpenseAmount(for: record)
                incomeMinor += reportedIncomeAmount(for: record)
            }
        }

        return TransactionSummarySnapshot(
            expenseMinor: expenseMinor,
            incomeMinor: incomeMinor,
            totalCount: records.count,
            draftCount: draftCount
        )
    }

    static func sections(
        from records: [TransactionRecordSnapshot],
        assumesSortedByRecency: Bool = false,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> [TransactionSectionSnapshot] {
        var builtSections: [TransactionSectionSnapshot] = []
        var drafts: [TransactionRecordSnapshot] = []
        var postedByDay: [Date: [TransactionRecordSnapshot]] = [:]
        var postedDays: [Date] = []

        for record in records {
            switch record.entryStatus {
            case .draft:
                drafts.append(record)
            case .posted:
                let day = calendar.startOfDay(for: record.occurredAt)
                if postedByDay[day] == nil {
                    postedDays.append(day)
                }
                postedByDay[day, default: []].append(record)
            }
        }

        if !assumesSortedByRecency {
            drafts.sort(by: recordSort)
            postedDays.sort(by: >)
        }

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

        let language = MistiaAppLanguage.current
        let startOfReference = calendar.startOfDay(for: referenceDate)

        for day in postedDays {
            let startOfDay = calendar.startOfDay(for: day)
            let dayDelta = calendar.dateComponents([.day], from: startOfDay, to: startOfReference).day ?? 0
            let title = MistiaDateFormatting.relativeDayLabel(for: dayDelta, language: language)
                ?? MistiaDateFormatting.fullDateString(for: day, language: language, calendar: calendar)
            let rows = assumesSortedByRecency
                ? postedByDay[day, default: []]
                : postedByDay[day, default: []].sorted(by: recordSort)

            builtSections.append(
                TransactionSectionSnapshot(
                    id: "day-\(day.timeIntervalSince1970)",
                    title: title,
                    rows: rows,
                    isDraftSection: false
                )
            )
        }

        return builtSections
    }

    static func openDebtPositions(
        from records: [TransactionRecordSnapshot]
    ) -> [CounterpartyDebtSnapshot] {
        let debtRecords = records.filter {
            $0.entryStatus == .posted
                && $0.primaryKind == .transfer
                && $0.transferSubtype == .debt
        }
        let grouped = Dictionary(grouping: debtRecords) { record in
            let counterpartyKey = record.normalizedCounterpartyKey
                ?? normalizeCounterpartyName(record.counterpartyName)
                ?? UUID().uuidString
            let currencyCode = MistiaCurrencyLogic.normalizedCode(record.sourceCurrencyCode)
            return "\(counterpartyKey)|\(currencyCode)"
        }
        return grouped.compactMap { key, groupedRecords in
            guard let first = groupedRecords.first,
                  let normalizedKey = first.normalizedCounterpartyKey ?? normalizeCounterpartyName(first.counterpartyName),
                  !normalizedKey.isEmpty
            else {
                return nil
            }

            let total = groupedRecords
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
            let preferredIntent: TransactionDebtIntent = total > 0 ? .lend : .borrow
            var preferredRecord: TransactionRecordSnapshot?
            for record in groupedRecords where record.debtIntent == preferredIntent && record.sourceWalletID != nil {
                if preferredRecord.map({ recordSort(lhs: record, rhs: $0) }) ?? true {
                    preferredRecord = record
                }
            }

            return CounterpartyDebtSnapshot(
                id: key,
                displayName: groupedRecords
                    .compactMap(\.counterpartyName)
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? L10n.shared.corelogic.transaction.unknownName,
                normalizedCounterpartyKey: normalizedKey,
                netMinor: total,
                currencyCode: MistiaCurrencyLogic.normalizedCode(first.sourceCurrencyCode),
                preferredWalletID: preferredRecord?.sourceWalletID,
                relatedRecords: groupedRecords.sorted(by: recordSort)
            )
        }
        .sorted {
            if $0.displayName.localizedCaseInsensitiveCompare($1.displayName) != .orderedSame {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            if $0.currencyCode != $1.currencyCode {
                return $0.currencyCode.localizedCaseInsensitiveCompare($1.currencyCode) == .orderedAscending
            }
            if abs($0.netMinor) != abs($1.netMinor) {
                return abs($0.netMinor) > abs($1.netMinor)
            }
            return $0.id < $1.id
        }
    }

    static func openReceivableDebtTotalsByCurrency(
        from positions: [CounterpartyDebtSnapshot]
    ) -> [PlanningCurrencyAmountTotalSnapshot] {
        Dictionary(grouping: positions.filter { $0.netMinor > 0 }) { position in
            MistiaCurrencyLogic.normalizedCode(position.currencyCode)
        }
        .compactMap { currencyCode, groupedPositions in
            let total = groupedPositions.reduce(into: Int64.zero) { partial, position in
                partial += position.netMinor
            }
            guard total > 0 else { return nil }
            return PlanningCurrencyAmountTotalSnapshot(
                currencyCode: currencyCode,
                amountMinor: total
            )
        }
        .sorted { lhs, rhs in
            lhs.currencyCode.localizedCaseInsensitiveCompare(rhs.currencyCode) == .orderedAscending
        }
    }

    static func counterpartySuggestions(
        from records: [TransactionRecordSnapshot],
        query: String,
        excludingTransactionID: UUID? = nil,
        limit: Int = 5
    ) -> [TransactionTitleSuggestion] {
        guard limit > 0,
              let normalizedQuery = normalizeCounterpartyName(query),
              !normalizedQuery.isEmpty else {
            return []
        }

        var groupedMatches: [String: TransactionSuggestionAccumulator] = [:]
        for record in records {
            guard record.id != excludingTransactionID,
                  record.entryStatus == .posted,
                  record.primaryKind == .transfer,
                  record.transferSubtype == .debt,
                  let counterpartyName = record.counterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !counterpartyName.isEmpty,
                  let counterpartyKey = normalizeCounterpartyName(counterpartyName)
            else {
                continue
            }

            guard titleSuggestionMatchRank(query: normalizedQuery, normalizedTitle: counterpartyKey) != nil else {
                continue
            }

            let key = counterpartyKey.replacingOccurrences(of: " ", with: "")
            if var accumulator = groupedMatches[key] {
                accumulator.usageCount += 1
                if recordSort(lhs: record, rhs: accumulator.representative) {
                    accumulator.representative = record
                }
                groupedMatches[key] = accumulator
            } else {
                groupedMatches[key] = TransactionSuggestionAccumulator(
                    representative: record,
                    usageCount: 1
                )
            }
        }

        return groupedMatches.compactMap { key, accumulator -> (TransactionTitleSuggestion, Int, Date, Int)? in
            let representative = accumulator.representative
            guard let counterpartyName = representative.counterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let counterpartyKey = normalizeCounterpartyName(counterpartyName),
                  let rank = titleSuggestionMatchRank(query: normalizedQuery, normalizedTitle: counterpartyKey)
            else {
                return nil
            }
            return (
                TransactionTitleSuggestion(id: key, title: counterpartyName),
                rank,
                representative.occurredAt,
                accumulator.usageCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            if lhs.3 != rhs.3 { return lhs.3 > rhs.3 }
            return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
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

        var groupedMatches: [String: TransactionSuggestionAccumulator] = [:]

        for record in records {
            guard record.id != excludingTransactionID,
                  record.entryStatus == .posted,
                  matchesTitleSuggestionScope(
                    record,
                    primaryKind: primaryKind,
                    transferSubtype: transferSubtype
                  ),
                  !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            let normalizedTitle = titleSuggestionGroupingKey(record.title) ?? record.id.uuidString
            if var accumulator = groupedMatches[normalizedTitle] {
                accumulator.usageCount += 1
                if recordSort(lhs: record, rhs: accumulator.representative) {
                    accumulator.representative = record
                }
                groupedMatches[normalizedTitle] = accumulator
            } else {
                groupedMatches[normalizedTitle] = TransactionSuggestionAccumulator(
                    representative: record,
                    usageCount: 1
                )
            }
        }

        let rankedSuggestions = groupedMatches.compactMap { normalizedTitle, accumulator -> (
            suggestion: TransactionTitleSuggestion,
            matchRank: Int,
            latestOccurredAt: Date,
            latestCreatedAt: Date,
            usageCount: Int
        )? in
            let representative = accumulator.representative
            guard let representativeKey = normalizeCounterpartyName(representative.title),
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
                usageCount: accumulator.usageCount
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

    static func effectiveBalance<Records: Sequence>(
        for wallet: TransactionWalletSnapshot,
        records: Records
    ) -> Int64 where Records.Element == TransactionRecordSnapshot {
        var balance = wallet.openingBalanceMinor
        for record in records where record.entryStatus == .posted && !record.isArchived {
            balance += balanceDelta(for: wallet, record: record)
        }
        return balance
    }

    static func walletBalanceIndex<Records: Sequence>(
        wallets: [TransactionWalletSnapshot],
        records: Records
    ) -> TransactionWalletBalanceIndex where Records.Element == TransactionRecordSnapshot {
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
                        amount: record.destinationAmountMinor ?? record.amountMinor,
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
                    guard !isSharedExpenseDebtPrincipal(record) else {
                        break
                    }
                    if isResaleReceivableDebtPrincipal(record) {
                        applyDelta(
                            walletID: record.sourceWalletID,
                            explicitKind: record.sourceWalletKind,
                            amount: resaleReceivablePurchaseCostMinor(for: record),
                            delta: { kind, amount in outgoingDelta(for: kind, amount: amount) }
                        )
                        break
                    }
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
        if isSharedExpenseDebtPrincipal(record) {
            return 0
        }

        if isResaleReceivableDebtPrincipal(record) {
            return -resaleReceivablePurchaseCostMinor(for: record)
        }

        switch record.primaryKind {
        case .expense:
            return -record.amountMinor
        case .income:
            return record.amountMinor
        case .transfer:
            switch record.transferSubtype {
            case .internalTransfer:
                return 0
            case .familyTransfer:
                return record.destinationWalletID == nil ? record.amountMinor : -record.amountMinor
            case .debt:
                switch record.debtIntent {
                case .lend, .repay:
                    return -record.amountMinor
                case .collect, .borrow:
                    return isPaidForDebt(record) ? 0 : record.amountMinor
                case nil:
                    return 0
                }
            case nil:
                return 0
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
                return (record.sourceWalletID != nil || isPaidForDebt(record) || isSharedExpenseDebtPrincipal(record))
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

        if let counterpartyDebtKey = normalizeCounterpartyName(filters.counterpartyDebtKey) {
            let recordCounterpartyKey = record.normalizedCounterpartyKey
                ?? normalizeCounterpartyName(record.counterpartyName)
            guard record.entryStatus == .posted,
                  record.primaryKind == .transfer,
                  record.transferSubtype == .debt,
                  recordCounterpartyKey == counterpartyDebtKey
            else {
                return false
            }
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
        } else if filters.isEventOnly {
            guard record.settlementGroupID != nil else { return false }
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
                    delta += incomingDelta(
                        for: wallet.kind,
                        amount: record.destinationAmountMinor ?? record.amountMinor
                    )
                }

                return delta
            case .familyTransfer:
                guard record.sourceWalletID == wallet.id else { return 0 }
                return record.destinationWalletID == nil
                    ? incomingDelta(for: wallet.kind, amount: record.amountMinor)
                    : outgoingDelta(for: wallet.kind, amount: record.amountMinor)
            case .debt:
                guard record.sourceWalletID == wallet.id else { return 0 }
                if isResaleReceivableDebtPrincipal(record) {
                    return outgoingDelta(
                        for: wallet.kind,
                        amount: resaleReceivablePurchaseCostMinor(for: record)
                    )
                }

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

    nonisolated private struct TransactionSuggestionAccumulator {
        var representative: TransactionRecordSnapshot
        var usageCount: Int
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

    static func isLockedByPaidStatement<Transactions: Sequence>(
        transaction: TransactionRecordSnapshot,
        allTransactions: Transactions,
        calendar: Calendar = MistiaCalendar.current
    ) -> Bool where Transactions.Element == TransactionRecordSnapshot {
        // Only card charges and internal transfers can be locked by a statement.
        guard transaction.primaryKind == .expense || transaction.primaryKind == .transfer else {
            return false
        }

        if isCreditCardDebtLending(transaction) {
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
    var localizedTransactionTitle: String {
        TransactionGeneratedTitle.localizedDisplayTitle(
            rawTitle: title,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            categoryID: category?.id,
            categorySystemKey: category?.systemKey
        )
    }

    var snapshot: TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: localizedTransactionTitle,
            note: note,
            amountMinor: amountMinor,
            settlementGroupID: settlementGroupID,
            settlementObligationID: settlementObligationID,
            settlementRole: settlementRole,
            reportingExpenseMinor: reportingExpenseMinor,
            reportingIncomeMinor: reportingIncomeMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            destinationCurrencyCode: destinationCurrencyCode,
            destinationAmountMinor: destinationAmountMinor,
            reportingCurrencyCode: reportingCurrencyCode,
            reportingAmountMinor: reportingAmountMinor,
            conversionModeRawValue: conversionModeRawValue,
            exchangeRateDecimalString: exchangeRateDecimalString,
            exchangeRateProvider: exchangeRateProvider,
            exchangeRateDate: exchangeRateDate,
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
