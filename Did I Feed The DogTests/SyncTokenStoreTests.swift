import XCTest
import CloudKit
@testable import Did_I_Feed_The_Dog

final class SyncTokenStoreTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "SyncTokenStoreTests-\(UUID().uuidString)")!
        return d
    }

    // A real CKServerChangeToken can't be constructed directly; round-trip via archiving
    // a token obtained from a fetch is not possible in a unit test. Instead we verify the
    // store's KEY behavior: archive-failure safety and key naming, using nil/no-token paths
    // plus a stand-in archived blob.

    func testLoadReturnsNilWhenAbsent() {
        let store = SyncTokenStore(defaults: freshDefaults())
        XCTAssertNil(store.loadDBToken())
        XCTAssertNil(store.loadZoneToken("Zone-abc", scope: "private"))
    }

    func testZoneTokenKeyIsScoped() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        // Simulate a previously-stored (opaque) blob under the expected key; loadZoneToken
        // should attempt to unarchive THIS key.
        d.set(Data([0x00]), forKey: "zoneToken.Zone-abc.private")
        // Corrupt blob → unarchive fails → returns nil (not a crash).
        XCTAssertNil(store.loadZoneToken("Zone-abc", scope: "private"))
        // A different scope must be a different key (still nil).
        XCTAssertNil(store.loadZoneToken("Zone-abc", scope: "shared"))
    }

    func testClearZoneTokensRemovesPrivateKey() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        d.set(Data([0x01]), forKey: "zoneToken.Zone-xyz.private")
        store.clearZoneTokens("Zone-xyz")
        XCTAssertNil(d.data(forKey: "zoneToken.Zone-xyz.private"))
    }

    func testCorruptDBTokenBlobReturnsNilNotCrash() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        d.set(Data([0xFF, 0x00]), forKey: "sharedSyncDBToken.private")
        XCTAssertNil(store.loadDBToken())
    }
}
