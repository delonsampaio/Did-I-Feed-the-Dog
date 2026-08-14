import CloudKit
import Foundation
import os

/// Caches the current user's CloudKit record name FROM THE sharedsync CONTAINER.
/// Identity differs per container, so routing logic must use this value (seeded from the
/// custom-sync container), never the NSPCKC container's user ID.
@MainActor
final class CloudKitIdentity {
    static let shared = CloudKitIdentity()

    nonisolated private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "CloudKitIdentity")
    nonisolated private static let key = "sharedSyncMyCloudKitID"

    private let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
    private let defaults: UserDefaults
    private(set) var cachedID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cachedID = defaults.string(forKey: Self.key)
    }

    /// Fetches and caches the user record name. Best-effort; failures keep the existing cache.
    func refresh() async {
        do {
            let id = try await container.userRecordID()
            cachedID = id.recordName
            defaults.set(id.recordName, forKey: Self.key)
        } catch {
            Self.log.error("userRecordID failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
