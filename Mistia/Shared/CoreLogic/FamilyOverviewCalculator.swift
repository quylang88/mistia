import Foundation
import os

struct FamilyOverviewCreditCardProfileSnapshot: Equatable {
    let issuerName: String
    let network: CreditCardNetwork
    let last4: String
    let creditLimitMinor: Int64
    let statementClosingDay: Int
    let paymentDueDay: Int
    let paymentSourceWalletID: UUID?
    let paymentSourceWalletName: String?
    let autoPayEnabled: Bool
}

struct FamilyOverviewWalletInputSnapshot: Equatable, Identifiable {
    let id: UUID
    let ownerUserID: UUID
    let name: String
    let kind: LedgerWalletKind
    let openingBalanceMinor: Int64
    let creditCardProfile: FamilyOverviewCreditCardProfileSnapshot?
    let currencyCode: String
    let sortOrder: Int
    let createdAt: Date
}

struct FamilyOverviewTransactionInputSnapshot: Equatable {
    let record: TransactionRecordSnapshot
    let overview: OverviewTransactionSnapshot
    let aggregate: FamilyAggregateTransactionSnapshot
}

struct FamilyOverviewCalculationInput: Equatable {
    let now: Date
    let currentMonth: Date
    let selectedBillMonth: Date
    let selectedInterval: DateInterval
    let timeframeTitle: String
    let familyMemberUserIDs: Set<UUID>
    let memberNames: [UUID: String]
    let memberOrder: [UUID]
    let familyOwnerUserID: UUID?
    let budgetManagerUserID: UUID?
    let goalManagerUserID: UUID?
    let reportingCurrencyCode: String
    let exchangeRates: [MistiaExchangeRate]
    let calendar: Calendar
    let wallets: [FamilyOverviewWalletInputSnapshot]
    let transactions: [FamilyOverviewTransactionInputSnapshot]
    let budgets: [FamilyBudgetPlanSnapshot]
    let goals: [FamilyGoalSnapshot]
    let bills: [PlanningBillSnapshot]
    let installments: [PlanningInstallmentSnapshot]
    let occurrences: [PlanningDueOccurrenceSnapshot]
}

struct FamilyOverviewCalculationResult: Equatable {
    let walletRows: [FamilyWalletAggregateSnapshot]
    let summary: FamilyAggregateSummary
    let monthlySpendable: FamilyMonthlySpendableSnapshot
    let categorySpendingSnapshot: OverviewCategorySpendingMonthSnapshot
    let budgetRows: [FamilyBudgetAggregateSnapshot]
    let goalRows: [FamilyGoalAggregateSnapshot]
    let dueAlerts: [OverviewDueAlertSnapshot]
    let monthlyBillRows: [FamilyMonthlyBillAggregateSnapshot]
    let monthlyBillTotalsByCurrency: [FamilyMonthlyBillTotalSnapshot]
}

