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

    func testDynamicJSONCategoryDescriptorLoading() {
        let pizzaDescriptor = MistiaSystemCategoryIdentity.descriptor(for: "test_dynamic_pizza")
        XCTAssertNotNil(pizzaDescriptor)
        XCTAssertEqual(pizzaDescriptor?.hierarchyRole, .child)
        XCTAssertEqual(pizzaDescriptor?.defaultParentSystemKey, "parent_expense_food")
        XCTAssertEqual(pizzaDescriptor?.iconSymbolName, "mistia.category.expense.food.test_dynamic_pizza")
        XCTAssertEqual(pizzaDescriptor?.fallbackIconSymbolName, "heart.fill")
        XCTAssertEqual(pizzaDescriptor?.iconColorHex, MistiaIconColorPalette.presetHex(forDefault: "#FF0000"))
        XCTAssertEqual(pizzaDescriptor?.startsArchived, false)
        XCTAssertEqual(pizzaDescriptor?.knownNames.contains("Test Dynamic Pizza"), true)
        XCTAssertEqual(pizzaDescriptor?.knownNames.contains("Pizza Thử Nghiệm"), true)
    }
}

