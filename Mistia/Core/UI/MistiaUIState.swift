import SwiftUI
import Observation

enum MistiaManagementNavigationDestination: Equatable {
    case backupRestore
    case archivedItems
    case familyOverview
}

struct MistiaManagementNavigationRequest: Identifiable, Equatable {
    let id: UUID
    let destination: MistiaManagementNavigationDestination

    init(destination: MistiaManagementNavigationDestination) {
        self.id = UUID()
        self.destination = destination
    }
}

@Observable
final class MistiaUIState {
    var isTabBarHidden: Bool = false
    var isQuickCreateHidden: Bool = false
    var quickCreateMenuRequestID: UUID?
    var managementNavigationRequest: MistiaManagementNavigationRequest?
    
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

    func requestManagementNavigation(_ destination: MistiaManagementNavigationDestination) {
        managementNavigationRequest = MistiaManagementNavigationRequest(destination: destination)
    }

    func clearManagementNavigationRequest(id: UUID) {
        guard managementNavigationRequest?.id == id else { return }
        managementNavigationRequest = nil
    }
}
