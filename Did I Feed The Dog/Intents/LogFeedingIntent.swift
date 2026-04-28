import AppIntents
import SwiftData
import WidgetKit

struct LogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Meal"
    static var description = IntentDescription("Log a meal for your dog")

    @Parameter(title: "Dog")
    var pet: PetEntity

    @Parameter(title: "Meal", default: .morning)
    var meal: MealTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$meal) feeding for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = IntentDataAccess.makeContext() else {
            return .result(dialog: "Could not access app data.")
        }
        let pets = IntentDataAccess.fetchPets(in: context)
        guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Could not find \(pet.name).")
        }

        let event = FeedingEvent(mealType: meal.label, pet: foundPet)
        context.insert(event)

        let stockModeRaw = UserDefaults.standard.string(forKey: "stockMode") ?? ""
        let stockMode = StockMode(rawValue: stockModeRaw) ?? .none
        switch stockMode {
        case .individual:
            foundPet.decrementStock()
        case .shared:
            let current = UserDefaults.standard.integer(forKey: "sharedFoodStock")
            UserDefaults.standard.set(max(0, current - 1), forKey: "sharedFoodStock")
        case .none:
            break
        }

        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "\(meal.label) feeding logged for \(pet.name).")
    }
}
