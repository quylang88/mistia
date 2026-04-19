import SwiftUI
import Observation

@Observable
final class MistiaUIState {
    var isTabBarHidden: Bool = false
    
    // Support for multiple requests to hide (e.g. nested screens)
    private var hideRequests: Set<UUID> = []
    
    func requestTabBarHidden(_ isHidden: Bool, id: UUID) {
        if isHidden {
            hideRequests.insert(id)
        } else {
            hideRequests.remove(id)
        }
        isTabBarHidden = !hideRequests.isEmpty
    }
}
