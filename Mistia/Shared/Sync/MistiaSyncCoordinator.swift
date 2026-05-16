import Foundation
import SwiftData

enum MistiaSyncResult {
    case idle
    case seeded(Int)
    case pulled(Int)
    case synced(Int)
    case pushedOnly

    var statusMessage: String {
        switch self {
        case .idle:
            return mistiaLocalized(
                vi: "Không có thay đổi mới cần đồng bộ.",
                en: "There are no new changes to sync.",
                ja: "新しく同期する変更はありません。"
            )
        case .seeded(let count):
            return mistiaLocalized(
                vi: "Đã đẩy \(count) bản ghi local lên cloud.",
                en: "Uploaded \(count) local records to the cloud.",
                ja: "ローカルの \(count) 件をクラウドへアップロードしました。"
            )
        case .pulled(let count):
            return mistiaLocalized(
                vi: "Đã nhận \(count) bản ghi từ cloud.",
                en: "Downloaded \(count) records from the cloud.",
                ja: "クラウドから \(count) 件を取得しました。"
            )
        case .synced(let count):
            return mistiaLocalized(
                vi: "Đồng bộ xong \(count) bản ghi.",
                en: "Sync completed across \(count) records.",
                ja: "\(count) 件の同期が完了しました。"
            )
        case .pushedOnly:
            return mistiaLocalized(
                vi: "Đã đẩy thay đổi local lên cloud.",
                en: "Uploaded local changes to the cloud.",
                ja: "ローカル変更をクラウドへアップロードしました。"
            )
        }
    }
}

private enum FamilyActivityNotificationAction: String {
    case created
    case updated
    case deleted
}

private nonisolated struct SyncRemoteSystemCategoryKey: Hashable {
    let userID: UUID
    let systemKey: String
}

