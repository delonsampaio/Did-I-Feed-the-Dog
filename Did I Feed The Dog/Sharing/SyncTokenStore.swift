import CloudKit
import Foundation
import os

/// Persists CloudKit change tokens in UserDefaults (not Core Data, to avoid taking the
/// store write lock for token reads/writes). Guards against the two ways a token silently
/// dies — archive failure that erases the key, and persisting a mid-page `moreComing` cursor
/// (the caller's responsibility: only pass the final checkpoint here).
struct SyncTokenStore {
    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SyncTokenStore")

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: DB token (per database scope: "private" | "shared")
    private func dbKey(_ scope: String) -> String { "sharedSyncDBToken.\(scope)" }
    func loadDBToken(scope: String) -> CKServerChangeToken? { unarchive(defaults.data(forKey: dbKey(scope))) }
    func saveDBToken(_ token: CKServerChangeToken, scope: String) { archiveAndStore(token, key: dbKey(scope)) }

    // MARK: zone tokens
    private func zoneKey(_ zoneName: String, _ scope: String) -> String { "zoneToken.\(zoneName).\(scope)" }
    func loadZoneToken(_ zoneName: String, scope: String) -> CKServerChangeToken? {
        unarchive(defaults.data(forKey: zoneKey(zoneName, scope)))
    }
    func saveZoneToken(_ token: CKServerChangeToken, zoneName: String, scope: String) {
        archiveAndStore(token, key: zoneKey(zoneName, scope))
    }
    func clearZoneTokens(_ zoneName: String) {
        for scope in ["private", "shared"] { defaults.removeObject(forKey: zoneKey(zoneName, scope)) }
    }

    // MARK: helpers
    private func unarchive(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
    private func archiveAndStore(_ token: CKServerChangeToken, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            Self.log.error("token archive failed for \(key, privacy: .public) — keeping existing token")
            return // do NOT set(nil): that erases the good token → full re-download → re-push storm
        }
        defaults.set(data, forKey: key)
    }
}
