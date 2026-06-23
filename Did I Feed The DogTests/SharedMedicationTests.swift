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
}
