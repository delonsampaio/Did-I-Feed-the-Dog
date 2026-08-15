import XCTest
import SwiftData
import CoreData
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharePreparationControllerTests: XCTestCase {

    private func swiftDataContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Pet.self, FeedingEvent.self, Medication.self, MedicationLog.self,
                                           configurations: config)
        return ModelContext(container)
    }

    private func sharedContext() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let container = NSPersistentContainer(name: "T", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadErr: Error?
        container.loadPersistentStores { _, e in loadErr = e }
        if let loadErr { throw loadErr }
        return container.viewContext
    }

    private func readOnlySharedContext() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let container = NSPersistentContainer(name: "T", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        container.persistentStoreDescriptions = [description]
        var loadErr: Error?
        container.loadPersistentStores { _, e in loadErr = e }
        if let loadErr { throw loadErr }
        return container.viewContext
    }

    @discardableResult
    private func makeFullPet(in context: ModelContext) -> Pet {
        let pet = Pet(name: "Max", birthday: Date(timeIntervalSince1970: 0), foodStockCount: 12)
        pet.feedingScheduleTimesRaw = "480,1200"
        pet.isFasting = true
        pet.notificationsMuted = true
        pet.lastFeedingDate = Date(timeIntervalSince1970: 1000)
        pet.todaysFeedingCount = 2
        context.insert(pet)

        let event = FeedingEvent(timestamp: Date(timeIntervalSince1970: 2000), mealType: "Breakfast",
                                 notes: "half portion", loggedBy: "Alex", pet: pet, didDeductStock: true)
        event.portionsDeducted = 1
        context.insert(event)

        let medication = Medication(name: "Heartgard", dose: "1 tab", frequencyHours: 720, notificationsEnabled: true)
        medication.reminderMinutes = [540, 1080]
        medication.lastGivenDate = Date(timeIntervalSince1970: 3000)
        medication.pet = pet
        context.insert(medication)

        let log = MedicationLog(timestamp: Date(timeIntervalSince1970: 4000), notes: "given with food",
                                loggedBy: "Alex", medication: medication)
        context.insert(log)

        try? context.save()
        return pet
    }

    func testMigrateToSharedClonesFullGraph() throws {
        let swiftData = try swiftDataContext()
        let shared = try sharedContext()
        let pet = makeFullPet(in: swiftData)
        let originalId = pet.id

        let sharedPet = try SharePreparationController.migrateToShared(pet: pet, sharedContext: shared)

        XCTAssertEqual(sharedPet.id, originalId)
        XCTAssertEqual(sharedPet.name, "Max")
        XCTAssertEqual(sharedPet.birthday, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(sharedPet.foodStockCount, 12)
        XCTAssertEqual(sharedPet.feedingScheduleTimesRaw, "480,1200")
        XCTAssertTrue(sharedPet.isFasting)
        XCTAssertTrue(sharedPet.notificationsMuted)
        XCTAssertEqual(sharedPet.lastFeedingDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(sharedPet.todaysFeedingCountRaw, 2)
        XCTAssertNotNil(sharedPet.ckRecordName)

        let events = (sharedPet.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        XCTAssertEqual(events.count, 1)
        let sharedEvent = try XCTUnwrap(events.first)
        XCTAssertEqual(sharedEvent.timestamp, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(sharedEvent.mealType, "Breakfast")
        XCTAssertEqual(sharedEvent.notes, "half portion")
        XCTAssertEqual(sharedEvent.loggedBy, "Alex")
        XCTAssertEqual(sharedEvent.didDeductStock?.boolValue, true)
        XCTAssertEqual(sharedEvent.portionsDeducted?.intValue, 1)
        XCTAssertNotNil(sharedEvent.ckRecordName)
        XCTAssertEqual(sharedEvent.pet, sharedPet)

        let meds = (sharedPet.medications as? Set<SharedMedication>) ?? []
        XCTAssertEqual(meds.count, 1)
        let sharedMed = try XCTUnwrap(meds.first)
        XCTAssertEqual(sharedMed.name, "Heartgard")
        XCTAssertEqual(sharedMed.dose, "1 tab")
        XCTAssertEqual(sharedMed.frequencyHours, 720)
        XCTAssertTrue(sharedMed.notificationsEnabled)
        XCTAssertEqual(sharedMed.reminderMinutes, [540, 1080])
        XCTAssertEqual(sharedMed.lastGivenDate, Date(timeIntervalSince1970: 3000))
        XCTAssertNotNil(sharedMed.ckRecordName)

        let logs = (sharedMed.logs as? Set<SharedMedicationLog>) ?? []
        XCTAssertEqual(logs.count, 1)
        let sharedLog = try XCTUnwrap(logs.first)
        XCTAssertEqual(sharedLog.timestamp, Date(timeIntervalSince1970: 4000))
        XCTAssertEqual(sharedLog.notes, "given with food")
        XCTAssertEqual(sharedLog.loggedBy, "Alex")
        XCTAssertNotNil(sharedLog.ckRecordName)
        XCTAssertEqual(sharedLog.medication, sharedMed)
    }

    func testMigrateToSharedRollsBackOnSaveFailure() throws {
        let swiftData = try swiftDataContext()
        let readOnly = try readOnlySharedContext()
        let pet = makeFullPet(in: swiftData)

        XCTAssertThrowsError(try SharePreparationController.migrateToShared(pet: pet, sharedContext: readOnly))

        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "SharedPet")
        XCTAssertEqual(try readOnly.count(for: fetch), 0)
    }

    func testMigrateToOwnedClonesFullGraphBack() throws {
        let shared = try sharedContext()
        let swiftData = try swiftDataContext()

        let sharedPet = SharedPet(context: shared)
        let originalId = UUID()
        sharedPet.id = originalId
        sharedPet.name = "Bella"
        sharedPet.birthday = Date(timeIntervalSince1970: 500)
        sharedPet.foodStockCount = 7
        sharedPet.feedingScheduleTimesRaw = "600"
        sharedPet.isFasting = false
        sharedPet.notificationsMuted = false
        sharedPet.lastFeedingDate = Date(timeIntervalSince1970: 1500)
        sharedPet.todaysFeedingCountRaw = 3

        let sharedEvent = SharedFeedingEvent(context: shared)
        sharedEvent.timestamp = Date(timeIntervalSince1970: 2500)
        sharedEvent.mealType = "Dinner"
        sharedEvent.notes = "extra treat"
        sharedEvent.loggedBy = "Sam"
        sharedEvent.didDeductStock = NSNumber(value: true)
        sharedEvent.portionsDeducted = NSNumber(value: 1)
        sharedEvent.pet = sharedPet

        let sharedMed = SharedMedication(context: shared)
        sharedMed.id = UUID()
        sharedMed.name = "Apoquel"
        sharedMed.dose = "half tab"
        sharedMed.frequencyHours = 24
        sharedMed.notificationsEnabled = false
        sharedMed.reminderMinutes = [420]
        sharedMed.lastGivenDate = Date(timeIntervalSince1970: 3500)
        sharedMed.pet = sharedPet

        let sharedLog = SharedMedicationLog(context: shared)
        sharedLog.id = UUID()
        sharedLog.timestamp = Date(timeIntervalSince1970: 4500)
        sharedLog.notes = "on time"
        sharedLog.loggedBy = "Sam"
        sharedLog.medicationName = "Apoquel"
        sharedLog.medication = sharedMed

        try shared.save()

        let pet = try SharePreparationController.migrateToOwned(sharedPet: sharedPet, modelContext: swiftData)

        XCTAssertEqual(pet.id, originalId)
        XCTAssertEqual(pet.name, "Bella")
        XCTAssertEqual(pet.birthday, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(pet.foodStockCount, 7)
        XCTAssertEqual(pet.feedingScheduleTimesRaw, "600")
        XCTAssertFalse(pet.isFasting)
        XCTAssertFalse(pet.notificationsMuted)
        XCTAssertEqual(pet.lastFeedingDate, Date(timeIntervalSince1970: 1500))
        XCTAssertEqual(pet.todaysFeedingCount, 3)

        let events = pet.feedingEvents ?? []
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 2500))
        XCTAssertEqual(event.mealType, "Dinner")
        XCTAssertEqual(event.notes, "extra treat")
        XCTAssertEqual(event.loggedBy, "Sam")
        XCTAssertEqual(event.didDeductStock, true)
        XCTAssertEqual(event.portionsDeducted, 1)

        let meds = pet.medications ?? []
        XCTAssertEqual(meds.count, 1)
        let medication = try XCTUnwrap(meds.first)
        XCTAssertEqual(medication.name, "Apoquel")
        XCTAssertEqual(medication.dose, "half tab")
        XCTAssertEqual(medication.frequencyHours, 24)
        XCTAssertFalse(medication.notificationsEnabled)
        XCTAssertEqual(medication.reminderMinutes, [420])
        XCTAssertEqual(medication.lastGivenDate, Date(timeIntervalSince1970: 3500))

        let logs = medication.logs ?? []
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.notes, "on time")
        XCTAssertEqual(log.loggedBy, "Sam")
        XCTAssertEqual(log.medicationName, "Apoquel")
    }
}
