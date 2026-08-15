# Family Sharing — Phase 5 Migration + Share Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clone an owned SwiftData `Pet` into the shared Core Data store the first time a user shares a dog (and clone back on stop-sharing), and replace the DEBUG-only Share/Stop-sharing controls with the real, Pro-gated, owner-gated entry points.

**Architecture:** A new `SharePreparationController` (Core Data/SwiftData clone in both directions) sits between the existing SwiftData `Pet` graph and the existing Phase 1-4 shared-store/sync machinery, which is otherwise untouched — migration only needs to *save* new objects with a stamped `ckRecordName`; the already-existing push observer, `ensureZone`, and `push` take it from there. A new `SharedSyncEngine.isOwner(ofZoneNamed:)` exposes an already-computed ownership signal for UI gating. `PetCard` and `SharedPetCard` get real Share/Stop-sharing entry points wired to these plus the existing `ShareController`.

**Tech Stack:** Swift, SwiftData, Core Data, CloudKit (`CKShare`), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-15-family-sharing-migration-share-button-design.md`

## Global Constraints

- **Migration replaces, not duplicates.** `migrateToShared` clones the full graph then the caller deletes the source `Pet`. `migrateToOwned` is the mirror for stop-sharing.
- **Identity preserved.** The cloned object reuses the source's `id` in both directions.
- **New shared objects must get a stamped `ckRecordName` before the shared context saves** — `SharedSyncEngine`'s push observer (`Did I Feed The Dog/Sharing/SharedSyncEngine.swift:45-72`) only forwards objects whose `ckRecordName` is already set at save time. No manual `ensureZone`/`push` call is needed otherwise; the observer + existing `push()` (which already ensures a zone for any root with `ckSystemFields == nil`) handle it automatically.
- **Ownership gating for the UI:** a private-scope zone token existing for a zone name is the same signal `database(forZone:)` already uses internally (`Did I Feed The Dog/Sharing/SharedSyncEngine.swift:96-102`) — Phase 5 exposes it via `SharedSyncEngine.isOwner(ofZoneNamed:)`, doesn't reinvent it.
- **Seeding-window fix (new for this phase):** a private-scope token for a brand-new zone is only written once a `fetchAllZones()` pull cycle completes for it — not at `ensureZone`/`makeShare` time. The owner's own "Share"/"Stop sharing" controls would be briefly invisible on their own freshly-shared dog without an explicit `await SharedSyncEngine.shared.fetchAllZones()` call right after `makeShare` succeeds. Task 3 includes this call for exactly that reason.
- **`CKServerChangeToken` has no public initializer** — it cannot be constructed in a unit test. Task 2's test therefore only covers the deterministic "no token → not owner" branch; the "has token → owner" branch is verified by the Phase 5 manual checklist (spec, Testing section), matching how this codebase already tests `SyncTokenStore` (see `Did I Feed The DogTests/SyncTokenStoreDBScopeTests.swift`, which only covers nil/corrupt paths for the same reason).
- **Flag-gated:** `SharingFeatureFlag.isFoundationEnabled` — unchanged this phase. `SharedPetCard` only ever renders when the flag is on (guarded upstream in `DashboardView`), so no redundant flag check is needed in its own logic, but one is kept for defense-in-depth consistent with the DEBUG code it replaces.
- **Never `fatalError`.** Log via `os.Logger(subsystem: "com.delon.DidIFeedTheDog", category: ...)`. Surface user-facing failures as a simple alert with `error.localizedDescription`.

### Environment / mechanics (every task)

- New files → `Did I Feed The Dog/Sharing/` (target "Did I Feed The Dog"); tests → `Did I Feed The DogTests/` (target "Did I Feed The DogTests"). Xcode 16 filesystem-synchronized groups — **no `project.pbxproj` edits**.
- **Swift 6 `-default-isolation=MainActor` strict concurrency is enforced.** Mark any `static let`/`static func` accessed from a `nonisolated` context `nonisolated`. `SharePreparationController` and `SharedSyncEngine` stay `@MainActor` (implicit under the project's default-isolation flag; `ShareController`/`CloudKitIdentity` mark it explicitly — follow that convention).
- **Single simulator (limited RAM — never spawn parallel clones).** Test:
  ```
  xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:"Did I Feed The DogTests/<ClassName>" 2>&1 | tail -40
  ```
  Build:
  ```
  xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
  ```
- **Known-flaky baseline:** two slow `FeedingLogServiceTests` (~100s, timeout-prone), a stale `PetTests.testAgeStringMonthsOnly`. Judge success by new tests passing + no NEW failures in touched files.
- Verify exact SwiftData/Core Data API shapes against the SDK (use the LSP tool) if the compiler disagrees with a signature below; adapt labels minimally, keeping behavior, and note it.

---

### Task 1: SharePreparationController — migrateToShared / migrateToOwned

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharePreparationController.swift`
- Test: `Did I Feed The DogTests/SharePreparationControllerTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor enum SharePreparationController`
  - `static func migrateToShared(pet: Pet, sharedContext: NSManagedObjectContext = SharedDataStack.shared.viewContext) throws -> SharedPet`
  - `static func migrateToOwned(sharedPet: SharedPet, modelContext: ModelContext) throws -> Pet`
