import XCTest
@testable import Mistia

final class OverviewSectionConfigTests: XCTestCase {
    func testDefaultConfig() {
        let defaults = OverviewSectionItemConfig.defaultConfig
        XCTAssertEqual(defaults.count, 5)

        let investment = defaults.first { $0.kind == .investment }
        XCTAssertNotNil(investment)
        XCTAssertFalse(investment?.isVisible ?? true, "Investment should be hidden by default")

        let budget = defaults.first { $0.kind == .budgetFocus }
        XCTAssertNotNil(budget)
        XCTAssertTrue(budget?.isVisible ?? false, "Budget section should be visible by default")
    }

    func testEncodingAndDecoding() throws {
        var items = OverviewSectionItemConfig.defaultConfig
        items[4].isVisible = true

        let data = try OverviewSectionConfigStorage.encode(items)
        let decoded = OverviewSectionConfigStorage.decode(from: data)

        XCTAssertEqual(decoded.count, 5)
        XCTAssertTrue(decoded.first { $0.kind == .investment }?.isVisible ?? false)
    }

    func testSanitizeRestoresMissingSections() {
        let incompleteData = try! JSONEncoder().encode([
            OverviewSectionItemConfig(kind: .budgetFocus, isVisible: true)
        ])
        let sanitized = OverviewSectionConfigStorage.decode(from: incompleteData)
        XCTAssertEqual(sanitized.count, 5, "Sanitizing incomplete stored config should append missing sections")
    }
}
