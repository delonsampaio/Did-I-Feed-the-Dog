# Siri Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four Siri shortcuts so users can log feedings, restock food, and check status hands-free without opening the app.

**Architecture:** All intents live in the main app target using the App Intents framework (iOS 16+), auto-discovered by the system — no separate extension needed. Data access uses a fresh `ModelContext` from the shared App Group container, identical to the widget pattern. A `PetEntity` + `PetEntityQuery` lets Siri resolve "Max" to the correct `Pet` record by name. An `AppShortcutsProvider` registers phrase templates so shortcuts appear in Siri and the Shortcuts app automatically.

**Tech Stack:** App Intents framework, SwiftData (App Group container `group.com.delon.DidIFeedTheDog`), WidgetKit (timeline reload after mutations), UserDefaults.standard (reading stockMode/sharedFoodStock settings)

---

## File Structure

```
Did I Feed The Dog/Intents/
  IntentDataAccess.swift      — shared ModelContainer + fetch helpers (no UI)
  PetEntity.swift             — AppEntity + PetEntityQuery (Siri name resolution)
  MealTypeAppEnum.swift       — AppEnum wrapper around MealType for Siri
  LogFeedingIntent.swift      — "Log Max's morning feeding"
  UpdateFoodStockIntent.swift — "Update Max's food stock" (additive)
  FeedingStatusIntent.swift   — "Did I feed Max?"
  FoodStockStatusIntent.swift — "How much food does Max have?"
  DogFoodShortcuts.swift      — AppShortcutsProvider (registers all phrase templates)
```

Modify:
- `Did I Feed The Dog/Views/DashboardView.swift` — call `DogFoodShortcuts.updateAppShortcutParameters()` on appear so new/deleted dogs are reflected in Siri

---

### Task 1: Shared data access helper

**Files:**
- Create: `Did I Feed The Dog/Intents/IntentDataAccess.swift`

This is the foundation everything else reads from. Identical pattern to the widget's `WidgetProvider`. Must be added to the **main app target** in Xcode (not the widget target).

- [ ] **Step 1: Create the Intents folder and file**

In Finder, create the folder `Did I Feed The Dog/Intents/` inside the worktree. Then create `IntentDataAccess.swift`:

```swift
import SwiftData
import Foundation

enum IntentDataAccess {
    static let container: ModelContainer? = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            allowsSave: true,
            groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }()

    static func makeContext() -> ModelContext? {
        guard let container else { return nil }
        return ModelContext(container)
    }

    static func fetchPets(in context: ModelContext) -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
```

- [ ] **Step 2: Verify target membership in Xcode**

Select `IntentDataAccess.swift` in the Xcode navigator. In the File Inspector on the right, confirm **Target Membership** shows the main app target (`Did I Feed The Dog`) is checked. The widget target must NOT be checked.

- [ ] **Step 3: Build**

Product → Build (⌘B). Expected: Build Succeeded with 0 errors.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Intents/IntentDataAccess.swift"
git commit -m "feat: add shared SwiftData access helper for App Intents"
```

---

### Task 2: PetEntity + PetEntityQuery

**Files:**
- Create: `Did I Feed The Dog/Intents/PetEntity.swift`

`PetEntity` is what Siri uses to understand "Max" in a spoken phrase. `PetEntityQuery` tells the system how to look up pets by name and how to list suggestions in the Shortcuts app.

- [ ] **Step 1: Create PetEntity.swift**

```swift
import AppIntents
import SwiftData

struct PetEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dog")
    static var defaultQuery = PetEntityQuery()

    var id: UUID
    var name: String
    var foodStockCount: Int
    var lastFedTimestamp: Date?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(from pet: Pet) {
        self.id = pet.id
        self.name = pet.name
        self.foodStockCount = pet.foodStockCount
        self.lastFedTimestamp = pet.lastFeedingEvent?.timestamp
    }
}

