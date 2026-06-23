# Family Sharing — Phase 1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a parallel Core Data stack for shared dogs alongside the existing SwiftData stack, plus a `DogDisplayable` UI seam so the dashboard renders owned and shared dogs through one path — with no CloudKit traffic yet.

**Architecture:** SwiftData and the private-data path are left untouched. A new, separate `NSPersistentContainer` (plain Core Data, no `NSPersistentCloudKitContainer`) with persistent history tracking holds `SharedPet`/`SharedFeedingEvent`/`SharedMedication`/`SharedMedicationLog` in an app-group SQLite file. A `DogDisplayable` protocol abstracts the read surface over both `Pet` (SwiftData) and `SharedPet` (Core Data) so `DashboardView`/`PetCard` render either. A separate CloudKit container is reserved in entitlements for Phase 2's sync engine.

**Tech Stack:** Swift, SwiftUI, SwiftData (existing), Core Data (new, for shared store), CloudKit (reserved only — no calls this phase), XCTest.

## Global Constraints

- **Design source:** `docs/superpowers/specs/2026-06-22-family-sharing-foundation-design.md`. Every task implicitly inherits its constraints.
- **Do not modify the SwiftData stack or private-data path** beyond the additive `DashboardView` merge and the `Pet` `DogDisplayable` conformance/`ageString` refactor (behavior-preserving).
- **The shared Core Data stack must never `fatalError`** on store-load failure — log and degrade to "owned dogs only".
- **Naming:** new user-sharing concept uses the `Shared*` prefix for Core Data entities and `SharedDataStack`/`SharedDogStore` for services. Never reuse the food-stock identifiers (`sharedFoodStock`, `StockMode`, `stockOutScopeIsShared`). User-facing copy says "Shared dog".
- **CloudKit container reserved this phase:** `iCloud.com.delon.DidIFeedTheDog.sharedsync` (added to entitlements, **unused** until Phase 2).
- **App group (reuse existing):** `group.com.delon.DidIFeedTheDog`.
- **Existing CloudKit container (do not touch):** `iCloud.com.delon.DidIFeedTheDog`.
- **Feature flag:** `sharingFoundationEnabled` (UserDefaults, `.sharedGroup`), default **false** in release. Shared-dog fetch/render only when true.
- **Refinement vs spec:** the spec's `SharedDataModel.xcdatamodeld` is implemented as a **programmatic `NSManagedObjectModel`** (pure Swift). Same entities/attributes/relationships and the same sync-bookkeeping fields; chosen to avoid model-bundle/pbxproj friction and to keep the model unit-testable without the Xcode GUI.
- **Sync-bookkeeping fields** exist on every shared entity now but are unused this phase: `ckRecordName: String?`, `ckSystemFields: Data?`, `ckZoneName: String?`, `ckDatabaseScope: Int16` (default 0).

### Adding new files to the Xcode target (applies to every Create step)

The project uses a raw `project.pbxproj` (no XcodeGen). After creating a new `.swift` file on disk you must add it to the correct target's "Compile Sources":

- **App-code files** (under `Did I Feed The Dog/…`) → target **"Did I Feed The Dog"**.
- **Test files** (under `Did I Feed The DogTests/…`) → target **"Did I Feed The DogTests"**.

Recommended programmatic method (no GUI), using the `xcodeproj` Ruby gem (preinstalled with CocoaPods; else `gem install xcodeproj`):

```bash
ruby -e '
require "xcodeproj"
proj = Xcodeproj::Project.open("Did I Feed The Dog.xcodeproj")
target = proj.targets.find { |t| t.name == ARGV[0] }
group  = proj.main_group.find_subpath(ARGV[1], true)
ref    = group.new_file(File.expand_path(ARGV[2]))
target.add_file_references([ref])
proj.save
' "<TARGET NAME>" "<group/path>" "<absolute/file/path>"
```

If `xcodeproj` is unavailable, add the file via Xcode (File ▸ Add Files…, check the correct target). **Every "Create" step below is not done until the file compiles into its target.**

### Build / test commands

Confirm exact scheme/target names once at the start:

```bash
xcodebuild -project "Did I Feed The Dog.xcodeproj" -list
```

Run a single test class (substitute an installed simulator from `xcrun simctl list devices available`):

```bash
xcodebuild test \
  -project "Did I Feed The Dog.xcodeproj" \
  -scheme "Did I Feed The Dog" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:"Did I Feed The DogTests/<ClassName>" \
  2>&1 | xcbeautify || true
```

Full app build (compile check):

```bash
xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

Widget compile check (entitlement unchanged, must still build):

```bash
xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "DidIFeedTheDogWidgetExtension" -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

> If `xcbeautify` is not installed, drop the pipe. All `git commit` steps assume the current branch is `feature/family-sharing-foundation`.

---

### Task 1: Reserve the separate CloudKit container in entitlements

**Files:**
- Modify: `DidIFeedTheDog.entitlements`

**Interfaces:**
- Consumes: nothing.
- Produces: entitlement now lists `iCloud.com.delon.DidIFeedTheDog.sharedsync` (used by Phase 2 only).

- [ ] **Step 1: Add the container to the identifier array**

Edit `DidIFeedTheDog.entitlements` so the iCloud container array contains both the existing and the new container:

```xml
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.delon.DidIFeedTheDog</string>
		<string>iCloud.com.delon.DidIFeedTheDog.sharedsync</string>
	</array>
```

