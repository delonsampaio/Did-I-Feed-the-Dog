# Did I Feed the Dog? — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a high-polish multi-dog feeding tracker iOS app using SwiftData + CloudKit with push notifications and a searchable toxic food safety guide.

**Architecture:** Vanilla SwiftData (no ViewModel layer) — `@Query` and `@Environment(\.modelContext)` in views directly. All notification logic in a singleton `NotificationManager`. Xcode filesystem sync is enabled so files added to the folder are auto-discovered.

**Tech Stack:** Swift, SwiftUI, SwiftData, CloudKit, UserNotifications, PhotosUI, XCTest

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| DELETE | `Did I Feed The Dog/Item.swift` | Replaced by Pet.swift |
| CREATE | `Did I Feed The Dog/Models/MealType.swift` | View-layer enum for meal picker |
| CREATE | `Did I Feed The Dog/Models/Pet.swift` | SwiftData Pet model + computed helpers |
| CREATE | `Did I Feed The Dog/Models/FeedingEvent.swift` | SwiftData FeedingEvent model |
| MODIFY | `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift` | ModelContainer + CloudKit + notification auth |
| CREATE | `Did I Feed The Dog/Services/NotificationManager.swift` | UNUserNotificationCenter singleton |
| CREATE | `Did I Feed The Dog/Resources/ToxicFoods.swift` | Static SafetyEntry array |
| CREATE | `Did I Feed The Dog/Views/DashboardView.swift` | Root NavigationStack + pet list |
| CREATE | `Did I Feed The Dog/Views/PetCard.swift` | Per-dog card with feed button |
| CREATE | `Did I Feed The Dog/Views/LogFeedingSheet.swift` | Meal picker bottom sheet |
| CREATE | `Did I Feed The Dog/Views/PetDetailView.swift` | Full history + swipe-to-delete |
| CREATE | `Did I Feed The Dog/Views/AddEditPetSheet.swift` | Create/edit pet form |
| CREATE | `Did I Feed The Dog/Views/SettingsView.swift` | Settings: stock, notifications, about |
| CREATE | `Did I Feed The Dog/Views/SafetyGuideView.swift` | Searchable toxic foods list |
| MODIFY | `Did I Feed The Dog/ContentView.swift` | Thin wrapper → DashboardView |
| CREATE | `Did I Feed The DogTests/MealTypeTests.swift` | Unit tests for MealType |
| CREATE | `Did I Feed The DogTests/PetTests.swift` | Unit tests for Pet computed properties |
| CREATE | `Did I Feed The DogTests/FeedingEventTests.swift` | Unit tests for feeding logic |
| CREATE | `Did I Feed The DogTests/NotificationManagerTests.swift` | Unit tests for notification scheduling |

---

## Task 1: MealType Enum

**Files:**
- Create: `Did I Feed The Dog/Models/MealType.swift`
- Create: `Did I Feed The DogTests/MealTypeTests.swift`

- [ ] **Step 1.1: Write the failing tests**

Create `Did I Feed The DogTests/MealTypeTests.swift`:

```swift
import XCTest
@testable import Did_I_Feed_The_Dog

final class MealTypeTests: XCTestCase {
    func testPresetLabels() {
        XCTAssertEqual(MealType.morning.label, "Morning")
        XCTAssertEqual(MealType.evening.label, "Evening")
        XCTAssertEqual(MealType.breakfast.label, "Breakfast")
        XCTAssertEqual(MealType.lunch.label, "Lunch")
        XCTAssertEqual(MealType.dinner.label, "Dinner")
        XCTAssertEqual(MealType.snack.label, "Snack")
    }

    func testCustomLabel() {
        XCTAssertEqual(MealType.custom("Medication").label, "Medication")
        XCTAssertEqual(MealType.custom("").label, "")
    }

    func testPresetEmojis() {
        XCTAssertEqual(MealType.morning.emoji, "🌅")
        XCTAssertEqual(MealType.evening.emoji, "🌙")
        XCTAssertEqual(MealType.breakfast.emoji, "🍳")
        XCTAssertEqual(MealType.lunch.emoji, "🥗")
        XCTAssertEqual(MealType.dinner.emoji, "🍽️")
        XCTAssertEqual(MealType.snack.emoji, "🦴")
        XCTAssertEqual(MealType.custom("Anything").emoji, "✏️")
    }

    func testPresetsCount() {
        XCTAssertEqual(MealType.presets.count, 6)
    }
}
```

- [ ] **Step 1.2: Run to confirm failure**

In Xcode: Product → Test (⌘U). Expected: compile error — `MealType` not found.

- [ ] **Step 1.3: Create the enum**

Create `Did I Feed The Dog/Models/MealType.swift`:

