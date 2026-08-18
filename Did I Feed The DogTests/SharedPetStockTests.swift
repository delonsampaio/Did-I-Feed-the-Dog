import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedPetStockTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    private func makeEvent(in context: NSManagedObjectContext, pet: SharedPet, timestamp: Date, portions: Int) {
        let event = SharedFeedingEvent(context: context)
        event.timestamp = timestamp
        event.portionsDeducted = NSNumber(value: portions)
        event.pet = pet
    }

    func testNoEventsReturnsBaselineUnchanged() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(pet.effectiveFoodStockCount, 10)
    }

    func testEventsAfterBaselineAreDeducted() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 3)
        XCTAssertEqual(pet.effectiveFoodStockCount, 7)
    }

    func testEventsBeforeBaselineAreExcluded() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 5000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 3)
        XCTAssertEqual(pet.effectiveFoodStockCount, 10)
    }

    func testMixedEventsOnlyCountsAfterBaseline() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 3000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 5) // before, excluded
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 4000), portions: 2) // after, counted
        XCTAssertEqual(pet.effectiveFoodStockCount, 8)
    }

    func testNilBaselineCountsAllEvents() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = nil
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 1), portions: 4)
        XCTAssertEqual(pet.effectiveFoodStockCount, 6)
    }

    func testNeverGoesNegative() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 2
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 5)
        XCTAssertEqual(pet.effectiveFoodStockCount, 0)
    }

    func testDeletingEventRestoresEffectiveStockWithNoExplicitCall() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        let event = SharedFeedingEvent(context: context)
        event.timestamp = Date(timeIntervalSince1970: 2000)
        event.portionsDeducted = NSNumber(value: 3)
        event.pet = pet
        XCTAssertEqual(pet.effectiveFoodStockCount, 7)

        context.delete(event)
        context.processPendingChanges() // Core Data nullifies the inverse `pet.feedingEvents` relationship
                                         // during change processing, not synchronously on delete(); this
                                         // just flushes that bookkeeping so the assertion below observes
                                         // it immediately instead of waiting for the next run-loop turn.
                                         // It is NOT a domain-level "restore stock" call — no such call exists.

        XCTAssertEqual(pet.effectiveFoodStockCount, 10, "deleting the event alone must restore the count — no explicit restore step exists for shared dogs")
    }
}
