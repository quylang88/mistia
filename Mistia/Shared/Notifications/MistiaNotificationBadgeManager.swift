import UserNotifications

@MainActor
enum MistiaNotificationBadgeManager {
    static func setBadgeCount(_ count: Int) {
        let center = UNUserNotificationCenter.current()
        center.setBadgeCount(count) { error in
            if let error {
                #if DEBUG
                print("Failed to set badge count: \(error)")
                #endif
            }
        }
    }
}