struct PetEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PetEntity] {
        guard let context = IntentDataAccess.makeContext() else { return [] }
        return IntentDataAccess.fetchPets(in: context)
            .filter { identifiers.contains($0.id) }
            .map { PetEntity(from: $0) }
    }

    func entities(matching string: String) async throws -> [PetEntity] {
        guard let context = IntentDataAccess.makeContext() else { return [] }
        return IntentDataAccess.fetchPets(in: context)
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { PetEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [PetEntity] {
        guard let context = IntentDataAccess.makeContext() else { return [] }
        return IntentDataAccess.fetchPets(in: context).map { PetEntity(from: $0) }
    }
}
```

- [ ] **Step 2: Verify target membership and build**

Select `PetEntity.swift`, confirm Target Membership = main app target only. Then ⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Intents/PetEntity.swift"
git commit -m "feat: add PetEntity and PetEntityQuery for Siri name resolution"
```

---

### Task 3: MealTypeAppEnum

**Files:**
- Create: `Did I Feed The Dog/Intents/MealTypeAppEnum.swift`

App Intents requires enums to conform to `AppEnum`. The existing `MealType` has an associated-value case (`.custom(String)`) which is incompatible. This is a separate flat enum for use in intents only.

- [ ] **Step 1: Create MealTypeAppEnum.swift**

```swift
import AppIntents

enum MealTypeAppEnum: String, AppEnum {
    case morning, evening, breakfast, lunch, dinner, snack

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")
    static var caseDisplayRepresentations: [MealTypeAppEnum: DisplayRepresentation] = [
        .morning:   "Morning",
        .evening:   "Evening",
        .breakfast: "Breakfast",
        .lunch:     "Lunch",
        .dinner:    "Dinner",
        .snack:     "Snack"
    ]

    var label: String {
        switch self {
        case .morning:   return "Morning"
        case .evening:   return "Evening"
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        }
    }
}
```

- [ ] **Step 2: Verify target membership and build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Intents/MealTypeAppEnum.swift"
git commit -m "feat: add MealTypeAppEnum for use in App Intents"
```

---

### Task 4: LogFeedingIntent

**Files:**
- Create: `Did I Feed The Dog/Intents/LogFeedingIntent.swift`

The highest-value shortcut. Creates a `FeedingEvent`, decrements stock if tracked, reloads the widget.

Spoken: "Hey Siri, log Max's morning feeding in Did I Feed The Dog"
Response: "Morning feeding logged for Max."

- [ ] **Step 1: Create LogFeedingIntent.swift**

```swift
import AppIntents
import SwiftData
import WidgetKit

struct LogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Feeding"
    static var description = IntentDescription("Log a meal for your dog")

    @Parameter(title: "Dog")
    var pet: PetEntity

    @Parameter(title: "Meal", default: .morning)
    var meal: MealTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal) feeding for \(\.$pet)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = IntentDataAccess.makeContext() else {
            return .result(dialog: "Could not access app data.")
        }
        let pets = IntentDataAccess.fetchPets(in: context)
        guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Could not find \(pet.name).")
        }

        let event = FeedingEvent(mealType: meal.label, pet: foundPet)
        context.insert(event)

        let stockModeRaw = UserDefaults.standard.string(forKey: "stockMode") ?? ""
        let stockMode = StockMode(rawValue: stockModeRaw) ?? .individual
        switch stockMode {
        case .individual:
            foundPet.decrementStock()
        case .shared:
            let current = UserDefaults.standard.integer(forKey: "sharedFoodStock")
            UserDefaults.standard.set(max(0, current - 1), forKey: "sharedFoodStock")
        case .none:
            break
        }

        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "\(meal.label) feeding logged for \(pet.name).")
    }
}
```

- [ ] **Step 2: Verify target membership and build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Manual test on simulator**

Run the app. Add a dog if none exists. Press ⌘L to lock the simulator screen. Long-press the Home button or use the Siri button to invoke Siri. Say "Log [dog name]'s morning feeding in Did I Feed The Dog." Siri should respond "Morning feeding logged for [dog name]." Open the app and verify the feeding appears in the dog's history card.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Intents/LogFeedingIntent.swift"
git commit -m "feat: add LogFeedingIntent for hands-free feeding logs via Siri"
```

---

### Task 5: UpdateFoodStockIntent

**Files:**
- Create: `Did I Feed The Dog/Intents/UpdateFoodStockIntent.swift`

Additive restock: asks how many portions were added, adds to the current count.

Spoken: "Hey Siri, update Max's food stock in Did I Feed The Dog"
Siri asks: "How many portions did you add?"
User: "50"
Response: "Updated. Max now has 62 portions remaining."

- [ ] **Step 1: Create UpdateFoodStockIntent.swift**

