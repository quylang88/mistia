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

    static func make<Record>(
        _ records: [Record],
        updatedAt: KeyPath<Record, Date>,
        deletedAt: KeyPath<Record, Date?>,
        isArchived: KeyPath<Record, Bool>? = nil,
        remoteVersion: KeyPath<Record, Int64>? = nil
    ) -> MistiaCollectionChangeSignature {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "MistiaCollectionChangeSignature.make", signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: "MistiaCollectionChangeSignature.make", signpostID: signpostID)
        }

        var latestUpdatedAt: TimeInterval?
        var latestDeletedAt: TimeInterval?
        var latestRemoteVersion: Int64 = 0
        var archivedCount = 0

        for record in records {
            latestUpdatedAt = max(
                latestUpdatedAt,
                record[keyPath: updatedAt].timeIntervalSince1970
            )

            if let deletedAt = record[keyPath: deletedAt]?.timeIntervalSince1970 {
                latestDeletedAt = max(latestDeletedAt, deletedAt)
            }

            if let isArchived, record[keyPath: isArchived] {
                archivedCount += 1
            }

            if let remoteVersion {
                latestRemoteVersion = Swift.max(latestRemoteVersion, record[keyPath: remoteVersion])
            }
        }

        return MistiaCollectionChangeSignature(
            count: records.count,
            latestUpdatedAt: latestUpdatedAt,
            latestDeletedAt: latestDeletedAt,
            latestRemoteVersion: latestRemoteVersion,
            archivedCount: archivedCount
        )
    }

    static func make<Record>(
        _ records: [Record],
        updatedAt: KeyPath<Record, Date>,
        deletedAt: (Record) -> Date?,
        isArchived: ((Record) -> Bool)? = nil,
        remoteVersion: ((Record) -> Int64)? = nil
    ) -> MistiaCollectionChangeSignature {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "MistiaCollectionChangeSignature.makeClosure", signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: "MistiaCollectionChangeSignature.makeClosure", signpostID: signpostID)
        }

        var latestUpdatedAt: TimeInterval?
        var latestDeletedAt: TimeInterval?
        var latestRemoteVersion: Int64 = 0
        var archivedCount = 0

        for record in records {
            latestUpdatedAt = max(
                latestUpdatedAt,
                record[keyPath: updatedAt].timeIntervalSince1970
            )

            if let deletedAt = deletedAt(record)?.timeIntervalSince1970 {
                latestDeletedAt = max(latestDeletedAt, deletedAt)
            }

            if isArchived?(record) == true {
                archivedCount += 1
            }

            if let remoteVersion {
                latestRemoteVersion = Swift.max(latestRemoteVersion, remoteVersion(record))
            }
        }

        return MistiaCollectionChangeSignature(
            count: records.count,
            latestUpdatedAt: latestUpdatedAt,
            latestDeletedAt: latestDeletedAt,
            latestRemoteVersion: latestRemoteVersion,
            archivedCount: archivedCount
        )
    }

    private static func max(_ lhs: TimeInterval?, _ rhs: TimeInterval) -> TimeInterval {
        Swift.max(lhs ?? rhs, rhs)
    }
}