- Consumes: `Pet`, `FeedingEvent`, `Medication`, `MedicationLog` (`Did I Feed The Dog/Models/`); `SharedPet`, `SharedFeedingEvent`, `SharedMedication`, `SharedMedicationLog` (`Did I Feed The Dog/Sharing/SharedManagedObjects.swift`); `SharedDataStack.shared.viewContext` (`Did I Feed The Dog/Sharing/SharedDataStack.swift`).

- [ ] **Step 1: Write the failing tests**

Create `Did I Feed The DogTests/SharePreparationControllerTests.swift`:

```swift
import XCTest
import SwiftData
import CoreData
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharePreparationControllerTests: XCTestCase {

    private func swiftDataContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Pet.self, FeedingEvent.self, Medication.self, MedicationLog.self,
                                           configurations: config)
        return ModelContext(container)
    }

    private func sharedContext() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let container = NSPersistentContainer(name: "T", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadErr: Error?
        container.loadPersistentStores { _, e in loadErr = e }
        if let loadErr { throw loadErr }
        return container.viewContext
    }

    private func readOnlySharedContext() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let container = NSPersistentContainer(name: "T", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        container.persistentStoreDescriptions = [description]
        var loadErr: Error?
        container.loadPersistentStores { _, e in loadErr = e }
        if let loadErr { throw loadErr }
        return container.viewContext
    }

    @discardableResult
    private func makeFullPet(in context: ModelContext) -> Pet {
        let pet = Pet(name: "Max", birthday: Date(timeIntervalSince1970: 0), foodStockCount: 12)
        pet.feedingScheduleTimesRaw = "480,1200"
        pet.isFasting = true
        pet.notificationsMuted = true
        pet.lastFeedingDate = Date(timeIntervalSince1970: 1000)
        pet.todaysFeedingCount = 2
        context.insert(pet)

        let event = FeedingEvent(timestamp: Date(timeIntervalSince1970: 2000), mealType: "Breakfast",
                                 notes: "half portion", loggedBy: "Alex", pet: pet, didDeductStock: true)
        event.portionsDeducted = 1
        context.insert(event)

        let medication = Medication(name: "Heartgard", dose: "1 tab", frequencyHours: 720, notificationsEnabled: true)
        medication.reminderMinutes = [540, 1080]
        medication.lastGivenDate = Date(timeIntervalSince1970: 3000)
        medication.pet = pet
        context.insert(medication)

        let log = MedicationLog(timestamp: Date(timeIntervalSince1970: 4000), notes: "given with food",
                                loggedBy: "Alex", medication: medication)
        context.insert(log)

        try? context.save()
        return pet
    }

    func testMigrateToSharedClonesFullGraph() throws {
        let swiftData = try swiftDataContext()
        let shared = try sharedContext()
        let pet = makeFullPet(in: swiftData)
        let originalId = pet.id

        let sharedPet = try SharePreparationController.migrateToShared(pet: pet, sharedContext: shared)

        XCTAssertEqual(sharedPet.id, originalId)
        XCTAssertEqual(sharedPet.name, "Max")
        XCTAssertEqual(sharedPet.birthday, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(sharedPet.foodStockCount, 12)
        XCTAssertEqual(sharedPet.feedingScheduleTimesRaw, "480,1200")
        XCTAssertTrue(sharedPet.isFasting)
        XCTAssertTrue(sharedPet.notificationsMuted)
        XCTAssertEqual(sharedPet.lastFeedingDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(sharedPet.todaysFeedingCountRaw, 2)
        XCTAssertNotNil(sharedPet.ckRecordName)

        let events = (sharedPet.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        XCTAssertEqual(events.count, 1)
        let sharedEvent = try XCTUnwrap(events.first)
        XCTAssertEqual(sharedEvent.timestamp, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(sharedEvent.mealType, "Breakfast")
        XCTAssertEqual(sharedEvent.notes, "half portion")
        XCTAssertEqual(sharedEvent.loggedBy, "Alex")
        XCTAssertEqual(sharedEvent.didDeductStock?.boolValue, true)
        XCTAssertEqual(sharedEvent.portionsDeducted?.intValue, 1)
        XCTAssertNotNil(sharedEvent.ckRecordName)
        XCTAssertEqual(sharedEvent.pet, sharedPet)

        let meds = (sharedPet.medications as? Set<SharedMedication>) ?? []
        XCTAssertEqual(meds.count, 1)
        let sharedMed = try XCTUnwrap(meds.first)
        XCTAssertEqual(sharedMed.name, "Heartgard")
        XCTAssertEqual(sharedMed.dose, "1 tab")
        XCTAssertEqual(sharedMed.frequencyHours, 720)
        XCTAssertTrue(sharedMed.notificationsEnabled)
        XCTAssertEqual(sharedMed.reminderMinutes, [540, 1080])
        XCTAssertEqual(sharedMed.lastGivenDate, Date(timeIntervalSince1970: 3000))
        XCTAssertNotNil(sharedMed.ckRecordName)

        let logs = (sharedMed.logs as? Set<SharedMedicationLog>) ?? []
        XCTAssertEqual(logs.count, 1)
        let sharedLog = try XCTUnwrap(logs.first)
        XCTAssertEqual(sharedLog.timestamp, Date(timeIntervalSince1970: 4000))
        XCTAssertEqual(sharedLog.notes, "given with food")
        XCTAssertEqual(sharedLog.loggedBy, "Alex")
        XCTAssertNotNil(sharedLog.ckRecordName)
        XCTAssertEqual(sharedLog.medication, sharedMed)
    }

    func testMigrateToSharedRollsBackOnSaveFailure() throws {
        let swiftData = try swiftDataContext()
        let readOnly = try readOnlySharedContext()
        let pet = makeFullPet(in: swiftData)

        XCTAssertThrowsError(try SharePreparationController.migrateToShared(pet: pet, sharedContext: readOnly))

        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "SharedPet")
        XCTAssertEqual(try readOnly.count(for: fetch), 0)
    }

    func testMigrateToOwnedClonesFullGraphBack() throws {
        let shared = try sharedContext()
        let swiftData = try swiftDataContext()

        let sharedPet = SharedPet(context: shared)
        let originalId = UUID()
        sharedPet.id = originalId
        sharedPet.name = "Bella"
        sharedPet.birthday = Date(timeIntervalSince1970: 500)
        sharedPet.foodStockCount = 7
        sharedPet.feedingScheduleTimesRaw = "600"
        sharedPet.isFasting = false
        sharedPet.notificationsMuted = false
        sharedPet.lastFeedingDate = Date(timeIntervalSince1970: 1500)
        sharedPet.todaysFeedingCountRaw = 3

        let sharedEvent = SharedFeedingEvent(context: shared)
        sharedEvent.timestamp = Date(timeIntervalSince1970: 2500)
        sharedEvent.mealType = "Dinner"
        sharedEvent.notes = "extra treat"
        sharedEvent.loggedBy = "Sam"
        sharedEvent.didDeductStock = NSNumber(value: true)
        sharedEvent.portionsDeducted = NSNumber(value: 1)
        sharedEvent.pet = sharedPet

        let sharedMed = SharedMedication(context: shared)
        sharedMed.id = UUID()
        sharedMed.name = "Apoquel"
        sharedMed.dose = "half tab"
        sharedMed.frequencyHours = 24
        sharedMed.notificationsEnabled = false
        sharedMed.reminderMinutes = [420]
        sharedMed.lastGivenDate = Date(timeIntervalSince1970: 3500)
        sharedMed.pet = sharedPet

        let sharedLog = SharedMedicationLog(context: shared)
        sharedLog.id = UUID()
        sharedLog.timestamp = Date(timeIntervalSince1970: 4500)
        sharedLog.notes = "on time"
        sharedLog.loggedBy = "Sam"
        sharedLog.medicationName = "Apoquel"
        sharedLog.medication = sharedMed

        try shared.save()

        let pet = try SharePreparationController.migrateToOwned(sharedPet: sharedPet, modelContext: swiftData)

        XCTAssertEqual(pet.id, originalId)
        XCTAssertEqual(pet.name, "Bella")
        XCTAssertEqual(pet.birthday, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(pet.foodStockCount, 7)
        XCTAssertEqual(pet.feedingScheduleTimesRaw, "600")
        XCTAssertFalse(pet.isFasting)
        XCTAssertFalse(pet.notificationsMuted)
        XCTAssertEqual(pet.lastFeedingDate, Date(timeIntervalSince1970: 1500))
        XCTAssertEqual(pet.todaysFeedingCount, 3)

        let events = pet.feedingEvents ?? []
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 2500))
        XCTAssertEqual(event.mealType, "Dinner")
        XCTAssertEqual(event.notes, "extra treat")
        XCTAssertEqual(event.loggedBy, "Sam")
        XCTAssertEqual(event.didDeductStock, true)
        XCTAssertEqual(event.portionsDeducted, 1)

        let meds = pet.medications ?? []
        XCTAssertEqual(meds.count, 1)
        let medication = try XCTUnwrap(meds.first)
        XCTAssertEqual(medication.name, "Apoquel")
        XCTAssertEqual(medication.dose, "half tab")
        XCTAssertEqual(medication.frequencyHours, 24)
        XCTAssertFalse(medication.notificationsEnabled)
        XCTAssertEqual(medication.reminderMinutes, [420])
        XCTAssertEqual(medication.lastGivenDate, Date(timeIntervalSince1970: 3500))

        let logs = medication.logs ?? []
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.notes, "on time")
        XCTAssertEqual(log.loggedBy, "Sam")
        XCTAssertEqual(log.medicationName, "Apoquel")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run `-only-testing:"Did I Feed The DogTests/SharePreparationControllerTests"`. Expected: compile failure (`SharePreparationController` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/SharePreparationController.swift`:

