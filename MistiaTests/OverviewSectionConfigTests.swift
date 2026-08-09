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

    func testRemoteMemberConfigKeepsRemoteOrderAndVisibility() {
        let remoteItems = [
            RemoteOverviewSectionItemConfig(kind: OverviewSectionKind.recentTransactions.rawValue, isVisible: false),
            RemoteOverviewSectionItemConfig(kind: OverviewSectionKind.investment.rawValue, isVisible: true)
        ]

        let decoded = OverviewSectionConfigStorage.decode(remoteItems: remoteItems)

        XCTAssertEqual(decoded.first?.kind, .recentTransactions)
        XCTAssertFalse(decoded.first?.isVisible ?? true)
        XCTAssertEqual(decoded.dropFirst().first?.kind, .investment)
        XCTAssertTrue(decoded.dropFirst().first?.isVisible ?? false)
        XCTAssertEqual(decoded.count, OverviewSectionKind.allCases.count)
    }

    func testPreferenceSyncUploadsNewerLocalConfig() {
        let local = OverviewSectionPreferenceSnapshot(
            items: [RemoteOverviewSectionItemConfig(kind: "investment", isVisible: false)],
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let remote = OverviewSectionPreferenceSnapshot(
            items: [RemoteOverviewSectionItemConfig(kind: "investment", isVisible: true)],
            modifiedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            OverviewSectionPreferenceSyncResolver.resolve(local: local, remote: remote),
            .upload(local)
        )
    }

    func testPreferenceSyncAppliesNewerRemoteConfig() {
        let local = OverviewSectionPreferenceSnapshot(
            items: [RemoteOverviewSectionItemConfig(kind: "investment", isVisible: false)],
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let remote = OverviewSectionPreferenceSnapshot(
            items: [RemoteOverviewSectionItemConfig(kind: "investment", isVisible: true)],
            modifiedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            OverviewSectionPreferenceSyncResolver.resolve(local: local, remote: remote),
            .applyRemote(remote)
        )
    }

    func testUnversionedLegacyPreferenceDoesNotOverwriteCloud() {
        let legacyLocal = OverviewSectionPreferenceSnapshot(
            items: [RemoteOverviewSectionItemConfig(kind: "budgetFocus", isVisible: false)],
            modifiedAt: nil
        )
        let remote = OverviewSectionPreferenceSnapshot(
            items: [RemoteOverviewSectionItemConfig(kind: "budgetFocus", isVisible: true)],
            modifiedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            OverviewSectionPreferenceSyncResolver.resolve(local: legacyLocal, remote: remote),
            .applyRemote(remote)
        )
    }

    func testLocalPreferencesAreNamespacedPerProfile() throws {
        let suiteName = "OverviewSectionConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let items = [RemoteOverviewSectionItemConfig(kind: "investment", isVisible: false)]

        try OverviewSectionPreferenceLocalStorage.save(
            items: items,
            modifiedAt: Date(timeIntervalSince1970: 100),
            for: firstProfileID,
            userDefaults: defaults
        )

        XCTAssertEqual(
            OverviewSectionPreferenceLocalStorage.snapshot(
                for: firstProfileID,
                userDefaults: defaults
            )?.items,
            items
        )
        XCTAssertNil(
            OverviewSectionPreferenceLocalStorage.snapshot(
                for: secondProfileID,
                userDefaults: defaults
            )
        )
    }

    func testCustomizeButtonIsVisibleOnlyInPersonalMode() {
        XCTAssertTrue(
            OverviewSectionCustomizationAvailability.isVisible(in: .personalSelf)
        )
        XCTAssertFalse(
            OverviewSectionCustomizationAvailability.isVisible(
                in: .familyHome(familyID: UUID())
            )
        )
        XCTAssertFalse(
            OverviewSectionCustomizationAvailability.isVisible(
                in: .member(userID: UUID())
            )
        )
    }
}
