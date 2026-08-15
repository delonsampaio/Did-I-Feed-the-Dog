# Family Sharing — Phase 6 Shared-Dog Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any participant (owner or invited family member) log a feeding or medication dose on a shared dog — today `SharedPetCard` is view-only — with concurrent logging from two devices never silently losing a write.

**Architecture:** New feeding/medication logging paths for the Core Data shared store, mirroring the existing owned-dog (`FeedingLogService`/`LogFeedingSheet`/`LogMedicationSheet`) patterns but structurally avoiding the mutable-counter conflict problem: `SharedPet.foodStockCount`/`todaysFeedingCount`/`lastFeedingDate` stop being read as stored, independently-mutated fields and become values computed live from the `feedingEvents` relationship. Two devices logging concurrently each create an independent new `SharedFeedingEvent` (different `ckRecordName`), so CloudKit sync has nothing to conflict on.

**Tech Stack:** Swift, SwiftUI, Core Data, CloudKit (unchanged — no new sync code, existing Phase 2 push observer picks up new records automatically), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-15-family-sharing-shared-dog-logging-design.md`

## Global Constraints

- **Design source:** `docs/superpowers/specs/2026-08-15-family-sharing-shared-dog-logging-design.md`.
- **`loggedBy` reuses `LoggedBy.current`** (`Did I Feed The Dog/Utilities/LoggedBy.swift`) unchanged — no new identity work.
- **No mutable stock/count fields for display.** `foodStockCount` stays a stored field but is only ever *written* by an explicit restock (never by logging a feeding); `todaysFeedingCount`/`lastFeedingDate` become fully computed from `feedingEvents`.
- **Medication's `lastGivenDate` keeps last-writer-wins** — a plain field write, same as owned dogs. Only feeding-related counters get the derived treatment.
- **Shared-dog stock deduction is NOT gated by `AppSettings.stockMode`** (that setting governs the owned-dog individual/shared-local-pool system only, an unrelated feature). A shared dog's `portionsDeducted` is purely a function of meal type + toggle, mirroring `FeedingLogService.resolvePortions`'s existing per-meal-type logic verbatim.
- **`LogSharedMedicationSheet` lists ALL of the dog's medications**, not just "due" ones — porting `Medication.isDue`'s reminder-mode logic to the Core Data side is out of scope for this phase (not in the approved spec); the user picks which medication they're logging.
- **No shared-dog history browsing this phase** — no `SharedPetDetailView`, no navigation destination. Logging is sheet-based from `SharedPetCard` only.
- **Flag-gated:** `SharingFeatureFlag.isFoundationEnabled` — unchanged pattern from every prior phase; `SharedPetCard` already only renders when the flag is on (upstream in `DashboardView`), but new entry points also carry an explicit flag check for defense-in-depth, matching Phase 5's convention.
- **Never `fatalError`.** Surface Core Data save failures as a simple alert with `error.localizedDescription`.

### Environment / mechanics (every task)

- New files → `Did I Feed The Dog/Sharing/` (services/model) or `Did I Feed The Dog/Views/` (sheets); tests → `Did I Feed The DogTests/`. Xcode 16 filesystem-synchronized groups — **no `project.pbxproj` edits**.
- **Swift 6 `-default-isolation=MainActor` strict concurrency is enforced.** New services/enums touching Core Data on the main thread should be `@MainActor`, matching `ShareController`/`SharePreparationController`.
- **Single simulator (limited RAM — never spawn parallel clones).** Test:
  ```
  xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:"Did I Feed The DogTests/<ClassName>" 2>&1 | tail -40
  ```
  Build:
  ```
  xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
  ```
- **Known-flaky baseline:** ~14 pre-existing/environmental failures (CloudKit-no-account + App-Group sandbox), consistent across every prior phase — judge success by new tests passing + no NEW failures in touched files.
- **SourceKit's live "Cannot find type/module in scope" diagnostics are unreliable on this project** (confirmed stale-index behavior on every file touched in Phases 5–6 so far) — always verify with a real `xcodebuild` run, never trust the editor's live error list.
- Verify exact Core Data/SwiftUI API shapes against the SDK (use the LSP tool) if the compiler disagrees with a signature below; adapt labels minimally, keeping behavior, and note it.

---

### Task 1: `foodStockBaselineDate` field + `SharedPet.effectiveFoodStockCount`

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedDataModel.swift`
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`
- Test: `Did I Feed The DogTests/SharedPetStockTests.swift`

**Interfaces:**
- Produces: `SharedPet.foodStockBaselineDate: Date?` (new `@NSManaged` property), `SharedPet.effectiveFoodStockCount: Int` (new computed property, used by Task 5's restock sheet and Task 4's feeding sheet).

- [ ] **Step 1: Write the failing tests**

Create `Did I Feed The DogTests/SharedPetStockTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedPetStockTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    private func makeEvent(in context: NSManagedObjectContext, pet: SharedPet, timestamp: Date, portions: Int) {
        let event = SharedFeedingEvent(context: context)
        event.timestamp = timestamp
        event.portionsDeducted = NSNumber(value: portions)
        event.pet = pet
    }

    func testNoEventsReturnsBaselineUnchanged() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(pet.effectiveFoodStockCount, 10)
    }

    func testEventsAfterBaselineAreDeducted() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 3)
        XCTAssertEqual(pet.effectiveFoodStockCount, 7)
    }

    func testEventsBeforeBaselineAreExcluded() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 5000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 3)
        XCTAssertEqual(pet.effectiveFoodStockCount, 10)
    }

    func testMixedEventsOnlyCountsAfterBaseline() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 3000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 5) // before, excluded
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 4000), portions: 2) // after, counted
        XCTAssertEqual(pet.effectiveFoodStockCount, 8)
    }

    func testNilBaselineCountsAllEvents() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 10
        pet.foodStockBaselineDate = nil
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 1), portions: 4)
        XCTAssertEqual(pet.effectiveFoodStockCount, 6)
    }

    func testNeverGoesNegative() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.foodStockCount = 2
        pet.foodStockBaselineDate = Date(timeIntervalSince1970: 1000)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000), portions: 5)
        XCTAssertEqual(pet.effectiveFoodStockCount, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run `-only-testing:"Did I Feed The DogTests/SharedPetStockTests"`. Expected: compile failure (`foodStockBaselineDate`/`effectiveFoodStockCount` not found).

- [ ] **Step 3: Implement**

In `Did I Feed The Dog/Sharing/SharedDataModel.swift`, in the `pet.properties` array, add a new line right after `attr("todaysFeedingCountRaw", .integer64AttributeType, defaultValue: 0),`:

```swift
            attr("foodStockBaselineDate", .dateAttributeType, optional: true),
```

In `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`, in the `SharedPet` class, add a new line right after `@NSManaged var todaysFeedingCountRaw: Int64`:

```swift
    @NSManaged var foodStockBaselineDate: Date?
```

At the bottom of the same file, add a new extension (near the existing `SharedMedication.reminderMinutes` extension):

```swift

extension SharedPet {
    /// Current stock, derived from the last manually-set baseline minus every feeding logged
    /// since. Two devices logging concurrently each create a new SharedFeedingEvent rather than
    /// mutating a shared counter, so CloudKit sync merges them with nothing to conflict on.
    var effectiveFoodStockCount: Int {
        let events = (feedingEvents as? Set<SharedFeedingEvent>) ?? []
        let since = foodStockBaselineDate ?? .distantPast
        let deducted = events
            .filter { $0.timestamp > since }
            .reduce(0) { $0 + ($1.portionsDeducted?.intValue ?? 0) }
        return max(0, Int(foodStockCount) - deducted)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedPetStockTests"`. Expected: 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedDataModel.swift" "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The DogTests/SharedPetStockTests.swift"
git commit -m "feat: foodStockBaselineDate + SharedPet.effectiveFoodStockCount (#57 phase 6)"
```

---

### Task 2: `DogDisplayable` derived `todaysFeedingCount`/`lastFeedingDate` for `SharedPet`

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`
- Modify: `Did I Feed The Dog/Sharing/DogDisplayable.swift`
- Test: `Did I Feed The DogTests/SharedPetDisplayableTests.swift`

**Interfaces:**
- Consumes: `SharedFeedingEvent` (existing, `Sharing/SharedManagedObjects.swift`).
- Produces: `SharedPet.todaysFeedingCount: Int` and `SharedPet.lastFeedingDate: Date?` (both now computed, satisfying the existing `DogDisplayable` protocol — no signature change, only behavior).

**Important — a redeclaration conflict to avoid:** `SharedPet` currently has a **stored** `@NSManaged var lastFeedingDate: Date?` property. You cannot add a same-named *computed* property for `lastFeedingDate` in the `DogDisplayable` extension while that stored property still exists on the class — Swift will reject it as a redeclaration. You must **remove** the stored `@NSManaged var lastFeedingDate: Date?` line from the `SharedPet` class first, then add the computed version in the extension. The underlying Core Data model attribute (declared in `SharedDataModel.swift`) stays as-is — do NOT remove it from the model, only the Swift class's `@NSManaged` accessor. This is safe: `CKRecordMapper`'s sync code reads/writes Core Data attributes via generic key-value coding (`value(forKey:)`/`setValue(forKey:)`) against the model's `attributesByName`, not via the Swift `@NSManaged` property — removing the Swift accessor does not break sync, it just means nothing in the app reads or writes that attribute going forward (it becomes inert/stale, which is fine — nothing currently writes to it either, since shared-dog feeding logging doesn't exist yet before this plan).

