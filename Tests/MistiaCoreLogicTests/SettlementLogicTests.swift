import XCTest
@testable import MistiaCoreLogic

final class SettlementLogicTests: XCTestCase {
    func testPreparingEventRequiresOnlyTitleAndAllowsNoParticipantsOrBills() {
        XCTAssertTrue(
            SettlementLogic.canSavePreparingEvent(
                title: "Trip",
                participantNames: ["Linh"]
            )
        )
        XCTAssertTrue(
            SettlementLogic.canSavePreparingEvent(
                title: "Trip",
                participantNames: []
            )
        )
        XCTAssertTrue(
            SettlementLogic.canSavePreparingEvent(
                title: "Trip",
                participantNames: ["   "]
            )
        )
        XCTAssertFalse(
            SettlementLogic.canSavePreparingEvent(
                title: "",
                participantNames: ["Linh"]
            )
        )
    }

    func testCompletedEventSnapshotsExcludePreparingEventIDs() {
        let ongoingID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
        let completedID = UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!
        let olderCompletedID = UUID(uuidString: "00000000-0000-0000-0000-00000000E003")!
        let ongoingEvent = eventSnapshot(id: ongoingID, title: "Ongoing")
        let completedEvent = eventSnapshot(id: completedID, title: "Completed")
        let olderCompletedEvent = eventSnapshot(id: olderCompletedID, title: "Older completed")

        let completedEvents = SettlementLogic.completedEventSnapshots(
            allEvents: [completedEvent, ongoingEvent, olderCompletedEvent],
            preparingEvents: [ongoingEvent]
        )

        XCTAssertEqual(completedEvents.map(\.id), [completedID, olderCompletedID])
    }


    func testAllEventSnapshotsExcludeArchivedEventsButIncludeCompletedEvents() {
        let activePreparingID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
        let completedID = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
        let archivedSettledID = UUID(uuidString: "00000000-0000-0000-0000-00000000D003")!
        let archivedPreparingID = UUID(uuidString: "00000000-0000-0000-0000-00000000D004")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let groups = [
            settlementGroupSnapshot(id: activePreparingID, status: .preparing, title: "Active preparing", now: now),
            settlementGroupSnapshot(
                id: completedID,
                status: .settled,
                title: "Completed",
                now: now
            ),
            settlementGroupSnapshot(
                id: archivedSettledID,
                status: .settled,
                title: "Archived settled",
                now: now,
                isArchived: true,
                archivedAt: now
            ),
            settlementGroupSnapshot(
                id: archivedPreparingID,
                status: .preparing,
                title: "Archived preparing",
                now: now,
                isArchived: true,
                archivedAt: now
            )
        ]

        let allEvents = SettlementLogic.allEventSnapshots(
            groups: groups,
            participants: [],
            records: []
        )
        let completedEvents = SettlementLogic.completedEventSnapshots(
            allEvents: allEvents,
            preparingEvents: SettlementLogic.preparingEventSnapshots(
                groups: groups,
                participants: [],
                records: []
            )
        )

        XCTAssertEqual(allEvents.map(\.id), [activePreparingID, completedID])
        XCTAssertEqual(completedEvents.map(\.id), [completedID])
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

    func testArchivedEventFilteringHidesGeneratedDebtButKeepsLinkedBills() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000E101")!
        let otherGroupID = UUID(uuidString: "00000000-0000-0000-0000-00000000E102")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let linkedExpense = settlementExpenseRecord(
            groupID: groupID,
            title: "Dinner",
            amountMinor: 12_000,
            occurredAt: now
        )
        let linkedPaidOnBehalf = paidOnBehalfEventBillRecord(
            groupID: groupID,
            amountMinor: 3_000,
            occurredAt: now.addingTimeInterval(60)
        )
        let generatedReceivable = sharedExpenseDebtPrincipalRecord(
            groupID: groupID,
            debtIntent: .lend,
            amountMinor: 4_000,
            occurredAt: now.addingTimeInterval(120)
        )
        let generatedPayment = sharedExpenseDebtSettlementRecord(
            groupID: groupID,
            debtIntent: .collect,
            amountMinor: 4_000,
            reportingExpenseMinor: 0,
            occurredAt: now.addingTimeInterval(180)
        )
        let otherEventDebt = sharedExpenseDebtPrincipalRecord(
            groupID: otherGroupID,
            debtIntent: .borrow,
            amountMinor: 5_000,
            occurredAt: now.addingTimeInterval(240)
        )

        let visibleRecords = SettlementLogic.visibleRecordsAfterEventArchiveFiltering(
            [linkedExpense, linkedPaidOnBehalf, generatedReceivable, generatedPayment, otherEventDebt],
            archivedEventIDs: [groupID]
        )

        XCTAssertEqual(visibleRecords.map(\.id), [linkedExpense.id, linkedPaidOnBehalf.id, otherEventDebt.id])
    }

