# Family Sharing — Phase 2 Sync Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A custom CloudKit engine that mirrors the Phase 1 shared Core Data store to/from the separate `iCloud.com.delon.DidIFeedTheDog.sharedsync` container's private database (owner / same-account), so a `SharedPet` and its children round-trip between two devices on one iCloud account.

**Architecture:** Three focused units in `Did I Feed The Dog/Sharing/`: `SyncTokenStore` (UserDefaults change tokens, safe persistence), `CKRecordMapper` (Core Data ↔ CKRecord using NSPCKC's `CD_` convention + zone resolution + upsert), and `SharedSyncEngine` (`@MainActor` singleton: zone creation, push with parents-first ordering + last-writer-wins, paged pull with background-context upsert, echo suppression). Driven on launch/foreground/poll; gated by `sharingFoundationEnabled`.

**Tech Stack:** Swift, CloudKit (modern async `CKDatabase` APIs: `databaseChanges`, `recordZoneChanges`, `modifyRecords`, `modifyRecordZones`), Core Data, XCTest.

## Global Constraints

- **Design source:** `docs/superpowers/specs/2026-06-23-family-sharing-sync-engine-design.md`. Every task inherits its constraints.
- **CloudKit container (this phase):** `iCloud.com.delon.DidIFeedTheDog.sharedsync`, **`privateCloudDatabase` only**. No `sharedCloudDatabase`, no CKShare, no participant routing, no "my CloudKit ID" seeding (Phase 3).
- **No silent push this phase:** no `CKDatabaseSubscription`, no `aps-environment` entitlement, no `remote-notification` background mode, no APNs. Sync is driven on launch, on `scenePhase` `.active`, and by a lightweight foreground poll.
- **Flag-gated:** the engine starts and makes CloudKit calls **only** when `SharingFeatureFlag.isFoundationEnabled` is true. Flag off (release default) = zero CloudKit calls, behavior identical to today.
- **Conflict policy:** last-writer-wins (client-trumps) — on `.serverRecordChanged`, re-apply local fields onto `ck.serverRecord`, retry once.
- **Single-container simplification (refinement vs spec/skill):** the shared store is its own `NSPersistentContainer` (one store). Therefore every object in `SharedDataStack`'s context is already in the shared store — do **not** call `context.assign(_, to:)` and do **not** filter by `isInSharedStore`; both are NSPCKC-multi-store machinery that does not apply here.
- **`CD_` field convention:** attribute `foo` → `CD_foo`; to-one relationship `parent` → `CD_parent` = parent's `ckRecordName` string; add `CD_entityName`; Bool→`1`/`0`; `UUID`→`uuidString`; `Data`(`photoData`)→`CKAsset`. `skipped` = the four `ck*` fields only.
- **Zone naming:** root `SharedPet` → `CKRecordZone.ID(zoneName: "Zone-\(pet.id.uuidString)", ownerName: CKCurrentUserDefaultName)`.
- **Token keys:** `"zoneToken.<zoneName>.<scope>"` (scope = `"private"`); DB token key `"sharedSyncDBToken.private"`.
- **Never `fatalError`.** Log via `os.Logger(subsystem: "com.delon.DidIFeedTheDog", category: ...)`.
- **The engine never round-trips the `ck*` fields**, but DOES round-trip all domain attributes including denormalized `lastFeedingDate` / `todaysFeedingCountRaw` (synced as plain fields, LWW).

### Environment / mechanics (apply to every task)

- **New files** go in `Did I Feed The Dog/Sharing/` (app code → target "Did I Feed The Dog") or `Did I Feed The DogTests/` (tests → target "Did I Feed The DogTests"). The project uses Xcode 16 **filesystem-synchronized groups** — files in the right directory are auto-included; **no `project.pbxproj` edits**.
- **Swift 6 `-default-isolation=MainActor`** is in effect. SwiftUI views and the engine are MainActor; resolve MainActor singletons inside `@MainActor` bodies, not in default-argument expressions. Mark CloudKit completion/observer escaping state that must be touched off-actor with care (see the echo-suppression pattern).
- **Run a test class:**
  ```
  xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Did I Feed The DogTests/<ClassName>" 2>&1 | tail -40
  ```
- **Build:**
  ```
  xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
  ```
- **Known-flaky baseline:** two `FeedingLogServiceTests` are slow (~100s) and intermittently time out; a stale `PetTests.testAgeStringMonthsOnly` asserts "5 months" vs the intended "Puppy". These are pre-existing — judge success by new tests passing and no NEW failures in files you touched.
- **CloudKit async API shapes:** verify exact return-tuple labels against the SDK at build time (the LSP reminder applies). The code below uses the modern convenience APIs; adjust labels if the compiler disagrees, keeping behavior identical.

---

### Task 1: SyncTokenStore

**Files:**
- Create: `Did I Feed The Dog/Sharing/SyncTokenStore.swift`
- Test: `Did I Feed The DogTests/SyncTokenStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct SyncTokenStore` with an injectable `UserDefaults` (`init(defaults: UserDefaults = .standard)`).
  - `func loadDBToken() -> CKServerChangeToken?` / `func saveDBToken(_:)`
  - `func loadZoneToken(_ zoneName: String, scope: String) -> CKServerChangeToken?` / `func saveZoneToken(_:zoneName:scope:)`
  - `func clearZoneTokens(_ zoneName: String)` (removes all scopes for a zone)
  - Archive failure keeps the existing token (never `set(nil)`).

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SyncTokenStoreTests.swift`:

```swift
import XCTest
import CloudKit
@testable import Did_I_Feed_The_Dog

final class SyncTokenStoreTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "SyncTokenStoreTests-\(UUID().uuidString)")!
        return d
    }

    // A real CKServerChangeToken can't be constructed directly; round-trip via archiving
    // a token obtained from a fetch is not possible in a unit test. Instead we verify the
    // store's KEY behavior: archive-failure safety and key naming, using nil/no-token paths
    // plus a stand-in archived blob.

    func testLoadReturnsNilWhenAbsent() {
        let store = SyncTokenStore(defaults: freshDefaults())
        XCTAssertNil(store.loadDBToken())
        XCTAssertNil(store.loadZoneToken("Zone-abc", scope: "private"))
    }

    func testZoneTokenKeyIsScoped() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        // Simulate a previously-stored (opaque) blob under the expected key; loadZoneToken
        // should attempt to unarchive THIS key.
        d.set(Data([0x00]), forKey: "zoneToken.Zone-abc.private")
        // Corrupt blob → unarchive fails → returns nil (not a crash).
        XCTAssertNil(store.loadZoneToken("Zone-abc", scope: "private"))
        // A different scope must be a different key (still nil).
        XCTAssertNil(store.loadZoneToken("Zone-abc", scope: "shared"))
    }

    func testClearZoneTokensRemovesPrivateKey() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        d.set(Data([0x01]), forKey: "zoneToken.Zone-xyz.private")
        store.clearZoneTokens("Zone-xyz")
        XCTAssertNil(d.data(forKey: "zoneToken.Zone-xyz.private"))
    }

    func testCorruptDBTokenBlobReturnsNilNotCrash() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        d.set(Data([0xFF, 0x00]), forKey: "sharedSyncDBToken.private")
        XCTAssertNil(store.loadDBToken())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SyncTokenStoreTests"`. Expected: compile failure (`SyncTokenStore` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/SyncTokenStore.swift`:

