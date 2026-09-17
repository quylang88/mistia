import Foundation
import XCTest
@testable import Mistia

final class TransactionLogicSummaryPerformanceTests: XCTestCase {
    func testSummaryPerformance() {
        let count = 100_000
        var records: [TransactionRecordSnapshot] = []
        records.reserveCapacity(count)

        let now = Date()

        for i in 0..<count {
            let kind: TransactionPrimaryKind = i % 3 == 0 ? .income : (i % 3 == 1 ? .expense : .transfer)
            let status: TransactionEntryStatus = i % 10 == 0 ? .draft : .posted

            records.append(
                TransactionRecordSnapshot(
                    id: UUID(),
                    primaryKind: kind,
                    transferSubtype: nil,
                    debtIntent: nil,
                    entryStatus: status,
                    title: "Test Transaction \(i)",
                    note: nil,
                    amountMinor: Int64(i * 10),
                    sourceCurrencyCode: "JPY",
                    occurredAt: now,
                    createdAt: now,
                    sourceWalletID: UUID(),
                    sourceWalletKind: .cash,
                    destinationWalletID: nil,
                    destinationWalletKind: nil,
                    categoryID: UUID(),
                    counterpartyName: nil,
                    normalizedCounterpartyKey: nil
                )
            )
        }

        measure {
            _ = TransactionLogic.summary(for: records)
        }
    }
}
