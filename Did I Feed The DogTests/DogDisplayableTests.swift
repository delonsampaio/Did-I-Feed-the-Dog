import XCTest
import CoreData
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class DogDisplayableTests: XCTestCase {

    func testPetIsNotShared() throws {
        let pet = Pet(name: "Max")
        XCTAssertFalse(pet.isShared)
        XCTAssertEqual(pet.displayName, "Max")
    }

    func testPetDisplayNameFallback() throws {
        let pet = Pet(name: nil)
        XCTAssertEqual(pet.displayName, "Dog")
    }

    func testSharedPetIsShared() throws {
        let stack = SharedDataStack(inMemory: true)
        let sp = SharedPet(context: stack.viewContext)
        sp.id = UUID(); sp.name = "Rex"
        XCTAssertTrue(sp.isShared)
        XCTAssertEqual(sp.displayName, "Rex")
    }

    /// Guards against drift: same birthday must produce identical age text for both kinds.
    func testAgeStringParity() throws {
        let birthday = Calendar.current.date(byAdding: DateComponents(year: -2, month: -3), to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        let stack = SharedDataStack(inMemory: true)
        let sp = SharedPet(context: stack.viewContext)
        sp.id = UUID(); sp.birthday = birthday
        XCTAssertEqual(pet.ageString, sp.ageString)
        XCTAssertEqual(pet.ageString, "2 years, 3 months")
    }
}
