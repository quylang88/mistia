import Foundation
import os
import SwiftData

nonisolated enum MistiaPerformanceSignpost {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "Mistia",
        category: "SyncPerformance"
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}

nonisolated struct MistiaSyncConflictSnapshot: Sendable {
    let entity: MistiaSyncEntity
    let localPayloadJSON: String
    let remotePayloadJSON: String
    let remoteVersion: Int64
}

actor MistiaSyncPersistenceWorker {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func exportSnapshot(for userID: UUID) throws -> MistiaRemoteSnapshot {
        let signpostID = MistiaPerformanceSignpost.begin("Local Export")
        defer { MistiaPerformanceSignpost.end("Local Export", id: signpostID) }
        return try MistiaSyncLocalStore.exportSnapshot(for: userID, from: modelContainer)
    }

    func exportSnapshotForUpload(for userID: UUID) throws -> MistiaRemoteSnapshot {
        let signpostID = MistiaPerformanceSignpost.begin("Local Export")
        defer { MistiaPerformanceSignpost.end("Local Export", id: signpostID) }
        return try MistiaSyncLocalStore.exportSnapshotForUpload(for: userID, from: modelContainer)
    }

    func exportRecord(for mutation: MistiaSyncMutation) throws -> MistiaSyncUploadRecord? {
        try MistiaSyncLocalStore.exportRecord(for: mutation, from: modelContainer)
    }

    func exportCategoryRecord(
        id: UUID,
        subjectUserID: UUID
    ) throws -> MistiaSyncUploadRecord? {
        try MistiaSyncLocalStore.exportCategoryRecord(
            remoteCategoryID: id,
            subjectUserID: subjectUserID,
            from: modelContainer
        )
    }

    func fingerprint(of snapshot: MistiaRemoteSnapshot) -> String {
        let signpostID = MistiaPerformanceSignpost.begin("Snapshot Fingerprint")
        defer { MistiaPerformanceSignpost.end("Snapshot Fingerprint", id: signpostID) }
        return snapshot.fingerprint
    }

    func applySnapshot(
        _ snapshot: MistiaRemoteSnapshot,
        protectedRecordIDs: Set<String>,
        preserveLocalNewerRows: Bool = false
    ) throws {
        let signpostID = MistiaPerformanceSignpost.begin("Snapshot Apply")
        defer { MistiaPerformanceSignpost.end("Snapshot Apply", id: signpostID) }
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: protectedRecordIDs,
            preserveLocalNewerRows: preserveLocalNewerRows,
            in: modelContainer
        )
    }

    func applyAccessibleFinanceSnapshot(
        _ snapshot: MistiaRemoteSnapshot,
        protectedRecordIDs: Set<String>,
        localUserID: UUID,
        pruneOwnerIDs: Set<UUID>,
        preserveLocalNewerRows: Bool
    ) throws {
        let signpostID = MistiaPerformanceSignpost.begin("Member Apply")
        defer { MistiaPerformanceSignpost.end("Member Apply", id: signpostID) }
        let reconciledSnapshot = MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
            snapshot
        )
        try MistiaSyncLocalStore.applyAccessibleFinanceSnapshot(
            reconciledSnapshot,
            protectedRecordIDs: protectedRecordIDs,
            familyCategoryScopedTo: localUserID,
            familyCategoryPruneOwnerIDs: pruneOwnerIDs,
            preserveLocalNewerRows: preserveLocalNewerRows,
            in: modelContainer
        )
    }

    func applyRemoteRecord(
        _ record: MistiaSyncUploadRecord,
        localUserID: UUID? = nil,
        preservesLocalSystemDefaults: Bool = true
    ) throws {
        try MistiaSyncLocalStore.applyRemoteRecord(
            record,
            localUserID: localUserID,
            preservesLocalSystemDefaults: preservesLocalSystemDefaults,
            in: modelContainer
        )
    }

    func fetchConflict(id: UUID) throws -> MistiaSyncConflictSnapshot? {
        guard let conflict = try MistiaSyncLocalStore.fetchConflict(id: id, from: modelContainer) else {
            return nil
        }
        return MistiaSyncConflictSnapshot(
            entity: conflict.entity,
            localPayloadJSON: conflict.localPayloadJSON,
            remotePayloadJSON: conflict.remotePayloadJSON,
            remoteVersion: conflict.remoteVersion
        )
    }

    func removeConflict(id: UUID) throws {
        try MistiaSyncLocalStore.removeConflict(id: id, from: modelContainer)
    }

    func saveConflictAndApplyRemote(
        entity: MistiaSyncEntity,
        recordID: UUID,
        kind: MistiaSyncConflictKind,
        localDraft: MistiaSyncUploadRecord,
        remoteRecord: MistiaSyncUploadRecord,
        baseVersion: Int64,
        remoteVersion: Int64
    ) throws {
        try MistiaSyncLocalStore.saveConflict(
            entity: entity,
            recordID: recordID,
            kind: kind,
            localDraft: localDraft,
            remoteRecord: remoteRecord,
            baseVersion: baseVersion,
            remoteVersion: remoteVersion,
            in: modelContainer
        )
        try MistiaSyncLocalStore.applyRemoteRecord(remoteRecord, in: modelContainer)
    }
}

enum MistiaSyncResult {
    case idle
    case seeded(Int)
    case pulled(Int)
    case synced(Int)
    case pushedOnly

    var statusMessage: String {
        switch self {
        case .idle:
            return L10n.shared.sync.mistiasynccoordinator.thereAreNoNewChangesToSync
        case .seeded(let count):
            return L10n.shared.sync.mistiasynccoordinator.uploadedValueLocalRecordsToTheCloud(String(describing: count))
        case .pulled(let count):
            return L10n.shared.sync.mistiasynccoordinator.downloadedValueRecordsFromTheCloud(String(describing: count))
        case .synced(let count):
            return L10n.shared.sync.mistiasynccoordinator.syncCompletedAcrossValueRecords(String(describing: count))
        case .pushedOnly:
            return L10n.shared.sync.mistiasynccoordinator.uploadedLocalChangesToTheCloud
        }
    }
}

private enum FamilyActivityNotificationAction: String {
    case created
    case updated
    case deleted
}

enum MistiaFamilyCloudFirstPushError: LocalizedError {
    case remoteChanged(MistiaSyncMutation)

    var mutation: MistiaSyncMutation? {
        switch self {
        case .remoteChanged(let mutation):
            return mutation
        }
    }

    var errorDescription: String? {
        L10n.shared.sync.mistiasynccoordinator.thisDataChangedInTheCloudRefresh
    }
}

struct MistiaFamilyCloudFirstPushSummary: Equatable {
    let pushedMutations: Bool
    let conflicts: [MistiaSyncMutation]

    var hasConflicts: Bool {
        !conflicts.isEmpty
    }
}

private nonisolated struct SyncRemoteSystemCategoryKey: Hashable {
    let userID: UUID
    let systemKey: String
}