```swift
import Foundation

enum MealType: Equatable {
    case morning, evening, breakfast, lunch, dinner, snack, custom(String)

    var label: String {
        switch self {
        case .morning:           return "Morning"
        case .evening:           return "Evening"
        case .breakfast:         return "Breakfast"
        case .lunch:             return "Lunch"
        case .dinner:            return "Dinner"
        case .snack:             return "Snack"
        case .custom(let text):  return text
        }
    }

    var emoji: String {
        switch self {
        case .morning:   return "🌅"
        case .evening:   return "🌙"
        case .breakfast: return "🍳"
        case .lunch:     return "🥗"
        case .dinner:    return "🍽️"
        case .snack:     return "🦴"
        case .custom:    return "✏️"
        }
    }

    static let presets: [MealType] = [.morning, .evening, .breakfast, .lunch, .dinner, .snack]
}
```

- [ ] **Step 1.4: Run tests to confirm pass**

In Xcode: ⌘U. Expected: `MealTypeTests` — 4 tests pass.

- [ ] **Step 1.5: Commit**

```bash
git add "Did I Feed The Dog/Models/MealType.swift" \
        "Did I Feed The DogTests/MealTypeTests.swift"
git commit -m "feat: add MealType enum with presets and custom label support"
```

---

## Task 2: Pet Model

**Files:**
- Delete: `Did I Feed The Dog/Item.swift`
- Create: `Did I Feed The Dog/Models/Pet.swift`
- Create: `Did I Feed The DogTests/PetTests.swift`

- [ ] **Step 2.1: Write the failing tests**

Create `Did I Feed The DogTests/PetTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class PetTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    func testAgeStringYearsAndMonths() throws {
        let cal = Calendar.current
        let birthday = cal.date(byAdding: .init(year: -3, month: -2), to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "3 years, 2 months")
    }

    func testAgeStringMonthsOnly() throws {
        let cal = Calendar.current
        let birthday = cal.date(byAdding: .month, value: -5, to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "5 months")
    }

    func testAgeStringYearsOnly() throws {
        let cal = Calendar.current
        let birthday = cal.date(byAdding: .year, value: -2, to: .now)!
        let pet = Pet(name: "Max", birthday: birthday)
        XCTAssertEqual(pet.ageString, "2 years")
    }

    func testIsFeedingOverdueWhenNeverFed() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        XCTAssertTrue(pet.isFeedingOverdue)
    }

    func testIsFeedingOverdueFalseWhenRecentlyFed() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let event = FeedingEvent(mealType: "Morning", pet: pet)
        context.insert(event)
        XCTAssertFalse(pet.isFeedingOverdue)
    }

    func testIsFeedingOverdueTrueAfter12Hours() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let oldDate = Date(timeIntervalSinceNow: -(13 * 3600))
        let event = FeedingEvent(timestamp: oldDate, mealType: "Morning", pet: pet)
        context.insert(event)
        XCTAssertTrue(pet.isFeedingOverdue)
    }

    func testFoodStockDoesNotGoBelowZero() throws {
        let pet = Pet(name: "Max", birthday: .now, foodStockCount: 0)
        context.insert(pet)
        pet.decrementStock()
        XCTAssertEqual(pet.foodStockCount, 0)
    }

    func testFoodStockDecrement() throws {
        let pet = Pet(name: "Max", birthday: .now, foodStockCount: 5)
        context.insert(pet)
        pet.decrementStock()
        XCTAssertEqual(pet.foodStockCount, 4)
    }

    func testTodaysFeedingCount() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let e1 = FeedingEvent(mealType: "Morning", pet: pet)
        let e2 = FeedingEvent(mealType: "Evening", pet: pet)
        let yesterday = Date(timeIntervalSinceNow: -(25 * 3600))
        let e3 = FeedingEvent(timestamp: yesterday, mealType: "Morning", pet: pet)
        context.insert(e1)
        context.insert(e2)
        context.insert(e3)
        XCTAssertEqual(pet.todaysFeedingCount, 2)
    }
}
```

- [ ] **Step 2.2: Run to confirm failure**

⌘U — expected: compile error, `Pet` not found.

- [ ] **Step 2.3: Delete Item.swift, create Pet.swift**

Delete `Did I Feed The Dog/Item.swift` (move to trash in Finder or `rm` in Terminal).

