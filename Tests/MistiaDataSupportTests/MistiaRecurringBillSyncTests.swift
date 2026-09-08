import Foundation
import XCTest
@testable import MistiaCoreLogic

final class MistiaRecurringBillSyncTests: XCTestCase {
    func testEveryEditableBillFieldChangesPayloadFingerprint() throws {
        let original = makeBill()
        let fingerprint = MistiaSyncUploadRecord.recurringBillPlan(original).payloadFingerprint
        let changes: [(String, (inout RemoteRecurringBillPlan) -> Void)] = [
            ("name", { $0.name = "Updated bill" }),
            ("icon", { $0.iconSymbolName = "house" }),
            ("category", { $0.categoryID = UUID() }),
            ("amount", { $0.amountMinor = 8_000 }),
            ("clear amount", { $0.amountMinor = nil }),
            ("due day", { $0.dueDay = 20 }),
            ("schedule kind", { $0.scheduleKindRawValue = "oneTime" }),
            ("payment start day", { $0.paymentStartDay = 7 }),
            ("payment start date", { $0.paymentStartDate = $0.createdAt }),
            ("first scheduled month", { $0.firstScheduledMonth = $0.createdAt }),
            ("explicit deadline", { $0.hasExplicitDueDate = true }),
            ("due date", { $0.dueDate = $0.createdAt }),
            ("auto pay", { $0.autoPayEnabled = true }),
            ("auto pay day", { $0.autoPayDay = 10 }),
            ("auto pay date", { $0.autoPayDate = $0.createdAt }),
            ("frequency", { $0.frequencyMonths = 3 }),
            ("payment wallet", { $0.paymentWalletID = UUID() }),
            ("currency", { $0.currencyCode = "VND" }),
            ("archive", { $0.isArchived = true }),
            ("pause", { $0.isPaused = true }),
            ("paused at", { $0.pausedAt = $0.createdAt }),
            ("resume month", { $0.resumeStartMonth = $0.createdAt }),
            ("delete", { $0.deletedAt = $0.createdAt })
        ]

        for (field, change) in changes {
            var edited = original
            change(&edited)
            XCTAssertNotEqual(
                fingerprint,
                MistiaSyncUploadRecord.recurringBillPlan(edited).payloadFingerprint,
                "Sync must recognize an edit to \(field)"
            )
        }
    }

    func testClearedOptionalFieldsAreExplicitNullsInUploadPayload() throws {
        var bill = makeBill()
        bill.amountMinor = nil
        bill.scheduleKindRawValue = nil
        bill.paymentStartDay = nil
        bill.hasExplicitDueDate = nil
        bill.autoPayEnabled = nil
        let data = try JSONEncoder.mistiaRemoteAPIEncoder.encode(bill)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for column in [
            "category_id", "amount_minor", "schedule_kind_raw_value", "payment_start_day",
            "payment_start_date", "first_scheduled_month", "has_explicit_due_date", "due_date",
            "auto_pay_enabled", "auto_pay_day", "auto_pay_date", "payment_wallet_id",
            "paused_at", "resume_start_month", "deleted_at", "last_modified_by_device_id"
        ] {
            XCTAssertTrue(payload[column] is NSNull, "Clearing \(column) must reach the server")
        }
    }

    func testSyncMetadataDoesNotChangePayloadFingerprint() {
        let original = makeBill()
        var updated = original
        updated.syncVersion += 1
        updated.updatedAt = original.updatedAt.addingTimeInterval(60)
        updated.lastModifiedByDeviceID = UUID()
        XCTAssertEqual(
            MistiaSyncUploadRecord.recurringBillPlan(original).payloadFingerprint,
            MistiaSyncUploadRecord.recurringBillPlan(updated).payloadFingerprint
        )
    }

    func testLegacyBillWithoutScheduleAndPauseFieldsStillDecodes() throws {
        let data = try JSONEncoder.mistiaRemoteAPIEncoder.encode(makeBill())
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for column in [
            "schedule_kind_raw_value", "payment_start_day", "payment_start_date", "first_scheduled_month",
            "has_explicit_due_date", "due_date", "auto_pay_enabled", "auto_pay_day", "auto_pay_date",
            "is_paused", "paused_at", "resume_start_month"
        ] {
            payload.removeValue(forKey: column)
        }
        let decoded = try JSONDecoder.mistiaRemoteAPIDecoder.decode(
            RemoteRecurringBillPlan.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertEqual(decoded.amountMinor, 4_200)
        XCTAssertFalse(decoded.isPaused)
        XCTAssertNil(decoded.pausedAt)
        XCTAssertNil(decoded.resumeStartMonth)
        XCTAssertNil(decoded.scheduleKindRawValue)
    }

    private func makeBill() -> RemoteRecurringBillPlan {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        return RemoteRecurringBillPlan(
            userID: UUID(), id: UUID(), name: "Electricity", iconSymbolName: "bolt",
            amountMinor: 4_200, dueDay: 15, scheduleKindRawValue: "recurring",
            paymentStartDay: 5, hasExplicitDueDate: false, autoPayEnabled: false,
            frequencyMonths: 1, currencyCode: "JPY", isArchived: false, isPaused: false,
            createdAt: date, updatedAt: date, syncVersion: 1
        )
    }
}