```swift
import CoreData
import Foundation
import SwiftData

/// Clones a dog's full data graph between the owned SwiftData store and the shared Core Data
/// store. `migrateToShared` runs the first time a dog is shared: the caller deletes the source
/// `Pet` only after this succeeds. `migrateToOwned` is the mirror, run when the owner stops
/// sharing, so they never lose data by unsharing.
@MainActor
enum SharePreparationController {

    /// Clones `pet` (and its feeding events, medications, medication logs) into a new
    /// `SharedPet` on `sharedContext`, reusing `pet.id` so the CloudKit zone name
    /// (`"Zone-\(id)"`) stays stable. Every new shared object gets a fresh `ckRecordName`
    /// stamped BEFORE save, since `SharedSyncEngine`'s push observer only picks up objects
    /// that already have one at save time. On save failure, rolls back and rethrows —
    /// the source `Pet` is never touched here.
    static func migrateToShared(
        pet: Pet,
        sharedContext: NSManagedObjectContext = SharedDataStack.shared.viewContext
    ) throws -> SharedPet {
        let sharedPet = SharedPet(context: sharedContext)
        sharedPet.id = pet.id
        sharedPet.name = pet.name
        sharedPet.birthday = pet.birthday
        sharedPet.photoData = pet.photoData
        sharedPet.foodStockCount = Int64(pet.foodStockCount)
        sharedPet.feedingScheduleTimesRaw = pet.feedingScheduleTimesRaw
        sharedPet.isFasting = pet.isFasting
        sharedPet.notificationsMuted = pet.notificationsMuted
        sharedPet.lastFeedingDate = pet.lastFeedingDate
        sharedPet.todaysFeedingCountRaw = Int64(pet.todaysFeedingCount)
        sharedPet.ckRecordName = UUID().uuidString

        for event in pet.feedingEvents ?? [] {
            let sharedEvent = SharedFeedingEvent(context: sharedContext)
            sharedEvent.timestamp = event.timestamp
            sharedEvent.mealType = event.mealType
            sharedEvent.notes = event.notes
            sharedEvent.loggedBy = event.loggedBy
            sharedEvent.didDeductStock = event.didDeductStock.map { NSNumber(value: $0) }
            sharedEvent.portionsDeducted = event.portionsDeducted.map { NSNumber(value: $0) }
            sharedEvent.ckRecordName = UUID().uuidString
            sharedEvent.pet = sharedPet
        }

        for medication in pet.medications ?? [] {
            let sharedMed = SharedMedication(context: sharedContext)
            sharedMed.id = medication.id
            sharedMed.name = medication.name
            sharedMed.dose = medication.dose
            sharedMed.frequencyHours = Int64(medication.frequencyHours)
            sharedMed.notificationsEnabled = medication.notificationsEnabled
            sharedMed.reminderMinutes = medication.reminderMinutes
            sharedMed.lastGivenDate = medication.lastGivenDate
            sharedMed.ckRecordName = UUID().uuidString
            sharedMed.pet = sharedPet

            for log in medication.logs ?? [] {
                let sharedLog = SharedMedicationLog(context: sharedContext)
                sharedLog.id = log.id
                sharedLog.timestamp = log.timestamp
                sharedLog.notes = log.notes
                sharedLog.loggedBy = log.loggedBy
                sharedLog.medicationName = log.medicationName
                sharedLog.petId = log.petId
                sharedLog.ckRecordName = UUID().uuidString
                sharedLog.medication = sharedMed
            }
        }

        do {
            try sharedContext.save()
        } catch {
            sharedContext.rollback()
            throw error
        }
        return sharedPet
    }

    /// Clones `sharedPet` back into a new owned `Pet` on `modelContext`, reusing `sharedPet.id`.
    /// Caller proceeds to `ShareController.stopSharing` only after this succeeds, so a failed
    /// reverse migration never destroys the shared copy.
    static func migrateToOwned(sharedPet: SharedPet, modelContext: ModelContext) throws -> Pet {
        let pet = Pet(name: sharedPet.name)
        pet.id = sharedPet.id
        pet.birthday = sharedPet.birthday
        pet.photoData = sharedPet.photoData
        pet.foodStockCount = Int(sharedPet.foodStockCount)
        pet.feedingScheduleTimesRaw = sharedPet.feedingScheduleTimesRaw
        pet.isFasting = sharedPet.isFasting
        pet.notificationsMuted = sharedPet.notificationsMuted
        pet.lastFeedingDate = sharedPet.lastFeedingDate
        pet.todaysFeedingCount = Int(sharedPet.todaysFeedingCountRaw)
        modelContext.insert(pet)

        let sharedEvents = (sharedPet.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        for sharedEvent in sharedEvents {
            let event = FeedingEvent(
                timestamp: sharedEvent.timestamp,
                mealType: sharedEvent.mealType,
                notes: sharedEvent.notes,
                loggedBy: sharedEvent.loggedBy,
                pet: pet,
                didDeductStock: sharedEvent.didDeductStock?.boolValue
            )
            event.portionsDeducted = sharedEvent.portionsDeducted?.intValue
            modelContext.insert(event)
        }

        let sharedMeds = (sharedPet.medications as? Set<SharedMedication>) ?? []
        for sharedMed in sharedMeds {
            let medication = Medication(
                name: sharedMed.name,
                dose: sharedMed.dose,
                frequencyHours: Int(sharedMed.frequencyHours),
                notificationsEnabled: sharedMed.notificationsEnabled
            )
            medication.id = sharedMed.id
            medication.reminderMinutes = sharedMed.reminderMinutes
            medication.lastGivenDate = sharedMed.lastGivenDate
            medication.pet = pet
            modelContext.insert(medication)

            let sharedLogs = (sharedMed.logs as? Set<SharedMedicationLog>) ?? []
            for sharedLog in sharedLogs {
                let log = MedicationLog(
                    timestamp: sharedLog.timestamp,
                    notes: sharedLog.notes,
                    loggedBy: sharedLog.loggedBy,
                    medication: medication
                )
                log.id = sharedLog.id
                log.medicationName = sharedLog.medicationName
                log.petId = sharedLog.petId
                modelContext.insert(log)
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return pet
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharePreparationControllerTests"`. Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharePreparationController.swift" "Did I Feed The DogTests/SharePreparationControllerTests.swift"
git commit -m "feat: SharePreparationController clones Pet<->SharedPet graphs (#57 phase 5)"
```

---

### Task 2: SharedSyncEngine.isOwner(ofZoneNamed:)

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`
- Test: `Did I Feed The DogTests/SharedSyncEngineIsOwnerTests.swift`