@MainActor
final class SyncCoordinator {
    private let modelContainer: ModelContainer
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
        Set(outbox.allMutations.map(\.id))
    }

    func queuedMutations() -> [MistiaSyncMutation] {
        outbox.allMutations
    }

    func clearQueuedMutations() {
        outbox.clear()
    }

    func clearLocalCache() throws {
        lastSnapshotFingerprint = nil
        try MistiaSyncLocalStore.clearAllData(in: modelContainer)
    }

    func previewInitialSync(session: SupabaseAuthSession) async throws -> MistiaInitialSyncPreview {
        let localSnapshot = try MistiaSyncLocalStore.exportSnapshot(
            for: session.user.id,
            from: modelContainer
        )
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
        let localSnapshot = try MistiaSyncLocalStore.exportSnapshot(
            for: session.user.id,
            from: modelContainer
        )
        let uploadReadyLocalSnapshot = try MistiaSyncLocalStore.exportSnapshotForUpload(
            for: session.user.id,
            from: modelContainer
        )
        onProgressUpdate?(0.1)
        let rawRemoteSnapshot = try await fetchReconciledSnapshot(session: session)
        let remoteSnapshot = rawRemoteSnapshot
        onProgressUpdate?(0.2)

        let localCount = localSnapshot.activeRowCount
        let remoteCount = remoteSnapshot.activeRowCount

        if localCount == 0 && remoteCount == 0 {
            lastSnapshotFingerprint = remoteSnapshot.fingerprint
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
            try applySnapshot(mergedSnapshot)
            onProgressUpdate?(1.0)
            return .seeded(mergedSnapshot.activeRowCount)
        }

        if localCount == 0 || choice == .useCloud {
            outbox.clear()
            try clearLocalCache()
            onProgressUpdate?(0.3)
            let freshSnapshot = try await fetchReconciledSnapshot(session: session)
            onProgressUpdate?(0.6)
            try applySnapshot(freshSnapshot)
            onProgressUpdate?(1.0)
            return .pulled(freshSnapshot.activeRowCount)
        }

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
        try applySnapshot(mergedSnapshot)
        onProgressUpdate?(1.0)
        return .synced(mergedSnapshot.activeRowCount)
    }

    func sync(session: SupabaseAuthSession) async throws -> MistiaSyncResult {
        onProgressUpdate?(0.05)
        var pushedMutations = false
        var seededMissingRows = false

        let mutations = outbox.allMutations
        let mutationCount = mutations.count

        let sortedMutations = sortedMutationsForPush(mutations)

        for (index, mutation) in sortedMutations.enumerated() {
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

        onProgressUpdate?(0.55)
        let localSnapshot = try MistiaSyncLocalStore.exportSnapshotForUpload(
            for: session.user.id,
            from: modelContainer
        )
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

        let snapshot = rawRemoteSnapshot
        let previousFingerprint = lastSnapshotFingerprint
        try applySnapshot(snapshot)
        onProgressUpdate?(1.0)

        if seededMissingRows && remoteWasEmpty {
            return .seeded(snapshot.activeRowCount)
        }

        if snapshot.fingerprint != previousFingerprint {
            return (pushedMutations || seededMissingRows) ? .synced(snapshot.activeRowCount) : .pulled(snapshot.activeRowCount)
        }

        return (pushedMutations || seededMissingRows) ? .pushedOnly : .idle
    }

    private func sortedMutationsForPush(_ mutations: [MistiaSyncMutation]) -> [MistiaSyncMutation] {
        mutations.sorted { a, b in
            if a.entity.pushPriority != b.entity.pushPriority {
                return a.entity.pushPriority < b.entity.pushPriority
            }

            if a.entity == .category && b.entity == .category {
                let aRecord = try? MistiaSyncLocalStore.exportRecord(for: a, from: modelContainer)
                let bRecord = try? MistiaSyncLocalStore.exportRecord(for: b, from: modelContainer)
                let aParent = aRecord?.parentID
                let bParent = bRecord?.parentID

                if aParent == nil && bParent != nil { return true }
                if aParent != nil && bParent == nil { return false }
            }

            return a.modifiedAt < b.modifiedAt
        }
    }

    func pushQueuedMutationsOnly(
        _ mutations: [MistiaSyncMutation],
        session: SupabaseAuthSession
    ) async throws -> Bool {
        var pushedMutations = false
        let sortedMutations = sortedMutationsForPush(mutations)

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

    func resolveConflict(
        id: UUID,
        resolution: MistiaSyncConflictResolution,
        session: SupabaseAuthSession
    ) async throws {
        guard let conflict = try MistiaSyncLocalStore.fetchConflict(id: id, from: modelContainer) else {
            return
        }

        switch resolution {
        case .useRemote:
            let remoteRecord = try MistiaSyncUploadRecord.decode(
                entity: conflict.entity,
                jsonString: conflict.remotePayloadJSON
            )
            try MistiaSyncLocalStore.applyRemoteRecord(remoteRecord, in: modelContainer)
            try MistiaSyncLocalStore.removeConflict(id: id, from: modelContainer)
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
            try MistiaSyncLocalStore.removeConflict(id: id, from: modelContainer)
        }
    }

    private func processUpsertMutation(
        _ mutation: MistiaSyncMutation,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        guard let localRecord = try MistiaSyncLocalStore.exportRecord(
            for: mutation,
            from: modelContainer
        ) else {
            outbox.remove(mutation)
            return false
        }
        try await ensureRemoteCategoryParentsExistIfNeeded(
            for: localRecord,
            subjectUserID: mutation.subjectUserID,
            session: session
        )

        let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: mutation.subjectUserID,
            session: session
        )

        if let remoteRecord, remoteRecord.payloadFingerprint == localRecord.payloadFingerprint {
            try MistiaSyncLocalStore.applyRemoteRecord(remoteRecord, in: modelContainer)
            try await createFamilyActivityNotificationIfNeeded(
                for: remoteRecord,
                subjectUserID: mutation.subjectUserID,
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
                    subjectUserID: mutation.subjectUserID,
                    session: session
                )
                outbox.remove(mutation)
                return resolvedLocally
            }

            let created = try await remoteStore.create(
                localRecord.preparedForCreate(deviceID: deviceID),
                subjectUserID: mutation.subjectUserID,
                session: session
            )
            try MistiaSyncLocalStore.applyRemoteRecord(created, in: modelContainer)
            try await createFamilyActivityNotificationIfNeeded(
                for: created,
                subjectUserID: mutation.subjectUserID,
                action: .created,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        guard let remoteRecord else {
            _ = try await forcePushLocalRecord(
                localRecord,
                subjectUserID: mutation.subjectUserID,
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
                subjectUserID: mutation.subjectUserID,
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
                subjectUserID: mutation.subjectUserID,
                session: session
            )
            outbox.remove(mutation)
            return resolvedLocally
        }

        if let updated = try await remoteStore.conditionalUpdate(
            localRecord.preparedForMutation(nextVersion: mutation.baseVersion + 1, deviceID: deviceID),
            expectedVersion: mutation.baseVersion,
            subjectUserID: mutation.subjectUserID,
            session: session
        ) {
            try MistiaSyncLocalStore.applyRemoteRecord(updated, in: modelContainer)
            try await createFamilyActivityNotificationIfNeeded(
                for: updated,
                subjectUserID: mutation.subjectUserID,
                action: .updated,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        let latestRemote = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: mutation.subjectUserID,
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
            subjectUserID: mutation.subjectUserID,
            session: session
        )
        outbox.remove(mutation)
        return resolvedLocally
    }

    private func processDeleteMutation(
        _ mutation: MistiaSyncMutation,
        session: SupabaseAuthSession
    ) async throws -> Bool {
        guard let localRecord = try MistiaSyncLocalStore.exportRecord(
            for: mutation,
            from: modelContainer
        ) else {
            outbox.remove(mutation)
            return false
        }

        let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: mutation.subjectUserID,
            session: session
        )

        guard let remoteRecord else {
            outbox.remove(mutation)
            return false
        }

        if remoteRecord.deletedAt != nil {
            try MistiaSyncLocalStore.applyRemoteRecord(remoteRecord, in: modelContainer)
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
                subjectUserID: mutation.subjectUserID,
                session: session
            )
            outbox.remove(mutation)
            return resolvedLocally
        }

        if let deletedRecord = try await remoteStore.conditionalDelete(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: mutation.subjectUserID,
            expectedVersion: mutation.baseVersion,
            modifiedAt: mutation.modifiedAt,
            deviceID: deviceID,
            session: session
        ) {
            try MistiaSyncLocalStore.applyRemoteRecord(deletedRecord, in: modelContainer)
            try await createFamilyActivityNotificationIfNeeded(
                for: deletedRecord,
                subjectUserID: mutation.subjectUserID,
                action: .deleted,
                session: session
            )
            outbox.remove(mutation)
            return true
        }

        let latestRemote = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: localRecord.id,
            subjectUserID: mutation.subjectUserID,
            session: session
        ) ?? synthesizedDeletedRecord(from: localRecord, remoteVersion: mutation.baseVersion + 1)

        if latestRemote.deletedAt != nil {
            try MistiaSyncLocalStore.applyRemoteRecord(latestRemote, in: modelContainer)
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
            subjectUserID: mutation.subjectUserID,
            session: session
        )
        outbox.remove(mutation)
        return resolvedLocally
    }

    private func mergeInitialSnapshots(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot,
        session: SupabaseAuthSession,
        progressStart: Double,
        progressEnd: Double
    ) async throws {
        let remoteByID = remoteSnapshot.recordsByKey
        let localRecords = hierarchicalSorted(localSnapshot.allRecords)
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
        let remoteByKey = remoteSnapshot.recordsByKey
        let localByKey = localSnapshot.recordsByKey
        let localRecords = hierarchicalSorted(localSnapshot.allRecords).filter { $0.deletedAt == nil }
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

        for remoteRecord in remoteSnapshot.allRecords where localByKey[remoteRecord.storageKey] == nil {
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
        let remoteKeys = Set(remoteSnapshot.allRecords.map(\.storageKey))
        let localOnly = hierarchicalSorted(localSnapshot.allRecords.filter { !remoteKeys.contains($0.storageKey) && $0.deletedAt == nil })
        let total = localOnly.count

        for (index, localRecord) in localOnly.enumerated() {
            let progress = progressStart + (Double(index) / Double(max(1, total))) * (progressEnd - progressStart)
            onProgressUpdate?(progress)

            try await ensureRemoteCategoryParentsExistIfNeeded(
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

    private func ensureRemoteCategoryParentsExistIfNeeded(
        for record: MistiaSyncUploadRecord,
        subjectUserID: UUID,
        session: SupabaseAuthSession,
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
            return
        }

        guard let parentRecord = try MistiaSyncLocalStore.exportCategoryRecord(
            remoteCategoryID: parentID,
            subjectUserID: subjectUserID,
            from: modelContainer
        ) else {
            return
        }

        try await ensureRemoteCategoryParentsExistIfNeeded(
            for: parentRecord,
            subjectUserID: subjectUserID,
            session: session,
            visitedParentIDs: visitedParentIDs.union([parentID])
        )

        let nextVersion = max((remoteParent?.syncVersion ?? parentRecord.syncVersion) + 1, 1)
        let upsertedParent = try await remoteStore.forceUpsert(
            parentRecord.preparedForMutation(nextVersion: nextVersion, deviceID: deviceID),
            subjectUserID: subjectUserID,
            session: session
        )
        try MistiaSyncLocalStore.applyRemoteRecord(upsertedParent, in: modelContainer)
    }

    private func shouldUploadLocalOnlyRows(
        localSnapshot: MistiaRemoteSnapshot,
        remoteSnapshot: MistiaRemoteSnapshot
    ) -> Bool {
        let remoteKeys = Set(remoteSnapshot.allRecords.map(\.storageKey))
        return localSnapshot.allRecords.contains { record in
            record.deletedAt == nil && !remoteKeys.contains(record.storageKey)
        }
    }

    private func fetchRawSnapshot(
        session: SupabaseAuthSession
    ) async throws -> MistiaRemoteSnapshot {
        try await remoteStore.fetchSnapshot(session: session)
    }

    private func fetchReconciledSnapshot(
        session: SupabaseAuthSession
    ) async throws -> MistiaRemoteSnapshot {
        let rawSnapshot = try await fetchRawSnapshot(session: session)
        if try await reconcileOwnedRemoteSystemCategories(rawSnapshot, session: session) {
            return MistiaSystemCategorySyncSupport.deduplicatingRemoteSystemCategories(
                try await fetchRawSnapshot(session: session),
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
        let remoteByKey = remoteSnapshot.recordsByKey
        let locallyNewer = hierarchicalSorted(
            localSnapshot.allRecords.filter { localRecord in
                guard let remoteRecord = remoteByKey[localRecord.storageKey] else {
                    return false
                }
                guard localRecord.payloadFingerprint != remoteRecord.payloadFingerprint else {
                    return false
                }
                return preferredAuthority(localDraft: localRecord, remoteRecord: remoteRecord) == .local
            }
        )

        guard !locallyNewer.isEmpty else {
            onProgressUpdate?(progressEnd)
            return false
        }

        let total = locallyNewer.count
        for (index, localRecord) in locallyNewer.enumerated() {
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

    private func applySnapshot(_ snapshot: MistiaRemoteSnapshot) throws {
        try MistiaSyncLocalStore.applySnapshotIncrementally(
            snapshot,
            shouldPruneMissing: false,
            protectedRecordIDs: queuedMutationIDs(),
            in: modelContainer
        )
        lastSnapshotFingerprint = snapshot.fingerprint
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
            try MistiaSyncLocalStore.applyRemoteRecord(remoteRecord, in: modelContainer)
            return false
        case .unresolved:
            try handleConflict(
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
        try await ensureRemoteCategoryParentsExistIfNeeded(
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
        try MistiaSyncLocalStore.applyRemoteRecord(pushedRecord, in: modelContainer)
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
            throw error
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
            ?? mistiaLocalized(vi: "Một thành viên", en: "A family member", ja: "家族メンバー")
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
            return mistiaLocalized(vi: "Giao dịch mới", en: "New transaction", ja: "新しい取引")
        case (.transaction, .updated):
            return mistiaLocalized(vi: "Giao dịch đã cập nhật", en: "Transaction updated", ja: "取引が更新されました")
        case (.transaction, .deleted):
            return mistiaLocalized(vi: "Giao dịch đã xóa", en: "Transaction deleted", ja: "取引が削除されました")
        case (.category, .updated), (.category, .created):
            return mistiaLocalized(vi: "Danh mục đã cập nhật", en: "Category updated", ja: "カテゴリが更新されました")
        case (.category, .deleted):
            return mistiaLocalized(vi: "Danh mục đã xóa", en: "Category deleted", ja: "カテゴリが削除されました")
        case (.wallet, .updated), (.wallet, .created):
            return mistiaLocalized(vi: "Ví đã cập nhật", en: "Wallet updated", ja: "ウォレットが更新されました")
        case (.wallet, .deleted):
            return mistiaLocalized(vi: "Ví đã xóa", en: "Wallet deleted", ja: "ウォレットが削除されました")
        case (.budget, .updated), (.budget, .created):
            return mistiaLocalized(vi: "Ngân sách đã cập nhật", en: "Budget updated", ja: "予算が更新されました")
        case (.budget, .deleted):
            return mistiaLocalized(vi: "Ngân sách đã xóa", en: "Budget deleted", ja: "予算が削除されました")
        case (.goal, .updated), (.goal, .created):
            return mistiaLocalized(vi: "Mục tiêu đã cập nhật", en: "Goal updated", ja: "目標が更新されました")
        case (.goal, .deleted):
            return mistiaLocalized(vi: "Mục tiêu đã xóa", en: "Goal deleted", ja: "目標が削除されました")
        case (.bill, .updated), (.bill, .created):
            return mistiaLocalized(vi: "Hóa đơn đã cập nhật", en: "Bill updated", ja: "請求が更新されました")
        case (.bill, .deleted):
            return mistiaLocalized(vi: "Hóa đơn đã xóa", en: "Bill deleted", ja: "請求が削除されました")
        case (.installment, .updated), (.installment, .created):
            return mistiaLocalized(vi: "Trả góp đã cập nhật", en: "Installment updated", ja: "分割払いが更新されました")
        case (.installment, .deleted):
            return mistiaLocalized(vi: "Trả góp đã xóa", en: "Installment deleted", ja: "分割払いが削除されました")
        default:
            return mistiaLocalized(vi: "Hoạt động gia đình", en: "Family activity", ja: "家族のアクティビティ")
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
            let label = row.title.isEmpty ? mistiaLocalized(vi: "một giao dịch", en: "a transaction", ja: "取引") : row.title
            if let walletName = familyActivityWalletName(for: row.sourceWalletID) {
                return mistiaLocalized(
                    vi: "\(actorName) vừa sử dụng ví \(walletName) của bạn để tạo \(label).",
                    en: "\(actorName) used your \(walletName) wallet to create \(label).",
                    ja: "\(actorName)があなたの\(walletName)ウォレットで\(label)を作成しました。"
                )
            }
            return mistiaLocalized(
                vi: "\(actorName) vừa sử dụng ví của bạn để tạo \(label).",
                en: "\(actorName) used your wallet to create \(label).",
                ja: "\(actorName)があなたのウォレットで\(label)を作成しました。"
            )
        case (.transaction(let row), .updated):
            let label = row.title.isEmpty ? mistiaLocalized(vi: "một giao dịch", en: "a transaction", ja: "取引") : row.title
            return mistiaLocalized(
                vi: "\(actorName) vừa chỉnh sửa \(label) trên ví của bạn.",
                en: "\(actorName) edited \(label) on your wallet.",
                ja: "\(actorName)があなたのウォレットの\(label)を編集しました。"
            )
        case (.transaction(let row), .deleted):
            let label = row.title.isEmpty ? mistiaLocalized(vi: "một giao dịch", en: "a transaction", ja: "取引") : row.title
            return mistiaLocalized(
                vi: "\(actorName) vừa xóa \(label) trên ví của bạn.",
                en: "\(actorName) deleted \(label) on your wallet.",
                ja: "\(actorName)があなたのウォレットの\(label)を削除しました。"
            )
        case (.wallet(let row), _):
            return mistiaLocalized(
                vi: "\(actorName) vừa cập nhật ví \(row.name) của bạn.",
                en: "\(actorName) updated your \(row.name) wallet.",
                ja: "\(actorName)があなたの\(row.name)ウォレットを更新しました。"
            )
        case (.category(let row), _):
            return mistiaLocalized(
                vi: "\(actorName) vừa cập nhật danh mục \(row.name) của bạn.",
                en: "\(actorName) updated your \(row.name) category.",
                ja: "\(actorName)があなたのカテゴリ\(row.name)を更新しました。"
            )
        case (.budgetPlan(_), _):
            return mistiaLocalized(
                vi: "\(actorName) vừa cập nhật ngân sách của bạn.",
                en: "\(actorName) updated your budget.",
                ja: "\(actorName)があなたの予算を更新しました。"
            )
        case (.savingsGoal(let row), _):
            return mistiaLocalized(
                vi: "\(actorName) vừa cập nhật mục tiêu \(row.name) của bạn.",
                en: "\(actorName) updated your \(row.name) goal.",
                ja: "\(actorName)があなたの目標\(row.name)を更新しました。"
            )
        case (.recurringBillPlan(let row), _):
            return mistiaLocalized(
                vi: "\(actorName) vừa cập nhật hóa đơn \(row.name) của bạn.",
                en: "\(actorName) updated your \(row.name) bill.",
                ja: "\(actorName)があなたの請求\(row.name)を更新しました。"
            )
        case (.installmentPlan(let row), _):
            return mistiaLocalized(
                vi: "\(actorName) vừa cập nhật trả góp \(row.name) của bạn.",
                en: "\(actorName) updated your \(row.name) installment.",
                ja: "\(actorName)があなたの分割払い\(row.name)を更新しました。"
            )
        default:
            switch resourceType {
            case .transaction:
                return mistiaLocalized(
                    vi: "\(actorName) vừa thao tác trên giao dịch của bạn.",
                    en: "\(actorName) changed one of your transactions.",
                    ja: "\(actorName)があなたの取引を変更しました。"
                )
            default:
                return mistiaLocalized(
                    vi: "\(actorName) vừa thao tác trên dữ liệu của bạn.",
                    en: "\(actorName) changed your data.",
                    ja: "\(actorName)があなたのデータを変更しました。"
                )
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

private extension MistiaRemoteSnapshot {
    var allRecords: [MistiaSyncUploadRecord] {
        wallets.map(MistiaSyncUploadRecord.wallet)
            + creditCardProfiles.map(MistiaSyncUploadRecord.creditCardProfile)
            + categories.map(MistiaSyncUploadRecord.category)
            + transactions.map(MistiaSyncUploadRecord.transaction)
            + budgetPlans.map(MistiaSyncUploadRecord.budgetPlan)
            + savingsGoals.map(MistiaSyncUploadRecord.savingsGoal)
            + recurringBillPlans.map(MistiaSyncUploadRecord.recurringBillPlan)
            + installmentPlans.map(MistiaSyncUploadRecord.installmentPlan)
            + dueOccurrences.map(MistiaSyncUploadRecord.dueOccurrence)
    }

    var recordsByKey: [String: MistiaSyncUploadRecord] {
        Dictionary(allRecords.map { ($0.storageKey, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}

private extension MistiaSyncUploadRecord {
    var storageKey: String {
        "\(entity.rawValue):\(id.uuidString.lowercased())"
    }
}
