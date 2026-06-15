import XCTest
@testable import MistiaCoreLogic

final class BillWorkflowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MistiaAppLanguage.persist(.vietnamese, defaults: UserDefaults.standard)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MistiaAppLanguage.backupUserDefaultsKey)
        super.tearDown()
    }

    // Phase 1: Date Format Fix
    func testDateFormatFixes() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 10
        components.hour = 12
        let date = calendar.date(from: components)!

        let shortString = MistiaDateFormatting.shortDateString(for: date, calendar: calendar)
        XCTAssertEqual(shortString, "10/05", "Short date string must use literal slash dd/MM format.")

        let fullDateString = MistiaDateFormatting.fullDateString(for: date, calendar: calendar)
        XCTAssertEqual(fullDateString, "10/05/2026", "Full date string must use literal slash dd/MM/yyyy format in Vietnamese.")
    }

    // Phase 2: Enum Extensions & Metadata
    func testMistiaAppNotificationKindCases() {
        XCTAssertEqual(MistiaAppNotificationKind.billPaymentRequired.rawValue, "billPaymentRequired")
        XCTAssertEqual(MistiaAppNotificationKind.billAutoPaymentSucceeded.rawValue, "billAutoPaymentSucceeded")
        XCTAssertEqual(MistiaAppNotificationKind.billAutoPaymentFailed.rawValue, "billAutoPaymentFailed")
        XCTAssertEqual(MistiaAppNotificationKind.billOverdue.rawValue, "billOverdue")
    }

    func testMistiaFamilyNotificationResourceTypeCases() {
        XCTAssertEqual(MistiaFamilyNotificationResourceType.bill.rawValue, "bill")
        XCTAssertEqual(MistiaFamilyNotificationResourceType.familyTransfer.rawValue, "family_transfer")
        XCTAssertEqual(MistiaFamilyNotificationResourceType.event.rawValue, "event")
        XCTAssertEqual(MistiaFamilyNotificationResourceType.event.localizedName, "Sự kiện")
    }

    func testLegacyRemoteCreditCardProfileDecodesAutoPayEnabledAsTrue() throws {
        let json = """
        {
          "user_id": "10000000-0000-4000-8000-000000000001",
          "id": "10000000-0000-4000-8000-000000000101",
          "issuer_name": "Visa",
          "network_raw_value": "visa",
          "last4": "1234",
          "credit_limit_minor": 120000,
          "statement_closing_day": 25,
          "payment_due_day": 10,
          "notes": null,
          "wallet_id": "10000000-0000-4000-8000-000000000201",
          "payment_source_wallet_id": "10000000-0000-4000-8000-000000000202",
          "created_at": "2026-05-01T00:00:00Z",
          "updated_at": "2026-05-01T00:00:00Z",
          "deleted_at": null,
          "sync_version": 7,
          "last_modified_by_device_id": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.mistiaRemoteAPIDecoder.decode(RemoteCreditCardProfile.self, from: json)

        XCTAssertTrue(decoded.autoPayEnabled)
    }

    // Phase 2: Overview Typed Routing Metadata
    func testOverviewDueAlertSnapshotMetadata() {
        let snapshot = OverviewDueAlertSnapshot(
            id: UUID().uuidString,
            name: "Test Bill",
            iconSymbolName: "doc",
            amountMinor: 1000,
            dueDate: Date(),
            dayDelta: 0,
            currencyCode: "VND",
            tint: .red,
            sourceKind: .recurringBill,
            sourceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            dueMonthKey: "2026-05",
            requiresAmountInput: true
        )

        XCTAssertEqual(snapshot.sourceKind, .recurringBill)
        XCTAssertEqual(snapshot.sourceID, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(snapshot.dueMonthKey, "2026-05")
        XCTAssertTrue(snapshot.requiresAmountInput)
    }

    // Phase 2: DueNotificationActionPayload
    func testDueNotificationActionPayload() throws {
        let sourceID = UUID()
        let payload = DueNotificationActionPayload(
            sourceKind: "recurringBill",
            sourceID: sourceID,
            dueMonthKey: "2026-05",
            dueDate: Date(timeIntervalSince1970: 0),
            requiresAmountInput: false,
            currencyCode: "USD",
            billName: "Test Name",
            linkedPaymentWalletID: nil
        )
        
        let encoder = JSONEncoder.mistiaSyncEncoder
        let data = try encoder.encode(payload)
        
        let decoder = JSONDecoder.mistiaSyncDecoder
        let decoded = try decoder.decode(DueNotificationActionPayload.self, from: data)
        
        XCTAssertEqual(decoded.sourceKind, "recurringBill")
        XCTAssertEqual(decoded.sourceID, sourceID)
        XCTAssertEqual(decoded.dueMonthKey, "2026-05")
        XCTAssertEqual(decoded.requiresAmountInput, false)
        XCTAssertEqual(decoded.currencyCode, "USD")
        XCTAssertEqual(decoded.billName, "Test Name")
        XCTAssertNil(decoded.linkedPaymentWalletID)
    }
}