**Interfaces:**
- Consumes: `SharedSyncEngine.shared` (existing singleton), its private `tokens: SyncTokenStore` (existing, `Did I Feed The Dog/Sharing/SyncTokenStore.swift`).
- Produces: `func isOwner(ofZoneNamed zoneName: String) -> Bool` on `SharedSyncEngine`, used by Task 4's `SharedPetCard`.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedSyncEngineIsOwnerTests.swift`:

```swift
import XCTest
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedSyncEngineIsOwnerTests: XCTestCase {
    func testIsOwnerFalseForZoneWithNoPrivateToken() {
        // A zone that has never been synced has no token under either scope — isOwner must
        // report false. CKServerChangeToken has no public initializer, so the true-path (a
        // real private-scope token present) is verified by the Phase 5 manual two-account
        // checklist, not a unit test — matching SyncTokenStoreDBScopeTests, which for the
        // same reason only covers the nil/corrupt paths.
        let zoneName = "Zone-\(UUID().uuidString)"
        XCTAssertFalse(SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEngineIsOwnerTests"`. Expected: compile failure (`isOwner(ofZoneNamed:)` not found).

- [ ] **Step 3: Implement**

In `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`, add this method right after `database(forZone:)` (after line 102):

```swift

    /// UI-only convenience: true when the current user owns this zone. Mirrors the same
    /// private-scope-token signal `database(forZone:)` already uses for push/pull routing —
    /// does not duplicate the routing logic, just exposes its ownership half.
    func isOwner(ofZoneNamed zoneName: String) -> Bool {
        tokens.loadZoneToken(zoneName, scope: "private") != nil
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEngineIsOwnerTests"`. Expected: 1 PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncEngine.swift" "Did I Feed The DogTests/SharedSyncEngineIsOwnerTests.swift"
git commit -m "feat: SharedSyncEngine.isOwner(ofZoneNamed:) for UI gating (#57 phase 5)"
```

---

### Task 3: PetCard — real Pro-gated Share entry point

**Files:**
- Modify: `Did I Feed The Dog/Views/PetCard.swift`
- Modify: `Did I Feed The Dog/Views/CloudSharingView.swift`
- Modify: `Did I Feed The Dog/Views/SharedPetCard.swift`

**Interfaces:**
- Consumes: `SharePreparationController.migrateToShared(pet:sharedContext:)` (Task 1), `ShareController.makeShare(forRoot:)` (existing, `Did I Feed The Dog/Sharing/ShareController.swift:15`), `SharedSyncEngine.shared.fetchAllZones()` (existing), `EntitlementManager` (existing, `@Environment(EntitlementManager.self) private var entitlements`, already present in `PetCard`), `PaywallSheet(source:petName:)` (existing).
- Produces: nothing new consumed by later tasks — this is a leaf UI wiring task. No new automated test: `startSharing()` only sequences already-tested primitives (Task 1's migration, and the pre-existing `ShareController`/`SharedSyncEngine`), so there's no new pure decision logic to unit test. Verified by build + the Phase 5 manual checklist (spec's Testing section, item 3: "Non-Pro account taps 'Share this dog' → paywall shown, no migration occurs").

This task also relocates the `CKShare: Identifiable` conformance out of `SharedPetCard.swift`'s `#if DEBUG` block into `CloudSharingView.swift` (unconditional), since `PetCard`'s new `.sheet(item:)` needs it in release builds too. Leaving it duplicated in both files would be a redundant-conformance compile error; leaving it DEBUG-only in `SharedPetCard.swift` while removing it there would break `PetCard`'s release build. Moving it now (this task) keeps every intermediate state buildable. `SharedPetCard`'s own DEBUG Share/Stop-sharing buttons are otherwise untouched here — Task 4 replaces them.

