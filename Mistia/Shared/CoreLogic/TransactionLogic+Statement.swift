import Foundation
import SwiftUI

typealias TransactionCashflowStyle = OverviewCashflowStyle
typealias TransactionStatementChartPoint = OverviewChartPoint
typealias OverviewStatementWalletRow = TransactionStatementWalletRow
typealias OverviewStatementTransactionRow = TransactionStatementRow
typealias OverviewMonthlyStatementSnapshot = TransactionSummaryStatementSnapshot

nonisolated enum TransactionStatementKind: String, Equatable {
    case monthlySummary
    case creditCard

}


nonisolated struct TransactionStatementWalletRow: Equatable, Identifiable {
    let id: UUID
    let name: String
    let kindTitle: String
    let openingBalanceMinor: Int64
    let currentBalanceMinor: Int64
    let currencyCode: String
}


nonisolated struct TransactionStatementRow: Equatable, Identifiable {
    let id: UUID
    let occurredAt: Date
    let title: String
    let kindTitle: String
    let accountText: String
    let detailText: String
    let amountMinor: Int64
    let currencyCode: String
    let cashflowStyle: TransactionCashflowStyle
    let statusTitle: String
}


nonisolated struct TransactionSummaryStatementSnapshot: Equatable {
    let generatedAt: Date
    let period: DateInterval
    let totalAssetBalanceMinor: Int64
    let totalIncomeMinor: Int64
    let totalExpenseMinor: Int64
    let netCashflowMinor: Int64
    let wallets: [TransactionStatementWalletRow]
    let chartPoints: [TransactionStatementChartPoint]
    let transactions: [TransactionStatementRow]
    let currencyCode: String
}


nonisolated struct TransactionCreditCardStatementCardSnapshot: Equatable, Identifiable {
    let id: UUID
    let walletName: String
    let iconSymbolName: String
    let issuerName: String
    let networkTitle: String
    let last4: String
    let creditLimitMinor: Int64
    let currentDebtMinor: Int64
    let availableCreditMinor: Int64
    let utilization: Double
    let statementClosingDay: Int
    let paymentDueDay: Int
    let paymentSourceWalletName: String?
    let cycle: DateInterval
    let nextPaymentDate: Date
    let charges: [TransactionStatementRow]
    let payments: [TransactionStatementRow]
    let currencyCode: String
}


nonisolated struct TransactionCreditCardStatementSnapshot: Equatable {
    let generatedAt: Date
    let cards: [TransactionCreditCardStatementCardSnapshot]
}


nonisolated struct TransactionStatementDocument: Equatable {
    let kind: TransactionStatementKind
    let filename: String
    let html: String
}