Create `Did I Feed The Dog/Models/Pet.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Pet {
    var id: UUID
    var name: String
    var birthday: Date
    var photoData: Data?
    var foodStockCount: Int
    @Relationship(deleteRule: .cascade) var feedingEvents: [FeedingEvent] = []

    init(name: String, birthday: Date, photoData: Data? = nil, foodStockCount: Int = 0) {
        self.id = UUID()
        self.name = name
        self.birthday = birthday
        self.photoData = photoData
        self.foodStockCount = foodStockCount
    }

    var ageString: String {
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        switch (years, months) {
        case (0, _):  return "\(months) month\(months == 1 ? "" : "s")"
        case (_, 0):  return "\(years) year\(years == 1 ? "" : "s")"
        default:      return "\(years) year\(years == 1 ? "" : "s"), \(months) month\(months == 1 ? "" : "s")"
        }
    }

    var lastFeedingEvent: FeedingEvent? {
        feedingEvents.max(by: { $0.timestamp < $1.timestamp })
    }

    var isFeedingOverdue: Bool {
        guard let last = lastFeedingEvent else { return true }
        return Date().timeIntervalSince(last.timestamp) >= 12 * 3600
    }

    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return feedingEvents.filter { $0.timestamp >= startOfDay }.count
    }

    func decrementStock() {
        foodStockCount = max(0, foodStockCount - 1)
    }
}
```

- [ ] **Step 2.4: Run tests to confirm pass**

⌘U — expected: `PetTests` — 7 tests pass. (FeedingEvent still needs creating — if tests fail to compile, proceed to Task 3 first, then re-run.)

- [ ] **Step 2.5: Commit**

```bash
git add "Did I Feed The Dog/Models/Pet.swift" \
        "Did I Feed The DogTests/PetTests.swift"
git rm "Did I Feed The Dog/Item.swift"
git commit -m "feat: add Pet SwiftData model with age, overdue, and stock helpers"
```

---

## Task 3: FeedingEvent Model

**Files:**
- Create: `Did I Feed The Dog/Models/FeedingEvent.swift`
- Create: `Did I Feed The DogTests/FeedingEventTests.swift`

- [ ] **Step 3.1: Write the failing tests**

Create `Did I Feed The DogTests/FeedingEventTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class FeedingEventTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    func testEventDefaultsToNow() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let before = Date()
        let event = FeedingEvent(mealType: "Morning", pet: pet)
        context.insert(event)
        let after = Date()
        XCTAssertGreaterThanOrEqual(event.timestamp, before)
        XCTAssertLessThanOrEqual(event.timestamp, after)
    }

    func testEventStoresMealType() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let event = FeedingEvent(mealType: "Custom Snack", pet: pet)
        context.insert(event)
        XCTAssertEqual(event.mealType, "Custom Snack")
    }

    func testCascadeDeleteRemovesEvents() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        let event = FeedingEvent(mealType: "Morning", pet: pet)
        context.insert(event)
        try context.save()
        context.delete(pet)
        try context.save()
        let events = try context.fetch(FetchDescriptor<FeedingEvent>())
        XCTAssertTrue(events.isEmpty)
    }
}
```

- [ ] **Step 3.2: Run to confirm failure**

⌘U — expected: compile error, `FeedingEvent` not found.

- [ ] **Step 3.3: Create FeedingEvent.swift**

Create `Did I Feed The Dog/Models/FeedingEvent.swift`:

```swift
import Foundation
import SwiftData

@Model
final class FeedingEvent {
    var timestamp: Date
    var mealType: String
    var pet: Pet?

    init(timestamp: Date = .now, mealType: String, pet: Pet) {
        self.timestamp = timestamp
        self.mealType = mealType
        self.pet = pet
    }
}
```

- [ ] **Step 3.4: Run all tests to confirm pass**

⌘U — expected: `MealTypeTests` (4), `PetTests` (7), `FeedingEventTests` (3) — all pass.

- [ ] **Step 3.5: Commit**

```bash
git add "Did I Feed The Dog/Models/FeedingEvent.swift" \
        "Did I Feed The DogTests/FeedingEventTests.swift"
git commit -m "feat: add FeedingEvent SwiftData model with cascade delete test"
```

---

## Task 4: App Entry Point

**Files:**
- Modify: `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift`

No tests for this task (system-level integration; tested by running the app).

- [ ] **Step 4.1: Replace Did_I_Feed_The_Dog_App.swift**

```swift
import SwiftUI
import SwiftData
import UserNotifications

@main
struct Did_I_Feed_The_Dog_App: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitContainerIdentifier: "iCloud.com.delon.DidIFeedTheDog"
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            container.mainContext.autosaveEnabled = true
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .task {
            await NotificationManager.shared.requestAuthorization()
        }
    }
}
```

> **Note:** CloudKit requires the `iCloud.com.delon.DidIFeedTheDog` container to be provisioned in the Apple Developer Portal and the iCloud capability added to the Xcode target. Until then, remove `cloudKitContainerIdentifier:` to run locally — SwiftData falls back to local-only storage silently.

- [ ] **Step 4.2: Build to confirm no errors**

In Xcode: Product → Build (⌘B). The build will fail because `NotificationManager` doesn't exist yet — that's expected. Proceed to Task 5.

- [ ] **Step 4.3: Commit**