    func testArchivedSharedExpenseEventIDsDriveFilteringAndRestoreWhenEmpty() {
        let archivedGroupID = UUID(uuidString: "00000000-0000-0000-0000-00000000E201")!
        let activeGroupID = UUID(uuidString: "00000000-0000-0000-0000-00000000E202")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let groups = [
            settlementGroupSnapshot(
                id: archivedGroupID,
                status: .settled,
                title: "Archived trip",
                now: now,
                isArchived: true,
                archivedAt: now
            ),
            settlementGroupSnapshot(
                id: activeGroupID,
                status: .settled,
                title: "Active trip",
                now: now
            )
        ]
        let linkedExpense = settlementExpenseRecord(
            groupID: archivedGroupID,
            title: "Dinner",
            amountMinor: 12_000,
            occurredAt: now
        )
        let generatedPayment = sharedExpenseDebtSettlementRecord(
            groupID: archivedGroupID,
            debtIntent: .collect,
            amountMinor: 4_000,
            reportingExpenseMinor: 0,
            occurredAt: now.addingTimeInterval(60)
        )
        let activeGeneratedDebt = sharedExpenseDebtPrincipalRecord(
            groupID: activeGroupID,
            debtIntent: .borrow,
            amountMinor: 5_000,
            occurredAt: now.addingTimeInterval(120)
        )
        let records = [linkedExpense, generatedPayment, activeGeneratedDebt]

        let archivedEventIDs = SettlementLogic.archivedSharedExpenseEventIDs(from: groups)
        let filtered = SettlementLogic.visibleRecordsAfterEventArchiveFiltering(
            records,
            archivedEventIDs: archivedEventIDs
        )
        let restored = SettlementLogic.visibleRecordsAfterEventArchiveFiltering(
            records,
            archivedEventIDs: []
        )

        XCTAssertEqual(archivedEventIDs, [archivedGroupID])
        XCTAssertEqual(filtered.map(\.id), [linkedExpense.id, activeGeneratedDebt.id])
        XCTAssertEqual(restored.map(\.id), records.map(\.id))
    }

