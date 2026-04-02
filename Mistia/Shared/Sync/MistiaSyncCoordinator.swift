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
                vi: "Cloud đang rỗng và chưa có dữ liệu local để đẩy lên.",
                en: "Cloud is empty and there is no local data to upload yet.",
                ja: "クラウドは空で、まだアップロードするローカルデータがありません。"
            )
        case .seeded(let count):
            return mistiaLocalized(
                vi: "Đã đẩy \(count) bản ghi local lên cloud.",
                en: "Uploaded \(count) local records to the cloud.",
                ja: "ローカルの \(count) 件をクラウドへアップロードしました。"
            )
        case .pulled(let count):
            return mistiaLocalized(
                vi: "Đã nhận \(count) bản ghi mới từ cloud.",
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
    private let remoteStore: SupabaseRemoteStore
    private let outbox: MistiaSyncOutbox

    private var lastSnapshotFingerprint: String?

    init(
        modelContainer: ModelContainer,
        remoteStore: SupabaseRemoteStore? = nil,
        outbox: MistiaSyncOutbox? = nil
    ) {
        self.modelContainer = modelContainer
        self.remoteStore = remoteStore ?? SupabaseRemoteStore()
        self.outbox = outbox ?? MistiaSyncOutbox()
    }

    func queue(_ mutation: MistiaSyncMutation) {
        outbox.enqueue(mutation)
    }

    func queue(_ mutations: [MistiaSyncMutation]) {
        outbox.enqueue(mutations)
    }

    func clearQueuedMutations() {
        outbox.clear()
    }

    func clearLocalCache() throws {
        lastSnapshotFingerprint = nil
        try MistiaSyncLocalStore.clearAllData(in: modelContainer)
    }

    func performInitialSync(session: SupabaseAuthSession) async throws -> MistiaSyncResult {
        let remoteSnapshot = try await remoteStore.fetchSnapshot(session: session)
        if remoteSnapshot.hasRemoteData {
            outbox.clear()
            try MistiaSyncLocalStore.replaceLocalData(with: remoteSnapshot, in: modelContainer)
            lastSnapshotFingerprint = remoteSnapshot.fingerprint
            return .pulled(remoteSnapshot.activeRowCount)
        }

        let localSnapshot = try MistiaSyncLocalStore.exportSnapshot(
            for: session.user.id,
            from: modelContainer
        )

        guard localSnapshot.activeRowCount > 0 else {
            lastSnapshotFingerprint = remoteSnapshot.fingerprint
            return .idle
        }

        try await remoteStore.uploadSeed(snapshot: localSnapshot, session: session)
        lastSnapshotFingerprint = localSnapshot.fingerprint
        return .seeded(localSnapshot.activeRowCount)
    }

    func sync(session: SupabaseAuthSession) async throws -> MistiaSyncResult {
        var pushedMutations = false
        var shouldPull = false

        for mutation in outbox.allMutations {
            let remoteVersion = try await remoteStore.fetchVersion(
                for: mutation.entity,
                recordID: mutation.recordID,
                session: session
            )

            switch mutation.kind {
            case .upsert:
                guard let record = try MistiaSyncLocalStore.exportRecord(
                    for: mutation,
                    userID: session.user.id,
                    from: modelContainer
                ) else {
                    outbox.remove(mutation)
                    continue
                }

                if let remoteVersion, remoteVersion.updatedAt > record.updatedAt {
                    outbox.remove(mutation)
                    shouldPull = true
                    continue
                }

                try await remoteStore.upsert(record, session: session)
                outbox.remove(mutation)
                pushedMutations = true
                shouldPull = true
            case .delete:
                if let remoteVersion, remoteVersion.updatedAt > mutation.modifiedAt {
                    outbox.remove(mutation)
                    shouldPull = true
                    continue
                }

                try await remoteStore.softDelete(
                    entity: mutation.entity,
                    recordID: mutation.recordID,
                    modifiedAt: mutation.modifiedAt,
                    session: session
                )
                outbox.remove(mutation)
                pushedMutations = true
                shouldPull = true
            }
        }

        let snapshot = try await remoteStore.fetchSnapshot(session: session)
        let fingerprint = snapshot.fingerprint

        if fingerprint != lastSnapshotFingerprint {
            try MistiaSyncLocalStore.replaceLocalData(with: snapshot, in: modelContainer)
            lastSnapshotFingerprint = fingerprint
            return pushedMutations ? .synced(snapshot.activeRowCount) : .pulled(snapshot.activeRowCount)
        }

        lastSnapshotFingerprint = fingerprint
        return pushedMutations || shouldPull ? .pushedOnly : .idle
    }
}
