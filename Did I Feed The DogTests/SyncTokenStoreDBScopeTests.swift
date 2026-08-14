import XCTest
import CloudKit
@testable import Did_I_Feed_The_Dog

final class SyncTokenStoreDBScopeTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SyncTokenStoreDBScopeTests-\(UUID().uuidString)")!
    }

    func testDBTokenIsScoped() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        XCTAssertNil(store.loadDBToken(scope: "private"))
        XCTAssertNil(store.loadDBToken(scope: "shared"))
        // A corrupt blob under the private DB key must not bleed into the shared scope.
        d.set(Data([0x00]), forKey: "sharedSyncDBToken.private")
        XCTAssertNil(store.loadDBToken(scope: "private")) // corrupt → nil, no crash
        XCTAssertNil(store.loadDBToken(scope: "shared"))  // different key
    }
}