```swift
import CloudKit
import Foundation
import os

/// Persists CloudKit change tokens in UserDefaults (not Core Data, to avoid taking the
/// store write lock for token reads/writes). Guards against the two ways a token silently
/// dies — archive failure that erases the key, and persisting a mid-page `moreComing` cursor
/// (the caller's responsibility: only pass the final checkpoint here).
struct SyncTokenStore {
    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SyncTokenStore")
    private static let dbKey = "sharedSyncDBToken.private"

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: DB token
    func loadDBToken() -> CKServerChangeToken? { unarchive(defaults.data(forKey: Self.dbKey)) }
    func saveDBToken(_ token: CKServerChangeToken) { archiveAndStore(token, key: Self.dbKey) }

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
```

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/SyncTokenStoreTests"`. Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SyncTokenStore.swift" "Did I Feed The DogTests/SyncTokenStoreTests.swift"
git commit -m "feat: SyncTokenStore with safe token persistence (#57 phase 2)"
```

---

### Task 2: CKRecordMapper

**Files:**
- Create: `Did I Feed The Dog/Sharing/CKRecordMapper.swift`
- Test: `Did I Feed The DogTests/CKRecordMapperTests.swift`

**Interfaces:**
- Consumes: the Shared* `NSManagedObject` subclasses; `SharedDataStack` (tests use an in-memory stack).
- Produces (all `static` on `enum CKRecordMapper`):
  - `func encodedSystemFields(of: CKRecord) -> Data` / `func record(fromSystemFields: Data?) -> CKRecord?`
  - `func zoneID(forRoot pet: SharedPet) -> CKRecordZone.ID`
  - `func zoneID(forNewObject: NSManagedObject, visited: Set<NSManagedObjectID>) -> CKRecordZone.ID?`
  - `func rank(for object: NSManagedObject) -> Int` (SharedPet 0, SharedFeedingEvent/SharedMedication 1, SharedMedicationLog 2)
  - `func applyFields(of: NSManagedObject, to: CKRecord)`
  - `func ckRecord(for: NSManagedObject) -> CKRecord?`
  - `func recordID(forDeleted: NSManagedObject) -> CKRecord.ID?`
  - `func apply(records: [CKRecord], deletions: [CKRecord.ID], into: NSManagedObjectContext)` (upsert)

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/CKRecordMapperTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/CKRecordMapperTests"`. Expected: compile failure (`CKRecordMapper` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/CKRecordMapper.swift`:

```swift
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
    static func encodedSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }
    static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data, let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: zones
    static func zoneID(forRoot pet: SharedPet) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Zone-\(pet.id.uuidString)", ownerName: CKCurrentUserDefaultName)
    }
    /// A new object borrows its zone from a synced ancestor; if none is synced yet, recurse to
    /// the root SharedPet base case. Cycle-guarded by visited objectIDs (gotcha #3).
    static func zoneID(forNewObject object: NSManagedObject, visited: Set<NSManagedObjectID> = []) -> CKRecordZone.ID? {
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
    static func rank(for object: NSManagedObject) -> Int {
        switch object.entity.name {
        case "SharedPet": return 0
        case "SharedFeedingEvent", "SharedMedication": return 1
        case "SharedMedicationLog": return 2
        default: return 99
        }
    }

    // MARK: encode
    static func applyFields(of object: NSManagedObject, to out: CKRecord) {
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

    static func ckRecord(for object: NSManagedObject) -> CKRecord? {
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

    static func recordID(forDeleted object: NSManagedObject) -> CKRecord.ID? {
        record(fromSystemFields: object.value(forKey: "ckSystemFields") as? Data)?.recordID
    }

    // MARK: decode / upsert
    static func apply(records: [CKRecord], deletions: [CKRecord.ID], into ctx: NSManagedObjectContext) {
        // Deletions first, by ckRecordName.
        let deleteNames = Set(deletions.map(\.recordID.recordName))
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

    private static func applyIncoming(_ rec: CKRecord, to obj: NSManagedObject) {
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

    private static func fetchByRecordName(_ name: String, entity: String?, in ctx: NSManagedObjectContext) -> NSManagedObject? {
        guard let entity else { return nil }
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "ckRecordName == %@", name)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }

    private static func tempAsset(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try data.write(to: url); return url } catch { log.error("tempAsset write failed"); return nil }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/CKRecordMapperTests"`. Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/CKRecordMapper.swift" "Did I Feed The DogTests/CKRecordMapperTests.swift"
git commit -m "feat: CKRecordMapper (CD_ convention, zone resolution, upsert) (#57 phase 2)"
```

---

### Task 3: SharedSyncEngine — container, zones, push, echo suppression

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`
- Test: `Did I Feed The DogTests/SharedSyncEnginePushDecisionTests.swift`

**Interfaces:**
- Consumes: `CKRecordMapper`, `SyncTokenStore`, `SharedDataStack`, `CKContainer`.
- Produces:
  - `extension Notification.Name { static let sharedRemoteChangeApplied = Notification.Name("sharedRemoteChangeApplied") }`
  - `@MainActor final class SharedSyncEngine` with `static let shared`, `func start()`, `func push(saveObjectIDs:delete:) async`, `func ensureZone(forRoot pet: SharedPet) async`.
  - `nonisolated(unsafe) static var applyingRemote: Bool` and `nonisolated(unsafe) static var pendingRemoteDeleteIDs: Set<String>` (main-thread only; used by the synchronous observer).
  - `static func pushDecision(insertedUpdatedRecordNames: [String], deletedRecordNames: [String], applyingRemote: Bool, pendingRemoteDeleteIDs: inout Set<String>) -> (saveNames: [String], deleteNames: [String])` — the **pure** observer decision, unit-tested.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedSyncEnginePushDecisionTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEnginePushDecisionTests"`. Expected: compile failure (`SharedSyncEngine` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`:

```swift
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

    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedSyncEngine")
    private static let containerID = "iCloud.com.delon.DidIFeedTheDog.sharedsync"

    private let container = CKContainer(identifier: SharedSyncEngine.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
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
            let deletedRecordIDs: [CKRecord.ID] = deletedObjs.compactMap(CKRecordMapper.recordID(forDeleted:))

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
    static func pushDecision(insertedUpdatedRecordNames: [String],
                             deletedRecordNames: [String],
                             applyingRemote: Bool,
                             pendingRemoteDeleteIDs: inout Set<String>) -> (saveNames: [String], deleteNames: [String]) {
        guard !applyingRemote else { return ([], []) }
        let deletes = deletedRecordNames.filter { pendingRemoteDeleteIDs.remove($0) == nil }
        return (insertedUpdatedRecordNames, deletes)
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

        // Ensure a zone exists for every root pet involved (a pet directly, or the root
        // ancestor of a child). ensureZone is idempotent (createdZones-guarded).
        var rootsEnsured: Set<NSManagedObjectID> = []
        for obj in objects {
            if let root = rootPet(of: obj), !rootsEnsured.contains(root.objectID) {
                await ensureZone(forRoot: root)
                rootsEnsured.insert(root.objectID)
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

        do {
            let (saveResults, _) = try await privateDB.modifyRecords(
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
                let (retry, _) = try await privateDB.modifyRecords(saving: conflicts, deleting: [],
                                                                   savePolicy: .ifServerRecordUnchanged, atomically: false)
                for (id, result) in retry {
                    if case .success(let saved) = result, let obj = objectByName[id.recordName] {
                        obj.setValue(CKRecordMapper.encodedSystemFields(of: saved), forKey: "ckSystemFields")
                    }
                }
            }
            // Persist written-back system fields, suppressed so we don't re-push.
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

    // Pull is added in Task 4.
    func fetchAllZones() async { /* implemented in Task 4 */ }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEnginePushDecisionTests"`. Expected: 3 tests PASS. Then build the app:
```
xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: BUILD SUCCEEDED. (The `fetchAllZones()` stub is intentional; Task 4 fills it.)

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncEngine.swift" "Did I Feed The DogTests/SharedSyncEnginePushDecisionTests.swift"
git commit -m "feat: SharedSyncEngine push + zones + echo suppression (#57 phase 2)"
```

---

### Task 4: SharedSyncEngine — pull

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift` (replace the `fetchAllZones()` stub)

**Interfaces:**
- Consumes: everything from Task 3, `SyncTokenStore`, `CKRecordMapper.apply`.
- Produces: working `func fetchAllZones() async` and `private func fetchZone(_:) async -> Int`, posting `.sharedRemoteChangeApplied` once after all zones; purges on `zoneNotFound`.

- [ ] **Step 1: Replace the `fetchAllZones()` stub**

In `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`, replace `func fetchAllZones() async { /* implemented in Task 4 */ }` with:

```swift
    func fetchAllZones() async {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        guard !isSyncing else { pendingFetch = true; return }
        isSyncing = true; defer { isSyncing = false }
        repeat {
            pendingFetch = false
            do {
                let dbChanges = try await privateDB.databaseChanges(since: tokens.loadDBToken())
                tokens.saveDBToken(dbChanges.changeToken)
                for deletion in dbChanges.deletions { purgeZone(deletion.zoneID) }
                var anyApplied = false
                for mod in dbChanges.modifications {
                    let n = await fetchZone(mod.zoneID)
                    anyApplied = anyApplied || (n > 0)
                }
                if anyApplied {
                    NotificationCenter.default.post(name: .sharedRemoteChangeApplied, object: nil)
                }
            } catch {
                Self.log.error("fetchAllZones failed: \(error.localizedDescription, privacy: .public)")
            }
        } while pendingFetch
    }

    private func fetchZone(_ zoneID: CKRecordZone.ID) async -> Int {
        var since = tokens.loadZoneToken(zoneID.zoneName, scope: "private")
        var checkpoint: CKServerChangeToken?
        var more = false
        var total = 0
        repeat {
            do {
                let changes = try await privateDB.recordZoneChanges(inZoneWith: zoneID, since: since)
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
                purgeZone(zoneID)
                return total
            } catch {
                Self.log.error("fetchZone \(zoneID.zoneName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return total
            }
        } while more
        if let checkpoint { tokens.saveZoneToken(checkpoint, zoneName: zoneID.zoneName, scope: "private") }
        return total
    }

    private func purgeZone(_ zoneID: CKRecordZone.ID) {
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
```

> Note: `applyingRemote` is set/reset inside `bg.perform`. Because the bookkeeping/echo flag is read on the main thread by the synchronous observer and the apply runs on a background queue, this is the documented `nonisolated(unsafe)` single-flag pattern from the skill; the synchronous observer only fires for main-context saves, and remote applies happen on the background context whose merge into the view context is covered by `pendingRemoteDeleteIDs`.

- [ ] **Step 2: Build to verify it compiles**

```
xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: BUILD SUCCEEDED, no new warnings in SharedSyncEngine.swift.

- [ ] **Step 3: Re-run the push-decision tests (regression)**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEnginePushDecisionTests"`. Expected: 3 PASS (unchanged).

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncEngine.swift"
git commit -m "feat: SharedSyncEngine pull (paged zone changes + safe tokens) (#57 phase 2)"
```

---

### Task 5: Wiring, lifecycle, and manual validation

**Files:**
- Modify: `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift` (start engine + foreground fetch + poll, flag-gated)
- Modify: `Did I Feed The Dog/Sharing/SharedDogStore.swift` (observe `.sharedRemoteChangeApplied`)

**Interfaces:**
- Consumes: `SharedSyncEngine.shared`, `SharingFeatureFlag`, `.sharedRemoteChangeApplied`.
- Produces: engine started on launch and re-fetched on foreground + poll; dashboard refreshes when remote changes are applied.

- [ ] **Step 1: Start engine + drive fetch on foreground (App)**

In `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift`, add `@Environment(\.scenePhase)` and wire lifecycle on the `WindowGroup`'s root view. Read the file first to integrate with the existing `.task`/`.onOpenURL`. Add:

```swift
    @Environment(\.scenePhase) private var scenePhase
```

and on the `ContentView` in `body` (alongside the existing modifiers):

```swift
                .task {
                    if SharingFeatureFlag.isFoundationEnabled { SharedSyncEngine.shared.start() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, SharingFeatureFlag.isFoundationEnabled {
                        Task { await SharedSyncEngine.shared.fetchAllZones() }
                    }
                }
```

> If a `.task` already exists on `ContentView`, merge the body rather than adding a second one.

- [ ] **Step 2: Lightweight foreground poll**

Add a poll that runs only while active and the flag is on. In the same view, add a timer-driven fetch:

```swift
                .task(id: scenePhase) {
                    guard scenePhase == .active, SharingFeatureFlag.isFoundationEnabled else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(20))
                        if Task.isCancelled { break }
                        await SharedSyncEngine.shared.fetchAllZones()
                    }
                }
```

> `task(id: scenePhase)` cancels and restarts when scenePhase changes, so the poll loop runs only while active. 20s is a reasonable foreground backstop.

- [ ] **Step 3: Dashboard refresh on remote changes (SharedDogStore)**

In `Did I Feed The Dog/Sharing/SharedDogStore.swift`, in `startObserving()`, add a second observer for `.sharedRemoteChangeApplied` that calls `refresh()` on the main actor (mirror the existing DidSave observer pattern, storing the token in the existing `ObserverBox` or a second box). Read the file first to match its concurrency pattern. Example addition inside `startObserving()`:

```swift
        observerBox.remoteToken = NotificationCenter.default.addObserver(
            forName: .sharedRemoteChangeApplied, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
```

Add `var remoteToken: NSObjectProtocol?` to `ObserverBox` and remove it in `deinit` alongside the existing token.

- [ ] **Step 4: Build + full test suite**

```
xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -40
```
Expected: BUILD SUCCEEDED; new suites (SyncTokenStoreTests, CKRecordMapperTests, SharedSyncEnginePushDecisionTests) PASS; no new failures in touched files.

- [ ] **Step 5: Confirm flag-off no-op**

Reason about / verify: with `sharingFoundationEnabled` false, `start()` returns immediately, `fetchAllZones()` returns immediately, the poll guard fails — zero CloudKit calls, behavior identical to today.

- [ ] **Step 6: Manual device validation (DEBUG, two same-account devices) — REQUIRED before calling Phase 2 done**

Per the skill's gotcha #6 (debugger masks push delivery), run from the home screen, not Xcode. On two devices signed into the **same** iCloud account, clean install, flag ON (Settings → Sharing Foundation DEBUG → Render shared dogs):

1. Device A: tap "Insert sample shared dog" → within a foreground fetch (or relaunch) on Device B, the dog appears on B's dashboard.
2. Confirm no infinite loop / no duplicate dogs (echo suppression holds) — the dog appears exactly once and the app stays responsive.
3. (If a temporary DEBUG rename action is available) edit on A → B reflects it after a foreground fetch.
4. Delete the seeded dog on A → it disappears on B and does NOT reappear (deletion echo suppressed).

Record results in the report. This step is manual; the controller/developer runs it on hardware.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift" "Did I Feed The Dog/Sharing/SharedDogStore.swift"
git commit -m "feat: wire SharedSyncEngine into launch/foreground/poll + dashboard refresh (#57 phase 2)"
```

---

## Self-Review

**Spec coverage:**
- `CKRecordMapper` (CD_ convention, system fields, zone resolution incl. root + recursion, upsert, rank) → Task 2. ✓
- `SyncTokenStore` (archive guard, scoped keys, no set(nil); moreComing handled by caller in Task 4) → Task 1 + Task 4. ✓
- `SharedSyncEngine` zone creation + push + LWW conflict + echo suppression (applyingRemote + pendingRemoteDeleteIDs) → Task 3. ✓
- Pull (paged, background apply, token persist final checkpoint only, zoneNotFound purge, single notification) → Task 4. ✓
- Lifecycle (launch/foreground/poll, flag-gated) + dashboard refresh → Task 5. ✓
- Flag-off zero-CloudKit guarantee → Tasks 3/4 guards + Task 5 Step 5. ✓
- Private DB only; no CKShare/participant/silent push/migration → nothing implements them (out of scope). ✓
- Single-container simplification (no context.assign / isInSharedStore) → Global Constraints + Task 3 observer comment. ✓
- Denormalized fields synced as plain CD_ fields → Task 2 `skipped` excludes only ck* fields. ✓
- Manual two-device validation → Task 5 Step 6. ✓

**Placeholder scan:** The only intentional stub is `fetchAllZones()` in Task 3, explicitly filled in Task 4 (and Task 3 Step 4 notes the stub builds). No TBD/TODO; all code steps show complete code.

**Type consistency:** `SharedSyncEngine.pushDecision(insertedUpdatedRecordNames:deletedRecordNames:applyingRemote:pendingRemoteDeleteIDs:)` signature matches between Task 3 implementation and its tests. `CKRecordMapper` static names (`zoneID(forRoot:)`, `zoneID(forNewObject:visited:)`, `rank(for:)`, `applyFields(of:to:)`, `ckRecord(for:)`, `recordID(forDeleted:)`, `apply(records:deletions:into:)`, `encodedSystemFields(of:)`, `record(fromSystemFields:)`) are consistent across Tasks 2–4. `SyncTokenStore` method names consistent across Tasks 1 and 4. `.sharedRemoteChangeApplied` defined in Task 3, consumed in Tasks 4–5. `ObserverBox.remoteToken` added in Task 5 Step 3.
