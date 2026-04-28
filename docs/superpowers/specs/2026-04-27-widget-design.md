# Did I Feed the Dog? — Widget Extension Design Specification
**Date:** 2026-04-27
**Author:** Delon Sampaio
**Stack:** WidgetKit + SwiftData + App Groups (iOS 26+)

---

## 1. Goals

Add home screen and lock screen widgets so family members can check feeding status and jump to the log-feeding flow without opening the app.

---

## 2. Widget Families

| Family | Content | Tap action |
|---|---|---|
| `.systemSmall` | Most-overdue dog: avatar, name, last-fed badge | Opens `LogFeedingSheet` for that dog |
| `.systemMedium` | All dogs (up to 3): avatar, name, last-fed badge per row | Each row opens `LogFeedingSheet` for that dog |
| `.accessoryCircular` | Paw icon + "fed / total" count | Opens app to dashboard |
| `.accessoryRectangular` | Most-overdue dog name + "Last fed X ago" | Opens `LogFeedingSheet` for that dog |
| `.accessoryInline` | "🐾 N of M dogs fed" | Opens app to dashboard |

---

## 3. Data Sharing via App Groups

Both the app and the widget extension share the same SwiftData SQLite store via an App Group container. The App Group identifier is `group.com.delon.DidIFeedTheDog`.

**`ModelConfiguration` change (applied to both targets):**

```swift
ModelConfiguration(
    schema: schema,
    allowsSave: true,                                          // false in widget
    groupContainer: .identifier("group.com.delon.DidIFeedTheDog")
)
```

The `groupContainer` parameter places the store inside the App Group container automatically — no manual URL construction needed.

**Required in Xcode (user action):**
- App target → Signing & Capabilities → `+` → App Groups → `group.com.delon.DidIFeedTheDog`
- Widget extension target → same App Group capability

---

## 4. Deep Linking

URL scheme: `didfeedthedog://log?petId=<uuid-string>`

Widget links are constructed with SwiftUI's `Link` view:
```swift
Link(destination: URL(string: "didfeedthedog://log?petId=\(pet.id.uuidString)")!) {
    // row content
}
```

The app handles incoming URLs in `Did_I_Feed_The_Dog_App.swift` via `.onOpenURL`. A `@State var deepLinkPetId: UUID?` on the `App` struct is passed into the environment. `DashboardView` reads it, finds the matching `Pet`, and presents `LogFeedingSheet` as a sheet — then clears the value.

---

## 5. Timeline & Refresh Policy

```swift
let nextUpdate = Date().addingTimeInterval(3600)
let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
```

One entry per refresh cycle — the widget shows a static snapshot of the current state and asks WidgetKit to refresh after 1 hour. The app calls `WidgetCenter.shared.reloadAllTimelines()` from `LogFeedingSheet.logFeeding()` so the widget reflects the new feeding immediately after the user logs one.

---

## 6. Data Model for Widget

`@Model` types cannot be passed across process boundaries. The `TimelineEntry` holds lightweight plain structs:

```swift
struct PetSnapshot: Identifiable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
    let isFeedingOverdue: Bool   // lastFedDate == nil || now - lastFedDate >= 12h
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let pets: [PetSnapshot]       // sorted by most-overdue first
}
```

The `TimelineProvider` creates its own `ModelContainer` (same App Group config, `allowsSave: false`), runs a `FetchDescriptor<Pet>` with a `FetchDescriptor<FeedingEvent>` per pet, maps to `PetSnapshot`, and sorts by most-overdue.

---

## 7. File Structure

```
DidIFeedTheDogWidget/           (new Xcode widget extension target)
  DidIFeedTheDogWidgetBundle.swift    — @main WidgetBundle
  WidgetEntry.swift                   — PetSnapshot + WidgetEntry
  WidgetProvider.swift                — TimelineProvider (fetches from shared store)
  SmallWidgetView.swift               — .systemSmall layout
  MediumWidgetView.swift              — .systemMedium layout
  LockScreenWidgetViews.swift         — .accessoryCircular/Rectangular/Inline layouts
```

**Modified existing files:**
- `Did_I_Feed_The_Dog_App.swift` — update `ModelConfiguration` to use `groupContainer`; add `onOpenURL` handler; thread `deepLinkPetId` into environment
- `DashboardView.swift` — read `deepLinkPetId` from environment; present `LogFeedingSheet` when non-nil
- `LogFeedingSheet.swift` — call `WidgetCenter.shared.reloadAllTimelines()` after logging

**Shared with widget target (target membership in Xcode):**
- `Models/Pet.swift`
- `Models/FeedingEvent.swift`

---

## 8. Xcode Setup (user actions required)

1. **Add Widget Extension target:** File → New → Target → Widget Extension, named `DidIFeedTheDogWidget`, "Include Live Activity" = No
2. **App Group capability** on both targets (see §3)
3. **Target membership:** Add `Pet.swift` and `FeedingEvent.swift` to the widget target
4. **URL scheme:** App target → Info → URL Types → add scheme `didfeedthedog`

---

## 9. Edge Cases

- **No pets added yet:** `WidgetEntry.pets` is empty. All widget views show a placeholder: paw icon + "Add a dog to get started." Tapping opens the app to the dashboard.
- **Deep link pet not found** (pet was deleted after widget snapshot): `DashboardView` silently ignores the `deepLinkPetId` and presents the dashboard normally.
- **Widget snapshot stale > 1 hour:** WidgetKit auto-refreshes via the `.after` policy. Between refreshes, relative times may drift slightly — acceptable for this use case.

---

## 10. Out of Scope

- Live Activities
- Interactive widgets (iOS 17+ button actions inside widgets) — tap-to-log is handled via deep link, not inline interaction
- watchOS complication