    func testArchivedEventFilteredRecordsDoNotAffectSummaryOrWalletBalance() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000E301")!
        let walletID = UUID(uuidString: "00000000-0000-0000-0000-00000000E302")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let wallet = TransactionWalletSnapshot(
            id: walletID,
            kind: .cash,
            openingBalanceMinor: 100_000
        )
        let linkedExpense = TransactionRecordSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000E303")!,
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Dinner",
            note: nil,
            amountMinor: 12_000,
            settlementGroupID: groupID,
            settlementRole: .sharedExpensePaid,
            reportingExpenseMinor: nil,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            occurredAt: now,
            createdAt: now,
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )
        let generatedReceipt = TransactionRecordSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000E304")!,
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .collect,
            entryStatus: .posted,
            title: "Expense reimbursement",
            note: nil,
            amountMinor: 4_000,
            settlementGroupID: groupID,
            settlementRole: .sharedExpenseReceipt,
            reportingExpenseMinor: -4_000,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            occurredAt: now.addingTimeInterval(60),
            createdAt: now.addingTimeInterval(60),
            sourceWalletID: walletID,
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: nil,
            counterpartyName: "Linh",
            normalizedCounterpartyKey: "linh"
        )

        let filteredRecords = SettlementLogic.visibleRecordsAfterEventArchiveFiltering(
            [linkedExpense, generatedReceipt],
            archivedEventIDs: [groupID]
        )
        let summary = TransactionLogic.summary(for: filteredRecords)
        let balanceIndex = TransactionLogic.walletBalanceIndex(
            wallets: [wallet],
            records: filteredRecords
        )

        XCTAssertEqual(filteredRecords.map(\.id), [linkedExpense.id])
        XCTAssertEqual(summary.expenseMinor, 12_000)
        XCTAssertEqual(summary.incomeMinor, 0)
        XCTAssertEqual(balanceIndex.balance(for: wallet), 88_000)
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

    func testEventTotalsCountOnlyDirectlyLinkedBillsIncludingPaidOnBehalfDebt() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000B201")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let linkedExpense = settlementExpenseRecord(
            groupID: groupID,
            title: "Hotel",
            amountMinor: 100_000,
            occurredAt: now
        )
        let paidOnBehalf = paidOnBehalfEventBillRecord(
            groupID: groupID,
            amountMinor: 20_000,
            occurredAt: now.addingTimeInterval(60)
        )
        let automaticPayable = sharedExpenseDebtPrincipalRecord(
            groupID: groupID,
            debtIntent: .borrow,
            amountMinor: 50_000,
            occurredAt: now.addingTimeInterval(120)
        )
        let automaticPayment = sharedExpenseDebtSettlementRecord(
            groupID: groupID,
            debtIntent: .repay,
            amountMinor: 10_000,
            reportingExpenseMinor: 0,
            occurredAt: now.addingTimeInterval(180)
        )
        let archivedLinkedExpense = archivedSettlementExpenseRecord(
            groupID: groupID,
            amountMinor: 30_000,
            occurredAt: now.addingTimeInterval(240)
        )
        let otherEventExpense = settlementExpenseRecord(
            groupID: UUID(),
            title: "Other event",
            amountMinor: 999_000,
            occurredAt: now
        )
        let group = settlementGroupSnapshot(
            id: groupID,
            status: .preparing,
            title: "Trip",
            now: now
        )

        let events = SettlementLogic.preparingEventSnapshots(
            groups: [group],
            participants: [],
            records: [
                linkedExpense,
                paidOnBehalf,
                automaticPayable,
                automaticPayment,
                archivedLinkedExpense,
                otherEventExpense
            ]
        )

        XCTAssertEqual(events.first?.totalPaidMinor, 120_000)
        XCTAssertEqual(events.first?.billCount, 2)
        XCTAssertEqual(events.first?.lastUpdatedAt, paidOnBehalf.occurredAt)
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

    func testDebtAmountOverrideChangesOnlyMatchingSuggestion() {
        let first = SettlementSuggestion(payerID: UUID(), receiverID: UUID(), amountMinor: 2_000)
        let second = SettlementSuggestion(payerID: UUID(), receiverID: UUID(), amountMinor: 3_000)

        let result = SettlementLogic.applyingDebtAmountOverrides(
            to: [first, second],
            overridesBySuggestionID: [first.id: 2_500]
        )

        XCTAssertEqual(result, [
            SettlementSuggestion(
                payerID: first.payerID,
                receiverID: first.receiverID,
                amountMinor: 2_500
            ),
            second
        ])
    }

    func testDebtAmountOverrideKeepsDirectionAndParticipantShares() {
        let organizerID = UUID()
        let participantID = UUID()
        let split = SettlementLogic.sharedExpenseSettlement(
            participants: [
                SettlementParticipantInput(id: organizerID, name: "Me", paidMinor: 6_000),
                SettlementParticipantInput(id: participantID, name: "An", paidMinor: 0)
            ],
            organizerID: organizerID
        )
        let automaticSuggestion = try! XCTUnwrap(split.suggestions.first)

        let overriddenSuggestions = SettlementLogic.applyingDebtAmountOverrides(
            to: split.suggestions,
            overridesBySuggestionID: [automaticSuggestion.id: 1_000]
        )

        XCTAssertEqual(split.participants.map(\.shareMinor), [3_000, 3_000])
        XCTAssertEqual(overriddenSuggestions.first?.payerID, automaticSuggestion.payerID)
        XCTAssertEqual(overriddenSuggestions.first?.receiverID, automaticSuggestion.receiverID)
        XCTAssertEqual(overriddenSuggestions.first?.amountMinor, 1_000)
    }

    func testDebtAmountOverrideIgnoresNonPositiveValues() {
        let suggestion = SettlementSuggestion(payerID: UUID(), receiverID: UUID(), amountMinor: 2_000)

        XCTAssertEqual(
            SettlementLogic.applyingDebtAmountOverrides(
                to: [suggestion],
                overridesBySuggestionID: [suggestion.id: 0]
            ),
            [suggestion]
        )
        XCTAssertEqual(
            SettlementLogic.applyingDebtAmountOverrides(
                to: [suggestion],
                overridesBySuggestionID: [suggestion.id: -500]
            ),
            [suggestion]
        )
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

    func testSharedExpensePaidReportingAllocationsReduceOriginalEventExpenseToSelfShare() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D101")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let bill = settlementExpenseRecord(
            groupID: eventID,
            title: "Dinner",
            amountMinor: 8_000,
            occurredAt: now
        )

        let allocations = SettlementLogic.sharedExpensePaidReportingAllocations(
            records: [bill],
            selfShareMinor: 5_000
        )

        XCTAssertEqual(
            allocations,
            [
                SettlementExpenseReportingAllocation(
                    transactionID: bill.id,
                    reportingExpenseMinor: 5_000
                )
            ]
        )
    }

    func testSharedExpensePaidReportingAllocationsCanIncreaseAndDistributeMultipleBills() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D102")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let first = settlementExpenseRecord(
            groupID: eventID,
            title: "Taxi",
            amountMinor: 1_000,
            occurredAt: now
        )
        let second = settlementExpenseRecord(
            groupID: eventID,
            title: "Hotel",
            amountMinor: 2_000,
            occurredAt: now.addingTimeInterval(60)
        )

        let allocations = SettlementLogic.sharedExpensePaidReportingAllocations(
            records: [second, first],
            selfShareMinor: 5_000
        )

        XCTAssertEqual(
            allocations,
            [
                SettlementExpenseReportingAllocation(
                    transactionID: first.id,
                    reportingExpenseMinor: 1_666
                ),
                SettlementExpenseReportingAllocation(
                    transactionID: second.id,
                    reportingExpenseMinor: 3_334
                )
            ]
        )
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

    func testSharedExpenseReceiptDoesNotChangeAlreadySplitEventExpense() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let paid = settlementExpenseRecord(
            groupID: eventID,
            title: "Dinner",
            amountMinor: 8_000,
            reportingExpenseMinor: 4_000,
            occurredAt: now
        )
        let receipt = sharedExpenseDebtSettlementRecord(
            groupID: eventID,
            debtIntent: .collect,
            amountMinor: 4_000,
            reportingExpenseMinor: SettlementLogic.sharedExpenseDebtReportingOverride(
                settlementIntent: .collect,
                amountMinor: 4_000
            ).expenseMinor,
            occurredAt: now.addingTimeInterval(60)
        )

        let summary = TransactionLogic.summary(for: [paid, receipt])

        XCTAssertEqual(TransactionLogic.reportedExpenseAmount(for: paid), 4_000)
        XCTAssertEqual(TransactionLogic.reportedExpenseAmount(for: receipt), 0)
        XCTAssertEqual(TransactionLogic.reportedIncomeAmount(for: receipt), 0)
        XCTAssertEqual(summary.expenseMinor, 4_000)
        XCTAssertEqual(summary.incomeMinor, 0)
    }

    func testSharedExpenseRepaymentDoesNotDoubleCountAlreadySplitEventExpense() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let repayment = sharedExpenseDebtSettlementRecord(
            groupID: eventID,
            debtIntent: .repay,
            amountMinor: 4_000,
            reportingExpenseMinor: SettlementLogic.sharedExpenseDebtReportingOverride(
                settlementIntent: .repay,
                amountMinor: 4_000
            ).expenseMinor,
            occurredAt: now
        )

        let summary = TransactionLogic.summary(for: [repayment])

        XCTAssertEqual(TransactionLogic.reportedExpenseAmount(for: repayment), 0)
        XCTAssertEqual(TransactionLogic.reportedIncomeAmount(for: repayment), 0)
        XCTAssertEqual(summary.expenseMinor, 0)
        XCTAssertEqual(summary.incomeMinor, 0)
    }

    func testDebtSettlementAllocatesEventLinkedDebtBeforeOutsideDebt() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D003")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let eventDebt = sharedExpenseDebtPrincipalRecord(
            groupID: eventID,
            debtIntent: .lend,
            amountMinor: 4_000,
            occurredAt: now
        )
        let outsideDebt = debtRecord(counterpartyName: "B", amountMinor: 3_000)

        let allocations = SettlementLogic.sharedExpenseDebtPaymentAllocations(
            from: [outsideDebt, eventDebt],
            settlementIntent: .collect,
            paymentMinor: 5_000
        )

        XCTAssertEqual(
            allocations,
            [
                SettlementDebtPaymentAllocation(
                    settlementGroupID: eventID,
                    settlementRole: .sharedExpenseReceipt,
                    amountMinor: 4_000,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                ),
                SettlementDebtPaymentAllocation(
                    settlementGroupID: nil,
                    settlementRole: nil,
                    amountMinor: 1_000,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                )
            ]
        )
    }

    func testDebtSettlementAllocatesEventThenResaleThenGenericDebt() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D004")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let eventDebt = sharedExpenseDebtPrincipalRecord(
            groupID: eventID,
            debtIntent: .lend,
            amountMinor: 4_000,
            occurredAt: now
        )
        let resaleDebt = resaleDebtPrincipalRecord(
            saleMinor: 3_000,
            costMinor: 2_000,
            occurredAt: now.addingTimeInterval(60)
        )
        let resalePriorReceipt = resaleDebtReceiptRecord(
            amountMinor: 500,
            reportingExpenseMinor: -500,
            reportingIncomeMinor: 0,
            occurredAt: now.addingTimeInterval(120)
        )
        let outsideDebt = debtRecord(counterpartyName: "B", amountMinor: 3_000)

        let allocations = SettlementLogic.sharedExpenseDebtPaymentAllocations(
            from: [outsideDebt, resalePriorReceipt, resaleDebt, eventDebt],
            settlementIntent: .collect,
            paymentMinor: 7_000
        )

        XCTAssertEqual(
            allocations,
            [
                SettlementDebtPaymentAllocation(
                    settlementGroupID: eventID,
                    settlementRole: .sharedExpenseReceipt,
                    amountMinor: 4_000,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                ),
                SettlementDebtPaymentAllocation(
                    settlementGroupID: nil,
                    settlementRole: .resaleReceipt,
                    amountMinor: 2_500,
                    reportingExpenseMinor: -1_500,
                    reportingIncomeMinor: 1_000
                ),
                SettlementDebtPaymentAllocation(
                    settlementGroupID: nil,
                    settlementRole: nil,
                    amountMinor: 500,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                )
            ]
        )
    }

    func testDebtSettlementAllocationsIgnoreDirectlyLinkedPaidOnBehalfDebtBills() {
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000D005")!
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        let paidOnBehalf = paidOnBehalfEventBillRecord(
            groupID: eventID,
            amountMinor: 6_000,
            occurredAt: now
        )
        let automaticPayable = sharedExpenseDebtPrincipalRecord(
            groupID: eventID,
            debtIntent: .borrow,
            amountMinor: 4_000,
            occurredAt: now.addingTimeInterval(60)
        )

        let allocations = SettlementLogic.sharedExpenseDebtPaymentAllocations(
            from: [paidOnBehalf, automaticPayable],
            settlementIntent: .repay,
            paymentMinor: 7_000
        )

        XCTAssertEqual(
            allocations,
            [
                SettlementDebtPaymentAllocation(
                    settlementGroupID: eventID,
                    settlementRole: .sharedExpensePayment,
                    amountMinor: 4_000,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                ),
                SettlementDebtPaymentAllocation(
                    settlementGroupID: nil,
                    settlementRole: nil,
                    amountMinor: 3_000,
                    reportingExpenseMinor: 0,
                    reportingIncomeMinor: 0
                )
            ]
        )
    }

    private func settlementExpenseRecord(
        groupID: UUID,
        title: String,
        amountMinor: Int64,
        reportingExpenseMinor: Int64? = nil,
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
            reportingExpenseMinor: reportingExpenseMinor,
            reportingIncomeMinor: 0,
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

    private func archivedSettlementExpenseRecord(
        groupID: UUID,
        amountMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Archived",
            note: nil,
            amountMinor: amountMinor,
            settlementGroupID: groupID,
            settlementRole: .sharedExpensePaid,
            reportingExpenseMinor: nil,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            isArchived: true,
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

    private func paidOnBehalfEventBillRecord(
        groupID: UUID,
        amountMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .borrow,
            entryStatus: .posted,
            title: "Duoc tra ho",
            note: nil,
            amountMinor: amountMinor,
            settlementGroupID: groupID,
            settlementRole: .sharedExpensePaid,
            reportingExpenseMinor: nil,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: nil,
            sourceWalletKind: nil,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: "B",
            normalizedCounterpartyKey: "b"
        )
    }

    private func sharedExpenseDebtPrincipalRecord(
        groupID: UUID,
        debtIntent: TransactionDebtIntent,
        amountMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: debtIntent,
            entryStatus: .posted,
            title: debtIntent.title,
            note: nil,
            amountMinor: amountMinor,
            settlementGroupID: groupID,
            settlementRole: debtIntent == .lend ? .sharedExpenseReceivable : .sharedExpensePayable,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: nil,
            counterpartyName: "B",
            normalizedCounterpartyKey: "b"
        )
    }

    private func sharedExpenseDebtSettlementRecord(
        groupID: UUID,
        debtIntent: TransactionDebtIntent,
        amountMinor: Int64,
        reportingExpenseMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: debtIntent,
            entryStatus: .posted,
            title: debtIntent.title,
            note: nil,
            amountMinor: amountMinor,
            settlementGroupID: groupID,
            settlementRole: debtIntent == .collect ? .sharedExpenseReceipt : .sharedExpensePayment,
            reportingExpenseMinor: reportingExpenseMinor,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: nil,
            counterpartyName: "B",
            normalizedCounterpartyKey: "b"
        )
    }

    private func resaleDebtPrincipalRecord(
        saleMinor: Int64,
        costMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            entryStatus: .posted,
            title: "Bán chịu",
            note: nil,
            amountMinor: saleMinor,
            settlementRole: .resaleReceivable,
            reportingExpenseMinor: costMinor,
            reportingIncomeMinor: 0,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: "B",
            normalizedCounterpartyKey: "b"
        )
    }

    private func resaleDebtReceiptRecord(
        amountMinor: Int64,
        reportingExpenseMinor: Int64,
        reportingIncomeMinor: Int64,
        occurredAt: Date
    ) -> TransactionRecordSnapshot {
        TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .collect,
            entryStatus: .posted,
            title: "Thu bán chịu",
            note: nil,
            amountMinor: amountMinor,
            settlementRole: .resaleReceipt,
            reportingExpenseMinor: reportingExpenseMinor,
            reportingIncomeMinor: reportingIncomeMinor,
            sourceCurrencyCode: "JPY",
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: UUID(),
            sourceWalletKind: .cash,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: nil,
            counterpartyName: "B",
            normalizedCounterpartyKey: "b"
        )
    }

    private func debtRecord(counterpartyName: String, amountMinor: Int64 = 1_000) -> TransactionRecordSnapshot {
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        return TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .transfer,
            transferSubtype: .debt,
            debtIntent: .lend,
            entryStatus: .posted,
            title: "Debt",
            note: nil,
            amountMinor: amountMinor,
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

    private func settlementGroupSnapshot(
        id: UUID,
        status: SettlementStatus,
        title: String,
        now: Date,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) -> SettlementGroupRecordSnapshot {
        SettlementGroupRecordSnapshot(
            id: id,
            kind: .sharedExpense,
            status: status,
            title: title,
            currencyCode: "JPY",
            occurredAt: now,
            totalMinor: 0,
            expectedMinor: 0,
            settledMinor: 0,
            note: nil,
            updatedAt: now,
            isArchived: isArchived,
            archivedAt: archivedAt
        )
    }

    private func eventSnapshot(
        id: UUID,
        title: String
    ) -> PreparingSettlementEventSnapshot {
        let now = Date(timeIntervalSince1970: 1_778_400_000)
        return PreparingSettlementEventSnapshot(
            id: id,
            title: title,
            currencyCode: "JPY",
            totalPaidMinor: 1_000,
            billCount: 1,
            participantNames: ["Linh"],
            note: nil,
            occurredAt: now,
            lastUpdatedAt: now
        )
    }
}
