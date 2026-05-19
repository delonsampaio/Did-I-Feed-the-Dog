import AppIntents
import SwiftData

struct FoodStockStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Food Stock Status"
    static var description = IntentDescription("Check how many portions a dog has remaining.")

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog's food stock would you like to check?"))
    var pet: PetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check food stock for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard EntitlementManager.shared.isPro else {
            return .result(dialog: "This feature requires Did I Feed the Dog Pro. Open the app to upgrade.")
        }
        switch AppSettings.stockMode {
        case .none:
            return .result(dialog: "Food stock tracking is turned off in the app.")

        case .shared:
            let count = AppSettings.sharedFoodStock
            if count == 0 {
                return .result(dialog: "The shared food pool is out of food — time to open a new bag!")
            }
            let portionWord = count == 1 ? "portion" : "portions"
            return .result(dialog: "The shared food pool has \(count) \(portionWord) remaining.")

        case .individual:
            // Use background context to avoid blocking Siri UI thread
            let context = ModelContext(sharedModelContainer)
            guard let foundPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
                return .result(dialog: "Couldn't find \(pet.name).")
            }
            let count = foundPet.foodStockCount
            if count == 0 {
                return .result(dialog: "\(pet.name) is out of food — time to open a new bag!")
            }
            let portionWord = count == 1 ? "portion" : "portions"
            return .result(dialog: "\(pet.name) has \(count) \(portionWord) remaining.")
        }
    }
}