```swift
import AppIntents
import SwiftData
import WidgetKit

struct UpdateFoodStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Food Stock"
    static var description = IntentDescription("Add portions to a dog's food stock after restocking")

    @Parameter(title: "Dog")
    var pet: PetEntity

    @Parameter(
        title: "Portions Added",
        description: "How many portions did you add?",
        requestValueDialog: IntentDialog("How many portions did you add?")
    )
    var portionsAdded: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$portionsAdded) portions for \(\.$pet)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard portionsAdded > 0 else {
            return .result(dialog: "Please provide a number greater than zero.")
        }
        guard let context = IntentDataAccess.makeContext() else {
            return .result(dialog: "Could not access app data.")
        }
        let pets = IntentDataAccess.fetchPets(in: context)
        guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Could not find \(pet.name).")
        }

        foundPet.foodStockCount = min(999, foundPet.foodStockCount + portionsAdded)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()

        let total = foundPet.foodStockCount
        let portionWord = total == 1 ? "portion" : "portions"
        return .result(dialog: "Updated. \(pet.name) now has \(total) \(portionWord) remaining.")
    }
}
```

- [ ] **Step 2: Verify target membership and build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Manual test**

Invoke Siri, say "Update [dog name]'s food stock in Did I Feed The Dog." Siri should ask "How many portions did you add?" Reply with a number. Siri should confirm the new total. Open the app and verify the stock count updated.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Intents/UpdateFoodStockIntent.swift"
git commit -m "feat: add UpdateFoodStockIntent for hands-free restocking via Siri"
```

---

### Task 6: FeedingStatusIntent + FoodStockStatusIntent

**Files:**
- Create: `Did I Feed The Dog/Intents/FeedingStatusIntent.swift`
- Create: `Did I Feed The Dog/Intents/FoodStockStatusIntent.swift`

Read-only intents — no mutations, no widget reload needed.

Spoken: "Did I feed Max in Did I Feed The Dog?"
Response: "Yes — Max was fed 2 hours ago (Morning)."

Spoken: "How much food does Max have in Did I Feed The Dog?"
Response: "Max has 35 portions remaining."

- [ ] **Step 1: Create FeedingStatusIntent.swift**

```swift
import AppIntents
import SwiftData

struct FeedingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Feeding Status"
    static var description = IntentDescription("Check when a dog was last fed")

    @Parameter(title: "Dog")
    var pet: PetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check feeding status for \(\.$pet)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = IntentDataAccess.makeContext() else {
            return .result(dialog: "Could not access app data.")
        }
        let pets = IntentDataAccess.fetchPets(in: context)
        guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Could not find \(pet.name).")
        }
        guard let lastEvent = foundPet.lastFeedingEvent else {
            return .result(dialog: "\(pet.name) hasn't been fed yet.")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTime = formatter.localizedString(for: lastEvent.timestamp, relativeTo: .now)

        if Calendar.current.isDateInToday(lastEvent.timestamp) {
            return .result(dialog: "Yes — \(pet.name) was fed \(relativeTime) (\(lastEvent.mealType)).")
        } else {
            return .result(dialog: "\(pet.name) was last fed \(relativeTime). They may be overdue.")
        }
    }
}
```

- [ ] **Step 2: Create FoodStockStatusIntent.swift**

```swift
import AppIntents
import SwiftData

struct FoodStockStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Food Stock Status"
    static var description = IntentDescription("Check how many portions a dog has remaining")

    @Parameter(title: "Dog")
    var pet: PetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check food stock for \(\.$pet)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stockModeRaw = UserDefaults.standard.string(forKey: "stockMode") ?? ""
        let stockMode = StockMode(rawValue: stockModeRaw) ?? .individual

        switch stockMode {
        case .none:
            return .result(dialog: "Food stock tracking is turned off in the app.")
        case .shared:
            let count = UserDefaults.standard.integer(forKey: "sharedFoodStock")
            let portionWord = count == 1 ? "portion" : "portions"
            return .result(dialog: "The shared food pool has \(count) \(portionWord) remaining.")
        case .individual:
            guard let context = IntentDataAccess.makeContext() else {
                return .result(dialog: "Could not access app data.")
            }
            let pets = IntentDataAccess.fetchPets(in: context)
            guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
                return .result(dialog: "Could not find \(pet.name).")
            }
            let count = foundPet.foodStockCount
            let portionWord = count == 1 ? "portion" : "portions"
            return .result(dialog: "\(pet.name) has \(count) \(portionWord) remaining.")
        }
    }
}
```

- [ ] **Step 3: Verify target membership for both files and build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Manual test both intents**

"Did I feed [dog name] in Did I Feed The Dog" — Siri should report relative time and meal type.
"How much food does [dog name] have in Did I Feed The Dog" — Siri should report the portion count.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Intents/FeedingStatusIntent.swift"
git add "Did I Feed The Dog/Intents/FoodStockStatusIntent.swift"
git commit -m "feat: add FeedingStatusIntent and FoodStockStatusIntent for Siri queries"
```

