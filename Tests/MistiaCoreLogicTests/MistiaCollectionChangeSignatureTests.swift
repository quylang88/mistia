import XCTest
@testable import MistiaCoreLogic

final class MistiaCollectionChangeSignatureTests: XCTestCase {
    private struct Record {
        let id: UUID
        let updatedAt: Date
        let deletedAt: Date?
        let isArchived: Bool
        let remoteVersion: Int64
    }

    func testSignatureChangesWhenCountChanges() {
        let baseDate = makeDate(seconds: 10)
        let first = Record(
            id: UUID(),
            updatedAt: baseDate,
            deletedAt: nil,
            isArchived: false,
            remoteVersion: 1
        )

        let oneRecord = MistiaCollectionChangeSignature.make(
            [first],
            updatedAt: \.updatedAt,
            deletedAt: \.deletedAt,
            isArchived: \.isArchived,
            remoteVersion: \.remoteVersion
        )
        let twoRecords = MistiaCollectionChangeSignature.make(
            [
                first,
                Record(
                    id: UUID(),
                    updatedAt: baseDate,
                    deletedAt: nil,
                    isArchived: false,
                    remoteVersion: 1
                )
            ],
            updatedAt: \.updatedAt,
            deletedAt: \.deletedAt,
            isArchived: \.isArchived,
            remoteVersion: \.remoteVersion
        )

        XCTAssertNotEqual(oneRecord, twoRecords)
    }

    func testSignatureTracksLatestUpdateDeleteArchiveAndRemoteVersion() {
        let active = Record(
            id: UUID(),
            updatedAt: makeDate(seconds: 10),
            deletedAt: nil,
            isArchived: false,
            remoteVersion: 1
        )
        let updated = Record(
            id: active.id,
            updatedAt: makeDate(seconds: 20),
            deletedAt: nil,
            isArchived: false,
            remoteVersion: 1
        )
        let deleted = Record(
            id: active.id,
            updatedAt: active.updatedAt,
            deletedAt: makeDate(seconds: 30),
            isArchived: false,
            remoteVersion: 1
        )
        let archived = Record(
            id: active.id,
            updatedAt: active.updatedAt,
            deletedAt: nil,
            isArchived: true,
            remoteVersion: 1
        )
        let remoteChanged = Record(
            id: active.id,
            updatedAt: active.updatedAt,
            deletedAt: nil,
            isArchived: false,
            remoteVersion: 2
        )

        let activeSignature = signature([active])

        XCTAssertNotEqual(activeSignature, signature([updated]))
        XCTAssertNotEqual(activeSignature, signature([deleted]))
        XCTAssertNotEqual(activeSignature, signature([archived]))
        XCTAssertNotEqual(activeSignature, signature([remoteChanged]))
    }

    func testSignatureTracksLocalOnlyRowsWithoutRemoteVersion() {
        let localDraft = Record(
            id: UUID(),
            updatedAt: makeDate(seconds: 10),
            deletedAt: nil,
            isArchived: false,
            remoteVersion: 0
        )
        let localEdited = Record(
            id: localDraft.id,
            updatedAt: makeDate(seconds: 11),
            deletedAt: nil,
            isArchived: false,
            remoteVersion: 0
        )

        XCTAssertNotEqual(signature([localDraft]), signature([localEdited]))
    }

    private func signature(_ records: [Record]) -> MistiaCollectionChangeSignature {
        MistiaCollectionChangeSignature.make(
            records,
            updatedAt: \.updatedAt,
            deletedAt: \.deletedAt,
            isArchived: \.isArchived,
            remoteVersion: \.remoteVersion
        )
    }

    private func makeDate(seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
