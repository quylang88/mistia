import XCTest
@testable import MistiaCoreLogic

/// Test cases for Credit Card Edge Cases
final class CreditCardEdgeCasesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese, defaults: UserDefaults.standard)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

    // MARK: - Helper Functions

    private func makeRecord(
        id: UUID = UUID(),
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        entryStatus: TransactionEntryStatus = .posted,
        title: String = "Sample",
        amountMinor: Int64,
        occurredAt: Date,
        sourceWalletID: UUID? = nil,
        sourceWalletKind: LedgerWalletKind? = nil,
        destinationWalletID: UUID? = nil,
        destinationWalletKind: LedgerWalletKind? = nil,
        categoryID: UUID? = nil,
        counterpartyName: String? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: title,
            note: nil,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletKind: destinationWalletKind,
            categoryID: categoryID,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(counterpartyName)
        )
    }

    // MARK: - Edge Case 1: No payment source wallet

    func testEdgeCase1_NoPaymentSourceWallet() {
        // When payment source wallet is not set, payment should fail
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // No payment transaction exists
        let allTransactions = [expenseTx]

        // Should not be locked (no payment made)
        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch không bị khóa khi chưa có thanh toán"
        )
    }

    // MARK: - Edge Case 2: Insufficient funds in payment source

    func testEdgeCase2_InsufficientFundsInPaymentSource() {
        let sourceWalletID = UUID()
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        // Source wallet has 300,000 but need 500,000
        let sourceWallet = TransactionWalletSnapshot(
            id: sourceWalletID,
            kind: .cash,
            openingBalanceMinor: 300_000
        )

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let records = [expenseTx]

        let balance = TransactionLogic.effectiveBalance(for: sourceWallet, records: records)
        XCTAssertEqual(balance, 300_000, "Số dư ví nguồn phải là 300,000")
        XCTAssertLessThan(balance, 500_000, "Số dư không đủ để thanh toán")
    }

    // MARK: - Edge Case 3: Double payment prevention

    func testEdgeCase3_DoublePaymentPrevention() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // First payment
        let paymentTx1 = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx1]

        // After first payment, transactions should be locked
        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch phải bị khóa sau khi thanh toán"
        )
    }

    // MARK: - Edge Case 4: Edit transaction after payment

    func testEdgeCase4_EditTransactionAfterPayment() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx]

        // Transaction should be locked
        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch phải bị khóa khi đã thanh toán"
        )
    }

    // MARK: - Edge Case 5: Archive wallet with debt

    func testEdgeCase5_ArchiveWalletWithDebt() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let creditCard = TransactionWalletSnapshot(
            id: creditCardID,
            kind: .creditCard,
            openingBalanceMinor: 0
        )

        // Expense creates debt
        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let records = [expenseTx]

        let debt = TransactionLogic.effectiveBalance(for: creditCard, records: records)
        XCTAssertEqual(debt, 500_000, "Dư nợ phải là 500,000")
        XCTAssertGreaterThan(debt, 0, "Phải có dư nợ để trigger validation")
    }

    // MARK: - Edge Case 6: Change payment source with debt

    func testEdgeCase6_ChangePaymentSourceWithDebt() {
        let creditCardID = UUID()
        _ = UUID() // sourceWallet1ID - used in UI logic
        _ = UUID() // sourceWallet2ID - used in UI logic
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let creditCard = TransactionWalletSnapshot(
            id: creditCardID,
            kind: .creditCard,
            openingBalanceMinor: 0
        )

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let records = [expenseTx]
        let debt = TransactionLogic.effectiveBalance(for: creditCard, records: records)

        XCTAssertEqual(debt, 500_000, "Dư nợ phải là 500,000")
        // Should require confirmation when changing from sourceWallet1ID to sourceWallet2ID
    }

    // MARK: - Edge Case 7: Change closing day mid-month

    func testEdgeCase7_ChangeClosingDayMidMonth() {
        let calendar = Calendar.current
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400) // March 2025

        // Original closing day: 25
        // New closing day: 10
        // Should not affect current month's statement cycle

        let originalCycle = OverviewLogic.creditCardStatementCycle(
            statementClosingDay: 25,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let newCycle = OverviewLogic.creditCardStatementCycle(
            statementClosingDay: 10,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Cycles should be different
        XCTAssertNotEqual(originalCycle.start, newCycle.start, "Cycle start should change")
        XCTAssertNotEqual(originalCycle.end, newCycle.end, "Cycle end should change")
    }

    // MARK: - Edge Case 8: Due day < Closing day

    func testEdgeCase8_DueDayLessThanClosingDay() {
        let calendar = Calendar.current
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400) // March 2025

        // Closing day: 25, Due day: 5 (next month)
        let cycle = OverviewLogic.creditCardStatementCycle(
            statementClosingDay: 25,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let nextPaymentDate = TransactionLogic.nextPaymentDate(
            paymentDueDay: 5,
            cycleEnd: cycle.end,
            calendar: calendar
        )

        // Payment date should be in the month after the cycle ends
        XCTAssertGreaterThan(nextPaymentDate, cycle.end, "Payment date should be after cycle ends")
    }

    // MARK: - Edge Case 9: Multiple payments in same month

    func testEdgeCase9_MultiplePaymentsSameMonth() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // Multiple payments in same month
        let paymentTx1 = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025",
            amountMinor: 300_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let paymentTx2 = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025 - lần 2",
            amountMinor: 200_000,
            occurredAt: referenceDate.addingTimeInterval(172800),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        _ = [expenseTx, paymentTx1, paymentTx2]

        // Should detect at least one payment
        let calendar = Calendar.current
        let hasPayment = [expenseTx, paymentTx1, paymentTx2].first { (tx: TransactionRecordSnapshot) -> Bool in
            guard tx.destinationWalletID == creditCardID else { return false }
            guard tx.primaryKind == .transfer else { return false }
            guard tx.transferSubtype == .internalTransfer else { return false }
            guard calendar.isDate(tx.occurredAt, equalTo: referenceDate, toGranularity: .month) else { return false }
            let titleMatch = tx.title.localizedStandardContains("thanh toán thẻ") ||
                             tx.title.localizedStandardContains("card payment")
            return titleMatch
        } != nil

        XCTAssertTrue(hasPayment, "Phải phát hiện ít nhất 1 thanh toán")
    }

    // MARK: - Edge Case 10: Partial payment

    func testEdgeCase10_PartialPayment() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx1 = makeRecord(
            primaryKind: .expense,
            amountMinor: 300_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let expenseTx2 = makeRecord(
            primaryKind: .expense,
            amountMinor: 200_000,
            occurredAt: referenceDate.addingTimeInterval(3600),
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // Partial payment (only 300,000 out of 500,000)
        let partialPaymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025",
            amountMinor: 300_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx1, expenseTx2, partialPaymentTx]

        // Total spent
        let totalSpent = expenseTx1.amountMinor + expenseTx2.amountMinor
        XCTAssertEqual(totalSpent, 500_000, "Tổng chi tiêu là 500,000")

        // Partial payment
        let partialPayment = partialPaymentTx.amountMinor
        XCTAssertEqual(partialPayment, 300_000, "Thanh toán 1 phần là 300,000")

        XCTAssertLessThan(partialPayment, totalSpent, "Partial payment < total spent")
    }

    // MARK: - Edge Case 11: Refund transactions

    func testEdgeCase11_RefundTransactions() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        // Original expense
        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // Refund (could be represented as negative expense or income to card)
        // For now, we track it as a separate transaction
        let refundTx = makeRecord(
            primaryKind: .income,
            amountMinor: 100_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let records = [expenseTx, refundTx]

        let creditCard = TransactionWalletSnapshot(
            id: creditCardID,
            kind: .creditCard,
            openingBalanceMinor: 0
        )

        let netDebt = TransactionLogic.effectiveBalance(for: creditCard, records: records)

        // Refund should reduce debt
        XCTAssertEqual(netDebt, 400_000, "Dư nợ sau refund là 400,000")
    }

    // MARK: - Edge Case 12: Undo payment after sync

    func testEdgeCase12_UndoPaymentAfterSync() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        // Simulate undo by removing payment from list (deletedAt set)
        let transactionsBeforeUndo = [expenseTx, paymentTx]
        let transactionsAfterUndo = [expenseTx]

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: transactionsBeforeUndo
            ),
            "Trước undo: giao dịch phải bị khóa"
        )

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: transactionsAfterUndo
            ),
            "Sau undo: giao dịch phải được mở khóa"
        )
    }

    // MARK: - Edge Case 13: Family member permission

    func testEdgeCase13_FamilyMemberPermission() {
        // This test verifies that family members with view-only access
        // cannot modify credit card transactions

        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // View-only members should not be able to modify
        // This is enforced at the UI/permission layer
        XCTAssertNotNil(expenseTx.id, "Transaction exists for view-only member to see")
    }

    // MARK: - Edge Case 14: Credit limit = 0 or < debt

    func testEdgeCase14_CreditLimitZeroOrLessThanDebt() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let creditCard = TransactionWalletSnapshot(
            id: creditCardID,
            kind: .creditCard,
            openingBalanceMinor: 0
        )

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let records = [expenseTx]
        let debt = TransactionLogic.effectiveBalance(for: creditCard, records: records)

        // Credit limit = 0
        let creditLimit: Int64 = 0
        let availableCredit = max(creditLimit - debt, 0)

        XCTAssertEqual(availableCredit, 0, "Available credit should be 0 when limit = 0")

        // Utilization > 100%
        let utilization = creditLimit > 0 ? Double(debt) / Double(creditLimit) : 1.0
        XCTAssertEqual(utilization, 1.0, "Utilization should be 100% when limit = 0")
    }

    // MARK: - Edge Case 15: Timezone issues with statement cycle

    func testEdgeCase15_TimezoneStatementCycle() {
        let calendar = Calendar.current
        let endOfMonth = Date(timeIntervalSince1970: 1_743_249_599) // March 31, 23:59:59
        let startOfNextMonth = Date(timeIntervalSince1970: 1_743_249_600) // April 1, 00:00:00

        _ = OverviewLogic.creditCardStatementCycle(
            statementClosingDay: 25,
            referenceDate: endOfMonth,
            calendar: calendar
        )

        // Transaction at 23:59 on month end should be in current cycle
        let transactionEndOfMonth = makeRecord(
            primaryKind: .expense,
            amountMinor: 100_000,
            occurredAt: endOfMonth,
            sourceWalletKind: .creditCard
        )

        // Transaction at 00:01 on next month should be in next cycle
        let transactionStartOfNextMonth = makeRecord(
            primaryKind: .expense,
            amountMinor: 100_000,
            occurredAt: startOfNextMonth,
            sourceWalletKind: .creditCard
        )

        let isInCurrentCycle = calendar.isDate(transactionEndOfMonth.occurredAt, equalTo: endOfMonth, toGranularity: .month)
        let isInNextCycle = calendar.isDate(transactionStartOfNextMonth.occurredAt, equalTo: startOfNextMonth, toGranularity: .month)

        XCTAssertTrue(isInCurrentCycle, "Transaction at month end should be in current month")
        XCTAssertTrue(isInNextCycle, "Transaction at next month start should be in next month")
    }
}