enum FamilyOverviewCalculator {
    nonisolated static func compute(
        input: FamilyOverviewCalculationInput
    ) -> FamilyOverviewCalculationResult {
        let log = OSLog(subsystem: "Mistia", category: "FamilyOverview")
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "FamilyOverviewCalculator.compute", signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: "FamilyOverviewCalculator.compute", signpostID: signpostID)
        }

        let transactionRecords = input.transactions.map(\.record)
        let overviewTransactions = input.transactions.map(\.overview)
        let aggregateTransactions = input.transactions.map(\.aggregate)
        let walletBalanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: input.wallets.map {
                TransactionWalletSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    openingBalanceMinor: $0.openingBalanceMinor
                )
            },
            records: transactionRecords
        )
        let creditCardAccounts = input.wallets.compactMap {
            creditCardAccount(for: $0, balanceIndex: walletBalanceIndex)
        }
        let currentMonthCreditCardStatements = PlanningLogic.creditCardStatementItems(
            accounts: creditCardAccounts,
            records: transactionRecords,
            occurrences: input.occurrences,
            statementMonths: [input.currentMonth],
            referenceDate: input.now,
            calendar: input.calendar
        )
        let creditCardStatementStatusByWalletID: [UUID: FamilyCreditCardStatementStatus] = Dictionary(
            uniqueKeysWithValues: currentMonthCreditCardStatements.compactMap { statement in
                guard statement.amountMinor > 0 else { return nil }
                let status: FamilyCreditCardStatementStatus = statement.state == .paid
                    ? .paid
                    : .upcoming
                return (statement.walletID, status)
            }
        )
        let walletRows = FamilyLogic.aggregateWalletsByName(
            input.wallets
                .sorted(by: walletSort)
                .map { wallet in
                    let balanceSnapshot = TransactionWalletSnapshot(
                        id: wallet.id,
                        kind: wallet.kind,
                        openingBalanceMinor: wallet.openingBalanceMinor
                    )
                    let debt = walletBalanceIndex.balance(for: balanceSnapshot)
                    let displayBalance: Int64
                    if wallet.kind == .creditCard,
                       let profile = wallet.creditCardProfile {
                        displayBalance = max(profile.creditLimitMinor - debt, 0)
                    } else {
                        displayBalance = debt
                    }

                    let creditCardDebt: Int64
                    if wallet.kind == .creditCard,
                       let profile = wallet.creditCardProfile {
                        creditCardDebt = max(profile.creditLimitMinor - displayBalance, 0)
                    } else {
                        creditCardDebt = 0
                    }

                    return FamilyWalletAggregateSnapshot(
                        id: wallet.id.uuidString,
                        ownerUserID: wallet.ownerUserID,
                        name: wallet.name,
                        kind: wallet.kind,
                        currentBalanceMinor: displayBalance,
                        debtMinor: creditCardDebt,
                        currencyCode: wallet.currencyCode,
                        sortOrder: wallet.sortOrder,
                        createdAt: wallet.createdAt,
                        creditCardStatementStatus: creditCardStatementStatusByWalletID[wallet.id]
                    )
                },
            reportingCurrencyCode: input.reportingCurrencyCode,
            exchangeRates: input.exchangeRates
        )
        let creditCardStatementDueItems = PlanningLogic.creditCardStatementsDue(
            in: input.currentMonth,
            accounts: creditCardAccounts,
            records: transactionRecords,
            occurrences: input.occurrences,
            referenceDate: input.now,
            calendar: input.calendar
        )
        let creditCardDueItems = PlanningLogic.creditCardDueItems(
            accounts: creditCardAccounts,
            records: transactionRecords,
            occurrences: input.occurrences,
            selectedMonth: input.currentMonth,
            referenceDate: input.now,
            calendar: input.calendar
        )
        let recurringBillDueItems = PlanningLogic.recurringBillDueItems(
            bills: input.bills,
            occurrences: input.occurrences,
            selectedMonth: input.currentMonth,
            calendar: input.calendar
        )
        let monthlyBillRows = FamilyLogic.monthlyBillRows(
            bills: input.bills,
            occurrences: input.occurrences,
            selectedMonth: input.selectedBillMonth,
            calendar: input.calendar
        )
        let installmentDueItems = PlanningLogic.installmentDueItems(
            plans: input.installments,
            occurrences: input.occurrences,
            selectedMonth: input.currentMonth,
            calendar: input.calendar
        )
        let monthlyDueSummary = PlanningLogic.dueSummary(
            creditStatements: creditCardStatementDueItems,
            recurring: recurringBillDueItems + installmentDueItems,
            selectedMonth: input.currentMonth,
            reportingCurrencyCode: input.reportingCurrencyCode,
            exchangeRates: input.exchangeRates,
            referenceDate: input.now,
            calendar: input.calendar
        )
        let budgetRows = FamilyLogic.familyBudgetRows(
            plans: input.budgets,
            transactions: aggregateTransactions,
            selectedMonth: input.currentMonth,
            ownerUserID: input.familyOwnerUserID,
            budgetManagerUserID: input.budgetManagerUserID,
            memberOrder: input.memberOrder,
            referenceDate: input.now,
            calendar: input.calendar,
            exchangeRates: input.exchangeRates
        )
        let goalRows = FamilyLogic.familyGoalRows(
            goals: input.goals,
            ownerUserID: input.familyOwnerUserID,
            goalManagerUserID: input.goalManagerUserID,
            memberOrder: input.memberOrder,
            exchangeRates: input.exchangeRates
        )
        let dueAlerts = OverviewLogic.dueAlerts(
            creditCardDues: creditCardDueItems,
            recurringDues: recurringBillDueItems + installmentDueItems,
            referenceDate: input.now,
            calendar: input.calendar
        )
        let summary = FamilyLogic.aggregateSummary(
            wallets: walletRows.map {
                FamilyAggregateWalletSnapshot(
                    ownerUserID: $0.ownerUserID,
                    kind: familyAggregateKind(for: $0.kind),
                    balanceMinor: $0.kind == LedgerWalletKind.creditCard ? 0 : $0.currentBalanceMinor,
                    debtMinor: $0.debtMinor,
                    name: $0.name,
                    currencyCode: $0.currencyCode
                )
            },
            transactions: aggregateTransactions,
            selectedInterval: input.selectedInterval,
            visibleMemberIDs: input.familyMemberUserIDs,
            memberNames: input.memberNames,
            reportingCurrencyCode: input.reportingCurrencyCode,
            exchangeRates: input.exchangeRates,
            calendar: input.calendar
        )
        let categorySpendingSnapshot = OverviewLogic.categorySpendingInterval(
            from: overviewTransactions,
            interval: input.selectedInterval,
            title: input.timeframeTitle,
            currencyCode: input.reportingCurrencyCode,
            exchangeRates: input.exchangeRates,
            calendar: input.calendar
        )
        let monthlySpendable = FamilyLogic.monthlySpendable(
            totalAssetsMinor: summary.totalAssetsMinor,
            monthlyDueMinor: monthlyDueSummary.totalDueMinor
        )

        return FamilyOverviewCalculationResult(
            walletRows: walletRows,
            summary: summary,
            monthlySpendable: monthlySpendable,
            categorySpendingSnapshot: categorySpendingSnapshot,
            budgetRows: budgetRows,
            goalRows: goalRows,
            dueAlerts: dueAlerts,
            monthlyBillRows: monthlyBillRows,
            monthlyBillTotalsByCurrency: FamilyLogic.monthlyBillTotalsByCurrency(from: monthlyBillRows)
        )
    }

    nonisolated private static func walletSort(
        lhs: FamilyOverviewWalletInputSnapshot,
        rhs: FamilyOverviewWalletInputSnapshot
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }

    nonisolated private static func familyAggregateKind(
        for kind: LedgerWalletKind
    ) -> FamilyAggregateWalletSnapshot.Kind {
        switch kind {
        case .cash:
            return .cash
        case .payPay, .eWallet, .prepaid:
            return .ewallet
        case .bank:
            return .bank
        case .creditCard:
            return .creditCard
        case .investment, .crypto, .other:
            return .other
        }
    }

    nonisolated private static func creditCardAccount(
        for wallet: FamilyOverviewWalletInputSnapshot,
        balanceIndex: TransactionWalletBalanceIndex
    ) -> PlanningCreditCardAccountSnapshot? {
        guard wallet.kind == .creditCard,
              let profile = wallet.creditCardProfile else {
            return nil
        }

        let debt = max(
            balanceIndex.balance(
                for: TransactionWalletSnapshot(
                    id: wallet.id,
                    kind: wallet.kind,
                    openingBalanceMinor: wallet.openingBalanceMinor
                )
            ),
            0
        )
        let availableCredit = max(profile.creditLimitMinor - debt, 0)

        return PlanningCreditCardAccountSnapshot(
            id: wallet.id,
            walletID: wallet.id,
            walletName: wallet.name,
            issuerName: profile.issuerName,
            network: profile.network,
            last4: profile.last4,
            dueDay: profile.paymentDueDay,
            statementClosingDay: profile.statementClosingDay,
            paymentSourceWalletID: profile.paymentSourceWalletID,
            paymentSourceWalletName: profile.paymentSourceWalletName,
            currencyCode: wallet.currencyCode,
            currentDebtMinor: debt,
            availableCreditMinor: availableCredit,
            openedAt: wallet.createdAt,
            autoPayEnabled: profile.autoPayEnabled
        )
    }
}
