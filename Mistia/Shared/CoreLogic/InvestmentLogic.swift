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

nonisolated struct InvestmentOpeningPosition: Equatable {
    let quantity: Decimal
    let costBasisMinor: Int64

    init(quantity: Decimal = 0, costBasisMinor: Int64 = 0) {
        self.quantity = quantity
        self.costBasisMinor = costBasisMinor
    }
}

nonisolated struct InvestmentTradeInput: Equatable, Identifiable {
    let id: UUID
    let kind: InvestmentTradeKind
    let quantity: Decimal
    let accountingGrossAmountMinor: Int64
    let accountingFeeMinor: Int64
    let occurredAt: Date
    let createdAt: Date

    init(
        id: UUID,
        kind: InvestmentTradeKind,
        quantity: Decimal,
        accountingGrossAmountMinor: Int64,
        accountingFeeMinor: Int64 = 0,
        occurredAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.quantity = quantity
        self.accountingGrossAmountMinor = accountingGrossAmountMinor
        self.accountingFeeMinor = accountingFeeMinor
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
}

nonisolated enum InvestmentAccountingError: Error, Equatable {
    case invalidOpeningPosition
    case invalidQuantity
    case invalidAmount
    case insufficientPosition
    case arithmeticOverflow
}

nonisolated enum InvestmentAccountingEngine {
    static func recalculate(
        openingPosition: InvestmentOpeningPosition = InvestmentOpeningPosition(),
        trades: [InvestmentTradeInput]
    ) throws -> [InvestmentTradeCalculation] {
        guard openingPosition.quantity >= 0, openingPosition.costBasisMinor >= 0 else {
            throw InvestmentAccountingError.invalidOpeningPosition
        }
        guard openingPosition.quantity > 0 || openingPosition.costBasisMinor == 0 else {
            throw InvestmentAccountingError.invalidOpeningPosition
        }

        var positionQuantity = openingPosition.quantity
        var positionCostBasisMinor = openingPosition.costBasisMinor
        var output: [InvestmentTradeCalculation] = []
        output.reserveCapacity(trades.count)

        for trade in sorted(trades) {
            guard trade.quantity > 0 else {
                throw InvestmentAccountingError.invalidQuantity
            }
            guard trade.accountingGrossAmountMinor > 0, trade.accountingFeeMinor >= 0 else {
                throw InvestmentAccountingError.invalidAmount
            }

            switch trade.kind {
            case .buy:
                let (addedCost, overflow) = trade.accountingGrossAmountMinor.addingReportingOverflow(
                    trade.accountingFeeMinor
                )
                guard !overflow else { throw InvestmentAccountingError.arithmeticOverflow }
                let (nextCost, costOverflow) = positionCostBasisMinor.addingReportingOverflow(addedCost)
                guard !costOverflow else { throw InvestmentAccountingError.arithmeticOverflow }

                positionQuantity += trade.quantity
                positionCostBasisMinor = nextCost
                output.append(
                    InvestmentTradeCalculation(
                        id: trade.id,
                        releasedCostBasisMinor: 0,
                        realizedProfitLossMinor: 0,
                        positionQuantityAfter: positionQuantity,
                        positionCostBasisAfterMinor: positionCostBasisMinor
                    )
                )

            case .sell:
                guard positionQuantity >= trade.quantity else {
                    throw InvestmentAccountingError.insufficientPosition
                }

                let releasedCostBasisMinor: Int64
                if positionQuantity == trade.quantity {
                    releasedCostBasisMinor = positionCostBasisMinor
                } else {
                    releasedCostBasisMinor = try proportionalMinor(
                        totalMinor: positionCostBasisMinor,
                        numerator: trade.quantity,
                        denominator: positionQuantity
                    )
                }

                let (netSaleMinor, netOverflow) = trade.accountingGrossAmountMinor.subtractingReportingOverflow(
                    trade.accountingFeeMinor
                )
                guard !netOverflow else { throw InvestmentAccountingError.arithmeticOverflow }
                let (realizedProfitLossMinor, profitOverflow) = netSaleMinor.subtractingReportingOverflow(
                    releasedCostBasisMinor
                )
                guard !profitOverflow else { throw InvestmentAccountingError.arithmeticOverflow }

                positionQuantity -= trade.quantity
                positionCostBasisMinor -= releasedCostBasisMinor
                if positionQuantity == 0 {
                    positionCostBasisMinor = 0
                }

                output.append(
                    InvestmentTradeCalculation(
                        id: trade.id,
                        releasedCostBasisMinor: releasedCostBasisMinor,
                        realizedProfitLossMinor: realizedProfitLossMinor,
                        positionQuantityAfter: positionQuantity,
                        positionCostBasisAfterMinor: positionCostBasisMinor
                    )
                )
            }
        }

        return output
    }

    static func calculationMap(
        openingPosition: InvestmentOpeningPosition = InvestmentOpeningPosition(),
        trades: [InvestmentTradeInput]
    ) throws -> [UUID: InvestmentTradeCalculation] {
        Dictionary(
            uniqueKeysWithValues: try recalculate(openingPosition: openingPosition, trades: trades)
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
    let marketValueMinor: Int64?

    var averageUnitCostMinor: Int64? {
        guard quantity > 0, remainingCostBasisMinor >= 0 else { return nil }
        var value = Decimal(remainingCostBasisMinor) / quantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending else {
            return nil
        }
        return number.int64Value
    }
}

nonisolated struct InvestmentPortfolioSummary: Equatable {
    let investedCapitalMinor: Int64
    let marketValueMinor: Int64
    let realizedProfitLossMinor: Int64
    let unrealizedProfitLossMinor: Int64
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
        let investedCapitalMinor = positions.reduce(into: Int64.zero) {
            $0 = saturatingAdd($0, max($1.remainingCostBasisMinor, 0))
        }
        let marketValueMinor = positions.reduce(into: Int64.zero) {
            $0 = saturatingAdd($0, max($1.marketValueMinor ?? $1.remainingCostBasisMinor, 0))
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
            investedCapitalMinor: investedCapitalMinor,
            marketValueMinor: marketValueMinor,
            realizedProfitLossMinor: realizedProfitLossMinor,
            unrealizedProfitLossMinor: saturatingSubtract(marketValueMinor, investedCapitalMinor),
            investmentWalletBalanceMinor: investmentWalletBalanceMinor
        )
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return value }
        return rhs >= 0 ? .max : .min
    }

    private static func saturatingSubtract(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard overflow else { return value }
        return rhs >= 0 ? .min : .max
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
