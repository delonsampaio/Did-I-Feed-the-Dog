import SwiftUI
import SwiftData
import WidgetKit

struct PetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let pet: Pet

    @AppStorage("stockMode")       private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock") private var sharedFoodStock = 0

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
                                if stockMode != .none && eventDecrementsStock(event) {
                                    Button {
                                        deleteEvent(event, restoreStock: true)
                                    } label: {
                                        Label("Delete & Restore Portion", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
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
            EditNoteSheet(event: event)
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

    private func eventDecrementsStock(_ event: FeedingEvent) -> Bool {
        event.resolvedMealType.decrementsStock
    }

    private func deleteEvent(_ event: FeedingEvent, restoreStock: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if restoreStock {
            switch stockMode {
            case .individual: pet.foodStockCount += 1
            case .shared:     sharedFoodStock += 1
            case .none:       break
            }
        }
        modelContext.delete(event)
        WidgetDataWriter.write(from: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteEvents(_ events: [FeedingEvent], at offsets: IndexSet) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for index in offsets {
            modelContext.delete(events[index])
        }
        WidgetDataWriter.write(from: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
    }


}

private struct EditNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: FeedingEvent

    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.mealType ?? "Feeding")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal)
                TextField("Note (optional)", text: $noteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        event.notes = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear { noteText = event.notes }
        }
        .presentationDetents([.medium])
    }
}
