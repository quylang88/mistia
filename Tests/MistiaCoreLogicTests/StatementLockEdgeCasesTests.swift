import XCTest
@testable import MistiaCoreLogic

final class StatementLockEdgeCasesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

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

    // MARK: - Statement Lock Edge Cases

    func testStatementLockWithExactMatchingTitleVietnamese() {
        let creditCardID = UUID()
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
            title: "thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch phải bị khóa với tiêu đề tiếng Việt khớp chính xác"
        )
    }

    func testStatementLockWithExactMatchingTitleEnglish() {
        let creditCardID = UUID()
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
            title: "card payment march 2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch phải bị khóa với tiêu đề tiếng Anh khớp chính xác"
        )
    }

    func testStatementLockWithExactMatchingTitleJapanese() {
        let creditCardID = UUID()
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
            title: "カード支払い 2025年3月",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch phải bị khóa với tiêu đề tiếng Nhật khớp chính xác"
        )
    }

    func testStatementLockWithPartialMatchingTitle() {
        let creditCardID = UUID()
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
            title: "thanh toán thẻ", // Partial match
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch phải bị khóa với tiêu đề khớp một phần"
        )
    }

    func testStatementLockCaseInsensitive() {
        let creditCardID = UUID()
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
            title: "THANH TOÁN THẺ THÁNG 3/2025", // Uppercase
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch phải bị khóa với tiêu đề không phân biệt hoa thường"
        )
    }

    func testStatementLockWithDifferentAmounts() {
        let creditCardID = UUID()
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
            title: "thanh toán thẻ tháng 3/2025",
            amountMinor: 300_000, // Different amount
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch vẫn bị khóa ngay cả khi số tiền thanh toán khác nhau"
        )
    }

    func testStatementLockWithMultipleExpensesSameMonth() {
        let creditCardID = UUID()
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

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx1, expenseTx2, paymentTx]

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx1,
                allTransactions: allTransactions
            ),
            "Cả hai giao dịch chi tiêu đều bị khóa khi có thanh toán cho tháng đó"
        )

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx2,
                allTransactions: allTransactions
            ),
            "Cả hai giao dịch chi tiêu đều bị khóa khi có thanh toán cho tháng đó"
        )
    }

    func testStatementLockTransferToNonCreditCard() {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: walletID,
            destinationWalletKind: .cash // Not credit card
        )

        let allTransactions = [expenseTx, paymentTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch không bị khóa khi chuyển tiền đến ví không phải thẻ tín dụng"
        )
    }

    func testStatementLockExpenseFromNonCreditCard() {
        let walletID = UUID()
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash // Not credit card
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ tháng 3/2025",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
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
            "Giao dịch không bị khóa khi chi tiêu từ ví không phải thẻ tín dụng"
        )
    }

    func testStatementLockWithDeletedPaymentTransaction() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // Simulate deleted payment transaction (not included in allTransactions)
        let allTransactions = [expenseTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch không bị khóa khi thanh toán đã bị xóa"
        )
    }

    func testStatementLockWithDraftPaymentTransaction() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let draftPaymentTx = TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            debtIntent: nil,
            entryStatus: .draft,
            title: "thanh toán thẻ tháng 3/2025",
            note: nil,
            amountMinor: 500_000,
            isArchived: false,
            occurredAt: referenceDate.addingTimeInterval(86400),
            createdAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard,
            categoryID: nil,
            categoryParentID: nil,
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )

        let allTransactions = [expenseTx, draftPaymentTx]

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch không bị khóa khi thanh toán ở trạng thái draft"
        )
    }

    func testStatementLockWithMultiplePaymentsSameMonth() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let paymentTx1 = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ lần 1",
            amountMinor: 300_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let paymentTx2 = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ lần 2",
            amountMinor: 200_000,
            occurredAt: referenceDate.addingTimeInterval(172800),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx1, paymentTx2]

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch bị khóa khi có nhiều thanh toán trong cùng tháng"
        )
    }

    func testStatementLockWithPaymentInDifferentYear() {
        let creditCardID = UUID()
        let march2025 = Date(timeIntervalSince1970: 1_742_646_400) // March 2025
        let march2026 = Date(timeIntervalSince1970: 1_774_182_400) // March 2026

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: march2025,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ tháng 3/2026",
            amountMinor: 500_000,
            occurredAt: march2026,
            sourceWalletID: UUID(),
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
            "Giao dịch không bị khóa khi thanh toán ở năm khác"
        )
    }
}