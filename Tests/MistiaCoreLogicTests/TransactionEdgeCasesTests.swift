import XCTest
@testable import MistiaCoreLogic

final class TransactionEdgeCasesTests: XCTestCase {
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
        counterpartyName: String? = nil,
        isArchived: Bool = false
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
            isArchived: isArchived,
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

    // MARK: - Validation Edge Cases

    func testZeroAmountTransaction() {
        let record = makeRecord(
            primaryKind: .expense,
            amountMinor: 0,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testNegativeAmountTransaction() {
        let record = makeRecord(
            primaryKind: .expense,
            amountMinor: -1000,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testEmptyTitleForExpense() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "",
            amountMinor: 1000,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testWhitespaceTitleForExpense() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "   ",
            amountMinor: 1000,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testMissingCategoryForExpense() {
        let record = makeRecord(
            primaryKind: .expense,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testMissingSourceWalletForExpense() {
        let record = makeRecord(
            primaryKind: .expense,
            amountMinor: 1000,
            occurredAt: Date(),
            categoryID: UUID()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testMissingSourceAndDestinationForInternalTransfer() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 1000,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testSameSourceAndDestinationForInternalTransfer() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            destinationWalletID: walletID,
            destinationWalletKind: .cash
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testMissingSourceWalletForDebtTransfer() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            amountMinor: 1000,
            occurredAt: Date(),
            counterpartyName: "Test"
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testMissingCounterpartyForDebtTransfer() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testEmptyCounterpartyForDebtTransfer() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            counterpartyName: ""
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testWhitespaceCounterpartyForDebtTransfer() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            counterpartyName: "   "
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testMissingDebtIntentForDebtTransfer() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            counterpartyName: "Test"
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Balance Calculation Edge Cases

    func testBalanceWithArchivedTransactions() {
        let walletID = UUID()
        let wallet = TransactionWalletSnapshot(
            id: walletID,
            kind: .cash,
            openingBalanceMinor: 1000
        )

        let postedTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 200,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash
        )

        let archivedTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 300,
            occurredAt: Date().addingTimeInterval(-86400),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            isArchived: true
        )

        let records = [postedTx, archivedTx]
        let balance = TransactionLogic.effectiveBalance(for: wallet, records: records)
        XCTAssertEqual(balance, 800) // Should not include archived transaction
    }

    func testCreditCardBalanceCalculation() {
        let creditCardID = UUID()
        let creditCard = TransactionWalletSnapshot(
            id: creditCardID,
            kind: .creditCard,
            openingBalanceMinor: 0
        )

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 5000,
            occurredAt: Date(),
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 2000,
            occurredAt: Date().addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let records = [expenseTx, paymentTx]
        let balance = TransactionLogic.effectiveBalance(for: creditCard, records: records)
        XCTAssertEqual(balance, 3000) // 5000 - 2000 = 3000 debt
    }

    // MARK: - Statement Lock Edge Cases

    func testStatementLockWithNonMatchingTitle() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        // Payment with non-matching title
        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Chuyển tiền thông thường",
            amountMinor: 500_000,
            occurredAt: referenceDate.addingTimeInterval(86400),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx]

        // Should not be locked because title doesn't match
        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch không bị khóa khi tiêu đề thanh toán không khớp"
        )
    }

    func testStatementLockWithIncomeTransaction() {
        let creditCardID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let incomeTx = makeRecord(
            primaryKind: .income,
            amountMinor: 500_000,
            occurredAt: referenceDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let allTransactions = [incomeTx]

        // Income transactions should not be lockable
        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: incomeTx,
                allTransactions: allTransactions
            ),
            "Giao dịch thu nhập không thể bị khóa"
        )
    }

    func testStatementLockWithDifferentMonth() {
        let creditCardID = UUID()
        let marchDate = Date(timeIntervalSince1970: 1_742_646_400) // March 2025
        let aprilDate = Date(timeIntervalSince1970: 1_745_324_800) // April 2025

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 500_000,
            occurredAt: marchDate,
            sourceWalletID: creditCardID,
            sourceWalletKind: .creditCard
        )

        let paymentTx = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "thanh toán thẻ tháng 4/2025",
            amountMinor: 500_000,
            occurredAt: aprilDate,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: creditCardID,
            destinationWalletKind: .creditCard
        )

        let allTransactions = [expenseTx, paymentTx]

        // Should not be locked because different months
        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: expenseTx,
                allTransactions: allTransactions
            ),
            "Giao dịch không bị khóa khi thanh toán ở tháng khác"
        )
    }

    // MARK: - Counterparty Normalization Edge Cases

    func testCounterpartyNormalizationWithSpecialCharacters() {
        let original = "Nguyễn Văn A (Công ty ABC)"
        let normalized = TransactionLogic.normalizeCounterpartyName(original)
        XCTAssertEqual(normalized, "nguyen van a cong ty abc")
    }

    func testCounterpartyNormalizationWithMultipleSpaces() {
        let original = "  Test    Multiple     Spaces  "
        let normalized = TransactionLogic.normalizeCounterpartyName(original)
        XCTAssertEqual(normalized, "test multiple spaces")
    }

    func testCounterpartyNormalizationWithEmptyString() {
        let normalized = TransactionLogic.normalizeCounterpartyName("")
        XCTAssertNil(normalized)
    }

    func testCounterpartyNormalizationWithOnlySpaces() {
        let normalized = TransactionLogic.normalizeCounterpartyName("   ")
        XCTAssertNil(normalized)
    }

    func testCounterpartyNormalizationWithNil() {
        let normalized = TransactionLogic.normalizeCounterpartyName(nil)
        XCTAssertNil(normalized)
    }

    // MARK: - Filter Edge Cases

    func testFilterWithEmptySearchText() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test transaction",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        var filters = TransactionFilterState()
        filters.searchText = ""

        let visible = TransactionLogic.visibleRecords(
            from: [record],
            selectedKind: .expense,
            filters: filters
        )

        XCTAssertEqual(visible.count, 1)
    }

    func testFilterWithOnlyWhitespaceSearchText() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test transaction",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        var filters = TransactionFilterState()
        filters.searchText = "   "

        let visible = TransactionLogic.visibleRecords(
            from: [record],
            selectedKind: .expense,
            filters: filters
        )

        XCTAssertEqual(visible.count, 1)
    }

    // MARK: - Quick Capture Edge Cases

    func testQuickCaptureDraftTransaction() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "",
            amountMinor: 1000,
            occurredAt: Date()
        )
        // Draft transactions (quick captures) can be minimally complete
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testQuickCaptureWithZeroAmount() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "",
            amountMinor: 0,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testQuickCaptureWithNegativeAmount() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "",
            amountMinor: -500,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Title Suggestions Edge Cases

    func testTitleSuggestionsWithEmptyQuery() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test transaction",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        let suggestions = TransactionLogic.titleSuggestions(
            from: [record],
            query: "",
            primaryKind: .expense
        )

        XCTAssertEqual(suggestions.count, 0)
    }

    func testTitleSuggestionsWithOnlyWhitespaceQuery() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test transaction",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        let suggestions = TransactionLogic.titleSuggestions(
            from: [record],
            query: "   ",
            primaryKind: .expense
        )

        XCTAssertEqual(suggestions.count, 0)
    }

    func testTitleSuggestionsWithEmptyStringQuery() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test transaction",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        let suggestions = TransactionLogic.titleSuggestions(
            from: [record],
            query: "",
            primaryKind: .expense
        )

        XCTAssertEqual(suggestions.count, 0)
    }
}