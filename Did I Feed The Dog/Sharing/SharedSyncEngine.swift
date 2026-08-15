import CloudKit
import CoreData
import Foundation
import os

extension Notification.Name {
    static let sharedRemoteChangeApplied = Notification.Name("sharedRemoteChangeApplied")
}

/// Custom CloudKit engine for the shared store. Phase 2: owner / privateCloudDatabase only,
/// driven on launch/foreground/poll. Heavy Core Data work hops to a background context.
@MainActor
final class SharedSyncEngine {
    static let shared = SharedSyncEngine()

    nonisolated private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedSyncEngine")
    private static let containerID = "iCloud.com.delon.DidIFeedTheDog.sharedsync"

    private let container = CKContainer(identifier: SharedSyncEngine.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private let stack = SharedDataStack.shared
    private let tokens = SyncTokenStore()

    private var startedObserving = false
    private var createdZones: Set<String> = []
    private var isSyncing = false
    private var pendingFetch = false

    // Echo suppression — touched only on the main thread.
    nonisolated(unsafe) static var applyingRemote = false
    nonisolated(unsafe) static var pendingRemoteDeleteIDs: Set<String> = []

    private init() {}

    func start() {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        if !startedObserving { attachPushObserver(); startedObserving = true }
        Task { await fetchAllZones() }
        Task { await SharedSyncPushSubscriptions.shared.registerIfNeeded() }
    }

    // MARK: push observer (synchronous so it runs inside the save while the flag is set)
    private func attachPushObserver() {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave,
                                               object: stack.viewContext, queue: nil) { note in
            // All objects in this context are in the shared store (single-store container),
            // so no isInSharedStore filtering is needed.
            let changed = ((note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
                .union((note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
            let deletedObjs = (note.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []

            let saveIDsByName: [(String, NSManagedObjectID)] = changed.compactMap {
                guard let n = $0.value(forKey: "ckRecordName") as? String else { return nil }
                return (n, $0.objectID)
            }
            let deletedRecordIDs: [CKRecord.ID] = deletedObjs.compactMap { CKRecordMapper.recordID(forDeleted: $0) }

            var pending = SharedSyncEngine.pendingRemoteDeleteIDs
            let decision = SharedSyncEngine.pushDecision(
                insertedUpdatedRecordNames: saveIDsByName.map(\.0),
                deletedRecordNames: deletedRecordIDs.map(\.recordName),
                applyingRemote: SharedSyncEngine.applyingRemote,
                pendingRemoteDeleteIDs: &pending)
            SharedSyncEngine.pendingRemoteDeleteIDs = pending

            guard !decision.saveNames.isEmpty || !decision.deleteNames.isEmpty else { return }
            let objectIDs = saveIDsByName.filter { decision.saveNames.contains($0.0) }.map(\.1)
            let deleteIDs = deletedRecordIDs.filter { decision.deleteNames.contains($0.recordName) }
            for id in deleteIDs { Self.log.info("push: deleting \(id.recordName, privacy: .public)") }
            Task { @MainActor in await SharedSyncEngine.shared.push(saveObjectIDs: objectIDs, delete: deleteIDs) }
        }
    }

    /// Pure decision used by the observer (and unit tests): suppress all while applyingRemote;
    /// consume-and-skip deletions that echo a remote delete we just applied.
    nonisolated static func pushDecision(insertedUpdatedRecordNames: [String],
                             deletedRecordNames: [String],
                             applyingRemote: Bool,
                             pendingRemoteDeleteIDs: inout Set<String>) -> (saveNames: [String], deleteNames: [String]) {
        guard !applyingRemote else { return ([], []) }
        let deletes = deletedRecordNames.filter { pendingRemoteDeleteIDs.remove($0) == nil }
        return (insertedUpdatedRecordNames, deletes)
    }

    /// Pure routing decision: is this zone owned by the current user (→ privateCloudDatabase)
    /// or shared with them (→ sharedCloudDatabase)? Owned if the owner is the current-user
    /// sentinel, or the cached own record name, or a private-scope token already exists
    /// (covers the owner's zone-creation seeding window before identity resolves).
    nonisolated static func isOwnedZone(ownerName: String, myCloudKitID: String?, hasPrivateToken: Bool) -> Bool {
        if ownerName == CKCurrentUserDefaultName { return true }
        if let myCloudKitID, ownerName == myCloudKitID { return true }
        return hasPrivateToken
    }

    private func database(forZone zoneID: CKRecordZone.ID) -> CKDatabase {
        let hasPriv = tokens.loadZoneToken(zoneID.zoneName, scope: "private") != nil
        let owned = Self.isOwnedZone(ownerName: zoneID.ownerName,
                                     myCloudKitID: CloudKitIdentity.shared.cachedID,
                                     hasPrivateToken: hasPriv)
        return owned ? privateDB : sharedDB
    }

    // MARK: zones
    func ensureZone(forRoot pet: SharedPet) async {
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        guard !createdZones.contains(zoneID.zoneName) else { return }
        do {
            _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            createdZones.insert(zoneID.zoneName)
        } catch {
            Self.log.error("ensureZone failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: push
    func push(saveObjectIDs: [NSManagedObjectID], delete recordIDs: [CKRecord.ID]) async {
        let ctx = stack.viewContext
        let objects = saveObjectIDs.compactMap { try? ctx.existingObject(with: $0) }
            .sorted { CKRecordMapper.rank(for: $0) < CKRecordMapper.rank(for: $1) }

        // Ensure a zone exists ONLY for brand-new root pets (no ckSystemFields yet). A pet
        // that already has system fields already has its zone: owned zones exist, and a
        // participant's shared zone is owned by someone else and must NOT be recreated in our
        // private DB — doing so leaves a stray private zone whose change token later poisons
        // database(forZone:)'s hasPrivateToken check and misroutes the participant's edits.
        var rootsEnsured: Set<NSManagedObjectID> = []
        for obj in objects {
            guard let root = rootPet(of: obj), !rootsEnsured.contains(root.objectID) else { continue }
            rootsEnsured.insert(root.objectID)
            if root.value(forKey: "ckSystemFields") == nil {
                await ensureZone(forRoot: root)
            }
        }

        var records: [CKRecord] = []
        var objectByName: [String: NSManagedObject] = [:]
        for obj in objects {
            if let r = CKRecordMapper.ckRecord(for: obj), let n = obj.value(forKey: "ckRecordName") as? String {
                records.append(r); objectByName[n] = obj
            }
        }
        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        // Collect temp asset URLs for cleanup after upload.
        let tempAssetURLs: [URL] = records.flatMap { record in
            record.allKeys().compactMap { key -> URL? in
                guard let asset = record[key] as? CKAsset, let url = asset.fileURL else { return nil }
                // Only clean up URLs in the temp directory (written by CKRecordMapper.tempAsset).
                return url.path.hasPrefix(FileManager.default.temporaryDirectory.path) ? url : nil
            }
        }

        // Group by destination database (owner→private, participant→shared).
        var saveByDB: [ObjectIdentifier: (db: CKDatabase, records: [CKRecord])] = [:]
        for r in records {
            let db = database(forZone: r.recordID.zoneID)
            saveByDB[ObjectIdentifier(db), default: (db, [])].records.append(r)
        }
        var deleteByDB: [ObjectIdentifier: (db: CKDatabase, ids: [CKRecord.ID])] = [:]
        for id in recordIDs {
            let db = database(forZone: id.zoneID)
            deleteByDB[ObjectIdentifier(db), default: (db, [])].ids.append(id)
        }
        let dbKeys = Set(saveByDB.keys).union(deleteByDB.keys)

        for key in dbKeys {
            let db = saveByDB[key]?.db ?? deleteByDB[key]!.db
            let saves = saveByDB[key]?.records ?? []
            let deletes = deleteByDB[key]?.ids ?? []
            await pushGroup(saving: saves, deleting: deletes, to: db, objectByName: objectByName, ctx: ctx)
        }

        for url in tempAssetURLs { try? FileManager.default.removeItem(at: url) }
    }

    /// Upload one database's worth of records with LWW conflict handling + write-back.
    private func pushGroup(saving records: [CKRecord], deleting recordIDs: [CKRecord.ID],
                           to db: CKDatabase, objectByName: [String: NSManagedObject],
                           ctx: NSManagedObjectContext) async {
        guard !records.isEmpty || !recordIDs.isEmpty else { return }
        do {
            let (saveResults, _) = try await db.modifyRecords(
                saving: records, deleting: recordIDs,
                savePolicy: .ifServerRecordUnchanged, atomically: false)
            var conflicts: [CKRecord] = []
            for (id, result) in saveResults {
                switch result {
                case .success(let saved):
                    if let obj = objectByName[id.recordName] {
                        obj.setValue(CKRecordMapper.encodedSystemFields(of: saved), forKey: "ckSystemFields")
                        obj.setValue(saved.recordID.zoneID.zoneName, forKey: "ckZoneName")
                    }
                case .failure(let e):
                    if let ck = e as? CKError, ck.code == .serverRecordChanged, let server = ck.serverRecord,
                       let obj = objectByName[id.recordName] {
                        CKRecordMapper.applyFields(of: obj, to: server) // client-trumps (LWW)
                        conflicts.append(server)
                    } else {
                        Self.log.error("push record failed: \(e.localizedDescription, privacy: .public)")
                    }
                }
            }
            if !conflicts.isEmpty {
                let (retry, _) = try await db.modifyRecords(saving: conflicts, deleting: [],
                                                            savePolicy: .ifServerRecordUnchanged, atomically: false)
                for (id, result) in retry {
                    if case .success(let saved) = result, let obj = objectByName[id.recordName] {
                        obj.setValue(CKRecordMapper.encodedSystemFields(of: saved), forKey: "ckSystemFields")
                        obj.setValue(saved.recordID.zoneID.zoneName, forKey: "ckZoneName")
                    }
                }
            }
            SharedSyncEngine.applyingRemote = true
            try? ctx.save()
            SharedSyncEngine.applyingRemote = false
        } catch {
            Self.log.error("push batch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rootPet(of object: NSManagedObject) -> SharedPet? {
        if let p = object as? SharedPet { return p }
        for (name, rel) in object.entity.relationshipsByName where !rel.isToMany {
            if let parent = object.value(forKey: name) as? NSManagedObject, let root = rootPet(of: parent) { return root }
        }
        return nil
    }

    // MARK: pull
    func fetchAllZones() async {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        guard !isSyncing else { pendingFetch = true; return }
        isSyncing = true; defer { isSyncing = false }
        repeat {
            pendingFetch = false
            var anyApplied = false
            anyApplied = await fetchDatabase(privateDB, scope: "private") || anyApplied
            anyApplied = await fetchDatabase(sharedDB, scope: "shared") || anyApplied
            if anyApplied {
                NotificationCenter.default.post(name: .sharedRemoteChangeApplied, object: nil)
            }
        } while pendingFetch
    }

    /// Fetch all changed zones for one database (owner=private / participant=shared).
    private func fetchDatabase(_ db: CKDatabase, scope: String) async -> Bool {
        do {
            let dbChanges = try await db.databaseChanges(since: tokens.loadDBToken(scope: scope))
            tokens.saveDBToken(dbChanges.changeToken, scope: scope)
            for deletion in dbChanges.deletions { purgeZone(deletion.zoneID, scope: scope) }
            var anyApplied = false
            for mod in dbChanges.modifications {
                let n = await fetchZone(mod.zoneID, in: db, scope: scope)
                anyApplied = anyApplied || (n > 0)
            }
            return anyApplied
        } catch {
            Self.log.error("fetchDatabase(\(scope, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func fetchZone(_ zoneID: CKRecordZone.ID, in db: CKDatabase, scope: String) async -> Int {
        var since = tokens.loadZoneToken(zoneID.zoneName, scope: scope)
        var checkpoint: CKServerChangeToken?
        var more = false
        var total = 0
        repeat {
            do {
                let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: since)
                let records = changes.modificationResultsByID.values
                    .compactMap { try? $0.get().record }
                    .filter { $0.recordType != CKRecord.SystemType.share }
                let deletions = changes.deletions.map(\.recordID)
                if !records.isEmpty || !deletions.isEmpty {
                    for id in deletions { SharedSyncEngine.pendingRemoteDeleteIDs.insert(id.recordName) }
                    let bg = stack.newBackgroundContext()
                    await bg.perform {
                        SharedSyncEngine.applyingRemote = true
                        CKRecordMapper.apply(records: records, deletions: deletions, into: bg)
                        try? bg.save()
                        SharedSyncEngine.applyingRemote = false
                    }
                    total += records.count + deletions.count
                }
                since = changes.changeToken
                checkpoint = changes.changeToken
                more = changes.moreComing
            } catch let e as CKError where e.code == .zoneNotFound {
                purgeZone(zoneID, scope: scope)
                return total
            } catch {
                Self.log.error("fetchZone \(zoneID.zoneName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return total
            }
        } while more
        if let checkpoint { tokens.saveZoneToken(checkpoint, zoneName: zoneID.zoneName, scope: scope) }
        return total
    }

    /// Public entry for owner stop-sharing: purge the local copy of a zone by name.
    func purgeLocalZone(named zoneName: String) {
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        purgeZone(zoneID, scope: "private")
    }

    private func purgeZone(_ zoneID: CKRecordZone.ID, scope: String) {
        let bg = stack.newBackgroundContext()
        bg.perform {
            SharedSyncEngine.applyingRemote = true
            let req = NSFetchRequest<NSManagedObject>(entityName: "SharedPet")
            req.predicate = NSPredicate(format: "ckZoneName == %@", zoneID.zoneName)
            for pet in (try? bg.fetch(req)) ?? [] { bg.delete(pet) } // cascade removes children
            try? bg.save()
            SharedSyncEngine.applyingRemote = false
        }
        tokens.clearZoneTokens(zoneID.zoneName)
        createdZones.remove(zoneID.zoneName)
    }
}
