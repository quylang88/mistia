import XCTest
@testable import MistiaCoreLogic

final class MistiaSystemCategoryRequestSupportTests: XCTestCase {
    func testExistingArchivedDeletedOrCustomizedMemberSystemCategoriesAreNotRequestable() {
        let ownerUserID = UUID()
        let otherUserID = UUID()
        let archivedCategory = makeSystemCategory(key: .dineOut, isArchived: true)
        let deletedCategory = makeSystemCategory(key: .grocery, deletedAt: Date(timeIntervalSince1970: 1_770_000_000))
        let customizedCategory = makeSystemCategory(key: .cafeTea, name: "Cafe rieng")
        let otherOwnerCategory = makeSystemCategory(key: .snacks)

        let missingSystemKeys = missingSystemKeys(
            categories: [
                archivedCategory,
                deletedCategory,
                customizedCategory,
                otherOwnerCategory
            ],
            categoryOwnerMap: [
                archivedCategory.id: ownerUserID,
                deletedCategory.id: ownerUserID,
                customizedCategory.id: ownerUserID,
                otherOwnerCategory.id: otherUserID
            ],
            ownerUserID: ownerUserID
        )

        XCTAssertFalse(missingSystemKeys.contains(MistiaSystemCategoryKey.dineOut.rawValue))
        XCTAssertFalse(missingSystemKeys.contains(MistiaSystemCategoryKey.grocery.rawValue))
        XCTAssertFalse(missingSystemKeys.contains(MistiaSystemCategoryKey.cafeTea.rawValue))
        XCTAssertTrue(missingSystemKeys.contains(MistiaSystemCategoryKey.snacks.rawValue))
    }

    private func missingSystemKeys(
        categories: [TransactionCategory],
        categoryOwnerMap: [UUID: UUID],
        ownerUserID: UUID
    ) -> Set<String> {
        Set(
            MistiaSystemCategoryRequestSupport.missingSections(
                ownerUserID: ownerUserID,
                kind: .expense,
                categories: categories,
                categoryOwnerMap: categoryOwnerMap
            )
            .flatMap(\.children)
            .compactMap(\.systemKey)
        )
    }

    private func makeSystemCategory(
        key: MistiaSystemCategoryKey,
        name: String? = nil,
        isArchived: Bool? = nil,
        deletedAt: Date? = nil
    ) -> TransactionCategory {
        let parentKey = MistiaCategoryHierarchy.defaultParentKey(for: key)
        let parent = TransactionCategory(
            id: MistiaSystemCategoryIdentity.canonicalID(for: parentKey),
            name: parentKey.title,
            kind: parentKey.kind,
            iconSymbolName: parentKey.iconSymbolName,
            iconColorHex: parentKey.iconColorHex,
            hierarchyRole: .parent,
            systemKey: parentKey.rawValue,
            isSystem: true,
            sortOrder: MistiaSystemCategoryParentKey.activeDefaults.firstIndex(of: parentKey) ?? 0
        )

        return TransactionCategory(
            id: MistiaSystemCategoryIdentity.canonicalID(for: key),
            name: name ?? key.title,
            kind: key.kind,
            iconSymbolName: key.iconSymbolName,
            iconColorHex: key.iconColorHex,
            parentCategory: parent,
            hierarchyRole: .child,
            systemKey: key.rawValue,
            isSystem: true,
            sortOrder: MistiaSystemCategoryKey.activeDefaults.firstIndex(of: key) ?? 0,
            isArchived: isArchived ?? !key.isActiveDefault,
            deletedAt: deletedAt
        )
    }
}
