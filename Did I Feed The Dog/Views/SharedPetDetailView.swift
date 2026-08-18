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
