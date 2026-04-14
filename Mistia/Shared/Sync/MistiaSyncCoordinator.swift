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
        let remoteSnapshot = reconcileLegacySystemCategoryRows(in: rawRemoteSnapshot)
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

        let snapshot = reconcileLegacySystemCategoryRows(in: rawRemoteSnapshot)
        onProgressUpdate?(0.85)
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
                try handleConflict(
                    entity: mutation.entity,
                    recordID: mutation.recordID,
                    kind: conflictKind,
                    localDraft: localRecord,
                    remoteRecord: remoteRecord ?? synthesizedDeletedRecord(from: localRecord, remoteVersion: 1),
                    baseVersion: mutation.baseVersion,
                    remoteVersion: remoteRecord?.syncVersion ?? 1
                )
                outbox.remove(mutation)
                return false
            }

            let created = try await remoteStore.create(
                localRecord.preparedForCreate(deviceID: deviceID),
                subjectUserID: mutation.subjectUserID,
                session: session
            )
            try MistiaSyncLocalStore.applyRemoteRecord(created, in: modelContainer)
            outbox.remove(mutation)
            return true
        }

        guard let remoteRecord else {
            let deletedRemote = synthesizedDeletedRecord(
                from: localRecord,
                remoteVersion: mutation.baseVersion
            )
            try handleConflict(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .editDelete,
                localDraft: localRecord,
                remoteRecord: deletedRemote,
                baseVersion: mutation.baseVersion,
                remoteVersion: mutation.baseVersion
            )
            outbox.remove(mutation)
            return false
        }

        if remoteRecord.deletedAt != nil {
            try handleConflict(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .editDelete,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: mutation.baseVersion,
                remoteVersion: remoteRecord.syncVersion
            )
            outbox.remove(mutation)
            return false
        }

        if remoteRecord.syncVersion != mutation.baseVersion {
            try handleConflict(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .editEdit,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: mutation.baseVersion,
                remoteVersion: remoteRecord.syncVersion
            )
            outbox.remove(mutation)
            return false
        }

        if let updated = try await remoteStore.conditionalUpdate(
            localRecord.preparedForMutation(nextVersion: mutation.baseVersion + 1, deviceID: deviceID),
            expectedVersion: mutation.baseVersion,
            subjectUserID: mutation.subjectUserID,
            session: session
        ) {
            try MistiaSyncLocalStore.applyRemoteRecord(updated, in: modelContainer)
            outbox.remove(mutation)
            return true
        }

        let latestRemote = try await remoteStore.fetchRecord(
            entity: mutation.entity,
            recordID: mutation.recordID,
            subjectUserID: mutation.subjectUserID,
            session: session
        ) ?? synthesizedDeletedRecord(from: localRecord, remoteVersion: mutation.baseVersion + 1)

        try handleConflict(
            entity: mutation.entity,
            recordID: mutation.recordID,
            kind: latestRemote.deletedAt == nil ? .editEdit : .editDelete,
            localDraft: localRecord,
            remoteRecord: latestRemote,
            baseVersion: mutation.baseVersion,
            remoteVersion: latestRemote.syncVersion
        )
        outbox.remove(mutation)
        return false
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
            try handleConflict(
                entity: mutation.entity,
                recordID: mutation.recordID,
                kind: .deleteEdit,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: mutation.baseVersion,
                remoteVersion: remoteRecord.syncVersion
            )
            outbox.remove(mutation)
            return false
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

        try handleConflict(
            entity: mutation.entity,
            recordID: mutation.recordID,
            kind: .deleteEdit,
            localDraft: localRecord,
            remoteRecord: latestRemote,
            baseVersion: mutation.baseVersion,
            remoteVersion: latestRemote.syncVersion
        )
        outbox.remove(mutation)
        return false
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

            try handleConflict(
                entity: localRecord.entity,
                recordID: localRecord.id,
                kind: conflictKind,
                localDraft: localRecord,
                remoteRecord: remoteRecord,
                baseVersion: localRecord.syncVersion,
                remoteVersion: remoteRecord.syncVersion
            )
        }

        try applySnapshot(reconcileLegacySystemCategoryRows(in: remoteSnapshot))
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
        let snapshot = try await fetchRawSnapshot(session: session)
        return reconcileLegacySystemCategoryRows(in: snapshot)
    }

    private func reconcileLegacySystemCategoryRows(
        in snapshot: MistiaRemoteSnapshot
    ) -> MistiaRemoteSnapshot {
        let activeSystemCategories = snapshot.categories.filter {
            $0.deletedAt == nil && $0.isSystem && $0.systemKey != nil
        }
        guard !activeSystemCategories.isEmpty else { return snapshot }

        let categoryByID = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
        let referencedCategoryIDs = referencedCategoryIDs(in: snapshot)
        let groupedBySystemKey = Dictionary(grouping: activeSystemCategories) { $0.systemKey ?? "" }

        var winnersBySystemKey: [String: RemoteTransactionCategory] = [:]
        var parentSystemKeyBySystemKey: [String: String?] = [:]
        var keptSystemKeys: Set<String> = []

        for (systemKey, rows) in groupedBySystemKey where !systemKey.isEmpty {
            let winner = preferredRemoteSystemCategory(
                in: rows,
                referencedCategoryIDs: referencedCategoryIDs,
                categoryByID: categoryByID
            )
            winnersBySystemKey[systemKey] = winner

            let parentSystemKey = winner.parentCategoryID.flatMap { categoryByID[$0]?.systemKey }
            parentSystemKeyBySystemKey[systemKey] = parentSystemKey

            let hasCustomizedRow = rows.contains {
                MistiaSystemCategorySyncSupport.isCustomizedRemoteSystemCategory(
                    $0,
                    parentSystemKey: $0.parentCategoryID.flatMap { categoryByID[$0]?.systemKey }
                )
            }

            if hasCustomizedRow {
                keptSystemKeys.insert(systemKey)
            }
        }

        var categoryRemappings: [UUID: UUID] = [:]
        var transformedSystemCategories: [RemoteTransactionCategory] = []

        for (systemKey, rows) in groupedBySystemKey where !systemKey.isEmpty {
            guard let winner = winnersBySystemKey[systemKey] else { continue }
            let parentSystemKey = parentSystemKeyBySystemKey[systemKey] ?? nil
            let canonicalID = MistiaSystemCategoryIdentity.canonicalID(for: systemKey)
            let canonicalRow = MistiaSystemCategorySyncSupport
                .canonicalizedSystemCategoryRow(winner, parentSystemKey: parentSystemKey)

            for row in rows where row.id != canonicalID {
                categoryRemappings[row.id] = canonicalID
            }

            if keptSystemKeys.contains(systemKey) {
                transformedSystemCategories.append(canonicalRow)
            }
        }

        let categories = remappedCategories(
            snapshot.categories,
            categoryRemappings: categoryRemappings,
            transformedSystemCategories: transformedSystemCategories
        )

        return MistiaRemoteSnapshot(
            wallets: snapshot.wallets,
            creditCardProfiles: snapshot.creditCardProfiles,
            categories: categories,
            transactions: snapshot.transactions.map { remappedTransaction($0, mappings: categoryRemappings) },
            budgetPlans: snapshot.budgetPlans.map { remappedBudgetPlan($0, mappings: categoryRemappings) },
            savingsGoals: snapshot.savingsGoals,
            recurringBillPlans: snapshot.recurringBillPlans.map { remappedRecurringBillPlan($0, mappings: categoryRemappings) },
            installmentPlans: snapshot.installmentPlans,
            dueOccurrences: snapshot.dueOccurrences
        )
    }

    private func referencedCategoryIDs(
        in snapshot: MistiaRemoteSnapshot
    ) -> Set<UUID> {
        var ids: Set<UUID> = []

        for row in snapshot.transactions where row.deletedAt == nil {
            if let categoryID = row.categoryID {
                ids.insert(categoryID)
            }
        }

        for row in snapshot.budgetPlans where row.deletedAt == nil {
            if let categoryID = row.categoryID {
                ids.insert(categoryID)
            }
        }

        for row in snapshot.recurringBillPlans where row.deletedAt == nil {
            if let categoryID = row.categoryID {
                ids.insert(categoryID)
            }
        }

        return ids
    }

    private func preferredRemoteSystemCategory(
        in rows: [RemoteTransactionCategory],
        referencedCategoryIDs: Set<UUID>,
        categoryByID: [UUID: RemoteTransactionCategory]
    ) -> RemoteTransactionCategory {
        rows.max { lhs, rhs in
            remoteSystemCategoryPriority(
                lhs,
                referencedCategoryIDs: referencedCategoryIDs,
                categoryByID: categoryByID
            ) < remoteSystemCategoryPriority(
                rhs,
                referencedCategoryIDs: referencedCategoryIDs,
                categoryByID: categoryByID
            )
        } ?? rows[0]
    }

    private func remoteSystemCategoryPriority(
        _ row: RemoteTransactionCategory,
        referencedCategoryIDs: Set<UUID>,
        categoryByID: [UUID: RemoteTransactionCategory]
    ) -> Int {
        var score = 0

        if let systemKey = row.systemKey,
           row.id == MistiaSystemCategoryIdentity.canonicalID(for: systemKey) {
            score += 8
        }
        if referencedCategoryIDs.contains(row.id) {
            score += 16
        }
        if MistiaSystemCategorySyncSupport.isCustomizedRemoteSystemCategory(
            row,
            parentSystemKey: row.parentCategoryID.flatMap { categoryByID[$0]?.systemKey }
        ) {
            score += 32
        }
        score += Int(min(row.syncVersion, 1_000))
        score += Int(row.updatedAt.timeIntervalSince1970 / 1_000_000)

        return score
    }

    private func remappedCategories(
        _ categories: [RemoteTransactionCategory],
        categoryRemappings: [UUID: UUID],
        transformedSystemCategories: [RemoteTransactionCategory]
    ) -> [RemoteTransactionCategory] {
        let transformedSystemKeys = Set(transformedSystemCategories.compactMap(\.systemKey))
        let nonSystemCategories = categories.compactMap { row -> RemoteTransactionCategory? in
            if row.isSystem, let systemKey = row.systemKey {
                if transformedSystemKeys.contains(systemKey) {
                    return nil
                }
                return nil
            }

            var remapped = row
            if let parentCategoryID = row.parentCategoryID,
               let replacementParentID = categoryRemappings[parentCategoryID] {
                remapped.parentCategoryID = replacementParentID
            }
            return remapped
        }

        return nonSystemCategories + transformedSystemCategories
    }

    private func remappedTransaction(
        _ row: RemoteLedgerTransaction,
        mappings: [UUID: UUID]
    ) -> RemoteLedgerTransaction {
        guard !mappings.isEmpty,
              let categoryID = row.categoryID,
              let replacementCategoryID = mappings[categoryID] else {
            return row
        }

        var remapped = row
        remapped.categoryID = replacementCategoryID
        return remapped
    }

    private func remappedBudgetPlan(
        _ row: RemoteBudgetPlan,
        mappings: [UUID: UUID]
    ) -> RemoteBudgetPlan {
        guard !mappings.isEmpty,
              let categoryID = row.categoryID,
              let replacementCategoryID = mappings[categoryID] else {
            return row
        }

        var remapped = row
        remapped.categoryID = replacementCategoryID
        return remapped
    }

    private func remappedRecurringBillPlan(
        _ row: RemoteRecurringBillPlan,
        mappings: [UUID: UUID]
    ) -> RemoteRecurringBillPlan {
        guard !mappings.isEmpty,
              let categoryID = row.categoryID,
              let replacementCategoryID = mappings[categoryID] else {
            return row
        }

        var remapped = row
        remapped.categoryID = replacementCategoryID
        return remapped
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
