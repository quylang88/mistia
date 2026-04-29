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
        let rawRemoteSnapshot = try await fetchRawSnapshot(session: session)
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

        let sortedMutations = mutations.sorted { a, b in
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
        var rawRemoteSnapshot = try await fetchRawSnapshot(session: session)
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
            rawRemoteSnapshot = try await fetchRawSnapshot(session: session)
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
            rawRemoteSnapshot = try await fetchRawSnapshot(session: session)
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
            try MistiaSyncLocalStore.applyRemoteRecord(localRecord, in: modelContainer)
            outbox.enqueue(
                MistiaSyncMutation(
                    entity: conflict.entity,
                    recordID: conflict.recordID,
                    subjectUserID: localRecord.userID,
                    kind: localRecord.deletedAt == nil ? .upsert : .delete,
                    modifiedAt: localRecord.updatedAt,
                    baseVersion: conflict.remoteVersion,
                    deviceID: deviceID
                )
            )
            try MistiaSyncLocalStore.removeConflict(id: id, from: modelContainer)
            _ = try await sync(session: session)
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

        let remoteRecord = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: mutation.recordID,
            subjectUserID: mutation.subjectUserID,
            session: session
        )

        if let remoteRecord, remoteRecord.payloadFingerprint == localRecord.payloadFingerprint {
            try MistiaSyncLocalStore.applyRemoteRecord(remoteRecord, in: modelContainer)
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
            await createFamilyActivityNotificationIfNeeded(
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
            await createFamilyActivityNotificationIfNeeded(
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
            recordID: mutation.recordID,
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
            recordID: mutation.recordID,
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
            recordID: mutation.recordID,
            subjectUserID: mutation.subjectUserID,
            expectedVersion: mutation.baseVersion,
            modifiedAt: mutation.modifiedAt,
            deviceID: deviceID,
            session: session
        ) {
            try MistiaSyncLocalStore.applyRemoteRecord(deletedRecord, in: modelContainer)
            await createFamilyActivityNotificationIfNeeded(
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
            recordID: mutation.recordID,
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

            _ = try await remoteStore.create(
                localRecord.preparedForCreate(deviceID: deviceID),
                subjectUserID: localRecord.userID,
                session: session
            )
        }
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
        try await fetchRawSnapshot(session: session)
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
        await createFamilyActivityNotificationIfNeeded(
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
    ) async {
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

        try? await remoteStore.createFamilyActivityNotification(event, session: session)
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
        case .transaction:
            return .transaction
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
        case (.wallet, .updated), (.wallet, .created):
            return mistiaLocalized(vi: "Ví đã cập nhật", en: "Wallet updated", ja: "ウォレットが更新されました")
        case (.wallet, .deleted):
            return mistiaLocalized(vi: "Ví đã xóa", en: "Wallet deleted", ja: "ウォレットが削除されました")
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
            return mistiaLocalized(
                vi: "\(actorName) vừa tạo \(label) trên ví của bạn.",
                en: "\(actorName) created \(label) on your wallet.",
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
        default:
            break
        }

        return metadata.filter { !$0.value.isEmpty }
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
        Dictionary(uniqueKeysWithValues: allRecords.map { ($0.storageKey, $0) })
    }
}

private extension MistiaSyncUploadRecord {
    var storageKey: String {
        "\(entity.rawValue):\(id.uuidString.lowercased())"
    }
}
