import XCTest
@testable import Mistia

final class OverviewSectionConfigTests: XCTestCase {
    func testDefaultConfig() {
        let defaults = OverviewSectionItemConfig.defaultConfig
        XCTAssertEqual(defaults.count, 5)

        XCTAssertEqual(defaults.first?.kind, .investment, "Investment should be top 1 by default")
        XCTAssertTrue(defaults.first?.isVisible ?? false, "Investment should be visible by default")

        let budget = defaults.first { $0.kind == .budgetFocus }
        XCTAssertNotNil(budget)
        XCTAssertTrue(budget?.isVisible ?? false, "Budget section should be visible by default")
    }

    func testEncodingAndDecoding() throws {
        var items = OverviewSectionItemConfig.defaultConfig
        items[0].isVisible = false

        let data = try OverviewSectionConfigStorage.encode(items)
        let decoded = OverviewSectionConfigStorage.decode(from: data)

        XCTAssertEqual(decoded.count, 5)
        XCTAssertFalse(decoded.first { $0.kind == .investment }?.isVisible ?? true)
    }

    func testSanitizeRestoresMissingSections() {
        let incompleteData = try! JSONEncoder().encode([
            OverviewSectionItemConfig(kind: .budgetFocus, isVisible: true)
        ])
        let sanitized = OverviewSectionConfigStorage.decode(from: incompleteData)
        XCTAssertEqual(sanitized.count, 5, "Sanitizing incomplete stored config should append missing sections")
    }
}
