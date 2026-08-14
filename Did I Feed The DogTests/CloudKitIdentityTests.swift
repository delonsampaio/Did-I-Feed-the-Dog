import XCTest
@testable import Did_I_Feed_The_Dog

@MainActor
final class CloudKitIdentityTests: XCTestCase {
    func testLoadsCachedIDFromDefaultsOnInit() {
        let d = UserDefaults(suiteName: "CloudKitIdentityTests-\(UUID().uuidString)")!
        d.set("user-record-123", forKey: "sharedSyncMyCloudKitID")
        let identity = CloudKitIdentity(defaults: d)
        XCTAssertEqual(identity.cachedID, "user-record-123")
    }

    func testNilWhenNoCache() {
        let d = UserDefaults(suiteName: "CloudKitIdentityTests-\(UUID().uuidString)")!
        XCTAssertNil(CloudKitIdentity(defaults: d).cachedID)
    }
}
