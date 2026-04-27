import XCTest
import UserNotifications
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class NotificationManagerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var center: UNUserNotificationCenter!

    override func setUp() async throws {
        let config = ModelConfiguration(allowsSave: false)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: config)
        context = container.mainContext
        center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    override func tearDown() async throws {
        center.removeAllPendingNotificationRequests()
        container = nil
        context = nil
    }

    func testLowStockNotificationIdentifierIsStable() throws {
        let pet = Pet(name: "Max", birthday: .now, foodStockCount: 3)
        context.insert(pet)
        let id1 = NotificationManager.shared.lowStockIdentifier(for: pet)
        let id2 = NotificationManager.shared.lowStockIdentifier(for: pet)
        XCTAssertEqual(id1, id2)
    }

    func testBirthdayNotificationIdentifierIsStable() throws {
        let pet = Pet(name: "Bailey", birthday: .now)
        context.insert(pet)
        let id1 = NotificationManager.shared.birthdayIdentifier(for: pet)
        let id2 = NotificationManager.shared.birthdayIdentifier(for: pet)
        XCTAssertEqual(id1, id2)
    }

    func testLowStockAndBirthdayIdentifiersDiffer() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        XCTAssertNotEqual(
            NotificationManager.shared.lowStockIdentifier(for: pet),
            NotificationManager.shared.birthdayIdentifier(for: pet)
        )
    }
}
