import AppIntents
import SwiftData

struct FeedingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Feeding Status"
    static var description = IntentDescription("Check when a dog was last fed.")

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog would you like to check?"))
    var pet: PetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check feeding status for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = sharedModelContainer.mainContext
        guard let foundPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Couldn't find \(pet.name).")
        }

        if foundPet.isFasting {
            if let lastEvent = foundPet.lastFeedingEvent {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let relative = formatter.localizedString(for: lastEvent.timestamp, relativeTo: .now)
                return .result(dialog: "\(pet.name) is currently fasting. Their last meal was \(relative).")
            }
            return .result(dialog: "\(pet.name) is currently fasting.")
        }

        guard let lastEvent = foundPet.lastFeedingEvent else {
            return .result(dialog: "\(pet.name) hasn't been fed yet.")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTime = formatter.localizedString(for: lastEvent.timestamp, relativeTo: .now)
        let mealName = lastEvent.mealType ?? "a meal"

        if Calendar.current.isDateInToday(lastEvent.timestamp) {
            return .result(dialog: "Yes — \(pet.name) was fed \(relativeTime) (\(mealName)).")
        }
        if foundPet.isFeedingOverdue {
            return .result(dialog: "\(pet.name) was last fed \(relativeTime) and is overdue.")
        }
        return .result(dialog: "\(pet.name) was last fed \(relativeTime).")
    }
}
