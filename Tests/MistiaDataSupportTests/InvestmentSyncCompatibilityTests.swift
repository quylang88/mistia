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

    func testLegacyInvestmentAssetPayloadDecodesWithoutImagePath() throws {
        let payload = """
        {
          "id": "20000000-0000-4000-8000-000000000002",
          "user_id": "10000000-0000-4000-8000-000000000001",
          "channel_id": "30000000-0000-4000-8000-000000000001",
          "name": "Card A",
          "currency_code": "JPY",
          "sort_order": 0,
          "is_archived": false,
          "created_at": "2026-08-09T00:00:00.000Z",
          "updated_at": "2026-08-09T00:00:00.000Z",
          "sync_version": 1
        }
        """

        let asset = try JSONDecoder.mistiaRemoteAPIDecoder.decode(
            RemoteInvestmentAsset.self,
            from: Data(payload.utf8)
        )

        XCTAssertNil(asset.imagePath)
        XCTAssertNil(asset.defaultUnitLabel)
    }

    func testLegacyInvestmentTradePayloadDecodesWithoutUnitLabel() throws {
        let trade = InvestmentTrade(
            ownerUserID: UUID(),
            channelID: UUID(),
            assetID: UUID(),
            kind: .buy,
            quantity: 1,
            unitLabel: "pack",
            grossAmountMinor: 100,
            currencyCode: "JPY",
            accountingGrossAmountMinor: 100,
            accountingCurrencyCode: "JPY"
        )
        let encoded = try JSONEncoder.mistiaRemoteAPIEncoder.encode(RemoteInvestmentTrade(local: trade))
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        payload.removeValue(forKey: "unit_label")

        let decoded = try JSONDecoder.mistiaRemoteAPIDecoder.decode(
            RemoteInvestmentTrade.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertNil(decoded.unitLabel)
        XCTAssertEqual(decoded.grossAmountMinor, 100)
    }

    func testLegacyBackupSnapshotIgnoresRemovedInvestmentValuations() throws {
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
          "dueOccurrences": [],
          "investmentChannels": [],
          "investmentAssets": [],
          "investmentTrades": [],
          "investmentValuations": [
            {"id":"20000000-0000-4000-8000-000000000099","marketValueMinor":999}
          ],
          "investmentPostings": []
        }
        """

        let snapshot = try JSONDecoder().decode(
            MistiaRemoteSnapshot.self,
            from: Data(payload.utf8)
        )

        XCTAssertTrue(snapshot.investmentAssets.isEmpty)
        XCTAssertTrue(snapshot.investmentTrades.isEmpty)
        XCTAssertTrue(snapshot.investmentPostings.isEmpty)
    }

    func testInvestmentAssetEncodingWithNilImagePathIncludesExplicitNull() throws {
        let asset = RemoteInvestmentAsset(
            userID: UUID(),
            id: UUID(),
            channelID: UUID(),
            name: "Gold Bar",
            currencyCode: "JPY",
            imagePath: nil,
            defaultUnitLabel: nil,
            sortOrder: 0,
            isArchived: false,
            archivedAt: nil,
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil,
            syncVersion: 1,
            lastModifiedByDeviceID: nil
        )

        let data = try JSONEncoder.mistiaRemoteAPIEncoder.encode(asset)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        XCTAssertTrue(jsonObject?["image_path"] is NSNull, "Expected image_path to be explicitly encoded as null so database updates clear the column")
    }

    func testInvestmentAssetEncodingWithImagePathIncludesValue() throws {
        let expectedPath = "owner-id/asset-id/image.jpg"
        let asset = RemoteInvestmentAsset(
            userID: UUID(),
            id: UUID(),
            channelID: UUID(),
            name: "Gold Bar",
            currencyCode: "JPY",
            imagePath: expectedPath,
            defaultUnitLabel: "bar",
            sortOrder: 0,
            isArchived: false,
            archivedAt: nil,
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil,
            syncVersion: 1,
            lastModifiedByDeviceID: nil
        )

        let data = try JSONEncoder.mistiaRemoteAPIEncoder.encode(asset)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["image_path"] as? String, expectedPath)
        XCTAssertEqual(jsonObject?["default_unit_label"] as? String, "bar")
    }

    func testInvestmentAssetPayloadFingerprintIncludesDefaultUnitLabelAndMetadata() {
        let baseAsset = RemoteInvestmentAsset(
            userID: UUID(),
            id: UUID(),
            channelID: UUID(),
            name: "Gold Bar",
            currencyCode: "JPY",
            imagePath: nil,
            defaultUnitLabel: nil,
            sortOrder: 0,
            isArchived: false,
            archivedAt: nil,
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil,
            syncVersion: 1,
            lastModifiedByDeviceID: nil
        )

        var assetWithUnit = baseAsset
        assetWithUnit.defaultUnitLabel = "g"

        var assetWithSortOrder = baseAsset
        assetWithSortOrder.sortOrder = 5

        var assetWithArchivedAt = baseAsset
        assetWithArchivedAt.archivedAt = Date(timeIntervalSince1970: 100_000)

        let baseFingerprint = MistiaSyncUploadRecord.investmentAsset(baseAsset).payloadFingerprint
        let unitFingerprint = MistiaSyncUploadRecord.investmentAsset(assetWithUnit).payloadFingerprint
        let sortFingerprint = MistiaSyncUploadRecord.investmentAsset(assetWithSortOrder).payloadFingerprint
        let archivedFingerprint = MistiaSyncUploadRecord.investmentAsset(assetWithArchivedAt).payloadFingerprint

        XCTAssertNotEqual(baseFingerprint, unitFingerprint, "Adding or editing defaultUnitLabel must change the payloadFingerprint")
        XCTAssertNotEqual(baseFingerprint, sortFingerprint, "Changing sortOrder must change the payloadFingerprint")
        XCTAssertNotEqual(baseFingerprint, archivedFingerprint, "Changing archivedAt must change the payloadFingerprint")
    }

    func testInvestmentTradePayloadFingerprintIncludesUnitLabelAndAccountingDetails() {
        let baseTrade = RemoteInvestmentTrade(
            userID: UUID(),
            id: UUID(),
            channelID: UUID(),
            assetID: UUID(),
            kindRawValue: InvestmentTradeKind.buy.rawValue,
            quantityDecimalString: "10",
            unitLabel: nil,
            grossAmountMinor: 100_000,
            currencyCode: "VND",
            accountingGrossAmountMinor: 100_000,
            accountingCurrencyCode: "VND",
            exchangeRateDecimalString: nil,
            exchangeRateProvider: nil,
            exchangeRateDate: nil,
            fundingWalletID: nil,
            capitalReturnWalletID: nil,
            fundingWalletCurrencyCode: nil,
            capitalReturnWalletCurrencyCode: nil,
            fundingWalletAmountMinor: nil,
            capitalReturnWalletAmountMinor: nil,
            fundingToAccountingRateDecimalString: nil,
            accountingToCapitalReturnRateDecimalString: nil,
            fundingLedgerTransactionID: nil,
            capitalReturnLedgerTransactionID: nil,
            profitLossLedgerTransactionID: nil,
            releasedCostBasisMinor: 0,
            realizedProfitLossMinor: 0,
            positionQuantityAfterDecimalString: "10",
            positionCostBasisAfterMinor: 100_000,
            note: nil,
            occurredAt: Date(timeIntervalSince1970: 1_000_000),
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil,
            syncVersion: 1,
            lastModifiedByDeviceID: nil
        )

        var tradeWithUnit = baseTrade
        tradeWithUnit.unitLabel = "cổ"

        var tradeWithNote = baseTrade
        tradeWithNote.note = "DCA monthly"

        let baseFingerprint = MistiaSyncUploadRecord.investmentTrade(baseTrade).payloadFingerprint
        let unitFingerprint = MistiaSyncUploadRecord.investmentTrade(tradeWithUnit).payloadFingerprint
        let noteFingerprint = MistiaSyncUploadRecord.investmentTrade(tradeWithNote).payloadFingerprint

        XCTAssertNotEqual(baseFingerprint, unitFingerprint, "Adding or changing unitLabel must change trade payloadFingerprint")
        XCTAssertNotEqual(baseFingerprint, noteFingerprint, "Adding or changing note must change trade payloadFingerprint")
    }
}
