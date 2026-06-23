import XCTest
import CoreData
import CloudKit
@testable import Did_I_Feed_The_Dog

final class CKRecordMapperTests: XCTestCase {

    private func ctx() -> NSManagedObjectContext { SharedDataStack(inMemory: true).viewContext }

    private func makePet(in c: NSManagedObjectContext, name: String = "Buster") -> SharedPet {
        let p = SharedPet(context: c); p.id = UUID(); p.name = name
        p.ckRecordName = p.id.uuidString
        return p
    }

    func testRankOrdersParentsBeforeChildren() {
        let c = ctx()
        let pet = makePet(in: c)
        let ev = SharedFeedingEvent(context: c); ev.timestamp = .now; ev.notes = ""
        let med = SharedMedication(context: c); med.id = UUID(); med.name = "Rx"
        let log = SharedMedicationLog(context: c); log.id = UUID(); log.timestamp = .now; log.loggedBy = ""; log.medicationName = ""
        XCTAssertLessThan(CKRecordMapper.rank(for: pet), CKRecordMapper.rank(for: ev))
        XCTAssertLessThan(CKRecordMapper.rank(for: med), CKRecordMapper.rank(for: log))
    }

    func testRootZoneIDDerivedFromPetUUID() {
        let c = ctx()
        let pet = makePet(in: c)
        XCTAssertEqual(CKRecordMapper.zoneID(forRoot: pet).zoneName, "Zone-\(pet.id.uuidString)")
    }

    func testApplyFieldsUsesCDConvention() {
        let c = ctx()
        let pet = makePet(in: c, name: "Rex"); pet.isFasting = true; pet.foodStockCount = 7
        let rec = CKRecord(recordType: "CD_SharedPet",
                           recordID: CKRecord.ID(recordName: pet.ckRecordName!,
                                                 zoneID: CKRecordMapper.zoneID(forRoot: pet)))
        CKRecordMapper.applyFields(of: pet, to: rec)
        XCTAssertEqual(rec["CD_entityName"] as? String, "SharedPet")
        XCTAssertEqual(rec["CD_name"] as? String, "Rex")
        XCTAssertEqual(rec["CD_isFasting"] as? Int, 1)
        XCTAssertEqual(rec["CD_foodStockCount"] as? Int64, 7)
        XCTAssertNil(rec["CD_ckRecordName"]) // ck* fields skipped
    }

    func testChildCDRelationshipIsParentRecordName() {
        let c = ctx()
        let pet = makePet(in: c)
        let ev = SharedFeedingEvent(context: c); ev.timestamp = .now; ev.notes = ""; ev.pet = pet
        ev.ckRecordName = UUID().uuidString
        let rec = CKRecord(recordType: "CD_SharedFeedingEvent",
                           recordID: CKRecord.ID(recordName: ev.ckRecordName!, zoneID: CKRecordMapper.zoneID(forRoot: pet)))
        CKRecordMapper.applyFields(of: ev, to: rec)
        XCTAssertEqual(rec["CD_pet"] as? String, pet.ckRecordName)
    }

    func testZoneResolutionRecursesToRootForNewChild() {
        let c = ctx()
        let pet = makePet(in: c) // root, has ckRecordName but NO ckSystemFields (new)
        let med = SharedMedication(context: c); med.id = UUID(); med.name = "Rx"; med.pet = pet
        let log = SharedMedicationLog(context: c); log.id = UUID(); log.timestamp = .now
        log.loggedBy = ""; log.medicationName = ""; log.medication = med
        // log -> med -> pet(root); none have ckSystemFields, so resolution must hit the root base case.
        let zone = CKRecordMapper.zoneID(forNewObject: log, visited: [])
        XCTAssertEqual(zone?.zoneName, "Zone-\(pet.id.uuidString)")
    }

    func testCKRecordForNewPetMintsRecordNameAndType() {
        let c = ctx()
        let pet = SharedPet(context: c); pet.id = UUID(); pet.name = "New"
        let rec = CKRecordMapper.ckRecord(for: pet)
        XCTAssertEqual(rec?.recordType, "CD_SharedPet")
        XCTAssertEqual(pet.ckRecordName, rec?.recordID.recordName)
        XCTAssertEqual(rec?.recordID.zoneID.zoneName, "Zone-\(pet.id.uuidString)")
    }

