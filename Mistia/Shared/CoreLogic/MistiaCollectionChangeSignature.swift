import Foundation
import os

struct MistiaCollectionChangeSignature: Hashable {
    private static let log = OSLog(
        subsystem: "Mistia",
        category: "CollectionChangeSignature"
    )

    let count: Int
    let latestUpdatedAt: TimeInterval?
    let latestDeletedAt: TimeInterval?
    let latestRemoteVersion: Int64
    let archivedCount: Int

    static let empty = MistiaCollectionChangeSignature(
        count: 0,
        latestUpdatedAt: nil,
        latestDeletedAt: nil,
        latestRemoteVersion: 0,
        archivedCount: 0
    )

    static func make<Records: Sequence, Record>(
        _ records: Records,
        updatedAt: KeyPath<Record, Date>,
        deletedAt: KeyPath<Record, Date?>,
        isArchived: KeyPath<Record, Bool>? = nil,
        remoteVersion: KeyPath<Record, Int64>? = nil
    ) -> MistiaCollectionChangeSignature where Records.Element == Record {
        if let col = records as? any Collection, col.isEmpty {
            return .empty
        }

        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "MistiaCollectionChangeSignature.make", signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: "MistiaCollectionChangeSignature.make", signpostID: signpostID)
        }

        var latestUpdatedAtDate: Date?
        var latestDeletedAtDate: Date?
        var latestRemoteVersion: Int64 = 0
        var archivedCount = 0
        var count = 0

        for record in records {
            count += 1
            let updateDate = record[keyPath: updatedAt]
            if let maxDate = latestUpdatedAtDate {
                if updateDate > maxDate { latestUpdatedAtDate = updateDate }
            } else {
                latestUpdatedAtDate = updateDate
            }

            if let delDate = record[keyPath: deletedAt] {
                if let maxDel = latestDeletedAtDate {
                    if delDate > maxDel { latestDeletedAtDate = delDate }
                } else {
                    latestDeletedAtDate = delDate
                }
            }

            if let isArchived, record[keyPath: isArchived] {
                archivedCount += 1
            }

            if let remoteVersion {
                latestRemoteVersion = Swift.max(latestRemoteVersion, record[keyPath: remoteVersion])
            }
        }

        return MistiaCollectionChangeSignature(
            count: count,
            latestUpdatedAt: latestUpdatedAtDate?.timeIntervalSince1970,
            latestDeletedAt: latestDeletedAtDate?.timeIntervalSince1970,
            latestRemoteVersion: latestRemoteVersion,
            archivedCount: archivedCount
        )
    }

    static func make<Records: Sequence, Record>(
        _ records: Records,
        updatedAt: KeyPath<Record, Date>,
        deletedAt: (Record) -> Date?,
        isArchived: ((Record) -> Bool)? = nil,
        remoteVersion: ((Record) -> Int64)? = nil
    ) -> MistiaCollectionChangeSignature where Records.Element == Record {
        if let col = records as? any Collection, col.isEmpty {
            return .empty
        }

        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "MistiaCollectionChangeSignature.makeClosure", signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: "MistiaCollectionChangeSignature.makeClosure", signpostID: signpostID)
        }

        var latestUpdatedAtDate: Date?
        var latestDeletedAtDate: Date?
        var latestRemoteVersion: Int64 = 0
        var archivedCount = 0
        var count = 0

        for record in records {
            count += 1
            let updateDate = record[keyPath: updatedAt]
            if let maxDate = latestUpdatedAtDate {
                if updateDate > maxDate { latestUpdatedAtDate = updateDate }
            } else {
                latestUpdatedAtDate = updateDate
            }

            if let delDate = deletedAt(record) {
                if let maxDel = latestDeletedAtDate {
                    if delDate > maxDel { latestDeletedAtDate = delDate }
                } else {
                    latestDeletedAtDate = delDate
                }
            }

            if isArchived?(record) == true {
                archivedCount += 1
            }

            if let remoteVersion {
                latestRemoteVersion = Swift.max(latestRemoteVersion, remoteVersion(record))
            }
        }

        return MistiaCollectionChangeSignature(
            count: count,
            latestUpdatedAt: latestUpdatedAtDate?.timeIntervalSince1970,
            latestDeletedAt: latestDeletedAtDate?.timeIntervalSince1970,
            latestRemoteVersion: latestRemoteVersion,
            archivedCount: archivedCount
        )
    }
}