```bash
git add "Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift"
git commit -m "feat: configure ModelContainer with CloudKit and provisional notification auth"
```

---

## Task 5: NotificationManager

**Files:**
- Create: `Did I Feed The Dog/Services/NotificationManager.swift`
- Create: `Did I Feed The DogTests/NotificationManagerTests.swift`

- [ ] **Step 5.1: Write the failing tests**

Create `Did I Feed The DogTests/NotificationManagerTests.swift`:

```swift
import XCTest
import UserNotifications
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class NotificationManagerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var center: UNUserNotificationCenter!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Pet.self, FeedingEvent.self, configurations: [config])
        context = container.mainContext
        center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    override func tearDown() async throws {
        center.removeAllPendingNotificationRequests()
        container = nil
        context = nil
    }

    func testLowStockNotificationIdentifierIsStable() throws {
        let pet = Pet(name: "Max", birthday: .now, foodStockCount: 3)
        context.insert(pet)
        let id1 = NotificationManager.shared.lowStockIdentifier(for: pet)
        let id2 = NotificationManager.shared.lowStockIdentifier(for: pet)
        XCTAssertEqual(id1, id2)
    }

    func testBirthdayNotificationIdentifierIsStable() throws {
        let pet = Pet(name: "Bailey", birthday: .now)
        context.insert(pet)
        let id1 = NotificationManager.shared.birthdayIdentifier(for: pet)
        let id2 = NotificationManager.shared.birthdayIdentifier(for: pet)
        XCTAssertEqual(id1, id2)
    }

    func testLowStockAndBirthdayIdentifiersDiffer() throws {
        let pet = Pet(name: "Max", birthday: .now)
        context.insert(pet)
        XCTAssertNotEqual(
            NotificationManager.shared.lowStockIdentifier(for: pet),
            NotificationManager.shared.birthdayIdentifier(for: pet)
        )
    }
}
```

- [ ] **Step 5.2: Run to confirm failure**

⌘U — expected: compile error, `NotificationManager` not found.

- [ ] **Step 5.3: Create NotificationManager.swift**

Create `Did I Feed The Dog/Services/NotificationManager.swift`:

```swift
import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .provisional]
        )
    }

    func lowStockIdentifier(for pet: Pet) -> String {
        "lowstock-\(pet.id.uuidString)"
    }

    func birthdayIdentifier(for pet: Pet) -> String {
        "birthday-\(pet.id.uuidString)"
    }

    func scheduleLowStockNotification(for pet: Pet) {
        let content = UNMutableNotificationContent()
        content.title = "🦴 Time to Restock \(pet.name)'s Food"
        content.body = "Only \(pet.foodStockCount) portion\(pet.foodStockCount == 1 ? "" : "s") remaining."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: lowStockIdentifier(for: pet),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleBirthdayNotification(for pet: Pet) {
        let identifier = birthdayIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let components = Calendar.current.dateComponents([.month, .day], from: pet.birthday)
        let content = UNMutableNotificationContent()
        content.title = "🎂 Happy Birthday \(pet.name)!"
        content.body = "Give \(pet.name) extra love and pets today!"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func removeBirthdayNotification(for pet: Pet) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [birthdayIdentifier(for: pet)]
        )
    }
}
```

- [ ] **Step 5.4: Run all tests to confirm pass**

⌘U — all 14 tests pass.

- [ ] **Step 5.5: Commit**

```bash
git add "Did I Feed The Dog/Services/NotificationManager.swift" \
        "Did I Feed The DogTests/NotificationManagerTests.swift"
git commit -m "feat: add NotificationManager for low-stock and birthday notifications"
```

---

## Task 6: ToxicFoods Static Data

**Files:**
- Create: `Did I Feed The Dog/Resources/ToxicFoods.swift`

No unit tests — this is inert static data.

- [ ] **Step 6.1: Create ToxicFoods.swift**

Create `Did I Feed The Dog/Resources/ToxicFoods.swift`:

```swift
import Foundation

struct SafetyEntry: Identifiable {
    let id = UUID()
    let name: String
    let danger: String
}

let toxicFoods: [SafetyEntry] = [
    SafetyEntry(name: "Chocolate",        danger: "Contains theobromine, which dogs can't metabolize. Can cause seizures and death even in small amounts."),
    SafetyEntry(name: "Grapes & Raisins", danger: "Can cause sudden kidney failure. Even small amounts are potentially fatal."),
    SafetyEntry(name: "Xylitol",          danger: "Artificial sweetener found in gum, candy, and peanut butter. Causes rapid insulin release and liver failure."),
    SafetyEntry(name: "Onions & Garlic",  danger: "Damages red blood cells, causing hemolytic anemia. All forms (raw, cooked, powdered) are toxic."),
    SafetyEntry(name: "Macadamia Nuts",   danger: "Causes weakness, vomiting, tremors, and hyperthermia within 12 hours."),
    SafetyEntry(name: "Avocado",          danger: "Persin in the fruit and pit can cause vomiting and diarrhea."),
    SafetyEntry(name: "Alcohol",          danger: "Even small amounts cause vomiting, disorientation, and can be fatal."),
    SafetyEntry(name: "Caffeine",         danger: "Found in coffee, tea, and energy drinks. Causes rapid heart rate, tremors, and seizures."),
    SafetyEntry(name: "Raw Yeast Dough",  danger: "Expands in the stomach and produces alcohol as it ferments, causing bloat and alcohol poisoning."),
    SafetyEntry(name: "Cooked Bones",     danger: "Splinter easily and can puncture the digestive tract. Raw bones are generally safer."),
    SafetyEntry(name: "Nutmeg",           danger: "Contains myristicin, causing disorientation, increased heart rate, and seizures."),
    SafetyEntry(name: "Salt",             danger: "Large amounts cause sodium ion poisoning — excessive thirst, vomiting, tremors, and seizures."),
    SafetyEntry(name: "Corn on the Cob",  danger: "The cob cannot be digested and causes intestinal blockage requiring emergency surgery."),
    SafetyEntry(name: "Cherries",         danger: "Pits, stems, and leaves contain cyanide. The flesh is non-toxic but the pits are dangerous."),
    SafetyEntry(name: "Peaches & Plums",  danger: "Pits contain cyanide and are a choking and intestinal blockage hazard."),
]
```

- [ ] **Step 6.2: Build to confirm no errors**

⌘B — clean build.

- [ ] **Step 6.3: Commit**

```bash
git add "Did I Feed The Dog/Resources/ToxicFoods.swift"
git commit -m "feat: add static toxic foods safety data"
```

---

## Task 7: ContentView Wrapper + DashboardView Shell

**Files:**
- Modify: `Did I Feed The Dog/ContentView.swift`
- Create: `Did I Feed The Dog/Views/DashboardView.swift`

- [ ] **Step 7.1: Create DashboardView.swift (shell)**

Create `Did I Feed The Dog/Views/DashboardView.swift`:

```swift
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.name) private var pets: [Pet]

    @State private var showAddPet = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(pets) { pet in
                        PetCard(pet: pet)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My Dogs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddPet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddPet) {
                AddEditPetSheet()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .overlay {
                if pets.isEmpty {
                    ContentUnavailableView(
                        "No Dogs Yet",
                        systemImage: "pawprint.fill",
                        description: Text("Tap + to add your first dog.")
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 7.2: Update ContentView.swift**

Replace the entire contents of `Did I Feed The Dog/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        DashboardView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Pet.self, FeedingEvent.self], inMemory: true)
}
```

- [ ] **Step 7.3: Build to confirm (partial — forward refs expected)**

⌘B — will show errors for `PetCard`, `AddEditPetSheet`, `SettingsView` not found. That's expected. Proceed to Task 8.

- [ ] **Step 7.4: Commit**

```bash
git add "Did I Feed The Dog/Views/DashboardView.swift" \
        "Did I Feed The Dog/ContentView.swift"
git commit -m "feat: add DashboardView shell and ContentView wrapper"
```

---

## Task 8: PetCard

**Files:**
- Create: `Did I Feed The Dog/Views/PetCard.swift`

- [ ] **Step 8.1: Create PetCard.swift**

Create `Did I Feed The Dog/Views/PetCard.swift`:

```swift
import SwiftUI
import SwiftData

struct PetCard: View {
    @AppStorage("lowStockUIWarning") private var lowStockUIWarning = true
    @AppStorage("lowStockThreshold") private var lowStockThreshold = 5

    let pet: Pet
    @State private var showFeedSheet = false

    private var recentEvents: [FeedingEvent] {
        pet.feedingEvents
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map { $0 }
    }

    private var lastFedBadgeColor: Color {
        pet.isFeedingOverdue ? Color(.systemRed).opacity(0.15) : Color(.systemGreen).opacity(0.15)
    }

    private var lastFedTextColor: Color {
        pet.isFeedingOverdue ? .red : .green
    }

