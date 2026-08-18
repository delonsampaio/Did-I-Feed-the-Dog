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

    /// Reproduces the exact merge shape SharedSyncEngine.fetchZone uses: a background
    /// context inserts a new SharedFeedingEvent wired to a SharedPet that's ALREADY
    /// resident (and already fired its feedingEvents fault) on viewContext, then saves.
    /// automaticallyMergesChangesFromParent is expected to update the resident SharedPet's
    /// relationship snapshot on its own; this guards that refresh() doesn't depend on it —
    /// callers must see the new event through the SAME SharedPet instance the dashboard
    /// already holds, without needing to refetch a fresh object.
    func testRefreshSeesRelationshipChangesMergedFromBackgroundContext() throws {
        let stack = SharedDataStack(inMemory: true)
        let store = SharedDogStore(stack: stack)

        let petId = UUID()
        let pet = SharedPet(context: stack.viewContext)
        pet.id = petId; pet.name = "Bacon"
        try stack.viewContext.save()

        store.refresh()
        let residentPet = try XCTUnwrap(store.sharedPets.first)
        // Fire the relationship fault before the merge, mirroring the dashboard having
        // already read todaysFeedingCount/lastFeedingDate once before the remote change lands.
        XCTAssertEqual(residentPet.todaysFeedingCount, 0)

        let bg = stack.newBackgroundContext()
        try bg.performAndWait {
            let req = NSFetchRequest<SharedPet>(entityName: "SharedPet")
            req.predicate = NSPredicate(format: "id == %@", petId as CVarArg)
            let petInBG = try bg.fetch(req).first!
            let event = SharedFeedingEvent(context: bg)
            event.timestamp = .now
            event.pet = petInBG
            try bg.save()
        }

        store.refresh()
        let refreshedPet = try XCTUnwrap(store.sharedPets.first)
        XCTAssertEqual(refreshedPet.todaysFeedingCount, 1,
                       "SharedDogStore must see feeding events merged in from a background context")
    }
}
