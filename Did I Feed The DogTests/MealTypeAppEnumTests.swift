import XCTest
@testable import Did_I_Feed_The_Dog

final class MealTypeAppEnumTests: XCTestCase {

    private func date(at hour: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    func testDefaultBeforeElevenIsBreakfast() {
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 0)), .breakfast)
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 7)), .breakfast)
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 10)), .breakfast)
    }

    func testDefaultMidDayIsLunch() {
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 11)), .lunch)
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 13)), .lunch)
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 15)), .lunch)
    }

    func testDefaultEveningIsDinner() {
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 16)), .dinner)
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 19)), .dinner)
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 22)), .dinner)
    }

    func testDefaultLateNightIsSnack() {
        XCTAssertEqual(MealTypeAppEnum.defaultForCurrentTime(date(at: 23)), .snack)
    }

    func testLabelMatchesDisplay() {
        XCTAssertEqual(MealTypeAppEnum.breakfast.label, "Breakfast")
        XCTAssertEqual(MealTypeAppEnum.treat.label, "Treat")
    }

    func testDeductsStock() {
        XCTAssertTrue(MealTypeAppEnum.breakfast.deductsStock)
        XCTAssertFalse(MealTypeAppEnum.snack.deductsStock)
        XCTAssertFalse(MealTypeAppEnum.treat.deductsStock)
    }
}
