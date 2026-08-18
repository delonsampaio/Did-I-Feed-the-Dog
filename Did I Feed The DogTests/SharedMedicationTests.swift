import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedMedicationTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    func testReminderMinutesRoundTrip() throws {
        let m = SharedMedication(context: try ctx())
        m.reminderMinutes = [480, 1200]
        XCTAssertEqual(m.reminderMinutesRaw, "480,1200")
        XCTAssertEqual(m.reminderMinutes, [480, 1200])
    }

    func testReminderMinutesEmpty() throws {
        let m = SharedMedication(context: try ctx())
        m.reminderMinutes = []
        XCTAssertEqual(m.reminderMinutesRaw, "")
        XCTAssertEqual(m.reminderMinutes, [])
    }

    func testIsDueWhenNeverGiven() throws {
        let m = SharedMedication(context: try ctx())
        m.frequencyHours = 24
        XCTAssertTrue(m.isDue)
    }

    func testIsDueFalseWhenRecentlyGiven() throws {
        let m = SharedMedication(context: try ctx())
        m.frequencyHours = 24
        m.lastGivenDate = .now
        XCTAssertFalse(m.isDue)
    }

    func testIsDueTrueAfterFrequencyElapsed() throws {
        let m = SharedMedication(context: try ctx())
        m.frequencyHours = 24
        m.lastGivenDate = Date(timeIntervalSinceNow: -(25 * 3600))
        XCTAssertTrue(m.isDue)
    }

    /// Guards against drift: SharedMedication must go due under the same rule as Medication,
    /// since both now call the shared medicationIsDue function.
    func testIsDueParityWithMedication() throws {
        let med = Medication(name: "Aspirin", frequencyHours: 24)
        med.lastGivenDate = Date(timeIntervalSinceNow: -(25 * 3600))
        let shared = SharedMedication(context: try ctx())
        shared.frequencyHours = 24
        shared.lastGivenDate = med.lastGivenDate
        XCTAssertEqual(med.isDue, shared.isDue)
        XCTAssertTrue(shared.isDue)
    }
}
