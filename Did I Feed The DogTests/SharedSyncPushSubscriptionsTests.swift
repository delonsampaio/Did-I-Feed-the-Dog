import XCTest
@testable import Did_I_Feed_The_Dog

final class SharedSyncPushSubscriptionsTests: XCTestCase {

    func testIsOurNotificationMatchesBothSubscriptionIDs() {
        XCTAssertTrue(SharedSyncPushSubscriptions.isOurSharedSyncNotification(
            subscriptionID: SharedSyncPushSubscriptions.privateSubID))
        XCTAssertTrue(SharedSyncPushSubscriptions.isOurSharedSyncNotification(
            subscriptionID: SharedSyncPushSubscriptions.sharedSubID))
    }

    func testIsOurNotificationRejectsForeignAndNil() {
        XCTAssertFalse(SharedSyncPushSubscriptions.isOurSharedSyncNotification(subscriptionID: "some-other-sub"))
        XCTAssertFalse(SharedSyncPushSubscriptions.isOurSharedSyncNotification(subscriptionID: nil))
    }

    func testShouldAttemptRegistrationOnlyWhenFlagOnAndNotYetRegistered() {
        XCTAssertTrue(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: true, alreadyRegistered: false))
        XCTAssertFalse(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: true, alreadyRegistered: true))
        XCTAssertFalse(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: false, alreadyRegistered: false))
        XCTAssertFalse(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: false, alreadyRegistered: true))
    }
}
