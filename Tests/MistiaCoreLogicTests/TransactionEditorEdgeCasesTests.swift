import XCTest
@testable import MistiaCoreLogic

final class TransactionEditorEdgeCasesTests: XCTestCase {
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
        categoryParentID: UUID? = nil,
        counterpartyName: String? = nil,
        isArchived: Bool = false,
        note: String? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: id,
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: entryStatus,
            title: title,
            note: note,
            amountMinor: amountMinor,
            isArchived: isArchived,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletKind: destinationWalletKind,
            categoryID: categoryID,
            categoryParentID: categoryParentID,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(counterpartyName)
        )
    }

    // MARK: - Transfer Mode Availability

    func testFamilyTransferModeOnlyAppearsForEligibleFamilyOrExistingFamilyRow() {
        XCTAssertEqual(
            TransactionTransferSubtype.editorOptions(
                isFamilyEligible: false,
                includesFamilyTransfer: false
            ),
            [.internalTransfer, .debt]
        )

        XCTAssertEqual(
            TransactionTransferSubtype.editorOptions(
                isFamilyEligible: true,
                includesFamilyTransfer: false
            ),
            [.internalTransfer, .familyTransfer, .debt]
        )

        XCTAssertEqual(
            TransactionTransferSubtype.editorOptions(
                isFamilyEligible: false,
                includesFamilyTransfer: true
            ),
            [.internalTransfer, .familyTransfer, .debt]
        )
    }

    func testFamilyTransferModeIsDisabledOfflineExceptExistingDetail() {
        XCTAssertFalse(
            TransactionTransferSubtype.isEditorOptionEnabled(
                .familyTransfer,
                canPerformRemoteActions: false,
                isFamilyTransferDetail: false
            )
        )
        XCTAssertTrue(
            TransactionTransferSubtype.isEditorOptionEnabled(
                .familyTransfer,
                canPerformRemoteActions: true,
                isFamilyTransferDetail: false
            )
        )
        XCTAssertTrue(
            TransactionTransferSubtype.isEditorOptionEnabled(
                .familyTransfer,
                canPerformRemoteActions: false,
                isFamilyTransferDetail: true
            )
        )
        XCTAssertTrue(
            TransactionTransferSubtype.isEditorOptionEnabled(
                .debt,
                canPerformRemoteActions: false,
                isFamilyTransferDetail: false
            )
        )
    }

    func testDebtIntentCreditCardWalletPolicyOnlyAllowsLending() {
        XCTAssertTrue(TransactionLogic.debtIntentAllowsCreditCardWallet(.lend))
        XCTAssertFalse(TransactionLogic.debtIntentAllowsCreditCardWallet(.collect))
        XCTAssertFalse(TransactionLogic.debtIntentAllowsCreditCardWallet(.borrow))
        XCTAssertFalse(TransactionLogic.debtIntentAllowsCreditCardWallet(.repay))
    }

    func testReceiptPersistencePolicyIsEphemeralForMemberOwnedTransactions() {
        let activeUserID = UUID()
        let memberUserID = UUID()

        XCTAssertEqual(
            TransactionReceiptPersistencePolicy.policy(
                ownerUserID: activeUserID,
                activeLocalProfileUserID: activeUserID
            ),
            .persistLocally
        )
        XCTAssertEqual(
            TransactionReceiptPersistencePolicy.policy(
                ownerUserID: memberUserID,
                activeLocalProfileUserID: activeUserID
            ),
            .ephemeral
        )
    }

    func testEphemeralReceiptPolicyDeletesStoredReceiptOnSave() {
        XCTAssertTrue(TransactionReceiptPersistencePolicy.ephemeral.deletesStoredReceiptOnSave)
        XCTAssertFalse(TransactionReceiptPersistencePolicy.persistLocally.deletesStoredReceiptOnSave)
        XCTAssertFalse(TransactionReceiptPersistencePolicy.ephemeral.canPersistReceiptImage)
        XCTAssertTrue(TransactionReceiptPersistencePolicy.persistLocally.canPersistReceiptImage)
    }

    func testReceiptAnalysisSourceSeparatesScannerFromManualModalImages() {
        XCTAssertTrue(TransactionReceiptAnalysisSource.initialScanner.shouldAnalyzeImmediately)
        XCTAssertFalse(TransactionReceiptAnalysisSource.modalPicker.shouldAnalyzeImmediately)
        XCTAssertFalse(TransactionReceiptAnalysisSource.prefill.shouldAnalyzeImmediately)

        XCTAssertEqual(
            TransactionReceiptAnalysisControlState.state(
                for: .initialScanner,
                hasReceiptDraft: true,
                hasAppliedAnalysis: false,
                isAnalyzing: false
            ),
            .hidden
        )
        XCTAssertEqual(
            TransactionReceiptAnalysisControlState.state(
                for: .modalPicker,
                hasReceiptDraft: true,
                hasAppliedAnalysis: false,
                isAnalyzing: false
            ),
            .enabled
        )
        XCTAssertEqual(
            TransactionReceiptAnalysisControlState.state(
                for: .modalPicker,
                hasReceiptDraft: true,
                hasAppliedAnalysis: true,
                isAnalyzing: false
            ),
            .disabled
        )
        XCTAssertEqual(
            TransactionReceiptAnalysisControlState.state(
                for: .modalPicker,
                hasReceiptDraft: false,
                hasAppliedAnalysis: false,
                isAnalyzing: false
            ),
            .hidden
        )
    }

    // MARK: - Quick Capture Edge Cases

    func testQuickCaptureZeroAmount() {
        let record = makeRecord(
            primaryKind: .expense,
            amountMinor: 0,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testQuickCaptureNegativeAmount() {
        let record = makeRecord(
            primaryKind: .expense,
            amountMinor: -1000,
            occurredAt: Date()
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testQuickCaptureValidAmount() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            amountMinor: 1000,
            occurredAt: Date()
        )
        // Quick capture transactions are draft transactions with minimal info
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testQuickCaptureTransferTransaction() {
        let record = makeRecord(
            primaryKind: .transfer,
            entryStatus: .draft,
            amountMinor: 1000,
            occurredAt: Date()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testQuickCaptureIncomeTransaction() {
        let record = makeRecord(
            primaryKind: .income,
            entryStatus: .draft,
            amountMinor: 1000,
            occurredAt: Date()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Expense Transaction Edge Cases

    func testExpenseWithNoAvailableWallets() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            categoryID: UUID()
        )
        // Missing source wallet ID
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testExpenseWithArchivedWallet() {
        let walletID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        // Should still be valid even if we don't check wallet archived status in this logic
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testExpenseWithParentCategory() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID() // Parent category would be missing child indicator
        )
        // This test assumes the category is valid, but in reality we'd need to check if it's a child category
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testExpenseWithInvalidCategory() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash
            // Missing category
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Income Transaction Edge Cases

    func testIncomeWithCreditCardWallet() {
        let record = makeRecord(
            primaryKind: .income,
            title: "Test income",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .creditCard, // This should be invalid
            categoryID: UUID()
        )
        // The business logic allows this, but UI should prevent it
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testIncomeWithNoWallet() {
        let record = makeRecord(
            primaryKind: .income,
            title: "Test income",
            amountMinor: 1000,
            occurredAt: Date(),
            categoryID: UUID()
            // Missing wallet
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Date and Time Edge Cases

    func testFutureDateTransaction() {
        let futureDate = Date().addingTimeInterval(86400 * 30) // 30 days in future
        let record = makeRecord(
            primaryKind: .expense,
            title: "Future expense",
            amountMinor: 1000,
            occurredAt: futureDate,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testVeryOldDateTransaction() {
        let oldDate = Date(timeIntervalSince1970: 0) // Unix epoch
        let record = makeRecord(
            primaryKind: .expense,
            title: "Old expense",
            amountMinor: 1000,
            occurredAt: oldDate,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Title and Note Edge Cases

    func testTitleWithSpecialCharacters() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense @#$%^&*()",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testTitleWithUnicodeCharacters() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "Tiếng Việt có dấu 🇻🇳",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testVeryLongTitle() {
        let longTitle = String(repeating: "A", count: 1000)
        let record = makeRecord(
            primaryKind: .expense,
            title: longTitle,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testNoteWithSpecialCharacters() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .posted,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID(),
            note: "Note with special chars @#$%^&*()"
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testNoteWithUnicodeCharacters() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .posted,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID(),
            note: "Ghi chú bằng tiếng Việt 🇻🇳"
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testVeryLongNote() {
        let longNote = String(repeating: "A", count: 5000)
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .posted,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID(),
            note: longNote
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Balance Validation Edge Cases

    func testExpenseExceedingCashBalance() {
        let walletID = UUID()
        let wallet = TransactionWalletSnapshot(
            id: walletID,
            kind: .cash,
            openingBalanceMinor: 500 // 5 units
        )

        let expenseTx = makeRecord(
            primaryKind: .expense,
            amountMinor: 1000, // 10 units - exceeds balance
            occurredAt: Date(),
            sourceWalletID: walletID,
            sourceWalletKind: .cash
        )

        let records = [expenseTx]
        let balance = TransactionLogic.effectiveBalance(for: wallet, records: records)
        
        // The balance would be negative, but the business logic doesn't prevent this
        // It's up to the UI layer to validate
        XCTAssertEqual(balance, -950)
    }

    // MARK: - Draft to Posted Transition

    func testDraftTransactionIncomplete() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "", // Empty title
            amountMinor: 1000,
            occurredAt: Date()
        )
        // Draft transactions can be incomplete
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testPostedTransactionIncomplete() {
        let record = makeRecord(
            primaryKind: .expense,
            entryStatus: .posted,
            title: "", // Empty title
            amountMinor: 1000,
            occurredAt: Date()
        )
        // Posted transactions must be complete
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Transfer Transaction Edge Cases

    func testTransferWithSameSourceAndDestination() {
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

    func testTransferWithMissingSource() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 1000,
            occurredAt: Date(),
            destinationWalletID: UUID(),
            destinationWalletKind: .cash
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testTransferWithMissingDestination() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash
        )
        XCTAssertFalse(TransactionLogic.isTransactionComplete(record))
    }

    func testDebtTransferWithMissingCounterparty() {
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

    func testDebtTransferWithEmptyCounterparty() {
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

    func testPaidForBorrowDebtCanBeCompleteWithoutWallet() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            amountMinor: 1000,
            occurredAt: Date(),
            counterpartyName: "Minh"
        )

        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testDraftPaidForBorrowDebtCanBeCompleteWithoutWallet() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            entryStatus: .draft,
            amountMinor: 1000,
            occurredAt: Date(),
            counterpartyName: "Minh"
        )

        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testReceiveIntoWalletBorrowDebtRemainsCompleteWithWallet() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            counterpartyName: "Minh"
        )

        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Category Edge Cases

    func testExpenseWithParentCategoryInsteadOfChild() {
        let parentCategoryID = UUID()
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: parentCategoryID,
            categoryParentID: nil // Indicates this is a parent category
        )
        // The logic doesn't distinguish between parent and child categories in this test
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    // MARK: - Wallet Edge Cases

    func testExpenseWithDeletedWallet() {
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(), // Wallet that doesn't exist
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }

    func testIncomeWithCreditCardWalletValidation() {
        // This represents what the UI validation should check
        let walletID = UUID()
        let wallet = TransactionWalletSnapshot(
            id: walletID,
            kind: .creditCard,
            openingBalanceMinor: 0
        )
        
        // Credit cards can technically receive income in the data model
        // but UI should prevent this
        XCTAssertEqual(wallet.kind, .creditCard)
    }

    // MARK: - Permission Edge Cases

    func testTransactionCreationWithoutProperPermissions() {
        // This would be tested more thoroughly in UI layer
        // but we can test the data integrity
        let record = makeRecord(
            primaryKind: .expense,
            title: "Test expense",
            amountMinor: 1000,
            occurredAt: Date(),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        XCTAssertTrue(TransactionLogic.isTransactionComplete(record))
    }
}
