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
        sourceWalletID: UUID = UUID()
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
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceWalletID: sourceWalletID,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: primaryKind == .expense || primaryKind == .income ? UUID() : nil,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: normalizedCounterpartyKey
        )
    }
}
