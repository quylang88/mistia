import SwiftUI
import Observation

@Observable
final class MistiaUIState {
    var isTabBarHidden: Bool = false
    var isQuickCreateHidden: Bool = false
    var quickCreateMenuRequestID: UUID?
    
    // Support for multiple requests to hide (e.g. nested screens)
    private var hideRequests: Set<UUID> = []
    private var quickCreateHideRequests: Set<UUID> = []
    
    func requestTabBarHidden(_ isHidden: Bool, id: UUID) {
        if isHidden {
            hideRequests.insert(id)
        } else {
            hideRequests.remove(id)
        }
        isTabBarHidden = !hideRequests.isEmpty
    }

    func requestQuickCreateHidden(_ isHidden: Bool, id: UUID) {
        if isHidden {
            quickCreateHideRequests.insert(id)
        } else {
            quickCreateHideRequests.remove(id)
        }
        isQuickCreateHidden = !quickCreateHideRequests.isEmpty
    }

    func requestQuickCreateMenuPresentation() {
        quickCreateMenuRequestID = UUID()
    }
}
