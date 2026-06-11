import XCTest
@testable import MistiaCoreLogic

final class SettlementLogicTests: XCTestCase {
    func testResaleFullPaymentRecoversCostBeforeProfit() {
        let allocation = SettlementLogic.resaleReceiptAllocation(
            costMinor: 1_000,
            saleMinor: 1_500,
            priorReceiptMinor: 0,
            paymentMinor: 1_500
        )

        XCTAssertEqual(allocation.expenseOffsetMinor, 1_000)
        XCTAssertEqual(allocation.incomeMinor, 500)
        XCTAssertEqual(allocation.settledMinor, 1_500)
    }

    func testResalePartialPaymentsAllocateCostFirst() {
        let first = SettlementLogic.resaleReceiptAllocation(
            costMinor: 1_000,
            saleMinor: 1_500,
            priorReceiptMinor: 0,
            paymentMinor: 600
        )
        let second = SettlementLogic.resaleReceiptAllocation(
            costMinor: 1_000,
            saleMinor: 1_500,
            priorReceiptMinor: 600,
            paymentMinor: 600
        )

        XCTAssertEqual(first.expenseOffsetMinor, 600)
        XCTAssertEqual(first.incomeMinor, 0)
        XCTAssertEqual(second.expenseOffsetMinor, 400)
        XCTAssertEqual(second.incomeMinor, 200)
    }

    func testResaleBelowCostNeverCreatesPositiveIncome() {
        let allocation = SettlementLogic.resaleReceiptAllocation(
            costMinor: 1_000,
            saleMinor: 800,
            priorReceiptMinor: 0,
            paymentMinor: 800
        )

        XCTAssertEqual(allocation.expenseOffsetMinor, 800)
        XCTAssertEqual(allocation.incomeMinor, 0)
        XCTAssertEqual(allocation.remainingReceivableMinor, 0)
    }

    func testSharedExpenseSplitCreatesSettlementFromCToA() {
        let organizerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let participantA = SettlementParticipantInput(id: organizerID, name: "A", paidMinor: 8_000)
        let participantB = SettlementParticipantInput(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "B", paidMinor: 5_000)
        let participantC = SettlementParticipantInput(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "C", paidMinor: 2_000)

        let result = SettlementLogic.sharedExpenseSettlement(
            participants: [participantA, participantB, participantC],
            organizerID: organizerID
        )

        XCTAssertEqual(result.participants.map(\.shareMinor), [5_000, 5_000, 5_000])
        XCTAssertEqual(result.participants.map(\.netMinor), [3_000, 0, -3_000])
        XCTAssertEqual(result.suggestions, [
            SettlementSuggestion(
                payerID: participantC.id,
                receiverID: participantA.id,
                amountMinor: 3_000
            )
        ])
    }

    func testSharedExpenseOddRoundingAssignsRemainderToOrganizer() {
        let organizerID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let participantA = SettlementParticipantInput(id: organizerID, name: "A", paidMinor: 2)
        let participantB = SettlementParticipantInput(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, name: "B", paidMinor: 0)
        let participantC = SettlementParticipantInput(id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!, name: "C", paidMinor: 0)

        let result = SettlementLogic.sharedExpenseSettlement(
            participants: [participantA, participantB, participantC],
            organizerID: organizerID
        )

        XCTAssertEqual(result.participants.map(\.shareMinor), [2, 0, 0])
        XCTAssertEqual(result.participants.map(\.netMinor), [0, 0, 0])
        XCTAssertTrue(result.suggestions.isEmpty)
    }

    func testSettlementReportingOverridesCashflowKind() {
        let receipt = TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .income,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "C trả A",
            note: nil,
            amountMinor: 3_000,
            reportingExpenseMinor: -3_000,
            reportingIncomeMinor: 0,
            occurredAt: Date(timeIntervalSince1970: 1_774_051_200),
            createdAt: Date(timeIntervalSince1970: 1_774_051_200),
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: nil,
            counterpartyName: "C",
            normalizedCounterpartyKey: "c"
        )

        XCTAssertEqual(TransactionLogic.reportedExpenseAmount(for: receipt), -3_000)
        XCTAssertEqual(TransactionLogic.reportedIncomeAmount(for: receipt), 0)
        XCTAssertEqual(TransactionLogic.summary(for: [receipt]).expenseMinor, -3_000)
        XCTAssertEqual(TransactionLogic.summary(for: [receipt]).incomeMinor, 0)
    }
}