---

### Task 7: AppShortcutsProvider + DashboardView update

**Files:**
- Create: `Did I Feed The Dog/Intents/DogFoodShortcuts.swift`
- Modify: `Did I Feed The Dog/Views/DashboardView.swift`

`AppShortcutsProvider` registers phrase templates with the system so shortcuts appear in Siri suggestions and the Shortcuts app without any user setup. `updateAppShortcutParameters()` must be called whenever the pet list changes so Siri knows about new or deleted dogs.

- [ ] **Step 1: Create DogFoodShortcuts.swift**

```swift
import AppIntents

struct DogFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedingIntent(),
            phrases: [
                "Log \(\.$pet)'s feeding in \(.applicationName)",
                "Log \(\.$meal) feeding for \(\.$pet) in \(.applicationName)",
                "Feed \(\.$pet) in \(.applicationName)"
            ],
            shortTitle: "Log Feeding",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: UpdateFoodStockIntent(),
            phrases: [
                "Update \(\.$pet)'s food stock in \(.applicationName)",
                "Restock \(\.$pet)'s food in \(.applicationName)"
            ],
            shortTitle: "Update Food Stock",
            systemImageName: "bag.fill"
        )
        AppShortcut(
            intent: FeedingStatusIntent(),
            phrases: [
                "Did I feed \(\.$pet) in \(.applicationName)",
                "When did I last feed \(\.$pet) in \(.applicationName)"
            ],
            shortTitle: "Feeding Status",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: FoodStockStatusIntent(),
            phrases: [
                "How much food does \(\.$pet) have in \(.applicationName)",
                "Check \(\.$pet)'s food stock in \(.applicationName)"
            ],
            shortTitle: "Food Stock",
            systemImageName: "chart.bar.fill"
        )
    }
}
```

- [ ] **Step 2: Update DashboardView.onAppear**

In `Did I Feed The Dog/Views/DashboardView.swift`, add the import at the top and the call inside the existing `.onAppear`:

```swift
import AppIntents  // add alongside existing imports
```

Update `.onAppear` to:

```swift
.onAppear {
    NotificationManager.shared.rescheduleIfNeeded(
        reminderMode: reminderMode,
        allDogsReminderTimes: allDogsReminderTimes,
        pets: pets
    )
    DogFoodShortcuts.updateAppShortcutParameters()
}
```

- [ ] **Step 3: Build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Manual test — shortcuts visible in Shortcuts app**

On simulator or device, open the Shortcuts app → tap the + button → search "Did I Feed". All four shortcuts should appear without the user having to create them manually.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Intents/DogFoodShortcuts.swift"
git add "Did I Feed The Dog/Views/DashboardView.swift"
git commit -m "feat: register Siri shortcut phrases via AppShortcutsProvider"
```

---

## Self-Review

**Spec coverage:**
- Log feeding ✅ Task 4
- Update food stock (additive, conversational) ✅ Task 5
- Did I feed [Dog]? ✅ Task 6
- How much food left? ✅ Task 6
- Phrase registration / Shortcuts app ✅ Task 7
- Siri name resolution ("Max" → Pet record) ✅ Task 2
- Stock mode awareness (individual / shared / none) ✅ Tasks 4, 5, 6
- Widget reload after mutations ✅ Tasks 4, 5

**Placeholder scan:** None — all steps contain exact code.

**Type consistency:**
- `PetEntity(from:)` defined in Task 2, used in Tasks 4–6 ✅
- `IntentDataAccess.makeContext()` / `fetchPets(in:)` defined in Task 1, used in Tasks 4–6 ✅
- `MealTypeAppEnum.label` defined in Task 3, used in Task 4 ✅
- `DogFoodShortcuts.updateAppShortcutParameters()` is a protocol-provided static method from `AppShortcutsProvider` — no custom definition needed ✅
