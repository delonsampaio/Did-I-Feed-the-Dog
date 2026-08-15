import XCTest
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedSyncEngineIsOwnerTests: XCTestCase {
    func testIsOwnerFalseForZoneWithNoPrivateToken() {
        // A zone that has never been synced has no token under either scope — isOwner must
        // report false. CKServerChangeToken has no public initializer, so the true-path (a
        // real private-scope token present) is verified by the Phase 5 manual two-account
        // checklist, not a unit test — matching SyncTokenStoreDBScopeTests, which for the
        // same reason only covers the nil/corrupt paths.
        let zoneName = "Zone-\(UUID().uuidString)"
        XCTAssertFalse(SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName))
    }
}
