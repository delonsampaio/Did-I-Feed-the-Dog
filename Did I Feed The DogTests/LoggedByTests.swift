import XCTest
@testable import Did_I_Feed_The_Dog

@MainActor
final class LoggedByTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LoggedBy.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LoggedBy.storageKey)
        super.tearDown()
    }

    func testReturnsStoredNameWhenSet() {
        UserDefaults.standard.set("Alex", forKey: LoggedBy.storageKey)
        XCTAssertEqual(LoggedBy.current, "Alex")
    }

    func testTrimsStoredName() {
        UserDefaults.standard.set("  Alex  ", forKey: LoggedBy.storageKey)
        XCTAssertEqual(LoggedBy.current, "Alex")
    }

    func testFallsBackToDeviceNameWhenEmpty() {
        // Empty AppStorage value (the default state) — must NOT fall through
        // to "Family Member" or empty string. Was a real bug pre-fix.
        UserDefaults.standard.set("", forKey: LoggedBy.storageKey)
        XCTAssertFalse(LoggedBy.current.isEmpty)
    }

    func testFallsBackToDeviceNameWhenWhitespaceOnly() {
        UserDefaults.standard.set("   ", forKey: LoggedBy.storageKey)
        XCTAssertFalse(LoggedBy.current.isEmpty)
    }
}
