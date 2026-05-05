import XCTest
@testable import Did_I_Feed_The_Dog

final class MealTypeTests: XCTestCase {
    func testPresetLabels() {
        XCTAssertEqual(MealType.morning.label, "Morning")
        XCTAssertEqual(MealType.afternoon.label, "Afternoon")
        XCTAssertEqual(MealType.evening.label, "Evening")
        XCTAssertEqual(MealType.breakfast.label, "Breakfast")
        XCTAssertEqual(MealType.lunch.label, "Lunch")
        XCTAssertEqual(MealType.dinner.label, "Dinner")
        XCTAssertEqual(MealType.snack.label, "Snack")
        XCTAssertEqual(MealType.treat.label, "Treat")
    }

    func testCustomLabel() {
        XCTAssertEqual(MealType.custom("Medication").label, "Medication")
        XCTAssertEqual(MealType.custom("").label, "")
    }

    func testPresetEmojis() {
        XCTAssertEqual(MealType.morning.emoji, "🌅")
        XCTAssertEqual(MealType.afternoon.emoji, "☀️")
        XCTAssertEqual(MealType.evening.emoji, "🌙")
        XCTAssertEqual(MealType.breakfast.emoji, "🍳")
        XCTAssertEqual(MealType.lunch.emoji, "🥗")
        XCTAssertEqual(MealType.dinner.emoji, "🍽️")
        XCTAssertEqual(MealType.snack.emoji, "🐾")
        XCTAssertEqual(MealType.treat.emoji, "🦴")
        XCTAssertEqual(MealType.custom("Anything").emoji, "✏️")
    }

    func testPresetsCount() {
        XCTAssertEqual(MealType.presets.count, 8)
    }

    func testPresetOrderGroupsNamedThenTimeOfDay() {
        // Named meals first (breakfast/lunch/dinner), then time-of-day
        // (morning/afternoon/evening), then supplementary (snack/treat).
        XCTAssertEqual(MealType.presets[0..<3].map(\.label), ["Breakfast", "Lunch", "Dinner"])
        XCTAssertEqual(MealType.presets[3..<6].map(\.label), ["Morning", "Afternoon", "Evening"])
        XCTAssertEqual(MealType.presets[6..<8].map(\.label), ["Snack", "Treat"])
    }

    func testFromKnownLabelReturnsPreset() {
        XCTAssertEqual(MealType.from("Breakfast"), .breakfast)
        XCTAssertEqual(MealType.from("Treat"), .treat)
    }

    func testFromUnknownLabelReturnsCustom() {
        XCTAssertEqual(MealType.from("Medication"), .custom("Medication"))
    }

    func testFromEmptyReturnsCustom() {
        XCTAssertEqual(MealType.from(""), .custom(""))
    }

    func testEmojiForKnownLabel() {
        XCTAssertEqual(MealType.emoji(for: "Breakfast"), "🍳")
        XCTAssertEqual(MealType.emoji(for: "Treat"), "🦴")
    }

    func testEmojiForUnknownLabel() {
        XCTAssertEqual(MealType.emoji(for: "Medication"), "✏️")
    }

    func testDecrementsStockMatrix() {
        XCTAssertTrue(MealType.morning.decrementsStock)
        XCTAssertTrue(MealType.afternoon.decrementsStock)
        XCTAssertTrue(MealType.evening.decrementsStock)
        XCTAssertTrue(MealType.breakfast.decrementsStock)
        XCTAssertTrue(MealType.lunch.decrementsStock)
        XCTAssertTrue(MealType.dinner.decrementsStock)
        XCTAssertFalse(MealType.snack.decrementsStock)
        XCTAssertFalse(MealType.treat.decrementsStock)
        XCTAssertTrue(MealType.custom("Medication").decrementsStock)
    }
}
