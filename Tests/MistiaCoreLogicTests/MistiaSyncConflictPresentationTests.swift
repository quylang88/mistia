import XCTest
@testable import MistiaCoreLogic

final class MistiaSyncConflictPresentationTests: XCTestCase {
    func testVisibleDifferencesPreferUserFacingFieldsAndHideInternalMetadata() {
        let differences: [MistiaSyncConflictDifference] = [
            difference(id: "syncVersion", title: "Version", local: "1", remote: "2"),
            difference(id: "updatedAt", title: "Updated", local: "Today", remote: "Yesterday"),
            difference(id: "title", title: "Title", local: "Coffee", remote: "Dinner"),
            difference(id: "amount", title: "Amount", local: "100", remote: "200")
        ]

        let visible = MistiaSyncConflictPresentation.visibleDifferences(from: differences)

        XCTAssertEqual(visible.map(\.id), ["title", "amount"])
    }

    func testVisibleDifferencesFallbackToMetadataWhenNoSemanticFieldsExist() {
        let differences: [MistiaSyncConflictDifference] = [
            difference(id: "updatedAt", title: "Updated", local: "Today", remote: "Yesterday"),
            difference(id: "archivedAt", title: "Archived", local: "-", remote: "Today"),
            difference(id: "deviceID", title: "Device", local: "A", remote: "B")
        ]

        let visible = MistiaSyncConflictPresentation.visibleDifferences(from: differences)

        XCTAssertEqual(visible.map(\.id), ["updatedAt", "archivedAt"])
    }

    private func difference(
        id: String,
        title: String,
        local: String,
        remote: String
    ) -> MistiaSyncConflictDifference {
        MistiaSyncConflictDifference(
            id: id,
            fieldTitle: title,
            localValue: local,
            remoteValue: remote,
            localRawValue: nil,
            remoteRawValue: nil
        )
    }
}
