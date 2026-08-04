import XCTest
#if canImport(Mistia)
@testable import Mistia
#elseif canImport(MistiaCoreLogic)
@testable import MistiaCoreLogic
#endif

final class FeedbackPromptCoordinatorTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FeedbackPromptCoordinatorTests_\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if let suiteName = suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        super.tearDown()
    }

    @MainActor
    func testShouldNotPresentPromptIfLaunchCountIsLessThanFive() {
        let coordinator = FeedbackPromptCoordinator(userDefaults: userDefaults)
        let installDate = Date().addingTimeInterval(-4 * 86400)
        coordinator.setFirstInstallDateForTesting(installDate)
        coordinator.recordAppLaunch() // count = 1
        XCTAssertFalse(coordinator.shouldPresentPrompt(now: Date()))
    }

    @MainActor
    func testShouldPresentPromptWhenMilestonesMet() {
        let coordinator = FeedbackPromptCoordinator(userDefaults: userDefaults)
        
        let installDate = Date().addingTimeInterval(-4 * 86400) // 4 days ago
        coordinator.setFirstInstallDateForTesting(installDate)
        
        for _ in 1...5 {
            coordinator.recordAppLaunch()
        }
        
        XCTAssertTrue(coordinator.shouldPresentPrompt(now: Date()))
    }

    @MainActor
    func testShouldNotPresentPromptWhenOptedOut() {
        let coordinator = FeedbackPromptCoordinator(userDefaults: userDefaults)
        let installDate = Date().addingTimeInterval(-4 * 86400)
        coordinator.setFirstInstallDateForTesting(installDate)
        for _ in 1...5 { coordinator.recordAppLaunch() }

        coordinator.recordPromptResponded(optOut: true)
        XCTAssertFalse(coordinator.shouldPresentPrompt(now: Date()))
    }

    @MainActor
    func testShouldNotPresentPromptDuring60DayCooldown() {
        let coordinator = FeedbackPromptCoordinator(userDefaults: userDefaults)
        let now = Date()
        let installDate = now.addingTimeInterval(-10 * 86400)
        coordinator.setFirstInstallDateForTesting(installDate)

        for _ in 1...5 {
            coordinator.recordAppLaunch()
        }

        coordinator.recordPromptResponded(optOut: false)
        let fiveDaysAgo = now.addingTimeInterval(-5 * 86400)
        userDefaults.set(fiveDaysAgo, forKey: FeedbackPromptCoordinator.Keys.lastPromptDate)

        XCTAssertFalse(coordinator.shouldPresentPrompt(now: now))

        let sixtyOneDaysLater = fiveDaysAgo.addingTimeInterval(61 * 86400)
        XCTAssertTrue(coordinator.shouldPresentPrompt(now: sixtyOneDaysLater))
    }
}
