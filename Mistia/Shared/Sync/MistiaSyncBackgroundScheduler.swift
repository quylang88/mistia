import BackgroundTasks
import Foundation

@MainActor
final class MistiaSyncBackgroundScheduler {
    static let shared = MistiaSyncBackgroundScheduler()
    static let taskIdentifier = "vn.com.quyln.mistia.sync.refresh"

    private weak var sessionStore: SessionStore?
    private var isRegistered = false

    private init() {}

    func registerIfNeeded(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        guard !isRegistered else { return }
        isRegistered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor [weak self] in
                await self?.handle(refreshTask: refreshTask)
            }
        }
    }

    func scheduleNextRefresh(after earliestBeginDate: Date?) {
        guard isRegistered else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        if let earliestBeginDate {
            request.earliestBeginDate = max(earliestBeginDate, Date().addingTimeInterval(60))
        } else {
            request.earliestBeginDate = Date().addingTimeInterval(60)
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("MistiaSyncBackgroundScheduler: failed to submit refresh task: \(error)")
            #endif
        }
    }

    func cancelPendingRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handle(refreshTask: BGAppRefreshTask) async {
        scheduleNextRefresh(after: sessionStore?.nextAutomaticSyncDate)

        let operation = Task { @MainActor [weak self] in
            await self?.sessionStore?.handleBackgroundRefresh() ?? false
        }

        refreshTask.expirationHandler = {
            operation.cancel()
        }

        let success = await operation.value
        refreshTask.setTaskCompleted(success: success)
        scheduleNextRefresh(after: sessionStore?.nextAutomaticSyncDate)
    }
}
