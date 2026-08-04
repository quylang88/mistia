import Foundation
import Combine

@MainActor
public final class FeedbackPromptCoordinator: ObservableObject {
    public static let shared = FeedbackPromptCoordinator()

    private let userDefaults: UserDefaults

    public enum Keys {
        public static let launchCount = "mistia_feedback_launch_count"
        public static let firstInstallDate = "mistia_feedback_first_install_date"
        public static let lastPromptDate = "mistia_feedback_last_prompt_date"
        public static let optedOut = "mistia_feedback_opted_out"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Keys.firstInstallDate) == nil {
            userDefaults.set(Date(), forKey: Keys.firstInstallDate)
        }
    }

    public func recordAppLaunch() {
        let count = userDefaults.integer(forKey: Keys.launchCount) + 1
        userDefaults.set(count, forKey: Keys.launchCount)
    }

    public func shouldPresentPrompt(now: Date = Date()) -> Bool {
        if userDefaults.bool(forKey: Keys.optedOut) { return false }

        let launchCount = userDefaults.integer(forKey: Keys.launchCount)
        guard launchCount >= 5 else { return false }

        guard let firstInstall = userDefaults.object(forKey: Keys.firstInstallDate) as? Date else { return false }
        let daysSinceInstall = now.timeIntervalSince(firstInstall)
        guard daysSinceInstall >= 3 * 86400 else { return false }

        if let lastPrompt = userDefaults.object(forKey: Keys.lastPromptDate) as? Date {
            let secondsSinceLastPrompt = now.timeIntervalSince(lastPrompt)
            if secondsSinceLastPrompt < 60 * 86400 { return false }
        }

        return true
    }

    public func recordPromptResponded(optOut: Bool = false) {
        userDefaults.set(Date(), forKey: Keys.lastPromptDate)
        if optOut {
            userDefaults.set(true, forKey: Keys.optedOut)
        }
    }

    public func setFirstInstallDateForTesting(_ date: Date) {
        userDefaults.set(date, forKey: Keys.firstInstallDate)
    }
}
