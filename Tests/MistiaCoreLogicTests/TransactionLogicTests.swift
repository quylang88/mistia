import XCTest
@testable import MistiaCoreLogic

final class TransactionLogicTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

    func testGeneratedTransactionTitlesUseRequestedLanguage() {
        XCTAssertEqual(
            TransactionGeneratedTitle.internalTransfer(language: .english),
            "Internal transfer"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.familyTransferSent(language: .vietnamese),
            "Chuyển tiền gia đình"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.familyTransferReceived(language: .english),
            "Family transfer received"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.balanceAdjustment(language: .japanese),
            "残高調整"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.debt(.collect, language: .japanese),
            "回収"
        )
    }

    func testStoredGeneratedTransactionTitlesLocalizeForCurrentLanguage() {
        XCTAssertEqual(
            TransactionGeneratedTitle.localizedDisplayTitle(
                rawTitle: "Thu nợ",
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .collect,
                categoryID: nil,
                language: .japanese
            ),
            "回収"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.localizedDisplayTitle(
                rawTitle: "Nhận tiền gia đình",
                primaryKind: .transfer,
                transferSubtype: .familyTransfer,
                debtIntent: nil,
                categoryID: nil,
                language: .english
            ),
            "Family transfer received"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.localizedDisplayTitle(
                rawTitle: "Điều chỉnh số dư",
                primaryKind: .expense,
                transferSubtype: nil,
                debtIntent: nil,
                categoryID: MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID,
                language: .english
            ),
            "Balance adjustment"
        )
        XCTAssertEqual(
            TransactionGeneratedTitle.localizedDisplayTitle(
                rawTitle: "Thu nợ khách A",
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .collect,
                categoryID: nil,
                language: .japanese
            ),
            "Thu nợ khách A"
        )
    }

    func testBalanceEngineHandlesAssetsAndCreditCardFlows() {
        let cash = TransactionWalletSnapshot(
            id: UUID(),
            kind: .cash,
            openingBalanceMinor: 10_000
        )
        let bank = TransactionWalletSnapshot(
            id: UUID(),
            kind: .bank,
            openingBalanceMinor: 20_000
        )
        let payPay = TransactionWalletSnapshot(
            id: UUID(),
            kind: .payPay,
            openingBalanceMinor: 1_000
        )
        let creditCard = TransactionWalletSnapshot(
            id: UUID(),
            kind: .creditCard,
            openingBalanceMinor: 10_000
        )
        let foodCategory = UUID()
        let now = Date(timeIntervalSince1970: 1_742_646_400)

        let records = [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 1_200,
                occurredAt: now,
                sourceWalletID: cash.id,
                sourceWalletKind: .cash,
                categoryID: foodCategory
            ),
            makeRecord(
                primaryKind: .income,
                amountMinor: 5_000,
                occurredAt: now.addingTimeInterval(-60),
                sourceWalletID: bank.id,
                sourceWalletKind: .bank,
                categoryID: UUID()
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .internalTransfer,
                amountMinor: 3_000,
                occurredAt: now.addingTimeInterval(-120),
                sourceWalletID: bank.id,
                sourceWalletKind: .bank,
                destinationWalletID: payPay.id,
                destinationWalletKind: .payPay
            ),
            makeRecord(
                primaryKind: .expense,
                amountMinor: 8_000,
                occurredAt: now.addingTimeInterval(-180),
                sourceWalletID: creditCard.id,
                sourceWalletKind: .creditCard,
                categoryID: foodCategory
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .internalTransfer,
                amountMinor: 7_000,
                occurredAt: now.addingTimeInterval(-240),
                sourceWalletID: bank.id,
                sourceWalletKind: .bank,
                destinationWalletID: creditCard.id,
                destinationWalletKind: .creditCard
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .internalTransfer,
                amountMinor: 2_000,
                occurredAt: now.addingTimeInterval(-300),
                sourceWalletID: creditCard.id,
                sourceWalletKind: .creditCard,
                destinationWalletID: cash.id,
                destinationWalletKind: .cash
            )
        ]

        XCTAssertEqual(TransactionLogic.effectiveBalance(for: cash, records: records), 10_800)
        XCTAssertEqual(TransactionLogic.effectiveBalance(for: bank, records: records), 15_000)
        XCTAssertEqual(TransactionLogic.effectiveBalance(for: payPay, records: records), 4_000)
        XCTAssertEqual(TransactionLogic.effectiveBalance(for: creditCard, records: records), 13_000)
    }

    func testWalletBalanceIndexMatchesEffectiveBalanceForMixedWallets() {
        let cash = TransactionWalletSnapshot(
            id: UUID(),
            kind: .cash,
            openingBalanceMinor: 10_000
        )
        let bank = TransactionWalletSnapshot(
            id: UUID(),
            kind: .bank,
            openingBalanceMinor: 20_000
        )
        let creditCard = TransactionWalletSnapshot(
            id: UUID(),
            kind: .creditCard,
            openingBalanceMinor: 0
        )
        let now = Date(timeIntervalSince1970: 1_742_646_400)
        let records = [
            makeRecord(
                primaryKind: .income,
                amountMinor: 7_000,
                occurredAt: now,
                sourceWalletID: bank.id,
                sourceWalletKind: bank.kind,
                categoryID: UUID()
            ),
            makeRecord(
                primaryKind: .expense,
                amountMinor: 1_500,
                occurredAt: now.addingTimeInterval(-60),
                sourceWalletID: cash.id,
                sourceWalletKind: cash.kind,
                categoryID: UUID()
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .internalTransfer,
                amountMinor: 2_000,
                occurredAt: now.addingTimeInterval(-120),
                sourceWalletID: bank.id,
                sourceWalletKind: bank.kind,
                destinationWalletID: creditCard.id,
                destinationWalletKind: creditCard.kind
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .lend,
                amountMinor: 500,
                occurredAt: now.addingTimeInterval(-180),
                sourceWalletID: cash.id,
                sourceWalletKind: cash.kind,
                counterpartyName: "Lan"
            ),
            makeRecord(
                primaryKind: .expense,
                entryStatus: .draft,
                amountMinor: 99_999,
                occurredAt: now.addingTimeInterval(-240),
                sourceWalletID: cash.id,
                sourceWalletKind: cash.kind,
                categoryID: UUID()
            )
        ]

        let wallets = [cash, bank, creditCard]
        let index = TransactionLogic.walletBalanceIndex(wallets: wallets, records: records)

        for wallet in wallets {
            XCTAssertEqual(
                index.balance(for: wallet),
                TransactionLogic.effectiveBalance(for: wallet, records: records)
            )
        }
    }

    func testWalletBalanceIndexUsesDestinationAmountForCrossCurrencyTransfer() {
        let source = TransactionWalletSnapshot(
            id: UUID(),
            kind: .bank,
            openingBalanceMinor: 100_000
        )
        let destination = TransactionWalletSnapshot(
            id: UUID(),
            kind: .cash,
            openingBalanceMinor: 1_000_000
        )
        let occurredAt = Date(timeIntervalSince1970: 1_774_051_200)

        let records = [
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .internalTransfer,
                amountMinor: 10_000,
                occurredAt: occurredAt,
                sourceWalletID: source.id,
                sourceWalletKind: .bank,
                sourceCurrencyCode: "JPY",
                destinationWalletID: destination.id,
                destinationWalletKind: .cash,
                destinationCurrencyCode: "VND",
                destinationAmountMinor: 1_650_000
            )
        ]

        let index = TransactionLogic.walletBalanceIndex(
            wallets: [source, destination],
            records: records
        )

        XCTAssertEqual(index.balance(for: source), 90_000)
        XCTAssertEqual(index.balance(for: destination), 2_650_000)
    }

    func testCrossCurrencyTransferManualDisplayUsesDestinationSnapshot() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 10_000_000,
            occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
            sourceCurrencyCode: "VND",
            destinationCurrencyCode: "JPY",
            destinationAmountMinor: 50_000,
            conversionModeRawValue: MistiaCurrencyConversionMode.manual.rawValue
        )

        let display = TransactionLogic.crossCurrencyTransferDestinationDisplay(for: record)

        XCTAssertEqual(display?.amountMinor, 50_000)
        XCTAssertEqual(display?.currencyCode, "JPY")
        XCTAssertEqual(display?.style, .exactDestination)
    }

    func testCrossCurrencyTransferAppRateDisplayUsesSavedSnapshot() {
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            amountMinor: 10_000_000,
            occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
            sourceCurrencyCode: "VND",
            destinationCurrencyCode: "JPY",
            destinationAmountMinor: 50_000,
            conversionModeRawValue: MistiaCurrencyConversionMode.appRate.rawValue,
            exchangeRateDecimalString: "0.005",
            exchangeRateProvider: "manual",
            exchangeRateDate: "2026-05-27"
        )

        let display = TransactionLogic.crossCurrencyTransferDestinationDisplay(for: record)

        XCTAssertEqual(display?.amountMinor, 50_000)
        XCTAssertEqual(display?.currencyCode, "JPY")
        XCTAssertEqual(display?.style, .approximateDestination)
    }

    func testFamilyTransfersAreNeutralButChangeOnlyTheDisplayedWalletBalance() {
        let senderWallet = TransactionWalletSnapshot(
            id: UUID(),
            kind: .bank,
            openingBalanceMinor: 20_000
        )
        let recipientWallet = TransactionWalletSnapshot(
            id: UUID(),
            kind: .cash,
            openingBalanceMinor: 5_000
        )
        let now = Date(timeIntervalSince1970: 1_742_646_400)
        let outgoing = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .familyTransfer,
            title: "Chuyen cho B",
            amountMinor: 3_000,
            occurredAt: now,
            sourceWalletID: senderWallet.id,
            sourceWalletKind: senderWallet.kind,
            destinationWalletID: recipientWallet.id,
            destinationWalletKind: recipientWallet.kind
        )
        let incoming = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .familyTransfer,
            title: "Nhan tu A",
            amountMinor: 3_000,
            occurredAt: now,
            sourceWalletID: recipientWallet.id,
            sourceWalletKind: recipientWallet.kind
        )

        XCTAssertTrue(TransactionLogic.isTransactionComplete(outgoing))
        XCTAssertTrue(TransactionLogic.isTransactionComplete(incoming))
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: outgoing), -3_000)
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: incoming), 3_000)

        let summary = TransactionLogic.summary(for: [outgoing, incoming])
        XCTAssertEqual(summary.expenseMinor, 0)
        XCTAssertEqual(summary.incomeMinor, 0)

        let index = TransactionLogic.walletBalanceIndex(
            wallets: [senderWallet, recipientWallet],
            records: [outgoing, incoming]
        )
        XCTAssertEqual(index.balance(for: senderWallet), 17_000)
        XCTAssertEqual(index.balance(for: recipientWallet), 8_000)
    }

    func testPaidForBorrowDebtDoesNotChangeWalletBalanceOrCashflow() {
        let wallet = TransactionWalletSnapshot(
            id: UUID(),
            kind: .bank,
            openingBalanceMinor: 20_000
        )
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            amountMinor: 4_000,
            occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
            sourceCurrencyCode: "JPY",
            counterpartyName: "Minh"
        )

        let index = TransactionLogic.walletBalanceIndex(wallets: [wallet], records: [record])

        XCTAssertTrue(TransactionLogic.isPaidForDebt(record))
        XCTAssertFalse(TransactionLogic.isPaidForExpenseDebt(record))
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: record), 0)
        XCTAssertEqual(index.balance(for: wallet), 20_000)
        XCTAssertEqual(TransactionLogic.effectiveBalance(for: wallet, records: [record]), 20_000)
    }

    func testPaidForBorrowDebtWithCategoryCountsAsExpenseSpending() {
        let categoryID = UUID()
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            amountMinor: 4_000,
            occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
            sourceCurrencyCode: "JPY",
            categoryID: categoryID,
            counterpartyName: "Minh"
        )

        let summary = TransactionLogic.summary(for: [record])

        XCTAssertTrue(TransactionLogic.isPaidForDebt(record))
        XCTAssertTrue(TransactionLogic.isPaidForExpenseDebt(record))
        XCTAssertEqual(summary.expenseMinor, 4_000)
        XCTAssertEqual(summary.incomeMinor, 0)
    }

    func testSharedExpenseDefaultCategoryUsesMostFrequentLinkedBillCategory() {
        let groupID = UUID()
        let grocery = UUID()
        let dining = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_774_051_200)

        let result = SettlementLogic.sharedExpenseDefaultCategoryID(from: [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 1_000,
                occurredAt: baseDate,
                settlementGroupID: groupID,
                settlementRole: .sharedExpensePaid,
                categoryID: grocery
            ),
            makeRecord(
                primaryKind: .expense,
                amountMinor: 2_000,
                occurredAt: baseDate.addingTimeInterval(60),
                settlementGroupID: groupID,
                settlementRole: .sharedExpensePaid,
                categoryID: dining
            ),
            makeRecord(
                primaryKind: .expense,
                amountMinor: 3_000,
                occurredAt: baseDate.addingTimeInterval(120),
                settlementGroupID: groupID,
                settlementRole: .sharedExpensePaid,
                categoryID: grocery
            )
        ])

        XCTAssertEqual(result, grocery)
    }

    func testSharedExpenseDefaultCategoryBreaksFrequencyTieByNewestBill() {
        let groupID = UUID()
        let grocery = UUID()
        let dining = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_774_051_200)

        let result = SettlementLogic.sharedExpenseDefaultCategoryID(from: [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 1_000,
                occurredAt: baseDate,
                settlementGroupID: groupID,
                settlementRole: .sharedExpensePaid,
                categoryID: grocery
            ),
            makeRecord(
                primaryKind: .expense,
                amountMinor: 2_000,
                occurredAt: baseDate.addingTimeInterval(60),
                settlementGroupID: groupID,
                settlementRole: .sharedExpensePaid,
                categoryID: dining
            )
        ])

        XCTAssertEqual(result, dining)
    }

    func testSharedExpenseDefaultCategoryIgnoresUncategorizedBills() {
        let groupID = UUID()
        let result = SettlementLogic.sharedExpenseDefaultCategoryID(from: [
            makeRecord(
                primaryKind: .expense,
                amountMinor: 1_000,
                occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
                settlementGroupID: groupID,
                settlementRole: .sharedExpensePaid,
                categoryID: nil
            )
        ])

        XCTAssertNil(result)
    }

    func testSharedExpensePrincipalReportingRequiresCategory() {
        let categoryID = UUID()

        XCTAssertEqual(
            SettlementLogic.sharedExpensePrincipalReportingOverride(
                settlementRole: .sharedExpensePayable,
                amountMinor: 4_000,
                categoryID: categoryID
            ),
            SettlementDebtReportingOverride(expenseMinor: 4_000, incomeMinor: 0)
        )
        XCTAssertEqual(
            SettlementLogic.sharedExpensePrincipalReportingOverride(
                settlementRole: .sharedExpenseReceivable,
                amountMinor: 1_500,
                categoryID: categoryID
            ),
            SettlementDebtReportingOverride(expenseMinor: -1_500, incomeMinor: 0)
        )
        XCTAssertEqual(
            SettlementLogic.sharedExpensePrincipalReportingOverride(
                settlementRole: .sharedExpensePayable,
                amountMinor: 4_000,
                categoryID: nil
            ),
            SettlementDebtReportingOverride(expenseMinor: 0, incomeMinor: 0)
        )
        XCTAssertEqual(
            SettlementLogic.sharedExpensePrincipalReportingOverride(
                settlementRole: .sharedExpenseReceivable,
                amountMinor: 1_500,
                categoryID: nil
            ),
            SettlementDebtReportingOverride(expenseMinor: 0, incomeMinor: 0)
        )
    }

    func testEventGeneratedExpenseReportingDraftTracksToggleCategoryAndDirtyState() {
        let originalCategoryID = UUID()
        let updatedCategoryID = UUID()

        var draft = EventGeneratedExpenseReportingDraft(
            originalCategoryID: originalCategoryID,
            countsAsExpense: true,
            categoryID: originalCategoryID
        )
        XCTAssertFalse(draft.hasChanges)
        XCTAssertFalse(draft.requiresCategorySelection)

        draft.setCountsAsExpense(false)
        XCTAssertFalse(draft.countsAsExpense)
        XCTAssertNil(draft.effectiveCategoryID)
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(
            draft.reportingOverride(settlementRole: .sharedExpensePayable, amountMinor: 4_000),
            SettlementDebtReportingOverride(expenseMinor: 0, incomeMinor: 0)
        )

        draft.setCountsAsExpense(true)
        XCTAssertEqual(draft.effectiveCategoryID, originalCategoryID)
        XCTAssertFalse(draft.hasChanges)

        draft.selectCategory(updatedCategoryID)
        XCTAssertTrue(draft.countsAsExpense)
        XCTAssertEqual(draft.effectiveCategoryID, updatedCategoryID)
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(
            draft.reportingOverride(settlementRole: .sharedExpensePayable, amountMinor: 4_000),
            SettlementDebtReportingOverride(expenseMinor: 4_000, incomeMinor: 0)
        )

        var uncategorizedDraft = EventGeneratedExpenseReportingDraft(
            originalCategoryID: nil,
            countsAsExpense: false,
            categoryID: nil
        )
        uncategorizedDraft.setCountsAsExpense(true)
        XCTAssertTrue(uncategorizedDraft.hasChanges)
        XCTAssertTrue(uncategorizedDraft.requiresCategorySelection)
        XCTAssertNil(uncategorizedDraft.effectiveCategoryID)
    }

    func testResaleReceivableUsesSalePriceForDebtAndPurchaseCostForWalletReporting() {
        let wallet = TransactionWalletSnapshot(
            id: UUID(),
            kind: .cash,
            openingBalanceMinor: 10_000
        )
        let record = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Bán chịu máy ảnh",
            amountMinor: 1_500,
            occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
            sourceWalletID: wallet.id,
            sourceWalletKind: wallet.kind,
            sourceCurrencyCode: "JPY",
            settlementRole: .resaleReceivable,
            reportingExpenseMinor: 1_000,
            reportingIncomeMinor: 0,
            categoryID: UUID(),
            counterpartyName: "Lan"
        )

        let summary = TransactionLogic.summary(for: [record])
        let position = TransactionLogic.openDebtPositions(from: [record]).first
        let index = TransactionLogic.walletBalanceIndex(wallets: [wallet], records: [record])

        XCTAssertTrue(TransactionLogic.isResaleReceivableDebtPrincipal(record))
        XCTAssertEqual(position?.netMinor, 1_500)
        XCTAssertEqual(summary.expenseMinor, 1_000)
        XCTAssertEqual(summary.incomeMinor, 0)
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: record), -1_000)
        XCTAssertEqual(index.balance(for: wallet), 9_000)
        XCTAssertEqual(TransactionLogic.effectiveBalance(for: wallet, records: [record]), 9_000)
    }

    func testDebtAggregationTracksBothDirectionsWithNormalizedNames() {
        let walletID = UUID()
        let now = Date(timeIntervalSince1970: 1_742_646_400)

        let records = [
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .lend,
                title: "Cho vay cafe",
                amountMinor: 5_000,
                occurredAt: now,
                sourceWalletID: walletID,
                sourceWalletKind: .cash,
                counterpartyName: "Lân"
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .collect,
                title: "Thu nợ",
                amountMinor: 1_000,
                occurredAt: now.addingTimeInterval(-60),
                sourceWalletID: walletID,
                sourceWalletKind: .cash,
                counterpartyName: " lan "
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .borrow,
                title: "Mượn tiền",
                amountMinor: 3_000,
                occurredAt: now.addingTimeInterval(-120),
                sourceWalletID: walletID,
                sourceWalletKind: .bank,
                counterpartyName: "Minh"
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .repay,
                title: "Trả nợ",
                amountMinor: 500,
                occurredAt: now.addingTimeInterval(-180),
                sourceWalletID: walletID,
                sourceWalletKind: .bank,
                counterpartyName: "minh"
            )
        ]

        let positions = TransactionLogic.openDebtPositions(from: records)

        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0].displayName, "Lân")
        XCTAssertEqual(positions[0].normalizedCounterpartyKey, "lan")
        XCTAssertEqual(positions[0].netMinor, 4_000)
        XCTAssertTrue(positions[0].isReceivable)
        XCTAssertEqual(
            positions[0].relatedRecords.map(\.title),
            ["Cho vay cafe", "Thu nợ"]
        )
        XCTAssertEqual(positions[1].displayName, "Minh")
        XCTAssertEqual(positions[1].normalizedCounterpartyKey, "minh")
        XCTAssertEqual(positions[1].netMinor, -2_500)
        XCTAssertFalse(positions[1].isReceivable)
        XCTAssertEqual(
            positions[1].relatedRecords.map(\.title),
            ["Mượn tiền", "Trả nợ"]
        )
    }

    func testPaidForBorrowDebtIsPayableAndRepaymentReducesSamePosition() {
        let walletID = UUID()
        let now = Date(timeIntervalSince1970: 1_774_051_200)
        let records = [
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .borrow,
                amountMinor: 4_000,
                occurredAt: now,
                sourceCurrencyCode: "JPY",
                counterpartyName: "Minh"
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .repay,
                amountMinor: 1_500,
                occurredAt: now.addingTimeInterval(60),
                sourceWalletID: walletID,
                sourceWalletKind: .bank,
                sourceCurrencyCode: "JPY",
                counterpartyName: "minh"
            )
        ]

        let position = TransactionLogic.openDebtPositions(from: records).first

        XCTAssertEqual(position?.displayName, "Minh")
        XCTAssertEqual(position?.netMinor, -2_500)
        XCTAssertEqual(position?.preferredWalletID, nil)
    }

    func testOverCollectingReceivableDebtClosesPositionWithoutCreatingPayableDebt() {
        let walletID = UUID()
        let now = Date(timeIntervalSince1970: 1_774_051_200)
        let records = [
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .lend,
                amountMinor: 5_000,
                occurredAt: now,
                sourceWalletID: walletID,
                sourceWalletKind: .cash,
                sourceCurrencyCode: "JPY",
                counterpartyName: "Lan"
            ),
            makeRecord(
                primaryKind: .transfer,
                transferSubtype: .debt,
                debtIntent: .collect,
                amountMinor: 7_000,
                occurredAt: now.addingTimeInterval(60),
                sourceWalletID: walletID,
                sourceWalletKind: .cash,
                sourceCurrencyCode: "JPY",
                counterpartyName: "Lan"
            )
        ]

        XCTAssertTrue(TransactionLogic.openDebtPositions(from: records).isEmpty)
    }

    func testDebtCollectionAndBorrowingDoNotCountAsIncomeEvenForLegacyIncomeRows() {
        let now = Date(timeIntervalSince1970: 1_774_051_200)
        let records = [
            makeRecord(
                primaryKind: .income,
                transferSubtype: .debt,
                debtIntent: .collect,
                amountMinor: 7_000,
                occurredAt: now,
                sourceWalletID: UUID(),
                sourceWalletKind: .cash,
                sourceCurrencyCode: "JPY",
                reportingIncomeMinor: 780,
                counterpartyName: "Lan"
            ),
            makeRecord(
                primaryKind: .income,
                transferSubtype: .debt,
                debtIntent: .borrow,
                amountMinor: 4_000,
                occurredAt: now.addingTimeInterval(60),
                sourceWalletID: UUID(),
                sourceWalletKind: .cash,
                sourceCurrencyCode: "JPY",
                counterpartyName: "Minh"
            ),
            makeRecord(
                primaryKind: .income,
                amountMinor: 9_000,
                occurredAt: now.addingTimeInterval(120),
                sourceWalletID: UUID(),
                sourceWalletKind: .cash,
                sourceCurrencyCode: "JPY",
                categoryID: UUID()
            )
        ]

        let summary = TransactionLogic.summary(for: records)

        XCTAssertEqual(records.map { TransactionLogic.reportedIncomeAmount(for: $0) }, [0, 0, 9_000])
        XCTAssertEqual(summary.incomeMinor, 9_000)
    }

    func testDraftDoesNotAffectSummaryBalanceAndDraftSectionComesFirst() {
        let wallet = TransactionWalletSnapshot(
            id: UUID(),
            kind: .cash,
            openingBalanceMinor: 1_000
        )
        let now = Date(timeIntervalSince1970: 1_742_646_400)

        let postedIncome = makeRecord(
            primaryKind: .income,
            amountMinor: 3_000,
            occurredAt: now,
            sourceWalletID: wallet.id,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let draftExpense = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            amountMinor: 900,
            occurredAt: now.addingTimeInterval(60),
            sourceWalletID: wallet.id,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        let records = [postedIncome, draftExpense]
        let summary = TransactionLogic.summary(for: records)
        let sections = TransactionLogic.sections(from: records, referenceDate: now)

        XCTAssertEqual(summary.expenseMinor, 0)
        XCTAssertEqual(summary.incomeMinor, 3_000)
        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.draftCount, 1)
        XCTAssertEqual(TransactionLogic.effectiveBalance(for: wallet, records: records), 4_000)
        XCTAssertEqual(sections.first?.title, "Cần hoàn thiện")
        XCTAssertTrue(sections.first?.isDraftSection == true)
        XCTAssertEqual(sections.first?.rows.count, 1)
    }

    func testSectionsCanReuseRecencySortedInputWithoutChangingOutput() {
        let walletID = UUID()
        let now = Date(timeIntervalSince1970: 1_742_646_400)

        let latestDraft = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "Draft latest",
            amountMinor: 700,
            occurredAt: now.addingTimeInterval(180),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let olderDraft = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "Draft older",
            amountMinor: 500,
            occurredAt: now.addingTimeInterval(60),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let todayExpense = makeRecord(
            primaryKind: .expense,
            title: "Today",
            amountMinor: 3_000,
            occurredAt: now,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let yesterdayExpense = makeRecord(
            primaryKind: .expense,
            title: "Yesterday",
            amountMinor: 2_000,
            occurredAt: now.addingTimeInterval(-86_400),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )

        let sortedRecords = TransactionLogic.visibleRecords(
            from: [todayExpense, olderDraft, yesterdayExpense, latestDraft],
            selectedKind: nil,
            filters: TransactionFilterState(),
            referenceDate: now
        )

        let baseline = TransactionLogic.sections(from: sortedRecords, referenceDate: now)
        let optimized = TransactionLogic.sections(
            from: sortedRecords,
            assumesSortedByRecency: true,
            referenceDate: now
        )

        XCTAssertEqual(optimized, baseline)
        XCTAssertEqual(optimized.first?.rows.map(\.id), [latestDraft.id, olderDraft.id])
    }

    func testNonSpendingExpenseLikePaymentsDoNotCountAsExpenseSpending() {
        let bankID = UUID()
        let cardID = UUID()
        let categoryID = UUID()
        let now = Date(timeIntervalSince1970: 1_742_646_400)

        let grocery = makeRecord(
            primaryKind: .expense,
            title: "Grocery",
            amountMinor: 4_000,
            occurredAt: now,
            sourceWalletID: bankID,
            sourceWalletKind: .bank,
            categoryID: categoryID
        )
        let adjustment = makeRecord(
            primaryKind: .expense,
            title: "Điều chỉnh số dư",
            amountMinor: 2_000,
            occurredAt: now.addingTimeInterval(30),
            sourceWalletID: bankID,
            sourceWalletKind: .bank,
            categoryID: MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID
        )
        let cardPayment = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Thanh toán thẻ Visa",
            amountMinor: 12_000,
            occurredAt: now.addingTimeInterval(60),
            sourceWalletID: bankID,
            sourceWalletKind: .bank,
            destinationWalletID: cardID,
            destinationWalletKind: .creditCard
        )
        let legacyExpensePayment = makeRecord(
            primaryKind: .expense,
            title: "Thanh toan the legacy",
            amountMinor: 8_000,
            occurredAt: now.addingTimeInterval(120),
            sourceWalletID: bankID,
            sourceWalletKind: .bank,
            categoryID: categoryID
        )
        let installmentPayment = makeRecord(
            primaryKind: .expense,
            title: "Laptop",
            amountMinor: 6_000,
            occurredAt: now.addingTimeInterval(180),
            sourceWalletID: bankID,
            sourceWalletKind: .bank,
            categoryID: MistiaSystemCategoryIdentity.canonicalID(for: .loanRepayment)
        )

        let summary = TransactionLogic.summary(for: [
            grocery,
            adjustment,
            cardPayment,
            legacyExpensePayment,
            installmentPayment
        ])

        XCTAssertTrue(TransactionLogic.isCreditCardPayment(cardPayment))
        XCTAssertTrue(TransactionLogic.isCreditCardPayment(legacyExpensePayment))
        XCTAssertTrue(TransactionLogic.isAdjustment(adjustment))
        XCTAssertTrue(TransactionLogic.isInstallmentPayment(installmentPayment))
        XCTAssertEqual(summary.expenseMinor, 4_000)
        XCTAssertEqual(summary.incomeMinor, 0)
    }

    func testExpenseFiltersCombineTypeTimeWalletCategoryAmountStatusAndSearch() {
        let walletID = UUID()
        let otherWalletID = UUID()
        let categoryID = UUID()
        let otherCategoryID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let matching = makeRecord(
            primaryKind: .expense,
            title: "Cafe voi Anh Minh",
            amountMinor: 5_500,
            occurredAt: referenceDate.addingTimeInterval(-60),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: categoryID
        )
        let wrongCategory = makeRecord(
            primaryKind: .expense,
            title: "Cafe sai danh muc",
            amountMinor: 5_500,
            occurredAt: referenceDate.addingTimeInterval(-120),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: otherCategoryID
        )
        let wrongStatus = makeRecord(
            primaryKind: .expense,
            entryStatus: .draft,
            title: "Cafe draft",
            amountMinor: 5_500,
            occurredAt: referenceDate.addingTimeInterval(-180),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: categoryID
        )
        let wrongWallet = makeRecord(
            primaryKind: .expense,
            title: "Cafe tai khoan khac",
            amountMinor: 5_500,
            occurredAt: referenceDate.addingTimeInterval(-240),
            sourceWalletID: otherWalletID,
            sourceWalletKind: .cash,
            categoryID: categoryID
        )

        var filters = TransactionFilterState()
        filters.timeScope = .thisMonth
        filters.walletID = walletID
        filters.categoryID = categoryID
        filters.statusScope = .postedOnly
        filters.minAmountMinor = 5_000
        filters.maxAmountMinor = 6_000
        filters.searchText = "anh minh"

        let visible = TransactionLogic.visibleRecords(
            from: [matching, wrongCategory, wrongStatus, wrongWallet],
            selectedKind: .expense,
            filters: filters,
            referenceDate: referenceDate
        )

        XCTAssertEqual(visible.map(\.id), [matching.id])
    }

    func testVisibleRecordsIncludesBalanceAdjustmentsInAllTransactions() {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)
        let normalExpense = makeRecord(
            primaryKind: .expense,
            title: "Cafe",
            amountMinor: 1_000,
            occurredAt: referenceDate.addingTimeInterval(-120),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let adjustment = makeRecord(
            primaryKind: .expense,
            title: "Dieu chinh so du",
            amountMinor: 2_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID
        )

        var filters = TransactionFilterState()
        filters.timeScope = .allTime

        let visible = TransactionLogic.visibleRecords(
            from: [normalExpense, adjustment],
            selectedKind: nil,
            filters: filters,
            referenceDate: referenceDate
        )

        XCTAssertEqual(visible.map(\.id), [adjustment.id, normalExpense.id])
    }

    func testVisibleRecordsKeepsBalanceAdjustmentsInTheirOwnSegment() {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)
        let normalExpense = makeRecord(
            primaryKind: .expense,
            title: "Cafe",
            amountMinor: 1_000,
            occurredAt: referenceDate.addingTimeInterval(-120),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let adjustment = makeRecord(
            primaryKind: .expense,
            title: "Dieu chinh so du",
            amountMinor: 2_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: MistiaSystemCategoryIdentity.balanceAdjustmentExpenseID
        )

        var expenseFilters = TransactionFilterState()
        expenseFilters.timeScope = .allTime
        let expenseVisible = TransactionLogic.visibleRecords(
            from: [normalExpense, adjustment],
            selectedKind: .expense,
            filters: expenseFilters,
            referenceDate: referenceDate
        )

        var adjustmentFilters = TransactionFilterState()
        adjustmentFilters.timeScope = .allTime
        adjustmentFilters.isAdjustmentOnly = true
        let adjustmentVisible = TransactionLogic.visibleRecords(
            from: [normalExpense, adjustment],
            selectedKind: nil,
            filters: adjustmentFilters,
            referenceDate: referenceDate
        )

        XCTAssertEqual(expenseVisible.map(\.id), [normalExpense.id])
        XCTAssertEqual(adjustmentVisible.map(\.id), [adjustment.id])
    }

    func testTransferFiltersCombineSubtypeAmountTimeStatusAndSearch() {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let matching = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay gap",
            amountMinor: 6_000,
            occurredAt: referenceDate.addingTimeInterval(-60),
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            counterpartyName: "Ngoc Anh"
        )
        let wrongSubtype = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Transfer noi bo",
            amountMinor: 6_000,
            occurredAt: referenceDate.addingTimeInterval(-120),
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            destinationWalletID: UUID(),
            destinationWalletKind: .cash
        )
        let wrongAmount = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay it hon",
            amountMinor: 3_000,
            occurredAt: referenceDate.addingTimeInterval(-180),
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            counterpartyName: "Ngoc Anh"
        )

        var filters = TransactionFilterState()
        filters.timeScope = .thisMonth
        filters.walletID = walletID
        filters.transferSubtype = .debt
        filters.statusScope = .postedOnly
        filters.minAmountMinor = 5_000
        filters.maxAmountMinor = 7_000
        filters.searchText = "anh"

        let visible = TransactionLogic.visibleRecords(
            from: [matching, wrongSubtype, wrongAmount],
            selectedKind: .transfer,
            filters: filters,
            referenceDate: referenceDate
        )

        XCTAssertEqual(visible.map(\.id), [matching.id])
    }

    func testCounterpartyDebtFilterOnlyIncludesPostedDebtForSelectedPerson() throws {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)
        let matching = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay Ngoc Anh",
            amountMinor: 6_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            counterpartyName: "Ngọc Anh"
        )
        let samePersonDraft = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            entryStatus: .draft,
            title: "Draft Ngoc Anh",
            amountMinor: 4_000,
            occurredAt: referenceDate.addingTimeInterval(-60),
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            counterpartyName: "Ngoc Anh"
        )
        let wrongPersonDebt = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay Minh",
            amountMinor: 6_000,
            occurredAt: referenceDate.addingTimeInterval(-120),
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            counterpartyName: "Minh"
        )
        let nonDebtWithSamePerson = makeRecord(
            primaryKind: .expense,
            title: "An toi voi Ngoc Anh",
            amountMinor: 6_000,
            occurredAt: referenceDate.addingTimeInterval(-180),
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            categoryID: UUID(),
            counterpartyName: "Ngoc Anh"
        )

        var filters = TransactionFilterState()
        filters.timeScope = .allTime
        filters.counterpartyDebtKey = try XCTUnwrap(TransactionLogic.normalizeCounterpartyName("ngọc anh"))

        let visible = TransactionLogic.visibleRecords(
            from: [matching, samePersonDraft, wrongPersonDebt, nonDebtWithSamePerson],
            selectedKind: nil,
            filters: filters,
            referenceDate: referenceDate
        )

        XCTAssertEqual(visible.map(\.id), [matching.id])
    }

    func testTransactionFilterStateMarksAnyVisibleListFilterActive() throws {
        XCTAssertFalse(TransactionFilterState(timeScope: .allTime, statusScope: .all).hasActiveVisibleListFilter)

        let timeFilter = TransactionFilterState(timeScope: .today, statusScope: .all)
        XCTAssertTrue(timeFilter.hasActiveVisibleListFilter)

        var walletFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        walletFilter.walletID = UUID()
        XCTAssertTrue(walletFilter.hasActiveVisibleListFilter)

        var categoryFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        categoryFilter.categoryID = UUID()
        XCTAssertTrue(categoryFilter.hasActiveVisibleListFilter)

        var transferFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        transferFilter.transferSubtype = .debt
        XCTAssertTrue(transferFilter.hasActiveVisibleListFilter)

        var personFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        personFilter.counterpartyDebtKey = try XCTUnwrap(TransactionLogic.normalizeCounterpartyName("Ngọc Anh"))
        XCTAssertTrue(personFilter.hasActiveVisibleListFilter)

        var amountFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        amountFilter.minAmountMinor = 5_000
        XCTAssertTrue(amountFilter.hasActiveVisibleListFilter)

        let statusFilter = TransactionFilterState(timeScope: .allTime, statusScope: .postedOnly)
        XCTAssertTrue(statusFilter.hasActiveVisibleListFilter)

        var adjustmentFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        adjustmentFilter.isAdjustmentOnly = true
        XCTAssertTrue(adjustmentFilter.hasActiveVisibleListFilter)

        var eventFilter = TransactionFilterState(timeScope: .allTime, statusScope: .all)
        eventFilter.isEventOnly = true
        XCTAssertTrue(eventFilter.hasActiveVisibleListFilter)
    }

    func testTitleSuggestionsPreferPrefixMatchesAndKeepNewestDuplicateTitle() {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)

        let olderDuplicate = makeRecord(
            primaryKind: .expense,
            title: "Cafe sua",
            amountMinor: 20_000,
            occurredAt: referenceDate.addingTimeInterval(-300),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let newestDuplicate = makeRecord(
            primaryKind: .expense,
            title: "Café sữa",
            amountMinor: 21_000,
            occurredAt: referenceDate.addingTimeInterval(-60),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let containsMatch = makeRecord(
            primaryKind: .expense,
            title: "Di cafe voi ban",
            amountMinor: 18_000,
            occurredAt: referenceDate.addingTimeInterval(-30),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            categoryID: UUID()
        )
        let wrongKind = makeRecord(
            primaryKind: .income,
            title: "Cafe freelance",
            amountMinor: 80_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .bank,
            categoryID: UUID()
        )

        let suggestions = TransactionLogic.titleSuggestions(
            from: [olderDuplicate, newestDuplicate, containsMatch, wrongKind],
            query: "cafe",
            primaryKind: .expense,
            limit: 5
        )

        XCTAssertEqual(
            suggestions.map(\.title),
            ["Café sữa", "Di cafe voi ban"]
        )
    }

    func testTitleSuggestionsRespectTransferSubtypeExclusionAndLimit() {
        let walletID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_742_646_400)
        let excludedID = UUID()

        let excluded = makeRecord(
            id: excludedID,
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay An",
            amountMinor: 50_000,
            occurredAt: referenceDate,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            counterpartyName: "An"
        )
        let second = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay Binh",
            amountMinor: 40_000,
            occurredAt: referenceDate.addingTimeInterval(-60),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            counterpartyName: "Binh"
        )
        let third = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay Cuong",
            amountMinor: 30_000,
            occurredAt: referenceDate.addingTimeInterval(-120),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            counterpartyName: "Cuong"
        )
        let fourth = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            title: "Cho vay Dung",
            amountMinor: 20_000,
            occurredAt: referenceDate.addingTimeInterval(-180),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            counterpartyName: "Dung"
        )
        let wrongSubtype = makeRecord(
            primaryKind: .transfer,
            transferSubtype: .internalTransfer,
            title: "Chuyen tien noi bo",
            amountMinor: 10_000,
            occurredAt: referenceDate.addingTimeInterval(-15),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            destinationWalletID: UUID(),
            destinationWalletKind: .bank
        )

        let suggestions = TransactionLogic.titleSuggestions(
            from: [excluded, second, third, fourth, wrongSubtype],
            query: "cho vay",
            primaryKind: .transfer,
            transferSubtype: .debt,
            excludingTransactionID: excludedID,
            limit: 2
        )

        XCTAssertEqual(
            suggestions.map(\.title),
            ["Cho vay Binh", "Cho vay Cuong"]
        )
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
        settlementGroupID: UUID? = nil,
        sourceWalletID: UUID? = nil,
        sourceWalletKind: LedgerWalletKind? = nil,
        sourceCurrencyCode: String? = nil,
        destinationWalletID: UUID? = nil,
        destinationWalletKind: LedgerWalletKind? = nil,
        destinationCurrencyCode: String? = nil,
        destinationAmountMinor: Int64? = nil,
        conversionModeRawValue: String? = nil,
        exchangeRateDecimalString: String? = nil,
        exchangeRateProvider: String? = nil,
        exchangeRateDate: String? = nil,
        settlementRole: SettlementTransactionRole? = nil,
        reportingExpenseMinor: Int64? = nil,
        reportingIncomeMinor: Int64? = nil,
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
            settlementGroupID: settlementGroupID,
            settlementRole: settlementRole,
            reportingExpenseMinor: reportingExpenseMinor,
            reportingIncomeMinor: reportingIncomeMinor,
            sourceCurrencyCode: sourceCurrencyCode,
            destinationCurrencyCode: destinationCurrencyCode,
            destinationAmountMinor: destinationAmountMinor,
            conversionModeRawValue: conversionModeRawValue,
            exchangeRateDecimalString: exchangeRateDecimalString,
            exchangeRateProvider: exchangeRateProvider,
            exchangeRateDate: exchangeRateDate,
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
}
