# Did I Feed the Dog? — Design Specification
**Date:** 2026-04-27
**Author:** Delon Sampaio
**Stack:** SwiftUI + SwiftData + CloudKit (iOS 26+)
**Architecture:** Vanilla SwiftData (Approach A — no ViewModel layer)

---

## 1. Goals

A high-polish, $0.99 utility app for multi-dog households to quickly log and track dog feedings. Family members share state in real time via CloudKit. The core UX loop must be fast enough to complete half-awake: open app → see which dog needs feeding → tap Feed → done.

---

## 2. Data Models

### `Pet` (`@Model`)
| Property | Type | Notes |
|---|---|---|
| `name` | `String` | Required |
| `birthday` | `Date` | Used for age display and birthday notification |
| `photoData` | `Data?` | Optional; nil shows a generated avatar |
| `foodStockCount` | `Int` | Portions remaining; decrements on each feeding |

**Relationship:** `@Relationship(.cascade) var feedingEvents: [FeedingEvent]`
Cascade delete — removing a pet removes all its feeding history.

### `FeedingEvent` (`@Model`)
| Property | Type | Notes |
|---|---|---|
| `timestamp` | `Date` | Set to `Date()` at the moment of logging |
| `mealType` | `String` | Raw string — stores both preset labels and custom text |
| `pet` | `Pet` | Back-reference to owning pet |

### `MealType` (not a SwiftData model — view-layer only)
A Swift enum used only in the UI to drive the meal picker:
```
case morning, evening, breakfast, lunch, dinner, snack, custom(String)
```
`var label: String` returns the display string. `mealType` on `FeedingEvent` stores the `.label` value directly, making custom labels first-class with no extra schema.

---

## 3. App Entry Point

**`Did_I_Feed_The_Dog_App.swift`**

- `ModelContainer` schema: `[Pet.self, FeedingEvent.self]`
- `ModelConfiguration`:
  - `isStoredInMemoryOnly: false`
  - `cloudKitContainerIdentifier: "iCloud.com.delon.DidIFeedTheDog"`
- After container creation: `container.mainContext.autosaveEnabled = true`
- At launch: `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .provisional])` — provisional authorization so no permission popup appears on first launch; notifications deliver silently to Notification Center until the user promotes them.

**CloudKit pre-requisite:** Requires an active Apple Developer Program membership and the iCloud container `iCloud.com.delon.DidIFeedTheDog` provisioned in the developer portal. The app compiles and runs locally without this — SwiftData falls back to local-only storage.

---

## 4. Navigation Structure

```
App
└── NavigationStack
    └── DashboardView                      ← root; ScrollView of PetCard
        ├── PetCard (per dog)
        │   ├── NavigationLink → PetDetailView   ← full event history + delete
        │   └── .sheet → LogFeedingSheet         ← meal picker + confirm
        ├── .sheet → AddEditPetSheet             ← create or edit a pet
        └── NavigationLink → SettingsView
            ├── Pet list (edit / delete)
            ├── Food stock manual override per pet
            ├── Notifications section
            │   ├── Toggle: Low stock UI warning
            │   ├── Toggle: Low stock push notification
            │   ├── Number field: Low stock threshold (default: 5)
            │   └── Toggle: Birthday push notification
            └── NavigationLink → SafetyGuideView ← searchable toxic foods list
```

---

## 5. Screen Specifications

### `DashboardView`
- `NavigationStack` root with title "My Dogs"
- Toolbar: `+` (AddEditPetSheet) and gear icon (SettingsView)
- Body: `ScrollView` containing a `VStack` of `PetCard` views, one per pet
- `@Query` fetches all `Pet` objects, sorted by `name`

### `PetCard`
Displays per-dog status at a glance:
- **Header row:** circular photo (or emoji avatar if no photo), name, age string, Last Fed badge
- **Last Fed badge:** green background if last feeding < 12 hours ago, red if ≥ 12 hours. Shows relative time via `RelativeDateTimeFormatter` (e.g. "30 min ago", "9 hrs ago")
- **Stats row:** Food Stock count (orange/red styling + warning banner when ≤ threshold), Today's Meals count (resets at midnight)
- **Low stock banner:** appears inline on the card when `foodStockCount ≤ threshold`. Shows "⚠️ Low Food Stock — Only N portions remaining"
- **Mini history:** last 3 `FeedingEvent` rows, each showing meal emoji + label + relative timestamp
- **Chevron/tap target:** tapping the card (or a trailing chevron) pushes `PetDetailView`
- **"Log Feeding" button:** full-width, green, presents `LogFeedingSheet` as `.sheet`

**Age calculation:** Derived from `pet.birthday` using `Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)`. Displayed as "N years, M months".

### `PetDetailView`
- Pushed via `NavigationLink` from `PetCard`
- Title: dog's name
- `@Query` filtered by pet, sorted by `timestamp` descending, no limit
- `List` with `ForEach`, showing full feeding history
- `.onDelete` (swipe-to-delete) removes a `FeedingEvent` from the model context — supports correcting accidental entries