nonisolated extension OverviewLogic {
    static func monthlyStatement(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        transactions: [OverviewTransactionSnapshot],
        currencyCode: String,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> TransactionSummaryStatementSnapshot {
        let statementPeriod = calendar.dateInterval(of: .month, for: referenceDate)
            ?? DateInterval(start: referenceDate, duration: 0)

        return TransactionLogic.monthlyStatement(
            wallets: wallets,
            transactionRecords: transactionRecords,
            transactions: transactions,
            statementPeriod: statementPeriod,
            currencyCode: currencyCode,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func creditCardStatement(
        accounts: [OverviewCreditCardStatementAccountSnapshot],
        transactions: [OverviewTransactionSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> TransactionCreditCardStatementSnapshot {
        TransactionLogic.creditCardStatement(
            accounts: accounts,
            transactions: transactions,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func renderMonthlyStatement(
        _ statement: TransactionSummaryStatementSnapshot
    ) -> TransactionStatementDocument {
        TransactionLogic.renderMonthlyStatement(statement)
    }
}


nonisolated extension TransactionLogic {
    private static func displayAmount(for row: TransactionStatementRow) -> String {
        formatAmount(row.amountMinor, currencyCode: row.currencyCode, style: row.cashflowStyle)
    }
    private static func formatAmount(_ amount: Int64, currencyCode: String, style: TransactionCashflowStyle) -> String {
        let raw = amount.formattedCurrency(code: currencyCode)
        switch style {
        case .income: return "+" + raw
        case .expense: return "-" + raw
        case .neutral: return raw
        }
    }


    private static func contains(
        _ date: Date,
        in interval: DateInterval
    ) -> Bool {
        date >= interval.start && date < interval.end
    }

    static func nextPaymentDate(
        paymentDueDay: Int,
        cycleEnd: Date,
        calendar: Calendar
    ) -> Date {
        let reference = calendar.date(byAdding: .day, value: 1, to: cycleEnd) ?? cycleEnd
        let referenceMonthStart = PlanningLogic.startOfMonth(for: reference, calendar: calendar)
        let currentMonthDue = OverviewLogic.scheduledDay(
            paymentDueDay,
            inMonthContaining: referenceMonthStart,
            calendar: calendar
        )

        if currentMonthDue >= calendar.startOfDay(for: reference) {
            return currentMonthDue
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: referenceMonthStart) ?? referenceMonthStart
        return OverviewLogic.scheduledDay(paymentDueDay, inMonthContaining: nextMonth, calendar: calendar)
    }

    static func monthlyStatement(
        wallets: [OverviewWalletSnapshot],
        transactionRecords: [TransactionRecordSnapshot],
        transactions: [OverviewTransactionSnapshot],
        statementPeriod: DateInterval,
        currencyCode: String,
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> TransactionSummaryStatementSnapshot {
        let chartPoints = OverviewLogic.recentSevenDaySpendingChartPoints(
            from: transactionRecords,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let heroSnapshot = OverviewLogic.hero(
            wallets: wallets,
            transactionRecords: transactionRecords,
            currencyCode: currencyCode,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let walletRows = wallets
            .filter { $0.kind != .creditCard }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
            .map { wallet in
                TransactionStatementWalletRow(
                    id: wallet.id,
                    name: wallet.name,
                    kindTitle: wallet.kind.title,
                    openingBalanceMinor: wallet.openingBalanceMinor,
                    currentBalanceMinor: TransactionLogic.effectiveBalance(
                        for: TransactionWalletSnapshot(
                            id: wallet.id,
                            kind: wallet.kind,
                            openingBalanceMinor: wallet.openingBalanceMinor
                        ),
                        records: transactionRecords
                    ),
                    currencyCode: wallet.currencyCode
                )
            }

        let transactionRows = transactions
            .filter { $0.entryStatus == .posted && !$0.isArchived && contains($0.occurredAt, in: statementPeriod) }
            .sorted(by: transactionSort)
            .map { makeStatementRow(from: $0, currencyCode: currencyCode) }

        return TransactionSummaryStatementSnapshot(
            generatedAt: referenceDate,
            period: statementPeriod,
            totalAssetBalanceMinor: heroSnapshot.totalAssetBalanceMinor,
            totalIncomeMinor: heroSnapshot.incomeThisMonthMinor,
            totalExpenseMinor: heroSnapshot.expenseThisMonthMinor,
            netCashflowMinor: heroSnapshot.incomeThisMonthMinor - heroSnapshot.expenseThisMonthMinor,
            wallets: walletRows,
            chartPoints: chartPoints,
            transactions: transactionRows,
            currencyCode: currencyCode
        )
    }


    static func creditCardStatement(
        accounts: [OverviewCreditCardStatementAccountSnapshot],
        transactions: [OverviewTransactionSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = MistiaCalendar.current
    ) -> TransactionCreditCardStatementSnapshot {
        guard !accounts.isEmpty else {
            return TransactionCreditCardStatementSnapshot(
                generatedAt: referenceDate,
                cards: []
            )
        }

        let transactionBuckets = creditCardStatementTransactionBuckets(from: transactions)
        let cards = accounts
            .sorted {
                $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending
            }
            .map { account in
                let cycle = OverviewLogic.creditCardStatementCycle(
                    statementClosingDay: account.statementClosingDay,
                    referenceDate: referenceDate,
                    calendar: calendar
                )

                let charges = transactionBuckets.chargesByWalletID[account.walletID, default: []]
                    .filter { contains($0.occurredAt, in: cycle) }
                    .map { makeStatementRow(from: $0, currencyCode: account.currencyCode) }

                let payments = transactionBuckets.paymentsByWalletID[account.walletID, default: []]
                    .filter { contains($0.occurredAt, in: cycle) }
                    .map { makeStatementRow(from: $0, currencyCode: account.currencyCode) }

                let availableCredit = max(account.creditLimitMinor - account.currentDebtMinor, 0)
                let utilization = account.creditLimitMinor > 0
                    ? Double(account.currentDebtMinor) / Double(account.creditLimitMinor)
                    : 0

                return TransactionCreditCardStatementCardSnapshot(
                    id: account.id,
                    walletName: account.walletName,
                    iconSymbolName: account.iconSymbolName,
                    issuerName: account.issuerName,
                    networkTitle: account.network.title,
                    last4: account.last4,
                    creditLimitMinor: account.creditLimitMinor,
                    currentDebtMinor: account.currentDebtMinor,
                    availableCreditMinor: availableCredit,
                    utilization: utilization,
                    statementClosingDay: account.statementClosingDay,
                    paymentDueDay: account.paymentDueDay,
                    paymentSourceWalletName: account.paymentSourceWalletName,
                    cycle: cycle,
                    nextPaymentDate: nextPaymentDate(
                        paymentDueDay: account.paymentDueDay,
                        cycleEnd: cycle.end,
                        calendar: calendar
                    ),
                    charges: charges,
                    payments: payments,
                    currencyCode: account.currencyCode
                )
            }

        return TransactionCreditCardStatementSnapshot(
            generatedAt: referenceDate,
            cards: cards
        )
    }

    private struct CreditCardStatementTransactionBuckets {
        let chargesByWalletID: [UUID: [OverviewTransactionSnapshot]]
        let paymentsByWalletID: [UUID: [OverviewTransactionSnapshot]]
    }

    private static func creditCardStatementTransactionBuckets(
        from transactions: [OverviewTransactionSnapshot]
    ) -> CreditCardStatementTransactionBuckets {
        var chargesByWalletID: [UUID: [OverviewTransactionSnapshot]] = [:]
        var paymentsByWalletID: [UUID: [OverviewTransactionSnapshot]] = [:]

        for transaction in transactions {
            guard transaction.entryStatus == .posted, !transaction.isArchived else { continue }

            if isCreditCardStatementCharge(transaction), let walletID = transaction.sourceWalletID {
                chargesByWalletID[walletID, default: []].append(transaction)
                continue
            }

            if transaction.primaryKind == .transfer,
               transaction.transferSubtype == .internalTransfer,
               let walletID = transaction.destinationWalletID {
                paymentsByWalletID[walletID, default: []].append(transaction)
            }
        }

        for walletID in Array(chargesByWalletID.keys) {
            chargesByWalletID[walletID]?.sort(by: transactionSort)
        }
        for walletID in Array(paymentsByWalletID.keys) {
            paymentsByWalletID[walletID]?.sort(by: transactionSort)
        }

        return CreditCardStatementTransactionBuckets(
            chargesByWalletID: chargesByWalletID,
            paymentsByWalletID: paymentsByWalletID
        )
    }

    private static func isCreditCardStatementCharge(_ transaction: OverviewTransactionSnapshot) -> Bool {
        if transaction.primaryKind == .expense {
            return true
        }

        return transaction.primaryKind == .transfer
            && transaction.transferSubtype == .debt
            && transaction.debtIntent == .lend
            && transaction.sourceWalletKind == .creditCard
    }


    static func renderMonthlyStatement(
        _ statement: TransactionSummaryStatementSnapshot
    ) -> TransactionStatementDocument {
        let filename = "mistia-sao-ke-tong-hop-\(yearMonthToken(for: statement.period.start)).html"
        let body = """
        <div class="hero">
          <div>
            <div class="eyebrow">Mistia Statement</div>
            <h1>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.monthlySummaryStatement))</h1>
            <p>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.statementPeriod)): \(htmlEscaped(fullDateString(for: statement.period.start))) - \(htmlEscaped(fullDateString(for: statement.period.end)))</p>
            <p>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.generatedAt)) \(htmlEscaped(dateTimeString(for: statement.generatedAt)))</p>
          </div>
          <div class="hero-amount">\(htmlEscaped(statement.totalAssetBalanceMinor.formattedCurrency(code: statement.currencyCode)))</div>
        </div>

        <div class="grid three">
          \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.availableAssets, value: statement.totalAssetBalanceMinor.formattedCurrency(code: statement.currencyCode), accentClass: "green"))
          \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.incomeThisMonth, value: statement.totalIncomeMinor.formattedCurrency(code: statement.currencyCode), accentClass: "blue"))
          \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.expenseThisMonth, value: statement.totalExpenseMinor.formattedCurrency(code: statement.currencyCode), accentClass: "red"))
        </div>

        <div class="grid two">
          <section class="panel">
            <div class="panel-header">
              <h2>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.netCashflow))</h2>
              <span>\(htmlEscaped(statement.netCashflowMinor.formattedCurrency(code: statement.currencyCode)))</span>
            </div>
            \(renderChart(points: statement.chartPoints, currencyCode: statement.currencyCode))
          </section>
          <section class="panel">
            <div class="panel-header">
              <h2>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.assetWallets))</h2>
              <span>\(statement.wallets.count) \(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.wallets))</span>
            </div>
            \(renderWalletTable(rows: statement.wallets))
          </section>
        </div>

        <section class="panel">
          <div class="panel-header">
            <h2>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.transactionsThisMonth))</h2>
            <span>\(statement.transactions.count) \(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.items))</span>
          </div>
          \(renderTransactionTable(rows: statement.transactions, emptyMessage: L10n.shared.corelogic.transactionlogicstatement.noTransactionsInThisMonthYet))
        </section>
        """

        return TransactionStatementDocument(
            kind: .monthlySummary,
            filename: filename,
            html: renderDocument(
                title: L10n.shared.corelogic.transactionlogicstatement.mistiaMonthlySummary,
                subtitle: L10n.shared.corelogic.transactionlogicstatement.aSummaryOfAssetsCashflowAndTransactions,
                body: body
            )
        )
    }


    static func renderCreditCardStatement(
        _ statement: TransactionCreditCardStatementSnapshot
    ) -> TransactionStatementDocument {
        let filename = "mistia-sao-ke-the-tin-dung-\(yearMonthToken(for: statement.generatedAt)).html"
        let sections: String

        if statement.cards.isEmpty {
            sections = """
            <section class="panel empty">
              <h2>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.noCreditCardsYet))</h2>
              <p>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.youHaveNotAddedAnyCardsTo))</p>
            </section>
            """
        } else {
            sections = statement.cards.map { card in
                """
                <section class="panel card-panel">
                  <div class="panel-header">
                    <div>
                      <div class="eyebrow">\(htmlEscaped(card.networkTitle)) • •••• \(htmlEscaped(card.last4))</div>
                      <h2>\(htmlEscaped(card.walletName))</h2>
                      <p>\(htmlEscaped(card.issuerName.isEmpty ? L10n.shared.corelogic.transactionlogicstatement.creditCard : card.issuerName))</p>
                    </div>
                    <div class="badge">\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.utilization)) \(htmlEscaped(percentText(card.utilization)))</div>
                  </div>

                  <div class="grid four">
                    \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.currentDebt, value: card.currentDebtMinor.formattedCurrency(code: card.currencyCode), accentClass: "red"))
                    \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.creditLimit, value: card.creditLimitMinor.formattedCurrency(code: card.currencyCode), accentClass: "blue"))
                    \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.availableCredit, value: card.availableCreditMinor.formattedCurrency(code: card.currencyCode), accentClass: "green"))
                    \(summaryCard(title: L10n.shared.corelogic.transactionlogicstatement.nextPaymentDate, value: fullDateString(for: card.nextPaymentDate), accentClass: "orange"))
                  </div>

                  <div class="meta-grid">
                    <div class="meta-item">
                      <span>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.currentCycle))</span>
                      <strong>\(htmlEscaped(fullDateString(for: card.cycle.start))) - \(htmlEscaped(fullDateString(for: card.cycle.end.addingTimeInterval(-1))))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.statementClosingDay))</span>
                      <strong>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.dayValueEachMonth(String(describing: card.statementClosingDay))))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.paymentDueDay))</span>
                      <strong>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.dayValueEachMonth(String(describing: card.paymentDueDay))))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.paymentWallet))</span>
                      <strong>\(htmlEscaped(card.paymentSourceWalletName ?? L10n.shared.corelogic.transactionlogicstatement.notSet))</strong>
                    </div>
                  </div>

                  <div class="grid two">
                    <section class="subpanel">
                      <div class="panel-header">
                        <h3>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.chargesInCycle))</h3>
                        <span>\(card.charges.count) \(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.items))</span>
                      </div>
                      \(renderTransactionTable(rows: card.charges, emptyMessage: L10n.shared.corelogic.transactionlogicstatement.thereAreNoChargesInThisCycle))
                    </section>
                    <section class="subpanel">
                      <div class="panel-header">
                        <h3>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.paymentsToCard))</h3>
                        <span>\(card.payments.count) \(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.items))</span>
                      </div>
                      \(renderTransactionTable(rows: card.payments, emptyMessage: L10n.shared.corelogic.transactionlogicstatement.thereAreNoCardPaymentsInThis))
                    </section>
                  </div>
                </section>
                """
            }
            .joined(separator: "\n")
        }

        let body = """
        <div class="hero">
          <div>
            <div class="eyebrow">Mistia Statement</div>
            <h1>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.creditCardStatement))</h1>
            <p>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.aSummaryOfActiveCardsInMistia))</p>
            <p>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.generatedAt)) \(htmlEscaped(dateTimeString(for: statement.generatedAt)))</p>
          </div>
          <div class="hero-amount">\(statement.cards.count) \(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.cards))</div>
        </div>
        \(sections)
        """

        return TransactionStatementDocument(
            kind: .creditCard,
            filename: filename,
            html: renderDocument(
                title: L10n.shared.corelogic.transactionlogicstatement.mistiaCreditCardStatement,
                subtitle: L10n.shared.corelogic.transactionlogicstatement.aSummaryOfDebtCreditLimitsAnd,
                body: body
            )
        )
    }


    private static func statementAccountText(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense, .income:
            return transaction.sourceWalletName ?? L10n.shared.corelogic.transactionlogicstatement.noWalletSelected
        case .transfer:
            let source = transaction.sourceWalletName ?? L10n.shared.corelogic.transactionlogicstatement.source
            let destination = transaction.destinationWalletName ?? L10n.shared.corelogic.transactionlogicstatement.destination
            return "\(source) -> \(destination)"
        }
    }


    private static func statementDetailText(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense, .income:
            if let category = transaction.categoryName, !category.isEmpty {
                return category
            }
            return transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "-"
        case .transfer:
            if transaction.transferSubtype == .debt {
                return transaction.counterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? L10n.shared.corelogic.transactionlogicstatement.debt
            }
            return transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "-"
        }
    }


    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }


    private static func yearMonthToken(for date: Date) -> String {
        let components = MistiaCalendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }


    private static func fullDateString(for date: Date) -> String {
        MistiaDateFormatting.fullDateString(for: date)
    }


    private static func dateTimeString(for date: Date) -> String {
        MistiaDateFormatting.dateTimeString(for: date)
    }


    private static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }


    private static func summaryCard(
        title: String,
        value: String,
        accentClass: String
    ) -> String {
        """
        <div class="summary-card \(accentClass)">
          <span>\(htmlEscaped(title))</span>
          <strong>\(htmlEscaped(value))</strong>
        </div>
        """
    }


    private static func renderChart(
        points: [TransactionStatementChartPoint],
        currencyCode: String
    ) -> String {
        let maxValue = max(points.map(\.valueMinor).max() ?? 0, 1)

        let bars = points.map { point in
            let height = max(Double(point.valueMinor) / Double(maxValue), point.valueMinor > 0 ? 0.12 : 0.04)
            return """
            <div class="chart-bar">
              <div class="chart-fill" style="height: \(Int((height * 160).rounded()))px; background: \(OverviewLogic.barColor(for: point.intensity));"></div>
              <div class="chart-meta">
                <strong>\(htmlEscaped(point.label))</strong>
                <span>\(htmlEscaped(point.valueMinor.formattedCurrency(code: currencyCode)))</span>
              </div>
            </div>
            """
        }.joined(separator: "\n")

        return "<div class=\"chart\">\(bars)</div>"
    }


    private static func renderWalletTable(
        rows: [TransactionStatementWalletRow]
    ) -> String {
        guard !rows.isEmpty else {
            return "<div class=\"empty\"><p>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.thereAreNoAssetWalletsYet))</p></div>"
        }

        let body = rows.map { row in
            """
            <tr>
              <td><strong>\(htmlEscaped(row.name))</strong>\(htmlEscaped(row.kindTitle))</td>
              <td>\(htmlEscaped(row.openingBalanceMinor.formattedCurrency(code: row.currencyCode)))</td>
              <td>\(htmlEscaped(row.currentBalanceMinor.formattedCurrency(code: row.currencyCode)))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <table>
          <thead>
            <tr>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.wallet))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.openingBalance))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.currentBalance))</th>
            </tr>
          </thead>
          <tbody>
            \(body)
          </tbody>
        </table>
        """
    }


    private static func renderTransactionTable(
        rows: [TransactionStatementRow],
        emptyMessage: String
    ) -> String {
        guard !rows.isEmpty else {
            return "<div class=\"empty\"><p>\(htmlEscaped(emptyMessage))</p></div>"
        }

        let body = rows.map { row in
            """
            <tr>
              <td>\(htmlEscaped(dateTimeString(for: row.occurredAt)))</td>
              <td><strong>\(htmlEscaped(row.title))</strong>\(htmlEscaped(row.detailText))</td>
              <td>\(htmlEscaped(row.kindTitle))</td>
              <td>\(htmlEscaped(row.accountText))</td>
              <td class="amount-\(row.cashflowStyle.rawValue)">\(htmlEscaped(TransactionLogic.displayAmount(for: row)))</td>
              <td>\(htmlEscaped(row.statusTitle))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <table>
          <thead>
            <tr>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.dateTime))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.transaction))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.type))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.account))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.amount))</th>
              <th>\(htmlEscaped(L10n.shared.corelogic.transactionlogicstatement.status))</th>
            </tr>
          </thead>
          <tbody>
            \(body)
          </tbody>
        </table>
        """
    }


    private static func renderDocument(
        title: String,
        subtitle: String,
        body: String
    ) -> String {
        let language = MistiaAppLanguage.current
        return """
        <!doctype html>
        <html lang="\(language.rawValue)">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(htmlEscaped(title))</title>
          <style>
            :root {
              color-scheme: light;
              --bg: #eef2ff;
              --bg-soft: #f8faff;
              --panel: rgba(255,255,255,0.78);
              --panel-strong: rgba(255,255,255,0.92);
              --text: #14213d;
              --muted: #5b6480;
              --line: rgba(91,123,255,0.14);
              --shadow: 0 24px 60px rgba(28, 34, 65, 0.12);
              --green: #2daa9e;
              --orange: #f59b3f;
              --red: #f45c7e;
              --blue: #5b7bff;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif;
              background:
                radial-gradient(circle at top left, rgba(91,123,255,0.22), transparent 30%),
                radial-gradient(circle at top right, rgba(45,170,158,0.18), transparent 28%),
                linear-gradient(180deg, #f8faff 0%, #edf2ff 100%);
              color: var(--text);
            }
            .page {
              width: min(1120px, calc(100vw - 40px));
              margin: 32px auto;
              padding: 28px;
              border: 1px solid rgba(255,255,255,0.72);
              border-radius: 28px;
              background: rgba(255,255,255,0.62);
              backdrop-filter: blur(20px);
              box-shadow: var(--shadow);
            }
            .page-title { margin: 0 0 6px; font-size: 30px; }
            .page-subtitle { margin: 0 0 28px; color: var(--muted); font-size: 15px; }
            .hero, .panel, .subpanel {
              background: linear-gradient(180deg, var(--panel-strong), var(--panel));
              border: 1px solid var(--line);
              border-radius: 24px;
              box-shadow: 0 16px 36px rgba(20, 33, 61, 0.08);
            }
            .hero {
              display: flex;
              justify-content: space-between;
              align-items: flex-end;
              gap: 20px;
              padding: 24px;
              margin-bottom: 20px;
            }
            .hero h1, .panel h2, .subpanel h3 { margin: 0; }
            .hero p { margin: 4px 0 0; color: var(--muted); }
            .hero-amount {
              font-size: clamp(28px, 4vw, 46px);
              font-weight: 700;
              text-align: right;
            }
            .eyebrow {
              text-transform: uppercase;
              letter-spacing: 0.16em;
              font-size: 12px;
              color: var(--blue);
              font-weight: 700;
              margin-bottom: 8px;
            }
            .grid {
              display: grid;
              gap: 16px;
              margin-bottom: 20px;
            }
            .grid.two { grid-template-columns: repeat(2, minmax(0, 1fr)); }
            .grid.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
            .grid.four { grid-template-columns: repeat(4, minmax(0, 1fr)); }
            .summary-card {
              padding: 18px 18px 16px;
              border-radius: 20px;
              background: rgba(255,255,255,0.64);
              border: 1px solid rgba(91,123,255,0.12);
            }
            .summary-card span {
              display: block;
              margin-bottom: 10px;
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              color: var(--muted);
            }
            .summary-card strong {
              font-size: 22px;
              line-height: 1.25;
            }
            .summary-card.green strong { color: var(--green); }
            .summary-card.orange strong { color: var(--orange); }
            .summary-card.red strong { color: var(--red); }
            .summary-card.blue strong { color: var(--blue); }
            .panel, .subpanel {
              padding: 20px;
            }
            .subpanel { padding: 18px; }
            .panel-header {
              display: flex;
              align-items: flex-start;
              justify-content: space-between;
              gap: 16px;
              margin-bottom: 18px;
            }
            .panel-header span, .panel-header p {
              color: var(--muted);
              margin: 4px 0 0;
            }
            .chart {
              display: grid;
              grid-template-columns: repeat(7, minmax(0, 1fr));
              gap: 12px;
              align-items: end;
              min-height: 220px;
            }
            .chart-bar {
              display: flex;
              flex-direction: column;
              justify-content: flex-end;
              gap: 10px;
              min-height: 200px;
            }
            .chart-fill {
              border-radius: 16px 16px 10px 10px;
              min-height: 12px;
              box-shadow: inset 0 1px 1px rgba(255,255,255,0.2);
            }
            .chart-meta strong {
              display: block;
              font-size: 13px;
            }
            .chart-meta span {
              color: var(--muted);
              font-size: 12px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
            }
            th, td {
              text-align: left;
              padding: 12px 10px;
              border-bottom: 1px solid rgba(91,123,255,0.12);
              vertical-align: top;
            }
            th {
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              color: var(--muted);
            }
            td strong {
              display: block;
              margin-bottom: 4px;
            }
            .amount-income { color: var(--green); font-weight: 700; }
            .amount-expense { color: var(--red); font-weight: 700; }
            .amount-neutral { color: var(--blue); font-weight: 700; }
            .badge {
              display: inline-flex;
              align-items: center;
              padding: 8px 12px;
              border-radius: 999px;
              background: rgba(91,123,255,0.10);
              color: var(--blue);
              font-weight: 700;
            }
            .meta-grid {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 12px;
              margin: 18px 0 20px;
            }
            .meta-item {
              padding: 14px 16px;
              border-radius: 18px;
              background: rgba(255,255,255,0.58);
              border: 1px solid rgba(91,123,255,0.10);
            }
            .meta-item span {
              display: block;
              margin-bottom: 6px;
              color: var(--muted);
              font-size: 12px;
            }
            .empty {
              text-align: center;
              padding: 34px 24px;
            }
            @media (max-width: 900px) {
              .grid.two, .grid.three, .grid.four, .meta-grid {
                grid-template-columns: 1fr;
              }
              .hero {
                flex-direction: column;
                align-items: flex-start;
              }
              .hero-amount {
                text-align: left;
              }
              .chart {
                gap: 10px;
              }
            }
          </style>
        </head>
        <body>
          <main class="page">
            <h1 class="page-title">\(htmlEscaped(title))</h1>
            <p class="page-subtitle">\(htmlEscaped(subtitle))</p>
            \(body)
          </main>
        </body>
        </html>
        """
    }


    private static func transactionSort(
        lhs: OverviewTransactionSnapshot,
        rhs: OverviewTransactionSnapshot
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }
        return lhs.createdAt > rhs.createdAt
    }


    private static func makeStatementRow(
        from transaction: OverviewTransactionSnapshot,
        currencyCode: String
    ) -> TransactionStatementRow {
        TransactionStatementRow(
            id: transaction.id,
            occurredAt: transaction.occurredAt,
            title: transaction.title,
            kindTitle: OverviewLogic.transactionKindTitle(for: transaction),
            accountText: statementAccountText(for: transaction),
            detailText: statementDetailText(for: transaction),
            amountMinor: transaction.amountMinor,
            currencyCode: currencyCode,
            cashflowStyle: OverviewLogic.cashflowStyle(for: transaction),
            statusTitle: transaction.entryStatus.title
        )
    }

}