    private var lastFedLabel: String {
        guard let last = pet.lastFeedingEvent else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: last.timestamp, relativeTo: .now)
    }

    private var isLowStock: Bool {
        lowStockUIWarning && pet.foodStockCount <= lowStockThreshold
    }

    var body: some View {
        NavigationLink(destination: PetDetailView(pet: pet)) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if isLowStock { lowStockBanner }
                statsRow
                if !recentEvents.isEmpty { miniHistory }
                feedButton
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFeedSheet) {
            LogFeedingSheet(pet: pet)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            petAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.title3).fontWeight(.bold)
                Text(pet.ageString)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            lastFedBadge
        }
        .padding(16)
    }

    private var petAvatar: some View {
        Group {
            if let data = pet.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var lastFedBadge: some View {
        VStack(spacing: 2) {
            Text("Last Fed")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(lastFedTextColor)
            Text(lastFedLabel)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(lastFedBadgeColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var lowStockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Low Food Stock")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                Text("Only \(pet.foodStockCount) portion\(pet.foodStockCount == 1 ? "" : "s") remaining — time to restock!")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell(
                title: "Food Stock",
                value: "\(pet.foodStockCount)",
                unit: "portions",
                accent: isLowStock ? .red : .primary
            )
            statCell(
                title: "Today's Meals",
                value: "\(pet.todaysFeedingCount)",
                unit: "feedings",
                accent: .primary
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func statCell(title: String, value: String, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value).font(.title2).fontWeight(.bold).foregroundStyle(accent)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var miniHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            ForEach(recentEvents) { event in
                HStack {
                    Text(emojiForMeal(event.mealType) + " " + event.mealType)
                        .font(.subheadline)
                    Spacer()
                    Text(RelativeDateTimeFormatter().localizedString(for: event.timestamp, relativeTo: .now))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var feedButton: some View {
        Button {
            showFeedSheet = true
        } label: {
            Label("Log Feeding", systemImage: "fork.knife")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func emojiForMeal(_ mealType: String) -> String {
        switch mealType {
        case "Morning":   return "🌅"
        case "Evening":   return "🌙"
        case "Breakfast": return "🍳"
        case "Lunch":     return "🥗"
        case "Dinner":    return "🍽️"
        case "Snack":     return "🦴"
        default:          return "✏️"
        }
    }
}
```

- [ ] **Step 8.2: Build to confirm (partial)**

⌘B — errors for `LogFeedingSheet`, `PetDetailView` not yet created. Expected. Continue.

- [ ] **Step 8.3: Commit**

```bash
git add "Did I Feed The Dog/Views/PetCard.swift"
git commit -m "feat: add PetCard with last-fed badge, low-stock banner, and mini history"
```

---

## Task 9: LogFeedingSheet

**Files:**
- Create: `Did I Feed The Dog/Views/LogFeedingSheet.swift`

- [ ] **Step 9.1: Create LogFeedingSheet.swift**

Create `Did I Feed The Dog/Views/LogFeedingSheet.swift`:

```swift
import SwiftUI
import SwiftData

struct LogFeedingSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lowStockPushEnabled") private var lowStockPushEnabled = true
    @AppStorage("lowStockThreshold") private var lowStockThreshold = 5

    let pet: Pet
    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("What meal is this?")
                    .font(.headline)
                    .padding(.horizontal)

                mealPicker

                if showCustomField {
                    TextField("Meal name (e.g. Medication)", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                Spacer()

                confirmButton
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .padding(.top, 24)
            .navigationTitle("Log Feeding — \(pet.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var mealPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 90))]
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
        } label: {
            VStack(spacing: 4) {
                Text(meal.emoji).font(.title2)
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
    }

    private var customChip: some View {
        Button {
            showCustomField = true
            selectedMealType = .custom("")
        } label: {
            VStack(spacing: 4) {
                Text("✏️").font(.title2)
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
    }

    private var confirmButton: some View {
        Button(action: logFeeding) {
            Label("Log Feeding", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canConfirm ? Color.green : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canConfirm)
    }

    private var canConfirm: Bool {
        if showCustomField { return !customLabel.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var resolvedMealLabel: String {
        showCustomField ? customLabel.trimmingCharacters(in: .whitespaces) : selectedMealType.label
    }

    private func logFeeding() {
        let event = FeedingEvent(mealType: resolvedMealLabel, pet: pet)
        modelContext.insert(event)
        pet.decrementStock()

        if lowStockPushEnabled && pet.foodStockCount <= lowStockThreshold {
            NotificationManager.shared.scheduleLowStockNotification(for: pet)
        }

        dismiss()
    }
}
```

- [ ] **Step 9.2: Build to confirm (partial)**

⌘B — errors for `PetDetailView` only. Expected.

- [ ] **Step 9.3: Commit**

```bash
git add "Did I Feed The Dog/Views/LogFeedingSheet.swift"
git commit -m "feat: add LogFeedingSheet with meal chip picker and stock decrement"
```

---

## Task 10: PetDetailView

**Files:**
- Create: `Did I Feed The Dog/Views/PetDetailView.swift`

- [ ] **Step 10.1: Create PetDetailView.swift**

Create `Did I Feed The Dog/Views/PetDetailView.swift`:

```swift
import SwiftUI
import SwiftData

struct PetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let pet: Pet

    private var sortedEvents: [FeedingEvent] {
        pet.feedingEvents.sorted { $0.timestamp > $1.timestamp }
    }

    private let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        List {
            if sortedEvents.isEmpty {
                ContentUnavailableView(
                    "No Feedings Yet",
                    systemImage: "fork.knife",
                    description: Text("Tap 'Log Feeding' on \(pet.name)'s card to get started.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(sortedEvents) { event in
                    HStack {
                        Text(emojiForMeal(event.mealType))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.mealType)
                                .font(.subheadline).fontWeight(.medium)
                            Text(dateFormatter.string(from: event.timestamp))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timeFormatter.localizedString(for: event.timestamp, relativeTo: .now))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .onDelete(perform: deleteEvents)
            }
        }
        .navigationTitle(pet.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            EditButton()
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedEvents[index])
        }
    }

    private func emojiForMeal(_ mealType: String) -> String {
        switch mealType {
        case "Morning":   return "🌅"
        case "Evening":   return "🌙"
        case "Breakfast": return "🍳"
        case "Lunch":     return "🥗"
        case "Dinner":    return "🍽️"
        case "Snack":     return "🦴"
        default:          return "✏️"
        }
    }
}
```

- [ ] **Step 10.2: Build to confirm (partial)**

⌘B — errors for `AddEditPetSheet`, `SettingsView` only. Expected.

- [ ] **Step 10.3: Commit**

```bash
git add "Did I Feed The Dog/Views/PetDetailView.swift"
git commit -m "feat: add PetDetailView with full history and swipe-to-delete"
```

---

## Task 11: AddEditPetSheet

**Files:**
- Create: `Did I Feed The Dog/Views/AddEditPetSheet.swift`

- [ ] **Step 11.1: Create AddEditPetSheet.swift**

Create `Did I Feed The Dog/Views/AddEditPetSheet.swift`:

```swift
import SwiftUI
import SwiftData
import PhotosUI

struct AddEditPetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("birthdayPushEnabled") private var birthdayPushEnabled = true

    var pet: Pet? // nil = create mode

    @State private var name = ""
    @State private var birthday = Date()
    @State private var foodStockCount = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dog Info") {
                    TextField("Name", text: $name)
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                }

                Section("Photo") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack {
                            if let data = photoData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "pawprint.fill")
                                    .font(.title2)
                                    .frame(width: 60, height: 60)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            Text(photoData == nil ? "Add Photo" : "Change Photo")
                                .foregroundStyle(.blue)
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            photoData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }
                }

                Section("Food Stock") {
                    Stepper("Portions: \(foodStockCount)", value: $foodStockCount, in: 0...999)
                    HStack {
                        Text("Or enter directly:")
                        Spacer()
                        TextField("0", value: $foodStockCount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }
            }
            .navigationTitle(pet == nil ? "Add Dog" : "Edit \(pet!.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { prefillIfEditing() }
        }
    }

    private func prefillIfEditing() {
        guard let pet else { return }
        name = pet.name
        birthday = pet.birthday
        foodStockCount = pet.foodStockCount
        photoData = pet.photoData
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let pet {
            pet.name = trimmedName
            pet.birthday = birthday
            pet.photoData = photoData
            pet.foodStockCount = foodStockCount
            if birthdayPushEnabled {
                NotificationManager.shared.scheduleBirthdayNotification(for: pet)
            }
        } else {
            let newPet = Pet(name: trimmedName, birthday: birthday, photoData: photoData, foodStockCount: foodStockCount)
            modelContext.insert(newPet)
            if birthdayPushEnabled {
                NotificationManager.shared.scheduleBirthdayNotification(for: newPet)
            }
        }
        dismiss()
    }
}
```

- [ ] **Step 11.2: Build to confirm (partial)**

⌘B — errors for `SettingsView` only. Expected.

- [ ] **Step 11.3: Commit**

```bash
git add "Did I Feed The Dog/Views/AddEditPetSheet.swift"
git commit -m "feat: add AddEditPetSheet with photo picker, birthday, and stock fields"
```

---

## Task 12: SafetyGuideView

**Files:**
- Create: `Did I Feed The Dog/Views/SafetyGuideView.swift`

- [ ] **Step 12.1: Create SafetyGuideView.swift**

Create `Did I Feed The Dog/Views/SafetyGuideView.swift`:

```swift
import SwiftUI

struct SafetyGuideView: View {
    @State private var searchText = ""

    private var filteredFoods: [SafetyEntry] {
        if searchText.isEmpty { return toxicFoods }
        return toxicFoods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.danger.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredFoods) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(entry.name)
                        .font(.headline)
                }
                Text(entry.danger)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Safety Guide")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search foods…")
    }
}
```

- [ ] **Step 12.2: Build to confirm (partial)**

⌘B — only `SettingsView` missing now. Expected.

- [ ] **Step 12.3: Commit**

```bash
git add "Did I Feed The Dog/Views/SafetyGuideView.swift"
git commit -m "feat: add SafetyGuideView with searchable toxic foods list"
```

---

## Task 13: SettingsView

**Files:**
- Create: `Did I Feed The Dog/Views/SettingsView.swift`

- [ ] **Step 13.1: Create SettingsView.swift**

Create `Did I Feed The Dog/Views/SettingsView.swift`:

```swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("lowStockUIWarning")    private var lowStockUIWarning = true
    @AppStorage("lowStockPushEnabled")  private var lowStockPushEnabled = true
    @AppStorage("birthdayPushEnabled")  private var birthdayPushEnabled = true
    @AppStorage("lowStockThreshold")    private var lowStockThreshold = 5

    @State private var editingPet: Pet?
    @State private var showAddPet = false

    var body: some View {
        Form {
            petsSection
            foodStockSection
            notificationsSection
            safetySection
            aboutSection
        }
        .navigationTitle("Settings")
        .sheet(item: $editingPet) { pet in
            AddEditPetSheet(pet: pet)
        }
        .sheet(isPresented: $showAddPet) {
            AddEditPetSheet()
        }
    }

    private var petsSection: some View {
        Section("Dogs") {
            ForEach(pets) { pet in
                Button {
                    editingPet = pet
                } label: {
                    HStack {
                        Text(pet.name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete(perform: deletePets)

            Button {
                showAddPet = true
            } label: {
                Label("Add Dog", systemImage: "plus.circle.fill")
            }
        }
    }

    private var foodStockSection: some View {
        Section("Food Stock Override") {
            ForEach(pets) { pet in
                HStack {
                    Text(pet.name)
                    Spacer()
                    Stepper("\(pet.foodStockCount) portions", value: Binding(
                        get: { pet.foodStockCount },
                        set: { pet.foodStockCount = max(0, $0) }
                    ), in: 0...999)
                }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Low Stock UI Warning", isOn: $lowStockUIWarning)
            Toggle("Low Stock Push Alert", isOn: $lowStockPushEnabled)
            Toggle("Birthday Push Alert", isOn: $birthdayPushEnabled)
            HStack {
                Text("Low Stock Threshold")
                Spacer()
                Stepper("\(lowStockThreshold) portions", value: $lowStockThreshold, in: 1...50)
            }
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink(destination: SafetyGuideView()) {
                Label("Toxic Foods Guide", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deletePets(at offsets: IndexSet) {
        for index in offsets {
            let pet = pets[index]
            NotificationManager.shared.removeBirthdayNotification(for: pet)
            modelContext.delete(pet)
        }
    }
}
```

- [ ] **Step 13.2: Build — expect clean**

⌘B — all types are now defined. Expect a clean build.

- [ ] **Step 13.3: Commit**

```bash
git add "Did I Feed The Dog/Views/SettingsView.swift"
git commit -m "feat: add SettingsView with pet management, stock override, and notification toggles"
```

---

## Task 14: Full Build, Run, and Smoke Test

- [ ] **Step 14.1: Run all unit tests**

⌘U — expected: all tests in `MealTypeTests`, `PetTests`, `FeedingEventTests`, `NotificationManagerTests` pass.

- [ ] **Step 14.2: Run app in simulator**

Select an iPhone simulator (e.g. iPhone 16), press ⌘R. Verify:
- Dashboard shows "No Dogs Yet" with pawprint icon
- Tap `+` → AddEditPetSheet appears
- Add a dog with name, birthday, and stock count → card appears on dashboard
- `Last Fed` badge shows **red** (never fed)
- Tap "Log Feeding" → LogFeedingSheet appears with meal chips
- Select a meal → badge turns **green**, mini history shows the event
- Tap again → stock decrements by 1
- Tap card → PetDetailView shows full history with swipe-to-delete
- Gear icon → SettingsView opens with pet list, stock stepper, toggles, and Safety Guide link
- Safety Guide → searchable toxic foods list

- [ ] **Step 14.3: Verify low-stock warning**

In Settings, set a pet's food stock to 3. Return to dashboard — confirm the orange low-stock banner appears on that pet's card.

- [ ] **Step 14.4: Final commit**

```bash
git add -A
git commit -m "feat: complete Did I Feed the Dog? v1 — all screens wired and building"
```

---

## CloudKit Activation (Post-MVP Step)

To enable family sync:
1. In Xcode, select the app target → Signing & Capabilities → add **iCloud** capability
2. Enable **CloudKit** and create container `iCloud.com.delon.DidIFeedTheDog`
3. In Apple Developer Portal, confirm the container is provisioned
4. Re-run the app — SwiftData will sync automatically across signed-in iCloud accounts
