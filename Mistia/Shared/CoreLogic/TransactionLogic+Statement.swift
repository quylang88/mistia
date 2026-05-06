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

                let charges = transactions
                    .filter {
                        $0.entryStatus == .posted
                            && !$0.isArchived
                            && $0.primaryKind == .expense
                            && $0.sourceWalletID == account.walletID
                            && contains($0.occurredAt, in: cycle)
                    }
                    .sorted(by: transactionSort)
                    .map { makeStatementRow(from: $0, currencyCode: account.currencyCode) }

                let payments = transactions
                    .filter {
                        $0.entryStatus == .posted
                            && !$0.isArchived
                            && $0.primaryKind == .transfer
                            && $0.transferSubtype == .internalTransfer
                            && $0.destinationWalletID == account.walletID
                            && contains($0.occurredAt, in: cycle)
                    }
                    .sorted(by: transactionSort)
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


    static func renderMonthlyStatement(
        _ statement: TransactionSummaryStatementSnapshot
    ) -> TransactionStatementDocument {
        let language = MistiaAppLanguage.current
        let filename = "mistia-sao-ke-tong-hop-\(yearMonthToken(for: statement.period.start)).html"
        let body = """
        <div class="hero">
          <div>
            <div class="eyebrow">Mistia Statement</div>
            <h1>\(htmlEscaped(mistiaLocalized(vi: "Sao kê tổng hợp tháng", en: "Monthly summary statement", ja: "月次サマリーステートメント", language: language)))</h1>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Kỳ sao kê", en: "Statement period", ja: "対象期間", language: language))): \(htmlEscaped(fullDateString(for: statement.period.start))) - \(htmlEscaped(fullDateString(for: statement.period.end)))</p>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Xuất lúc", en: "Generated at", ja: "出力日時", language: language))) \(htmlEscaped(dateTimeString(for: statement.generatedAt)))</p>
          </div>
          <div class="hero-amount">\(htmlEscaped(statement.totalAssetBalanceMinor.formattedCurrency(code: statement.currencyCode)))</div>
        </div>

        <div class="grid three">
          \(summaryCard(title: mistiaLocalized(vi: "Tài sản khả dụng", en: "Available assets", ja: "利用可能資産", language: language), value: statement.totalAssetBalanceMinor.formattedCurrency(code: statement.currencyCode), accentClass: "green"))
          \(summaryCard(title: mistiaLocalized(vi: "Thu tháng này", en: "Income this month", ja: "今月の収入", language: language), value: statement.totalIncomeMinor.formattedCurrency(code: statement.currencyCode), accentClass: "blue"))
          \(summaryCard(title: mistiaLocalized(vi: "Chi tháng này", en: "Expense this month", ja: "今月の支出", language: language), value: statement.totalExpenseMinor.formattedCurrency(code: statement.currencyCode), accentClass: "red"))
        </div>

        <div class="grid two">
          <section class="panel">
            <div class="panel-header">
              <h2>\(htmlEscaped(mistiaLocalized(vi: "Chênh lệch dòng tiền", en: "Net cashflow", ja: "キャッシュフロー差額", language: language)))</h2>
              <span>\(htmlEscaped(statement.netCashflowMinor.formattedCurrency(code: statement.currencyCode)))</span>
            </div>
            \(renderChart(points: statement.chartPoints, currencyCode: statement.currencyCode))
          </section>
          <section class="panel">
            <div class="panel-header">
              <h2>\(htmlEscaped(mistiaLocalized(vi: "Ví tài sản", en: "Asset wallets", ja: "資産ウォレット", language: language)))</h2>
              <span>\(statement.wallets.count) \(htmlEscaped(mistiaLocalized(vi: "ví", en: "wallets", ja: "件", language: language)))</span>
            </div>
            \(renderWalletTable(rows: statement.wallets))
          </section>
        </div>

        <section class="panel">
          <div class="panel-header">
            <h2>\(htmlEscaped(mistiaLocalized(vi: "Giao dịch tháng hiện tại", en: "Transactions this month", ja: "今月の取引", language: language)))</h2>
            <span>\(statement.transactions.count) \(htmlEscaped(mistiaLocalized(vi: "mục", en: "items", ja: "件", language: language)))</span>
          </div>
          \(renderTransactionTable(rows: statement.transactions, emptyMessage: mistiaLocalized(vi: "Chưa có giao dịch nào trong tháng này.", en: "No transactions in this month yet.", ja: "今月の取引はまだありません。", language: language)))
        </section>
        """

        return TransactionStatementDocument(
            kind: .monthlySummary,
            filename: filename,
            html: renderDocument(
                title: mistiaLocalized(vi: "Mistia Sao kê tổng hợp", en: "Mistia Monthly Summary", ja: "Mistia 月次サマリー", language: language),
                subtitle: mistiaLocalized(vi: "Tổng hợp tài sản, dòng tiền và giao dịch tháng hiện tại", en: "A summary of assets, cashflow, and transactions for the current month", ja: "今月の資産、キャッシュフロー、取引のサマリー", language: language),
                body: body
            )
        )
    }


    static func renderCreditCardStatement(
        _ statement: TransactionCreditCardStatementSnapshot
    ) -> TransactionStatementDocument {
        let language = MistiaAppLanguage.current
        let filename = "mistia-sao-ke-the-tin-dung-\(yearMonthToken(for: statement.generatedAt)).html"
        let sections: String

        if statement.cards.isEmpty {
            sections = """
            <section class="panel empty">
              <h2>\(htmlEscaped(mistiaLocalized(vi: "Chưa có thẻ tín dụng", en: "No credit cards yet", ja: "クレジットカードはまだありません", language: language)))</h2>
              <p>\(htmlEscaped(mistiaLocalized(vi: "Hiện tại bạn chưa thêm thẻ nào vào Mistia nên không có sao kê để xuất.", en: "You have not added any cards to Mistia yet, so there is no statement to export.", ja: "Mistia にカードがまだ追加されていないため、書き出せる明細がありません。", language: language)))</p>
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
                      <p>\(htmlEscaped(card.issuerName.isEmpty ? mistiaLocalized(vi: "Thẻ tín dụng", en: "Credit card", ja: "クレジットカード", language: language) : card.issuerName))</p>
                    </div>
                    <div class="badge">\(htmlEscaped(mistiaLocalized(vi: "Tỷ lệ sử dụng", en: "Utilization", ja: "利用率", language: language))) \(htmlEscaped(percentText(card.utilization)))</div>
                  </div>

                  <div class="grid four">
                    \(summaryCard(title: mistiaLocalized(vi: "Dư nợ hiện tại", en: "Current debt", ja: "現在の利用残高", language: language), value: card.currentDebtMinor.formattedCurrency(code: card.currencyCode), accentClass: "red"))
                    \(summaryCard(title: mistiaLocalized(vi: "Hạn mức", en: "Credit limit", ja: "利用限度額", language: language), value: card.creditLimitMinor.formattedCurrency(code: card.currencyCode), accentClass: "blue"))
                    \(summaryCard(title: mistiaLocalized(vi: "Hạn mức còn lại", en: "Available credit", ja: "利用可能額", language: language), value: card.availableCreditMinor.formattedCurrency(code: card.currencyCode), accentClass: "green"))
                    \(summaryCard(title: mistiaLocalized(vi: "Ngày thanh toán tiếp theo", en: "Next payment date", ja: "次回支払日", language: language), value: fullDateString(for: card.nextPaymentDate), accentClass: "orange"))
                  </div>

                  <div class="meta-grid">
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Kỳ sao kê hiện tại", en: "Current cycle", ja: "現在の締め期間", language: language)))</span>
                      <strong>\(htmlEscaped(fullDateString(for: card.cycle.start))) - \(htmlEscaped(fullDateString(for: card.cycle.end.addingTimeInterval(-1))))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Ngày chốt sao kê", en: "Statement closing day", ja: "締め日", language: language)))</span>
                      <strong>\(htmlEscaped(mistiaLocalized(vi: "\(card.statementClosingDay) hằng tháng", en: "Day \(card.statementClosingDay) each month", ja: "毎月 \(card.statementClosingDay) 日", language: language)))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Ngày thanh toán", en: "Payment due day", ja: "支払日", language: language)))</span>
                      <strong>\(htmlEscaped(mistiaLocalized(vi: "\(card.paymentDueDay) hằng tháng", en: "Day \(card.paymentDueDay) each month", ja: "毎月 \(card.paymentDueDay) 日", language: language)))</strong>
                    </div>
                    <div class="meta-item">
                      <span>\(htmlEscaped(mistiaLocalized(vi: "Ví thanh toán", en: "Payment wallet", ja: "支払い元ウォレット", language: language)))</span>
                      <strong>\(htmlEscaped(card.paymentSourceWalletName ?? mistiaLocalized(vi: "Chưa cài đặt", en: "Not set", ja: "未設定", language: language)))</strong>
                    </div>
                  </div>

                  <div class="grid two">
                    <section class="subpanel">
                      <div class="panel-header">
                        <h3>\(htmlEscaped(mistiaLocalized(vi: "Chi tiêu trong kỳ", en: "Charges in cycle", ja: "期間内の利用", language: language)))</h3>
                        <span>\(card.charges.count) \(htmlEscaped(mistiaLocalized(vi: "mục", en: "items", ja: "件", language: language)))</span>
                      </div>
                      \(renderTransactionTable(rows: card.charges, emptyMessage: mistiaLocalized(vi: "Không có chi tiêu nào trong kỳ sao kê này.", en: "There are no charges in this cycle.", ja: "この締め期間の利用はありません。", language: language)))
                    </section>
                    <section class="subpanel">
                      <div class="panel-header">
                        <h3>\(htmlEscaped(mistiaLocalized(vi: "Thanh toán vào thẻ", en: "Payments to card", ja: "カードへの支払い", language: language)))</h3>
                        <span>\(card.payments.count) \(htmlEscaped(mistiaLocalized(vi: "mục", en: "items", ja: "件", language: language)))</span>
                      </div>
                      \(renderTransactionTable(rows: card.payments, emptyMessage: mistiaLocalized(vi: "Chưa có giao dịch thanh toán vào thẻ trong kỳ.", en: "There are no card payments in this cycle.", ja: "この期間のカード支払いはありません。", language: language)))
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
            <h1>\(htmlEscaped(mistiaLocalized(vi: "Sao kê thẻ tín dụng", en: "Credit card statement", ja: "クレジットカード明細", language: language)))</h1>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Bản tổng hợp cho các thẻ đang hoạt động trong Mistia.", en: "A summary of active cards in Mistia.", ja: "Mistia で利用中のカードをまとめた明細です。", language: language)))</p>
            <p>\(htmlEscaped(mistiaLocalized(vi: "Xuất lúc", en: "Generated at", ja: "出力日時", language: language))) \(htmlEscaped(dateTimeString(for: statement.generatedAt)))</p>
          </div>
          <div class="hero-amount">\(statement.cards.count) \(htmlEscaped(mistiaLocalized(vi: "thẻ", en: "cards", ja: "枚", language: language)))</div>
        </div>
        \(sections)
        """

        return TransactionStatementDocument(
            kind: .creditCard,
            filename: filename,
            html: renderDocument(
                title: mistiaLocalized(vi: "Mistia Sao kê thẻ tín dụng", en: "Mistia Credit Card Statement", ja: "Mistia クレジットカード明細", language: language),
                subtitle: mistiaLocalized(vi: "Tổng hợp dư nợ, hạn mức và giao dịch trong kỳ sao kê hiện tại", en: "A summary of debt, credit limits, and transactions in the current cycle", ja: "現在の締め期間における残高、利用枠、取引のサマリー", language: language),
                body: body
            )
        )
    }


    private static func statementAccountText(
        for transaction: OverviewTransactionSnapshot
    ) -> String {
        switch transaction.primaryKind {
        case .expense, .income:
            return transaction.sourceWalletName ?? mistiaLocalized(vi: "Chưa chọn ví", en: "No wallet selected", ja: "ウォレット未選択")
        case .transfer:
            let source = transaction.sourceWalletName ?? mistiaLocalized(vi: "Nguồn", en: "Source", ja: "出金元")
            let destination = transaction.destinationWalletName ?? mistiaLocalized(vi: "Đích", en: "Destination", ja: "入金先")
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
                return transaction.counterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? mistiaLocalized(vi: "Công nợ", en: "Debt", ja: "貸し借り")
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
            return "<div class=\"empty\"><p>\(htmlEscaped(mistiaLocalized(vi: "Chưa có ví tài sản nào.", en: "There are no asset wallets yet.", ja: "資産ウォレットはまだありません。")))</p></div>"
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
              <th>\(htmlEscaped(mistiaLocalized(vi: "Ví", en: "Wallet", ja: "ウォレット")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Số dư đầu kỳ", en: "Opening balance", ja: "期首残高")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Số dư hiện tại", en: "Current balance", ja: "現在残高")))</th>
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
              <th>\(htmlEscaped(mistiaLocalized(vi: "Ngày giờ", en: "Date & time", ja: "日時")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Giao dịch", en: "Transaction", ja: "取引")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Loại", en: "Type", ja: "種類")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Tài khoản", en: "Account", ja: "口座")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Số tiền", en: "Amount", ja: "金額")))</th>
              <th>\(htmlEscaped(mistiaLocalized(vi: "Trạng thái", en: "Status", ja: "状態")))</th>
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
