import XCTest
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class PetTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(allowsSave: false)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: config)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    func testAgeStringYearsAndMonths() throws {
        let cal = Calendar.current
        let birthday = cal.date(byAdding: DateComponents(year: -3, month: -2), to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "3 years, 2 months")
    }

    func testAgeStringMonthsOnly() throws {
        let cal = Calendar.current
        let birthday = cal.date(byAdding: .month, value: -5, to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "5 months")
    }

    func testAgeStringYearsOnly() throws {
        let cal = Calendar.current
        let birthday = cal.date(byAdding: .year, value: -2, to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "2 years")
    }

    func testAgeStringPuppyForUnderOneYear() throws {
        let birthday = Date(timeIntervalSinceNow: -(3 * 24 * 3600)) // 3 days ago
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "Puppy")
    }

    func testAgeStringPuppyForElevenMonths() throws {
        let birthday = Calendar.current.date(byAdding: .month, value: -11, to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "Puppy")
    }

    func testAgeStringEmptyWhenNoBirthday() throws {
        let pet = Pet()
        XCTAssertEqual(pet.ageString, "")
    }

    func testIsFeedingOverdueWhenNeverFed() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        XCTAssertTrue(pet.isFeedingOverdue)
    }

    func testIsFeedingOverdueFalseWhenRecentlyFed() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let event = FeedingEvent(mealType: "Morning", pet: pet)
        context.insert(event)
        XCTAssertFalse(pet.isFeedingOverdue)
    }

    func testIsFeedingOverdueTrueAfter12Hours() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let oldDate = Date(timeIntervalSinceNow: -(13 * 3600))
        let event = FeedingEvent(timestamp: oldDate, mealType: "Morning", pet: pet)
        context.insert(event)
        XCTAssertTrue(pet.isFeedingOverdue)
    }

    func testFoodStockDoesNotGoBelowZero() throws {
        let pet = Pet(name: "Max", birthday: .now, foodStockCount: 0)
        context.insert(pet)
        pet.decrementStock()
        XCTAssertEqual(pet.foodStockCount, 0)
    }

    func testFoodStockDecrement() throws {
        let pet = Pet(name: "Max", birthday: .now, foodStockCount: 5)
        context.insert(pet)
        pet.decrementStock()
        XCTAssertEqual(pet.foodStockCount, 4)
    }

    func testTodaysFeedingCount() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let e1 = FeedingEvent(mealType: "Morning", pet: pet)
        let e2 = FeedingEvent(mealType: "Evening", pet: pet)
        let yesterday = Date(timeIntervalSinceNow: -(25 * 3600))
        let e3 = FeedingEvent(timestamp: yesterday, mealType: "Morning", pet: pet)
        context.insert(e1)
        context.insert(e2)
        context.insert(e3)
        XCTAssertEqual(pet.todaysFeedingCount, 2)
    }
}
