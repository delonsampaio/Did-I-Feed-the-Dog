import XCTest
import CloudKit
@testable import Did_I_Feed_The_Dog

final class SharedSyncEngineRoutingTests: XCTestCase {
    func testCurrentUserSentinelIsOwned() {
        XCTAssertTrue(SharedSyncEngine.isOwnedZone(
            ownerName: CKCurrentUserDefaultName, myCloudKitID: "me", hasPrivateToken: false))
    }

    func testMyRealRecordNameIsOwned() {
        XCTAssertTrue(SharedSyncEngine.isOwnedZone(
            ownerName: "me", myCloudKitID: "me", hasPrivateToken: false))
    }

    func testPrivateTokenMeansOwnedEvenIfOwnerUnknown() {
        // Seeding window: owner created the zone, identity not yet resolved, but a private
        // token already exists → still owned.
        XCTAssertTrue(SharedSyncEngine.isOwnedZone(
            ownerName: "someone", myCloudKitID: nil, hasPrivateToken: true))
    }

    func testOtherOwnerWithNoPrivateTokenIsShared() {
        XCTAssertFalse(SharedSyncEngine.isOwnedZone(
            ownerName: "owner-A", myCloudKitID: "me", hasPrivateToken: false))
    }
}
