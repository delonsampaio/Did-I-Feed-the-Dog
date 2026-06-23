import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedDogStoreTests: XCTestCase {

    func testRefreshReturnsInsertedDogsSortedByName() throws {
        let stack = SharedDataStack(inMemory: true)
        let store = SharedDogStore(stack: stack)

        for name in ["Zoe", "Apple"] {
            let p = SharedPet(context: stack.viewContext)
            p.id = UUID(); p.name = name
        }
        try stack.viewContext.save()

        store.refresh()
        XCTAssertEqual(store.sharedPets.map(\.name), ["Apple", "Zoe"])
    }

    func testEmptyStoreRefreshesToEmpty() throws {
        let stack = SharedDataStack(inMemory: true)
        let store = SharedDogStore(stack: stack)
        store.refresh()
        XCTAssertTrue(store.sharedPets.isEmpty)
    }
}
