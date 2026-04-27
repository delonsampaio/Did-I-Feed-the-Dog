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
