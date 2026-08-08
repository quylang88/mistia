import Foundation
import XCTest
@testable import MistiaCoreLogic

final class InvestmentSyncCompatibilityTests: XCTestCase {
    func testPreInvestmentSnapshotDecodesWithEmptyInvestmentCollections() throws {
        let payload = """
        {
          "wallets": [],
          "creditCardProfiles": [],
          "categories": [],
          "settlementGroups": [],
          "transactions": [],
          "budgetPlans": [],
          "savingsGoals": [],
          "recurringBillPlans": [],
          "installmentPlans": [],
          "dueOccurrences": []
        }
        """

        let snapshot = try JSONDecoder().decode(
            MistiaRemoteSnapshot.self,
            from: Data(payload.utf8)
        )

        XCTAssertTrue(snapshot.investmentChannels.isEmpty)
        XCTAssertTrue(snapshot.investmentAssets.isEmpty)
        XCTAssertTrue(snapshot.investmentTrades.isEmpty)
        XCTAssertTrue(snapshot.investmentValuations.isEmpty)
        XCTAssertTrue(snapshot.investmentPostings.isEmpty)
    }

    func testPreInvestmentWalletPayloadDecodesWithoutSystemPurpose() throws {
        let payload = """
        {
          "user_id": "10000000-0000-4000-8000-000000000001",
          "id": "20000000-0000-4000-8000-000000000001",
          "name": "Cash",
          "kind_raw_value": "cash",
          "icon_symbol_name": "banknote.fill",
          "icon_color_hex": "#000000",
          "currency_code": "JPY",
          "opening_balance_minor": 100,
          "sort_order": 0,
          "is_archived": false,
          "created_at": "2026-08-09T00:00:00.000Z",
          "updated_at": "2026-08-09T00:00:00.000Z",
          "sync_version": 1
        }
        """

        let wallet = try JSONDecoder.mistiaRemoteAPIDecoder.decode(
            RemoteLedgerWallet.self,
            from: Data(payload.utf8)
        )

        XCTAssertNil(wallet.systemPurposeRawValue)
    }
}
