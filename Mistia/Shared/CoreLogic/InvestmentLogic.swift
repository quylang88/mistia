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
    let accountingGrossAmountMinor: Int64
    let occurredAt: Date
    let createdAt: Date

    init(
        id: UUID,
        kind: InvestmentTradeKind,
        quantity: Decimal,
        accountingGrossAmountMinor: Int64,
        occurredAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.quantity = quantity
        self.accountingGrossAmountMinor = accountingGrossAmountMinor
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}

nonisolated struct InvestmentTradeCalculation: Equatable, Identifiable {
    let id: UUID
    let releasedCostBasisMinor: Int64
    let realizedProfitLossMinor: Int64
    let positionQuantityAfter: Decimal
    let positionCostBasisAfterMinor: Int64
    let openLotCountAfter: Int
}

nonisolated enum InvestmentAccountingError: Error, Equatable {
    case invalidQuantity
    case invalidAmount
    case insufficientPosition
    case arithmeticOverflow
}

nonisolated enum InvestmentAccountingEngine {
    private struct OpenLot {
        var quantity: Decimal
        var costBasisMinor: Int64
    }

    static func recalculate(
        trades: [InvestmentTradeInput]
    ) throws -> [InvestmentTradeCalculation] {
        var positionQuantity: Decimal = 0
        var positionCostBasisMinor: Int64 = 0
        var openLots: [OpenLot] = []
        var firstOpenLotIndex = 0
        var output: [InvestmentTradeCalculation] = []
        output.reserveCapacity(trades.count)

        for trade in sorted(trades) {
            guard trade.quantity > 0 else {
                throw InvestmentAccountingError.invalidQuantity
            }
            guard trade.accountingGrossAmountMinor > 0 else {
                throw InvestmentAccountingError.invalidAmount
            }

            switch trade.kind {
            case .buy:
                let (nextCost, costOverflow) = positionCostBasisMinor.addingReportingOverflow(
                    trade.accountingGrossAmountMinor
                )
                guard !costOverflow else { throw InvestmentAccountingError.arithmeticOverflow }

                positionQuantity += trade.quantity
                positionCostBasisMinor = nextCost
                openLots.append(
                    OpenLot(
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
                        openLotCountAfter: openLots.count - firstOpenLotIndex
                    )
                )

            case .sell:
                guard positionQuantity >= trade.quantity else {
                    throw InvestmentAccountingError.insufficientPosition
                }

                var quantityToRelease = trade.quantity
                var releasedCostBasisMinor: Int64 = 0

                while quantityToRelease > 0 {
                    guard firstOpenLotIndex < openLots.count else {
                        throw InvestmentAccountingError.insufficientPosition
                    }

                    var lot = openLots[firstOpenLotIndex]
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

                    if lot.quantity == 0 {
                        firstOpenLotIndex += 1
                    } else {
                        openLots[firstOpenLotIndex] = lot
                    }
                }

                let (realizedProfitLossMinor, profitOverflow) = trade.accountingGrossAmountMinor.subtractingReportingOverflow(
                    releasedCostBasisMinor
                )
                guard !profitOverflow else { throw InvestmentAccountingError.arithmeticOverflow }

                positionQuantity -= trade.quantity
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
                        openLotCountAfter: openLots.count - firstOpenLotIndex
                    )
                )
            }
        }

        return output
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
        let remainingInventoryCostMinor = positions.reduce(into: Int64.zero) {
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
        let query = normalized(query, locale: locale)
        guard !query.isEmpty else { return true }
        return normalized(productName, locale: locale).contains(query)
            || normalized(channelName, locale: locale).contains(query)
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
