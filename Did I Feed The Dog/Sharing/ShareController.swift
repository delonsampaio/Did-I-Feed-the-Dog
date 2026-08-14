import CloudKit
import Foundation
import os

/// Owner-side share lifecycle: create a zone-wide CKShare for a shared dog, fetch it back,
/// and stop sharing (delete the zone). Phase 3 operates on DEBUG-seeded SharedPets; the real
/// Pro-gated entry point ships with first-share migration.
@MainActor
enum ShareController {
    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "ShareController")
    private static let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
    private static var privateDB: CKDatabase { container.privateCloudDatabase }

    /// Ensure the dog's zone exists, then create (or fetch the existing) zone-wide share.
    static func makeShare(forRoot pet: SharedPet) async throws -> CKShare {
        await SharedSyncEngine.shared.ensureZone(forRoot: pet)
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = (pet.name ?? "A dog") as CKRecordValue
        share.publicPermission = .none
        do {
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged)
            return share
        } catch let e as CKError where e.code == .serverRecordChanged || e.code == .partialFailure {
            // Already shared (interrupted retry) — fetch the well-known zone-wide share.
            let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            guard let existing = try await privateDB.record(for: id) as? CKShare else { throw e }
            return existing
        }
    }

    static func fetchShare(forRoot pet: SharedPet) async throws -> CKShare? {
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try? await privateDB.record(for: id) as? CKShare
    }

    /// Owner stops sharing: delete the zone (participants get zoneNotFound → purge) and clean up locally.
    static func stopSharing(forRoot pet: SharedPet) async {
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        do {
            _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch {
            Self.log.error("stopSharing failed: \(error.localizedDescription, privacy: .public)")
        }
        await SharedSyncEngine.shared.purgeLocalZone(named: zoneID.zoneName)
    }
}
