import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedDataModelTests: XCTestCase {

    /// Builds an in-memory Core Data stack from the programmatic model.
    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let container = NSPersistentContainer(name: "SharedTest", managedObjectModel: model)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container.viewContext
    }

    func testModelDefinesAllFourEntities() throws {
        let model = SharedDataModel.makeModel()
        let names = Set(model.entities.compactMap { $0.name })
        XCTAssertEqual(names, ["SharedPet", "SharedFeedingEvent", "SharedMedication", "SharedMedicationLog"])
    }

    func testPetHasSyncBookkeepingFields() throws {
        let model = SharedDataModel.makeModel()
        let pet = try XCTUnwrap(model.entitiesByName["SharedPet"])
        XCTAssertNotNil(pet.attributesByName["ckRecordName"])
        XCTAssertNotNil(pet.attributesByName["ckSystemFields"])
        XCTAssertNotNil(pet.attributesByName["ckZoneName"])
        XCTAssertNotNil(pet.attributesByName["ckDatabaseScope"])
    }

    func testInsertAndFetchPetWithChild() throws {
        let ctx = try makeInMemoryContext()
        let pet = SharedPet(context: ctx)
        pet.id = UUID()
        pet.name = "Buster"
        let event = SharedFeedingEvent(context: ctx)
        event.timestamp = .now
        event.notes = ""
        event.pet = pet
        try ctx.save()

        let fetched = try ctx.fetch(NSFetchRequest<SharedPet>(entityName: "SharedPet"))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Buster")
        XCTAssertEqual((fetched.first?.feedingEvents as? Set<SharedFeedingEvent>)?.count, 1)
    }
}
