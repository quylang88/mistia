import Foundation
import XCTest
@testable import MistiaCoreLogic

final class InvestmentAccountingParityVectorTests: XCTestCase {
    private struct Trade: Codable {
        let id: String; let kind: String; let quantity: String; let unitLabel: String?
        let gross: String; let occurredAt: String; let createdAt: String
    }
    private struct Calculation: Codable, Equatable {
        let id: String; let released: String; let profit: String; let quantity: String; let basis: String; let lots: Int
    }
    private struct Position: Codable, Equatable {
        let key: String; let label: String?; let quantity: String
    }
    private struct Expected: Codable, Equatable {
        let calculations: [Calculation]; let positions: [Position]; let error: String?
    }
    private struct Vector: Codable {
        let name: String; let trades: [Trade]; var expected: Expected
    }
    private struct UnitVector: Codable {
        let input: String?; var display: String?; var key: String
    }
    private struct Document: Codable {
        let version: Int; var units: [UnitVector]; var cases: [Vector]
    }
    private func evaluate(_ vector: Vector) throws -> Expected {
        let formatter = ISO8601DateFormatter()
        let inputs = try vector.trades.map { trade in
            InvestmentTradeInput(
                id: try XCTUnwrap(UUID(uuidString: trade.id)), kind: try XCTUnwrap(InvestmentTradeKind(rawValue: trade.kind)),
                quantity: try XCTUnwrap(Decimal(string: trade.quantity, locale: Locale(identifier: "en_US_POSIX"))),
                unitLabel: trade.unitLabel, accountingGrossAmountMinor: try XCTUnwrap(Int64(trade.gross)),
                occurredAt: try XCTUnwrap(formatter.date(from: trade.occurredAt)),
                createdAt: try XCTUnwrap(formatter.date(from: trade.createdAt))
            )
        }
        do {
            let projection = try InvestmentAccountingEngine.projection(trades: inputs)
            return Expected(calculations: projection.calculations.map {
                Calculation(id: $0.id.uuidString.lowercased(), released: String($0.releasedCostBasisMinor),
                            profit: String($0.realizedProfitLossMinor),
                            quantity: NSDecimalNumber(decimal: $0.positionQuantityAfter).stringValue,
                            basis: String($0.positionCostBasisAfterMinor), lots: $0.openLotCountAfter)
            }, positions: projection.unitPositions.map {
                Position(key: $0.unitKey.precomposedStringWithCanonicalMapping, label: $0.unitLabel,
                         quantity: NSDecimalNumber(decimal: $0.quantity).stringValue)
            }.sorted { $0.key < $1.key }, error: nil)
        } catch let error as InvestmentAccountingError {
            return Expected(calculations: [], positions: [], error: String(describing: error))
        }
    }
    func testSharedUnitAndFIFOVectorsAgainstActualSwiftEngine() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("contracts/golden/investment-accounting-v1.json")
        var document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        XCTAssertEqual(1, document.version); XCTAssertEqual(147, document.cases.count); XCTAssertEqual(32, document.units.count)
        if ProcessInfo.processInfo.environment["MISTIA_GENERATE_INVESTMENT_VECTORS"] == "1" {
            for index in document.units.indices {
                document.units[index].display = InvestmentUnitLabel.normalizedDisplay(document.units[index].input)
                document.units[index].key = InvestmentUnitLabel.comparisonKey(document.units[index].input).precomposedStringWithCanonicalMapping
            }
            for index in document.cases.indices {
                document.cases[index].expected = try evaluate(document.cases[index])
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try (encoder.encode(document) + Data("\n".utf8)).write(to: file, options: .atomic)
        }
        for unit in document.units {
            XCTAssertEqual(unit.display, InvestmentUnitLabel.normalizedDisplay(unit.input))
            XCTAssertEqual(unit.key, InvestmentUnitLabel.comparisonKey(unit.input).precomposedStringWithCanonicalMapping)
        }
        for vector in document.cases {
            XCTAssertEqual(vector.expected, try evaluate(vector), vector.name)
        }
    }
}
