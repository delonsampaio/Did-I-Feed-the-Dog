import XCTest
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class FeedingLogServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: config)
        context = container.mainContext

        // Reset UserDefaults keys the service consults so tests start clean.
        let keys = [
            AppSettings.Key.stockMode,
            AppSettings.Key.sharedFoodStock,
            AppSettings.Key.lowStockThreshold,
            AppSettings.Key.lowStockPushEnabled,
            AppSettings.Key.reminderMode,
            AppSettings.Key.allDogsReminderTimesRaw,
            AppSettings.Key.overdueThresholdHours,
            AppSettings.Key.badgeEnabled
        ]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Single feeding

    func testLogFeedingDeductsIndividualStock() throws {
        UserDefaults.standard.set(StockMode.individual.rawValue, forKey: AppSettings.Key.stockMode)

        let pet = Pet(name: "Max", foodStockCount: 5)
        context.insert(pet)

        let result = try FeedingLogService.logFeeding(
            for: pet, mealLabel: "Breakfast", deductsStock: true,
            logger: "Tester", in: context
        )

        XCTAssertEqual(pet.foodStockCount, 4)
        XCTAssertEqual(result.event.didDeductStock, true)
        XCTAssertTrue(result.event.actuallyDeductedStock)
    }

    func testLogFeedingDoesNotDeductWhenMealTypeSaysSo() throws {
        UserDefaults.standard.set(StockMode.individual.rawValue, forKey: AppSettings.Key.stockMode)

        let pet = Pet(name: "Max", foodStockCount: 5)
        context.insert(pet)

        let result = try FeedingLogService.logFeeding(
            for: pet, mealLabel: "Treat", deductsStock: false,
            logger: "Tester", in: context
        )

        XCTAssertEqual(pet.foodStockCount, 5)
        XCTAssertEqual(result.event.didDeductStock, false)
        XCTAssertFalse(result.event.actuallyDeductedStock)
    }

    func testLogFeedingDoesNotDeductWhenStockModeIsNone() throws {
        UserDefaults.standard.set("", forKey: AppSettings.Key.stockMode) // .none

        let pet = Pet(name: "Max", foodStockCount: 5)
        context.insert(pet)

        let result = try FeedingLogService.logFeeding(
            for: pet, mealLabel: "Breakfast", deductsStock: true,
            logger: "Tester", in: context
        )

        XCTAssertEqual(pet.foodStockCount, 5)
        XCTAssertEqual(result.event.didDeductStock, false,
                       "didDeductStock should be false when stock tracking is off — even if meal type would normally deduct.")
    }

    func testLogFeedingDeductsSharedPool() throws {
        UserDefaults.standard.set(StockMode.shared.rawValue, forKey: AppSettings.Key.stockMode)
        UserDefaults.standard.set(10, forKey: AppSettings.Key.sharedFoodStock)

        let pet = Pet(name: "Max")
        context.insert(pet)

        _ = try FeedingLogService.logFeeding(
            for: pet, mealLabel: "Dinner", deductsStock: true,
            logger: "Tester", in: context
        )

        XCTAssertEqual(AppSettings.sharedFoodStock, 9)
    }

    func testLogFeedingTriggersLowStockFlagAtThreshold() throws {
        UserDefaults.standard.set(StockMode.individual.rawValue, forKey: AppSettings.Key.stockMode)
        UserDefaults.standard.set(5, forKey: AppSettings.Key.lowStockThreshold)

        let pet = Pet(name: "Max", foodStockCount: 6) // -> 5 = at threshold
        context.insert(pet)

        let result = try FeedingLogService.logFeeding(
            for: pet, mealLabel: "Breakfast", deductsStock: true,
            logger: "Tester", in: context
        )

        XCTAssertTrue(result.didTriggerLowStock)
    }

    // MARK: - Batch feeding

    func testLogFeedingForAllSkipsFastingDogsByContract() throws {
        // The service itself takes whatever pet list the caller passes in;
        // intent/sheet code is responsible for filtering. Verify the service
        // logs an event for every pet it receives.
        let p1 = Pet(name: "A")
        let p2 = Pet(name: "B")
        context.insert(p1)
        context.insert(p2)

        let result = try FeedingLogService.logFeedingForAll(
            pets: [p1, p2], mealLabel: "Dinner", deductsStock: false,
            logger: "Tester", in: context
        )

        XCTAssertEqual(result.events.count, 2)
    }

    func testLogFeedingForAllSharedPoolDeductsOncePerPet() throws {
        UserDefaults.standard.set(StockMode.shared.rawValue, forKey: AppSettings.Key.stockMode)
        UserDefaults.standard.set(20, forKey: AppSettings.Key.sharedFoodStock)

        let p1 = Pet(name: "A")
        let p2 = Pet(name: "B")
        let p3 = Pet(name: "C")
        [p1, p2, p3].forEach { context.insert($0) }

        _ = try FeedingLogService.logFeedingForAll(
            pets: [p1, p2, p3], mealLabel: "Dinner", deductsStock: true,
            logger: "Tester", in: context
        )

        XCTAssertEqual(AppSettings.sharedFoodStock, 17, "Each pet should subtract one portion from the shared pool.")
    }
}