### `LogFeedingSheet`
- Bottom sheet (`.sheet`) triggered by "Log Feeding" on `PetCard`
- Meal type picker: wrapping chip grid of preset options (Morning 🌅, Evening 🌙, Breakfast 🍳, Lunch 🥗, Dinner 🍽️, Snack 🦴)
- "Custom…" chip opens an inline `TextField` for free-text entry
- Confirm button: "Log Feeding"
  - Inserts `FeedingEvent(timestamp: .now, mealType: selectedLabel, pet: pet)`
  - Decrements `pet.foodStockCount` by 1 (floor at 0 — never goes negative)
  - Schedules low-stock notification check via `NotificationManager`
  - Dismisses the sheet

### `AddEditPetSheet`
- Used for both creating a new pet and editing an existing one
- Fields: name (`TextField`), birthday (`DatePicker`), photo (`PhotosPicker` — camera or library), initial food stock count (`Stepper` or `TextField`)
- On save: inserts or updates the `Pet` model, then calls `NotificationManager.scheduleBirthdayNotification(for: pet)` — this removes any existing birthday notification for the pet before scheduling the new one, so editing a birthday always produces a correctly-timed notification

### `SettingsView`
Five sections:
1. **Pets** — `List` of pets with edit (push `AddEditPetSheet`) and swipe-to-delete
2. **Food Stock** — per-pet `Stepper` + `TextField` for manual stock override (lets user sync the app with the physical food bag)
3. **Notifications** — three `Toggle` controls + threshold `TextField`; preferences stored in `UserDefaults` via `@AppStorage`
4. **Safety Guide** — `NavigationLink` to `SafetyGuideView`
5. **About** — app version from `Bundle.main.infoDictionary`

### `SafetyGuideView`
- Searchable list of foods toxic to dogs (e.g. chocolate, grapes, xylitol, onions, macadamia nuts, avocado, alcohol, caffeine, raw dough, cooked bones)
- `.searchable` modifier drives a filtered view of a static local array — no network required
- Each entry: food name + brief danger description
- Data is hardcoded in the app — no external dependency

---

## 6. Notification Architecture

All notification logic lives in a `NotificationManager` singleton (`final class NotificationManager`). It is not injected via environment — called directly from `LogFeedingSheet` and from the App entry point.

### Low-stock notification
- Triggered from `LogFeedingSheet` after each feeding
- If `pet.foodStockCount ≤ threshold` AND the push toggle is enabled: schedule a `UNNotificationRequest` with a 1-second delay (effectively immediate)
- Title: "🦴 Time to Restock [Pet Name]'s Food"
- Body: "Only [N] portions remaining."
- Identifier: `"lowstock-\(pet.persistentModelID)"` — overwritten each time so duplicates don't pile up

### Birthday notification
- Scheduled once per pet from `AddEditPetSheet` on save
- `UNCalendarNotificationTrigger` matching the pet's month and day, repeating annually
- Title: "🎂 Happy Birthday [Pet Name]!"
- Body: "[Pet Name] turns [age] today. Give them extra pets!"
- Identifier: `"birthday-\(pet.persistentModelID)"`

### Low-stock UI warning
- Driven purely by comparing `pet.foodStockCount` to the threshold at render time — no separate state needed
- The `PetCard` reads `@AppStorage("lowStockThreshold")` and `@AppStorage("lowStockUIWarning")` to decide whether to show the banner and apply red styling

---

## 7. UserDefaults Keys (`@AppStorage`)
| Key | Type | Default | Purpose |
|---|---|---|---|
| `lowStockUIWarning` | `Bool` | `true` | Show red indicator on card |
| `lowStockPushEnabled` | `Bool` | `true` | Send push when stock low |
| `birthdayPushEnabled` | `Bool` | `true` | Send push on birthday |
| `lowStockThreshold` | `Int` | `5` | Portions at which warnings trigger |

---

## 8. File Structure (Target: `Did I Feed The Dog/`)

```
Models/
  Pet.swift
  FeedingEvent.swift
Views/
  DashboardView.swift
  PetCard.swift
  PetDetailView.swift
  LogFeedingSheet.swift
  AddEditPetSheet.swift
  SettingsView.swift
  SafetyGuideView.swift
Services/
  NotificationManager.swift
Resources/
  ToxicFoods.swift       ← static array of SafetyEntry structs
Did_I_Feed_The_Dog_App.swift
ContentView.swift        ← thin wrapper: body returns DashboardView(); existing file kept to avoid Xcode project file churn
```

---

## 9. Out of Scope (v1)
- Feeding schedule / reminders (e.g. "remind me at 7am")
- Multiple food types per pet
- Vet appointment tracking
- Weight tracking
- watchOS or widget extensions
- iCloud backup restore UI (handled transparently by CloudKit)
