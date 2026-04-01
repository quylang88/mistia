import XCTest
@testable import MistiaCoreLogic

final class TransactionLogicTests: XCTestCase {
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
        XCTAssertEqual(positions[0].netMinor, 4_000)
        XCTAssertTrue(positions[0].isReceivable)
        XCTAssertEqual(positions[1].displayName, "Minh")
        XCTAssertEqual(positions[1].netMinor, -2_500)
        XCTAssertFalse(positions[1].isReceivable)
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

    private func makeRecord(
        primaryKind: TransactionPrimaryKind,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        entryStatus: TransactionEntryStatus = .posted,
        title: String = "Sample",
        amountMinor: Int64,
        occurredAt: Date,
        sourceWalletID: UUID? = nil,
        sourceWalletKind: LedgerAccountKind? = nil,
        destinationWalletID: UUID? = nil,
        destinationWalletKind: LedgerAccountKind? = nil,
        categoryID: UUID? = nil,
        counterpartyName: String? = nil
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
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
}
