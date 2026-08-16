import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedPetDisplayableTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    private func makeEvent(in context: NSManagedObjectContext, pet: SharedPet, timestamp: Date) {
        let event = SharedFeedingEvent(context: context)
        event.timestamp = timestamp
        event.pet = pet
    }

    func testEmptyEventsReturnsNilLastFeedingDateAndZeroToday() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        XCTAssertNil(pet.lastFeedingDate)
        XCTAssertEqual(pet.todaysFeedingCount, 0)
    }

    func testLastFeedingDateIsMaxTimestamp() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 1000))
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 3000))
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(pet.lastFeedingDate, Date(timeIntervalSince1970: 3000))
    }

    func testTodaysFeedingCountOnlyCountsToday() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let yesterday = startOfToday.addingTimeInterval(-3600)
        let laterToday = startOfToday.addingTimeInterval(3600)
        makeEvent(in: context, pet: pet, timestamp: yesterday)
        makeEvent(in: context, pet: pet, timestamp: laterToday)
        makeEvent(in: context, pet: pet, timestamp: startOfToday)
        XCTAssertEqual(pet.todaysFeedingCount, 2)
    }
}
