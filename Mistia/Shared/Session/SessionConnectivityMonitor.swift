import Foundation
import Network

enum SessionNetworkStatus: Equatable {
    case checking
    case connected
    case disconnected
}

final class SessionConnectivityMonitor {
    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "vn.com.quyln.mistia.session-connectivity")

    var onStatusChange: ((SessionNetworkStatus) -> Void)?
    private(set) var currentStatus: SessionNetworkStatus = .checking

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    init(initialStatus: SessionNetworkStatus) {
        monitor = nil
        currentStatus = initialStatus
    }

    func start() {
        guard let monitor else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let nextStatus: SessionNetworkStatus = switch path.status {
            case .satisfied:
                .connected
            case .unsatisfied, .requiresConnection:
                .disconnected
            @unknown default:
                .checking
            }

            guard nextStatus != self.currentStatus else { return }
            self.currentStatus = nextStatus

            DispatchQueue.main.async {
                self.onStatusChange?(nextStatus)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
    }
}
