# CloudKit Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable iCloud/CloudKit sync so feedings logged on one household member's phone appear on all others.

**Architecture:** SwiftData's built-in CloudKit integration is enabled by switching `cloudKitDatabase: .none` to `.automatic` in both the app and widget `ModelConfiguration`. CloudKit requires every stored attribute to be optional or have an inline default value — so `Pet.name`, `Pet.birthday`, and `FeedingEvent.mealType` become `String?`/`Date?`, and `Pet.foodStockCount` and `FeedingEvent.timestamp` gain inline defaults. Every read site across views, intents, and the widget is updated to unwrap safely. A manual Xcode step (add iCloud + CloudKit capability) must be completed before the final task.

**Tech Stack:** SwiftData CloudKit integration (`cloudKitDatabase: .automatic`), existing App Group container (`group.com.delon.DidIFeedTheDog`), existing models `Pet` and `FeedingEvent`

---

## ⚠️ Manual Xcode prerequisite — do this before Task 7

Before running the app with CloudKit enabled you must add the capability in Xcode:

1. Select the **Did I Feed The Dog** target → **Signing & Capabilities**
2. Click **+ Capability** → add **iCloud**
3. Check the **CloudKit** checkbox
4. Under Containers, click **+** and create `iCloud.com.delon.DidIFeedTheDog`
5. Repeat steps 1–4 for the **DidIFeedTheDogWidget** target (same container)

Xcode writes the entitlement and registers the container in the developer portal automatically.

---

## File Structure

**Modified files only — no new files.**

```
Did I Feed The Dog/Models/
  Pet.swift               — name: String?, birthday: Date?, foodStockCount: Int = 0
  FeedingEvent.swift      — mealType: String?, timestamp: Date = .now

Did I Feed The Dog/Views/
  PetCard.swift           — unwrap pet.name, event.mealType
  PetDetailView.swift     — unwrap event.mealType, pet.name
  LogFeedingSheet.swift   — unwrap pet.name in title
  SettingsView.swift      — unwrap pet.name
  AddEditPetSheet.swift   — unwrap pet.name, pet.birthday in prefill

Did I Feed The Dog/Services/
  NotificationManager.swift — unwrap pet.name, pet.birthday

Did I Feed The Dog/Intents/
  PetEntity.swift           — unwrap pet.name
  LogFeedingIntent.swift    — unwrap pet.name in dialog
  FeedingStatusIntent.swift — unwrap lastEvent.mealType
  UpdateFoodStockIntent.swift — unwrap pet.name in dialog
  FoodStockStatusIntent.swift — unwrap pet.name in dialog

DidIFeedTheDogWidget/
  WidgetEntry.swift       — no change (PetSnapshot.name stays String)
  WidgetProvider.swift    — unwrap pet.name, enable cloudKitDatabase

Did I Feed The Dog/
  Did_I_Feed_The_Dog_App.swift — enable cloudKitDatabase: .automatic
```

---

### Task 1: Update Pet model

**Files:**
- Modify: `Did I Feed The Dog/Models/Pet.swift`

CloudKit requires `name` and `birthday` to be optional (no safe default exists for either). `foodStockCount` keeps its type but gains an inline default so CloudKit can hydrate records that predate the field.

- [ ] **Step 1: Replace Pet.swift with the updated model**