- [ ] **Step 1: Move `CKShare: Identifiable` to `CloudSharingView.swift`**

In `Did I Feed The Dog/Views/CloudSharingView.swift`, add at the end of the file (after the closing brace of `CloudSharingView`):

```swift

extension CKShare: @retroactive Identifiable {
    public typealias ID = String
    public var id: String { recordID.recordName }
}
```

In `Did I Feed The Dog/Views/SharedPetCard.swift`, delete lines 56-68 (the `#if DEBUG ... #endif` block containing the now-duplicated `extension CKShare: @retroactive Identifiable`), leaving the rest of the file (including its own `#if DEBUG` contextMenu block above it) unchanged.

- [ ] **Step 2: Build to verify no duplicate-conformance error**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Add the Share entry point to PetCard**

In `Did I Feed The Dog/Views/PetCard.swift`, add `import CloudKit` after `import SwiftData` (line 2):

```swift
import SwiftUI
import SwiftData
import CloudKit
```

Add new `@State` properties after `@State private var showFastingAlert = false` (line 25):

```swift
    @State private var isSharing = false
    @State private var showSharePaywall = false
    @State private var shareToPresent: CKShare?
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
```

In the `.contextMenu { ... }` block (lines 124-145), add a new button after the "Edit Dog" button (after line 144, before the closing `}` of `.contextMenu`):

