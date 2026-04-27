import XCTest
@testable import Did_I_Feed_The_Dog

final class MealTypeTests: XCTestCase {
    func testPresetLabels() {
        XCTAssertEqual(MealType.morning.label, "Morning")
        XCTAssertEqual(MealType.evening.label, "Evening")
        XCTAssertEqual(MealType.breakfast.label, "Breakfast")
        XCTAssertEqual(MealType.lunch.label, "Lunch")
        XCTAssertEqual(MealType.dinner.label, "Dinner")
        XCTAssertEqual(MealType.snack.label, "Snack")
    }

    func testCustomLabel() {
        XCTAssertEqual(MealType.custom("Medication").label, "Medication")
        XCTAssertEqual(MealType.custom("").label, "")
    }

    func testPresetEmojis() {
        XCTAssertEqual(MealType.morning.emoji, "🌅")
        XCTAssertEqual(MealType.evening.emoji, "🌙")
        XCTAssertEqual(MealType.breakfast.emoji, "🍳")
        XCTAssertEqual(MealType.lunch.emoji, "🥗")
        XCTAssertEqual(MealType.dinner.emoji, "🍽️")
        XCTAssertEqual(MealType.snack.emoji, "🦴")
        XCTAssertEqual(MealType.custom("Anything").emoji, "✏️")
    }

    func testPresetsCount() {
        XCTAssertEqual(MealType.presets.count, 6)
    }
}
