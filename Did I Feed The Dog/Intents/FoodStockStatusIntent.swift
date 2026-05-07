import AppIntents
import SwiftData

struct FoodStockStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Food Stock Status"
    static var description = IntentDescription("Check how many portions a dog has remaining.")

    @Parameter(
        title: "Dog",
        requestValueDialog: IntentDialog(printed: "Which dog's food stock would you like to check?", spoken: "Which dog's food stock would you like to check?")
    )
    var pet: PetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check food stock for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch AppSettings.stockMode {
        case .none:
            return .result(dialog: IntentDialog(printed: "Food stock tracking is turned off in the app.", spoken: "Food stock tracking is turned off in the app."))

        case .shared:
            let count = AppSettings.sharedFoodStock
            let portionWord = count == 1 ? "portion" : "portions"
            return .result(dialog: IntentDialog(printed: "The shared food pool has \(count) \(portionWord) remaining.", spoken: "The shared food pool has \(count) \(portionWord) remaining."))

        case .individual:
            let context = sharedModelContainer.mainContext
            guard let foundPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
                return .result(dialog: IntentDialog(printed: "Couldn't find \(pet.name).", spoken: "Couldn't find \(pet.name)."))
            }
            let count = foundPet.foodStockCount
            let portionWord = count == 1 ? "portion" : "portions"
            return .result(dialog: IntentDialog(printed: "\(pet.name) has \(count) \(portionWord) remaining.", spoken: "\(pet.name) has \(count) \(portionWord) remaining."))
        }
    }
}
