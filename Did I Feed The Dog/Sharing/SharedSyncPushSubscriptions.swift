import CloudKit
import Foundation
import os

/// Registers silent CloudKit database subscriptions so the app is woken by APNs when a shared
/// dog changes. Two subscriptions: one on the sharedsync private DB (owner wakes on participant
/// edits) and one on its shared DB (participant wakes on owner edits). No NSPCKC involved, so
/// these are plain CKDatabaseSubscriptions with our own IDs and content-available delivery.
@MainActor
final class SharedSyncPushSubscriptions {
    static let shared = SharedSyncPushSubscriptions()

    nonisolated static let privateSubID = "sharedsync-private-db"
    nonisolated static let sharedSubID = "sharedsync-shared-db"

    nonisolated private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedSyncPush")
    nonisolated private static let registeredKey = "sharedSyncSubscriptionsRegistered"

    private let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Is this incoming CloudKit notification for one of our two subscriptions?
    nonisolated static func isOurSharedSyncNotification(subscriptionID: String?) -> Bool {
        guard let subscriptionID else { return false }
        return subscriptionID == privateSubID || subscriptionID == sharedSubID
    }

    /// Pure guard: attempt registration only when sharing is on and we haven't succeeded before.
    nonisolated static func shouldAttemptRegistration(flagEnabled: Bool, alreadyRegistered: Bool) -> Bool {
        flagEnabled && !alreadyRegistered
    }

    /// Save both subscriptions once. Idempotent: a UserDefaults flag prevents re-saving every
    /// launch; a failure clears the flag so the next launch retries. No-op unless the flag is on.
    func registerIfNeeded() async {
        let alreadyRegistered = defaults.bool(forKey: Self.registeredKey)
        guard Self.shouldAttemptRegistration(flagEnabled: SharingFeatureFlag.isFoundationEnabled,
                                             alreadyRegistered: alreadyRegistered) else { return }
        do {
            try await save(Self.privateSubID, to: container.privateCloudDatabase)
            try await save(Self.sharedSubID, to: container.sharedCloudDatabase)
            defaults.set(true, forKey: Self.registeredKey)
        } catch {
            defaults.set(false, forKey: Self.registeredKey) // retry on next launch
            Self.log.error("subscription registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save(_ id: String, to db: CKDatabase) async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent: no alert/badge/sound
        subscription.notificationInfo = info
        _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
    }
}
