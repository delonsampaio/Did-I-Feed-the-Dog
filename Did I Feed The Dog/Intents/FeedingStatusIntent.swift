import AppIntents
import SwiftData

struct FeedingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Feeding Status"
    static var description = IntentDescription("Check when a dog was last fed")

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog would you like to check?"))
    var pet: PetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check feeding status for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = sharedModelContainer.mainContext
        let pets = IntentDataAccess.fetchPets(in: context)
        guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Could not find \(pet.name).")
        }
        guard let lastEvent = foundPet.lastFeedingEvent else {
            return .result(dialog: "\(pet.name) hasn't been fed yet.")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTime = formatter.localizedString(for: lastEvent.timestamp, relativeTo: .now)

        if Calendar.current.isDateInToday(lastEvent.timestamp) {
            return .result(dialog: "Yes — \(pet.name) was fed \(relativeTime) (\(lastEvent.mealType ?? "a meal")).")
        } else {
            return .result(dialog: "\(pet.name) was last fed \(relativeTime). They may be overdue.")
        }
    }
}