```swift

            Button {
                if entitlements.isPro {
                    Task { await startSharing() }
                } else {
                    showSharePaywall = true
                }
            } label: {
                Label("Share this dog", systemImage: "person.2.badge.plus")
            }
```

After the existing `.sheet(isPresented: $showPaywall) { PaywallSheet(source: "overdueCard") }` block (around line 209-211), add:

```swift
        .sheet(isPresented: $showSharePaywall) {
            PaywallSheet(source: "shareThisDog")
        }
        .sheet(item: $shareToPresent) { share in
            CloudSharingView(share: share)
        }
        .alert("Couldn't share this dog", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
```

Add the async helper as a new private method (near `checkOverdueTease()`, e.g. right after it):

```swift

    private func startSharing() async {
        guard !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        do {
            let sharedPet = try SharePreparationController.migrateToShared(pet: pet)
            modelContext.delete(pet)
            let share = try await ShareController.makeShare(forRoot: sharedPet)
            // Closes the seeding window: without this, isOwner(ofZoneNamed:) would report
            // false for the owner's own zone until the next natural fetchAllZones() cycle
            // (launch/foreground/poll), briefly hiding Share/Stop-sharing on the dog they
            // just shared.
            await SharedSyncEngine.shared.fetchAllZones()
            shareToPresent = share
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Views/PetCard.swift" "Did I Feed The Dog/Views/CloudSharingView.swift" "Did I Feed The Dog/Views/SharedPetCard.swift"
git commit -m "feat: real Pro-gated Share entry point on PetCard (#57 phase 5)"
```

