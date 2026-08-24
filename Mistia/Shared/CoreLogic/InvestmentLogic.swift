import CryptoKit
import Foundation

nonisolated enum InvestmentSystemWalletIdentity {
    private static let namespace = "com.mistia.wallet.system.investment-profit"
    static let canonicalSortOrder = Int(Int32.max) - 100

    static func walletID(ownerUserID: UUID) -> UUID {
        let seed = Data("\(namespace):\(ownerUserID.uuidString.lowercased())".utf8)
        var bytes = Array(SHA256.hash(data: seed).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func isInvestmentWallet(walletID: UUID, ownerUserID: UUID) -> Bool {
        walletID == self.walletID(ownerUserID: ownerUserID)
    }
}

nonisolated enum InvestmentLedgerIdentity {
    static func derivedID(eventID: UUID, component: String) -> UUID {
        let seed = Data("com.mistia.investment.ledger:\(eventID.uuidString.lowercased()):\(component)".utf8)
        var bytes = Array(SHA256.hash(data: seed).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

nonisolated struct InvestmentTradeInput: Equatable, Identifiable {
    let id: UUID
    let kind: InvestmentTradeKind
    let quantity: Decimal
    let unitLabel: String?
    let accountingGrossAmountMinor: Int64
    let occurredAt: Date
    let createdAt: Date

    init(
        id: UUID,
        kind: InvestmentTradeKind,
        quantity: Decimal,
        unitLabel: String? = nil,
        accountingGrossAmountMinor: Int64,
        occurredAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.quantity = quantity
        self.unitLabel = InvestmentUnitLabel.normalizedDisplay(unitLabel)
        self.accountingGrossAmountMinor = accountingGrossAmountMinor
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}

nonisolated enum InvestmentUnitLabel {
    static let legacyKey = "__mistia_legacy_unit__"

    static func normalizedDisplay(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    static func comparisonKey(_ value: String?) -> String {
        guard let normalized = normalizedDisplay(value) else { return legacyKey }
        return normalized
            .folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        comparisonKey(lhs) == comparisonKey(rhs)
    }
}

nonisolated struct InvestmentUnitPosition: Equatable, Identifiable {
    let unitKey: String
    let unitLabel: String?
    let quantity: Decimal

    var id: String { unitKey }
}

nonisolated struct InvestmentTradeCalculation: Equatable, Identifiable {
    let id: UUID
    let releasedCostBasisMinor: Int64
    let realizedProfitLossMinor: Int64
    let positionQuantityAfter: Decimal
    let positionCostBasisAfterMinor: Int64
    let openLotCountAfter: Int
}

nonisolated enum InvestmentAccountingError: LocalizedError, Equatable {
    case invalidQuantity
    case invalidAmount
    case insufficientPosition
    case arithmeticOverflow

    var errorDescription: String? {
        switch self {
        case .invalidQuantity:
            return L10n.investment.error.invalidQuantity
        case .invalidAmount:
            return L10n.investment.error.invalidAmount
        case .insufficientPosition:
            return L10n.investment.error.insufficientPosition
        case .arithmeticOverflow:
            return L10n.investment.error.arithmeticOverflow
        }
    }
}

nonisolated enum InvestmentAccountingEngine {
    private struct OpenLot {
        let unitKey: String
        var quantity: Decimal
        var costBasisMinor: Int64
    }

    private struct UnitBalance {
        var label: String?
        var quantity: Decimal
    }

    private struct RecalculationResult {
        let calculations: [InvestmentTradeCalculation]
        let unitPositions: [InvestmentUnitPosition]
    }

    static func recalculate(
        trades: [InvestmentTradeInput]
    ) throws -> [InvestmentTradeCalculation] {
        try recalculateState(trades: trades).calculations
    }

    static func unitPositions(
        trades: [InvestmentTradeInput]
    ) throws -> [InvestmentUnitPosition] {
        try recalculateState(trades: trades).unitPositions
    }

    private static func recalculateState(
        trades: [InvestmentTradeInput]
    ) throws -> RecalculationResult {
        var positionQuantity: Decimal = 0
        var positionCostBasisMinor: Int64 = 0
        var openLots: [OpenLot] = []
        var unitBalances: [String: UnitBalance] = [:]
        var output: [InvestmentTradeCalculation] = []
        output.reserveCapacity(trades.count)

        for trade in sorted(trades) {
            guard trade.quantity > 0 else {
                throw InvestmentAccountingError.invalidQuantity
            }
            let unitKey = InvestmentUnitLabel.comparisonKey(trade.unitLabel)
            switch trade.kind {
            case .buy:
                guard trade.accountingGrossAmountMinor >= 0 else {
                    throw InvestmentAccountingError.invalidAmount
                }
                let (nextCost, costOverflow) = positionCostBasisMinor.addingReportingOverflow(
                    trade.accountingGrossAmountMinor
                )
                guard !costOverflow else { throw InvestmentAccountingError.arithmeticOverflow }

                positionQuantity += trade.quantity
                positionCostBasisMinor = nextCost
                var unitBalance = unitBalances[unitKey] ?? UnitBalance(
                    label: InvestmentUnitLabel.normalizedDisplay(trade.unitLabel),
                    quantity: 0
                )
                unitBalance.quantity += trade.quantity
                if unitBalance.label == nil {
                    unitBalance.label = InvestmentUnitLabel.normalizedDisplay(trade.unitLabel)
                }
                unitBalances[unitKey] = unitBalance
                openLots.append(
                    OpenLot(
                        unitKey: unitKey,
                        quantity: trade.quantity,
                        costBasisMinor: trade.accountingGrossAmountMinor
                    )
                )
                output.append(
                    InvestmentTradeCalculation(
                        id: trade.id,
                        releasedCostBasisMinor: 0,
                        realizedProfitLossMinor: 0,
                        positionQuantityAfter: positionQuantity,
                        positionCostBasisAfterMinor: positionCostBasisMinor,
                        openLotCountAfter: openLots.lazy.filter { $0.quantity > 0 }.count
                    )
                )

            case .sell:
                guard trade.accountingGrossAmountMinor >= 0 else {
                    throw InvestmentAccountingError.invalidAmount
                }
                guard (unitBalances[unitKey]?.quantity ?? 0) >= trade.quantity else {
                    throw InvestmentAccountingError.insufficientPosition
                }

                var quantityToRelease = trade.quantity
                var releasedCostBasisMinor: Int64 = 0

                while quantityToRelease > 0 {
                    guard let lotIndex = openLots.firstIndex(where: {
                        $0.unitKey == unitKey && $0.quantity > 0
                    }) else {
                        throw InvestmentAccountingError.insufficientPosition
                    }

                    var lot = openLots[lotIndex]
                    let releasedQuantity = min(quantityToRelease, lot.quantity)
                    let releasedLotCost: Int64
                    if releasedQuantity == lot.quantity {
                        releasedLotCost = lot.costBasisMinor
                    } else {
                        releasedLotCost = try proportionalMinor(
                            totalMinor: lot.costBasisMinor,
                            numerator: releasedQuantity,
                            denominator: lot.quantity
                        )
                    }

                    let (nextReleasedCost, releasedOverflow) = releasedCostBasisMinor.addingReportingOverflow(
                        releasedLotCost
                    )
                    guard !releasedOverflow else {
                        throw InvestmentAccountingError.arithmeticOverflow
                    }
                    releasedCostBasisMinor = nextReleasedCost
                    quantityToRelease -= releasedQuantity
                    lot.quantity -= releasedQuantity
                    lot.costBasisMinor -= releasedLotCost

                    openLots[lotIndex] = lot
                }

                let (realizedProfitLossMinor, profitOverflow) = trade.accountingGrossAmountMinor.subtractingReportingOverflow(
                    releasedCostBasisMinor
                )
                guard !profitOverflow else { throw InvestmentAccountingError.arithmeticOverflow }

                positionQuantity -= trade.quantity
                var unitBalance = unitBalances[unitKey]!
                unitBalance.quantity -= trade.quantity
                unitBalances[unitKey] = unitBalance
                let (nextPositionCost, costOverflow) = positionCostBasisMinor.subtractingReportingOverflow(
                    releasedCostBasisMinor
                )
                guard !costOverflow, nextPositionCost >= 0 else {
                    throw InvestmentAccountingError.arithmeticOverflow
                }
                positionCostBasisMinor = nextPositionCost
                if positionQuantity == 0 {
                    positionCostBasisMinor = 0
                }

                output.append(
                    InvestmentTradeCalculation(
                        id: trade.id,
                        releasedCostBasisMinor: releasedCostBasisMinor,
                        realizedProfitLossMinor: realizedProfitLossMinor,
                        positionQuantityAfter: positionQuantity,
                        positionCostBasisAfterMinor: positionCostBasisMinor,
                        openLotCountAfter: openLots.lazy.filter { $0.quantity > 0 }.count
                    )
                )
            }
        }

        let positions = unitBalances.compactMap { key, balance -> InvestmentUnitPosition? in
            guard balance.quantity > 0 else { return nil }
            return InvestmentUnitPosition(
                unitKey: key,
                unitLabel: balance.label,
                quantity: balance.quantity
            )
        }
        .sorted { lhs, rhs in
            lhs.unitKey.localizedStandardCompare(rhs.unitKey) == .orderedAscending
        }
        return RecalculationResult(calculations: output, unitPositions: positions)
    }

    static func calculationMap(
        trades: [InvestmentTradeInput]
    ) throws -> [UUID: InvestmentTradeCalculation] {
        Dictionary(
            uniqueKeysWithValues: try recalculate(trades: trades)
                .map { ($0.id, $0) }
        )
    }

    private static func sorted(_ trades: [InvestmentTradeInput]) -> [InvestmentTradeInput] {
        trades.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return MistiaStableUUIDOrdering.precedes(lhs.id, rhs.id)
        }
    }

    private static func proportionalMinor(
        totalMinor: Int64,
        numerator: Decimal,
        denominator: Decimal
    ) throws -> Int64 {
        guard denominator > 0 else { throw InvestmentAccountingError.invalidQuantity }
        var value = Decimal(totalMinor) * numerator / denominator
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { throw InvestmentAccountingError.arithmeticOverflow }
        return number.int64Value
    }
}

nonisolated struct InvestmentAssetPositionSnapshot: Equatable, Identifiable {
    let id: UUID
    let channelID: UUID
    let quantity: Decimal
    let remainingCostBasisMinor: Int64
    let openLotCount: Int
}

nonisolated struct InvestmentPortfolioSummary: Equatable {
    let remainingInventoryCostMinor: Int64
    let realizedProfitLossMinor: Int64
    let investmentWalletBalanceMinor: Int64
}

nonisolated enum InvestmentSummaryLogic {
    static func summary(
        positions: [InvestmentAssetPositionSnapshot],
        trades: [InvestmentTradeCalculation],
        tradeDates: [UUID: Date],
        period: DateInterval?,
        investmentWalletBalanceMinor: Int64
    ) -> InvestmentPortfolioSummary {
        let remainingInventoryCostMinor = positions
            .filter { $0.quantity > 0 }
            .reduce(into: Int64.zero) {
            $0 = saturatingAdd($0, max($1.remainingCostBasisMinor, 0))
        }
        let realizedProfitLossMinor = trades.reduce(into: Int64.zero) { partial, trade in
            guard trade.realizedProfitLossMinor != 0,
                  let date = tradeDates[trade.id],
                  period?.contains(date) ?? true else {
                return
            }
            partial = saturatingAdd(partial, trade.realizedProfitLossMinor)
        }

        return InvestmentPortfolioSummary(
            remainingInventoryCostMinor: remainingInventoryCostMinor,
            realizedProfitLossMinor: realizedProfitLossMinor,
            investmentWalletBalanceMinor: investmentWalletBalanceMinor
        )
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return value }
        return rhs >= 0 ? .max : .min
    }

}

nonisolated enum InvestmentPeriodLogic {
    static func monthInterval(
        containing date: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> DateInterval {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let candidateEnd = calendar.date(byAdding: .month, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return DateInterval(
            start: start,
            end: max(candidateEnd, start.addingTimeInterval(1))
        )
    }

    static func month(
        byAdding value: Int,
        to date: Date,
        calendar: Calendar = MistiaCalendar.current
    ) -> Date {
        let start = monthInterval(containing: date, calendar: calendar).start
        return calendar.date(byAdding: .month, value: value, to: start) ?? start
    }
}

nonisolated enum InvestmentAssetSearchLogic {
    static func matches(
        productName: String,
        channelName: String,
        query: String,
        locale: Locale = Locale(identifier: "vi_VN")
    ) -> Bool {
        matches(
            values: [productName, channelName],
            query: query,
            locale: locale
        )
    }

    static func matches(
        values: [String],
        query: String,
        locale: Locale = Locale(identifier: "vi_VN")
    ) -> Bool {
        let query = normalized(query, locale: locale)
        guard !query.isEmpty else { return true }
        return values.contains { normalized($0, locale: locale).contains(query) }
    }

    private static func normalized(_ value: String, locale: Locale) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale
        )
        .replacingOccurrences(of: "đ", with: "d")
        .replacingOccurrences(of: "Đ", with: "d")
    }
}

nonisolated enum InvestmentCurrencyConversion {
    static func convertedMinor(
        _ amountMinor: Int64,
        rate: Decimal
    ) throws -> Int64 {
        guard rate > 0 else { throw InvestmentAccountingError.invalidAmount }
        var value = Decimal(amountMinor) * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { throw InvestmentAccountingError.arithmeticOverflow }
        return number.int64Value
    }
}

nonisolated struct InvestmentCashPostingSnapshot: Equatable, Sendable {
    let walletID: UUID
    let currencyCode: String
    let amountMinor: Int64
    let accountingAmountMinor: Int64
    let accountingCurrencyCode: String
    let bucket: InvestmentCashBucket
}

nonisolated enum InvestmentCashAllocationLogic {
    static func snapshot(
        postings: [InvestmentCashPostingSnapshot],
        accountingCurrencyCode: String,
        unidentifiedMinor: Int64 = 0
    ) -> InvestmentCashAllocationSnapshot {
        struct Totals {
            var currencyCode: String
            var booked: Int64 = 0
            var unreconciled: Int64 = 0
            var originalBooked: Int64 = 0
            var originalUnreconciled: Int64 = 0
        }

        let normalizedAccountingCurrency = MistiaCurrencyLogic.normalizedCode(accountingCurrencyCode)
        var totalsByWallet: [UUID: Totals] = [:]
        for posting in postings where MistiaCurrencyLogic.normalizedCode(posting.accountingCurrencyCode) == normalizedAccountingCurrency {
            var totals = totalsByWallet[posting.walletID]
                ?? Totals(currencyCode: MistiaCurrencyLogic.normalizedCode(posting.currencyCode))
            switch posting.bucket {
            case .booked:
                totals.booked = saturatingAdd(totals.booked, posting.accountingAmountMinor)
                totals.originalBooked = saturatingAdd(totals.originalBooked, posting.amountMinor)
            case .unreconciled:
                totals.unreconciled = saturatingAdd(totals.unreconciled, posting.accountingAmountMinor)
                totals.originalUnreconciled = saturatingAdd(totals.originalUnreconciled, posting.amountMinor)
            }
            totalsByWallet[posting.walletID] = totals
        }

        let locations = totalsByWallet.map { walletID, totals in
            InvestmentWalletCashLocation(
                walletID: walletID,
                currencyCode: totals.currencyCode,
                bookedMinor: totals.booked,
                unreconciledMinor: totals.unreconciled,
                originalBookedMinor: totals.originalBooked,
                originalUnreconciledMinor: totals.originalUnreconciled
            )
        }
        .filter { $0.totalMinor != 0 || $0.bookedMinor != 0 || $0.unreconciledMinor != 0 }
        .sorted { MistiaStableUUIDOrdering.precedes($0.walletID, $1.walletID) }

        return InvestmentCashAllocationSnapshot(
            accountingCurrencyCode: normalizedAccountingCurrency,
            locations: locations,
            unidentifiedMinor: unidentifiedMinor
        )
    }

    static func usagePreview(
        requestedMinor: Int64,
        visibleWalletBalanceMinor: Int64,
        bookedInvestmentMinor: Int64,
        unreconciledInvestmentMinor: Int64,
        totalInvestmentMinor: Int64
    ) -> InvestmentFundUsagePreview {
        let requested = max(requestedMinor, 0)
        let booked = max(bookedInvestmentMinor, 0)
        let unreconciled = max(unreconciledInvestmentMinor, 0)
        let ordinaryAvailable = max(visibleWalletBalanceMinor - booked, 0)
        var remaining = max(requested - ordinaryAvailable, 0)
        let bookedToUse = min(booked, remaining)
        remaining -= bookedToUse
        let unreconciledToUse = min(unreconciled, remaining)
        remaining -= unreconciledToUse
        let outcome: InvestmentFundUsageOutcome
        if remaining > 0 {
            outcome = .insufficientFunds
        } else if bookedToUse > 0 || unreconciledToUse > 0 {
            outcome = .requiresConfirmation
        } else {
            outcome = .ordinaryFundsOnly
        }
        return InvestmentFundUsagePreview(
            requestedMinor: requested,
            ordinaryAvailableMinor: ordinaryAvailable,
            bookedToUseMinor: bookedToUse,
            unreconciledToUseMinor: unreconciledToUse,
            remainingInvestmentMinor: max(totalInvestmentMinor - bookedToUse - unreconciledToUse, 0),
            outcome: outcome
        )
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return value }
        return rhs >= 0 ? .max : .min
    }
}
