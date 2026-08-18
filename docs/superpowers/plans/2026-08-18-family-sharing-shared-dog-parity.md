# Family Sharing — Phase 7 Shared-Dog CRUD Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any participant on a shared dog (owner or not, Pro or not) gets the same data-editing power an owner has on an owned dog: browse/filter/edit/delete meal and medication history, edit the dog's core fields, toggle fasting, and manage medications — today `SharedPetCard` only supports logging, with no history screen and no edit sheet at all.

**Architecture:** Three new views mirroring the owned-dog equivalents feature-for-feature (`SharedPetDetailView` ↔ `PetDetailView`, `EditSharedPetSheet` ↔ `AddEditPetSheet`, `EditSharedMedicationSheet` ↔ `AddEditMedicationSheet`), adapted from SwiftData to Core Data and with all `NotificationManager`/`WidgetDataWriter`/Siri-shortcut side effects dropped (out of scope this phase — see Global Constraints). Two small existing private types (`AvatarPickerSheet`, `MealFilterSheet`) get de-privatized for direct reuse instead of duplication. No new Core Data model fields; no `SharedSyncEngine`/`CKRecordMapper` changes — both are already generic per-entity/per-attribute.

**Tech Stack:** Swift, SwiftUI, Core Data, CloudKit (unchanged sync layer), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-18-family-sharing-shared-dog-parity-design.md`

## Global Constraints

- **Design source:** `docs/superpowers/specs/2026-08-18-family-sharing-shared-dog-parity-design.md`.
- **Any participant, any Pro status, full data CRUD** on a shared dog — no `entitlements.isPro` checks anywhere in the new code, matching the existing precedent (`SharedPetCard`'s Log Meal/Log Medication/Update Stock are already ungated). Only "Share this dog"/"Stop sharing" stay `isOwner`-gated, unchanged.
- **Notifications, widget, and Siri shortcuts are out of scope.** Do not call `NotificationManager`, `WidgetDataWriter.write`, `RemindersCoordinator`, or `DogFoodShortcuts` anywhere in new shared-dog code. `SharedMedication.notificationsEnabled`/`reminderMinutesRaw` are not exposed in `EditSharedMedicationSheet`'s UI at all this phase (no "Notifications" section).
- **Ruling on a spec/codebase mismatch found while planning:** the spec's `EditSharedPetSheet` bullet mentions "feeding schedule times." Reading the actual owned-dog code shows `AddEditPetSheet` does **not** have a feeding-schedule editor in its Form at all — per-dog schedule editing lives in `SettingsView.swift`, a separate screen tied to `reminderMode == .perDog`'s notification scheduling (out of scope this phase, see above). `EditSharedPetSheet` therefore mirrors `AddEditPetSheet`'s *actual* fields only (photo, name, birthday, fasting, food stock, mute-notifications) with no schedule editor — this is not a scope cut, it's correcting an inaccuracy in the spec's prose against what the owned-dog screen actually contains. `feedingScheduleTimesRaw` keeps whatever value migrated in at share time; editing it for shared dogs is deferred alongside the rest of the notification-scheduling subsystem.
- **No new Core Data model fields.** Every field these screens need already exists on `SharedPet`/`SharedMedication`/`SharedFeedingEvent`/`SharedMedicationLog`.
- **Deleting a feeding event that deducted stock needs no "restore portions" branch.** `SharedPet.effectiveFoodStockCount` is derived from `feedingEvents`; removing the event alone restores the derived count. The bulk-delete confirmation dialog and swipe actions in `SharedPetDetailView` have one fewer option than `PetDetailView`'s owned-dog equivalent as a result — this is intentional, not a missing feature.
- **Never `fatalError`.** Surface Core Data save failures as a simple alert with `error.localizedDescription`, matching every prior phase.
- **Flag-gated:** `SharingFeatureFlag.isFoundationEnabled` — unchanged pattern; shared dogs themselves already don't render without the flag (upstream in `DashboardView`), so no additional flag checks are needed inside the new views themselves (matching how `SharedPetDetailView`/`EditSharedPetSheet`/`EditSharedMedicationSheet` are only ever reachable through an already-flag-gated `SharedPetCard`). `SharedPetCard`'s own body keeps its existing `SharingFeatureFlag.isFoundationEnabled` checks unchanged.

### Environment / mechanics (every task)

- New files → `Did I Feed The Dog/Views/` (all five new/modified views in this plan are Views, not services). Xcode 16 filesystem-synchronized groups — **no `project.pbxproj` edits**.
- **Swift 6 `-default-isolation=MainActor` strict concurrency is enforced.** These are all SwiftUI `View`s (implicitly MainActor) — no explicit `@MainActor` annotation needed on the structs themselves, matching `SharedPetCard`/`SharedRestockSheet`'s existing pattern.
- **Single simulator (limited RAM — never spawn parallel clones).** Test:
  ```
  xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:"Did I Feed The DogTests/<ClassName>" 2>&1 | tail -40
  ```
  Build:
  ```
  xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
  ```
  If the simulator reports "failed preflight checks" / "Busy" on launch, run `xcrun simctl boot "iPhone 17 Pro"` and retry — this is an environment flake, not a code issue.
- **Known-flaky baseline:** ~14 pre-existing/environmental failures (`AppSettingsTests`, `FeedingEventTests`, `FeedingLogServiceTests`, `LoggedByTests`, three `PetTests`), confirmed present on unmodified `main` via `git stash` comparison in the same-day debugging session — judge success by new tests passing + no NEW failures in touched files, not a fully-green suite.
- **SourceKit's live "Cannot find type/module in scope" diagnostics are unreliable on this project** (confirmed stale-index behavior on every file touched in every phase so far) — always verify with a real `xcodebuild` run, never trust the editor's live error list.
- Verify exact Core Data/SwiftUI API shapes against the SDK (use the LSP tool) if the compiler disagrees with a signature below; adapt labels minimally, keeping behavior, and note it.

---

### Task 1: De-privatize two reusable sheets + `EditSharedPetSheet`

**Files:**
- Modify: `Did I Feed The Dog/Views/AddEditPetSheet.swift`
- Modify: `Did I Feed The Dog/Views/PetDetailView.swift`
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`
- Create: `Did I Feed The Dog/Views/EditSharedPetSheet.swift`

