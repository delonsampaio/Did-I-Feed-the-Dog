import XCTest
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class FeedingEventTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    func testEventDefaultsToNow() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let before = Date()
        let event = FeedingEvent(mealType: "Morning", pet: pet)
        context.insert(event)
        let after = Date()
        XCTAssertGreaterThanOrEqual(event.timestamp, before)
        XCTAssertLessThanOrEqual(event.timestamp, after)
    }

    func testEventStoresMealType() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let event = FeedingEvent(mealType: "Custom Snack", pet: pet)
        context.insert(event)
        XCTAssertEqual(event.mealType, "Custom Snack")
    }

    func testCascadeDeleteRemovesEvents() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let event = FeedingEvent(mealType: "Morning", pet: pet)
        context.insert(event)
        try context.save()
        context.delete(pet)
        try context.save()
        let events = try context.fetch(FetchDescriptor<FeedingEvent>())
        XCTAssertTrue(events.isEmpty)
    }
}