- [ ] **Step 2: Verify the app still builds**

Run the full app build command. Expected: BUILD SUCCEEDED. (The container is unused in code, so a signing warning about the new container is acceptable locally; the developer creates the container in CloudKit Dashboard / regenerates the provisioning profile before Phase 2.)

- [ ] **Step 3: Commit**

```bash
git add DidIFeedTheDog.entitlements
git commit -m "chore: reserve sharedsync CloudKit container for family sharing (#57 phase 1)"
```

---

### Task 2: Programmatic Core Data model + managed object subclasses

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharedDataModel.swift`
- Create: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`
- Test: `Did I Feed The DogTests/SharedDataModelTests.swift`

**Interfaces:**
- Produces:
  - `enum SharedDataModel { static func makeModel() -> NSManagedObjectModel }` — builds the `NSManagedObjectModel` for the four entities.
  - `@objc(SharedPet) final class SharedPet: NSManagedObject` with `@NSManaged` properties: `id: UUID`, `name: String?`, `birthday: Date?`, `photoData: Data?`, `foodStockCount: Int64`, `feedingScheduleTimesRaw: String`, `isFasting: Bool`, `notificationsMuted: Bool`, `lastFeedingDate: Date?`, `todaysFeedingCount: Int64`, `ckRecordName: String?`, `ckSystemFields: Data?`, `ckZoneName: String?`, `ckDatabaseScope: Int16`, `feedingEvents: NSSet?`, `medications: NSSet?`.
  - `@objc(SharedFeedingEvent) final class SharedFeedingEvent: NSManagedObject` — `timestamp: Date`, `mealType: String?`, `notes: String`, `loggedBy: String?`, `didDeductStock: NSNumber?`, `portionsDeducted: NSNumber?`, the four `ck*` fields, `pet: SharedPet?`.
  - `@objc(SharedMedication) final class SharedMedication: NSManagedObject` — `id: UUID`, `name: String`, `dose: String`, `frequencyHours: Int64`, `notificationsEnabled: Bool`, `reminderMinutesRaw: String`, `lastGivenDate: Date?`, the four `ck*` fields, `pet: SharedPet?`, `logs: NSSet?`.
  - `@objc(SharedMedicationLog) final class SharedMedicationLog: NSManagedObject` — `id: UUID`, `timestamp: Date`, `notes: String`, `loggedBy: String`, `medicationName: String`, `petId: UUID?`, the four `ck*` fields, `medication: SharedMedication?`.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedDataModelTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedDataModelTests: XCTestCase {

    /// Builds an in-memory Core Data stack from the programmatic model.
    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let container = NSPersistentContainer(name: "SharedTest", managedObjectModel: model)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container.viewContext
    }

    func testModelDefinesAllFourEntities() throws {
        let model = SharedDataModel.makeModel()
        let names = Set(model.entities.compactMap { $0.name })
        XCTAssertEqual(names, ["SharedPet", "SharedFeedingEvent", "SharedMedication", "SharedMedicationLog"])
    }

    func testPetHasSyncBookkeepingFields() throws {
        let model = SharedDataModel.makeModel()
        let pet = try XCTUnwrap(model.entitiesByName["SharedPet"])
        XCTAssertNotNil(pet.attributesByName["ckRecordName"])
        XCTAssertNotNil(pet.attributesByName["ckSystemFields"])
        XCTAssertNotNil(pet.attributesByName["ckZoneName"])
        XCTAssertNotNil(pet.attributesByName["ckDatabaseScope"])
    }

    func testInsertAndFetchPetWithChild() throws {
        let ctx = try makeInMemoryContext()
        let pet = SharedPet(context: ctx)
        pet.id = UUID()
        pet.name = "Buster"
        let event = SharedFeedingEvent(context: ctx)
        event.timestamp = .now
        event.notes = ""
        event.pet = pet
        try ctx.save()

        let fetched = try ctx.fetch(NSFetchRequest<SharedPet>(entityName: "SharedPet"))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Buster")
        XCTAssertEqual((fetched.first?.feedingEvents as? Set<SharedFeedingEvent>)?.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command with `-only-testing:"Did I Feed The DogTests/SharedDataModelTests"`.
Expected: FAILS to compile (`SharedDataModel`, `SharedPet`, etc. undefined).

- [ ] **Step 3: Write the managed object subclasses**

Create `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`:

```swift
import CoreData
import Foundation

@objc(SharedPet)
final class SharedPet: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String?
    @NSManaged var birthday: Date?
    @NSManaged var photoData: Data?
    @NSManaged var foodStockCount: Int64
    @NSManaged var feedingScheduleTimesRaw: String
    @NSManaged var isFasting: Bool
    @NSManaged var notificationsMuted: Bool
    @NSManaged var lastFeedingDate: Date?
    @NSManaged var todaysFeedingCount: Int64
    // sync bookkeeping (unused in Phase 1)
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var feedingEvents: NSSet?
    @NSManaged var medications: NSSet?
}

@objc(SharedFeedingEvent)
final class SharedFeedingEvent: NSManagedObject {
    @NSManaged var timestamp: Date
    @NSManaged var mealType: String?
    @NSManaged var notes: String
    @NSManaged var loggedBy: String?
    @NSManaged var didDeductStock: NSNumber?     // optional Bool
    @NSManaged var portionsDeducted: NSNumber?   // optional Int
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var pet: SharedPet?
}

@objc(SharedMedication)
final class SharedMedication: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var dose: String
    @NSManaged var frequencyHours: Int64
    @NSManaged var notificationsEnabled: Bool
    @NSManaged var reminderMinutesRaw: String
    @NSManaged var lastGivenDate: Date?
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var pet: SharedPet?
    @NSManaged var logs: NSSet?
}

@objc(SharedMedicationLog)
final class SharedMedicationLog: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date
    @NSManaged var notes: String
    @NSManaged var loggedBy: String
    @NSManaged var medicationName: String
    @NSManaged var petId: UUID?
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var medication: SharedMedication?
}
```

- [ ] **Step 4: Write the programmatic model builder**

Create `Did I Feed The Dog/Sharing/SharedDataModel.swift`:

```swift
import CoreData

/// Builds the Core Data model for the shared-dog store programmatically so there is
/// no .xcdatamodeld bundle to manage. Mirrors the SwiftData Pet/FeedingEvent/
/// Medication/MedicationLog graph and adds CloudKit sync bookkeeping fields used
/// by the Phase 2 custom sync engine.
enum SharedDataModel {

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let pet = entity("SharedPet", SharedPet.self)
        let event = entity("SharedFeedingEvent", SharedFeedingEvent.self)
        let med = entity("SharedMedication", SharedMedication.self)
        let log = entity("SharedMedicationLog", SharedMedicationLog.self)

        pet.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType, optional: true),
            attr("birthday", .dateAttributeType, optional: true),
            attr("photoData", .binaryDataAttributeType, optional: true),
            attr("foodStockCount", .integer64AttributeType, defaultValue: 0),
            attr("feedingScheduleTimesRaw", .stringAttributeType, defaultValue: ""),
            attr("isFasting", .booleanAttributeType, defaultValue: false),
            attr("notificationsMuted", .booleanAttributeType, defaultValue: false),
            attr("lastFeedingDate", .dateAttributeType, optional: true),
            attr("todaysFeedingCount", .integer64AttributeType, defaultValue: 0),
        ] + syncFields()

        event.properties = [
            attr("timestamp", .dateAttributeType),
            attr("mealType", .stringAttributeType, optional: true),
            attr("notes", .stringAttributeType, defaultValue: ""),
            attr("loggedBy", .stringAttributeType, optional: true),
            attr("didDeductStock", .booleanAttributeType, optional: true),
            attr("portionsDeducted", .integer64AttributeType, optional: true),
        ] + syncFields()

        med.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType, defaultValue: ""),
            attr("dose", .stringAttributeType, defaultValue: ""),
            attr("frequencyHours", .integer64AttributeType, defaultValue: 24),
            attr("notificationsEnabled", .booleanAttributeType, defaultValue: false),
            attr("reminderMinutesRaw", .stringAttributeType, defaultValue: ""),
            attr("lastGivenDate", .dateAttributeType, optional: true),
        ] + syncFields()

        log.properties = [
            attr("id", .UUIDAttributeType),
            attr("timestamp", .dateAttributeType),
            attr("notes", .stringAttributeType, defaultValue: ""),
            attr("loggedBy", .stringAttributeType, defaultValue: ""),
            attr("medicationName", .stringAttributeType, defaultValue: ""),
            attr("petId", .UUIDAttributeType, optional: true),
        ] + syncFields()

        // Pet 1—* FeedingEvent (cascade)
        relate(pet, "feedingEvents", to: event, toMany: true, delete: .cascadeDeleteRule,
               inverseName: "pet", inverse: &event, inverseToMany: false, inverseDelete: .nullifyDeleteRule)
        // Pet 1—* Medication (cascade)
        relate(pet, "medications", to: med, toMany: true, delete: .cascadeDeleteRule,
               inverseName: "pet", inverse: &med, inverseToMany: false, inverseDelete: .nullifyDeleteRule)
        // Medication 1—* MedicationLog (nullify)
        relate(med, "logs", to: log, toMany: true, delete: .nullifyDeleteRule,
               inverseName: "medication", inverse: &log, inverseToMany: false, inverseDelete: .nullifyDeleteRule)

        model.entities = [pet, event, med, log]
        return model
    }

    // MARK: helpers

    private static func entity(_ name: String, _ klass: AnyClass) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        e.managedObjectClassName = NSStringFromClass(klass)
        return e
    }

    private static func attr(_ name: String,
                             _ type: NSAttributeType,
                             optional: Bool = false,
                             defaultValue: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        if let defaultValue { a.defaultValue = defaultValue }
        return a
    }

    private static func syncFields() -> [NSAttributeDescription] {
        [
            attr("ckRecordName", .stringAttributeType, optional: true),
            attr("ckSystemFields", .binaryDataAttributeType, optional: true),
            attr("ckZoneName", .stringAttributeType, optional: true),
            attr("ckDatabaseScope", .integer16AttributeType, defaultValue: 0),
        ]
    }

    /// Wires a to-many relationship and its to-one inverse with delete rules.
    private static func relate(_ from: NSEntityDescription,
                               _ name: String,
                               to dest: NSEntityDescription,
                               toMany: Bool,
                               delete: NSDeleteRule,
                               inverseName: String,
                               inverse: inout NSEntityDescription,
                               inverseToMany: Bool,
                               inverseDelete: NSDeleteRule) {
        let forward = NSRelationshipDescription()
        forward.name = name
        forward.destinationEntity = dest
        forward.deleteRule = delete
        forward.minCount = 0
        forward.maxCount = toMany ? 0 : 1

        let back = NSRelationshipDescription()
        back.name = inverseName
        back.destinationEntity = from
        back.deleteRule = inverseDelete
        back.minCount = 0
        back.maxCount = inverseToMany ? 0 : 1

        forward.inverseRelationship = back
        back.inverseRelationship = forward

        from.properties += [forward]
        dest.properties += [back]
    }
}
```

> Note: `relate(...)` appends the inverse relationship onto `dest.properties`, so it must be called **after** each entity's scalar `properties` are assigned (as ordered above) and before `model.entities = [...]`. The `inout` parameter is unused mechanically but kept to signal the destination is mutated.

- [ ] **Step 5: Add all three files to their targets**

Add `SharedManagedObjects.swift` and `SharedDataModel.swift` to target **"Did I Feed The Dog"** (group `Did I Feed The Dog/Sharing`); add `SharedDataModelTests.swift` to target **"Did I Feed The DogTests"**. See "Adding new files to the Xcode target".

- [ ] **Step 6: Run tests to verify they pass**

Run with `-only-testing:"Did I Feed The DogTests/SharedDataModelTests"`. Expected: 3 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedDataModel.swift" "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The DogTests/SharedDataModelTests.swift" "Did I Feed The Dog.xcodeproj/project.pbxproj"
git commit -m "feat: add programmatic Core Data model for shared dogs (#57 phase 1)"
```

---

### Task 2.5: reminderMinutes string round-trip helper

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`
- Test: `Did I Feed The DogTests/SharedMedicationTests.swift`

**Interfaces:**
- Produces: `extension SharedMedication { var reminderMinutes: [Int] { get set } }` — mirrors SwiftData `Medication.reminderMinutes` (`[Int]` ↔ comma-joined string), so later phases and UI read it uniformly.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedMedicationTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedMedicationTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    func testReminderMinutesRoundTrip() throws {
        let m = SharedMedication(context: try ctx())
        m.reminderMinutes = [480, 1200]
        XCTAssertEqual(m.reminderMinutesRaw, "480,1200")
        XCTAssertEqual(m.reminderMinutes, [480, 1200])
    }

    func testReminderMinutesEmpty() throws {
        let m = SharedMedication(context: try ctx())
        m.reminderMinutes = []
        XCTAssertEqual(m.reminderMinutesRaw, "")
        XCTAssertEqual(m.reminderMinutes, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedMedicationTests"`. Expected: compile failure (`reminderMinutes` undefined).

- [ ] **Step 3: Add the computed property**

Append to `SharedManagedObjects.swift`:

```swift
extension SharedMedication {
    /// Mirrors SwiftData `Medication.reminderMinutes`: [Int] backed by a comma-joined string.
    var reminderMinutes: [Int] {
        get { reminderMinutesRaw.split(separator: ",").compactMap { Int($0) } }
        set { reminderMinutesRaw = newValue.map(String.init).joined(separator: ",") }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedMedicationTests"`. Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The DogTests/SharedMedicationTests.swift"
git commit -m "feat: reminderMinutes round-trip on SharedMedication (#57 phase 1)"
```

---

### Task 3: SharedDataStack (app-group Core Data container)

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharedDataStack.swift`
- Test: `Did I Feed The DogTests/SharedDataStackTests.swift`

**Interfaces:**
- Consumes: `SharedDataModel.makeModel()`, the `Shared*` classes.
- Produces:
  - `@Observable final class SharedDataStack` with: `static let shared: SharedDataStack`, `var viewContext: NSManagedObjectContext`, `private(set) var loadError: Error?`, `func newBackgroundContext() -> NSManagedObjectContext`, and `init(inMemory: Bool = false)` for tests.
  - The store file lives at the app-group container under `SharedDogs.sqlite`; history tracking + remote-change notifications enabled; never `fatalError`s.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedDataStackTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedDataStackTests: XCTestCase {

    func testInMemoryStackLoadsWithoutError() throws {
        let stack = SharedDataStack(inMemory: true)
        XCTAssertNil(stack.loadError)
        XCTAssertNotNil(stack.viewContext.persistentStoreCoordinator)
    }

    func testRoundTripInsertFetch() throws {
        let stack = SharedDataStack(inMemory: true)
        let pet = SharedPet(context: stack.viewContext)
        pet.id = UUID()
        pet.name = "Rex"
        try stack.viewContext.save()

        let req = NSFetchRequest<SharedPet>(entityName: "SharedPet")
        XCTAssertEqual(try stack.viewContext.fetch(req).first?.name, "Rex")
    }

    func testBackgroundContextSharesCoordinator() throws {
        let stack = SharedDataStack(inMemory: true)
        let bg = stack.newBackgroundContext()
        XCTAssertTrue(bg.persistentStoreCoordinator === stack.viewContext.persistentStoreCoordinator)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedDataStackTests"`. Expected: compile failure (`SharedDataStack` undefined).

- [ ] **Step 3: Implement the stack**

Create `Did I Feed The Dog/Sharing/SharedDataStack.swift`:

```swift
import CoreData
import Foundation
import os

/// Owns the Core Data container for shared dogs. Plain NSPersistentContainer (no
/// NSPersistentCloudKitContainer): the Phase 2 custom engine syncs this store to a
/// separate CloudKit container. Persistent history tracking is on so that engine can
/// detect local changes to push. Must never fatalError — a failure to open the shared
/// store must not break the app's private-data experience.
@Observable
final class SharedDataStack {

    static let shared = SharedDataStack()

    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedDataStack")
    private static let appGroupID = "group.com.delon.DidIFeedTheDog"
    private static let storeFileName = "SharedDogs.sqlite"

    private let container: NSPersistentContainer
    private(set) var loadError: Error?

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SharedDogs", managedObjectModel: SharedDataModel.makeModel())

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else if let url = Self.storeURL() {
            description = NSPersistentStoreDescription(url: url)
        } else {
            description = NSPersistentStoreDescription()
            Self.log.error("Could not resolve app-group store URL; using default location")
        }
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { [weak self] _, error in
            if let error {
                Self.log.error("Shared store failed to load: \(error.localizedDescription, privacy: .public)")
                self?.loadError = error
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    private static func storeURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(storeFileName)
    }
}
```

- [ ] **Step 4: Add files to targets**

Add `SharedDataStack.swift` → "Did I Feed The Dog" (`Did I Feed The Dog/Sharing`); `SharedDataStackTests.swift` → "Did I Feed The DogTests".

- [ ] **Step 5: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedDataStackTests"`. Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedDataStack.swift" "Did I Feed The DogTests/SharedDataStackTests.swift" "Did I Feed The Dog.xcodeproj/project.pbxproj"
git commit -m "feat: add SharedDataStack app-group Core Data container (#57 phase 1)"
```

---

### Task 4: DogDisplayable protocol + conformances + shared ageString

**Files:**
- Create: `Did I Feed The Dog/Sharing/DogDisplayable.swift`
- Modify: `Did I Feed The Dog/Models/Pet.swift:40-50` (refactor `ageString` to call shared helper)
- Test: `Did I Feed The DogTests/DogDisplayableTests.swift`

**Interfaces:**
- Consumes: `Pet` (SwiftData), `SharedPet` (Core Data).
- Produces:
  - `func dogAgeString(from birthday: Date?) -> String` — the single source of age formatting.
  - `protocol DogDisplayable: Identifiable` with: `id: UUID`, `displayName: String`, `photoData: Data?`, `birthday: Date?`, `isFasting: Bool`, `notificationsMuted: Bool`, `lastFeedingDate: Date?`, `todaysFeedingCount: Int`, `ageString: String`, `isShared: Bool`.
  - `extension Pet: DogDisplayable` (`isShared == false`) and `extension SharedPet: DogDisplayable` (`isShared == true`).

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/DogDisplayableTests.swift`:

```swift
import XCTest
import CoreData
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class DogDisplayableTests: XCTestCase {

    func testPetIsNotShared() throws {
        let pet = Pet(name: "Max")
        XCTAssertFalse(pet.isShared)
        XCTAssertEqual(pet.displayName, "Max")
    }

    func testPetDisplayNameFallback() throws {
        let pet = Pet(name: nil)
        XCTAssertEqual(pet.displayName, "Dog")
    }

    func testSharedPetIsShared() throws {
        let stack = SharedDataStack(inMemory: true)
        let sp = SharedPet(context: stack.viewContext)
        sp.id = UUID(); sp.name = "Rex"
        XCTAssertTrue(sp.isShared)
        XCTAssertEqual(sp.displayName, "Rex")
    }

    /// Guards against drift: same birthday must produce identical age text for both kinds.
    func testAgeStringParity() throws {
        let birthday = Calendar.current.date(byAdding: DateComponents(year: -2, month: -3), to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        let stack = SharedDataStack(inMemory: true)
        let sp = SharedPet(context: stack.viewContext)
        sp.id = UUID(); sp.birthday = birthday
        XCTAssertEqual(pet.ageString, sp.ageString)
        XCTAssertEqual(pet.ageString, "2 years, 3 months")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/DogDisplayableTests"`. Expected: compile failure (`isShared`, `displayName` undefined).

- [ ] **Step 3: Create the protocol, helper, and conformances**

Create `Did I Feed The Dog/Sharing/DogDisplayable.swift`:

```swift
import Foundation

/// Single source of truth for age formatting, shared by the SwiftData `Pet` and the
/// Core Data `SharedPet` so the two model layers can't drift.
func dogAgeString(from birthday: Date?) -> String {
    guard let birthday else { return "" }
    let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
    let years = components.year ?? 0
    let months = components.month ?? 0
    switch (years, months) {
    case (0, _):  return "Puppy"
    case (_, 0):  return "\(years) year\(years == 1 ? "" : "s")"
    default:      return "\(years) year\(years == 1 ? "" : "s"), \(months) month\(months == 1 ? "" : "s")"
    }
}

/// Read surface the dashboard/PetCard need, conformed by both owned (`Pet`) and
/// shared (`SharedPet`) dogs so they render through one path.
protocol DogDisplayable: Identifiable {
    var id: UUID { get }
    var displayName: String { get }
    var photoData: Data? { get }
    var birthday: Date? { get }
    var isFasting: Bool { get }
    var notificationsMuted: Bool { get }
    var lastFeedingDate: Date? { get }
    var todaysFeedingCount: Int { get }
    var ageString: String { get }
    var isShared: Bool { get }
}

extension Pet: DogDisplayable {
    var displayName: String { name ?? "Dog" }
    var isShared: Bool { false }
    // `id`, `photoData`, `birthday`, `isFasting`, `notificationsMuted`,
    // `lastFeedingDate`, `ageString` already exist on Pet.
    // `todaysFeedingCount` is stored as Int already.
}

extension SharedPet: DogDisplayable {
    var displayName: String { name ?? "Dog" }
    var isShared: Bool { true }
    var todaysFeedingCount: Int { Int(todaysFeedingCountRaw) }
    var ageString: String { dogAgeString(from: birthday) }
}
```

> `SharedPet.todaysFeedingCount` is stored as `Int64` (`todaysFeedingCount` `@NSManaged`). To satisfy the protocol's `Int` without name clash, rename the stored `@NSManaged` to `todaysFeedingCountRaw` in `SharedManagedObjects.swift` **and** in the model builder attribute name. Apply that rename now: in `SharedDataModel.swift` change the attribute name `"todaysFeedingCount"` → `"todaysFeedingCountRaw"`; in `SharedManagedObjects.swift` rename the `@NSManaged var todaysFeedingCount: Int64` to `todaysFeedingCountRaw`. Do the same pattern for `foodStockCount` only if a protocol clash arises — it does not here, so leave `foodStockCount` as is.

- [ ] **Step 4: Refactor Pet.ageString to use the shared helper**

In `Did I Feed The Dog/Models/Pet.swift`, replace the body of `ageString` (lines ~40–50) with a call to the helper, preserving behavior:

```swift
    var ageString: String { dogAgeString(from: birthday) }
```

- [ ] **Step 5: Add file to target**

Add `DogDisplayable.swift` → "Did I Feed The Dog" (`Did I Feed The Dog/Sharing`); `DogDisplayableTests.swift` → "Did I Feed The DogTests".

- [ ] **Step 6: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/DogDisplayableTests"`. Expected: 4 tests PASS.
Then run the existing `PetTests` to confirm the `ageString` refactor preserved behavior:
`-only-testing:"Did I Feed The DogTests/PetTests"`. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Sharing/DogDisplayable.swift" "Did I Feed The Dog/Sharing/SharedDataModel.swift" "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The Dog/Models/Pet.swift" "Did I Feed The DogTests/DogDisplayableTests.swift" "Did I Feed The Dog.xcodeproj/project.pbxproj"
git commit -m "feat: DogDisplayable seam over Pet and SharedPet (#57 phase 1)"
```

---

### Task 5: SharedDogStore (fetch, observe, DEBUG seed)

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharedDogStore.swift`
- Test: `Did I Feed The DogTests/SharedDogStoreTests.swift`

**Interfaces:**
- Consumes: `SharedDataStack`, `SharedPet`.
- Produces:
  - `@Observable @MainActor final class SharedDogStore` with: `init(stack: SharedDataStack = .shared)`, `private(set) var sharedPets: [SharedPet]`, `func refresh()` (fetch all `SharedPet` sorted by `name`), `func startObserving()` (refresh on `.NSManagedObjectContextDidSave` / remote-change), and `#if DEBUG func insertSampleDog(named: String)`.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedDogStoreTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedDogStoreTests: XCTestCase {

    func testRefreshReturnsInsertedDogsSortedByName() throws {
        let stack = SharedDataStack(inMemory: true)
        let store = SharedDogStore(stack: stack)

        for name in ["Zoe", "Apple"] {
            let p = SharedPet(context: stack.viewContext)
            p.id = UUID(); p.name = name
        }
        try stack.viewContext.save()

        store.refresh()
        XCTAssertEqual(store.sharedPets.map(\.name), ["Apple", "Zoe"])
    }

    func testEmptyStoreRefreshesToEmpty() throws {
        let stack = SharedDataStack(inMemory: true)
        let store = SharedDogStore(stack: stack)
        store.refresh()
        XCTAssertTrue(store.sharedPets.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedDogStoreTests"`. Expected: compile failure (`SharedDogStore` undefined).

- [ ] **Step 3: Implement the store**

Create `Did I Feed The Dog/Sharing/SharedDogStore.swift`:

```swift
import CoreData
import Foundation

/// Fetches and observes shared dogs for the dashboard. Read-only surface in Phase 1
/// (no logging into shared dogs yet). On store-load failure it simply yields no dogs.
@Observable
@MainActor
final class SharedDogStore {

    private let stack: SharedDataStack
    private var observer: NSObjectProtocol?
    private(set) var sharedPets: [SharedPet] = []

    init(stack: SharedDataStack = .shared) {
        self.stack = stack
    }

    func refresh() {
        guard stack.loadError == nil else { sharedPets = []; return }
        let req = NSFetchRequest<SharedPet>(entityName: "SharedPet")
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        sharedPets = (try? stack.viewContext.fetch(req)) ?? []
    }

    func startObserving() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: stack.viewContext,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    #if DEBUG
    /// Inserts a fake shared dog so the foundation can be validated without CloudKit.
    func insertSampleDog(named name: String) {
        let p = SharedPet(context: stack.viewContext)
        p.id = UUID()
        p.name = name
        p.ckDatabaseScope = 1 // pretend it's a participant store record
        try? stack.viewContext.save()
        refresh()
    }
    #endif
}
```

- [ ] **Step 4: Add files to targets**

Add `SharedDogStore.swift` → "Did I Feed The Dog" (`Did I Feed The Dog/Sharing`); `SharedDogStoreTests.swift` → "Did I Feed The DogTests".

- [ ] **Step 5: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedDogStoreTests"`. Expected: 2 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedDogStore.swift" "Did I Feed The DogTests/SharedDogStoreTests.swift" "Did I Feed The Dog.xcodeproj/project.pbxproj"
git commit -m "feat: SharedDogStore fetch/observe + DEBUG seed (#57 phase 1)"
```

---

### Task 6: Feature flag + PetCard display generalization

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharingFeatureFlag.swift`
- Modify: `Did I Feed The Dog/Views/PetCard.swift`

**Interfaces:**
- Consumes: `DogDisplayable`.
- Produces:
  - `enum SharingFeatureFlag { static var isFoundationEnabled: Bool }` reading `UserDefaults.sharedGroup` key `"sharingFoundationEnabled"` (default false).
  - `PetCard` renders a shared dog read-only: when the bound dog `isShared`, the Log Meal / stock +/- / quick-toggle controls are hidden or disabled, and a small `person.2.fill` marker is shown. Owned-dog rendering and actions are unchanged.

**Note on PetCard:** `PetCard` currently takes a SwiftData `Pet` and performs logging actions on it. Phase 1 keeps that typed `Pet` action path intact. Generalize only the **display** by adding an internal helper that reads from `any DogDisplayable`, and add an `isShared` guard around the action controls. Do **not** route shared-dog logging anywhere this phase.

- [ ] **Step 1: Create the feature flag**

Create `Did I Feed The Dog/Sharing/SharingFeatureFlag.swift`:

```swift
import Foundation

enum SharingFeatureFlag {
    /// Phase 1 foundation: render shared dogs on the dashboard. Default off in release.
    static var isFoundationEnabled: Bool {
        UserDefaults.sharedGroup.bool(forKey: "sharingFoundationEnabled")
    }
}
```

- [ ] **Step 2: Add a shared marker + read-only guard to PetCard**

Open `Did I Feed The Dog/Views/PetCard.swift`. Add a `person.2.fill` badge in the card header when the displayed dog is shared, and wrap the action controls (Log Meal button, stock steppers, long-press quick-toggle) so they are disabled/hidden for a shared dog. Use the dog's `isShared`. (Exact insertion points depend on the current card layout; the rule: any control that *writes* to the dog is gated behind `!isShared`; everything that *reads* renders unchanged.)

Concretely, near the card's name/title row add:

```swift
if dog.isShared {
    Image(systemName: "person.2.fill")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Shared dog")
}
```

and gate each writing control, e.g.:

```swift
if !dog.isShared {
    // existing Log Meal button / steppers / context menu
}
```

where `dog` is the card's displayed value conforming to `DogDisplayable` (for the existing owned-dog path this is the `Pet`).

- [ ] **Step 3: Add files to target**

Add `SharingFeatureFlag.swift` → "Did I Feed The Dog" (`Did I Feed The Dog/Sharing`).

- [ ] **Step 4: Compile check**

Run the full app build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharingFeatureFlag.swift" "Did I Feed The Dog/Views/PetCard.swift" "Did I Feed The Dog.xcodeproj/project.pbxproj"
git commit -m "feat: shared-dog read-only marker on PetCard + feature flag (#57 phase 1)"
```

---

### Task 7: Dashboard merge + DEBUG validation affordance

**Files:**
- Modify: `Did I Feed The Dog/Views/DashboardView.swift`
- Modify: `Did I Feed The Dog/Views/SettingsView.swift` (DEBUG-only seed row)

**Interfaces:**
- Consumes: `SharedDogStore`, `SharingFeatureFlag`, `DogDisplayable`.
- Produces: dashboard renders owned + shared dogs in one grid when the flag is on; a DEBUG-only Settings control seeds/clears a sample shared dog.

- [ ] **Step 1: Add the SharedDogStore to DashboardView**

In `DashboardView`, add state and lifecycle wiring (alongside the existing `@Query(sort: \Pet.name) private var pets`):

```swift
@State private var sharedDogStore = SharedDogStore()
```

In the `NavigationStack`'s `.task` / `.onAppear` (add one if absent):

```swift
.task {
    if SharingFeatureFlag.isFoundationEnabled {
        sharedDogStore.startObserving()
    }
}
```

- [ ] **Step 2: Merge owned + shared dogs for the grid**

Add a computed property that produces the merged, name-sorted list and update the grid's `ForEach`:

```swift
private var displayedDogs: [any DogDisplayable] {
    let owned: [any DogDisplayable] = pets
    let shared: [any DogDisplayable] = SharingFeatureFlag.isFoundationEnabled ? sharedDogStore.sharedPets : []
    return (owned + shared).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
}
```

Update the grid. The existing `PetCard(pet:)` needs a `Pet`; for shared dogs render a read-only card variant. Keep owned dogs on the existing typed path:

```swift
ForEach(displayedDogs, id: \.id) { dog in
    if let pet = dog as? Pet {
        PetCard(pet: pet, undoVersion: undoVersion, onFed: { _, undo in
            triggerToast(message: "Meal logged", undo: undo)
        })
    } else {
        SharedPetCard(dog: dog) // read-only card; see Step 3
    }
}
```

- [ ] **Step 3: Add a minimal read-only SharedPetCard**

Rather than refactor the full `PetCard`, add a small read-only card for shared dogs (Phase 1 only; later phases fold this back in). Create it inline in `DashboardView.swift` or a new file `Did I Feed The Dog/Views/SharedPetCard.swift`:

```swift
import SwiftUI

/// Read-only dashboard card for a dog shared with the user (Phase 1 foundation).
/// Logging into shared dogs arrives with the Phase 2 sync engine.
struct SharedPetCard: View {
    let dog: any DogDisplayable

    var body: some View {
        HStack(spacing: 12) {
            // Reuse the app's avatar rendering if a shared helper exists; else a placeholder.
            Image(systemName: "pawprint.circle.fill")
                .resizable().frame(width: 44, height: 44)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(dog.displayName).font(.headline)
                    Image(systemName: "person.2.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Shared dog")
                }
                if let last = dog.lastFeedingDate {
                    Text("Last fed \(last.formatted(.relative(presentation: .named)))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("No meals yet").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

If you create the file, add it to the "Did I Feed The Dog" target.

- [ ] **Step 4: Add a DEBUG seed/clear row in SettingsView**

In `SettingsView`, inside a `#if DEBUG` block, add a section that toggles the flag and seeds/clears a sample shared dog (use `@State private var debugSharedStore = SharedDogStore()` or reuse a shared instance):

```swift
#if DEBUG
Section("Sharing Foundation (DEBUG)") {
    Toggle("Render shared dogs", isOn: Binding(
        get: { UserDefaults.sharedGroup.bool(forKey: "sharingFoundationEnabled") },
        set: { UserDefaults.sharedGroup.set($0, forKey: "sharingFoundationEnabled") }
    ))
    Button("Insert sample shared dog") {
        SharedDogStore().insertSampleDog(named: "Sample Shared Dog")
    }
}
#endif
```

- [ ] **Step 5: Compile check + run full test suite**

Run the full app build, then the whole test target:

```bash
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED and all tests PASS.

- [ ] **Step 6: Manual validation (DEBUG)**

Run the app in the simulator. In Settings ▸ Sharing Foundation (DEBUG): toggle "Render shared dogs" ON, tap "Insert sample shared dog". Return to dashboard → "Sample Shared Dog" appears with the `person.2` marker and "No meals yet". Force-quit and relaunch → it persists. Toggle the flag OFF → it disappears; owned dogs unaffected.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Views/DashboardView.swift" "Did I Feed The Dog/Views/SettingsView.swift" "Did I Feed The Dog/Views/SharedPetCard.swift" "Did I Feed The Dog.xcodeproj/project.pbxproj"
git commit -m "feat: render shared dogs on dashboard behind flag + DEBUG seed (#57 phase 1)"
```

---

### Task 8: Final verification

- [ ] **Step 1: Build both targets**

Run the full app build **and** the widget build command. Expected: both BUILD SUCCEEDED (widget entitlement untouched).

- [ ] **Step 2: Run the entire test suite**

```bash
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

Expected: all tests PASS (new `SharedDataModelTests`, `SharedMedicationTests`, `SharedDataStackTests`, `DogDisplayableTests`, `SharedDogStoreTests` + all pre-existing).

- [ ] **Step 3: Confirm release-default behavior**

With the flag OFF (release default), confirm the dashboard shows only owned dogs and behaves identically to before. The shared store loads empty and silently.

- [ ] **Step 4: Update the spec status**

In `docs/superpowers/specs/2026-06-22-family-sharing-foundation-design.md`, change the status line to `Status: Phase 1 implemented` and commit:

```bash
git add docs/superpowers/specs/2026-06-22-family-sharing-foundation-design.md
git commit -m "docs: mark family sharing Phase 1 foundation implemented (#57)"
```

---

## Self-Review

**Spec coverage:**
- Separate CloudKit container in entitlements → Task 1. ✓
- Core Data model mirroring 4 entities + sync bookkeeping → Task 2 (+ reminderMinutes Task 2.5). ✓ (refined to programmatic model — noted in Global Constraints).
- `SharedDataStack` (app group, history tracking, no fatalError) → Task 3. ✓
- `DogDisplayable` protocol + both conformances + shared ageString (no drift) → Task 4. ✓
- `SharedDogStore` fetch/observe + DEBUG seed → Task 5. ✓
- Feature flag + dashboard merge + shared marker + read-only shared cards → Tasks 6–7. ✓
- DEBUG validation harness + persistence check → Task 7. ✓
- Error handling (no fatalError, degrade to owned-only) → Task 3 + Task 5 `refresh()` guard. ✓
- Testing (parity, round-trips, stack load, regression, both targets build) → Tasks 2–8. ✓
- Out-of-scope items (CloudKit traffic, logging into shared dogs, migration, PetDetail/intents/widgets, attribution) → not implemented, as required. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. The one layout-dependent step (Task 6 Step 2, PetCard insertion points) gives an explicit rule and concrete snippets because the exact lines depend on current card markup.

**Type consistency:** `SharedPet.todaysFeedingCountRaw` (Int64 stored) vs `todaysFeedingCount: Int` (protocol) reconciled by the rename note in Task 4 Step 3, applied to both the model builder and the subclass. `dogAgeString(from:)` used by both `Pet.ageString` (Task 4 Step 4) and `SharedPet.ageString` (Task 4 Step 3). `SharedDogStore.sharedPets: [SharedPet]` consumed by Dashboard Task 7. `SharingFeatureFlag.isFoundationEnabled` used in Tasks 6–7. Names consistent across tasks.