**Interfaces:**
- Consumes: `SharedPet` (existing), `AvatarPickerSheet(selectedAvatarName: Binding<String?>, photoData: Binding<Data?>)` (existing, made non-private by this task).
- Produces: `EditSharedPetSheet(pet: SharedPet)`, used by Task 5's `SharedPetCard`. `MealFilterSheet` made non-private, used by Task 3.

`AvatarPickerSheet` (in `AddEditPetSheet.swift`) and `MealFilterSheet` (in `PetDetailView.swift`) are both `private struct`s whose entire implementation is Pet-agnostic (they only touch primitive `Binding`s, `DefaultAvatars`, and `AppConstants`) — de-privatizing them avoids duplicating ~150 lines of photo-compression and filter-UI code for the shared-dog side.

- [ ] **Step 1: De-privatize `AvatarPickerSheet`**

In `Did I Feed The Dog/Views/AddEditPetSheet.swift`, change:
```swift
private struct AvatarPickerSheet: View {
```
to:
```swift
struct AvatarPickerSheet: View {
```

- [ ] **Step 2: De-privatize `MealFilterSheet`**

In `Did I Feed The Dog/Views/PetDetailView.swift`, change:
```swift
private struct MealFilterSheet: View {
```
to:
```swift
struct MealFilterSheet: View {
```

- [ ] **Step 3: Build to verify both changes compile with no access-level errors**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Add `SharedMedication.frequencyLabel`**

In `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`, add this new extension after the existing `extension SharedPet { var effectiveFoodStockCount: Int { ... } }` block, at the end of the file:

```swift

extension SharedMedication {
    /// Mirrors Medication.frequencyLabel so SharedPetDetailView's medication row can display
    /// this without a second copy of the switch statement.
    var frequencyLabel: String {
        switch frequencyHours {
        case 8:   return "3 times daily"
        case 12:  return "Twice daily"
        case 24:  return "Daily"
        case 48:  return "Every 2 days"
        case 72:  return "Every 3 days"
        case 168: return "Weekly"
        case 720: return "Monthly"
        default:  return "Every \(frequencyHours)h"
        }
    }
}
```

- [ ] **Step 5: Create `EditSharedPetSheet`**

Create `Did I Feed The Dog/Views/EditSharedPetSheet.swift`:

```swift
import CoreData
import PhotosUI
import SwiftUI

/// Edit-only equivalent of AddEditPetSheet for shared dogs — a SharedPet is only ever created by
/// migration (SharePreparationController), never fresh through this sheet, so there is no "Add"
/// mode. Mirrors AddEditPetSheet's actual Form fields exactly: photo, name, birthday, fasting,
/// food stock (always shown here — unlike the owned sheet, never behind a Pro paywall), and mute
/// notifications (stored only; no NotificationManager call, matching this phase's scope).
struct EditSharedPetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet

    @State private var name = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var foodStockCount = 0
    @State private var photoData: Data?
    @State private var selectedAvatarName: String?
    @State private var showAvatarPicker = false
    @State private var isFasting = false
    @State private var notificationsMuted = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Dog Info") {
                    Button { showAvatarPicker = true } label: {
                        HStack(spacing: 14) {
                            photoPreview
                            Text(photoData == nil ? "Add Photo" : "Change Photo")
                                .foregroundStyle(.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    TextField("Name", text: $name)
                    Toggle("Add Birthday", isOn: $hasBirthday.animation())
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                }

                Section("Health") {
                    Toggle("Fasting Mode", isOn: $isFasting)
                        .tint(.red)
                    if isFasting {
                        Text("A DO NOT FEED warning will appear on the dashboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(
                    header: Text("Food Stock"),
                    footer: Text("Snack and Treat meals do not reduce the portion count.")
                ) {
                    Stepper(value: $foodStockCount, in: 0...999) {
                        HStack {
                            Text("Portions")
                            Spacer()
                            Text("\(foodStockCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Type a number")
                        Spacer()
                        TextField("0", value: $foodStockCount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }

                Section("Alerts & Reminders") {
                    Toggle("Mute Notifications", isOn: $notificationsMuted)
                }
            }
            .navigationTitle("Edit \(pet.name ?? "Unknown")")
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
            .onAppear { prefill() }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerSheet(selectedAvatarName: $selectedAvatarName, photoData: $photoData)
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
    }

    private var photoPreview: some View {
        Group {
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
                    .accessibilityHidden(true)
            }
        }
    }

    private func prefill() {
        name = pet.name ?? ""
        if let stored = pet.birthday {
            hasBirthday = true
            birthday = stored
        } else {
            hasBirthday = false
            birthday = Date()
        }
        foodStockCount = pet.effectiveFoodStockCount
        photoData = pet.photoData
        isFasting = pet.isFasting
        notificationsMuted = pet.notificationsMuted
    }

    private func save() {
        guard let context = pet.managedObjectContext else {
            saveErrorMessage = "Failed to save: no context"
            showSaveError = true
            return
        }
        pet.name = name.trimmingCharacters(in: .whitespaces)
        pet.birthday = hasBirthday ? birthday : nil
        pet.photoData = photoData
        pet.isFasting = isFasting
        pet.notificationsMuted = notificationsMuted
        // Editing the stock number here is a restock, same as SharedRestockSheet: reset the
        // baseline so effectiveFoodStockCount reads back exactly what was typed. Only touch the
        // baseline if the value actually changed, so saving unrelated fields (name, photo, ...)
        // doesn't silently discard deductions recorded since the last real restock.
        if foodStockCount != pet.effectiveFoodStockCount {
            pet.foodStockCount = Int64(foodStockCount)
            pet.foodStockBaselineDate = .now
        }
        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
```

No dedicated unit test for this task — the one real branch (baseline reset only when the stock value changed) reads `pet.effectiveFoodStockCount`, already fully covered by `SharedPetStockTests` from Phase 6; everything else is direct field assignment with no new decision logic. Verified by build, matching the convention used for equivalently-shaped Phase 6 tasks (`SharedRestockSheet`, `LogSharedMedicationSheet`).

