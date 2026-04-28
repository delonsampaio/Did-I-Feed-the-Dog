import SwiftUI
import SwiftData

struct PetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let pet: Pet

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
                    "No Feedings Yet",
                    systemImage: "fork.knife",
                    description: Text("Tap Log Meal on \(pet.name ?? "Unknown")'s card to get started.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(groupedEvents, id: \.date) { group in
                    Section(header: Text(sectionTitle(for: group.date))) {
                        ForEach(group.events) { event in
                            Button { editingEvent = event } label: {
                                eventRow(event)
                            }
                            .buttonStyle(.plain)
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
            Text(emojiForMeal(event.mealType ?? ""))
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.mealType ?? "Feeding")
                    .font(.subheadline).fontWeight(.medium)
                Text(Self.timeFormatter.string(from: event.timestamp))
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

    private func deleteEvents(_ events: [FeedingEvent], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
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

private struct EditNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: FeedingEvent

    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.mealType ?? "Feeding")
                    .font(.headline)
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
