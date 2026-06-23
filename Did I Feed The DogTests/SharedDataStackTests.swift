import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedDataStackTests: XCTestCase {

    func testInMemoryStackLoadsWithoutError() throws {
        let stack = SharedDataStack(inMemory: true)
        XCTAssertNil(stack.loadError)
        XCTAssertNotNil(stack.viewContext.persistentStoreCoordinator)
    }

    func testRoundTripInsertFetch() throws {
        let stack = SharedDataStack(inMemory: true)
        let pet = SharedPet(context: stack.viewContext)
        pet.id = UUID()
        pet.name = "Rex"
        try stack.viewContext.save()

        let req = NSFetchRequest<SharedPet>(entityName: "SharedPet")
        XCTAssertEqual(try stack.viewContext.fetch(req).first?.name, "Rex")
    }

    func testBackgroundContextSharesCoordinator() throws {
        let stack = SharedDataStack(inMemory: true)
        let bg = stack.newBackgroundContext()
        XCTAssertTrue(bg.persistentStoreCoordinator === stack.viewContext.persistentStoreCoordinator)
    }
}
