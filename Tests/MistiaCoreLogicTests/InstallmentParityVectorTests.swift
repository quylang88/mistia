import Foundation
import XCTest
@testable import MistiaCoreLogic

final class InstallmentParityVectorTests: XCTestCase {
    private struct Document: Decodable { let version: Int; let owner: String; let cases: [Vector] }
    private struct Vector: Decodable {
        let name: String; let month: String; let zone: String
        let plans: [Plan]; let occurrences: [Occurrence]; let expected: [Expected]
    }
    private struct Plan: Decodable {
        let id: String; let owner: String; let name: String; let icon: String
        let amount: Int64; let dueDay: Int; let totalCycles: Int?; let frequency: Int
        let paymentWallet: String?; let currency: String; let createdAt: String; let archived: Bool; let deleted: Bool
    }
    private struct Occurrence: Decodable {
        let owner: String; let sourceKind: String; let sourceId: String; let month: String
        let amount: Int64?; let status: String; let linked: String?; let deleted: Bool
    }
    private struct Expected: Decodable {
        let id: String; let name: String; let amount: Int64; let currency: String; let due: String
        let status: String; let linked: String?; let paymentWallet: String?; let frequency: Int; let totalCycles: Int?
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testSharedAndroidInstallmentCalendarAndOccurrenceVectors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: root.appendingPathComponent("contracts/golden/installment-due-v1.json")))
        XCTAssertEqual(doc.version, 1)
        for vector in doc.cases {
            let calendar = MistiaCalendar.gregorian(timeZone: TimeZone(identifier: vector.zone)!)
            let parts = vector.month.split(separator: "-")
            let month = calendar.date(from: DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: 1))!
            // Match PlanningView's personal subject, live query and !isArchived visibility before the pure Swift engine.
            let plans = vector.plans.filter { $0.owner == doc.owner && !$0.deleted && !$0.archived }.map { p in
                PlanningInstallmentSnapshot(id: UUID(uuidString: p.id)!, name: p.name, iconSymbolName: p.icon,
                    amountPerCycleMinor: p.amount, dueDay: p.dueDay, totalCycles: p.totalCycles, frequencyMonths: p.frequency,
                    paymentWalletID: p.paymentWallet.flatMap(UUID.init(uuidString:)), currencyCode: p.currency, createdAt: date(p.createdAt))
            }
            let occurrences = vector.occurrences.filter { $0.owner == doc.owner && !$0.deleted }.map { p in
                PlanningDueOccurrenceSnapshot(id: UUID(), sourceKind: PlanningDueSourceKind(rawValue: p.sourceKind) ?? .creditCard,
                    sourceID: UUID(uuidString: p.sourceId)!, selectedMonthKey: p.month, scheduledDate: date("2035-01-01T00:00:00Z"),
                    amountMinorSnapshot: p.amount, status: PlanningDueOccurrenceStatus(rawValue: p.status) ?? .pending,
                    linkedTransactionID: p.linked.flatMap(UUID.init(uuidString:)))
            }
            let rows = PlanningLogic.installmentDueItems(plans: plans, occurrences: occurrences, selectedMonth: month, calendar: calendar)
            XCTAssertEqual(rows.count, vector.expected.count, vector.name)
            for (actual, expected) in zip(rows, vector.expected) {
                XCTAssertEqual(actual.sourceID.uuidString.lowercased(), expected.id, vector.name)
                XCTAssertEqual(actual.sourceKind, .installment, vector.name)
                XCTAssertEqual(actual.categorySystemKey, .loanRepayment, vector.name)
                XCTAssertEqual(actual.name, expected.name, vector.name)
                XCTAssertEqual(actual.amountMinor, expected.amount, vector.name)
                XCTAssertEqual(actual.currencyCode, expected.currency, vector.name)
                XCTAssertEqual(actual.dueDate, date(expected.due), vector.name)
                XCTAssertEqual(actual.status.rawValue, expected.status, vector.name)
                XCTAssertEqual(actual.linkedTransactionID?.uuidString.lowercased(), expected.linked, vector.name)
                XCTAssertEqual(actual.paymentWalletID?.uuidString.lowercased(), expected.paymentWallet, vector.name)
                XCTAssertEqual(actual.frequencyMonths, expected.frequency, vector.name)
                XCTAssertEqual(actual.totalCycles, expected.totalCycles, vector.name)
            }
        }
    }
}
