import SwiftUI
import SwiftData

struct PetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let pet: Pet

    @Environment(EntitlementManager.self) private var entitlements

    @AppStorage("stockMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))       private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var sharedFoodStock = 0

    @State private var editingEvent: FeedingEvent?

    private var groupedEvents: [(date: Date, events: [FeedingEvent])] {
        let sorted = (pet.feedingEvents ?? []).sorted { $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: sorted) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, events: $0.value) }
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
        List {
            if groupedEvents.isEmpty {
                ContentUnavailableView(
                    "No Meals Yet",
                    systemImage: "fork.knife",
                    description: Text("Tap Log Meal on \(pet.name ?? "Unknown")'s card to get started.")
                )
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(groupedEvents, id: \.date) { group in
                    Section(header: Text(sectionTitle(for: group.date))) {
                        ForEach(group.events) { event in
                            Button { editingEvent = event } label: {
                                eventRow(event)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(event.mealType ?? "Feeding"), \(Self.timeFormatter.string(from: event.timestamp))\((event.loggedBy ?? "").isEmpty ? "" : ", by \(event.loggedBy!)")")
                            .accessibilityHint("Double tap to edit note")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteEvent(event, restoreStock: false)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                if entitlements.isPro && stockMode != .none && event.actuallyDeductedStock {
                                    Button {
                                        deleteEvent(event, restoreStock: true)
                                    } label: {
                                        Label("Delete & Restore Portion", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                                Button {
                                    editingEvent = event
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                        .onDelete { offsets in
                            deleteEvents(group.events, at: offsets)
                        }
                    }
                }
            }
        }
        .navigationTitle(pet.name ?? "Unknown")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { EditButton() }
        .sheet(item: $editingEvent) { event in
            EditEventSheet(event: event)
        }
    }

    private func eventRow(_ event: FeedingEvent) -> some View {
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

    private func deleteEvent(_ event: FeedingEvent, restoreStock: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Only credit a portion if this event actually deducted one when it
        // was logged — guarded against double-credit on custom no-deduct meals.
        if restoreStock, event.actuallyDeductedStock {
            switch stockMode {
            case .individual:
                pet.foodStockCount = min(AppConstants.perPetStockCap, pet.foodStockCount + 1)
            case .shared:
                sharedFoodStock = min(AppConstants.sharedStockCap, sharedFoodStock + 1)
            case .none:
                break
            }
        }
        modelContext.delete(event)
        WidgetDataWriter.write(from: modelContext)
    }

    private func deleteEvents(_ events: [FeedingEvent], at offsets: IndexSet) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for index in offsets {
            modelContext.delete(events[index])
        }
        WidgetDataWriter.write(from: modelContext)
    }


}

private struct EditEventSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let event: FeedingEvent

    @State private var noteText = ""
    @State private var mealType: MealType = .custom("")
    @State private var customMealText = ""

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
                    Button("Save") {
                        let newLabel = mealType.label.trimmingCharacters(in: .whitespacesAndNewlines)
                        event.mealType = newLabel.isEmpty ? "Feeding" : newLabel
                        event.notes = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        WidgetDataWriter.write(from: modelContext)
                        dismiss()
                    }
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
        }
        .presentationDetents([.medium, .large])
    }
}
