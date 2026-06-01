import Foundation
import XCTest
@testable import Mistia

final class TransactionLogicTests: XCTestCase {
    func testOpenDebtPositionsAreGroupedByCounterpartyAndCurrency() {
        let personKey = TransactionLogic.normalizeCounterpartyName("An")!
        let lendWalletID = UUID()
        let records = [
            debtRecord(
                amountMinor: 1_000,
                currencyCode: "JPY",
                intent: .lend,
                counterpartyName: "An",
                normalizedCounterpartyKey: personKey,
                sourceWalletID: lendWalletID
            ),
            debtRecord(
                amountMinor: 200,
                currencyCode: "JPY",
                intent: .collect,
                counterpartyName: "An",
                normalizedCounterpartyKey: personKey
            ),
            debtRecord(
                amountMinor: 500_000,
                currencyCode: "VND",
                intent: .lend,
                counterpartyName: "An",
                normalizedCounterpartyKey: personKey
            )
        ]

        let positions = TransactionLogic.openDebtPositions(from: records)

        XCTAssertEqual(positions.map(\.currencyCode).sorted(), ["JPY", "VND"])
        XCTAssertEqual(positions.first { $0.currencyCode == "JPY" }?.netMinor, 800)
        XCTAssertEqual(positions.first { $0.currencyCode == "JPY" }?.preferredWalletID, lendWalletID)
        XCTAssertEqual(positions.first { $0.currencyCode == "VND" }?.netMinor, 500_000)
    }

    func testOpenDebtPositionsPreferBorrowWalletForRepayment() {
        let borrowWalletID = UUID()
        let otherWalletID = UUID()
        let records = [
            debtRecord(amountMinor: 1_000, intent: .borrow, sourceWalletID: borrowWalletID),
            debtRecord(amountMinor: 300, intent: .repay, sourceWalletID: otherWalletID)
        ]

        let position = TransactionLogic.openDebtPositions(from: records).first

        XCTAssertEqual(position?.netMinor, -700)
        XCTAssertEqual(position?.preferredWalletID, borrowWalletID)
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
        counterpartyName: String = "An",
        normalizedCounterpartyKey: String? = TransactionLogic.normalizeCounterpartyName("An"),
        sourceWalletID: UUID = UUID()
    ) -> TransactionRecordSnapshot {
        record(
            primaryKind: .transfer,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            transferSubtype: .debt,
            debtIntent: intent,
            title: intent.title,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey,
            sourceWalletID: sourceWalletID
        )
    }

    private func record(
        primaryKind: TransactionPrimaryKind,
        amountMinor: Int64,
        currencyCode: String,
        transferSubtype: TransactionTransferSubtype? = nil,
        debtIntent: TransactionDebtIntent? = nil,
        title: String = "Record",
        counterpartyName: String? = nil,
        normalizedCounterpartyKey: String? = nil,
        sourceWalletID: UUID = UUID(),
        sourceWalletKind: LedgerWalletKind = .cash,
        occurredAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: primaryKind,
            transferSubtype: transferSubtype,
            debtIntent: debtIntent,
            entryStatus: .posted,
            title: title,
            note: nil,
            amountMinor: amountMinor,
            sourceCurrencyCode: currencyCode,
            isArchived: false,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: sourceWalletID,
            sourceWalletKind: sourceWalletKind,
            destinationWalletID: nil,
            destinationWalletKind: nil,
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
}
