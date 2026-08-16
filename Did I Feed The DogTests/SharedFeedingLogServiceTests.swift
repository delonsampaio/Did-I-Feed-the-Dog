import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedFeedingLogServiceTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    func testLogFeedingCreatesStampedEvent() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.id = UUID()
        pet.name = "Fido"
        try context.save()

        let event = try SharedFeedingLogService.logFeeding(
            for: pet, mealLabel: "Breakfast", deductsStock: true,
            timestamp: Date(timeIntervalSince1970: 1000), notes: "yum",
            logger: "Alex", in: context
        )

        XCTAssertEqual(event.mealType, "Breakfast")
        XCTAssertEqual(event.notes, "yum")
        XCTAssertEqual(event.loggedBy, "Alex")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 1000))
        XCTAssertNotNil(event.ckRecordName)
        XCTAssertEqual(event.pet, pet)
        XCTAssertEqual(event.didDeductStock, true)
        XCTAssertEqual(event.portionsDeducted?.intValue, AppSettings.portionSize(for: .breakfast))
    }

    func testCustomMealWithToggleOffDeductsNothing() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.id = UUID()
        try context.save()

        let event = try SharedFeedingLogService.logFeeding(
            for: pet, mealLabel: "Peanut Butter Kong", deductsStock: false,
            timestamp: .now, logger: "Sam", in: context
        )

        XCTAssertEqual(event.portionsDeducted?.intValue, 0)
        XCTAssertEqual(event.didDeductStock, false)
    }

    func testCustomMealWithToggleOnDeductsOnePortion() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.id = UUID()
        try context.save()

        let event = try SharedFeedingLogService.logFeeding(
            for: pet, mealLabel: "Peanut Butter Kong", deductsStock: true,
            timestamp: .now, logger: "Sam", in: context
        )

        XCTAssertEqual(event.portionsDeducted?.intValue, 1)
        XCTAssertEqual(event.didDeductStock, true)
    }
}
