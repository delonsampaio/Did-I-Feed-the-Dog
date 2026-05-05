import XCTest
@testable import Did_I_Feed_The_Dog

final class AppSettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let keys = [
            AppSettings.Key.stockMode,
            AppSettings.Key.sharedFoodStock,
            AppSettings.Key.lowStockThreshold,
            AppSettings.Key.lowStockPushEnabled,
            AppSettings.Key.overdueThresholdHours,
            AppSettings.Key.reminderMode,
            AppSettings.Key.allDogsReminderTimesRaw,
            AppSettings.Key.badgeEnabled,
            AppSettings.Key.birthdayPushEnabled
        ]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    func testStockModeDefaultsToNone() {
        XCTAssertEqual(AppSettings.stockMode, .none)
    }

    func testStockModeReadsRawValue() {
        UserDefaults.standard.set("individual", forKey: AppSettings.Key.stockMode)
        XCTAssertEqual(AppSettings.stockMode, .individual)
    }

    func testLowStockThresholdFallsBackToDefault() {
        XCTAssertEqual(AppSettings.lowStockThreshold, AppConstants.defaultLowStockThreshold)
    }

    func testLowStockThresholdReadsStoredValue() {
        UserDefaults.standard.set(8, forKey: AppSettings.Key.lowStockThreshold)
        XCTAssertEqual(AppSettings.lowStockThreshold, 8)
    }

    func testOverdueThresholdHoursDefaultsTo12() {
        XCTAssertEqual(AppSettings.overdueThresholdHours, AppConstants.defaultOverdueThresholdHours)
    }

    func testOverdueThresholdHoursClampsToOne() {
        UserDefaults.standard.set(0, forKey: AppSettings.Key.overdueThresholdHours)
        XCTAssertEqual(AppSettings.overdueThresholdHours, AppConstants.defaultOverdueThresholdHours,
                       "0 should resolve to the default, not zero (no useful overdue at 0 hours).")
    }

    func testLowStockPushDefaultsTrue() {
        XCTAssertTrue(AppSettings.lowStockPushEnabled)
    }

    func testLowStockPushReadsExplicitFalse() {
        UserDefaults.standard.set(false, forKey: AppSettings.Key.lowStockPushEnabled)
        XCTAssertFalse(AppSettings.lowStockPushEnabled)
    }

    func testReminderModeDefaultsToNone() {
        XCTAssertEqual(AppSettings.reminderMode, .none)
    }

    func testAllDogsReminderTimesParsesRaw() {
        UserDefaults.standard.set("420,1080", forKey: AppSettings.Key.allDogsReminderTimesRaw)
        XCTAssertEqual(AppSettings.allDogsReminderTimes, [420, 1080])
    }

    func testAllDogsReminderTimesEmptyWhenUnset() {
        XCTAssertEqual(AppSettings.allDogsReminderTimes, [])
    }

    func testSharedFoodStockClampsAtZero() {
        AppSettings.sharedFoodStock = -5
        XCTAssertEqual(AppSettings.sharedFoodStock, 0)
    }
}