    func testUpsertInsertsThenUpdatesByRecordName() {
        let c = ctx()
        let zone = CKRecordZone.ID(zoneName: "Zone-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let rid = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let rec = CKRecord(recordType: "CD_SharedPet", recordID: rid)
        rec["CD_entityName"] = "SharedPet"
        rec["CD_id"] = UUID().uuidString
        rec["CD_name"] = "Fetched"
        CKRecordMapper.apply(records: [rec], deletions: [], into: c)
        let pets1 = try! c.fetch(NSFetchRequest<SharedPet>(entityName: "SharedPet"))
        XCTAssertEqual(pets1.count, 1)
        XCTAssertEqual(pets1.first?.name, "Fetched")
        XCTAssertEqual(pets1.first?.ckRecordName, rid.recordName)
        // Update same record name → no duplicate.
        rec["CD_name"] = "Renamed"
        CKRecordMapper.apply(records: [rec], deletions: [], into: c)
        let pets2 = try! c.fetch(NSFetchRequest<SharedPet>(entityName: "SharedPet"))
        XCTAssertEqual(pets2.count, 1)
        XCTAssertEqual(pets2.first?.name, "Renamed")
    }

    func testUpsertDeletionRemovesByRecordName() {
        let c = ctx()
        let zone = CKRecordZone.ID(zoneName: "Zone-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let rid = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let rec = CKRecord(recordType: "CD_SharedPet", recordID: rid)
        rec["CD_entityName"] = "SharedPet"; rec["CD_id"] = UUID().uuidString; rec["CD_name"] = "Doomed"
        CKRecordMapper.apply(records: [rec], deletions: [], into: c)
        CKRecordMapper.apply(records: [], deletions: [rid], into: c)
        XCTAssertEqual(try! c.fetch(NSFetchRequest<SharedPet>(entityName: "SharedPet")).count, 0)
    }

    func testOptionalBoolNilIsNotEncoded() {
        let c = ctx()
        let pet = makePet(in: c)
        let zone = CKRecordMapper.zoneID(forRoot: pet)

        // nil didDeductStock → key must be absent from the CKRecord
        let evNil = SharedFeedingEvent(context: c)
        evNil.timestamp = .now; evNil.notes = ""; evNil.pet = pet
        evNil.didDeductStock = nil
        evNil.ckRecordName = UUID().uuidString
        let recNil = CKRecord(recordType: "CD_SharedFeedingEvent",
                              recordID: CKRecord.ID(recordName: evNil.ckRecordName!, zoneID: zone))
        CKRecordMapper.applyFields(of: evNil, to: recNil)
        XCTAssertNil(recNil["CD_didDeductStock"], "nil optional Bool must not be encoded (key should be absent)")

        // true didDeductStock → key must be 1
        let evTrue = SharedFeedingEvent(context: c)
        evTrue.timestamp = .now; evTrue.notes = ""; evTrue.pet = pet
        evTrue.didDeductStock = NSNumber(value: true)
        evTrue.ckRecordName = UUID().uuidString
        let recTrue = CKRecord(recordType: "CD_SharedFeedingEvent",
                               recordID: CKRecord.ID(recordName: evTrue.ckRecordName!, zoneID: zone))
        CKRecordMapper.applyFields(of: evTrue, to: recTrue)
        XCTAssertEqual(recTrue["CD_didDeductStock"] as? Int, 1, "true optional Bool must encode as 1")
    }

    func testPhotoDataRoundTripsThroughCKAsset() {
        let c = ctx()
        let originalBytes = Data("woof".utf8)

        // Build a SharedPet with photoData
        let pet = SharedPet(context: c)
        pet.id = UUID(); pet.name = "Pixel"
        pet.photoData = originalBytes
        pet.ckRecordName = pet.id.uuidString

        // Encode via ckRecord(for:) — pet is its own zone root so zoneID resolves
        guard let ckRec = CKRecordMapper.ckRecord(for: pet) else {
            return XCTFail("ckRecord(for:) returned nil")
        }

        // The asset key must be present
        XCTAssertNotNil(ckRec["CD_photoData_ckAsset"] as? CKAsset,
                        "photoData must be written as a CKAsset")

        // Stamp entity name and id so apply() can find/insert the record
        ckRec["CD_entityName"] = "SharedPet"
        ckRec["CD_id"] = pet.id.uuidString as CKRecordValue

        // Decode into a fresh in-memory context
        let c2 = SharedDataStack(inMemory: true).viewContext
        CKRecordMapper.apply(records: [ckRec], deletions: [], into: c2)

        let fetched = try! c2.fetch(NSFetchRequest<SharedPet>(entityName: "SharedPet"))
        XCTAssertEqual(fetched.count, 1, "exactly one SharedPet should be upserted")
        XCTAssertEqual(fetched.first?.photoData, originalBytes,
                       "photoData must survive a CKAsset round-trip")
    }
}
