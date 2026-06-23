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

    func testAllEntitiesHaveSyncBookkeepingFields() throws {
        let model = SharedDataModel.makeModel()
        let entityNames = ["SharedPet", "SharedFeedingEvent", "SharedMedication", "SharedMedicationLog"]
        let syncAttrs = ["ckRecordName", "ckSystemFields", "ckZoneName", "ckDatabaseScope"]
        for entityName in entityNames {
            let entity = try XCTUnwrap(model.entitiesByName[entityName], "Entity \(entityName) not found")
            for attr in syncAttrs {
                XCTAssertNotNil(
                    entity.attributesByName[attr],
                    "Entity \(entityName) is missing sync attribute '\(attr)'"
                )
            }
        }
    }

    func testDeletingPetCascadesToEventsAndMedications() throws {
        let ctx = try makeInMemoryContext()

        let pet = SharedPet(context: ctx)
        pet.id = UUID()
        pet.name = "Rex"

        let event = SharedFeedingEvent(context: ctx)
        event.timestamp = .now
        event.notes = ""
        event.pet = pet

        let med = SharedMedication(context: ctx)
        med.id = UUID()
        med.name = "Heartgard"
        med.pet = pet

        try ctx.save()

        ctx.delete(pet)
        try ctx.save()

        let eventCount = try ctx.count(for: NSFetchRequest<SharedFeedingEvent>(entityName: "SharedFeedingEvent"))
        let medCount = try ctx.count(for: NSFetchRequest<SharedMedication>(entityName: "SharedMedication"))
        XCTAssertEqual(eventCount, 0, "Cascading delete of pet should remove all feeding events")
        XCTAssertEqual(medCount, 0, "Cascading delete of pet should remove all medications")
    }

    func testDeletingMedicationNullifiesLogs() throws {
        let ctx = try makeInMemoryContext()

        let med = SharedMedication(context: ctx)
        med.id = UUID()
        med.name = "Bravecto"

        let log = SharedMedicationLog(context: ctx)
        log.id = UUID()
        log.timestamp = .now
        log.loggedBy = "owner"
        log.medicationName = "Bravecto"
        log.medication = med

        try ctx.save()

        ctx.delete(med)
        try ctx.save()

        let logs = try ctx.fetch(NSFetchRequest<SharedMedicationLog>(entityName: "SharedMedicationLog"))
        XCTAssertEqual(logs.count, 1, "Nullify delete rule should keep the log object")
        XCTAssertNil(logs.first?.medication, "Log's medication relationship should be nil after nullify")
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