```swift
import Foundation
import SwiftData

@Model
final class Pet {
    var id: UUID = UUID()
    var name: String?
    var birthday: Date?
    var photoData: Data?
    var foodStockCount: Int = 0
    var feedingScheduleTimesRaw: String = ""
    @Relationship(deleteRule: .cascade) var feedingEvents: [FeedingEvent] = []

    var feedingScheduleTimes: [Int] {
        get { feedingScheduleTimesRaw.split(separator: ",").compactMap { Int($0) } }
        nonmutating set { feedingScheduleTimesRaw = newValue.map(String.init).joined(separator: ",") }
    }

    init(name: String? = nil, birthday: Date? = nil, photoData: Data? = nil, foodStockCount: Int = 0) {
        self.id = UUID()
        self.name = name
        self.birthday = birthday
        self.photoData = photoData
        self.foodStockCount = foodStockCount
        self.feedingScheduleTimesRaw = ""
    }

    var ageString: String {
        guard let birthday else { return "Age unknown" }
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        switch (years, months) {
        case (0, 0):  return "Less than a month"
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

- [ ] **Step 2: Build to confirm no model-layer errors**

Product → Build (⌘B). The compiler will show errors in every file that reads `pet.name` or `pet.birthday` without unwrapping — that is expected and will be fixed in later tasks.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Models/Pet.swift"
git commit -m "feat(cloudkit): make Pet.name and Pet.birthday optional for CloudKit compatibility"
```

---

### Task 2: Update FeedingEvent model

**Files:**
- Modify: `Did I Feed The Dog/Models/FeedingEvent.swift`

`mealType` has no safe default so it becomes `String?`. `timestamp` gets an inline `= Date.now` default — it stays non-optional, which avoids unwrapping timestamps throughout the codebase.

- [ ] **Step 1: Replace FeedingEvent.swift**

```swift
import Foundation
import SwiftData

@Model
final class FeedingEvent {
    var timestamp: Date = Date.now
    var mealType: String?
    var notes: String = ""
    var pet: Pet?

    init(timestamp: Date = .now, mealType: String? = nil, notes: String = "", pet: Pet) {
        self.timestamp = timestamp
        self.mealType = mealType
        self.notes = notes
        self.pet = pet
    }
}
```

- [ ] **Step 2: Build**

⌘B. More errors will appear at call sites that pass a `String` for `mealType` — those are fixed in later tasks. The model itself should show no errors.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Models/FeedingEvent.swift"
git commit -m "feat(cloudkit): make FeedingEvent.mealType optional, add timestamp inline default"
```

---

### Task 3: Fix views — PetCard, PetDetailView, LogFeedingSheet

**Files:**
- Modify: `Did I Feed The Dog/Views/PetCard.swift`
- Modify: `Did I Feed The Dog/Views/PetDetailView.swift`
- Modify: `Did I Feed The Dog/Views/LogFeedingSheet.swift`

- [ ] **Step 1: Fix PetCard.swift**

Two changes:

**Change 1** — header row pet name (line ~79):
```swift
// Before
Text(pet.name)
    .font(.title3).fontWeight(.bold)

// After
Text(pet.name ?? "Unknown")
    .font(.title3).fontWeight(.bold)
```

**Change 2** — mini history meal display (line ~192):
```swift
// Before
Text(emojiForMeal(event.mealType) + " " + event.mealType)

// After
Text(emojiForMeal(event.mealType ?? "") + " " + (event.mealType ?? "Feeding"))
```

- [ ] **Step 2: Fix PetDetailView.swift**

Four changes:

**Change 1** — empty state description (line ~44):
```swift
// Before
description: Text("Tap Log Feeding on \(pet.name)'s card to get started.")

// After
description: Text("Tap Log Feeding on \(pet.name ?? "Unknown")'s card to get started.")
```

**Change 2** — navigation title (line ~60):
```swift
// Before
.navigationTitle(pet.name)

// After
.navigationTitle(pet.name ?? "Unknown")
```

**Change 3** — emoji in eventRow (line ~67):
```swift
// Before
Text(emojiForMeal(event.mealType))
    .font(.title3)

// After
Text(emojiForMeal(event.mealType ?? ""))
    .font(.title3)
```

**Change 4** — meal type label in eventRow (line ~70):
```swift
// Before
Text(event.mealType)
    .font(.subheadline).fontWeight(.medium)

// After
Text(event.mealType ?? "Feeding")
    .font(.subheadline).fontWeight(.medium)
```

**Change 5** — meal name in EditNoteSheet title (inside the private EditNoteSheet struct):
```swift
// Before
Text(event.mealType)
    .font(.headline)