@MainActor
final class SyncCoordinator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Mistia",
        category: "SyncCoordinator"
    )

    private let modelContainer: ModelContainer
    private let persistenceWorker: MistiaSyncPersistenceWorker
    private let remoteStore: MistiaRemoteStore
    private let outbox: MistiaSyncOutbox
    private let deviceID: UUID

    var onProgressUpdate: ((Double) -> Void)?
    private var lastSnapshotFingerprint: String?

    init(
        modelContainer: ModelContainer,
        remoteStore: MistiaRemoteStore? = nil,
        outbox: MistiaSyncOutbox? = nil,
        deviceID: UUID = MistiaSyncDeviceIdentity.current()
    ) {
        self.modelContainer = modelContainer
        self.persistenceWorker = MistiaSyncPersistenceWorker(modelContainer: modelContainer)
        self.remoteStore = remoteStore ?? SupabaseRemoteStore()
        self.outbox = outbox ?? MistiaSyncOutbox()
        self.deviceID = deviceID
    }

    func queue(_ mutation: MistiaSyncMutation) {
        outbox.enqueue(mutation)
    }

    func queue(_ mutations: [MistiaSyncMutation]) {
        outbox.enqueue(mutations)
    }

    func hasQueuedMutation(entity: MistiaSyncEntity, recordID: UUID) -> Bool {
        outbox.contains(entity: entity, recordID: recordID)
    }

    func queuedMutationIDs() -> Set<String> {
        Set(outbox.allMutations.map { $0.id.lowercased() })
    }

    func queuedMutations() -> [MistiaSyncMutation] {
        outbox.allMutations
    }

    func removeQueuedMutation(entity: MistiaSyncEntity, recordID: UUID) {
        outbox.remove(entity: entity, recordID: recordID)
    }

    func clearQueuedMutations() {
        outbox.clear()
    }

    func clearLocalCache() throws {
        lastSnapshotFingerprint = nil
        try MistiaSyncLocalStore.clearAllData(in: modelContainer)
    }

    func previewInitialSync(session: SupabaseAuthSession) async throws -> MistiaInitialSyncPreview {
        let localSnapshot = try await persistenceWorker.exportSnapshot(for: session.user.id)
        let remoteSnapshot = try await fetchReconciledSnapshot(session: session)

        let localCount = localSnapshot.activeRowCount
        let remoteCount = remoteSnapshot.activeRowCount

        if localCount == 0 && remoteCount == 0 {
            return MistiaInitialSyncPreview(mode: .idle, localActiveCount: 0, remoteActiveCount: 0)
        }

        if remoteCount == 0 {
            return MistiaInitialSyncPreview(mode: .choose, localActiveCount: localCount, remoteActiveCount: remoteCount)
        }

        if localCount == 0 {
            return MistiaInitialSyncPreview(mode: .downloadCloud, localActiveCount: localCount, remoteActiveCount: remoteCount)
        }

        return MistiaInitialSyncPreview(mode: .choose, localActiveCount: localCount, remoteActiveCount: remoteCount)
    }

    func performInitialSync(
        session: SupabaseAuthSession,
        choice: MistiaInitialSyncChoice
    ) async throws -> MistiaSyncResult {
        onProgressUpdate?(0.05)
        let localSnapshot = try await persistenceWorker.exportSnapshot(for: session.user.id)
        let uploadReadyLocalSnapshot = try await persistenceWorker.exportSnapshotForUpload(
            for: session.user.id
        )
        onProgressUpdate?(0.1)
        let rawRemoteSnapshot = try await fetchReconciledSnapshot(session: session)
        let remoteSnapshot = rawRemoteSnapshot
        onProgressUpdate?(0.2)

        try Task.checkCancellation()

        let localCount = localSnapshot.activeRowCount
        let remoteCount = remoteSnapshot.activeRowCount

        if localCount == 0 && remoteCount == 0 {
            lastSnapshotFingerprint = await persistenceWorker.fingerprint(of: remoteSnapshot)
            onProgressUpdate?(1.0)
            return .idle
        }

        if remoteCount == 0 {
            try await uploadLocalOnlyRows(
                localSnapshot: uploadReadyLocalSnapshot,
                remoteSnapshot: rawRemoteSnapshot,
                session: session,
                progressStart: 0.2,
                progressEnd: 0.8
            )
            let mergedSnapshot = try await fetchReconciledSnapshot(session: session)
            onProgressUpdate?(0.9)
            let mergedCount = mergedSnapshot.activeRowCount
            try await applySnapshot(mergedSnapshot)
            onProgressUpdate?(1.0)
            return .seeded(mergedCount)
        }

        if localCount == 0 || choice == .useCloud {
            outbox.clear()
            try clearLocalCache()
            onProgressUpdate?(0.3)
            let freshSnapshot = try await fetchReconciledSnapshot(session: session)
            onProgressUpdate?(0.6)
            let freshCount = freshSnapshot.activeRowCount
            try await applySnapshot(freshSnapshot)
            onProgressUpdate?(1.0)
            return .pulled(freshCount)
        }

        try Task.checkCancellation()

        switch choice {
        case .mergeSafely:
            try await mergeInitialSnapshots(
                localSnapshot: uploadReadyLocalSnapshot,
                remoteSnapshot: rawRemoteSnapshot,
                session: session,
                progressStart: 0.2,
                progressEnd: 0.8
            )
        case .useDevice:
            try await makeLocalAuthoritative(
                localSnapshot: uploadReadyLocalSnapshot,
                remoteSnapshot: rawRemoteSnapshot,
                session: session,
                progressStart: 0.2,
                progressEnd: 0.8
            )
        case .useCloud:
            break
        }

        onProgressUpdate?(0.85)
        let mergedSnapshot = try await fetchReconciledSnapshot(session: session)
        onProgressUpdate?(0.9)
        let mergedCount = mergedSnapshot.activeRowCount
        try await applySnapshot(mergedSnapshot)
        onProgressUpdate?(1.0)
        return .synced(mergedCount)
    }

    func sync(session: SupabaseAuthSession) async throws -> MistiaSyncResult {
        onProgressUpdate?(0.05)
        var pushedMutations = false
        var seededMissingRows = false

        let mutations = outbox.allMutations.filter { $0.subjectUserID == session.user.id }
        let mutationCount = mutations.count

        let sortedMutations = await sortedMutationsForPush(mutations)

        try Task.checkCancellation()

        for (index, mutation) in sortedMutations.enumerated() {
            try Task.checkCancellation()
            let progress = 0.05 + (Double(index) / Double(max(1, mutationCount))) * 0.45
            onProgressUpdate?(progress)

            switch mutation.kind {
            case .upsert:
                if try await processUpsertMutation(mutation, session: session) {
                    pushedMutations = true
                }
            case .delete:
                if try await processDeleteMutation(mutation, session: session) {
                    pushedMutations = true
                }
            }
        }

        try Task.checkCancellation()

        onProgressUpdate?(0.55)
        let localSnapshot = try await persistenceWorker.exportSnapshotForUpload(for: session.user.id)
        var rawRemoteSnapshot = try await fetchReconciledSnapshot(session: session)
        let remoteWasEmpty = rawRemoteSnapshot.activeRowCount == 0

        if shouldUploadLocalOnlyRows(localSnapshot: localSnapshot, remoteSnapshot: rawRemoteSnapshot) {
            try await uploadLocalOnlyRows(
                localSnapshot: localSnapshot,
                remoteSnapshot: rawRemoteSnapshot,
                session: session,
                progressStart: 0.55,
                progressEnd: 0.8
            )
            seededMissingRows = true
            rawRemoteSnapshot = try await fetchReconciledSnapshot(session: session)
        } else {
            onProgressUpdate?(0.8)
        }

        try Task.checkCancellation()

        if try await pushLocallyNewerRows(
            localSnapshot: localSnapshot,
            remoteSnapshot: rawRemoteSnapshot,
            session: session,
            progressStart: 0.8,
            progressEnd: 0.85
        ) {
            pushedMutations = true
            rawRemoteSnapshot = try await fetchReconciledSnapshot(session: session)
        }

        try Task.checkCancellation()

        let snapshot = rawRemoteSnapshot
        let previousFingerprint = lastSnapshotFingerprint
        let snapshotActiveCount = snapshot.activeRowCount
        let snapshotFingerprint = try await applySnapshot(snapshot)
        onProgressUpdate?(1.0)

        if seededMissingRows && remoteWasEmpty {
            return .seeded(snapshotActiveCount)
        }

        if snapshotFingerprint != previousFingerprint {
            return (pushedMutations || seededMissingRows) ? .synced(snapshotActiveCount) : .pulled(snapshotActiveCount)
        }

        return (pushedMutations || seededMissingRows) ? .pushedOnly : .idle
    }

    private func sortedMutationsForPush(_ mutations: [MistiaSyncMutation]) async -> [MistiaSyncMutation] {
        let categoryChildRecordIDs = await categoryChildRecordIDsForPushSorting(mutations)

        return mutations.sorted { a, b in
            if a.entity.pushPriority != b.entity.pushPriority {
                return a.entity.pushPriority < b.entity.pushPriority
            }

            if a.entity == .category && b.entity == .category {
                let aIsChild = categoryChildRecordIDs.contains(a.recordID)
                let bIsChild = categoryChildRecordIDs.contains(b.recordID)

                if !aIsChild && bIsChild { return true }
                if aIsChild && !bIsChild { return false }
            }

            return a.modifiedAt < b.modifiedAt
        }
    }

    private func categoryChildRecordIDsForPushSorting(_ mutations: [MistiaSyncMutation]) async -> Set<UUID> {
        let categoryMutations = mutations.filter { $0.entity == .category }
        guard !categoryMutations.isEmpty else { return [] }

        var childRecordIDs: Set<UUID> = []
        var inspectedRecordIDs: Set<UUID> = []
        for mutation in categoryMutations where inspectedRecordIDs.insert(mutation.recordID).inserted {
            guard let record = try? await persistenceWorker.exportRecord(for: mutation),
                  record.parentID != nil else {
                continue
            }
            childRecordIDs.insert(mutation.recordID)
        }
        return childRecordIDs
    }

    func pushQueuedMutationsOnly(
        _ mutations: [MistiaSyncMutation],
        session: SupabaseAuthSession
    ) async throws -> Bool {
        var pushedMutations = false
        let sortedMutations = await sortedMutationsForPush(mutations)

        for mutation in sortedMutations {
            switch mutation.kind {
            case .upsert:
                if try await processUpsertMutation(mutation, session: session) {
                    pushedMutations = true
                }
            case .delete:
                if try await processDeleteMutation(mutation, session: session) {
                    pushedMutations = true
                }
            }
        }

        return pushedMutations
    }

    func pushQueuedFamilyOwnerMutationsCloudFirst(
        _ mutations: [MistiaSyncMutation],
        session: SupabaseAuthSession
    ) async throws -> Bool {
        let summary = try await pushQueuedFamilyOwnerMutationsCloudFirstCollectingConflicts(
            mutations,
            session: session
        )
        if let conflict = summary.conflicts.first {
            throw MistiaFamilyCloudFirstPushError.remoteChanged(conflict)
        }
        return summary.pushedMutations
    }

    func pushQueuedFamilyOwnerMutationsCloudFirstCollectingConflicts(
        _ mutations: [MistiaSyncMutation],
        session: SupabaseAuthSession
    ) async throws -> MistiaFamilyCloudFirstPushSummary {
        let familyMutations = mutations.filter { $0.subjectUserID != session.user.id }
        guard !familyMutations.isEmpty else {
            return MistiaFamilyCloudFirstPushSummary(pushedMutations: false, conflicts: [])
        }

        var pushedMutations = false
        var conflicts: [MistiaSyncMutation] = []
        let groupedByOwner = Dictionary(grouping: familyMutations, by: \.subjectUserID)
        let ownerIDs = groupedByOwner.keys.sorted { $0.uuidString < $1.uuidString }

        for ownerID in ownerIDs {
            let ownerMutations = groupedByOwner[ownerID] ?? []
            for mutation in await sortedMutationsForPush(ownerMutations) {
                do {
                    switch mutation.kind {
                    case .upsert:
                        if try await processFamilyOwnerUpsertMutation(mutation, session: session) {
                            pushedMutations = true
                        }
                    case .delete:
                        if try await processFamilyOwnerDeleteMutation(mutation, session: session) {
                            pushedMutations = true
                        }
                    }
                } catch MistiaFamilyCloudFirstPushError.remoteChanged(let conflictMutation) {
                    conflicts.append(conflictMutation)
                }
            }
        }

        return MistiaFamilyCloudFirstPushSummary(
            pushedMutations: pushedMutations,
            conflicts: conflicts
        )
    }

    func resolveConflict(
        id: UUID,
        resolution: MistiaSyncConflictResolution,
        session: SupabaseAuthSession
    ) async throws {
        guard let conflict = try await persistenceWorker.fetchConflict(id: id) else {
            return
        }

        switch resolution {
        case .useRemote:
            let remoteRecord = try MistiaSyncUploadRecord.decode(
                entity: conflict.entity,
                jsonString: conflict.remotePayloadJSON
            )
            try await persistenceWorker.applyRemoteRecord(
                remoteRecord,
                preservesLocalSystemDefaults: false
            )
            try await persistenceWorker.removeConflict(id: id)
        case .useLocal:
            let localRecord = try MistiaSyncUploadRecord.decode(
                entity: conflict.entity,
                jsonString: conflict.localPayloadJSON
            )
            _ = try await forcePushLocalRecord(
                localRecord,
                subjectUserID: localRecord.userID,
                remoteVersion: conflict.remoteVersion,
                session: session
            )
            try await persistenceWorker.removeConflict(id: id)
        }
    }

    private func processUpsertMutation(
        _ mutation: MistiaSyncMutation,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        guard let localRecord = try await persistenceWorker.exportRecord(for: mutation) else {
            outbox.remove(mutation)
            return false
        }
        let subjectUserID = localRecord.userID
        try await ensureRemoteCategoryDependenciesExistIfNeeded(
            for: localRecord,
            subjectUserID: subjectUserID,
            session: session
        )

        let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            session: session
        )

        if let remoteRecord, remoteRecord.payloadFingerprint == localRecord.payloadFingerprint {
            try await persistenceWorker.applyRemoteRecord(remoteRecord)
            try await createFamilyActivityNotificationIfNeeded(
                for: remoteRecord,
                subjectUserID: subjectUserID,
                action: remoteRecord.deletedAt == nil
                    ? (mutation.baseVersion == 0 ? .created : .updated)
                    : .deleted,
                session: session
            )
            outbox.remove(mutation)
            return false
        }

        if mutation.baseVersion == 0 {
            guard remoteRecord == nil else {
                let conflictKind: MistiaSyncConflictKind = remoteRecord?.deletedAt == nil ? .createCreate : .editDelete
                let resolvedLocally = try await resolveConflictingRecords(
                    entity: mutation.entity,
                    recordID: mutation.recordID,
                    kind: conflictKind,
                    localDraft: localRecord,
                    remoteRecord: remoteRecord ?? synthesizedDeletedRecord(from: localRecord, remoteVersion: 1),
                    baseVersion: mutation.baseVersion,
                    remoteVersion: remoteRecord?.syncVersion ?? 1,
                    subjectUserID: subjectUserID,
                    session: session
                )
                outbox.remove(mutation)
                return resolvedLocally
            }

            let created = try await remoteStore.create(
                localRecord.preparedForCreate(deviceID: deviceID),
                subjectUserID: subjectUserID,
                session: session
            )
            try await persistenceWorker.applyRemoteRecord(created)
            try await createFamilyActivityNotificationIfNeeded(
                for: created,
                subjectUserID: subjectUserID,
                action: .created,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        guard let remoteRecord else {
            _ = try await forcePushLocalRecord(
                localRecord,
                subjectUserID: subjectUserID,
                remoteVersion: mutation.baseVersion,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        if remoteRecord.deletedAt != nil {
            let resolvedLocally = try await resolveConflictingRecords(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .editDelete,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: mutation.baseVersion,
                remoteVersion: remoteRecord.syncVersion,
                subjectUserID: subjectUserID,
                session: session
            )
            outbox.remove(mutation)
            return resolvedLocally
        }

        if remoteRecord.syncVersion != mutation.baseVersion {
            let resolvedLocally = try await resolveConflictingRecords(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .editEdit,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: mutation.baseVersion,
                remoteVersion: remoteRecord.syncVersion,
                subjectUserID: subjectUserID,
                session: session
            )
            outbox.remove(mutation)
            return resolvedLocally
        }

        if let updated = try await remoteStore.conditionalUpdate(
            localRecord.preparedForMutation(nextVersion: mutation.baseVersion + 1, deviceID: deviceID),
            expectedVersion: mutation.baseVersion,
            subjectUserID: subjectUserID,
            session: session
        ) {
            try await persistenceWorker.applyRemoteRecord(updated)
            try await createFamilyActivityNotificationIfNeeded(
                for: updated,
                subjectUserID: subjectUserID,
                action: .updated,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        let latestRemote = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            session: session
        ) ?? synthesizedDeletedRecord(from: localRecord, remoteVersion: mutation.baseVersion + 1)

        let resolvedLocally = try await resolveConflictingRecords(
            entity: mutation.entity,
            recordID: mutation.recordID,
            kind: latestRemote.deletedAt == nil ? .editEdit : .editDelete,
            localDraft: localRecord,
            remoteRecord: latestRemote,
            baseVersion: mutation.baseVersion,
            remoteVersion: latestRemote.syncVersion,
            subjectUserID: subjectUserID,
            session: session
        )
        outbox.remove(mutation)
        return resolvedLocally
    }

    private func processDeleteMutation(
        _ mutation: MistiaSyncMutation,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        guard let localRecord = try await persistenceWorker.exportRecord(for: mutation) else {
            outbox.remove(mutation)
            return false
        }
        let subjectUserID = localRecord.userID

        let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            session: session
        )

        guard let remoteRecord else {
            outbox.remove(mutation)
            return false
        }

        if remoteRecord.deletedAt != nil {
            try await persistenceWorker.applyRemoteRecord(remoteRecord)
            outbox.remove(mutation)
            return false
        }

        if remoteRecord.syncVersion != mutation.baseVersion {
            let resolvedLocally = try await resolveConflictingRecords(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .deleteEdit,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: mutation.baseVersion,
                remoteVersion: remoteRecord.syncVersion,
                subjectUserID: subjectUserID,
                session: session
            )
            outbox.remove(mutation)
            return resolvedLocally
        }

        if let deletedRecord = try await remoteStore.conditionalDelete(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            expectedVersion: mutation.baseVersion,
            modifiedAt: mutation.modifiedAt,
            deviceID: deviceID,
            session: session
        ) {
            try await persistenceWorker.applyRemoteRecord(deletedRecord)
            try await createFamilyActivityNotificationIfNeeded(
                for: deletedRecord,
                subjectUserID: subjectUserID,
                action: .deleted,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        let latestRemote = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            session: session
        ) ?? synthesizedDeletedRecord(from: localRecord, remoteVersion: mutation.baseVersion + 1)

        if latestRemote.deletedAt != nil {
            try await persistenceWorker.applyRemoteRecord(latestRemote)
            outbox.remove(mutation)
            return false
        }

        let resolvedLocally = try await resolveConflictingRecords(
            entity: mutation.entity,
            recordID: mutation.recordID,
            kind: .deleteEdit,
            localDraft: localRecord,
            remoteRecord: latestRemote,
            baseVersion: mutation.baseVersion,
            remoteVersion: latestRemote.syncVersion,
            subjectUserID: subjectUserID,
            session: session
        )
        outbox.remove(mutation)
        return resolvedLocally
    }

    private func processFamilyOwnerUpsertMutation(
        _ mutation: MistiaSyncMutation,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        guard let localRecord = try await persistenceWorker.exportRecord(for: mutation) else {
            outbox.remove(mutation)
            return false
        }
        let subjectUserID = localRecord.userID
        let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            session: session
        )

        if let remoteRecord, remoteRecord.payloadFingerprint == localRecord.payloadFingerprint {
            try await persistenceWorker.applyRemoteRecord(
                remoteRecord,
                localUserID: session.user.id
            )
            outbox.remove(mutation)
            return false
        }

        if mutation.baseVersion == 0 {
            guard remoteRecord == nil else {
                throw MistiaFamilyCloudFirstPushError.remoteChanged(mutation)
            }

            let created = try await remoteStore.create(
                localRecord.preparedForCreate(deviceID: deviceID),
                subjectUserID: subjectUserID,
                session: session
            )
            try await persistenceWorker.applyRemoteRecord(
                created,
                localUserID: session.user.id
            )
            try await createFamilyActivityNotificationIfNeeded(
                for: created,
                subjectUserID: subjectUserID,
                action: .created,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        guard let remoteRecord, remoteRecord.deletedAt == nil else {
            throw MistiaFamilyCloudFirstPushError.remoteChanged(mutation)
        }

        guard remoteRecord.syncVersion == mutation.baseVersion else {
            throw MistiaFamilyCloudFirstPushError.remoteChanged(mutation)
        }

        guard let updated = try await remoteStore.conditionalUpdate(
            localRecord.preparedForMutation(nextVersion: mutation.baseVersion + 1, deviceID: deviceID),
            expectedVersion: mutation.baseVersion,
            subjectUserID: subjectUserID,
            session: session
        ) else {
            throw MistiaFamilyCloudFirstPushError.remoteChanged(mutation)
        }

        try await persistenceWorker.applyRemoteRecord(
            updated,
            localUserID: session.user.id
        )
        try await createFamilyActivityNotificationIfNeeded(
            for: updated,
            subjectUserID: subjectUserID,
            action: .updated,
            session: session
        )
        outbox.remove(mutation)
        return true
    }

    private func processFamilyOwnerDeleteMutation(
        _ mutation: MistiaSyncMutation,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        guard let localRecord = try await persistenceWorker.exportRecord(for: mutation) else {
            outbox.remove(mutation)
            return false
        }
        let subjectUserID = localRecord.userID

        guard let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            session: session
        ) else {
            outbox.remove(mutation)
            return false
        }

        if remoteRecord.deletedAt != nil {
            try await persistenceWorker.applyRemoteRecord(
                remoteRecord,
                localUserID: session.user.id
            )
            outbox.remove(mutation)
            return false
        }

        guard remoteRecord.syncVersion == mutation.baseVersion else {
            throw MistiaFamilyCloudFirstPushError.remoteChanged(mutation)
        }

        guard let deletedRecord = try await remoteStore.conditionalDelete(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: subjectUserID,
            expectedVersion: mutation.baseVersion,
            modifiedAt: mutation.modifiedAt,
            deviceID: deviceID,
            session: session
        ) else {
            throw MistiaFamilyCloudFirstPushError.remoteChanged(mutation)
        }

        try await persistenceWorker.applyRemoteRecord(
            deletedRecord,
            localUserID: session.user.id
        )
        try await createFamilyActivityNotificationIfNeeded(
            for: deletedRecord,
            subjectUserID: subjectUserID,
            action: .deleted,
            session: session
        )
        outbox.remove(mutation)
        return true
    }

    private func mergeInitialSnapshots(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession,
        progressStart: Double,
        progressEnd: Double
    ) async throws {
        let remoteByID = remoteSnapshot.uploadRecordsByStorageKey
        let localRecords = hierarchicalSorted(localSnapshot.uploadRecords)
        let total = localRecords.count

        for (index, localRecord) in localRecords.enumerated() {
            let progress = progressStart + (Double(index) / Double(max(1, total))) * (progressEnd - progressStart)
            onProgressUpdate?(progress)

            let key = localRecord.storageKey
            guard let remoteRecord = remoteByID[key] else {
                guard localRecord.deletedAt == nil else { continue }
                _ = try await remoteStore.create(
                    localRecord.preparedForCreate(deviceID: deviceID),
                    subjectUserID: localRecord.userID,
                    session: session
                )
                continue
            }

            guard localRecord.payloadFingerprint != remoteRecord.payloadFingerprint else {
                continue
            }

            let conflictKind: MistiaSyncConflictKind
            if remoteRecord.deletedAt != nil {
                conflictKind = .editDelete
            } else if localRecord.deletedAt != nil {
                conflictKind = .deleteEdit
            } else if localRecord.syncVersion == 0 {
                conflictKind = .createCreate
            } else {
                conflictKind = .editEdit
            }

            _ = try await resolveConflictingRecords(
                entity: localRecord.entity,
                recordID: localRecord.id,
                kind: conflictKind,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: localRecord.syncVersion,
                remoteVersion: remoteRecord.syncVersion,
                subjectUserID: localRecord.userID,
                session: session
            )
        }

        _ = try await sync(session: session)
    }

    private func makeLocalAuthoritative(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession,
        progressStart: Double,
        progressEnd: Double
    ) async throws {
        let remoteByKey = remoteSnapshot.uploadRecordsByStorageKey
        let localByKey = localSnapshot.uploadRecordsByStorageKey
        let localRecords = hierarchicalSorted(localSnapshot.uploadRecords(where: { $0.deletedAt == nil }))
        let total = localRecords.count

        for (index, localRecord) in localRecords.enumerated() {
            let progress = progressStart + (Double(index) / Double(max(1, total))) * (progressEnd - progressStart) * 0.8
            onProgressUpdate?(progress)

            let remoteVersion = remoteByKey[localRecord.storageKey]?.syncVersion ?? 0
            let prepared = localRecord.preparedForMutation(
                nextVersion: max(remoteVersion + 1, 1),
                deviceID: deviceID
            )
            _ = try await remoteStore.forceUpsert(
                prepared,
                subjectUserID: localRecord.userID,
                session: session
            )
        }

        for remoteRecord in remoteSnapshot.uploadRecords where localByKey[remoteRecord.storageKey] == nil {
            _ = try await remoteStore.conditionalDelete(
                entity: remoteRecord.entity,
                recordID: remoteRecord.id,
                subjectUserID: remoteRecord.userID,
                expectedVersion: remoteRecord.syncVersion,
                modifiedAt: Date(),
                deviceID: deviceID,
                session: session
            )
        }
    }

    private func uploadLocalOnlyRows(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession,
        progressStart: Double,
        progressEnd: Double
    ) async throws {
        let remoteKeys = remoteSnapshot.uploadRecordStorageKeys
        let localOnly = hierarchicalSorted(localSnapshot.uploadRecords(where: { !remoteKeys.contains($0.storageKey) && $0.deletedAt == nil }))
        let total = localOnly.count

        for (index, localRecord) in localOnly.enumerated() {
            try Task.checkCancellation()
            let progress = progressStart + (Double(index) / Double(max(1, total))) * (progressEnd - progressStart)
            onProgressUpdate?(progress)

            try await ensureRemoteCategoryDependenciesExistIfNeeded(
                for: localRecord,
                subjectUserID: localRecord.userID,
                session: session
            )
            _ = try await remoteStore.create(
                localRecord.preparedForCreate(deviceID: deviceID),
                subjectUserID: localRecord.userID,
                session: session
            )
        }
    }

    private func ensureRemoteCategoryDependenciesExistIfNeeded(
        for record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession,
        localUserID: UUID? = nil,
        visitedCategoryIDs: Set<UUID> = []
    ) async throws {
        try await ensureRemoteCategoryParentsExistIfNeeded(
            for: record,
            subjectUserID: subjectUserID,
            session: session,
            localUserID: localUserID
        )

        guard let categoryID = categoryReferenceID(for: record),
              !visitedCategoryIDs.contains(categoryID) else {
            return
        }

        let remoteCategory = try await remoteStore.fetchRecord(
            entity: .category,
            recordID: categoryID,
            subjectUserID: subjectUserID,
            session: session
        )

        if let remoteCategory, remoteCategory.deletedAt == nil {
            try await ensureRemoteCategoryParentsExistIfNeeded(
                for: remoteCategory,
                subjectUserID: subjectUserID,
                session: session,
                localUserID: localUserID,
                visitedParentIDs: visitedCategoryIDs.union([categoryID])
            )
            return
        }

        guard let categoryRecord = try await persistenceWorker.exportCategoryRecord(
            id: categoryID,
            subjectUserID: subjectUserID
        ) else {
            return
        }

        try await ensureRemoteCategoryDependenciesExistIfNeeded(
            for: categoryRecord,
            subjectUserID: subjectUserID,
            session: session,
            localUserID: localUserID,
            visitedCategoryIDs: visitedCategoryIDs.union([categoryID])
        )

        let nextVersion = max((remoteCategory?.syncVersion ?? categoryRecord.syncVersion) + 1, 1)
        let upsertedCategory = try await remoteStore.forceUpsert(
            categoryRecord.preparedForMutation(nextVersion: nextVersion, deviceID: deviceID),
            subjectUserID: subjectUserID,
            session: session
        )
        try await persistenceWorker.applyRemoteRecord(
            upsertedCategory,
            localUserID: localUserID
        )
    }

    private func ensureRemoteCategoryParentsExistIfNeeded(
        for record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession,
        localUserID: UUID? = nil,
        visitedParentIDs: Set<UUID> = []
    ) async throws {
        guard record.entity == .category,
              let parentID = record.parentID,
              !visitedParentIDs.contains(parentID) else {
            return
        }

        let remoteParent = try await remoteStore.fetchRecord(
            entity: .category,
            recordID: parentID,
            subjectUserID: subjectUserID,
            session: session
        )
        if let remoteParent, remoteParent.deletedAt == nil {
            try await ensureRemoteCategoryParentsExistIfNeeded(
                for: remoteParent,
                subjectUserID: subjectUserID,
                session: session,
                localUserID: localUserID,
                visitedParentIDs: visitedParentIDs.union([parentID])
            )
            return
        }

        guard let parentRecord = try await persistenceWorker.exportCategoryRecord(
            id: parentID,
            subjectUserID: subjectUserID
        ) else {
            return
        }

        try await ensureRemoteCategoryParentsExistIfNeeded(
            for: parentRecord,
            subjectUserID: subjectUserID,
            session: session,
            localUserID: localUserID,
            visitedParentIDs: visitedParentIDs.union([parentID])
        )

        let nextVersion = max((remoteParent?.syncVersion ?? parentRecord.syncVersion) + 1, 1)
        let upsertedParent = try await remoteStore.forceUpsert(
            parentRecord.preparedForMutation(nextVersion: nextVersion, deviceID: deviceID),
            subjectUserID: subjectUserID,
            session: session
        )
        try await persistenceWorker.applyRemoteRecord(
            upsertedParent,
            localUserID: localUserID
        )
    }

    private func categoryReferenceID(for record: MistiaSyncUploadRecord) -> UUID? {
        switch record {
        case .transaction(let row):
            row.categoryID
        case .budgetPlan(let row):
            row.categoryID
        case .recurringBillPlan(let row):
            row.categoryID
        case .wallet, .creditCardProfile, .category, .settlementGroup, .settlementParticipant, .savingsGoal, .installmentPlan, .dueOccurrence:
            nil
        }
    }

    private func shouldUploadLocalOnlyRows(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot
    ) -> Bool {
        let remoteKeys = remoteSnapshot.uploadRecordStorageKeys
        return localSnapshot.containsUploadRecord { record in
            record.deletedAt == nil && !remoteKeys.contains(record.storageKey)
        }
    }

    private func fetchRawSnapshot(
        session: SupabaseAuthSession,
        subjectUserID: UUID? = nil
    ) async throws -> MistiaRemoteSnapshot {
        let signpostID = MistiaPerformanceSignpost.begin("Remote Fetch")
        defer { MistiaPerformanceSignpost.end("Remote Fetch", id: signpostID) }
        return try await remoteStore.fetchSnapshot(session: session, subjectUserID: subjectUserID)
    }

    private func fetchReconciledSnapshot(
        session: SupabaseAuthSession,
        subjectUserID: UUID? = nil
    ) async throws -> MistiaRemoteSnapshot {
        let rawSnapshot = try await fetchRawSnapshot(session: session, subjectUserID: subjectUserID)
        if try await reconcileOwnedRemoteSystemCategories(rawSnapshot, session: session) {
            return MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
                try await fetchRawSnapshot(session: session, subjectUserID: subjectUserID),
                preferCloudScopedIDs: true
            )
        }

        return MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
            rawSnapshot,
            preferCloudScopedIDs: true
        )
    }

    private func reconcileOwnedRemoteSystemCategories(
        _ snapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        let ownerUserID = session.user.id
        let ownedSystemRows = snapshot.categories.filter {
            $0.userID == ownerUserID
                && $0.isSystem
                && $0.systemKey != nil
                && $0.deletedAt == nil
        }
        guard !ownedSystemRows.isEmpty else { return false }

        let categoryByID = Dictionary(
            snapshot.categories.map { ($0.id, $0) },
            uniquingKeysWith: preferredRemoteCategory
        )
        let groupedRows = Dictionary(grouping: ownedSystemRows) { row in
            SyncRemoteSystemCategoryKey(userID: row.userID, systemKey: row.systemKey ?? "")
        }

        var replacementByID: [UUID: UUID] = [:]
        var duplicateRows: [RemoteTransactionCategory] = []
        var preferredCategoryRecords: [MistiaSyncUploadRecord] = []

        for (key, group) in groupedRows where !key.systemKey.isEmpty {
            let cloudScopedID = MistiaSystemCategoryIdentity.cloudScopedID(
                canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: key.systemKey),
                ownerUserID: key.userID
            )
            let needsRepair = group.count > 1 || group.first?.id != cloudScopedID
            guard needsRepair else { continue }
            guard let source = group.max(by: { remoteCategoryScore($0) < remoteCategoryScore($1) }) else {
                continue
            }

            var repairedRow = source
            repairedRow.id = cloudScopedID
            repairedRow.parentCategoryID = repairedParentCategoryID(
                source.parentCategoryID,
                ownerUserID: key.userID,
                categoryByID: categoryByID
            )
            repairedRow.deletedAt = nil

            let nextVersion = (group.map(\.syncVersion).max() ?? repairedRow.syncVersion) + 1
            preferredCategoryRecords.append(
                MistiaSyncUploadRecord
                    .category(repairedRow)
                    .preparedForMutation(nextVersion: nextVersion, deviceID: deviceID)
            )

            for row in group where row.id != cloudScopedID {
                replacementByID[row.id] = cloudScopedID
                duplicateRows.append(row)
            }
        }

        guard !preferredCategoryRecords.isEmpty || !replacementByID.isEmpty else {
            return false
        }

        for record in hierarchicalSorted(preferredCategoryRecords) {
            _ = try await remoteStore.forceUpsert(
                record,
                subjectUserID: ownerUserID,
                session: session
            )
        }

        let duplicateIDs = Set(duplicateRows.map(\.id))
        let referenceRepairRecords = remoteRecordsNeedingCategoryReferenceRepair(
            snapshot: snapshot,
            ownerUserID: ownerUserID,
            duplicateIDs: duplicateIDs,
            replacementByID: replacementByID
        )

        for record in hierarchicalSorted(referenceRepairRecords) {
            _ = try await remoteStore.forceUpsert(
                record,
                subjectUserID: ownerUserID,
                session: session
            )
        }

        for row in duplicateRows {
            _ = try await remoteStore.conditionalDelete(
                entity: .category,
                recordID: row.id,
                subjectUserID: ownerUserID,
                expectedVersion: row.syncVersion,
                modifiedAt: Date(),
                deviceID: deviceID,
                session: session
            )
        }

        return true
    }

    private func remoteRecordsNeedingCategoryReferenceRepair(
        snapshot: MistiaRemoteSnapshot,
        ownerUserID: UUID,
        duplicateIDs: Set<UUID>,
        replacementByID: [UUID: UUID]
    ) -> [MistiaSyncUploadRecord] {
        guard !replacementByID.isEmpty else { return [] }

        var records: [MistiaSyncUploadRecord] = []

        for row in snapshot.categories where row.userID == ownerUserID && !duplicateIDs.contains(row.id) {
            appendRepairedRecord(.category(row), replacementByID: replacementByID, to: &records)
        }
        for row in snapshot.transactions where row.userID == ownerUserID {
            appendRepairedRecord(.transaction(row), replacementByID: replacementByID, to: &records)
        }
        for row in snapshot.budgetPlans where row.userID == ownerUserID {
            appendRepairedRecord(.budgetPlan(row), replacementByID: replacementByID, to: &records)
        }
        for row in snapshot.recurringBillPlans where row.userID == ownerUserID {
            appendRepairedRecord(.recurringBillPlan(row), replacementByID: replacementByID, to: &records)
        }

        return records
    }

    private func appendRepairedRecord(
        _ record: MistiaSyncUploadRecord,
        replacementByID: [UUID: UUID],
        to records: inout [MistiaSyncUploadRecord]
    ) {
        let repaired = record.remappingCategoryReferences(replacementByID)
        guard repaired.payloadFingerprint != record.payloadFingerprint else { return }
        let nextVersion = max(record.syncVersion, 0) + 1
        records.append(
            repaired.preparedForMutation(nextVersion: nextVersion, deviceID: deviceID)
        )
    }

    private func repairedParentCategoryID(
        _ parentCategoryID: UUID?,
        ownerUserID: UUID,
        categoryByID: [UUID: RemoteTransactionCategory]
    ) -> UUID? {
        guard let parentCategoryID,
              let parentRow = categoryByID[parentCategoryID],
              parentRow.userID == ownerUserID,
              parentRow.isSystem,
              let parentSystemKey = parentRow.systemKey else {
            return parentCategoryID
        }

        return MistiaSystemCategoryIdentity.cloudScopedID(
            canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: parentSystemKey),
            ownerUserID: ownerUserID
        )
    }

    private func preferredRemoteCategory(
        _ lhs: RemoteTransactionCategory,
        _ rhs: RemoteTransactionCategory
    ) -> RemoteTransactionCategory {
        remoteCategoryScore(lhs) >= remoteCategoryScore(rhs) ? lhs : rhs
    }

    private func remoteCategoryScore(_ row: RemoteTransactionCategory) -> Int {
        var score = Int(row.updatedAt.timeIntervalSince1970)
        if row.deletedAt == nil {
            score += 1_000_000_000
        }
        if row.isSystem,
           let systemKey = row.systemKey,
           row.id == MistiaSystemCategoryIdentity.cloudScopedID(
               canonicalCategoryID: MistiaSystemCategoryIdentity.canonicalID(for: systemKey),
               ownerUserID: row.userID
           ) {
            score += 1_000
        }
        return score
    }

    private func pushLocallyNewerRows(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession,
        progressStart: Double,
        progressEnd: Double
    ) async throws -> Bool {
        let remoteByKey = remoteSnapshot.uploadRecordsByStorageKey
        let locallyNewer = hierarchicalSorted(
            localSnapshot.uploadRecords(where: { localRecord in
                guard let remoteRecord = remoteByKey[localRecord.storageKey] else {
                    return false
                }
                guard localRecord.payloadFingerprint != remoteRecord.payloadFingerprint else {
                    return false
                }
                return preferredAuthority(localDraft: localRecord, remoteRecord: remoteRecord) == .local
            })
        )

        guard !locallyNewer.isEmpty else {
            onProgressUpdate?(progressEnd)
            return false
        }

        let total = locallyNewer.count
        for (index, localRecord) in locallyNewer.enumerated() {
            try Task.checkCancellation()
            let progress = progressStart + (Double(index) / Double(max(1, total))) * (progressEnd - progressStart)
            onProgressUpdate?(progress)

            guard let remoteRecord = remoteByKey[localRecord.storageKey] else { continue }
            _ = try await forcePushLocalRecord(
                localRecord,
                subjectUserID: localRecord.userID,
                remoteVersion: remoteRecord.syncVersion,
                session: session
            )
        }

        onProgressUpdate?(progressEnd)
        return true
    }

    @discardableResult
    private func applySnapshot(_ snapshot: MistiaRemoteSnapshot) async throws -> String {
        let fingerprint = await persistenceWorker.fingerprint(of: snapshot)
        guard fingerprint != lastSnapshotFingerprint else {
            return fingerprint
        }

        // preserveLocalNewerRows: true guards against a stale snapshot overwriting
        // a record that was just successfully pushed (e.g. unarchiving an event).
        // The pushed record already has applyRemoteRecord applied with the server's
        // newer updatedAt, so any snapshot row with an older timestamp is skipped.
        try await persistenceWorker.applySnapshot(
            snapshot,
            protectedRecordIDs: queuedMutationIDs(),
            preserveLocalNewerRows: true
        )
        lastSnapshotFingerprint = fingerprint
        return fingerprint
    }

    private func resolveConflictingRecords(
        entity: MistiaSyncEntity,
        recordID: UUID,
        kind: MistiaSyncConflictKind,
        localDraft: MistiaSyncUploadRecord,
        remoteRecord: MistiaSyncUploadRecord,
        baseVersion: Int64,
        remoteVersion: Int64,
        subjectUserID: UUID,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        switch preferredAuthority(localDraft: localDraft, remoteRecord: remoteRecord) {
        case .local:
            _ = try await forcePushLocalRecord(
                localDraft,
                subjectUserID: subjectUserID,
                remoteVersion: remoteVersion,
                session: session
            )
            return true
        case .remote:
            try await persistenceWorker.applyRemoteRecord(remoteRecord)
            return false
        case .unresolved:
            try await handleConflict(
                entity: entity,
                recordID: recordID,
                kind: kind,
                localDraft: localDraft,
                remoteRecord: remoteRecord,
                baseVersion: baseVersion,
                remoteVersion: remoteVersion
            )
            return false
        }
    }

    private func forcePushLocalRecord(
        _ localRecord: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        remoteVersion: Int64,
        session: SupabaseAuthSession
    ) async throws -> MistiaSyncUploadRecord {
        try await ensureRemoteCategoryDependenciesExistIfNeeded(
            for: localRecord,
            subjectUserID: subjectUserID,
            session: session
        )
        let nextVersion = max(max(remoteVersion, localRecord.syncVersion), 0) + 1
        let authoritativeRecord = localRecord.preparedForMutation(
            nextVersion: nextVersion,
            deviceID: deviceID
        )
        let pushedRecord = try await remoteStore.forceUpsert(
            authoritativeRecord,
            subjectUserID: subjectUserID,
            session: session
        )
        try await persistenceWorker.applyRemoteRecord(pushedRecord)
        try await createFamilyActivityNotificationIfNeeded(
            for: pushedRecord,
            subjectUserID: subjectUserID,
            action: pushedRecord.deletedAt == nil ? .updated : .deleted,
            session: session
        )
        return pushedRecord
    }

    private func createFamilyActivityNotificationIfNeeded(
        for record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        action: FamilyActivityNotificationAction,
        session: SupabaseAuthSession
    ) async throws {
        guard session.user.id != subjectUserID else { return }

        guard let resourceType = familyNotificationResourceType(for: record.entity) else {
            return
        }

        let actorName = familyActivityActorName(session: session)
        let event = RemoteFamilyActivityNotificationEvent(
            recipientUserID: subjectUserID,
            resourceType: resourceType,
            resourceID: record.id,
            sourceEventKey: familyActivitySourceEventKey(
                record: record,
                action: action,
                actorUserID: session.user.id
            ),
            title: familyActivityTitle(action: action, resourceType: resourceType),
            body: familyActivityBody(
                record: record,
                action: action,
                resourceType: resourceType,
                actorName: actorName
            ),
            metadata: familyActivityMetadata(record: record, action: action, actorName: actorName)
        )

        do {
            try await remoteStore.createFamilyActivityNotification(event, session: session)
        } catch {
            if error is CancellationError {
                throw error
            }
            Self.logger.warning("Family activity notification sync skipped: \(String(describing: error), privacy: .public)")
        }
    }

    private func familyActivityActorName(session: SupabaseAuthSession) -> String {
        let candidates = [
            session.user.userMetadata?.displayName,
            session.user.userMetadata?.fullName,
            session.user.userMetadata?.name,
            session.user.email
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? L10n.shared.sync.mistiasynccoordinator.aFamilyMember
    }

    private func familyNotificationResourceType(
        for entity: MistiaSyncEntity
    ) -> MistiaFamilyNotificationResourceType? {
        switch entity {
        case .wallet:
            return .wallet
        case .category:
            return .category
        case .transaction:
            return .transaction
        case .budgetPlan:
            return .budget
        case .savingsGoal:
            return .goal
        case .recurringBillPlan:
            return .bill
        case .installmentPlan:
            return .installment
        default:
            return nil
        }
    }

    private func familyActivitySourceEventKey(
        record: MistiaSyncUploadRecord,
        action: FamilyActivityNotificationAction,
        actorUserID: UUID
    ) -> String {
        [
            "family-activity",
            record.entity.rawValue,
            record.id.uuidString.lowercased(),
            action.rawValue,
            "\(record.syncVersion)",
            actorUserID.uuidString.lowercased()
        ].joined(separator: ":")
    }

    private func familyActivityTitle(
        action: FamilyActivityNotificationAction,
        resourceType: MistiaFamilyNotificationResourceType
    ) -> String {
        switch (resourceType, action) {
        case (.transaction, .created):
            return L10n.shared.sync.mistiasynccoordinator.newTransaction
        case (.transaction, .updated):
            return L10n.shared.sync.mistiasynccoordinator.transactionUpdated
        case (.transaction, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.transactionDeleted
        case (.category, .updated), (.category, .created):
            return L10n.shared.sync.mistiasynccoordinator.categoryUpdated
        case (.category, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.categoryDeleted
        case (.wallet, .updated), (.wallet, .created):
            return L10n.shared.sync.mistiasynccoordinator.walletUpdated
        case (.wallet, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.walletDeleted
        case (.budget, .updated), (.budget, .created):
            return L10n.shared.sync.mistiasynccoordinator.budgetUpdated
        case (.budget, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.budgetDeleted
        case (.goal, .updated), (.goal, .created):
            return L10n.shared.sync.mistiasynccoordinator.goalUpdated
        case (.goal, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.goalDeleted
        case (.bill, .updated), (.bill, .created):
            return L10n.shared.sync.mistiasynccoordinator.billUpdated
        case (.bill, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.billDeleted
        case (.installment, .updated), (.installment, .created):
            return L10n.shared.sync.mistiasynccoordinator.installmentUpdated
        case (.installment, .deleted):
            return L10n.shared.sync.mistiasynccoordinator.installmentDeleted
        default:
            return L10n.shared.sync.mistiasynccoordinator.familyActivity
        }
    }

    private func familyActivityBody(
        record: MistiaSyncUploadRecord,
        action: FamilyActivityNotificationAction,
        resourceType: MistiaFamilyNotificationResourceType,
        actorName: String
    ) -> String {
        switch (record, action) {
        case (.transaction(let row), .created):
            let label = row.title.isEmpty ? L10n.shared.sync.mistiasynccoordinator.aTransaction : row.title
            if let walletName = familyActivityWalletName(for: row.sourceWalletID) {
                return L10n.shared.sync.mistiasynccoordinator.valueUsedYourValueWalletToCreate(String(describing: actorName), String(describing: walletName), String(describing: label))
            }
            return L10n.shared.sync.mistiasynccoordinator.valueUsedYourWalletToCreateValue(String(describing: actorName), String(describing: label))
        case (.transaction(let row), .updated):
            let label = row.title.isEmpty ? L10n.shared.sync.mistiasynccoordinator.aTransaction : row.title
            return L10n.shared.sync.mistiasynccoordinator.valueEditedValueOnYourWallet(String(describing: actorName), String(describing: label))
        case (.transaction(let row), .deleted):
            let label = row.title.isEmpty ? L10n.shared.sync.mistiasynccoordinator.aTransaction : row.title
            return L10n.shared.sync.mistiasynccoordinator.valueDeletedValueOnYourWallet(String(describing: actorName), String(describing: label))
        case (.wallet(let row), _):
            return L10n.shared.sync.mistiasynccoordinator.valueUpdatedYourValueWallet(String(describing: actorName), String(describing: row.name))
        case (.category(let row), _):
            return L10n.shared.sync.mistiasynccoordinator.valueUpdatedYourValueCategory(String(describing: actorName), String(describing: row.name))
        case (.budgetPlan(_), _):
            return L10n.shared.sync.mistiasynccoordinator.valueUpdatedYourBudget(String(describing: actorName))
        case (.savingsGoal(let row), _):
            return L10n.shared.sync.mistiasynccoordinator.valueUpdatedYourValueGoal(String(describing: actorName), String(describing: row.name))
        case (.recurringBillPlan(let row), _):
            return L10n.shared.sync.mistiasynccoordinator.valueUpdatedYourValueBill(String(describing: actorName), String(describing: row.name))
        case (.installmentPlan(let row), _):
            return L10n.shared.sync.mistiasynccoordinator.valueUpdatedYourValueInstallment(String(describing: actorName), String(describing: row.name))
        default:
            switch resourceType {
            case .transaction:
                return L10n.shared.sync.mistiasynccoordinator.valueChangedOneOfYourTransactions(String(describing: actorName))
            default:
                return L10n.shared.sync.mistiasynccoordinator.valueChangedYourData(String(describing: actorName))
            }
        }
    }

    private func familyActivityMetadata(
        record: MistiaSyncUploadRecord,
        action: FamilyActivityNotificationAction,
        actorName: String
    ) -> [String: String] {
        var metadata: [String: String] = [
            "action": action.rawValue,
            "entity": record.entity.rawValue,
            "record_id": record.id.uuidString.lowercased(),
            "actor_name": actorName
        ]

        switch record {
        case .transaction(let row):
            metadata["amount_minor"] = "\(row.amountMinor)"
            metadata["transaction_title"] = row.title
            metadata["source_wallet_id"] = row.sourceWalletID?.uuidString.lowercased()
            metadata["destination_wallet_id"] = row.destinationWalletID?.uuidString.lowercased()
        case .wallet(let row):
            metadata["wallet_name"] = row.name
        case .category(let row):
            metadata["category_name"] = row.name
        case .savingsGoal(let row):
            metadata["goal_name"] = row.name
        case .recurringBillPlan(let row):
            metadata["bill_name"] = row.name
        case .installmentPlan(let row):
            metadata["installment_name"] = row.name
        default:
            break
        }

        return metadata.filter { !$0.value.isEmpty }
    }

    private func familyActivityWalletName(for walletID: UUID?) -> String? {
        guard let walletID else {
            return nil
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<LedgerWallet>(
            predicate: #Predicate { $0.id == walletID }
        )
        guard let wallet = try? context.fetch(descriptor).first else {
            return nil
        }
        let name = wallet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func preferredAuthority(
        localDraft: MistiaSyncUploadRecord,
        remoteRecord: MistiaSyncUploadRecord
    ) -> RecordAuthority {
        if localDraft.payloadFingerprint == remoteRecord.payloadFingerprint {
            return .remote
        }

        if localDraft.updatedAt > remoteRecord.updatedAt {
            return .local
        }

        if remoteRecord.updatedAt > localDraft.updatedAt {
            return .remote
        }

        if localDraft.deletedAt != nil, remoteRecord.deletedAt == nil {
            return .local
        }

        if remoteRecord.deletedAt != nil, localDraft.deletedAt == nil {
            return .remote
        }

        if localDraft.syncVersion > remoteRecord.syncVersion {
            return .local
        }

        if remoteRecord.syncVersion > localDraft.syncVersion {
            return .remote
        }

        return .unresolved
    }

    private func handleConflict(
        entity: MistiaSyncEntity,
        recordID: UUID,
        kind: MistiaSyncConflictKind,
        localDraft: MistiaSyncUploadRecord,
        remoteRecord: MistiaSyncUploadRecord,
        baseVersion: Int64,
        remoteVersion: Int64
    ) async throws {
        try await persistenceWorker.saveConflictAndApplyRemote(
            entity: entity,
            recordID: recordID,
            kind: kind,
            localDraft: localDraft,
            remoteRecord: remoteRecord,
            baseVersion: baseVersion,
            remoteVersion: remoteVersion
        )
    }

    private func hierarchicalSorted(_ records: [MistiaSyncUploadRecord]) -> [MistiaSyncUploadRecord] {
        records.sorted { a, b in
            if a.entity.pushPriority != b.entity.pushPriority {
                return a.entity.pushPriority < b.entity.pushPriority
            }

            if a.entity == .category && b.entity == .category {
                let aParent = a.parentID
                let bParent = b.parentID

                if aParent == nil && bParent != nil { return true }
                if aParent != nil && bParent == nil { return false }
            }

            return false
        }
    }

    private func synthesizedDeletedRecord(
        from record: MistiaSyncUploadRecord,
        remoteVersion: Int64
    ) -> MistiaSyncUploadRecord {
        let deletedAt = record.updatedAt

        switch record {
        case .wallet(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .wallet(row)
        case .creditCardProfile(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .creditCardProfile(row)
        case .category(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .category(row)
        case .settlementGroup(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .settlementGroup(row)
        case .settlementParticipant(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .settlementParticipant(row)
        case .transaction(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .transaction(row)
        case .budgetPlan(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .budgetPlan(row)
        case .savingsGoal(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .savingsGoal(row)
        case .recurringBillPlan(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .recurringBillPlan(row)
        case .installmentPlan(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .installmentPlan(row)
        case .dueOccurrence(var row):
            row.deletedAt = deletedAt
            row.syncVersion = max(remoteVersion, row.syncVersion)
            row.lastModifiedByDeviceID = nil
            return .dueOccurrence(row)
        }
    }
}

private enum RecordAuthority {
    case local
    case remote
    case unresolved
}