---

### Task 4: SharedPetCard — real owner-gated Share/Stop-sharing, remove DEBUG block

**Files:**
- Modify: `Did I Feed The Dog/Views/SharedPetCard.swift`

**Interfaces:**
- Consumes: `SharedSyncEngine.shared.isOwner(ofZoneNamed:)` (Task 2), `CKRecordMapper.zoneID(forRoot:)` (existing, `Did I Feed The Dog/Sharing/CKRecordMapper.swift:30-32`), `SharePreparationController.migrateToOwned(sharedPet:modelContext:)` (Task 1), `ShareController.fetchShare`/`makeShare`/`stopSharing(forRoot:)` (existing).
- Produces: nothing consumed by later tasks (final task in this plan). No new automated test — same reasoning as Task 3: this composes already-tested primitives (Task 1's `migrateToOwned`, Task 2's `isOwner`, pre-existing `ShareController`) with no new pure decision logic. Verified by build + the Phase 5 manual checklist (spec's Testing section, items 1, 2, 4).

- [ ] **Step 1: Replace SharedPetCard's DEBUG block with the real, owner-gated one**

Read the current `Did I Feed The Dog/Views/SharedPetCard.swift` first (Task 3 already removed its trailing `CKShare: Identifiable` extension). Replace the entire file with:

```swift
import CloudKit
import CoreData
import SwiftData
import SwiftUI

/// Dashboard card for a dog shared with the user. Read-only for meal/medication logging
/// (deferred to a later phase); owner-gated Share/Stop-sharing controls (Phase 5).
struct SharedPetCard: View {
    @Environment(\.modelContext) private var modelContext
    let dog: any DogDisplayable

    @State private var shareToPresent: CKShare?
    @State private var isBusy = false
    @State private var showStopSharingConfirm = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""

    private var sharedPet: SharedPet? { dog as? SharedPet }

    private var isOwner: Bool {
        guard SharingFeatureFlag.isFoundationEnabled, let pet = sharedPet else { return false }
        let zoneName = CKRecordMapper.zoneID(forRoot: pet).zoneName
        return SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName)
    }

    var body: some View {
        HStack(spacing: 12) {
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
        .contextMenu {
            if let pet = sharedPet, isOwner {
                Button {
                    Task { await manageSharing(for: pet) }
                } label: {
                    Label("Share this dog", systemImage: "person.2.badge.plus")
                }
                Button("Stop sharing", role: .destructive) {
                    showStopSharingConfirm = true
                }
            }
        }
        .confirmationDialog("Stop sharing this dog?", isPresented: $showStopSharingConfirm, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) {
                if let pet = sharedPet { Task { await stopSharing(pet) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll keep this dog and its history. Anyone you shared it with will lose access.")
        }
        .sheet(item: $shareToPresent) { share in
            CloudSharingView(share: share)
        }
        .alert("Couldn't share this dog", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
    }

    private func manageSharing(for pet: SharedPet) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let existing = try await ShareController.fetchShare(forRoot: pet) {
                shareToPresent = existing
            } else {
                shareToPresent = try await ShareController.makeShare(forRoot: pet)
            }
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }

    private func stopSharing(_ pet: SharedPet) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try SharePreparationController.migrateToOwned(sharedPet: pet, modelContext: modelContext)
            await ShareController.stopSharing(forRoot: pet)
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the full existing suite for regressions**

```
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 2>&1 | tail -60
```

Expected: no new failures beyond the known-flaky baseline (see Environment / mechanics). All `SharePreparationControllerTests` and `SharedSyncEngineIsOwnerTests` pass.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Views/SharedPetCard.swift"
git commit -m "feat: real owner-gated Share/Stop-sharing on SharedPetCard, remove DEBUG block (#57 phase 5)"
```

---

## Manual validation (not automatable — real devices, two accounts, Pro entitlement active)

After all 4 tasks are merged, per the spec's Testing section:

1. Owner shares a real dog with existing feeding/medication history → dashboard shows it as a `SharedPetCard`; participant accepts and sees the same history.
2. Owner taps "Stop sharing" → dog returns to owner's dashboard as a normal `PetCard` with all history intact; participant's copy disappears.
3. Non-Pro account taps "Share this dog" → paywall shown, no migration occurs, dog stays owned.
4. Participant's `SharedPetCard` context menu shows no Share/Stop-sharing entries.
5. Re-share the same dog a second time after stop-sharing → works normally (fresh zone, fresh `ckRecordName`s).