// After
Text(event.mealType ?? "Feeding")
    .font(.headline)
```

- [ ] **Step 3: Fix LogFeedingSheet.swift**

One change — navigation title:
```swift
// Before
.navigationTitle("Log Feeding — \(pet.name)")

// After
.navigationTitle("Log Feeding — \(pet.name ?? "Unknown")")
```

One change — the `FeedingEvent` initializer call in `logFeeding()`:
```swift
// Before
let event = FeedingEvent(mealType: resolvedMealLabel, notes: ..., pet: pet)

// After — resolvedMealLabel is String, passes fine as String? parameter, no change needed
let event = FeedingEvent(mealType: resolvedMealLabel, notes: ..., pet: pet)
```

No change needed on the FeedingEvent init call — Swift auto-promotes `String` to `String?`.

- [ ] **Step 4: Build**

⌘B. Expected: only errors in files not yet touched (SettingsView, AddEditPetSheet, NotificationManager, Intents, Widget).

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Views/PetCard.swift"
git add "Did I Feed The Dog/Views/PetDetailView.swift"
git add "Did I Feed The Dog/Views/LogFeedingSheet.swift"
git commit -m "fix(cloudkit): unwrap optional name and mealType in PetCard, PetDetailView, LogFeedingSheet"
```

---

### Task 4: Fix SettingsView, AddEditPetSheet, NotificationManager

**Files:**
- Modify: `Did I Feed The Dog/Views/SettingsView.swift`
- Modify: `Did I Feed The Dog/Views/AddEditPetSheet.swift`
- Modify: `Did I Feed The Dog/Services/NotificationManager.swift`

- [ ] **Step 1: Fix SettingsView.swift**

Three locations use `pet.name`:

**petsSection** (line ~48):
```swift
// Before
Text(pet.name).foregroundStyle(.primary)

// After
Text(pet.name ?? "Unknown").foregroundStyle(.primary)
```

**feedingRemindersSection** per-dog list (line ~193):
```swift
// Before
Text(pet.name).foregroundStyle(.primary)

// After
Text(pet.name ?? "Unknown").foregroundStyle(.primary)
```

**scheduleAllDogsReminders call** in `updateReminders()`:
```swift
// Before
NotificationManager.shared.scheduleAllDogsReminders(
    times: allDogsReminderTimes, petNames: pets.map(\.name)
)

// After
NotificationManager.shared.scheduleAllDogsReminders(
    times: allDogsReminderTimes, petNames: pets.map { $0.name ?? "Unknown" }
)
```

- [ ] **Step 2: Fix AddEditPetSheet.swift**

**Navigation title** (line ~110):
```swift
// Before
.navigationTitle(pet == nil ? "Add Dog" : "Edit \(pet!.name)")

// After
.navigationTitle(pet == nil ? "Add Dog" : "Edit \(pet?.name ?? "Unknown")")
```

**prefillIfEditing()** (lines ~128–129):
```swift
// Before
name = pet.name
birthday = pet.birthday

// After
name = pet.name ?? ""
birthday = pet.birthday ?? Date()
```

- [ ] **Step 3: Fix NotificationManager.swift**

**scheduleBirthdayNotification** — guard on birthday, unwrap name:
```swift
func scheduleBirthdayNotification(for pet: Pet) {
    guard let birthday = pet.birthday else { return }
    let identifier = birthdayIdentifier(for: pet)
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

    let components = Calendar.current.dateComponents([.month, .day], from: birthday)
    let content = UNMutableNotificationContent()
    content.title = "🎂 Happy Birthday \(pet.name ?? "your dog")!"
    content.body = "Give \(pet.name ?? "them") extra love and pets today!"
    content.sound = .default

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}
```

