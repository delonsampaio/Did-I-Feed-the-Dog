import XCTest
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedSyncEnginePushDecisionTests: XCTestCase {

    func testApplyingRemoteSuppressesEverything() {
        var pending: Set<String> = []
        let d = SharedSyncEngine.pushDecision(insertedUpdatedRecordNames: ["a"], deletedRecordNames: ["b"],
                                              applyingRemote: true, pendingRemoteDeleteIDs: &pending)
        XCTAssertTrue(d.saveNames.isEmpty)
        XCTAssertTrue(d.deleteNames.isEmpty)
    }

    func testLocalSavesPassThrough() {
        var pending: Set<String> = []
        let d = SharedSyncEngine.pushDecision(insertedUpdatedRecordNames: ["a", "c"], deletedRecordNames: ["b"],
                                              applyingRemote: false, pendingRemoteDeleteIDs: &pending)
        XCTAssertEqual(Set(d.saveNames), ["a", "c"])
        XCTAssertEqual(d.deleteNames, ["b"])
    }

    func testRemoteDeleteEchoIsConsumedAndSkipped() {
        var pending: Set<String> = ["b"] // we just applied a remote deletion of "b"
        let d = SharedSyncEngine.pushDecision(insertedUpdatedRecordNames: [], deletedRecordNames: ["b"],
                                              applyingRemote: false, pendingRemoteDeleteIDs: &pending)
        XCTAssertTrue(d.deleteNames.isEmpty, "remote-delete echo must not be re-pushed")
        XCTAssertFalse(pending.contains("b"), "pending id must be consumed")
    }
}
