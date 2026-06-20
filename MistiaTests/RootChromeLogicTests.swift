import CoreGraphics
import XCTest
@testable import Mistia

final class RootChromeLogicTests: XCTestCase {
    func testQuickCreateVisibilityIgnoresLegacyPersistedHideFlag() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: MistiaAppStorageKey.hideQuickCreate)

        XCTAssertFalse(
            MistiaRootChromeLogic.hidesQuickCreate(
                transientHidden: false,
                menuVisible: false
            )
        )
    }

    func testQuickCreateVisibilityFollowsTransientChromeRequests() {
        XCTAssertTrue(
            MistiaRootChromeLogic.hidesQuickCreate(
                transientHidden: true,
                menuVisible: false
            )
        )

        XCTAssertTrue(
            MistiaRootChromeLogic.hidesQuickCreate(
                transientHidden: false,
                menuVisible: true
            )
        )
    }

    func testQuickCreatePresentationRequiresVisibleChromeAndMeasuredButtonFrame() {
        XCTAssertTrue(
            MistiaRootChromeLogic.canPresentQuickCreate(
                transientHidden: false,
                buttonFrame: CGRect(x: 320, y: 720, width: 44, height: 44)
            )
        )
        XCTAssertFalse(
            MistiaRootChromeLogic.canPresentQuickCreate(
                transientHidden: true,
                buttonFrame: CGRect(x: 320, y: 720, width: 44, height: 44)
            )
        )
        XCTAssertFalse(
            MistiaRootChromeLogic.canPresentQuickCreate(
                transientHidden: false,
                buttonFrame: .zero
            )
        )
    }

    func testLegacyPersistentChromeFlagIsClearedDuringStartupNormalization() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: MistiaAppStorageKey.hideQuickCreate)

        MistiaRootChromeLogic.normalizeLegacyPersistentFlags(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: MistiaAppStorageKey.hideQuickCreate))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RootChromeLogicTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