- [ ] **Step 6: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Views/AddEditPetSheet.swift" "Did I Feed The Dog/Views/PetDetailView.swift" "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The Dog/Views/EditSharedPetSheet.swift"
git commit -m "feat: EditSharedPetSheet for editing a shared dog's core fields (#57 phase 7)"
```

---

### Task 2: `EditSharedMedicationSheet`

**Files:**
- Create: `Did I Feed The Dog/Views/EditSharedMedicationSheet.swift`

**Interfaces:**
- Consumes: `SharedPet`, `SharedMedication`, `SharedMedicationLog` (existing).
- Produces: `EditSharedMedicationSheet(pet: SharedPet, medication: SharedMedication?)` (nil = new), used by Task 4's `SharedPetDetailView` and Task 5's `SharedPetCard`.

Mirrors `AddEditMedicationSheet` minus its entire "Notifications" section (Dose Reminder toggle, fixed-time pickers) — out of scope this phase.

- [ ] **Step 1: Implement**

Create `Did I Feed The Dog/Views/EditSharedMedicationSheet.swift`:

```swift
import CoreData
import SwiftUI

/// Mirrors AddEditMedicationSheet minus its Notifications section (Dose Reminder, fixed-time
/// pickers) — notifications for shared dogs are out of scope this phase. nil medication = new.
struct EditSharedMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet
    var medication: SharedMedication?

    @State private var name = ""
    @State private var dose = ""
    @State private var frequencyHours = 24
    @State private var showDeleteConfirm = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private let frequencyOptions = [8, 12, 24, 48, 72, 168, 720]

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name (e.g. Heartgard, Prednisone)", text: $name)
                    TextField("Dose — optional (e.g. 25mg, 1 tablet)", text: $dose)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequencyHours) {
                        ForEach(frequencyOptions, id: \.self) { hours in
                            Text(frequencyLabel(hours)).tag(hours)
                        }
                    }
                }

                if medication != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Medication", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(medication == nil ? "Add Medication" : "Edit Medication")
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
            .onAppear { prefill() }
            .confirmationDialog(
                "Delete \(medication?.name ?? "Medication")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("This will also remove all log history for this medication.")
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        guard let med = medication else { return }
        name = med.name
        dose = med.dose
        frequencyHours = Int(med.frequencyHours)
    }

    private func frequencyLabel(_ hours: Int) -> String {
        switch hours {
        case 8:   return "3 times daily"
        case 12:  return "Twice daily"
        case 24:  return "Daily"
        case 48:  return "Every 2 days"
        case 72:  return "Every 3 days"
        case 168: return "Weekly"
        case 720: return "Monthly"
        default:  return "Every \(hours)h"
        }
    }

    private func save() {
        guard let context = pet.managedObjectContext else {
            saveErrorMessage = "Failed to save: no context"
            showSaveError = true
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDose = dose.trimmingCharacters(in: .whitespaces)

        if let med = medication {
            med.name = trimmedName
            med.dose = trimmedDose
            med.frequencyHours = Int64(frequencyHours)
        } else {
            let newMed = SharedMedication(context: context)
            newMed.id = UUID()
            newMed.name = trimmedName
            newMed.dose = trimmedDose
            newMed.frequencyHours = Int64(frequencyHours)
            newMed.notificationsEnabled = false
            newMed.reminderMinutesRaw = ""
            newMed.ckRecordName = UUID().uuidString
            newMed.pet = pet
        }

        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save: \(error.localizedDescription)"
            showSaveError = true
        }
    }

    private func delete() {
        guard let med = medication, let context = pet.managedObjectContext else { return }
        for log in (med.logs as? Set<SharedMedicationLog>) ?? [] { log.medication = nil }
        context.delete(med)
        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to delete: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
```

No dedicated unit test — direct field assignment plus the nullify-before-delete pattern, which is already covered generically by `SharedMedicationTests`/`MedicationTests` for the owned side and by the Core Data model's own `.nullifyDeleteRule` on `SharedMedication.logs` (confirmed in `SharedDataModel.swift` during spec self-review). Verified by build.

- [ ] **Step 2: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Views/EditSharedMedicationSheet.swift"
git commit -m "feat: EditSharedMedicationSheet adds/edits/deletes a shared dog's medications (#57 phase 7)"
```

---

### Task 3: `SharedPetDetailView` — meals tab

**Files:**
- Create: `Did I Feed The Dog/Views/SharedPetDetailView.swift`
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`

**Interfaces:**
- Consumes: `SharedFeedingEvent`, `SharedPet` (existing), `MealFilterSheet` (Task 1, non-private).
- Produces: `SharedPetDetailView(pet: SharedPet)` — meals-tab-only in this task; Task 4 modifies this same file to add the medications tab and the tab picker. `SharedFeedingEvent: Identifiable` conformance, needed for `.sheet(item:)` below and reused by nothing else in this plan.

- [ ] **Step 1: Add `SharedFeedingEvent: Identifiable`**

In `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`, add this new extension at the end of the file (after the `SharedMedication.frequencyLabel` extension added in Task 1):

```swift

extension SharedFeedingEvent: Identifiable {
    /// SharedFeedingEvent has no stored `id` field (unlike SharedMedication/SharedMedicationLog,
    /// which do) — objectID is stable for the object's lifetime in a context and is enough for
    /// SwiftUI's `.sheet(item:)`, which only needs identity, not a persisted business key.
    public var id: NSManagedObjectID { objectID }
}
```

- [ ] **Step 2: Create `SharedPetDetailView` with the meals tab only**

Create `Did I Feed The Dog/Views/SharedPetDetailView.swift`:

```swift
import CoreData
import SwiftUI

/// Shared-dog equivalent of PetDetailView. This task ships the meals tab only — Task 4 in this
/// same plan adds the segmented picker and the medications tab by replacing this file.
struct SharedPetDetailView: View {
    let pet: SharedPet

    @State private var editingEvent: SharedFeedingEvent?
    @State private var showFilters = false
    @State private var filterMealTypes: Set<String> = []
    @State private var filterLoggedBy: Set<String> = []
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var sortAscending = false
    @State private var isSelecting = false
    @State private var selectedEventIDs: Set<NSManagedObjectID> = []
    @State private var showDeleteConfirmation = false

    private var allEvents: [SharedFeedingEvent] {
        Array((pet.feedingEvents as? Set<SharedFeedingEvent>) ?? [])
    }

    private var availableMealTypes: [String] {
        let types = allEvents.compactMap { $0.mealType }.filter { !$0.isEmpty }
        return Array(Set(types)).sorted()
    }

    private var availableLoggers: [String] {
        let loggers = allEvents.compactMap { $0.loggedBy }.filter { !$0.isEmpty }
        return Array(Set(loggers)).sorted()
    }

    private var activeFilterCount: Int {
        (filterMealTypes.isEmpty ? 0 : 1) +
        (filterLoggedBy.isEmpty ? 0 : 1) +
        (filterStartDate != nil || filterEndDate != nil ? 1 : 0)
    }

    private var filteredGroupedEvents: [(date: Date, events: [SharedFeedingEvent])] {
        var events = allEvents
        if !filterMealTypes.isEmpty {
            events = events.filter { filterMealTypes.contains($0.mealType ?? "") }
        }
        if !filterLoggedBy.isEmpty {
            events = events.filter { filterLoggedBy.contains($0.loggedBy ?? "") }
        }
        if let start = filterStartDate {
            events = events.filter { $0.timestamp >= Calendar.current.startOfDay(for: start) }
        }
        if let end = filterEndDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            events = events.filter { $0.timestamp < endOfDay }
        }
        events.sort { sortAscending ? $0.timestamp < $1.timestamp : $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.sorted { sortAscending ? $0.key < $1.key : $0.key > $1.key }.map { (date: $0.key, events: $0.value) }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        List(selection: $selectedEventIDs) {
            mealsContent
        }
        .navigationTitle(pet.name ?? "Unknown")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button("Cancel") {
                        isSelecting = false
                        selectedEventIDs = []
                    }
                } else {
                    Button("Select") {
                        isSelecting = true
                    }
                    .disabled(allEvents.isEmpty)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: activeFilterCount > 0
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(activeFilterCount > 0 ? Color.accentColor : .primary)
                }
                .accessibilityLabel(activeFilterCount > 0 ? "Filters active — \(activeFilterCount)" : "Filter meals")
            }
        }
        .sheet(item: $editingEvent) { event in
            EditSharedEventSheet(event: event)
        }
        .sheet(isPresented: $showFilters) {
            MealFilterSheet(
                filterMealTypes: $filterMealTypes,
                filterLoggedBy: $filterLoggedBy,
                filterStartDate: $filterStartDate,
                filterEndDate: $filterEndDate,
                sortAscending: $sortAscending,
                availableMealTypes: availableMealTypes,
                availableLoggers: availableLoggers
            )
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedEventIDs.isEmpty {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete \(selectedEventIDs.count) Meal\(selectedEventIDs.count == 1 ? "" : "s")", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
                .background(.bar)
            }
        }
        .confirmationDialog(
            "Delete \(selectedEventIDs.count) Meal\(selectedEventIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedEventIDs() }
        }
    }

    @ViewBuilder
    private var mealsContent: some View {
        let groups = filteredGroupedEvents
        let hasAnyEvents = !allEvents.isEmpty
        if groups.isEmpty && !hasAnyEvents {
            ContentUnavailableView(
                "No Meals Yet",
                systemImage: "fork.knife",
                description: Text("Tap Log Meal on \(pet.name ?? "Unknown")'s card to get started.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else if groups.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No meals match the current filters.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else {
            ForEach(groups, id: \.date) { group in
                Section(header: Text(sectionTitle(for: group.date))) {
                    ForEach(group.events, id: \.objectID) { event in
                        if isSelecting {
                            eventRow(event)
                                .accessibilityLabel("\(event.mealType ?? "Feeding"), \(Self.timeFormatter.string(from: event.timestamp))\((event.loggedBy ?? "").isEmpty ? "" : ", by \(event.loggedBy!)")")
                        } else {
                            Button { editingEvent = event } label: {
                                eventRow(event)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(event.mealType ?? "Feeding"), \(Self.timeFormatter.string(from: event.timestamp))\((event.loggedBy ?? "").isEmpty ? "" : ", by \(event.loggedBy!)")")
                            .accessibilityHint("Double tap to edit note")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteEvent(event)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingEvent = event
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: SharedFeedingEvent) -> some View {
        HStack(spacing: 12) {
            Text(MealType.emoji(for: event.mealType ?? ""))
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.mealType ?? "Feeding")
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: event.timestamp))
                    if let by = event.loggedBy, !by.isEmpty {
                        Text("·")
                        Text("by \(by)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: .now))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date)     { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.sectionDateFormatter.string(from: date)
    }

    private func deleteEvent(_ event: SharedFeedingEvent) {
        guard let context = pet.managedObjectContext else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        context.delete(event)
        try? context.save()
    }

    private func deleteSelectedEventIDs() {
        guard let context = pet.managedObjectContext else { return }
        let toDelete = allEvents.filter { selectedEventIDs.contains($0.objectID) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for event in toDelete { context.delete(event) }
        try? context.save()
        selectedEventIDs = []
        isSelecting = false
    }
}

private struct EditSharedEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: SharedFeedingEvent

    @State private var noteText = ""
    @State private var mealType: MealType = .custom("")
    @State private var customMealText = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Type") {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.presets, id: \.label) { type in
                            Text(type.label).tag(type)
                        }
                        Text("Custom").tag(MealType.custom(customMealText))
                    }
                    .pickerStyle(.menu)

                    if case .custom = mealType {
                        TextField("Custom Meal Name", text: $customMealText)
                            .onChange(of: customMealText) { _, newText in
                                mealType = .custom(newText)
                            }
                    }
                }

                Section("Notes") {
                    TextField("Add a note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Feeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                noteText = event.notes
                let currentLabel = event.mealType ?? "Feeding"
                let matchedPreset = MealType.presets.first { $0.label == currentLabel }
                if let preset = matchedPreset {
                    mealType = preset
                } else {
                    customMealText = currentLabel
                    mealType = .custom(currentLabel)
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let context = event.managedObjectContext else {
            saveErrorMessage = "Failed to save: no context"
            showSaveError = true
            return
        }
        let newLabel = mealType.label.trimmingCharacters(in: .whitespacesAndNewlines)
        event.mealType = newLabel.isEmpty ? "Feeding" : newLabel
        event.notes = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
```

No dedicated unit test for the filter/group/delete logic in this task — `PetDetailView`'s equivalent owned-dog logic has never had dedicated tests either (confirmed absent from the existing test target); this task mirrors that existing convention rather than introducing test coverage asymmetric with the owned side. Verified by build; the manual checklist at the end of this plan exercises it end-to-end.

- [ ] **Step 3: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The Dog/Views/SharedPetDetailView.swift"
git commit -m "feat: SharedPetDetailView meals tab — view/filter/edit/delete shared-dog feedings (#57 phase 7)"
```

---

### Task 4: `SharedPetDetailView` — medications tab

**Files:**
- Modify: `Did I Feed The Dog/Views/SharedPetDetailView.swift` (full replacement)
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`

**Interfaces:**
- Consumes: `EditSharedMedicationSheet(pet:medication:)` (Task 2), `SharedMedication.frequencyLabel` (Task 1), `SharedMedicationLog` (existing).
- Produces: `SharedPetDetailView`'s final, complete two-tab form — consumed by Task 5's `DashboardView` navigation destination.

- [ ] **Step 1: Add `SharedMedication: Identifiable`**

In `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`, add this at the end of the file (after `SharedFeedingEvent: Identifiable` from Task 3):

```swift

extension SharedMedication: Identifiable {}
```

`SharedMedication` already has a stored `@NSManaged var id: UUID`, so this conformance needs no extra code — it's needed for `.sheet(item: $editingMedication)` below.

- [ ] **Step 2: Replace `SharedPetDetailView.swift` with the two-tab version**

Read the file Task 3 created first to confirm it's in the expected meals-only state (no `HistoryTab`, no `selectedTab`). Replace the entire file with:

```swift
import CoreData
import SwiftUI

/// Shared-dog equivalent of PetDetailView: meals tab (filter/sort/bulk-select/swipe edit-delete)
/// and medications tab (add/edit/delete medications, dose-log history with delete). Deleting a
/// stock-deducting feeding event needs no "restore portions" branch — effectiveFoodStockCount is
/// derived from feedingEvents, so removing the event alone restores the count.
struct SharedPetDetailView: View {
    let pet: SharedPet

    @State private var selectedTab: HistoryTab = .meals
    @State private var editingEvent: SharedFeedingEvent?
    @State private var showAddMedication = false
    @State private var editingMedication: SharedMedication?
    @State private var pendingDeleteMedId: UUID?
    @State private var deleteTask: Task<Void, Never>?
    @State private var showMedDeleteToast = false
    @State private var medDeleteToastName = ""
    @State private var showFilters = false
    @State private var filterMealTypes: Set<String> = []
    @State private var filterLoggedBy: Set<String> = []
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var sortAscending = false
    @State private var isSelecting = false
    @State private var selectedEventIDs: Set<NSManagedObjectID> = []
    @State private var showDeleteConfirmation = false

    private enum HistoryTab { case meals, medications }

    // MARK: - Feeding

    private var allEvents: [SharedFeedingEvent] {
        Array((pet.feedingEvents as? Set<SharedFeedingEvent>) ?? [])
    }

    private var availableMealTypes: [String] {
        let types = allEvents.compactMap { $0.mealType }.filter { !$0.isEmpty }
        return Array(Set(types)).sorted()
    }

    private var availableLoggers: [String] {
        let loggers = allEvents.compactMap { $0.loggedBy }.filter { !$0.isEmpty }
        return Array(Set(loggers)).sorted()
    }

    private var activeFilterCount: Int {
        (filterMealTypes.isEmpty ? 0 : 1) +
        (filterLoggedBy.isEmpty ? 0 : 1) +
        (filterStartDate != nil || filterEndDate != nil ? 1 : 0)
    }

    private var filteredGroupedEvents: [(date: Date, events: [SharedFeedingEvent])] {
        var events = allEvents
        if !filterMealTypes.isEmpty {
            events = events.filter { filterMealTypes.contains($0.mealType ?? "") }
        }
        if !filterLoggedBy.isEmpty {
            events = events.filter { filterLoggedBy.contains($0.loggedBy ?? "") }
        }
        if let start = filterStartDate {
            events = events.filter { $0.timestamp >= Calendar.current.startOfDay(for: start) }
        }
        if let end = filterEndDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            events = events.filter { $0.timestamp < endOfDay }
        }
        events.sort { sortAscending ? $0.timestamp < $1.timestamp : $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.sorted { sortAscending ? $0.key < $1.key : $0.key > $1.key }.map { (date: $0.key, events: $0.value) }
    }

    // MARK: - Medications & logs

    private var medications: [SharedMedication] {
        Array((pet.medications as? Set<SharedMedication>) ?? [])
    }

    private var allMedLogs: [(date: Date, logs: [SharedMedicationLog])] {
        guard let context = pet.managedObjectContext else { return [] }
        let petId = pet.id
        let req = NSFetchRequest<SharedMedicationLog>(entityName: "SharedMedicationLog")
        req.predicate = NSPredicate(format: "petId == %@", petId as CVarArg)
        let logs = ((try? context.fetch(req)) ?? []).sorted { $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: logs) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, logs: $0.value) }
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    // MARK: - Body

    var body: some View {
        List(selection: $selectedEventIDs) {
            if selectedTab == .meals {
                mealsContent
            } else {
                medicationsContent
            }
        }
        .navigationTitle(pet.name ?? "Unknown")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("History", selection: $selectedTab) {
                Text("Meals").tag(HistoryTab.meals)
                Text("Medications").tag(HistoryTab.medications)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedTab == .meals {
                    if isSelecting {
                        Button("Cancel") {
                            isSelecting = false
                            selectedEventIDs = []
                        }
                    } else {
                        Button("Select") {
                            isSelecting = true
                        }
                        .disabled(allEvents.isEmpty)
                    }
                } else {
                    Button { showAddMedication = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selectedTab == .meals {
                    Button { showFilters = true } label: {
                        Image(systemName: activeFilterCount > 0
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(activeFilterCount > 0 ? Color.accentColor : .primary)
                    }
                    .accessibilityLabel(activeFilterCount > 0 ? "Filters active — \(activeFilterCount)" : "Filter meals")
                }
            }
        }
        .sheet(item: $editingEvent) { event in
            EditSharedEventSheet(event: event)
        }
        .sheet(isPresented: $showAddMedication) {
            EditSharedMedicationSheet(pet: pet, medication: nil)
        }
        .sheet(item: $editingMedication) { med in
            EditSharedMedicationSheet(pet: pet, medication: med)
        }
        .sheet(isPresented: $showFilters) {
            MealFilterSheet(
                filterMealTypes: $filterMealTypes,
                filterLoggedBy: $filterLoggedBy,
                filterStartDate: $filterStartDate,
                filterEndDate: $filterEndDate,
                sortAscending: $sortAscending,
                availableMealTypes: availableMealTypes,
                availableLoggers: availableLoggers
            )
        }
        .environment(\.editMode, .constant(selectedTab == .meals && isSelecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selectedEventIDs.isEmpty {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete \(selectedEventIDs.count) Meal\(selectedEventIDs.count == 1 ? "" : "s")", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
                .background(.bar)
            }
        }
        .confirmationDialog(
            "Delete \(selectedEventIDs.count) Meal\(selectedEventIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedEventIDs() }
        }
        .overlay(alignment: .bottom) {
            if showMedDeleteToast {
                UndoToast(
                    message: "Medication \"\(medDeleteToastName)\" will be deleted",
                    tint: .purple,
                    systemImage: "pill.fill"
                ) {
                    deleteTask?.cancel()
                    pendingDeleteMedId = nil
                    showMedDeleteToast = false
                } onDismiss: {
                    showMedDeleteToast = false
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showMedDeleteToast)
        .onChange(of: selectedTab) { _, _ in
            isSelecting = false
            selectedEventIDs = []
        }
    }

    // MARK: - Meals tab

    @ViewBuilder
    private var mealsContent: some View {
        let groups = filteredGroupedEvents
        let hasAnyEvents = !allEvents.isEmpty
        if groups.isEmpty && !hasAnyEvents {
            ContentUnavailableView(
                "No Meals Yet",
                systemImage: "fork.knife",
                description: Text("Tap Log Meal on \(pet.name ?? "Unknown")'s card to get started.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else if groups.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No meals match the current filters.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else {
            ForEach(groups, id: \.date) { group in
                Section(header: Text(sectionTitle(for: group.date))) {
                    ForEach(group.events, id: \.objectID) { event in
                        if isSelecting {
                            eventRow(event)
                                .accessibilityLabel("\(event.mealType ?? "Feeding"), \(Self.timeFormatter.string(from: event.timestamp))\((event.loggedBy ?? "").isEmpty ? "" : ", by \(event.loggedBy!)")")
                        } else {
                            Button { editingEvent = event } label: {
                                eventRow(event)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(event.mealType ?? "Feeding"), \(Self.timeFormatter.string(from: event.timestamp))\((event.loggedBy ?? "").isEmpty ? "" : ", by \(event.loggedBy!)")")
                            .accessibilityHint("Double tap to edit note")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteEvent(event)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingEvent = event
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Medications tab

    @ViewBuilder
    private var medicationsContent: some View {
        let visibleMedications = medications.filter { $0.id != pendingDeleteMedId }

        Section("Medications") {
            ForEach(visibleMedications, id: \.objectID) { med in
                Button { editingMedication = med } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name)
                                .foregroundStyle(.primary)
                            Text(med.dose.isEmpty ? med.frequencyLabel : "\(med.dose) · \(med.frequencyLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        scheduleMedicationDelete(med)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button { showAddMedication = true } label: {
                Label("Add Medication", systemImage: "plus.circle.fill")
            }
        }

        ForEach(allMedLogs, id: \.date) { group in
            Section(header: Text(sectionTitle(for: group.date))) {
                ForEach(group.logs, id: \.objectID) { log in
                    medLogRow(log)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteMedLog(log)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func scheduleMedicationDelete(_ med: SharedMedication) {
        deleteTask?.cancel()
        pendingDeleteMedId = med.id
        medDeleteToastName = med.name
        showMedDeleteToast = true
        deleteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(AppConstants.undoToastSeconds))
            guard !Task.isCancelled else { return }
            if let context = med.managedObjectContext {
                for log in (med.logs as? Set<SharedMedicationLog>) ?? [] { log.medication = nil }
                context.delete(med)
                try? context.save()
            }
            pendingDeleteMedId = nil
            showMedDeleteToast = false
        }
    }

    // MARK: - Row views

    private func eventRow(_ event: SharedFeedingEvent) -> some View {
        HStack(spacing: 12) {
            Text(MealType.emoji(for: event.mealType ?? ""))
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.mealType ?? "Feeding")
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: event.timestamp))
                    if let by = event.loggedBy, !by.isEmpty {
                        Text("·")
                        Text("by \(by)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: .now))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func medLogRow(_ log: SharedMedicationLog) -> some View {
        HStack(spacing: 12) {
            Text("💊")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(log.medication?.name ?? (log.medicationName.isEmpty ? "Medication" : log.medicationName))
                        .font(.subheadline).fontWeight(.medium)
                    if let dose = log.medication?.dose, !dose.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(dose)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: log.timestamp))
                    if !log.loggedBy.isEmpty {
                        Text("·")
                        Text("by \(log.loggedBy)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !log.notes.isEmpty {
                    Text(log.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            Text(Self.relativeFormatter.localizedString(for: log.timestamp, relativeTo: .now))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date)     { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.sectionDateFormatter.string(from: date)
    }

    private func deleteEvent(_ event: SharedFeedingEvent) {
        guard let context = pet.managedObjectContext else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        context.delete(event)
        try? context.save()
    }

    private func deleteSelectedEventIDs() {
        guard let context = pet.managedObjectContext else { return }
        let toDelete = allEvents.filter { selectedEventIDs.contains($0.objectID) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for event in toDelete { context.delete(event) }
        try? context.save()
        selectedEventIDs = []
        isSelecting = false
    }

    private func deleteMedLog(_ log: SharedMedicationLog) {
        guard let context = pet.managedObjectContext else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let med = log.medication {
            let remaining = ((med.logs as? Set<SharedMedicationLog>) ?? []).filter { $0.id != log.id }.sorted { $0.timestamp > $1.timestamp }
            med.lastGivenDate = remaining.first?.timestamp
        }
        context.delete(log)
        try? context.save()
    }
}

private struct EditSharedEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: SharedFeedingEvent

    @State private var noteText = ""
    @State private var mealType: MealType = .custom("")
    @State private var customMealText = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Type") {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.presets, id: \.label) { type in
                            Text(type.label).tag(type)
                        }
                        Text("Custom").tag(MealType.custom(customMealText))
                    }
                    .pickerStyle(.menu)

                    if case .custom = mealType {
                        TextField("Custom Meal Name", text: $customMealText)
                            .onChange(of: customMealText) { _, newText in
                                mealType = .custom(newText)
                            }
                    }
                }

                Section("Notes") {
                    TextField("Add a note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Feeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                noteText = event.notes
                let currentLabel = event.mealType ?? "Feeding"
                let matchedPreset = MealType.presets.first { $0.label == currentLabel }
                if let preset = matchedPreset {
                    mealType = preset
                } else {
                    customMealText = currentLabel
                    mealType = .custom(currentLabel)
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let context = event.managedObjectContext else {
            saveErrorMessage = "Failed to save: no context"
            showSaveError = true
            return
        }
        let newLabel = mealType.label.trimmingCharacters(in: .whitespacesAndNewlines)
        event.mealType = newLabel.isEmpty ? "Feeding" : newLabel
        event.notes = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
```

No dedicated unit test, for the same reason as Task 3 — `PetDetailView`'s equivalent medication-tab logic has no dedicated tests either. Verified by build; exercised end-to-end by the manual checklist.

- [ ] **Step 3: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedManagedObjects.swift" "Did I Feed The Dog/Views/SharedPetDetailView.swift"
git commit -m "feat: SharedPetDetailView medications tab — add/edit/delete meds and dose logs (#57 phase 7)"
```

---

### Task 5: Wire navigation, Edit Dog, and fasting toggle

**Files:**
- Modify: `Did I Feed The Dog/Views/SharedPetCard.swift` (full replacement)
- Modify: `Did I Feed The Dog/Views/DashboardView.swift`
- Modify: `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`

**Interfaces:**
- Consumes: `SharedPetDetailView(pet:)` (Tasks 3–4), `EditSharedPetSheet(pet:)` (Task 1).
- Produces: nothing consumed by later tasks (final task in this plan).

`NavigationLink(value: pet)` and `navigationDestination(for: SharedPet.self)` both require `SharedPet: Hashable` — unlike `Pet` (a SwiftData `@Model`, which gets `Hashable` synthesized by the macro), `SharedPet` is a plain `NSManagedObject` subclass and needs this declared explicitly.

- [ ] **Step 1: Add `SharedPet: Hashable`**

In `Did I Feed The Dog/Sharing/SharedManagedObjects.swift`, add this at the end of the file (after `SharedMedication: Identifiable` from Task 4):

```swift

extension SharedPet: Hashable {
    public static func == (lhs: SharedPet, rhs: SharedPet) -> Bool { lhs.objectID == rhs.objectID }
    public func hash(into hasher: inout Hasher) { hasher.combine(objectID) }
}
```

- [ ] **Step 2: Replace `SharedPetCard.swift`**

Read the current file first to confirm it matches the state left by the same-day visual-parity commit (header/statsRow/miniHistory as plain views, no `NavigationLink`; context menu with only Update Food Stock + owner-gated Share/Stop-sharing). Replace the entire file with:

```swift
import CloudKit
import CoreData
import SwiftData
import SwiftUI

/// Dashboard card for a dog shared with the user. Mirrors PetCard's layout (photo, Last Fed
/// badge, Low Food Stock / due-medication banners, stats, recent history, fasting banner) so a
/// dog looks the same before and after sharing. Logging, restocking, editing, the fasting
/// toggle, and history navigation are all available to any participant regardless of their own
/// Pro status — only the owner needed Pro to create the share in the first place. Only "Share
/// this dog"/"Stop sharing" stay owner-gated.
struct SharedPetCard: View {
    @AppStorage("lowStockUIWarning", store: .sharedGroup) private var lowStockUIWarning = true
    @AppStorage("lowStockThreshold", store: .sharedGroup) private var lowStockThreshold = 5
    @AppStorage("reminderMode", store: .sharedGroup)      private var reminderMode: ReminderMode = .none

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
    @State private var showEditSheet = false

    private var sharedPet: SharedPet? { dog as? SharedPet }

    private var isOwner: Bool {
        guard SharingFeatureFlag.isFoundationEnabled, let pet = sharedPet else { return false }
        let zoneName = CKRecordMapper.zoneID(forRoot: pet).zoneName
        return SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName)
    }

    private var medications: [SharedMedication] {
        Array((sharedPet?.medications as? Set<SharedMedication>) ?? [])
    }

    private var dueMedications: [SharedMedication] {
        medications.filter(\.isDue)
    }

    private var hasDueMedications: Bool { !dueMedications.isEmpty }

    private var medicationBannerTitle: String {
        let due = dueMedications
        if due.count == 1 { return due[0].name }
        return "\(due.count) meds due"
    }

    private var recentEvents: [SharedFeedingEvent] {
        let events = (sharedPet?.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        return Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(3))
    }

    private var currentStockCount: Int {
        sharedPet?.effectiveFoodStockCount ?? 0
    }

    private var isLowStock: Bool {
        guard lowStockUIWarning, sharedPet != nil else { return false }
        return currentStockCount <= lowStockThreshold
    }

    private var lastFedBadgeColor: Color {
        dog.isFeedingOverdue ? Color(.systemRed).opacity(0.15) : Color(.systemGreen).opacity(0.15)
    }

    private var lastFedTextColor: Color {
        dog.isFeedingOverdue ? .red : .green
    }

    private var lastFedLabel: String {
        guard let lastDate = dog.lastFeedingDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastDate, relativeTo: .now)
    }

    private var nextMealInfo: (value: String, unit: String)? {
        guard reminderMode == .perDog else { return nil }
        return nextMealLabel(from: dog.feedingScheduleTimes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pet = sharedPet {
                NavigationLink(value: pet) { headerRow }
                    .buttonStyle(.plain)
            } else {
                headerRow
            }

            if isLowStock || hasDueMedications {
                VStack(spacing: 6) {
                    if isLowStock {
                        Button { showRestockSheet = true } label: { lowStockBanner }
                            .buttonStyle(.plain)
                    }
                    if hasDueMedications {
                        Button { showLogMedication = true } label: { medicationBanner }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            statsRow

            if !recentEvents.isEmpty {
                if let pet = sharedPet {
                    NavigationLink(value: pet) { miniHistory }
                        .buttonStyle(.plain)
                } else {
                    miniHistory
                }
            }

            if dog.isFasting {
                HStack {
                    Image(systemName: "exclamationmark.octagon.fill")
                    Text("DO NOT FEED — FASTING")
                        .font(.caption).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if SharingFeatureFlag.isFoundationEnabled, sharedPet != nil {
                actionButtons
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        .contextMenu {
            if let pet = sharedPet {
                Button {
                    pet.isFasting.toggle()
                    try? pet.managedObjectContext?.save()
                } label: {
                    Label(pet.isFasting ? "End Fasting" : "Start Fasting",
                          systemImage: pet.isFasting ? "fork.knife" : "exclamationmark.octagon")
                }
                Button {
                    showEditSheet = true
                } label: {
                    Label("Edit Dog", systemImage: "pencil")
                }
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
        .sheet(isPresented: $showEditSheet) {
            if let pet = sharedPet {
                EditSharedPetSheet(pet: pet)
            }
        }
        .alert("Couldn't share this dog", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(dog.displayName)
                        .font(.title3).fontWeight(.bold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "person.2.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Shared dog")
                }
                let age = dog.ageString
                if !age.isEmpty {
                    Text(age)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            lastFedBadge
        }
        .padding(16)
    }

    private var avatar: some View {
        Group {
            if let data = dog.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: dog.id))
                    .resizable().scaledToFill()
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .accessibilityHidden(true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dog.isFeedingOverdue
            ? "Last fed \(lastFedLabel), overdue"
            : "Last fed \(lastFedLabel)")
    }

    private var lowStockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Low Food Stock")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                Text("Only \(currentStockCount) portion\(currentStockCount == 1 ? "" : "s") remaining · Tap to restock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var medicationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pill.fill")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(medicationBannerTitle)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.purple)
                Text("Tap to log dose")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if sharedPet != nil {
                    Button {
                        showRestockSheet = true
                    } label: {
                        statCell(
                            title: "Food Stock",
                            value: "\(currentStockCount)",
                            unit: "portions",
                            accent: isLowStock ? .red : .primary,
                            statusLabel: isLowStock ? "low stock" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to edit food stock")
                }
                statCell(
                    title: "Today's Meals",
                    value: "\(dog.todaysFeedingCount)",
                    unit: "meals",
                    accent: .primary
                )
            }
            if let info = nextMealInfo {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Next meal · \(info.value) · \(info.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func statCell(title: String, value: String, unit: String, accent: Color, statusLabel: String? = nil) -> some View {
        let label = statusLabel.map { "\(title): \(value) \(unit), \($0)" } ?? "\(title): \(value) \(unit)"
        return VStack(alignment: .leading, spacing: 4) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var miniHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            ForEach(recentEvents, id: \.objectID) { event in
                HStack {
                    Text(MealType.emoji(for: event.mealType ?? "") + " " + (event.mealType ?? "Feeding"))
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(abbreviatedRelative(event.timestamp))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var actionButtons: some View {
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
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func abbreviatedRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
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

- [ ] **Step 3: Add the navigation destination in `DashboardView`**

In `Did I Feed The Dog/Views/DashboardView.swift`, find:
```swift
            .navigationDestination(for: Pet.self) { pet in PetDetailView(pet: pet) }
```
and change it to:
```swift
            .navigationDestination(for: Pet.self) { pet in PetDetailView(pet: pet) }
            .navigationDestination(for: SharedPet.self) { pet in SharedPetDetailView(pet: pet) }
```

- [ ] **Step 4: Build to verify it compiles**

Run the build command from Environment / mechanics. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full existing suite for regressions**

```
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 2>&1 | tail -80
```

Expected: no new failures beyond the known-flaky baseline (see Environment / mechanics).

- [ ] **Step 6: Commit**

```bash
git add "Did I Feed The Dog/Views/SharedPetCard.swift" "Did I Feed The Dog/Views/DashboardView.swift" "Did I Feed The Dog/Sharing/SharedManagedObjects.swift"
git commit -m "feat: wire history navigation, Edit Dog, and fasting toggle on SharedPetCard (#57 phase 7)"
```

---

## Manual validation (not automatable — real devices, two accounts, flag on)

After all 5 tasks are merged, per the spec's Testing section:

1. Tap into a shared dog's history from both the Last Fed badge/header and the Recent-history
   rows on both devices — same destination (`SharedPetDetailView`), same content.
2. From a non-owner, non-Pro participant device: edit the dog's name/photo/fasting/food-stock →
   change appears on the owner's device after sync. Toggle fasting via the quick context-menu
   action too — same result.
3. Add a medication from the participant device → appears and is loggable from the owner's
   device. Edit it, then delete it from either device → disappears from both; dose-log history
   for it survives (still visible, un-attributed to a medication object) in the medications tab.
4. Delete a feeding event that deducted stock (either the meals-tab swipe action or a bulk-select
   delete) → `effectiveFoodStockCount` on that device reflects the restored portion immediately,
   with no separate "restore" action taken.
5. Filter meal history by meal type / logger / date range; sort ascending/descending; confirm
   results match; clear filters.
6. Flag off: no "Edit Dog"/fasting-toggle/navigation entry points appear on any `SharedPetCard`
   (shared dogs themselves don't render without the flag, unaffected by this phase).
