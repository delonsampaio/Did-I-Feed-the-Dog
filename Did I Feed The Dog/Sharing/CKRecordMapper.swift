import CloudKit
import CoreData
import Foundation
import os

/// Converts the shared store's NSManagedObjects to/from CKRecords using NSPCKC's CD_ wire
/// convention, so the data stays schema-compatible. Pure (no CloudKit I/O); all I/O lives in
/// SharedSyncEngine.
enum CKRecordMapper {
    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "CKRecordMapper")

    /// Local-only attributes that must never round-trip to CloudKit.
    private static let skipped: Set<String> = ["ckRecordName", "ckSystemFields", "ckZoneName", "ckDatabaseScope"]

    // MARK: system fields
    nonisolated static func encodedSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }

    nonisolated static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data, let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: zones
    nonisolated static func zoneID(forRoot pet: SharedPet) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Zone-\(pet.id.uuidString)", ownerName: CKCurrentUserDefaultName)
    }

    /// A new object borrows its zone from a synced ancestor; if none is synced yet, recurse to
    /// the root SharedPet base case. Cycle-guarded by visited objectIDs.
    nonisolated static func zoneID(forNewObject object: NSManagedObject, visited: Set<NSManagedObjectID> = []) -> CKRecordZone.ID? {
        if let pet = object as? SharedPet { return zoneID(forRoot: pet) }
        guard !visited.contains(object.objectID) else { return nil }
        var visited = visited; visited.insert(object.objectID)
        for (name, rel) in object.entity.relationshipsByName where !rel.isToMany {
            guard let parent = object.value(forKey: name) as? NSManagedObject else { continue }
            if let rec = record(fromSystemFields: parent.value(forKey: "ckSystemFields") as? Data) {
                return rec.recordID.zoneID
            }
            if let zone = zoneID(forNewObject: parent, visited: visited) { return zone }
        }
        return nil
    }

    // MARK: ordering
    nonisolated static func rank(for object: NSManagedObject) -> Int {
        switch object.entity.name {
        case "SharedPet": return 0
        case "SharedFeedingEvent", "SharedMedication": return 1
        case "SharedMedicationLog": return 2
        default: return 99
        }
    }

    // MARK: encode
    nonisolated static func applyFields(of object: NSManagedObject, to out: CKRecord) {
        out["CD_entityName"] = (object.entity.name ?? "") as CKRecordValue
        for (name, attr) in object.entity.attributesByName where !skipped.contains(name) {
            let key = "CD_\(name)"
            let v = object.value(forKey: name)
            switch attr.attributeType {
            case .booleanAttributeType:
                out[key] = (((v as? Bool) == true) ? 1 : 0) as CKRecordValue
            case .UUIDAttributeType:
                if let u = v as? UUID { out[key] = u.uuidString as CKRecordValue }
            case .binaryDataAttributeType:
                if let d = v as? Data, let url = tempAsset(d) { out["\(key)_ckAsset"] = CKAsset(fileURL: url) }
            default:
                if let val = v as? CKRecordValue { out[key] = val }
            }
        }
        for (name, rel) in object.entity.relationshipsByName where !rel.isToMany {
            let parentName = (object.value(forKey: name) as? NSManagedObject)?.value(forKey: "ckRecordName") as? String
            out["CD_\(name)"] = (parentName?.isEmpty == false) ? (parentName! as CKRecordValue) : nil
        }
    }

    nonisolated static func ckRecord(for object: NSManagedObject) -> CKRecord? {
        let out: CKRecord
        if let existing = record(fromSystemFields: object.value(forKey: "ckSystemFields") as? Data) {
            out = existing
        } else {
            guard let zoneID = zoneID(forNewObject: object) else {
                log.error("no zone for new \(object.entity.name ?? "?", privacy: .public) — skipped")
                return nil
            }
            let name = (object.value(forKey: "ckRecordName") as? String) ?? UUID().uuidString
            object.setValue(name, forKey: "ckRecordName")
            out = CKRecord(recordType: "CD_\(object.entity.name!)",
                           recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        }
        applyFields(of: object, to: out)
        return out
    }

    nonisolated static func recordID(forDeleted object: NSManagedObject) -> CKRecord.ID? {
        record(fromSystemFields: object.value(forKey: "ckSystemFields") as? Data)?.recordID
    }

    // MARK: decode / upsert
    // NOTE: brief had `deletions.map(\.recordID.recordName)` which is wrong —
    // CKRecord.ID has no .recordID property; corrected to `\.recordName`.
    nonisolated static func apply(records: [CKRecord], deletions: [CKRecord.ID], into ctx: NSManagedObjectContext) {
        // Deletions first, by ckRecordName.
        let deleteNames = Set(deletions.map(\.recordName))
        if !deleteNames.isEmpty {
            for entity in ["SharedPet", "SharedFeedingEvent", "SharedMedication", "SharedMedicationLog"] {
                let req = NSFetchRequest<NSManagedObject>(entityName: entity)
                req.predicate = NSPredicate(format: "ckRecordName IN %@", deleteNames)
                for obj in (try? ctx.fetch(req)) ?? [] { ctx.delete(obj) }
            }
        }
        guard !records.isEmpty else { return }

        // Group incoming by entity; batch-fetch existing locals by ckRecordName.
        var byName: [String: NSManagedObject] = [:]
        let byEntity = Dictionary(grouping: records, by: { $0["CD_entityName"] as? String ?? $0.recordType.replacingOccurrences(of: "CD_", with: "") })
        for (entity, recs) in byEntity {
            let names = recs.map(\.recordID.recordName)
            let req = NSFetchRequest<NSManagedObject>(entityName: entity)
            req.predicate = NSPredicate(format: "ckRecordName IN %@", names)
            for obj in (try? ctx.fetch(req)) ?? [] {
                if let n = obj.value(forKey: "ckRecordName") as? String { byName[n] = obj }
            }
            for rec in recs {
                let obj = byName[rec.recordID.recordName] ?? NSEntityDescription.insertNewObject(forEntityName: entity, into: ctx)
                applyIncoming(rec, to: obj)
                byName[rec.recordID.recordName] = obj
            }
        }
        // Second pass: wire CD_<rel> string references to local objects.
        for rec in records {
            guard let obj = byName[rec.recordID.recordName] else { continue }
            for (name, rel) in obj.entity.relationshipsByName where !rel.isToMany {
                guard let parentName = rec["CD_\(name)"] as? String else { continue }
                if let parent = byName[parentName] ?? fetchByRecordName(parentName, entity: rel.destinationEntity?.name, in: ctx) {
                    obj.setValue(parent, forKey: name)
                }
            }
        }
    }

    private nonisolated static func applyIncoming(_ rec: CKRecord, to obj: NSManagedObject) {
        obj.setValue(rec.recordID.recordName, forKey: "ckRecordName")
        obj.setValue(encodedSystemFields(of: rec), forKey: "ckSystemFields")
        obj.setValue(rec.recordID.zoneID.zoneName, forKey: "ckZoneName")
        for (name, attr) in obj.entity.attributesByName where !skipped.contains(name) {
            let key = "CD_\(name)"
            switch attr.attributeType {
            case .booleanAttributeType:
                if let n = rec[key] as? Int { obj.setValue(n != 0, forKey: name) }
            case .UUIDAttributeType:
                if let s = rec[key] as? String, let u = UUID(uuidString: s) { obj.setValue(u, forKey: name) }
            case .binaryDataAttributeType:
                if let asset = rec["\(key)_ckAsset"] as? CKAsset, let url = asset.fileURL,
                   let d = try? Data(contentsOf: url) { obj.setValue(d, forKey: name) }
            default:
                if let v = rec[key] { obj.setValue(v, forKey: name) }
            }
        }
    }

    private nonisolated static func fetchByRecordName(_ name: String, entity: String?, in ctx: NSManagedObjectContext) -> NSManagedObject? {
        guard let entity else { return nil }
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "ckRecordName == %@", name)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }

    private nonisolated static func tempAsset(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try data.write(to: url); return url } catch { log.error("tempAsset write failed"); return nil }
    }
}
