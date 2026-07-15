import XCTest
@testable import Mistia

@MainActor
final class CreditCardAvailableCreditTests: XCTestCase {
    func testPlanningSnapshotUsesLedgerDebtAndLatestLimit() {
        let wallet = LedgerWallet(
            name: "Card",
            kind: .creditCard,
            iconSymbolName: LedgerWalletKind.creditCard.defaultIconSymbolName,
            iconColorHex: LedgerWalletKind.creditCard.defaultColorHex,
            openingBalanceMinor: 46_058
        )
        let profile = CreditCardProfile(
            creditLimitMinor: 350_000,
            wallet: wallet
        )
        wallet.creditCardProfile = profile
        let occurredAt = Date(timeIntervalSince1970: 1_783_728_000)
        let purchase = TransactionRecordSnapshot(
            id: UUID(),
            primaryKind: .expense,
            transferSubtype: nil,
            debtIntent: nil,
            entryStatus: .posted,
            title: "Purchase",
            note: nil,
            amountMinor: 25_916,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            sourceWalletID: wallet.id,
            sourceWalletKind: .creditCard,
            destinationWalletID: nil,
            destinationWalletKind: nil,
            categoryID: UUID(),
            counterpartyName: nil,
            normalizedCounterpartyKey: nil
        )

        let snapshot = wallet.planningCreditCardSnapshot(
            records: [purchase],
            occurrences: []
        )

        XCTAssertEqual(snapshot?.currentDebtMinor, 25_916)
        XCTAssertEqual(snapshot?.availableCreditMinor, 324_084)
    }
}
