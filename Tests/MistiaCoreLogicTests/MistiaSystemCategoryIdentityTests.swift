import XCTest
@testable import MistiaCoreLogic

final class MistiaSystemCategoryIdentityTests: XCTestCase {
    func testAndroidBootstrapCrossPlatformGoldenVectors() {
        let owner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let rent = MistiaSystemCategoryIdentity.canonicalID(for: "rent")
        let internet = MistiaSystemCategoryIdentity.canonicalID(for: "internet")
        XCTAssertEqual(rent.uuidString.lowercased(), "50cd7bc4-edb6-5bb6-9c0d-0edfa0522601")
        XCTAssertEqual(internet.uuidString.lowercased(), "95c65048-8f44-558d-9ad1-1a43cdec5483")
        XCTAssertEqual(MistiaSystemCategoryIdentity.canonicalID(for: "loan_repayment").uuidString.lowercased(), "d872b8af-d28a-5b90-8822-839dfa097b23")
        XCTAssertEqual(MistiaSystemCategoryIdentity.cloudScopedID(canonicalCategoryID: rent, ownerUserID: owner).uuidString.lowercased(), "b37f0c1b-b967-5f0a-ba59-0e795d0a4d75")
        let cloudInternet = MistiaSystemCategoryIdentity.cloudScopedID(canonicalCategoryID: internet, ownerUserID: owner)
        XCTAssertEqual(cloudInternet.uuidString.lowercased(), "d1021d10-3990-54d4-bd3a-9cb7503758b9")
        XCTAssertEqual(MistiaSystemCategoryIdentity.familyScopedID(remoteCategoryID: cloudInternet, ownerUserID: owner).uuidString.lowercased(), "7fa4dc60-3397-57ba-890a-e926a5f1927e")
    }
    func testCanonicalIDIsStableAndDistinctAcrossSystemKeys() {
        let foodID = MistiaSystemCategoryIdentity.canonicalID(for: MistiaSystemCategoryKey.food)
        let sameFoodID = MistiaSystemCategoryIdentity.canonicalID(for: MistiaSystemCategoryKey.food.rawValue)
        let travelID = MistiaSystemCategoryIdentity.canonicalID(for: MistiaSystemCategoryKey.travel)

        XCTAssertEqual(foodID, sameFoodID)
        XCTAssertNotEqual(foodID, travelID)
    }

    func testParentDescriptorUsesParentMetadata() {
        let descriptor = MistiaSystemCategoryIdentity.descriptor(
            for: MistiaSystemCategoryParentKey.expenseFood.rawValue
        )

        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.hierarchyRole, .parent)
        XCTAssertEqual(descriptor?.kind, .expense)
        XCTAssertNil(descriptor?.defaultParentSystemKey)
        XCTAssertEqual(
            descriptor?.sortOrder,
            MistiaSystemCategoryParentKey.activeDefaults.firstIndex(of: .expenseFood)
        )
        XCTAssertEqual(
            descriptor?.iconColorHex,
            MistiaIconColorPalette.presetHex(forDefault: MistiaSystemCategoryParentKey.expenseFood.iconColorHex)
        )
    }

    func testChildDescriptorUsesCanonicalParentAndArchivedRules() {
        let groceryDescriptor = MistiaSystemCategoryIdentity.descriptor(
            for: MistiaSystemCategoryKey.grocery.rawValue
        )
        let legacyFoodDescriptor = MistiaSystemCategoryIdentity.descriptor(
            for: MistiaSystemCategoryKey.food.rawValue
        )

        XCTAssertNotNil(groceryDescriptor)
        XCTAssertEqual(groceryDescriptor?.hierarchyRole, .child)
        XCTAssertEqual(
            groceryDescriptor?.defaultParentSystemKey,
            MistiaSystemCategoryParentKey.expenseFood.rawValue
        )
        XCTAssertEqual(groceryDescriptor?.startsArchived, false)

        XCTAssertNotNil(legacyFoodDescriptor)
        XCTAssertEqual(legacyFoodDescriptor?.startsArchived, true)
    }
}

