import BackgroundTasks
import Foundation
import os

@MainActor
final class MistiaSyncBackgroundScheduler {
    static let shared = MistiaSyncBackgroundScheduler()
    static let taskIdentifier = "vn.com.quyln.mistia.sync.refresh"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Mistia", category: "BackgroundSync")
    private weak var sessionStore: SessionStore?
    private var isRegistered = false

    private init() {}

    func registerIfNeeded(sessionStore: SessionStore) {
        self.sessionStore = sessionStore

        guard !isRegistered else { return }

        let didRegister = BGTaskScheduler.shared.register(
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

        isRegistered = didRegister
        if didRegister {
            logger.info("Registered background refresh task \(Self.taskIdentifier, privacy: .public)")
            sessionStore.recordBackgroundSyncDiagnostic(event: "Background task registered")
        } else {
            logger.error("Failed to register background refresh task \(Self.taskIdentifier, privacy: .public)")
            sessionStore.recordBackgroundSyncDiagnostic(event: "Background task registration failed")
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
            logger.info("Submitted background refresh task earliestBeginDate=\(String(describing: request.earliestBeginDate), privacy: .public)")
            sessionStore?.recordBackgroundSyncDiagnostic(
                event: "Background sync requested",
                nextRequestedAt: request.earliestBeginDate
            )
        } catch {
            logger.error("Failed to submit background refresh task: \(error.localizedDescription, privacy: .public)")
            sessionStore?.recordBackgroundSyncDiagnostic(event: "Background sync request failed: \(error.localizedDescription)")
            #if DEBUG
            print("MistiaSyncBackgroundScheduler: failed to submit refresh task: \(error)")
            #endif
        }
    }

    func cancelPendingRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handle(refreshTask: BGAppRefreshTask) async {
        let startedAt = Date()
        logger.info("Started background refresh task")
        sessionStore?.recordBackgroundSyncDiagnostic(event: "Background sync started", attemptAt: startedAt)
        scheduleNextRefresh(after: sessionStore?.nextAutomaticSyncDate)

        let operation = Task { @MainActor [weak self] in
            await self?.sessionStore?.handleBackgroundRefresh() ?? false
        }

        refreshTask.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.logger.warning("Background refresh task expired")
                self?.sessionStore?.recordBackgroundSyncDiagnostic(event: "Background sync expired", attemptAt: Date())
            }
            operation.cancel()
        }

        let success = await operation.value
        logger.info("Completed background refresh task success=\(success, privacy: .public)")
        sessionStore?.recordBackgroundSyncDiagnostic(
            event: success ? "Background sync completed" : "Background sync completed without syncing",
            attemptAt: startedAt
        )
        refreshTask.setTaskCompleted(success: success)
        scheduleNextRefresh(after: sessionStore?.nextAutomaticSyncDate)
    }
}
