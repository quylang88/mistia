import XCTest
@testable import MistiaCoreLogic

final class SettlementLogicTests: XCTestCase {
    func testPreparingEventRequiresTitleAndNonSelfParticipantButAllowsNoBills() {
        XCTAssertTrue(
            SettlementLogic.canSavePreparingEvent(
                title: "Trip",
                participantNames: ["Linh"]
            )
        )
        XCTAssertFalse(
            SettlementLogic.canSavePreparingEvent(
                title: "",
                participantNames: ["Linh"]
            )
        )
        XCTAssertFalse(
            SettlementLogic.canSavePreparingEvent(
                title: "Trip",
                participantNames: ["   "]
            )
        )
    }

    func testPreparingEventSummarizesLinkedBillsAndVisibleParticipants() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
        let selfID = UUID(uuidString: "00000000-0000-0000-0000-00000000A101")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let later = now.addingTimeInterval(60)
        let groups = [
            SettlementGroupRecordSnapshot(
                id: groupID,
                kind: .sharedExpense,
                status: .preparing,
                title: "Weekend Osaka",
                currencyCode: "JPY",
                occurredAt: now,
                totalMinor: 0,
                expectedMinor: 0,
                settledMinor: 0,
                note: "Train and food",
                updatedAt: now
            )
        ]
        let participants = [
            SettlementParticipantRecordSnapshot(
                id: selfID,
                groupID: groupID,
                displayName: "Me",
                normalizedKey: "me",
                isSelf: true,
                sortOrder: 0,
                updatedAt: now
            ),
            SettlementParticipantRecordSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000A102")!,
                groupID: groupID,
                displayName: "Linh",
                normalizedKey: "linh",
                isSelf: false,
                sortOrder: 1,
                updatedAt: now
            ),
            SettlementParticipantRecordSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000A103")!,
                groupID: groupID,
                displayName: "Mai",
                normalizedKey: "mai",
                isSelf: false,
                sortOrder: 2,
                updatedAt: now
            )
        ]
        let records = [
            settlementExpenseRecord(
                groupID: groupID,
                title: "Train",
                amountMinor: 5_000,
                occurredAt: now
            ),
            settlementExpenseRecord(
                groupID: groupID,
                title: "Dinner",
                amountMinor: 7_500,
                occurredAt: later
            ),
            settlementExpenseRecord(
                groupID: UUID(),
                title: "Other event",
                amountMinor: 9_000,
                occurredAt: later
            )
        ]

        let events = SettlementLogic.preparingEventSnapshots(
            groups: groups,
            participants: participants,
            records: records
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, groupID)
        XCTAssertEqual(events.first?.totalPaidMinor, 12_500)
        XCTAssertEqual(events.first?.billCount, 2)
        XCTAssertEqual(events.first?.participantNames, ["Linh", "Mai"])
        XCTAssertEqual(events.first?.note, "Train and food")
        XCTAssertEqual(events.first?.lastUpdatedAt, later)
    }

    func testParticipantSuggestionRecordsUseOnlyCurrentOwnerTransactions() {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
        let familyMemberID = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
        let currentRecord = debtRecord(counterpartyName: "An")
        let familyRecord = debtRecord(counterpartyName: "Anh")
        let unscopedLocalRecord = debtRecord(counterpartyName: "Aoi")
        let records = [currentRecord, familyRecord, unscopedLocalRecord]

        let scopedRecords = SettlementLogic.participantSuggestionRecords(
            from: records,
            transactionOwnerMap: [
                currentRecord.id: currentUserID,
                familyRecord.id: familyMemberID
            ],
            currentUserID: currentUserID
        )

        XCTAssertEqual(scopedRecords.map(\.id), [currentRecord.id, unscopedLocalRecord.id])
        let suggestionTitles = TransactionLogic.counterpartySuggestions(from: scopedRecords, query: "a").map(\.title)
        XCTAssertTrue(suggestionTitles.contains("An"))
        XCTAssertTrue(suggestionTitles.contains("Aoi"))
        XCTAssertFalse(suggestionTitles.contains("Anh"))
    }

    func testFinalizationInputsUseSelfPaidTotalFromLinkedBills() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let selfParticipant = SettlementParticipantRecordSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B101")!,
            groupID: groupID,
            displayName: "Me",
            normalizedKey: "me",
            isSelf: true,
            sortOrder: 0,
            updatedAt: Date(timeIntervalSince1970: 1_778_400_000)
        )
        let otherParticipants = [
            SettlementParticipantRecordSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000B102")!,
                groupID: groupID,
                displayName: "Linh",
                normalizedKey: "linh",
                isSelf: false,
                sortOrder: 1,
                updatedAt: Date(timeIntervalSince1970: 1_778_400_000)
            ),
            SettlementParticipantRecordSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000B103")!,
                groupID: groupID,
                displayName: "Mai",
                normalizedKey: "mai",
                isSelf: false,
                sortOrder: 2,
                updatedAt: Date(timeIntervalSince1970: 1_778_400_000)
            )
        ]
        let records = [
            settlementExpenseRecord(
                groupID: groupID,
                title: "Train",
                amountMinor: 5_000,
                occurredAt: Date(timeIntervalSince1970: 1_778_400_000)
            ),
            settlementExpenseRecord(
                groupID: groupID,
                title: "Dinner",
                amountMinor: 7_000,
                occurredAt: Date(timeIntervalSince1970: 1_778_401_000)
            )
        ]

        let inputs = SettlementLogic.sharedExpenseInputsForFinalization(
            selfParticipant: selfParticipant,
            participants: otherParticipants,
            records: records
        )
        let result = SettlementLogic.sharedExpenseSettlement(
            participants: inputs,
            organizerID: selfParticipant.id
        )

        XCTAssertEqual(inputs.map(\.name), ["Me", "Linh", "Mai"])
        XCTAssertEqual(inputs.map(\.paidMinor), [12_000, 0, 0])
        XCTAssertEqual(result.participants.map(\.shareMinor), [4_000, 4_000, 4_000])
        XCTAssertEqual(result.suggestions, [
            SettlementSuggestion(
                payerID: otherParticipants[0].id,
                receiverID: selfParticipant.id,
                amountMinor: 4_000
            ),
            SettlementSuggestion(
                payerID: otherParticipants[1].id,
                receiverID: selfParticipant.id,
                amountMinor: 4_000
            )
        ])
    }

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

    private func settlementExpenseRecord(
        groupID: UUID,
        title: String,
        amountMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: title,
            note: nil,
            amountMinor: amountMinor,
            settlementGroupID: groupID,
            settlementRole: .sharedExpensePaid,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
    }

    private func debtRecord(counterpartyName: String) -> TransactionRecordSnapshot {
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        return TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            entryStatus: .posted,
            title: "Debt",
            note: nil,
            amountMinor: 1_000,
            occurredAt: now,
            createdAt: now,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: nil,
            counterpartyName: counterpartyName,
            normalizedCounterpartyKey: TransactionLogic.normalizeCounterpartyName(counterpartyName)
        )
    }
}
