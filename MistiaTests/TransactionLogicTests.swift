import Foundation
import XCTest
@testable import Mistia

final class TransactionLogicTests: XCTestCase {
    func testOpenDebtPositionsAreGroupedByCounterpartyAndCurrency() {
        let personKey = TransactionLogic.normalizeCounterpartyName("An")!
        let lendWalletID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            debtRecord(
                amountMinor: 1_000,
                currencyCode: "JPY",
                intent: .lend,
                counterpartyName: "An",
                normalizedCounterpartyKey: personKey,
                sourceWalletID: lendWalletID,
                occurredAt: now
            ),
            debtRecord(
                amountMinor: 200,
                currencyCode: "JPY",
                intent: .collect,
                counterpartyName: "An",
                normalizedCounterpartyKey: personKey,
                occurredAt: now.addingTimeInterval(-60)
            ),
            debtRecord(
                amountMinor: 500_000,
                currencyCode: "VND",
                intent: .lend,
                counterpartyName: "An",
                normalizedCounterpartyKey: personKey,
                occurredAt: now.addingTimeInterval(-120)
            )
        ]

        let positions = TransactionLogic.openDebtPositions(from: records)

        XCTAssertEqual(positions.map(\.currencyCode).sorted(), ["JPY", "VND"])
        let jpyPosition = positions.first { $0.currencyCode == "JPY" }
        XCTAssertEqual(jpyPosition?.normalizedCounterpartyKey, personKey)
        XCTAssertEqual(jpyPosition?.netMinor, 800)
        XCTAssertEqual(jpyPosition?.preferredWalletID, lendWalletID)
        XCTAssertEqual(jpyPosition?.relatedRecords.map(\.debtIntent), [.lend, .collect])
        XCTAssertEqual(positions.first { $0.currencyCode == "VND" }?.netMinor, 500_000)
    }

    func testOpenDebtPositionsPreferBorrowWalletForRepayment() {
        let borrowWalletID = UUID()
        let otherWalletID = UUID()
        let records = [
            debtRecord(
                amountMinor: 1_000,
                intent: .borrow,
                sourceWalletID: borrowWalletID,
                occurredAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            debtRecord(
                amountMinor: 300,
                intent: .repay,
                sourceWalletID: otherWalletID,
                occurredAt: Date(timeIntervalSince1970: 1_799_999_940)
            )
        ]

        let position = TransactionLogic.openDebtPositions(from: records).first

        XCTAssertEqual(position?.netMinor, -700)
        XCTAssertEqual(position?.preferredWalletID, borrowWalletID)
        XCTAssertEqual(position?.relatedRecords.map(\.debtIntent), [.borrow, .repay])
    }

    func testCounterpartyDebtFilterOnlyIncludesPostedDebtForSelectedPerson() throws {
        let walletID = UUID()
        let key = try XCTUnwrap(TransactionLogic.normalizeCounterpartyName("Ngọc Anh"))
        let matching = debtRecord(
            amountMinor: 6_000,
            intent: .lend,
            counterpartyName: "Ngọc Anh",
            normalizedCounterpartyKey: key,
            sourceWalletID: walletID
        )
        let samePersonDraft = debtRecord(
            amountMinor: 4_000,
            intent: .lend,
            entryStatus: .draft,
            counterpartyName: "Ngoc Anh",
            normalizedCounterpartyKey: key,
            sourceWalletID: walletID
        )
        let wrongPersonDebt = debtRecord(
            amountMinor: 6_000,
            intent: .lend,
            counterpartyName: "Minh",
            normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName("Minh"),
            sourceWalletID: walletID
        )
        let nonDebtWithSamePerson = record(
            primaryKind: .expense,
            amountMinor: 6_000,
            currencyCode: "JPY",
            title: "An toi voi Ngoc Anh",
            counterpartyName: "Ngoc Anh",
            normalizedCounterpartyKey: key,
            sourceWalletID: walletID
        )

        var filters = TransactionFilterState()
        filters.timeScope = .allTime
        filters.counterpartyDebtKey = key

        let visible = TransactionLogic.visibleRecords(
            from: [matching, samePersonDraft, wrongPersonDebt, nonDebtWithSamePerson],
            selectedKind: nil,
            filters: filters,
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(visible.map(\.id), [matching.id])
    }

    func testOpenReceivableDebtTotalsOnlyIncludeCurrentLendingByCurrency() {
        let positions = [
            CounterpartyDebtSnapshot(
                id: "an-jpy",
                displayName: "An",
                netMinor: 1_200,
                currencyCode: "JPY",
                preferredWalletID: nil
            ),
            CounterpartyDebtSnapshot(
                id: "binh-jpy",
                displayName: "Binh",
                netMinor: -700,
                currencyCode: "JPY",
                preferredWalletID: nil
            ),
            CounterpartyDebtSnapshot(
                id: "chi-jpy",
                displayName: "Chi",
                netMinor: 300,
                currencyCode: "jpy",
                preferredWalletID: nil
            ),
            CounterpartyDebtSnapshot(
                id: "dung-vnd",
                displayName: "Dung",
                netMinor: 500_000,
                currencyCode: "VND",
                preferredWalletID: nil
            )
        ]

        XCTAssertEqual(
            TransactionLogic.openReceivableDebtTotalsByCurrency(from: positions),
            [
                PlanningCurrencyAmountTotalSnapshot(currencyCode: "JPY", amountMinor: 1_500),
                PlanningCurrencyAmountTotalSnapshot(currencyCode: "VND", amountMinor: 500_000)
            ]
        )
    }

    func testDebtTransfersDoNotCountAsIncomeOrExpenseSummary() {
        let records = [
            debtRecord(amountMinor: 1_000, currencyCode: "JPY", intent: .lend),
            debtRecord(amountMinor: 300, currencyCode: "JPY", intent: .collect),
            record(primaryKind: .expense, amountMinor: 700, currencyCode: "JPY"),
            record(primaryKind: .income, amountMinor: 900, currencyCode: "JPY")
        ]

        let summary = TransactionLogic.summary(for: records)

        XCTAssertEqual(summary.expenseMinor, 700)
        XCTAssertEqual(summary.incomeMinor, 900)
    }

    func testDebtCashflowSignsFollowIntent() {
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: debtRecord(amountMinor: 100, intent: .lend)), -100)
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: debtRecord(amountMinor: 100, intent: .collect)), 100)
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: debtRecord(amountMinor: 100, intent: .borrow)), 100)
        XCTAssertEqual(TransactionLogic.cashflowAmount(for: debtRecord(amountMinor: 100, intent: .repay)), -100)
    }

    func testDebtIntentCreditCardWalletPolicyOnlyAllowsLending() {
        XCTAssertTrue(TransactionLogic.debtIntentAllowsCreditCardWallet(.lend))
        XCTAssertFalse(TransactionLogic.debtIntentAllowsCreditCardWallet(.collect))
        XCTAssertFalse(TransactionLogic.debtIntentAllowsCreditCardWallet(.borrow))
        XCTAssertFalse(TransactionLogic.debtIntentAllowsCreditCardWallet(.repay))
    }

    func testCreditCardStatementKeepsDebtLendingChargeAfterCollectionToCashWallet() throws {
        let calendar = Calendar(identifier: .gregorian)
        let cardWalletID = UUID()
        let cashWalletID = UUID()
        let paymentWalletID = UUID()
        let statementMonth = try makeDate(year: 2026, month: 2, day: 1, calendar: calendar)
        let account = PlanningCreditCardAccountSnapshot(
            id: cardWalletID,
            walletID: cardWalletID,
            walletName: "SMBC Card",
            issuerName: "SMBC",
            network: .visa,
            last4: "1234",
            dueDay: 26,
            statementClosingDay: 10,
            paymentSourceWalletID: paymentWalletID,
            paymentSourceWalletName: "Main",
            currencyCode: "JPY",
            currentDebtMinor: 32_456,
            availableCreditMinor: 67_544,
            openedAt: try makeDate(year: 2026, month: 1, day: 1, calendar: calendar)
        )
        let records = [
            record(
                primaryKind: .transfer,
                amountMinor: 32_456,
                currencyCode: "JPY",
                transferSubtype: .debt,
                debtIntent: .lend,
                title: TransactionDebtIntent.lend.title,
                sourceWalletID: cardWalletID,
                sourceWalletKind: .creditCard,
                occurredAt: try makeDate(year: 2026, month: 2, day: 12, calendar: calendar)
            ),
            record(
                primaryKind: .transfer,
                amountMinor: 32_456,
                currencyCode: "JPY",
                transferSubtype: .debt,
                debtIntent: .collect,
                title: TransactionDebtIntent.collect.title,
                sourceWalletID: cashWalletID,
                sourceWalletKind: .cash,
                occurredAt: try makeDate(year: 2026, month: 2, day: 20, calendar: calendar)
            )
        ]

        let statements = PlanningLogic.creditCardStatementItems(
            accounts: [account],
            records: records,
            occurrences: [],
            statementMonths: [statementMonth],
            referenceDate: try makeDate(year: 2026, month: 3, day: 10, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(statements.first?.amountMinor, 32_456)
        XCTAssertEqual(statements.first?.status, .pending)
        XCTAssertEqual(statements.first?.state, .payable)
    }

    func testLegacyPaymentTitleLockDoesNotLockCreditCardDebtLending() throws {
        let calendar = Calendar(identifier: .gregorian)
        let cardWalletID = UUID()
        let cashWalletID = UUID()
        let debtLending = record(
            primaryKind: .transfer,
            amountMinor: 32_456,
            currencyCode: "JPY",
            transferSubtype: .debt,
            debtIntent: .lend,
            title: TransactionDebtIntent.lend.title,
            sourceWalletID: cardWalletID,
            sourceWalletKind: .creditCard,
            occurredAt: try makeDate(year: 2026, month: 2, day: 12, calendar: calendar)
        )
        let unrelatedPayment = record(
            primaryKind: .transfer,
            amountMinor: 40_000,
            currencyCode: "JPY",
            transferSubtype: .internalTransfer,
            title: "Card payment",
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: cardWalletID,
            destinationWalletKind: .creditCard,
            occurredAt: try makeDate(year: 2026, month: 2, day: 26, calendar: calendar)
        )

        XCTAssertFalse(
            TransactionLogic.isLockedByPaidStatement(
                transaction: debtLending,
                allTransactions: [debtLending, unrelatedPayment],
                calendar: calendar
            )
        )
    }

    func testPaidStatementLockAcceptsLazyTransactionSequences() throws {
        let calendar = Calendar(identifier: .gregorian)
        let cardWalletID = UUID()
        let cashWalletID = UUID()
        let cardExpense = record(
            primaryKind: .expense,
            amountMinor: 12_000,
            currencyCode: "JPY",
            sourceWalletID: cardWalletID,
            sourceWalletKind: .creditCard,
            occurredAt: try makeDate(year: 2026, month: 2, day: 12, calendar: calendar)
        )
        let matchingPayment = record(
            primaryKind: .transfer,
            amountMinor: 12_000,
            currencyCode: "JPY",
            transferSubtype: .internalTransfer,
            title: "Card payment 02/2026",
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: cardWalletID,
            destinationWalletKind: .creditCard,
            occurredAt: try makeDate(year: 2026, month: 2, day: 26, calendar: calendar)
        )
        let laterIrrelevantPayment = record(
            primaryKind: .transfer,
            amountMinor: 1_000,
            currencyCode: "JPY",
            transferSubtype: .internalTransfer,
            title: "Card payment 03/2026",
            sourceWalletID: cashWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: cardWalletID,
            destinationWalletKind: .creditCard,
            occurredAt: try makeDate(year: 2026, month: 3, day: 26, calendar: calendar)
        )
        let counter = SequenceIterationCounter()
        let sequence = CountingTransactionSequence(
            records: [matchingPayment, laterIrrelevantPayment],
            counter: counter
        )

        XCTAssertTrue(
            TransactionLogic.isLockedByPaidStatement(
                transaction: cardExpense,
                allTransactions: sequence,
                calendar: calendar
            )
        )
        XCTAssertEqual(counter.nextCalls, 1)
    }

    func testCounterpartySuggestionsMatchSingleCharacterQueries() {
        let records = [
            debtRecord(
                amountMinor: 100,
                intent: .lend,
                counterpartyName: "An",
                normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName("An")
            ),
            debtRecord(
                amountMinor: 100,
                intent: .borrow,
                counterpartyName: "Binh",
                normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName("Binh")
            )
        ]

        let suggestions = TransactionLogic.counterpartySuggestions(
            from: records,
            query: "a",
            excludingTransactionID: nil,
            limit: 5
        )

        XCTAssertEqual(suggestions.map(\.title), ["An"])
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

    func testEphemeralReceiptPolicyDeletesStoredReceiptOnSave() {
        XCTAssertTrue(TransactionReceiptPersistencePolicy.ephemeral.deletesStoredReceiptOnSave)
        XCTAssertFalse(TransactionReceiptPersistencePolicy.persistLocally.deletesStoredReceiptOnSave)
        XCTAssertFalse(TransactionReceiptPersistencePolicy.ephemeral.canPersistReceiptImage)
        XCTAssertTrue(TransactionReceiptPersistencePolicy.persistLocally.canPersistReceiptImage)
    }

    private func debtRecord(
        amountMinor: Int64,
        currencyCode: String = "JPY",
        intent: TransactionDebtIntent,
        entryStatus: TransactionEntryStatus = .posted,
        counterpartyName: String = "An",
        normalizedCounterpartyKey: String? = TransactionLogic.normalizeCounterpartyName("An"),
        sourceWalletID: UUID = UUID(),
        occurredAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> TransactionRecordSnapshot {
        record(
            primaryKind: .transfer,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            transferSubtype: .debt,
            debtIntent: intent,
            entryStatus: entryStatus,
            title: intent.title,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey,
            sourceWalletID: sourceWalletID,
            occurredAt: occurredAt
        )
    }

    private func record(
        primaryKind: TransactionPrimaryKind,
        amountMinor: Int64,
        currencyCode: String,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        entryStatus: TransactionEntryStatus = .posted,
        title: String = "Record",
        counterpartyName: String? = nil,
        normalizedCounterpartyKey: String? = nil,
        sourceWalletID: UUID = UUID(),
        sourceWalletKind: LedgerWalletKind = .cash,
        destinationWalletID: UUID? = nil,
        destinationWalletKind: LedgerWalletKind? = nil,
        occurredAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
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
            sourceCurrencyCode: currencyCode,
            isArchived: false,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: destinationWalletID,
            destinationWalletKind: destinationWalletKind,
            categoryID: primaryKind == .expense || primaryKind == .income ? UUID() : nil,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        return try XCTUnwrap(calendar.date(from: components))
    }

    private final class SequenceIterationCounter {
        var nextCalls = 0
    }

    private struct CountingTransactionSequence: Sequence {
        let records: [TransactionRecordSnapshot]
        let counter: SequenceIterationCounter

        func makeIterator() -> AnyIterator<TransactionRecordSnapshot> {
            var iterator = records.makeIterator()
            return AnyIterator {
                counter.nextCalls += 1
                return iterator.next()
            }
        }
    }
}