Before editing, run this to confirm nothing outside `DogDisplayable.swift`/`SharedManagedObjects.swift` references `SharedPet`'s `lastFeedingDate` directly (bypassing the protocol) — if it finds any other hit, stop and report it as a concern rather than proceeding:
```bash
grep -rn "\.lastFeedingDate" "Did I Feed The Dog" --include=*.swift
```
(Expected hits: `DashboardView.swift`/`PetCard.swift`/`SharedPetCard.swift` accessing it through the `dog: any DogDisplayable` protocol type — those are fine and unaffected by this change, since the protocol requirement's *type* doesn't change, only `SharedPet`'s implementation.)

- [ ] **Step 1: Write the failing tests**

Create `Did I Feed The DogTests/SharedPetDisplayableTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

final class SharedPetDisplayableTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    private func makeEvent(in context: NSManagedObjectContext, pet: SharedPet, timestamp: Date) {
        let event = SharedFeedingEvent(context: context)
        event.timestamp = timestamp
        event.pet = pet
    }

    func testEmptyEventsReturnsNilLastFeedingDateAndZeroToday() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        XCTAssertNil(pet.lastFeedingDate)
        XCTAssertEqual(pet.todaysFeedingCount, 0)
    }

    func testLastFeedingDateIsMaxTimestamp() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 1000))
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 3000))
        makeEvent(in: context, pet: pet, timestamp: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(pet.lastFeedingDate, Date(timeIntervalSince1970: 3000))
    }

    func testTodaysFeedingCountOnlyCountsToday() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let yesterday = startOfToday.addingTimeInterval(-3600)
        let laterToday = startOfToday.addingTimeInterval(3600)
        makeEvent(in: context, pet: pet, timestamp: yesterday)
        makeEvent(in: context, pet: pet, timestamp: laterToday)
        makeEvent(in: context, pet: pet, timestamp: startOfToday)
        XCTAssertEqual(pet.todaysFeedingCount, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run `-only-testing:"Did I Feed The DogTests/SharedPetDisplayableTests"`. Expected: `testEmptyEventsReturnsNilLastFeedingDateAndZeroToday` may pass by coincidence (stored field defaults to nil/0); `testLastFeedingDateIsMaxTimestamp` and `testTodaysFeedingCountOnlyCountsToday` FAIL, since the current implementation reads stored fields that are never written by this test.

- [ ] **Step 3: Implement**

In `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`, in the `SharedPet` class, **delete** this line entirely:

```swift
    @NSManaged var lastFeedingDate: Date?
```

In `Did I Feed The Dog/Sharing/DogDisplayable.swift`, replace the `SharedPet` extension (lines 40-45) with:

```swift
extension SharedPet: DogDisplayable {
    var displayName: String { name ?? "Dog" }
    var isShared: Bool { true }
    var ageString: String { dogAgeString(from: birthday) }

    /// Derived from feedingEvents rather than a stored counter, so two devices logging
    /// concurrently both count — see SharedFeedingLogService.
    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let events = (feedingEvents as? Set<SharedFeedingEvent>) ?? []
        return events.filter { $0.timestamp >= startOfDay }.count
    }

    /// Derived from feedingEvents rather than a stored field, for the same concurrent-write
    /// reason as todaysFeedingCount. The Core Data model still declares a lastFeedingDate
    /// attribute (harmless, unused by the app — see the Phase 6 spec).
    var lastFeedingDate: Date? {
        let events = (feedingEvents as? Set<SharedFeedingEvent>) ?? []
        return events.map(\.timestamp).max()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedPetDisplayableTests"`. Expected: 3 PASS.

- [ ] **Step 5: Build to check for regressions**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED (confirms removing the stored `@NSManaged` property didn't break any other reference).

- [ ] **Step 6: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The Dog/Sharing/DogDisplayable.swift" "Did I Feed The DogTests/SharedPetDisplayableTests.swift"
git commit -m "feat: derive SharedPet todaysFeedingCount/lastFeedingDate from events (#57 phase 6)"
```

---

### Task 3: `SharedFeedingLogService`

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharedFeedingLogService.swift`
- Test: `Did I Feed The DogTests/SharedFeedingLogServiceTests.swift`

**Interfaces:**
- Consumes: `SharedPet`, `SharedFeedingEvent` (existing), `MealType.from(_:)`/`AppSettings.portionSize(for:)` (existing, `Did I Feed The Dog/Models/MealType.swift` and `Did I Feed The Dog/Services/AppSettings.swift`).
- Produces: `SharedFeedingLogService.logFeeding(for:mealLabel:deductsStock:timestamp:notes:logger:in:) throws -> SharedFeedingEvent`, used by Task 4's `LogSharedFeedingSheet`.

- [ ] **Step 1: Write the failing tests**

Create `Did I Feed The DogTests/SharedFeedingLogServiceTests.swift`:

```swift
import XCTest
import CoreData
@testable import Did_I_Feed_The_Dog

@MainActor
final class SharedFeedingLogServiceTests: XCTestCase {

    private func ctx() throws -> NSManagedObjectContext {
        let model = SharedDataModel.makeModel()
        let c = NSPersistentContainer(name: "T", managedObjectModel: model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var err: Error?; c.loadPersistentStores { _, e in err = e }
        if let err { throw err }
        return c.viewContext
    }

    func testLogFeedingCreatesStampedEvent() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.id = UUID()
        pet.name = "Fido"
        try context.save()

        let event = try SharedFeedingLogService.logFeeding(
            for: pet, mealLabel: "Breakfast", deductsStock: true,
            timestamp: Date(timeIntervalSince1970: 1000), notes: "yum",
            logger: "Alex", in: context
        )

        XCTAssertEqual(event.mealType, "Breakfast")
        XCTAssertEqual(event.notes, "yum")
        XCTAssertEqual(event.loggedBy, "Alex")
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 1000))
        XCTAssertNotNil(event.ckRecordName)
        XCTAssertEqual(event.pet, pet)
        XCTAssertEqual(event.didDeductStock, true)
        XCTAssertEqual(event.portionsDeducted?.intValue, AppSettings.portionSize(for: .breakfast))
    }

    func testCustomMealWithToggleOffDeductsNothing() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.id = UUID()
        try context.save()

        let event = try SharedFeedingLogService.logFeeding(
            for: pet, mealLabel: "Peanut Butter Kong", deductsStock: false,
            timestamp: .now, logger: "Sam", in: context
        )

        XCTAssertEqual(event.portionsDeducted?.intValue, 0)
        XCTAssertEqual(event.didDeductStock, false)
    }

    func testCustomMealWithToggleOnDeductsOnePortion() throws {
        let context = try ctx()
        let pet = SharedPet(context: context)
        pet.id = UUID()
        try context.save()

        let event = try SharedFeedingLogService.logFeeding(
            for: pet, mealLabel: "Peanut Butter Kong", deductsStock: true,
            timestamp: .now, logger: "Sam", in: context
        )

        XCTAssertEqual(event.portionsDeducted?.intValue, 1)
        XCTAssertEqual(event.didDeductStock, true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run `-only-testing:"Did I Feed The DogTests/SharedFeedingLogServiceTests"`. Expected: compile failure (`SharedFeedingLogService` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/SharedFeedingLogService.swift`:

```swift
import CoreData
import Foundation

/// Shared-dog analog of FeedingLogService, deliberately thin: it only creates the
/// SharedFeedingEvent. No stock mutation — SharedPet.effectiveFoodStockCount derives current
/// stock from feedingEvents instead (see the Phase 6 spec) — and none of FeedingLogService's
/// owned-dog-only side effects (low-stock notifications, overdue scheduling, reminder
/// suppression, widget/badge refresh) apply to shared dogs yet.
@MainActor
enum SharedFeedingLogService {

    static func logFeeding(
        for pet: SharedPet,
        mealLabel: String,
        deductsStock: Bool,
        timestamp: Date = .now,
        notes: String = "",
        logger: String,
        in context: NSManagedObjectContext
    ) throws -> SharedFeedingEvent {
        let portionsToDeduct = resolvePortions(mealLabel: mealLabel, deductsStock: deductsStock)

        let event = SharedFeedingEvent(context: context)
        event.timestamp = timestamp
        event.mealType = mealLabel
        event.notes = notes
        event.loggedBy = logger
        event.didDeductStock = NSNumber(value: portionsToDeduct > 0)
        event.portionsDeducted = NSNumber(value: portionsToDeduct)
        event.ckRecordName = UUID().uuidString
        event.pet = pet

        try context.save()
        return event
    }

    /// Mirrors FeedingLogService.resolvePortions verbatim: custom meals use the explicit
    /// toggle (0 or 1); preset meals always look up the user's configured portion size,
    /// regardless of the toggle, so per-meal-type multipliers apply consistently.
    private static func resolvePortions(mealLabel: String, deductsStock: Bool) -> Int {
        let mealType = MealType.from(mealLabel)
        switch mealType {
        case .custom: return deductsStock ? 1 : 0
        default:      return AppSettings.portionSize(for: mealType)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run `-only-testing:"Did I Feed The DogTests/SharedFeedingLogServiceTests"`. Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedFeedingLogService.swift" "Did I Feed The DogTests/SharedFeedingLogServiceTests.swift"
git commit -m "feat: SharedFeedingLogService creates stamped SharedFeedingEvents (#57 phase 6)"
```

---

### Task 4: `LogSharedFeedingSheet`

**Files:**
- Create: `Did I Feed The Dog/Views/LogSharedFeedingSheet.swift`

**Interfaces:**
- Consumes: `SharedFeedingLogService.logFeeding(for:mealLabel:deductsStock:timestamp:notes:logger:in:) throws -> SharedFeedingEvent` (Task 3), `LoggedBy.current` (existing), `MealType` (existing), `SharedDataStack.shared.viewContext` (existing, fallback only).
- Produces: `LogSharedFeedingSheet(pet: SharedPet, onLogged: ((SharedFeedingEvent) -> Void)? = nil)`, used by Task 7's `SharedPetCard`.

This task has no new pure decision logic — it's UI wiring around Task 3's already-tested service (portion/stock resolution lives entirely in `SharedFeedingLogService`). Verified by build, not a dedicated unit test, matching the same reasoning used for equivalent UI-wiring tasks in the Phase 5 plan.

- [ ] **Step 1: Implement**

Create `Did I Feed The Dog/Views/LogSharedFeedingSheet.swift`:

```swift
import SwiftUI

struct LogSharedFeedingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet
    var onLogged: ((SharedFeedingEvent) -> Void)? = nil

    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false
    @State private var notes = ""
    @State private var deductPortion = true
    @State private var isSubmitting = false
    @State private var showCustomTime = false
    @State private var logDate = Date()
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @FocusState private var notesFocused: Bool

    private var noteSuggestions: [String] {
        let events = (pet.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for event in events.sorted(by: { $0.timestamp > $1.timestamp }).prefix(200) {
            let note = event.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty, seen.insert(note).inserted else { continue }
            result.append(note)
            if result.count == 8 { break }
        }
        return result
    }

    private var filteredSuggestions: [String] {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return noteSuggestions }
        let q = trimmed.lowercased()
        return noteSuggestions.filter { $0.lowercased().contains(q) && $0.lowercased() != q }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                mealPicker

                if showCustomField {
                    TextField("Meal name (e.g. Medication)", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    Toggle("Deduct a portion", isOn: $deductPortion)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Toggle("Set custom time", isOn: $showCustomTime.animation())
                        .tint(.green)
                    if showCustomTime {
                        DatePicker("Time", selection: $logDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .padding(.horizontal)

                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .focused($notesFocused)
                    .padding(.horizontal)

                let suggestions = filteredSuggestions
                if (notesFocused || !notes.isEmpty) && !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    notes = suggestion
                                    notesFocused = false
                                } label: {
                                    Text(suggestion)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .safeAreaInset(edge: .bottom) {
                confirmButton
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom)
            }
            .navigationTitle(pet.name ?? "Unknown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.fraction(0.65), .large])
    }

    private var mealPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 110))]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(MealType.presets, id: \.label) { meal in
                mealChip(meal)
            }
            customChip
        }
        .padding(.horizontal)
    }

    private func mealChip(_ meal: MealType) -> some View {
        let isSelected = selectedMealType == meal && !showCustomField
        return Button {
            selectedMealType = meal
            showCustomField = false
            deductPortion = true
        } label: {
            VStack(spacing: 4) {
                Text(meal.emoji).font(.title2).accessibilityHidden(true)
                Text(meal.label).font(.caption).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .green : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : .clear, lineWidth: 2)
            )
        }
        .accessibilityLabel(meal.label)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var customChip: some View {
        Button {
            showCustomField = true
            selectedMealType = .custom("")
        } label: {
            VStack(spacing: 4) {
                Text("✏️").font(.title2).accessibilityHidden(true)
                Text("Custom").font(.caption).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(showCustomField ? Color.blue.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundStyle(showCustomField ? .blue : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(showCustomField ? Color.blue : .clear, lineWidth: 2)
            )
        }
        .accessibilityLabel("Custom meal")
        .accessibilityValue(showCustomField ? "Selected" : "")
    }

    private var confirmButton: some View {
        Button(action: logFeeding) {
            Label("Log Meal", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canConfirm ? Color.green : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canConfirm || isSubmitting)
    }

    private var canConfirm: Bool {
        if showCustomField { return !customLabel.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var resolvedMealLabel: String {
        showCustomField ? customLabel.trimmingCharacters(in: .whitespaces) : selectedMealType.label
    }

    private func logFeeding() {
        guard !isSubmitting else { return }
        isSubmitting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let shouldDecrementStock = showCustomField ? deductPortion : selectedMealType.decrementsStock

        do {
            let event = try SharedFeedingLogService.logFeeding(
                for: pet,
                mealLabel: resolvedMealLabel,
                deductsStock: shouldDecrementStock,
                timestamp: showCustomTime ? logDate : .now,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                logger: LoggedBy.current,
                in: pet.managedObjectContext ?? SharedDataStack.shared.viewContext
            )
            onLogged?(event)
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save meal: \(error.localizedDescription)"
            showSaveError = true
            isSubmitting = false
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Views/LogSharedFeedingSheet.swift"
git commit -m "feat: LogSharedFeedingSheet for logging shared-dog feedings (#57 phase 6)"
```

---

### Task 5: Shared-dog restock sheet

**Files:**
- Create: `Did I Feed The Dog/Views/SharedRestockSheet.swift`

**Interfaces:**
- Consumes: `SharedPet.effectiveFoodStockCount` (Task 1).
- Produces: `SharedRestockSheet(pet: SharedPet)`, used by Task 7's `SharedPetCard`.

No dedicated test — the implementation is two field writes plus a save, with no branching logic beyond what `effectiveFoodStockCount` (already tested in Task 1) already covers. Verified by build.

- [ ] **Step 1: Implement**

Create `Did I Feed The Dog/Views/SharedRestockSheet.swift`:

```swift
import CoreData
import SwiftUI

/// Sets a new stock baseline for a shared dog. Unlike QuickStockSheet (owned dogs, live
/// Binding<Int>), this commits explicitly on "Done" — writing foodStockCount and
/// foodStockBaselineDate together in one save, rather than pushing a CloudKit record on every
/// +/-1 tap.
struct SharedRestockSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pet: SharedPet
    @State private var newCount: Int
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    init(pet: SharedPet) {
        self.pet = pet
        _newCount = State(initialValue: pet.effectiveFoodStockCount)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("\(newCount)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("portions remaining")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Button {
                        if newCount > 0 { newCount -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Decrease stock by 1")
                    Button {
                        if newCount < 9999 { newCount += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Increase stock by 1")
                }

                Stepper("Adjust by 10", value: $newCount, in: 0...9999, step: 10)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("\(pet.name ?? "Dog")'s Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitAndDismiss() }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationDetents([.medium])
    }

    private func commitAndDismiss() {
        pet.foodStockCount = Int64(newCount)
        pet.foodStockBaselineDate = .now
        do {
            try pet.managedObjectContext?.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save stock count: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Views/SharedRestockSheet.swift"
git commit -m "feat: SharedRestockSheet sets a new shared-dog stock baseline (#57 phase 6)"
```

---

### Task 6: `LogSharedMedicationSheet`

**Files:**
- Create: `Did I Feed The Dog/Views/LogSharedMedicationSheet.swift`

**Interfaces:**
- Consumes: `SharedMedication`, `SharedMedicationLog` (existing, `Sharing/SharedManagedObjects.swift`), `LoggedBy.current` (existing).
- Produces: `LogSharedMedicationSheet(pet: SharedPet, medications: [SharedMedication])`, used by Task 7's `SharedPetCard`.

No dedicated test — this mirrors `LogMedicationSheet`'s existing inline (no-service-layer) pattern, with no new pure decision logic beyond direct field assignment. Verified by build.

- [ ] **Step 1: Implement**

Create `Did I Feed The Dog/Views/LogSharedMedicationSheet.swift`:

```swift
import CoreData
import SwiftUI

struct LogSharedMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet
    let medications: [SharedMedication]

    @State private var selectedMedication: SharedMedication?
    @State private var notes = ""
    @State private var showCustomTime = false
    @State private var logDate = Date()
    @State private var isSubmitting = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if medications.count > 1 {
                    medicationPicker
                }

                VStack(spacing: 12) {
                    Toggle("Set custom time", isOn: $showCustomTime.animation())
                        .tint(.purple)
                    if showCustomTime {
                        DatePicker("Time", selection: $logDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .padding(.horizontal)

                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .padding(.horizontal)

                Spacer()
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .safeAreaInset(edge: .bottom) {
                logButton
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom)
            }
            .navigationTitle(medications.count == 1 ? medications[0].name : "Log Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { selectedMedication = medications.first }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.fraction(0.55), .large])
    }

    @ViewBuilder
    private var medicationPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 120))]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(medications, id: \.objectID) { med in
                let isSelected = selectedMedication?.objectID == med.objectID
                Button {
                    selectedMedication = med
                } label: {
                    VStack(spacing: 4) {
                        Text("💊").font(.title2).accessibilityHidden(true)
                        Text(med.name)
                            .font(.caption).fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Color.purple.opacity(0.2) : Color(.secondarySystemBackground))
                    .foregroundStyle(isSelected ? .purple : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.purple : .clear, lineWidth: 2)
                    )
                }
                .accessibilityLabel(med.name)
                .accessibilityValue(isSelected ? "Selected" : "")
            }
        }
        .padding(.horizontal)
    }

    private var logButton: some View {
        Button(action: logDose) {
            Label("Log Dose", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(selectedMedication != nil ? Color.purple : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(selectedMedication == nil || isSubmitting)
    }

    private func logDose() {
        guard let med = selectedMedication, !isSubmitting else { return }
        isSubmitting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let timestamp = showCustomTime ? logDate : .now
        guard let context = med.managedObjectContext else {
            saveErrorMessage = "Failed to save dose: no context"
            showSaveError = true
            isSubmitting = false
            return
        }

        let log = SharedMedicationLog(context: context)
        log.id = UUID()
        log.timestamp = timestamp
        log.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        log.loggedBy = LoggedBy.current
        log.medicationName = med.name
        log.petId = pet.id
        log.ckRecordName = UUID().uuidString
        log.medication = med
        med.lastGivenDate = timestamp

        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save dose: \(error.localizedDescription)"
            showSaveError = true
            isSubmitting = false
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Views/LogSharedMedicationSheet.swift"
git commit -m "feat: LogSharedMedicationSheet for logging shared-dog medication doses (#57 phase 6)"
```

---

### Task 7: `SharedPetCard` — wire logging entry points

**Files:**
- Modify: `Did I Feed The Dog/Views/SharedPetCard.swift`

**Interfaces:**
- Consumes: `LogSharedFeedingSheet(pet:onLogged:)` (Task 4), `SharedRestockSheet(pet:)` (Task 5), `LogSharedMedicationSheet(pet:medications:)` (Task 6).
- Produces: nothing consumed by later tasks (final task in this plan).

No new automated test — pure UI composition of already-tested/already-built-verified pieces. Verified by build + a full-suite regression pass (last task in the plan) + the manual checklist.

- [ ] **Step 1: Replace `SharedPetCard` with the version that wires all three logging entry points**

Read the current `Did I Feed The Dog/Views/SharedPetCard.swift` first to confirm it matches the state left by Phase 5 (owner-gated Share/Stop-sharing `contextMenu`, no logging affordances). Replace the entire file with:

```swift
import CloudKit
import CoreData
import SwiftData
import SwiftUI

/// Dashboard card for a dog shared with the user. Log Meal / Log Medication / Update Stock are
/// available to any participant; Share/Stop-sharing stay owner-gated (Phase 5).
struct SharedPetCard: View {
    @Environment(\.modelContext) private var modelContext
    let dog: any DogDisplayable

    @State private var shareToPresent: CKShare?
    @State private var isBusy = false
    @State private var showStopSharingConfirm = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    @State private var showLogFeeding = false
    @State private var showLogMedication = false
    @State private var showRestockSheet = false

    private var sharedPet: SharedPet? { dog as? SharedPet }

    private var isOwner: Bool {
        guard SharingFeatureFlag.isFoundationEnabled, let pet = sharedPet else { return false }
        let zoneName = CKRecordMapper.zoneID(forRoot: pet).zoneName
        return SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName)
    }

    private var medications: [SharedMedication] {
        Array((sharedPet?.medications as? Set<SharedMedication>) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if SharingFeatureFlag.isFoundationEnabled, sharedPet != nil {
                HStack(spacing: 8) {
                    Button {
                        showLogFeeding = true
                    } label: {
                        Label("Log Meal", systemImage: "fork.knife")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !medications.isEmpty {
                        Button {
                            showLogMedication = true
                        } label: {
                            Label("Log Medication", systemImage: "pill")
                                .font(.subheadline).fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if sharedPet != nil {
                Button {
                    showRestockSheet = true
                } label: {
                    Label("Update Food Stock", systemImage: "shippingbox")
                }
            }
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
        .sheet(isPresented: $showLogFeeding) {
            if let pet = sharedPet {
                LogSharedFeedingSheet(pet: pet)
            }
        }
        .sheet(isPresented: $showLogMedication) {
            if let pet = sharedPet {
                LogSharedMedicationSheet(pet: pet, medications: medications)
            }
        }
        .sheet(isPresented: $showRestockSheet) {
            if let pet = sharedPet {
                SharedRestockSheet(pet: pet)
            }
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
            try await ShareController.stopSharing(forRoot: pet)
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
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 2>&1 | tail -80
```

Expected: no new failures beyond the known-flaky baseline (see Environment / mechanics). All `SharedPetStockTests`, `SharedPetDisplayableTests`, and `SharedFeedingLogServiceTests` pass.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Views/SharedPetCard.swift"
git commit -m "feat: wire Log Meal/Log Medication/restock entry points on SharedPetCard (#57 phase 6)"
```

---

## Manual validation (not automatable — real devices, two accounts, flag on)

After all 7 tasks are merged, per the spec's Testing section:

1. Both devices log feedings for the same shared dog within a short window (before either syncs)
   → after sync, both events appear on both devices; stock and today's-count reflect the sum,
   not just one side's write.
2. Restock on one device → other device shows the new baseline after sync.
3. Log a medication dose from either device → the other device's medication list reflects the
   updated `lastGivenDate` after sync (last-writer-wins accepted if truly concurrent).
4. Flag off: no logging entry points appear (shared dogs themselves don't render without the
   flag, per existing `DashboardView` gating — confirmed unaffected by this phase).