**scheduleLowStockNotification** — unwrap name:
```swift
func scheduleLowStockNotification(for pet: Pet, stockCount: Int? = nil) {
    let count = stockCount ?? pet.foodStockCount
    let content = UNMutableNotificationContent()
    content.title = "🦴 Time to Restock \(pet.name ?? "your dog")'s Food"
    content.body = "Only \(count) portion\(count == 1 ? "" : "s") remaining."
    content.sound = .default
    // ... rest unchanged
}
```

**scheduleAllDogsReminders** — petNames parameter is already `[String]`, no change needed there.

**schedulePerDogReminders** — unwrap name:
```swift
func schedulePerDogReminders(for pet: Pet, times: [Int]) {
    removePerDogReminders(for: pet)
    for (i, minutes) in times.enumerated() {
        scheduleReminder(
            identifier: "feeding-\(pet.id.uuidString)-\(i)",
            title: "Time to Feed \(pet.name ?? "your dog")",
            body: "Don't forget \(pet.name ?? "their") feeding!",
            minutesSinceMidnight: minutes
        )
    }
}
```

- [ ] **Step 4: Build**

⌘B. Expected: errors only in Intents and Widget files.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Views/SettingsView.swift"
git add "Did I Feed The Dog/Views/AddEditPetSheet.swift"
git add "Did I Feed The Dog/Services/NotificationManager.swift"
git commit -m "fix(cloudkit): unwrap optional pet properties in SettingsView, AddEditPetSheet, NotificationManager"
```

---

### Task 5: Fix Intents

**Files:**
- Modify: `Did I Feed The Dog/Intents/PetEntity.swift`
- Modify: `Did I Feed The Dog/Intents/LogFeedingIntent.swift`
- Modify: `Did I Feed The Dog/Intents/UpdateFoodStockIntent.swift`
- Modify: `Did I Feed The Dog/Intents/FeedingStatusIntent.swift`
- Modify: `Did I Feed The Dog/Intents/FoodStockStatusIntent.swift`

- [ ] **Step 1: Fix PetEntity.swift**

`PetEntity.name` is `String` (non-optional — Siri needs a display name). The `init(from:)` must unwrap `pet.name`:

```swift
init(from pet: Pet) {
    self.id = pet.id
    self.name = pet.name ?? "Unknown"   // unwrap here
    self.foodStockCount = pet.foodStockCount
    self.lastFedTimestamp = pet.lastFeedingEvent?.timestamp
}
```

- [ ] **Step 2: Fix LogFeedingIntent.swift**

Unwrap `pet.name` in dialogs (two places):
```swift
// Before
return .result(dialog: "Could not find \(pet.name).")
// After
return .result(dialog: "Could not find \(pet.name).")  // pet.name here is PetEntity.name: String — no change needed
```

`pet` in the intent is a `PetEntity` (with `name: String`), not a `Pet` model — no change needed in the dialog lines. However the `FeedingEvent` initializer call:
```swift
// mealType is meal.label: String, auto-promotes to String? — no change needed
let event = FeedingEvent(mealType: meal.label, pet: foundPet)
```

- [ ] **Step 3: Fix UpdateFoodStockIntent.swift**

Same as LogFeedingIntent — `pet` is `PetEntity` with `name: String`, dialogs are already fine. No changes needed.

- [ ] **Step 4: Fix FeedingStatusIntent.swift**

`lastEvent.mealType` is now `String?` — unwrap in the dialog:

```swift
// Before
return .result(dialog: "Yes — \(pet.name) was fed \(relativeTime) (\(lastEvent.mealType)).")

// After
return .result(dialog: "Yes — \(pet.name) was fed \(relativeTime) (\(lastEvent.mealType ?? "a meal")).")
```

- [ ] **Step 5: Fix FoodStockStatusIntent.swift**

No changes needed — this intent reads `foundPet.foodStockCount` (non-optional with default) and `pet.name` from `PetEntity` (non-optional).

- [ ] **Step 6: Build**

⌘B. Expected: errors only in Widget files.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Intents/PetEntity.swift"
git add "Did I Feed The Dog/Intents/FeedingStatusIntent.swift"
git commit -m "fix(cloudkit): unwrap optional mealType in Intents"
```

