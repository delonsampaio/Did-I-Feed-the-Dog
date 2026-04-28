import XCTest
@testable import Did_I_Feed_The_Dog

final class DeepLinkParserTests: XCTestCase {
    func testValidURLReturnsPetId() {
        let id = UUID()
        let url = URL(string: "didfeedthedog://log?petId=\(id.uuidString)")!
        XCTAssertEqual(parseDeepLink(url), id)
    }

    func testWrongSchemeReturnsNil() {
        let url = URL(string: "https://example.com/log?petId=\(UUID().uuidString)")!
        XCTAssertNil(parseDeepLink(url))
    }

    func testWrongHostReturnsNil() {
        let url = URL(string: "didfeedthedog://open?petId=\(UUID().uuidString)")!
        XCTAssertNil(parseDeepLink(url))
    }

    func testMissingPetIdReturnsNil() {
        let url = URL(string: "didfeedthedog://log")!
        XCTAssertNil(parseDeepLink(url))
    }

    func testInvalidUUIDReturnsNil() {
        let url = URL(string: "didfeedthedog://log?petId=not-a-uuid")!
        XCTAssertNil(parseDeepLink(url))
    }
}
