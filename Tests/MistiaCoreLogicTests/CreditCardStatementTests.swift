import XCTest
@testable import MistiaCoreLogic

final class CreditCardStatementTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese, defaults: UserDefaults.standard)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

    // MARK: - Helper

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

    // MARK: - Test: Giao dịch bị khóa khi sao kê đã thanh toán

    func testExpenseTransactionIsLockedWhenStatementIsPaid() {
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

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch chi tiêu từ thẻ tín dụng phải bị khóa khi đã có thanh toán sao kê cùng tháng"
        )
    }

    func testInternalTransferToCardIsLockedWhenStatementIsPaid() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let transferTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Chuyển tiền vào thẻ",
            amountMinor: 1_000_000,
            occurredAt: referenceDate,
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
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

        let allTransactions = [transferTx, paymentTx]

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: transferTx,
                allTransactions: allTransactions
            ),
            "Giao dịch chuyển tiền nội bộ vào thẻ tín dụng phải bị khóa khi đã có thanh toán sao kê cùng tháng"
        )
    }

    func testTransactionFromDifferentMonthIsNotLocked() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)
        let nextMonthDate = Calendar.current.date(byAdding: .month, value: 1, to: referenceDate)!

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
            title: "Thanh toán thẻ tháng sau",
            amountMinor: 500_000,
            occurredAt: nextMonthDate,
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch tháng khác không được bị khóa bởi thanh toán sao kê tháng khác"
        )
    }

    func testTransactionIsNotLockedWithoutPayment() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: [expenseTx]
            ),
            "Giao dịch không được khóa khi chưa có thanh toán sao kê"
        )
    }

    func testIncomeTransactionIsNotLockedByStatement() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let incomeTx = makeRecord(
            primaryKind: .income,
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
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [incomeTx, paymentTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: incomeTx,
                allTransactions: allTransactions
            ),
            "Giao dịch thu nhập không được khóa bởi sao kê đã thanh toán"
        )
    }

    func testNonCreditCardExpenseIsNotLocked() {
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: UUID(),
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch chi tiêu từ ví thường không được khóa bởi thanh toán thẻ tín dụng"
        )
    }

    // MARK: - Test: Payment title variations

    func testPaymentDetectionWithVietnameseTitle() {
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
            title: "THANH TOÁN THẺ - Tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: [expenseTx, paymentTx]
            ),
            "Phải phát hiện thanh toán với tiêu đề tiếng Việt (case-insensitive)"
        )
    }

    func testPaymentDetectionWithEnglishTitle() {
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
            title: "CARD PAYMENT for March 2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: [expenseTx, paymentTx]
            ),
            "Phải phát hiện thanh toán với tiêu đề tiếng Anh (case-insensitive)"
        )
    }

    func testPaymentDetectionWithJapaneseTitle() {
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
            title: "カード支払い 2025 年 3 月分",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: [expenseTx, paymentTx]
            ),
            "Phải phát hiện thanh toán với tiêu đề tiếng Nhật"
        )
    }

    // MARK: - Test: Transfer subtype validation

    func testNonInternalTransferDoesNotLockTransactions() {
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

        let debtTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay tiền",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: [expenseTx, debtTx]
            ),
            "Giao dịch debt không được coi là thanh toán sao kê"
        )
    }

    // MARK: - Test: Undo payment flow

    func testTransactionsUnlockedAfterUndoPayment() {
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

        let allTransactionsWithPayment = [expenseTx, paymentTx]

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactionsWithPayment
            ),
            "Giao dịch phải bị khóa khi có thanh toán"
        )

        // Khi undo payment, transaction bị xóa (deletedAt set) và không còn trong danh sách
        let allTransactionsAfterUndo = [expenseTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactionsAfterUndo
            ),
            "Giao dịch phải được mở khóa sau khi hoàn tác (xóa) thanh toán"
        )
    }

    func testMultipleExpensesLockedBySamePayment() {
        let creditCardID = UUID()
        let cashWalletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expense1 = makeRecord(
            primaryKind: .expense,
            amountMinor: 100_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let expense2 = makeRecord(
            primaryKind: .expense,
            amountMinor: 200_000,
            occurredAt: referenceDate.addingTimeInterval(3600),
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let expense3 = makeRecord(
            primaryKind: .expense,
            amountMinor: 200_000,
            occurredAt: referenceDate.addingTimeInterval(7200),
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

        let allTransactions = [expense1, expense2, expense3, paymentTx]

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(transaction: expense1, allTransactions: allTransactions),
            "Chi tiêu thứ 1 phải bị khóa"
        )
        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(transaction: expense2, allTransactions: allTransactions),
            "Chi tiêu thứ 2 phải bị khóa"
        )
        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(transaction: expense3, allTransactions: allTransactions),
            "Chi tiêu thứ 3 phải bị khóa"
        )
    }
}
