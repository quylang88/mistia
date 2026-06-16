import XCTest
@testable import MistiaCoreLogic

final class MistiaSystemCategoryIdentityTests: XCTestCase {
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