---

### Task 6: Fix Widget

**Files:**
- Modify: `DidIFeedTheDogWidget/WidgetProvider.swift`

`PetSnapshot.name` is `String` (non-optional — widget views display it directly). Unwrap `pet.name` at the mapping point.

- [ ] **Step 1: Fix WidgetProvider.swift — unwrap pet.name**

In `fetchPetSnapshots()`, the `PetSnapshot` initializer call:

```swift
// Before
return PetSnapshot(id: pet.id, name: pet.name,
                   photoData: pet.photoData, lastFedDate: lastDate)

// After
return PetSnapshot(id: pet.id, name: pet.name ?? "Unknown",
                   photoData: pet.photoData, lastFedDate: lastDate)
```

- [ ] **Step 2: Build**

⌘B. Expected: Build Succeeded with 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "DidIFeedTheDogWidget/WidgetProvider.swift"
git commit -m "fix(cloudkit): unwrap optional pet.name in WidgetProvider"
```

---

### Task 7: Enable CloudKit

**Files:**
- Modify: `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift`
- Modify: `DidIFeedTheDogWidget/WidgetProvider.swift`

⚠️ **Complete the manual Xcode prerequisite (adding iCloud + CloudKit capability to both targets) before this task. If the capability is not added, the app will crash on launch.**

- [ ] **Step 1: Update Did_I_Feed_The_Dog_App.swift**

```swift
// Before
let config = ModelConfiguration(
    schema: schema,
    allowsSave: true,
    groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
    cloudKitDatabase: .none
)

// After
let config = ModelConfiguration(
    schema: schema,
    allowsSave: true,
    groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
    cloudKitDatabase: .automatic
)
```

- [ ] **Step 2: Update WidgetProvider.swift**

```swift
// Before
let config = ModelConfiguration(
    schema: schema,
    allowsSave: false,
    groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
    cloudKitDatabase: .none
)

// After
let config = ModelConfiguration(
    schema: schema,
    allowsSave: false,
    groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
    cloudKitDatabase: .automatic
)
```

- [ ] **Step 3: Build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Run on a real device and verify sync**

Run on two devices signed into the same iCloud account. Log a feeding on device A. Within 30–60 seconds the feeding should appear on device B after opening the app (CloudKit sync is not instant).

- [ ] **Step 5: Commit and push**

```bash
git add "Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift"
git add "DidIFeedTheDogWidget/WidgetProvider.swift"
git commit -m "feat: enable CloudKit sync via cloudKitDatabase: .automatic"
git push
```

---

## Self-Review

**Spec coverage:**
- `Pet.name: String?` ✅ Task 1
- `Pet.birthday: Date?` ✅ Task 1
- `Pet.foodStockCount: Int = 0` (inline default) ✅ Task 1
- `FeedingEvent.mealType: String?` ✅ Task 2
- `FeedingEvent.timestamp: Date = .now` (inline default) ✅ Task 2
- All view read sites unwrapped ✅ Tasks 3–4
- NotificationManager unwrapped ✅ Task 4
- Intents unwrapped ✅ Task 5
- Widget unwrapped ✅ Task 6
- `cloudKitDatabase: .automatic` in App + Widget ✅ Task 7
- Manual Xcode prerequisite documented ✅ Task 7 header

**Placeholder scan:** None found — all steps contain exact code.

**Type consistency:**
- `PetEntity.name: String` (non-optional) — init(from:) unwraps `pet.name ?? "Unknown"` ✅ Task 5
- `PetSnapshot.name: String` (non-optional) — WidgetProvider unwraps `pet.name ?? "Unknown"` ✅ Task 6
- `FeedingEvent(mealType: String?)` — all callers pass `String` which auto-promotes ✅ Tasks 3, 5
- `Pet(name: String?)` — all callers pass `String` which auto-promotes ✅ Task 1
